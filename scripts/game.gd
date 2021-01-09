extends Spatial


# How many clients can connect at a time.
export var max_clients = 32

# True if we're connected to network.
var connected

# The currently used RNG seed.
var current_seed

var _terrain_node

var _forest_node

onready var _sun = $Sun


func _ready():
	# Prevent warnings over discarded value.
	var _tmp
	
	_tmp = $Multiplayer.connect("tried_hosting", self, "_try_to_host")
	_tmp = $Multiplayer.connect("tried_joining", self, "_try_to_join")
	
	_tmp = get_tree().connect("network_peer_connected", self, "_on_peer_connected")
	_tmp = get_tree().connect("network_peer_disconnected", self, "_on_peer_dead")
	_tmp = get_tree().connect("server_disconnected", self, "reset")


func _process(_delta):
	var status_label = $Multiplayer/Split/Host/Status
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
	for player in $Players.get_children():
		$Players.remove_child(player)
		player.call_deferred("free")
	
	connected = false
	
	generate_map()


func set_seed_or_random(specific_seed=null):
	if not specific_seed:
		randomize()
		current_seed = randi()
	else:
		current_seed = specific_seed
	
	seed(current_seed)


func run_generator(node_property, resource):
	var node = get(node_property)
	
	if node:
		remove_child(node)
		node.call_deferred("free")
	
	set(node_property, resource.instance())
	add_child(get(node_property))


remote func generate_map(specific_seed=null):
	set_seed_or_random(specific_seed)
	run_generator("_terrain_node", preload("res://entities/terrain.tscn"))
	run_generator("_forest_node", preload("res://entities/forest.tscn"))


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
	
	# Generate them some trees.
	
	if new_id == 1:
		finalize_connection(_sun.current_time)
	else:
		rpc_id(new_id, "generate_trees", current_seed)
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
	var player_node = get_player(id)
	player_node.queue_free()
	
	# Make sure the hook is deleted with the player.
	if player_node.hook_node:
		player_node.hook_node.queue_free()
