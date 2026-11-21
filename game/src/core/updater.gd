extends Node
## Updates from inside the game (autoload "Updater"). At launch, asks GitHub for the latest release of
## BigFatDeuce/retro-chess-game; when its version is newer than this one, the title screen offers it.
## Windows: downloads the release's zip, unpacks it next to the save files, then a small PowerShell script waits
## for the game to close, copies the new files over the old ones and starts the game again.
## Android: downloads the APK and opens it: the system installer takes over (the player confirms).
## The web version is always the latest one (the page is never cached): no updates there.
## Test: --update-url <url of a JSON like GitHub's "latest release"> replaces the GitHub address;
## --update-install installs what it finds without asking.

signal found(info: Dictionary)  ## {"version", "notes", "url" (asset), "size", "page"}
signal progress(ratio: float)
signal failed(message: String)
signal installing  ## Windows: the game closes in a moment, the update installs, the game starts again

const REPO := "BigFatDeuce/retro-chess-game"
const API := "https://api.github.com/repos/%s/releases/latest" % REPO
const ASSET_WINDOWS := "RetroChess-windows.zip"
const ASSET_ANDROID := "RetroChess-android.apk"
const ASSET_LINUX := "RetroChess-linux.tar.gz"
const ASSET_MACOS := "RetroChess-macos.zip"
const DIR := "user://update"

var info: Dictionary = {}  ## the newer release found, or {}
var busy := false
var _http: HTTPRequest
var _dl: HTTPRequest


func supported() -> bool:
	if OS.has_feature("web") or OS.has_feature("editor"):
		return false
	return OS.has_feature("windows") or OS.has_feature("android") or OS.has_feature("linuxbsd") 		or OS.has_feature("macos")


## Whether the update is downloaded and installed by the game; elsewhere (Linux, macOS) the release page opens.
func self_installs() -> bool:
	return OS.has_feature("windows") or OS.has_feature("android")


func _asset() -> String:
	if OS.has_feature("android"):
		return ASSET_ANDROID
	if OS.has_feature("linuxbsd"):
		return ASSET_LINUX
	if OS.has_feature("macos"):
		return ASSET_MACOS
	return ASSET_WINDOWS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if supported() and bool(Settings.get_value("check_updates")):
		check.call_deferred()


func version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## "1.2.10" > "1.2.9"; a leading "v" is ignored.
static func newer(a: String, b: String) -> bool:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false


func check() -> void:
	if busy:
		return
	var url := API
	var args := OS.get_cmdline_user_args()
	if "--update-url" in args:
		url = args[args.find("--update-url") + 1]
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = 15.0
		add_child(_http)
		_http.request_completed.connect(_on_checked)
	_http.request(url, ["User-Agent: RetroChess-Updater", "Accept: application/vnd.github+json"])


func _on_checked(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return  # offline or no release yet: nothing to say
	var d: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not d is Dictionary:
		return
	var tag := String(d.get("tag_name", ""))
	if tag == "" or not newer(tag, version()):
		return
	var want := _asset()
	for a: Dictionary in d.get("assets", []):
		if String(a.get("name", "")) == want:
			info = {"version": tag.trim_prefix("v"), "notes": String(d.get("body", "")),
				"url": String(a.get("browser_download_url", "")), "size": int(a.get("size", 0)),
				"page": String(d.get("html_url", "https://github.com/" + REPO + "/releases/latest"))}
			found.emit(info)
			if "--update-install" in OS.get_cmdline_user_args():  # test: installs without asking
				install()
			return


## Downloads the update, then installs it (the game closes on Windows).
func install() -> void:
	if info.is_empty() or busy:
		return
	if not self_installs():
		OS.shell_open(String(info["page"]))
		return
	busy = true
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := DIR.path_join(_asset())
	_dl = HTTPRequest.new()
	_dl.download_file = file
	_dl.use_threads = true
	add_child(_dl)
	_dl.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		set_process(false)
		_dl.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			busy = false
			failed.emit(Lang.t("Téléchargement impossible. Vérifie ta connexion et réessaie."))
			return
		progress.emit(1.0)
		if OS.has_feature("android"):
			_install_android(file)
		else:
			_install_windows(file))
	var err := _dl.request(String(info["url"]), ["User-Agent: RetroChess-Updater"])
	if err != OK:
		busy = false
		failed.emit(Lang.t("Téléchargement impossible. Vérifie ta connexion et réessaie."))
		return
	set_process(true)


func _process(_delta: float) -> void:
	if _dl and is_instance_valid(_dl):
		var total := _dl.get_body_size()
		if total <= 0:
			total = int(info.get("size", 0))
		if total > 0:
			progress.emit(clampf(float(_dl.get_downloaded_bytes()) / total, 0.0, 0.99))


func _install_windows(zip_path: String) -> void:
	# A PowerShell script does the rest once the game has closed: unpacks the zip (tar reads it as a stream: the
	# game's data is far too big to unpack in memory here), copies the files over the game, starts it again.
	var zip := ProjectSettings.globalize_path(zip_path)
	var tmp := ProjectSettings.globalize_path(DIR.path_join("files"))
	var dst := OS.get_executable_path().get_base_dir()
	var exe := OS.get_executable_path()
	var script := ProjectSettings.globalize_path(DIR.path_join("install.ps1"))
	var ps := FileAccess.open(script, FileAccess.WRITE)
	if ps == null:
		_fail_install()
		return
	var q := func(t: String) -> String: return "'" + t.replace("'", "''") + "'"
	ps.store_string("""$ErrorActionPreference = 'Stop'
$zip = %s; $tmp = %s; $dst = %s; $exe = %s
try {
	Wait-Process -Id %d -Timeout 60 -ErrorAction SilentlyContinue
	Start-Sleep -Milliseconds 500
	if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
	New-Item -ItemType Directory -Path $tmp | Out-Null
	& tar.exe -xf $zip -C $tmp
	if ($LASTEXITCODE -ne 0) { Expand-Archive -Path $zip -DestinationPath $tmp -Force }
	$root = $tmp
	$items = @(Get-ChildItem $tmp)
	if ($items.Count -eq 1 -and $items[0].PSIsContainer) { $root = $items[0].FullName }
	Copy-Item -Path (Join-Path $root '*') -Destination $dst -Recurse -Force
} catch {}
Start-Process -FilePath $exe -WorkingDirectory $dst
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zip -Force -ErrorAction SilentlyContinue
""" % [q.call(zip), q.call(tmp), q.call(dst), q.call(exe), OS.get_process_id()])
	ps.close()
	var pid := OS.create_process("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
		"-File", script])
	if pid <= 0:
		_fail_install()
		return
	installing.emit()
	await get_tree().create_timer(1.2).timeout
	get_tree().quit()


func _install_android(apk_path: String) -> void:
	# the system installer opens the package (Godot shares the file with it); the player confirms
	if OS.shell_open(ProjectSettings.globalize_path(apk_path)) != OK:
		OS.shell_open(String(info.get("page", "")))
	busy = false


func _fail_install() -> void:
	busy = false
	failed.emit(Lang.t("Installation impossible. La page de téléchargement va s'ouvrir."))
	OS.shell_open(String(info.get("page", "")))
