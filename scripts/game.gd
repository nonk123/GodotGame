extends Spatial


# How many clients can connect at a time.
export var max_clients = 32

# True if we're connected to network.
var connected

# The seed that generated the world.
var world_seed

onready var _sun = $Sun


func _ready():
# warning-ignore:return_value_discarded
	$MultiplayerMenu.connect("tried_hosting", self, "_try_to_host")
# warning-ignore:return_value_discarded
	$MultiplayerMenu.connect("tried_joining", self, "_try_to_join")
	
# warning-ignore:return_value_discarded
	get_tree().connect("network_peer_connected", self, "_on_peer_connected")
	# warning-ignore:return_value_discarded
	get_tree().connect("network_peer_disconnected", self, "_on_peer_disconnected")
# warning-ignore:return_value_discarded
	get_tree().connect("server_disconnected", self, "reset")


func _process(_delta):
	var status_label = $MultiplayerMenu/Split/Host/Status
	status_label.text = "Connected" if connected else "Disconnected"


func _try_to_host(port):
	reset()
	
	var peer = NetworkedMultiplayerENet.new()
	var result = peer.create_server(port, max_clients)
	
	if result == OK:
		get_tree().network_peer = peer
		
		randomize()
		world_seed = randi()
		
		# `seed()` will be called here.
		finish_connection(world_seed)


func _try_to_join(address, port):
	reset()
	
	var peer = NetworkedMultiplayerENet.new()
	var result = peer.create_client(address, port)
	
	if result == OK:
		get_tree().network_peer = peer


func _on_peer_connected(new_id):
	var our_id = get_tree().get_network_unique_id()
	
	var our_color = find_player(our_id).albedo_color
	rpc_id(new_id, "spawn_player", our_color, our_id)
	
	if is_network_master():
		rpc_id(new_id, "finish_connection", world_seed)


func _on_peer_disconnected(their_id):
	find_player(their_id).seppuku()


# Reset the game's state.
func reset():
	# Close the connection before opening another one.
	if get_tree().network_peer:
		get_tree().network_peer = null
	
	Input.set_custom_mouse_cursor(null)
	
	var map = get_node_or_null("Map")
	
	if map:
		remove_child(map)
		map.free()
	
	for player in $Players.get_children():
		player.get_parent().remove_child(player)
		player.call_deferred("free")
	
	connected = false


# Generate the map, and end the connection phase.
remote func finish_connection(their_world_seed: int):
	var new_map = Spatial.new()
	new_map.name = "Map"
	
	var terrain = preload("res://entities/terrain.tscn").instance()
	terrain.world_seed = their_world_seed
	
	var forest = preload("res://entities/forest.tscn").instance()
	forest.world_seed = their_world_seed
	
	new_map.add_child(terrain)
	new_map.add_child(forest)
	
	add_child(new_map)
	
	spawn_our_player()
	
	connected = true


func find_player(their_id):
	return $Players.get_node(str(their_id))


# The player's ID is passed explicitly to allow local calls.
remote func spawn_player(their_color, their_id):
	var node = preload("res://entities/player.tscn").instance()
	
	node.name = str(their_id)
	node.albedo_color = their_color
	node.set_network_master(their_id)
	
	$Players.add_child(node)


# Spawn the local player with a random color.
func spawn_our_player():
	randomize()
	
	var random_color = Color(randf(), randf(), randf())
	var our_id = get_tree().get_network_unique_id()
	
	spawn_player(random_color, our_id)
