extends CheckBox

func _toggled(button_pressed):
	OS.window_fullscreen = button_pressed
