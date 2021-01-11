extends KinematicBody


# Linear velocity vector.
var velocity = Vector3()


func _physics_process(delta):
	# Only the network master can run physics. Predict movement otherwise.
	if is_network_master():
		think(delta)
		commit_movement()
	else:
		velocity = move_and_slide(velocity)


puppet func seppuku():
	get_parent().remove_child(self)
	call_deferred("free")


# Override this to play with the velocity.
func think(_delta):
	pass


# Update the body's position locally and for the peers.
func commit_movement():
	velocity = move_and_slide(velocity, Vector3(0.0, 1.0, 0.0))
	
	var new_origin = global_transform.origin
	var new_basis = global_transform.basis
	
	rpc("receive_physics", new_origin, new_basis, velocity)


# Called remotely from `commit_movement`.
puppet func receive_physics(new_origin, new_basis, new_velocity):
	global_transform.origin = new_origin
	global_transform.basis = new_basis
	velocity = new_velocity
