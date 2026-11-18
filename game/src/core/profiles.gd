extends Node
## Player profiles and their progress, saved in user://profiles.json (written to a temporary file, then
## renamed, so a crash never leaves half a save). Each profile: name, avatar, opponents beaten, results per
## opponent. The ladder: the first opponent is open, beating one opens the next.

signal current_changed

var PATH := "user://profiles.json"  ## tests pass --test-profile on the command line and get their own file
const MAX_NAME := 18

var data := {"current": "", "profiles": {}}
var opponents: Array = []  ## data/opponents.json, weakest first
## Portraits taken out of the list, and the one that replaces them (9060: an unfinished drawing of the library).
const RETIRED := {"npc_9060": "npc_9026"}
var avatars: Array = []  ## the portraits a profile can take (data/avatars.json): characters of the library, "npc_<gfx>"


func _ready() -> void:
	if "--test-profile" in OS.get_cmdline_user_args():
		PATH = "user://profiles_test.json"
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var o: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/opponents.json"))
	if o is Dictionary:
		opponents = o.get("opponents", [])
	var av: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/avatars.json"))
	if av is Dictionary:
		for g in av.get("avatars", []):
			avatars.append("npc_%d" % int(g))
	if FileAccess.file_exists(PATH):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if v is Dictionary and v.get("profiles") is Dictionary:
			data = v
	# profiles made when the portraits were creatures get a character instead
	var i := 0
	for p: Dictionary in data["profiles"].values():
		var av_id := String(p.get("avatar", ""))
		if RETIRED.has(av_id):
			p["avatar"] = RETIRED[av_id]
		elif not av_id.begins_with("npc_") and not avatars.is_empty():
			p["avatar"] = avatars[i % avatars.size()]
			i += 1
	if data["profiles"].is_empty():
		create("Aventurier", default_avatar())
	elif not data["profiles"].has(data.get("current", "")):
		data["current"] = data["profiles"].keys()[0]


# --- profiles --------------------------------------------------------------------------------------------------------

func current() -> Dictionary:
	return data["profiles"].get(data["current"], {})


func current_id() -> String:
	return String(data["current"])


## Profiles sorted by creation.
func all() -> Array:
	var l: Array = data["profiles"].values()
	l.sort_custom(func(a, b): return int(a.get("created", 0)) < int(b.get("created", 0)))
	return l


func create(p_name: String, avatar: String) -> String:
	var id := "p%d" % Time.get_unix_time_from_system()
	while data["profiles"].has(id):
		id += "_"
	data["profiles"][id] = {"id": id, "name": clean_name(p_name), "avatar": avatar, "created": Time.get_unix_time_from_system(),
		"beaten": [], "results": {}, "last_side": "white"}
	data["current"] = id
	save()
	current_changed.emit()
	return id


func select(id: String) -> void:
	if data["profiles"].has(id):
		data["current"] = id
		save()
		current_changed.emit()


func update(id: String, fields: Dictionary) -> void:
	var p: Dictionary = data["profiles"].get(id, {})
	if p.is_empty():
		return
	for k in fields:
		p[k] = clean_name(fields[k]) if k == "name" else fields[k]
	save()
	current_changed.emit()


func default_avatar() -> String:
	return String(avatars[0]) if not avatars.is_empty() else "white_pawn"


## A portrait other than `taken` (the second player of a game on one screen).
func other_avatar(taken: String) -> String:
	for a in avatars:
		if a != taken and a != default_avatar():
			return a
	return default_avatar()


func remove(id: String) -> void:
	data["profiles"].erase(id)
	if data["profiles"].is_empty():
		create("Aventurier", default_avatar())
		return
	if data["current"] == id:
		data["current"] = all()[0]["id"]
	save()
	current_changed.emit()


static func clean_name(s: String) -> String:
	s = s.strip_edges().replace("\n", " ")
	if s.is_empty():
		s = "Aventurier"
	return s.substr(0, MAX_NAME)


# --- ladder ----------------------------------------------------------------------------------------------------------

func opponent(id: String) -> Dictionary:
	for o in opponents:
		if o["id"] == id:
			return o
	return {}


func index_of(id: String) -> int:
	for i in opponents.size():
		if opponents[i]["id"] == id:
			return i
	return -1


func is_beaten(id: String) -> bool:
	return id in current().get("beaten", [])


## Open: the first opponent, any beaten one, and the one right after a beaten one.
func is_unlocked(id: String) -> bool:
	var i := index_of(id)
	if i <= 0:
		return i == 0
	return is_beaten(id) or is_beaten(opponents[i - 1]["id"])


func beaten_count() -> int:
	return current().get("beaten", []).size()


## The opponent to suggest: the first open one not beaten yet, else the strongest.
func next_challenge() -> String:
	for o in opponents:
		if is_unlocked(o["id"]) and not is_beaten(o["id"]):
			return o["id"]
	return opponents[-1]["id"] if not opponents.is_empty() else ""


func record(id: String) -> Dictionary:
	return current().get("results", {}).get(id, {"w": 0, "l": 0, "d": 0})


## Stores a finished game. Returns {"unlocked": id of the opponent this win opened, or ""}.
func record_result(opp_id: String, outcome: String, side: String) -> Dictionary:
	var p := current()
	if p.is_empty():
		return {}
	var res: Dictionary = p.get("results", {})
	var r: Dictionary = res.get(opp_id, {"w": 0, "l": 0, "d": 0})
	var k: String = {"win": "w", "loss": "l", "draw": "d"}.get(outcome, "l")
	r[k] = int(r.get(k, 0)) + 1
	res[opp_id] = r
	p["results"] = res
	p["last_side"] = side
	var unlocked := ""
	if outcome == "win" and not is_beaten(opp_id):
		var b: Array = p.get("beaten", [])
		b.append(opp_id)
		p["beaten"] = b
		var i := index_of(opp_id)
		if i >= 0 and i + 1 < opponents.size():
			unlocked = opponents[i + 1]["id"]
	save()
	return {"unlocked": unlocked}


# --- game in progress -------------------------------------------------------------------------------------------------

## {"opp": opponent id ("" = two players), "side", "board", "fen" (start), "moves" (UCI), "at"} or {}.
func saved_game() -> Dictionary:
	var g: Variant = current().get("game", {})
	return g if g is Dictionary else {}


func store_game(g: Dictionary) -> void:
	var p := current()
	if p.is_empty():
		return
	g["at"] = int(Time.get_unix_time_from_system())
	p["game"] = g
	save()


func clear_game() -> void:
	var p := current()
	if p.has("game"):
		p.erase("game")
		save()


func save() -> void:
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Sauvegarde impossible : %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data, " "))
	f.close()
	var dst := ProjectSettings.globalize_path(PATH)
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), dst) != OK:
		# some systems refuse to rename over an existing file
		DirAccess.remove_absolute(dst)
		DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), dst)
