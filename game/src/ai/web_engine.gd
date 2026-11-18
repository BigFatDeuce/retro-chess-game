class_name WebEngine
extends RefCounted
## The engine in the browser version: the same Stockfish 11 compiled to WebAssembly, running in a Web Worker
## (stockfish_worker.js + stockfish.js + stockfish.wasm, next to index.html). Same calls as the native
## StockfishEngine: start(), send(line), poll() -> the lines it answered since the last poll.

var _ok := false


static func supported() -> bool:
	return OS.has_feature("web")


func start() -> void:
	if not supported():
		return
	JavaScriptBridge.eval("""
		(function () {
			if (window.rcEngine) return;
			var e = { lines: [], worker: null };
			try {
				e.worker = new Worker('stockfish_worker.js');
				e.worker.onmessage = function (m) { e.lines.push(String(m.data)); };
				e.worker.onerror = function () { e.lines.push('error'); };
			} catch (x) { e.worker = null; }
			window.rcEngine = e;
		})();
	""", true)
	_ok = bool(JavaScriptBridge.eval("!!(window.rcEngine && window.rcEngine.worker)", true))


func is_running() -> bool:
	return _ok


func send(line: String) -> void:
	if _ok:
		JavaScriptBridge.eval("window.rcEngine.worker.postMessage(%s)" % JSON.stringify(line), true)


func poll() -> PackedStringArray:
	var out := PackedStringArray()
	if not _ok:
		return out
	var s: Variant = JavaScriptBridge.eval(
		"(function(){var e=window.rcEngine;if(!e.lines.length)return '';var t=e.lines.join('\\n');e.lines=[];return t;})()", true)
	if s is String and String(s) != "":
		out = String(s).split("\n")
	return out
