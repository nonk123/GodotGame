extends KinematicBody

# Gravity applied to the player, in m * s^(-2).
export var gravity = -20.0;

# Character movement speed in m/s.
export var movement_speed = 10;

# Movement speed while sprinting, in m/s.
export var sprint_speed = 20;

# Apply this much velocity when jumping. m/s.
export var jump_power = 20;

# Hook rope cannot get shorter than this.
export var min_hook_length = 0.5;

# Maximum grappling distance, in meters.
export var max_hook_length = 50;

# Apply this much force when hanging from the grappling hook. m * s^(-2).
export var hook_dampening_factor = 200;

# Adjust the hook length by this many meters for each second scrolled.
export var hook_length_adjust_factor = 50;

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

# Dampening defined by grappling hook's length.
var hook_dampening = Vector3();

# Mouse position for use in raycasting.
var mouse_position = Vector2();


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
	
	# Capture the mouse to properly control camera.
	if Input.is_action_pressed("pan_camera"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED);
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE);
	
	# In m * s^(-1) by default, so we multiply by delta again.
	velocity.y += gravity * delta;
	
	var has_support = is_on_floor() or is_on_wall();
	
	if has_support and Input.is_action_just_pressed("jump"):
		velocity.y = jump_power;
	
	# X = left/right, Y = forward/backward.
	var movement = Vector2();
	
	if Input.is_action_pressed("move_left"):
		movement.x -= movement_speed;
	
	if Input.is_action_pressed("move_right"):
		movement.x += movement_speed;
	
	if Input.is_action_pressed("move_forward"):
		movement.y += movement_speed;
	
	if Input.is_action_pressed("move_backward"):
		movement.y -= movement_speed;
	
	if Input.is_action_pressed("sprint"):
		movement *= sprint_speed / movement_speed;
	
	# The (X; Y) vector is relative to the body's XZ plane.
	# Here we turn it by -theta to align.
	# Also, its Y (the body's Z) is backwards. Account for that, too.
	
	var theta = rotation.y;
	
	# The vector rotation formula has been adjusted.
	velocity.x = cos(theta) * movement.x - sin(theta) * movement.y;
	velocity.z = -cos(theta) * movement.y - sin(theta) * movement.x;
	
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
	var hook_node = $GrapplingHook;
	
	# Prevent weird hook behaviour when the mouse is captured.
	var panning = Input.is_action_pressed("pan_camera");
	
	# Reset before calculating.
	hook_dampening = Vector3();
	
	if not panning and Input.is_action_pressed("attach_hook"):
		if hook_node:
			if hook_node.length > hook_length:
				# Dampen toward the hook's end.
				var direction = (hook_node.end - hook_node.start).normalized();
				hook_dampening = direction * hook_dampening_factor;
				
				# Scale according to the stretching factor.
				hook_dampening *= hook_node.length / hook_length;
		else:
			# Create a new grappling hook if it doesn't exist.
			var hook_target = cast_ray(max_hook_length);
			
			# Can't hook to anything.
			if not hook_target:
				return;
			
			hook_node = preload("res://entities/grappling_hook.tscn").instance();
			hook_node.name = "GrapplingHook";
			hook_node.end = hook_target["position"];
			
			add_child(hook_node);
			
			# Default to current hook length.
			hook_length = hook_node.length;
	elif hook_node:
		remove_child(hook_node);
