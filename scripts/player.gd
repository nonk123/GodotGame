extends KinematicBody


# Gravity applied to the player, in m * s^(-2).
export var gravity = 30.0;

# Gravity applied to the player when using the gas canister. m * s^(-2).
export var gas_canister_gravity = 15.0;

# A character accelerates by this much when he starts walking. In m * s^(-2).
export var walking_acceleration = 150.0;

# A character cannot walk faster than this value. m/s.
export var max_walking_speed = 20.0;

# Apply this much velocity when jumping. m/s.
export var jump_power = 20.0;

# Friction coefficent applied to ground movement.
export var ground_friction = 1.5;

# How much force to apply when moving with gas canister activated. m * s^(-2).
# There is no limit on air speed, so the value should be quite low.
export var gas_canister_air_control = 12.0;

# TODO: I don't know how to explain this.
export var slowdown_angle = PI / 3;

# Hook rope cannot get shorter than this.
export var min_hook_length = 0.5;

# Maximum grappling distance, in meters.
export var max_hook_length = 80.0;

# Apply this much force when hanging from the grappling hook. m * s^(-2).
export var hook_dampening_factor = 150;

# Adjust the hook length by this many meters for each second scrolled.
export var hook_length_adjust_factor = 60.0;

# Multiplied by relative mouse coordinates.
export var mouse_sensitivity = 0.01;

# If positive, the player is turning right. If negative, turning left.
# Value of zero means no turning. Modified by mouse input.
var _turn_direction = 0.0;

# If positive, pan the camera upwards. If negative, pan downwards.
# Value of zero means no panning. Modified by mouse input.
var _pan_direction = 0.0;

# Player's velocity at this moment. Used in physics calculations.
var _velocity = Vector3();

# If true, show a gas effect for the player. Used in multiplayer.
var _gas_is_on = false;

# Hook length regulated with the scroll wheel.
var _adjusted_hook_length = max_hook_length;

# If non-null, specifies the absolute position of the grappling hook end.
var _hook_end = null;

# If non-null, a dictionary used to calculate the hook's end translation.
# Contains two keys: "them", the hooked entity, and "offset" of the hook.
var _hooked_entity = null;

# Don't stop grappling while true.
var _hook_on = false;

# Dampening defined by grappling hook's length.
var _hook_dampening = Vector3();

# Mouse position for use in raycasting.
var _mouse_position = Vector2();

# A little hack to get the starting position.
onready var spawn_point = transform.origin;


# Only accept mouse events for now.
func _input(event):
	if is_network_master() and event is InputEventMouseMotion:
		_mouse_position = event.position;
		
		if Input.is_action_pressed("pan_camera"):
			_turn_direction = event.relative.x * mouse_sensitivity;
			_pan_direction = event.relative.y * mouse_sensitivity;


func _physics_process(delta):
	# Each player runs their own physics routine.
	if not is_network_master():
		return;
	
	if Input.is_action_pressed("pan_camera"):
		# Capture the mouse to properly control camera.
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED);
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE);
	
	# Apply gravity.
	# It's in m * s^(-1) by default, so we multiply by delta again.
	
	if Input.is_action_pressed("gas_canister"):
		_gas_is_on = true;
		_velocity.y -= gas_canister_gravity * delta;
	else:
		_gas_is_on = false;
		_velocity.y -= gravity * delta;
	
	# Can jump from the floor or the walls.
	# TODO: special walljump behaviour?
	var has_support = is_on_floor() or is_on_wall();
	
	# TODO: allow or disallow bhop?
	if has_support and Input.is_action_pressed("jump"):
		_velocity.y += jump_power;
	
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
	
	# Keep in mind, the camera lines up with _negative_ Z.
	
	if Input.is_action_pressed("move_forward"):
		movement.y -= force;
	
	if Input.is_action_pressed("move_backward"):
		movement.y += force;
	
	# Convert to m * s^(-2).
	movement *= delta;
	
	# Rotate to line up with the XZ plane.
	movement = movement.rotated(-rotation.y);
	
	# Ground speed, basically. Converted to 2D for easier manipulation.
	var xz_velocity = Vector2(_velocity.x, _velocity.z);
	
	# Compare the direction of walking and whatever forces act on us.
	# If going in a different direction, apply our ground acceleration.
	
	var angle = xz_velocity.angle_to(movement);
	var counteracting = angle > slowdown_angle and angle < TAU - slowdown_angle;
	
	# Otherwise, compare ground velocity.
	var speeding = xz_velocity.length() > max_walking_speed;
	
	if is_on_floor():
		if counteracting or not speeding:
			xz_velocity += movement;
		
		# Apply friction.
		var normal_force = _velocity.length();
		var friction_force = ground_friction * normal_force * delta;
		
		xz_velocity -= friction_force * xz_velocity.normalized();
	else:
		xz_velocity += movement;
	
	_velocity.x = xz_velocity.x;
	_velocity.z = xz_velocity.y;
	
	# Don't forget the hook's force. In m * s^(-2).
	_velocity += _hook_dampening * delta;
	
	var up = Vector3(0.0, 1.0, 0.0);
	_velocity = move_and_slide(_velocity, up);


func _process(delta):
	# Refer to the comment at the start of _physics_process.
	if is_network_master():
		if Input.is_action_just_pressed("quit"):
			get_tree().quit(0);
		
		_adjust_for_camera();
		_grapple(delta);


func get_info():
	return {
		"origin": transform.origin,
		"hook_end": _hook_end,
		"gas_is_on": _gas_is_on,
	};


func _adjust_for_camera():
	# Turn the whole body.
	rotate_y(-_turn_direction);
	
	var arm = $SpringArm;
	
	# Only pan the camera arm.
	arm.rotate_x(-_pan_direction);
	
	# Limit the rotation.
	arm.rotation.x = clamp(arm.rotation.x, -PI / 2.0, PI / 2.0);
	
	# Reset for the next frame.
	_turn_direction = 0.0;
	_pan_direction = 0.0;


func _grapple(delta):
	# Prevent weird hook behaviour when the mouse is captured.
	var panning = Input.is_action_pressed("pan_camera");
	
	# Reset before calculating.
	_hook_dampening = Vector3();
	
	# Fiddle with the hook length.
	if Input.is_action_just_released("tighten_rope"):
		_adjusted_hook_length -= hook_length_adjust_factor * delta;
	elif Input.is_action_just_released("loosen_rope"):
		_adjusted_hook_length += hook_length_adjust_factor * delta;
	
	_adjusted_hook_length = clamp(_adjusted_hook_length, min_hook_length, max_hook_length);
	
	if Input.is_action_just_pressed("attach_hook"):
		# Toggle.
		_hook_on = not _hook_on;
	
	if not _hook_on:
		_hook_end = null;
		_hooked_entity = null;
		return;
	
	# Shift the hook's end according to the hooked entitiy's movement.
	if _hooked_entity:
		var their_position = _hooked_entity["them"].global_transform.origin;
		_hook_end = their_position + _hooked_entity["offset"];
	
	if _hook_end:
		if get_hook_length() > _adjusted_hook_length:
			# Dampen towards the hook's end.
			var relative_hook_end = _hook_end - global_transform.origin;
			var direction = relative_hook_end.normalized();
			_hook_dampening = direction * hook_dampening_factor;
			
			# Scale according to the stretching factor.
			_hook_dampening *= get_hook_length() / _adjusted_hook_length;
	elif not panning:
		# Create a new grappling hook if it doesn't exist.
		var hook_target = cast_ray(max_hook_length);
		
		if hook_target:
			_hook_end = hook_target["position"];
			_hooked_entity = {"them": hook_target["collider"]};
			_adjusted_hook_length = get_hook_length();
			
			# Calculate the hook's offset in the entity.
			if _hooked_entity["them"]:
				var their_transform = _hooked_entity["them"].global_transform;
				_hooked_entity["offset"] = _hook_end - their_transform.origin;
		else:
			_hook_on = false;


func get_hook_length():
	return (_hook_end - global_transform.origin).length();


# Cast a ray from the mouse cursor.
func cast_ray(length):
	var space = get_world().direct_space_state;
	
	var camera = $SpringArm/Camera;
	
	var from = camera.project_ray_origin(_mouse_position);
	var to = from + camera.project_ray_normal(_mouse_position) * length;
	
	return space.intersect_ray(from, to, [self]);
