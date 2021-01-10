extends Spatial


# How many clients can connect at a time.
export var max_clients = 32

# True if we're connected to network.
var connected

# The currently used RNG seed.
var current_seed

onready var _sun = $Sun


func _ready():
	var multiplayer_menu = $Multiplayer
	
	multiplayer_menu.connect("tried_hosting", self, "_try_to_host")
	multiplayer_menu.connect("tried_joining", self, "_try_to_join")
	
# warning-ignore:return_value_discarded
	get_tree().connect("network_peer_connected", self, "_on_peer_connected")
# warning-ignore:return_value_discarded
	get_tree().connect("network_peer_disconnected", self, "_on_peer_dead")
# warning-ignore:return_value_discarded
	get_tree().connect("connected_to_server", self, "_we_connected")
# warning-ignore:return_value_discarded
	get_tree().connect("server_disconnected", self, "reset")


func _process(_delta):
	var status_label = $Multiplayer/Split/Host/Status
	status_label.text = "Connected" if connected else "Disconnected"


func _try_to_host(port):
	reset()
	generate_map()
	
	var peer = NetworkedMultiplayerENet.new()
	var result = peer.create_server(port, max_clients)
	
	if result == OK:
		get_tree().network_peer = peer
		rpc("spawn_player", Color())
		connected = true


func _try_to_join(address, port):
	reset()
	
	var peer = NetworkedMultiplayerENet.new()
	var result = peer.create_client(address, port)
	
	if result == OK:
		get_tree().network_peer = peer


func _on_peer_connected(new_id):
	if get_tree().is_network_server():
		rpc_id(new_id, "generate_map", current_seed)
		rpc_id(new_id, "finalize_connection", _sun.current_time)
	
	if new_id != 1:
		var our_id = get_tree().get_network_unique_id()
		var our_player = find_player(our_id)
		
		rpc_id(new_id, "spawn_player", our_player.albedo_color)


func _on_peer_dead(dead_id):
	delete_player(dead_id)


func _we_connected():
	var random_color = Color(randf(), randf(), randf())
	rpc("spawn_player", random_color)


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
		player.queue_free()
	
	connected = false


func set_seed_or_randomize(specific_seed=null):
	if specific_seed:
		current_seed = specific_seed
	else:
		randomize()
		current_seed = randi()
	
	seed(current_seed)


remote func generate_map(specific_seed=null):
	set_seed_or_randomize(specific_seed)
	
	var new_map = Spatial.new()
	new_map.name = "Map"
	
	var terrain = preload("res://entities/terrain.tscn").instance()
	var forest = preload("res://entities/forest.tscn").instance()
	
	new_map.add_child(terrain)
	new_map.add_child(forest)
	
	add_child(new_map)


# Mark the end of connection phase, and synchronize time.
puppet func finalize_connection(server_time):
	_sun.current_time = server_time
	connected = true


func find_player(their_id):
	return $Players.get_node(str(their_id))


remotesync func spawn_player(their_color):
	var sender_id = get_tree().get_rpc_sender_id()
	
	var node = preload("res://entities/player.tscn").instance()
	
	node.name = str(sender_id)
	node.albedo_color = their_color
	node.set_network_master(sender_id)
	
	$Players.add_child(node)


func delete_player(id):
	var player_node = find_player(id)
	player_node.queue_free()
	
	# Make sure the hook is deleted with the player.
	if player_node.hook_node:
		player_node.hook_node.queue_free()
