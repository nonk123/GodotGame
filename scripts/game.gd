extends Spatial


# How many clients can connect at a time.
export var max_clients = 32

# True if we're connected to network.
var connected

onready var _sun = $Terrain/Sun


func _ready():
	randomize()
	
	# Prevent warnings over discarded value.
	var _tmp
	
	_tmp = $Multiplayer.connect("tried_hosting", self, "_try_to_host")
	_tmp = $Multiplayer.connect("tried_joining", self, "_try_to_join")
	
	_tmp = get_tree().connect("network_peer_connected", self, "_on_peer_connected")
	_tmp = get_tree().connect("network_peer_disconnected", self, "_on_peer_dead")
	_tmp = get_tree().connect("server_disconnected", self, "reset")
	
	reset()

func _process(_delta):
	var status_label = $Multiplayer/HSplit/HostSplit/Center/Status
	status_label.text = "Connected" if connected else "Disconnected"


func is_server():
	return get_tree().network_peer && get_tree().is_network_server()


# Reset the game state.
func reset():
	# Close the connection before opening another one.
	if get_tree().network_peer:
		get_tree().network_peer = null
	
	# Reset the mouse cursor set by the player.
	Input.set_custom_mouse_cursor(null)
	
	# Delete all the received entities.
	for child in $Players.get_children():
		child.queue_free()
	
	connected = false


func _try_to_host(port):
	reset()
	
	var peer = NetworkedMultiplayerENet.new()
	var result = peer.create_server(port, max_clients)
	
	if result == OK:
		get_tree().network_peer = peer
		_on_peer_connected(1)


func _try_to_join(address, port):
	reset()
	
	var peer = NetworkedMultiplayerENet.new()
	var result = peer.create_client(address, port)
	
	if result == OK:
		get_tree().network_peer = peer


func _on_peer_connected(new_id):
	if not is_server():
		return
	
	# Spawn everyone for the new player.
	for player in $Players.get_children():
		rpc_id(new_id, "spawn_player", {
			"id": int(player.name),
			"color": player.our_color
		})
	
	var their_info = {
		"id": new_id,
		"color": Color(randf(), randf(), randf())
	}
	
	# And spawn the new player for everyone.
	spawn_player(their_info)
	rpc("spawn_player", their_info)
	
	if new_id == 1:
		finalize_connection(_sun.current_time)
	else:
		rpc_id(new_id, "finalize_connection", _sun.current_time)


func _on_peer_dead(dead_id):
	if is_server():
		rpc("delete_player", dead_id)


# Mark the end of connection phase, and synchronize time.
puppet func finalize_connection(server_time):
	_sun.current_time = server_time
	connected = true


func get_player(their_id):
	return $Players.get_node(str(their_id))


# Info is a dictionary with two keys: "id", the player's id, and their "color".
puppet func spawn_player(info):
	var node = preload("res://entities/player.tscn").instance()
	
	node.name = str(info.id)
	node.set_network_master(info.id)
	
	node.our_color = info.color
	
	$Players.add_child(node)


puppetsync func delete_player(id):
	get_player(id).queue_free()
