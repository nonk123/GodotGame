extends KinematicBody


# Linear velocity vector.
var velocity = Vector3()

# The scene path of this entity.
var scene_path

# Fields transferred when spawning this entity remotely.
var init_fields = []


func _ready():
	# warning-ignore:return_value_discarded
	get_tree().connect("network_peer_connected", self, "spawn_for_peer")
	
	# warning-ignore:return_value_discarded
	get_tree().connect("network_peer_disconnected", self, "_on_peer_disconnected")
	
	if is_network_master():
		spawn_convoluted("rpc")


func _physics_process(delta):
	if is_network_master():
		# Only the network master can run physics.
		_think(delta)
		apply_movement()
	else:
		# Predict movement otherwise.
		velocity = move_and_slide(velocity)


# Override this to play with the velocity.
func _think(_delta):
	pass


puppet func seppuku():
	queue_free()


func spawn_for_peer(peer_id):
	spawn_convoluted("rpc_id", [peer_id])


func spawn_convoluted(spawn_function, prepend_args = []):
	var fields_dict = {}
	
	for field in init_fields:
		fields_dict[field] = get(field)
	
	var extra_args = ["spawn_entity", name, get_network_master(), scene_path, fields_dict]
	
	var root = get_node("/root/World")
	root.callv(spawn_function, prepend_args + extra_args)


func _on_peer_disconnected(peer_id):
	if get_network_master() == peer_id:
		rpc("seppuku")


# Update the body's position locally and for the peers.
func apply_movement():
	velocity = move_and_slide(velocity, Vector3(0.0, 1.0, 0.0))
	
	var new_origin = global_transform.origin
	var new_basis = global_transform.basis
	
	rpc_unreliable("receive_physics", new_origin, new_basis, velocity)


# Called remotely from `apply_movement`.
puppet func receive_physics(new_origin, new_basis, new_velocity):
	global_transform.origin = new_origin
	global_transform.basis = new_basis
	velocity = new_velocity
