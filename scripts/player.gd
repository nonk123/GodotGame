extends KinematicBody


# Gravity applied to the player, in m * s^(-2).
export var gravity = 30.0;

# Gravity applied to the player when using the gas canister. m * s^(-2).
export var gas_canister_gravity = 15.0;

# A character accelerates by this much when he starts walking. In m * s^(-2).
export var walking_acceleration = 150.0;

# A character cannot walk faster than this value. m/s.
export var max_walking_speed = 10.0;

# Apply this much velocity when jumping. m/s.
export var jump_power = 20.0;

# A big push received when the gas canister is activated. In m/s.
export var dash_power = 50.0;

# Friction coefficent applied to ground movement.
export var ground_friction = 1.5;

# How much force to apply when moving with gas canister activated. m * s^(-2).
# There is no limit on air speed, so the value should be quite low.
export var gas_canister_air_control = 15.0;

# You cannot dash again for this long. In seconds.
export var dash_cooldown = 5.0;

# If the grappling hook gets this short, it snaps.
export var min_hook_length = 2;

# Maximum grappling distance, in meters.
export var max_hook_length = 100.0;

# Apply this much force when hanging from the grappling hook. m * s^(-2).
export var hook_dampening_force = 80;

# Adjust the hook length by this many meters for each second scrolled.
# The word "second" is not accurate here, but it _is_ scaled by delta. 
export var hook_length_adjust_factor = 60.0;

# Relative mouse coordinates are scaled by this much when panning.
export var mouse_sensitivity = 0.01;

# Zoom in by this many meters for each second scrolled.
# As with all scrollwheel-dependent variables, it may be inaccurate.
export var zoom_distance = 3;

# The camera arm cannot get shorter than this many meters.
export var min_zoom = 1.0;

# The camera arm cannot get longer than this many meters.
export var max_zoom = 10.0;

# Assigned randomly at start.
var player_color;

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

# Set this to false to break the grappling hook.
var _is_hook_on = false;

# Dampening defined by grappling hook's length.
var _hook_dampening = Vector3();

# How much time _left_ until you can dash again.
var _dash_cooldown = 0.0;

# Mouse position for use in raycasting.
var _mouse_position = Vector2();

# Scroll direction received from an input event.
var _scroll_direction = 0;

# Custom cursor image.
var _cursor = preload("res://textures/cursor.png");

# Used to prevent re-shading the cursor every frame.
var _last_cursor_shade = Color();

# A little hack to get the starting position.
onready var spawn_point = get_parent_spatial().translation;


func _ready():
	# Create a new material, which will be managed by the game.
	$Shape/Model.material = SpatialMaterial.new();
	player_color = Color(randf(), randf(), randf());
	
	if is_network_master():
		# Set up the camera.
		$SpringArm/Camera.make_current();
		# And initialize the UI.
		add_child(preload("res://entities/ui.tscn").instance());


# Only accept mouse events for now.
func _input(event):
	if is_network_master():
		if event is InputEventMouseMotion:
			_mouse_position = event.position;
			
			if Input.is_action_pressed("pan_camera"):
				# Capture the mouse to properly control the camera.
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED);
				
				_turn_direction = event.relative.x * mouse_sensitivity;
				_pan_direction = event.relative.y * mouse_sensitivity;
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE);
		elif event is InputEventMouseButton:
			if event.pressed:
				match event.button_index:
					BUTTON_WHEEL_UP:
						_scroll_direction = 1;
					BUTTON_WHEEL_DOWN:
						_scroll_direction = -1;
					_:
						_scroll_direction = 0;


func _physics_process(delta):
	# Each player runs their own physics routine.
	if not is_network_master():
		return;
	
	# Go back to spawn. Reset all the variables.
	if Input.is_action_just_pressed("reset_myself"):
		translation = Vector3();
		_velocity = Vector3();
		_hook_dampening = Vector3();
		_is_hook_on = false;
		_dash_cooldown = 0.0;
	
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
	
	# No autojump.
	if has_support and Input.is_action_just_pressed("jump"):
		_velocity.y += jump_power;
	
	# X = left/right, Y = forward/backward.
	var movement = Vector2();
	
	if Input.is_action_pressed("move_left"):
		movement.x -= walking_acceleration;
	
	if Input.is_action_pressed("move_right"):
		movement.x += walking_acceleration;
	
	# Keep in mind, the camera lines up with _negative_ Z.
	# Forwards is negative in this case.
	
	if Input.is_action_pressed("move_forward"):
		movement.y -= walking_acceleration;
	
	if Input.is_action_pressed("move_backward"):
		movement.y += walking_acceleration;
	
	# Convert to m * s^(-2).
	movement *= delta;
	
	# Rotate to line up with the XZ plane.
	movement = movement.rotated(-rotation.y);
	
	# Ground speed, basically. Converted to 2D for easier manipulation.
	var xz_velocity = Vector2(_velocity.x, _velocity.z);

	var speeding = xz_velocity.length() > max_walking_speed;
	
	_dash_cooldown -= delta;
	
	# Try dashing.
	if Input.is_action_just_pressed("gas_canister") and _dash_cooldown <= 0.0:
		var dash_velocity = movement.normalized() * dash_power;
		
		# Don't start the cooldown timer if we're not dashing.
		if dash_velocity.length_squared() > 0.0:
			xz_velocity += dash_velocity;
			_dash_cooldown = dash_cooldown;
	
	if Input.is_action_pressed("gas_canister"):
		# The difference between .normalized() and division is that the latter
		# includes the delta.
		xz_velocity += movement / walking_acceleration * gas_canister_air_control;
	
	if is_on_floor():
		if not speeding:
			xz_velocity += movement;
		
		var normal_force = _velocity.length();
		var friction_force = ground_friction * normal_force * delta;
		
		# Simulate friction.
		xz_velocity -= friction_force * xz_velocity.normalized();
	
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
		
		_adjust_for_camera(delta);
		_run_smart_cursor();
		_update_ui();
		_grapple(delta);


func get_info():
	return {
		"origin": transform.origin,
		"hook_end": _hook_end,
		"gas_is_on": _gas_is_on,
		"color": player_color,
	};


# Modify image data directly to replace non-transparent pixels with color.
func _shade_cursor(color):
	# Don't re-shade into the same color.
	if _last_cursor_shade == color:
		return;
	
	_cursor.lock();
	
	for x in range(_cursor.get_width()):
		for y in range(_cursor.get_height()):
			if _cursor.get_pixel(x, y).a == 1:
				_cursor.set_pixel(x, y, color);
	
	_cursor.unlock();
	
	_last_cursor_shade = color;


func _run_smart_cursor():
	var result = cast_ray(max_hook_length);
	
	var hotspot = _cursor.get_size() / 2.0;
	
	var can_hit = Color(1.0, 1.0, 1.0);
	var too_far = Color(1.0, 0.0, 0.0);
	
	_shade_cursor(can_hit if result else too_far);
	
	# Convert to a texture usable as a cursor.
	var cursor = ImageTexture.new();
	cursor.create_from_image(_cursor);
	
	Input.set_custom_mouse_cursor(cursor, Input.CURSOR_ARROW, hotspot);


func _update_ui():
	var dash_progress = get_node_or_null("UI/BottomRight/DashCooldown");
	dash_progress.value = 1.0 - _dash_cooldown / dash_cooldown;
	
	var position_label = get_node_or_null("UI/TopRight/Position");
	
	var position = global_transform.origin;
	var format = "X: %.2f; Y: %.2f; Z: %.2f";
	
	position_label.text = format % [position.x, position.y, position.z];


func _adjust_for_camera(delta):
	# Turn the whole body for horizontal rotation.
	rotate_y(-_turn_direction);
	
	var arm = $SpringArm;
	
	# Only pan the camera arm.
	arm.rotate_x(-_pan_direction);
	
	# Zoom in/out.
	if Input.is_action_pressed("pan_camera"):
		arm.spring_length -= zoom_distance * delta * _scroll_direction;
		arm.spring_length = clamp(arm.spring_length, min_zoom, max_zoom);
	
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
	
	if Input.is_action_just_pressed("attach_hook"):
		_is_hook_on = not _is_hook_on; # toggle
	
	if _hook_end and not panning:
		# Fiddle with the hook length.
		var base_speed = hook_length_adjust_factor * delta;
		var adjust = get_hook_length() / max_hook_length;
		var result = base_speed * adjust;
		
		_adjusted_hook_length -= result * _scroll_direction;
		_adjusted_hook_length = clamp(_adjusted_hook_length, 1, max_hook_length);
	
	# Break the hook if it gets too short.
	if _hook_end and get_hook_length() <= min_hook_length:
		_is_hook_on = false;
	
	if not _is_hook_on:
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
			
			_hook_dampening = direction * hook_dampening_force;
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
			_is_hook_on = false;


func get_hook_length():
	return (_hook_end - global_transform.origin).length();


# Cast a ray from the mouse cursor.
func cast_ray(length):
	var space = get_world().direct_space_state;
	
	var camera = $SpringArm/Camera;
	
	var from = camera.project_ray_origin(_mouse_position);
	var to = from + camera.project_ray_normal(_mouse_position) * length;
	
	return space.intersect_ray(from, to, [self]);
