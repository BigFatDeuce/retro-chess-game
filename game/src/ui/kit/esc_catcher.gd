extends Node
## Calls `on_cancel` on Esc (or the gamepad's back button) and keeps the key from reaching what lies beneath.

var on_cancel: Callable


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and on_cancel.is_valid():
		get_viewport().set_input_as_handled()
		on_cancel.call()
