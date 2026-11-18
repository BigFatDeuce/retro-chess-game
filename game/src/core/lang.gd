class_name Lang
## The game's languages: French (the text as written in the code and the data) and English (data/lang/en.json,
## French text -> English text). Labels, buttons and tooltips translate their own text; sentences put together
## in code go through t() and f(). The choice is the "language" setting ("" = French).

const LANGS := [["fr", "Français"], ["en", "English"]]

static var _loaded := false


static func setup() -> void:
	if _loaded:
		return
	_loaded = true
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/lang/en.json"))
	if not d is Dictionary:
		push_error("Traduction anglaise illisible")
		return
	var tr := Translation.new()
	tr.locale = "en"
	var strings: Dictionary = d.get("strings", {})
	for k: String in strings:
		tr.add_message(k, String(strings[k]))
	TranslationServer.add_translation(tr)


## "fr" or "en": the setting, else French (the game's own language; English is chosen in the settings).
static func resolve(setting: String) -> String:
	if setting == "fr" or setting == "en":
		return setting
	return "fr"


static func apply(setting: String) -> void:
	setup()
	TranslationServer.set_locale(resolve(setting))


static func is_en() -> bool:
	return TranslationServer.get_locale().begins_with("en")


## The text in the current language.
static func t(s: String) -> String:
	return String(TranslationServer.translate(s))


## A sentence with values: the format is translated, then filled.
static func f(fmt: String, args: Variant) -> String:
	return t(fmt) % args
