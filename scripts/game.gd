extends Spatial


# How many clients can connect at a time.
const MAX_CLIENTS = 32

# The seed that generated the world.
var world_seed

onready var entities = $Entities

onready var mp_menu = $MultiplayerMenu


func _ready():
	# warning-ignore:return_value_discarded
	mp_menu.connect("tried_hosting", self, "_try_to_host")
	mp_menu.connect("tried_joining", self, "_try_to_join")
	
	# warning-ignore:return_value_discarded
	get_tree().connect("network_peer_connected", self, "_on_peer_connected")
	get_tree().connect("connected_to_server", self, "_we_connected")
	
	# warning-ignore:return_value_discarded
	get_tree().connect("server_disconnected", self, "reset")


func _process(_delta):
	var status_label = $MultiplayerMenu/Split/Host/Status
	var peer = get_tree().network_peer
	
	if peer == null:
		status_label.text = "Disconnected"
	else:
		match peer.get_connection_status():
			NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
				status_label.text = "Disconnected"
			NetworkedMultiplayerPeer.CONNECTION_CONNECTING:
				status_label.text = "Connecting"
			NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
				status_label.text = "Connected"


func _try_to_host(port):
	reset()
	
	var peer = NetworkedMultiplayerENet.new()
	var result = peer.create_server(port, MAX_CLIENTS)
	
	if result == OK:
		get_tree().network_peer = peer
		
		_we_connected()
		
		world_seed = randi()
		finish_connection(world_seed)


func _try_to_join(address, port):
	reset()
	
	var peer = NetworkedMultiplayerENet.new()
	var result = peer.create_client(address, port)
	
	if result == OK:
		get_tree().network_peer = peer


func _on_peer_connected(new_id):
	if new_id != 1 and is_network_master():
		rpc_id(new_id, "finish_connection", world_seed)


func _we_connected():
	var our_id = get_tree().get_network_unique_id()
	var scene_path = "res://entities/player.tscn"
	
	randomize()
	
	# Spawn our player.
	spawn_entity(str(our_id), our_id, scene_path, {
		"body_color": Color(randf(), randf(), randf()),
	})


# Reset the game's state.
func reset():
	# Close the connection before opening another one.
	if get_tree().network_peer:
		get_tree().network_peer = null
	
	Input.set_custom_mouse_cursor(null)
	
	var map = get_node_or_null("Map")
	
	# .queue_free() produces weird effects in world generation.
	
	if map:
		remove_child(map)
		map.free()
	
	for entity in entities.get_children():
		entities.remove_child(entity)
		entity.free()


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


remote func spawn_entity(its_name, its_master, scene_path, fields_dict):
	var node = load(scene_path).instance()
	
	for field in fields_dict:
		node.set(field, fields_dict[field])
	
	node.name = its_name
	node.scene_path = scene_path
	
	node.set_network_master(its_master)
	
	entities.add_child(node)


func find_entity(name):
	return entities.get_node_or_null(str(name))
