extends KinematicBody

# Gravity applied to the player, in m * s^(-2).
export var gravity = 30.0;

# Gravity applied to the player when using the gas canister. m * s^(-2).
export var gas_canister_gravity = 12.0;

# A character accelerates by this much when he starts walking. In m * s^(-2).
export var walking_acceleration = 150.0;

# A character cannot walk faster than this value. m/s.
export var max_walking_speed = 20.0;

# Apply this much velocity when jumping. m/s.
export var jump_power = 20.0;

# Friction coefficent applied to ground movement.
export var ground_friction = 0.8;

# How much force to apply when moving with gas canister activated. m * s^(-2).
# There is no limit on air speed, so the value should be quite low.
export var gas_canister_air_control = 15.0;

# TODO: I don't know how to explain.
export var slowdown_angle = PI / 3;

# Hook rope cannot get shorter than this.
export var min_hook_length = 0.5;

# Maximum grappling distance, in meters.
export var max_hook_length = 50;

# Apply this much force when hanging from the grappling hook. m * s^(-2).
export var hook_dampening_factor = 150;

# Adjust the hook length by this many meters for each second scrolled.
export var hook_length_adjust_factor = 60.0;

# Multiplied by relative mouse coordinates.
export var mouse_sensitivity = 0.01;

# If positive, the player is turning right. If negative, turning left.
# Value of zero means no turning. Modified by mouse input.
var turn_direction = 0.0;

# If positive, pan the camera upwards. If negative, pan downwards.
# Value of zero means no panning. Modified by mouse input.
var pan_direction = 0.0;

# Player's velocity at this moment. Used in physics calculations.
var velocity = Vector3();

# Adjustable hook length.
var hook_length = max_hook_length;

# Don't stop grappling while true.
var hook_on = false;

# Dampening defined by grappling hook's length.
var hook_dampening = Vector3();

# Mouse position for use in raycasting.
var mouse_position = Vector2();

# A little hack to get the starting position.
onready var spawn_point = transform.origin;


# Only accept mouse events for now.
func _input(event):
	if event is InputEventMouseMotion:
		mouse_position = event.position;
		
		if Input.is_action_pressed("pan_camera"):
			turn_direction = event.relative.x * mouse_sensitivity;
			pan_direction = event.relative.y * mouse_sensitivity;


func _physics_process(delta):
	if Input.is_action_just_pressed("quit"):
		get_tree().quit(0);
	
	if Input.is_action_just_pressed("reset"):
		transform.origin = spawn_point;
		hook_dampening = Vector3();
		velocity = Vector3();
		hook_on = false;
	
	if Input.is_action_pressed("pan_camera"):
		# Capture the mouse to properly control camera.
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED);
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE);
	
	# Apply gravity.
	# It's in m * s^(-1) by default, so we multiply by delta again.
	
	var gas_node = get_node_or_null("Gas");
	
	if Input.is_action_pressed("gas_canister"):
		if not gas_node:
			gas_node = preload("res://entities/gas.tscn").instance();
			add_child(gas_node);
		velocity.y -= gas_canister_gravity * delta;
	else:
		if gas_node:
			remove_child(gas_node);
		velocity.y -= gravity * delta;
	
	# Can jump from the floor or the walls.
	var has_support = is_on_floor() or is_on_wall();
	
	# TODO: allow or disallow bhop?
	if has_support and Input.is_action_pressed("jump"):
		velocity.y += jump_power;
	
	# X = left/right, Y = forward/backward.
	var movement = Vector2();
	
	# Force applied through directed movement.
	var force = 0.0;
	
	if is_on_floor():
		force += walking_acceleration;
	
	if Input.is_action_pressed("gas_canister"):
		force += gas_canister_air_control;
	
	# Actual movement calculations.
	
	if Input.is_action_pressed("move_left"):
		movement.x -= force;
	
	if Input.is_action_pressed("move_right"):
		movement.x += force;
	
	if Input.is_action_pressed("move_forward"):
		movement.y += force;
	
	if Input.is_action_pressed("move_backward"):
		movement.y -= force;
	
	# Convert to m * s^(-2).
	movement *= delta;
	
	# Ground speed, basically. Converted to 2D for easier manipulation.
	var xz_velocity = Vector2(velocity.x, velocity.z);
	
	# The formula below rotates the movement vector (the body's XZ, with
	# the Z axis pointing forwards from it) to line up with the global
	# coordinates.
	#
	# We are rotating by -theta, for which the formula is adjusted.
	
	var theta = rotation.y;
	var absolute = Vector2();
	
	absolute.x -= sin(theta) * movement.y - cos(theta) * movement.x;
	absolute.y -= cos(theta) * movement.y + sin(theta) * movement.x;
	
	# Compare the direction of walking and whatever forces act on us.
	# If going in a different direction, apply our ground acceleration.
	var angle = xz_velocity.angle_to(absolute);
	
	var counteracting = angle > slowdown_angle and angle < TAU - slowdown_angle;
	
	# Otherwise, compare ground velocity.
	var speeding = xz_velocity.length() > max_walking_speed;
	
	if is_on_floor():
		# Apply special rules for ground movement.
		if counteracting or not speeding:
			xz_velocity += absolute;
		
		# Apply friction. Assuming normal force is the opposite of gravity.
		var friction_force = ground_friction * gravity * delta;
		xz_velocity -= friction_force * xz_velocity.normalized();
	else:
		xz_velocity += absolute;
	
	# Apply the values from 2D modifications.
	velocity.x = xz_velocity.x;
	velocity.z = xz_velocity.y;
	
	# Don't forget the hook's force. In m * s^(-2).
	velocity += hook_dampening * delta;
	
	velocity = move_and_slide(velocity, Vector3(0.0, 1.0, 0.0));


func _process(delta):
	# Turn the whole body.
	rotate_y(-turn_direction);
	
	var arm = $SpringArm;
	
	# Only pan the camera arm.
	arm.rotate_x(-pan_direction);
	
	# Limit the rotation.
	arm.rotation.x = clamp($SpringArm.rotation.x, -PI / 2.0, PI / 2.0);
	
	# Reset for the next frame.
	turn_direction = 0.0;
	pan_direction = 0.0;
	
	# Fiddle with hook length.
	if Input.is_action_just_released("tighten_rope"):
		hook_length -= hook_length_adjust_factor * delta;
	elif Input.is_action_just_released("loosen_rope"):
		hook_length += hook_length_adjust_factor * delta;
	
	hook_length = clamp(hook_length, min_hook_length, max_hook_length);
	
	# Process grappling hook stuff.
	grapple();


# Cast a ray from the mouse cursor.
func cast_ray(length):
	var space = get_world().direct_space_state;
	
	var camera = $SpringArm/Camera;
	
	var from = camera.project_ray_origin(mouse_position);
	var to = from + camera.project_ray_normal(mouse_position) * length;
	
	return space.intersect_ray(from, to, [self]);


func grapple():
	var hook_node = get_node_or_null("GrapplingHook");
	
	# Prevent weird hook behaviour when the mouse is captured.
	var panning = Input.is_action_pressed("pan_camera");
	
	# Reset before calculating.
	hook_dampening = Vector3();
	
	if Input.is_action_just_pressed("attach_hook"):
		hook_on = not hook_on;
	
	if hook_on:
		if hook_node:
			if hook_node.get_length() > hook_length:
				# Dampen towards the hook's end.
				var direction = (hook_node.end - hook_node.start).normalized();
				hook_dampening = direction * hook_dampening_factor;
				
				# Scale according to the stretching factor.
				hook_dampening *= hook_node.get_length() / hook_length;
		elif not panning:
			# Create a new grappling hook if it doesn't exist.
			var hook_target = cast_ray(max_hook_length);
			
			# Can't hook to anything.
			if not hook_target:
				# Also don't try to grapple every frame.
				hook_on = false;
				return;
			
			hook_node = preload("res://entities/grappling_hook.tscn").instance();
			hook_node.name = "GrapplingHook";
			hook_node.end = hook_target["position"];
			
			add_child(hook_node);
			
			# Default to current hook length.
			hook_length = hook_node.get_length();
	elif hook_node:
		remove_child(hook_node);
