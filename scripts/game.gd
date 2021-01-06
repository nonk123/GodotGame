extends Spatial


# How many clients can connect at a time.
export var max_clients = 32;

# Point where all the players spawn.
export var spawn_point = Vector3(100.0, 0.0, 100.0);

# Connected peers' IDs.
var connections = [];

# True if we're connected to network.
var _connected = false;

# Our network ID.
var _our_id;


enum Status {
	DISCONNECTED,
	CONNECTED,
}


func _ready():
	# Prevent warnings over discarded value.
	var _tmp;
	
	_tmp = $Multiplayer.connect("tried_hosting", self, "_try_to_host");
	_tmp = $Multiplayer.connect("tried_joining", self, "_try_to_join");
	
	_tmp = get_tree().connect("network_peer_connected", self, "_on_peer_connected");
	_tmp = get_tree().connect("network_peer_disconnected", self, "_on_peer_dead");
	_tmp = get_tree().connect("server_disconnected", self, "reset");
	
	$Players.translate(spawn_point);
	
	set_status(Status.DISCONNECTED);


func _process(_delta):
	if _connected:
		# Send our info to other players.
		var us = find_player_node(_our_id);
		rpc_unreliable("receive_player_info", us.get_info());


func is_server():
	return get_tree().network_peer && get_tree().is_network_server();


# Display status in the status label.
func set_status(status):
	var status_label = $Multiplayer/HSplit/HostSplit/Center/Status;
	
	if status == Status.DISCONNECTED:
		status_label.text = "Disconnected";
	else:
		status_label.text = "Connected";


# Reset the game state.
func reset():
	# Close the connection before opening another one.
	if get_tree().network_peer:
		get_tree().network_peer = null;
	
	set_status(Status.DISCONNECTED);
	
	# Reset the mouse cursor set by the player.
	Input.set_custom_mouse_cursor(null);
	
	_connected = false;
	_our_id = null;
	
	# Delete all the received entities.
	for child in $Players.get_children():
		$Players.remove_child(child);


func _try_to_host(port):
	reset();
	
	var peer = NetworkedMultiplayerENet.new();
	
	if OK == peer.create_server(port, max_clients):
		get_tree().network_peer = peer;
		set_status(Status.CONNECTED);
		
		# Spawn in the host.
		_our_id = get_tree().get_network_unique_id();
		_on_peer_connected(_our_id);


func _try_to_join(address, port):
	reset();
	
	var peer = NetworkedMultiplayerENet.new();
	
	if OK == peer.create_client(address, port):
		get_tree().network_peer = peer;
		set_status(Status.CONNECTED);
		
		_our_id = get_tree().get_network_unique_id();


func _on_peer_connected(new_id):
	if not is_server():
		return;
	
	# Spawn the new player for everyone.
	rpc("spawn_player", new_id);
	spawn_player(new_id);
	
	# And spawn everyone else for him. rpc_id on the host won't work though.
	if new_id != _our_id:
		for player_id in connections:
			rpc_id(new_id, "spawn_player", player_id);
	
	connections.append(new_id);
	
	rpc_id(new_id, "finalize_connection");


func _on_peer_dead(dead_id):
	if not is_server():
		return;
	
	# Delete their player for everyone, including the host.
	rpc("delete_player", dead_id);
	delete_player(dead_id);
	
	connections.erase(dead_id);


func find_player_node(player_id):
	return $Players.get_node(str(player_id));


remotesync func finalize_connection():
	_connected = true;


func apply_player_info(player_node, player_info):
	# Apply the transform.
	player_node.transform.origin = player_info["origin"];
	
	var gas_node = player_node.get_node_or_null("Gas");
	
	# Manage the gas node.
	if player_info["gas_is_on"]:
		if not gas_node:
			gas_node = preload("res://entities/gas.tscn").instance();
			player_node.add_child(gas_node);
	elif gas_node:
		player_node.remove_child(gas_node);
	
	var hook_node = player_node.get_node_or_null("GrapplingHook");
	
	# Manage the hook node.
	if player_info["hook_end"]:
		if not hook_node:
			hook_node = preload("res://entities/grappling_hook.tscn").instance();
			player_node.add_child(hook_node);
		hook_node.end = player_info["hook_end"];
	elif hook_node:
		player_node.remove_child(hook_node);


# Sent by the client to the other peers.
remotesync func receive_player_info(info):
	var player_id = get_tree().get_rpc_sender_id();
	var node = find_player_node(player_id);
	apply_player_info(node, info);


remote func spawn_player(id):
	var node = preload("res://entities/player.tscn").instance();
	node.name = str(id);
	node.set_network_master(id);
	$Players.add_child(node);


remote func delete_player(id):
	$Players.remove_child(find_player_node(id));
