extends Control


# Emitted when the host button is pressed.
signal tried_hosting(port)

# Emitted when the join button is pressed.
signal tried_joining(address, port)


# Default port for the text fields. Also used when the port field is empty.
const DEFAULT_PORT = 15347

onready var host_button = $Split/Host/HostButton
onready var join_button = $Split/Join/JoinButton

onready var join_addr_field = $Split/Join/AddressField

onready var host_port_field = $Split/Host/PortField
onready var join_port_field = $Split/Join/PortField


func _ready():
	host_button.connect("pressed", self, "_on_HostButton_pressed")
	join_button.connect("pressed", self, "_on_JoinButton_pressed")
	
	# Insert the default port.
	host_port_field.text = str(DEFAULT_PORT)
	join_port_field.text = str(DEFAULT_PORT)


func _on_HostButton_pressed():
	var port = int(host_port_field.text)
	
	if port <= 0: # failed to parse
		host_port_field.text = str(DEFAULT_PORT)
	else:
		host_button.release_focus()
		emit_signal("tried_hosting", port)


func _on_JoinButton_pressed():
	var port = int(join_port_field.text)
	var address = join_addr_field.text
	
	if port == 0:
		join_port_field.text = str(DEFAULT_PORT)
	else:
		join_button.release_focus()
		emit_signal("tried_joining", address, port)
