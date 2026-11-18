class_name OnlineClient
extends Node
## A game against a friend at a distance: the line to the room of the online server (tools/build/cloudflare/worker.js,
## a WebSocket). The host opens a room and gets a code to share; the guest joins it with the code. The room relays the
## moves and keeps them: when the line drops, the client comes back on its own (same token, same seat) and gets the
## game where it stands. No clock between moves.

signal room_changed(info: Dictionary)  ## {code, you, state: waiting | playing, board, opponent, moves, result, game}
signal opponent_moved(uci: String, n: int)
signal opponent_state(state: String)  ## joined | left | back
signal opponent_resigned
signal rematch_asked
signal failed(why: String)  ## not_found | full | version | bad | network
signal line_changed(up: bool)  ## the line dropped / came back

const PROTOCOL := 1
const SERVER := "wss://retro-chess.holy-c.men/api"
const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  ## the codes' letters (no I, O, 0, 1)
const CODE_LEN := 6

var code := ""
var side := ""  ## "white" | "black", given by the room
var info: Dictionary = {}  ## the last room state
var active := false  ## in a room (or trying to get into one)

var _ws: WebSocketPeer
var _token := ""
var _opened := false  ## the line was up at least once for this room: a drop is retried, not a failure
var _retry_in := -1.0
var _ping_in := 0.0
var _queue: Array[String] = []  ## messages written while the line was down
var _was_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the pause menu never cuts the line


## The server: the page's own address in the browser (local tests too), else the public one;
## `-- --online-url ws://127.0.0.1:8787/api` for a local server.
static func server_url() -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--online-url")
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	if OS.has_feature("web"):
		var origin: Variant = JavaScriptBridge.eval("location.origin")
		if origin is String and String(origin).begins_with("http"):
			return String(origin).replace("https://", "wss://").replace("http://", "ws://") + "/api"
	return SERVER


## A code as typed: upper case, anything outside the alphabet dropped (spaces, dashes), at most CODE_LEN characters.
static func clean_code(s: String) -> String:
	var out := ""
	for ch in s.to_upper():
		if ALPHABET.contains(ch):
			out += ch
	return out.substr(0, CODE_LEN)


func host(p_side: String, board: String) -> void:
	_begin("")
	_connect("/host", {"side": p_side, "board": board})


func join(p_code: String) -> void:
	_begin(clean_code(p_code))
	_connect("/room/" + code, {})


func leave() -> void:
	active = false
	code = ""
	side = ""
	info = {}
	_queue.clear()
	_retry_in = -1.0
	if _ws:
		_ws.close(1000, "bye")
	_ws = null


func send_move(uci: String, n: int) -> void:
	_send({"t": "move", "uci": uci, "n": n})


func resign() -> void:
	_send({"t": "resign"})


func report_over() -> void:
	_send({"t": "over"})


func ask_rematch() -> void:
	_send({"t": "rematch"})


func opponent_name() -> String:
	var o: Variant = info.get("opponent")
	return String((o as Dictionary).get("name", "")) if o is Dictionary else ""


# --- the line -------------------------------------------------------------------------------------------------------

func _begin(p_code: String) -> void:
	leave()
	active = true
	code = p_code
	_opened = false
	_token = "%08x%08x%08x" % [randi(), randi(), randi()]


func _connect(path: String, extra: Dictionary) -> void:
	var prof := Profiles.current()
	var q := {"v": PROTOCOL, "token": _token, "name": String(prof.get("name", "Joueur")),
		"avatar": String(prof.get("avatar", ""))}
	q.merge(extra)
	var parts := PackedStringArray()
	for k in q:
		parts.append("%s=%s" % [k, String.num_int64(q[k]) if q[k] is int else String(q[k]).uri_encode()])
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 18
	_was_open = false
	var err := _ws.connect_to_url(server_url() + path + "?" + "&".join(parts))
	if err != OK:
		_lost()


func _send(msg: Dictionary) -> void:
	var s := JSON.stringify(msg)
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(s)
	elif active:
		_queue.append(s)


func _process(delta: float) -> void:
	if not active:
		return
	if _retry_in >= 0.0:
		_retry_in -= delta
		if _retry_in < 0.0 and code != "":
			_connect("/room/" + code, {})  # same token: the room gives the seat back
		return
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				if _opened:
					line_changed.emit(true)
				_opened = true
				for s in _queue:
					_ws.send_text(s)
				_queue.clear()
			while _ws.get_available_packet_count() > 0:
				var data: Variant = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
				if data is Dictionary:
					_on_message(data)
			_ping_in -= delta
			if _ping_in <= 0.0:
				_ping_in = 25.0  # keeps the line up through proxies that close quiet connections
				_ws.send_text("{\"t\":\"ping\"}")
		WebSocketPeer.STATE_CLOSED:
			_lost()


func _lost() -> void:
	_ws = null
	if not active:
		return
	if not _opened or code == "":
		active = false
		failed.emit("network")
		return
	if _was_open:
		line_changed.emit(false)
	_was_open = false
	_retry_in = 2.0


func _on_message(m: Dictionary) -> void:
	match String(m.get("t", "")):
		"room":
			info = m
			code = String(m.get("code", code))
			side = String(m.get("you", side))
			room_changed.emit(m)
		"move":
			opponent_moved.emit(String(m.get("uci", "")), int(m.get("n", -1)))
		"opponent":
			opponent_state.emit(String(m.get("state", "")))
		"resign":
			opponent_resigned.emit()
		"rematch_ask":
			rematch_asked.emit()
		"error":
			var why := String(m.get("why", "bad"))
			active = false
			_ws = null
			failed.emit(why)
