extends Control


# Emitted when the host button is pressed.
signal tried_hosting(port)

# Emitted when the join button is pressed.
signal tried_joining(address, port)


# Default port for the text fields. Also used when the port field is empty.
const default_port = 15347

onready var _host_button = $HSplit/HostSplit/HostButton
onready var _join_button = $HSplit/JoinSplit/JoinButton


func _ready():
	_host_button.connect("pressed", self, "_on_HostButton_pressed")
	_join_button.connect("pressed", self, "_on_JoinButton_pressed")
	
	# Insert default port.
	$HSplit/HostSplit/PortField.text = str(default_port)
	$HSplit/JoinSplit/PortField.text = str(default_port)


func _on_HostButton_pressed():
	var port_field = $HSplit/HostSplit/PortField
	
	var port = int(port_field.text)
	
	if port == 0: # failed to parse
		port_field.text = str(default_port)
	else:
		_host_button.release_focus()
		emit_signal("tried_hosting", port)


func _on_JoinButton_pressed():
	var port_field = $HSplit/JoinSplit/PortField
	var address_field = $HSplit/JoinSplit/AddressField
		
	var port = int(port_field.text)
	var address = address_field.text
	
	if port == 0:
		port_field.text = str(default_port)
	else:
		_join_button.release_focus()
		emit_signal("tried_joining", address, port)
