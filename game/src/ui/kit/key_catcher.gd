extends Node
## Presses the button whose "key" meta matches a typed letter (promotion: the piece letters of the current language).

var buttons: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var ch := OS.get_keycode_string(k.keycode).to_upper()
	for b in buttons:
		if is_instance_valid(b) and b is BaseButton and String(b.get_meta("key", "")) == ch:
			get_viewport().set_input_as_handled()
			(b as BaseButton).pressed.emit()
			return
