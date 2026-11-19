class_name Lang
## The game's languages: French (the text as written in the code and the data) and the translations in
## data/lang/<code>.json (French text -> translated text). Labels, buttons and tooltips translate their own text;
## sentences put together in code go through t() and f(). The choice is the "language" setting ("" = French).

const LANGS := [["fr", "Français"], ["en", "English"], ["es", "Español"], ["pt", "Português"], ["de", "Deutsch"], ["it", "Italiano"]]

## Piece letters of the algebraic notation, per language: king, queen, rook, bishop, knight.
const SAN := {
	"fr": ["R", "D", "T", "F", "C"], "en": ["K", "Q", "R", "B", "N"], "es": ["R", "D", "T", "A", "C"],
	"pt": ["R", "D", "T", "B", "C"], "de": ["K", "D", "T", "L", "S"], "it": ["R", "D", "T", "A", "C"],
}

static var _loaded := false


static func setup() -> void:
	if _loaded:
		return
	_loaded = true
	for l in LANGS:
		if l[0] == "fr":
			continue
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/lang/%s.json" % l[0]))
		if not d is Dictionary:
			push_error("Traduction illisible : " + l[0])
			continue
		var tr := Translation.new()
		tr.locale = l[0]
		var strings: Dictionary = d.get("strings", {})
		for k: String in strings:
			tr.add_message(k, String(strings[k]))
		TranslationServer.add_translation(tr)


## A language code of LANGS: the setting, else French (the game's own language).
static func resolve(setting: String) -> String:
	for l in LANGS:
		if l[0] == setting:
			return setting
	return "fr"


static func apply(setting: String) -> void:
	setup()
	TranslationServer.set_locale(resolve(setting))


static func code() -> String:
	return resolve(TranslationServer.get_locale().left(2))


## The algebraic-notation letter of a piece ("K", "Q", "R", "B", "N") in the current language.
static func san_letter(piece: String) -> String:
	return SAN[code()]["KQRBN".find(piece)]


## The text in the current language.
static func t(s: String) -> String:
	return String(TranslationServer.translate(s))


## A sentence with values: the format is translated, then filled.
static func f(fmt: String, args: Variant) -> String:
	return t(fmt) % args
