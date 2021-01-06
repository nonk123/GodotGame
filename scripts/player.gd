extends KinematicBody;


# Player's mass in kg. Only used once.
export var mass = 10.0;

# A character accelerates by this much when he walks. In m * s^(-2).
export var walking_acceleration = 20.0;

# A character cannot walk faster than this value. m/s.
export var max_walking_speed = 12.0;

# Impulse applied when a jump is made. m/s.
export var jump_power = 15.0;

# Impulse applied when the player dashes. m/s.
export var dash_power = 50.0;

# Friction coefficient applied to walking.
export var walking_friction = 0.8;

# Friction coefficient for sliding with gas canister on.
export var sliding_friction = 0.3;

# Used in air resistance calculations. Not meant to be realistic.
export var drag_coefficient = 0.08;

# Each player starts with this much gas. In abstract units.
export var starting_gas_capacity = 100;

# How much boost does the air canister give, in m * s^(-2).
export var gas_canister_boost = 15.0;

# Doing a dash costs this much gas.
export var dash_cost = 3.0;

# Using gas costs this much per second.
export var gas_boost_cost = 0.4;

# If the grappling hook rope gets this short, it snaps.
export var min_hook_rope_length = 0.5;

# Maximum grappling distance, in meters.
export var max_hook_rope_length = 100.0;

# The rope's stretching coefficient cannot get higher than this.
export var max_hook_rope_stretching = 10;

# How fast the hook retracts with each scroll, in m * u/s.
export var hook_retraction_speed = 25.0;

# Speed higher than this is shown as red on the speedometer. m/s.
# Used to indicate that, e.g., you are very prone to drag.
export var red_velocity = 120.0;

# Relative mouse coordinates are scaled by this much when panning.
export var mouse_sensitivity = 0.01;

# Each mouse wheel event registers this many scroll units.
export var scroll_sensitivity = 5.0;

# How much to zoom in/out, in m * u/s.
export var zoom_distance = 3.0;

# The camera arm cannot get shorter than this many meters.
export var min_zoom = 1.0;

# The camera arm cannot get longer than this many meters.
export var max_zoom = 10.0;

# A velocity vector used in physics calculations.
var _velocity = Vector3();

# If positive, the player is turning right. If negative, turning left.
# Value of zero means no turning. Modified by mouse input.
var _turn_direction = 0.0;

# If positive, pan the camera upwards. If negative, pan downwards.
# Value of zero means no panning. Modified by mouse input.
var _pan_direction = 0.0;

# If true, show a gas effect for the player. Only useful in multiplayer.
var _show_gas = false;

# Hook length regulated with the scroll wheel.
var _adjusted_rope_length = max_hook_rope_length;

# If non-null, specifies the absolute position of the grappling hook end.
var _hook_end = null;

# If non-null, a dictionary used to calculate the hook's end translation.
# Contains two keys: "them", the hooked entity, and "offset" of the hook.
var _hooked_entity = null;

# Set this to false to break the grappling hook.
var _is_hook_on = false;

# How much gas we have at the moment.
var _gas_meter = starting_gas_capacity;

# Mouse position for use in raycasting.
var _mouse_position = Vector2();

# How much scrolling was requested.
var _scroll_delta = 0.0;

# Custom cursor image.
var _cursor = preload("res://textures/cursor.png");

# Used to prevent re-shading the cursor every frame.
var _last_cursor_shade = Color();

# Assigned randomly at start.
onready var player_color = Color(randf(), randf(), randf());


func _ready():
	# Create a new material, which will be managed in game.gd.
	$Shape/Model.material = SpatialMaterial.new();
	
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
			match event.button_index:
				BUTTON_WHEEL_UP:
					_scroll_delta += scroll_sensitivity;
				BUTTON_WHEEL_DOWN:
					_scroll_delta -= scroll_sensitivity;


func _physics_process(delta):
	# Each player runs their own physics routine, but not others'.
	if not is_network_master():
		return;
	
	# Go back to spawn. Reset all variables.
	if Input.is_action_just_pressed("reset_myself"):
		# With y = 0.0 you will get stuck if you're moving.
		translation = Vector3(0.0, 0.01, 0.0);
		_velocity = Vector3();
		_is_hook_on = false;
		_gas_meter = starting_gas_capacity;
	
	# No autojump. Can only bounce off the floor.
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		_velocity.y += jump_power;
	
	# Apply gravity.
	_velocity.y -= 9.8 * delta;
	
	# X = left/right, Y = forward/backward.
	var movement = Vector2();
	
	if Input.is_action_pressed("move_left"):
		movement.x -= 1.0;
	
	if Input.is_action_pressed("move_right"):
		movement.x += 1.0;
	
	# Keep in mind, the camera lines up with _negative_ Z.
	# Forwards is negative in this case.
	
	if Input.is_action_pressed("move_forward"):
		movement.y -= 1.0;
	
	if Input.is_action_pressed("move_backward"):
		movement.y += 1.0;
	
	# Rotate to line up with the XZ plane.
	movement = movement.rotated(-rotation.y);
	
	# Reset before each frame.
	_show_gas = false;
	
	# Can we use gas this frame?
	var can_use_gas = _gas_meter > 0.0;
	
	if can_use_gas and Input.is_action_just_pressed("dash"):
		var dash_vector = movement * dash_power;
		
		# Don't drain the gas meter if we didn't dash.
		if dash_vector.length_squared() > 0.0:
			_velocity.x += dash_vector.x;
			_velocity.z += dash_vector.y;
			
			_gas_meter -= dash_cost;
			_show_gas = true;
	
	if is_on_floor():
		var speeding = _velocity.length() > max_walking_speed;
		
		# Don't apply movement speed if we're walking too fast.
		if not speeding:
			_velocity.x += movement.x * walking_acceleration * delta;
			_velocity.z += movement.y * walking_acceleration * delta; 
		
		# Simulate friction.
		
		var normal_abs = 9.8 * delta;
		
		# When the gas canister is on, we're sliding. Thus, the COF is changed.
		if can_use_gas and Input.is_action_pressed("gas_canister"):
			normal_abs *= sliding_friction;
		else:
			normal_abs *= walking_friction;
		
		_velocity -= _velocity.normalized() * normal_abs;
	
	if can_use_gas and Input.is_action_pressed("gas_canister"):
		var extra_velocity = movement.normalized() * gas_canister_boost * delta;
		
		_velocity.x += extra_velocity.x;
		_velocity.z += extra_velocity.y;
		
		_gas_meter -= gas_boost_cost * delta;
		_show_gas = true;
	
	var drag_force_abs = 0.5 * _velocity.length_squared() * drag_coefficient * delta;
	
	# Apply air resistance, converting to acceleration.
	_velocity -= _velocity.normalized() * drag_force_abs / mass;
	
	_grapple(delta);
	
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
		
		_scroll_delta = 0.0;


func get_info():
	return {
		"origin": transform.origin,
		"hook_end": _hook_end,
		"show_gas": _show_gas,
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
	var can_hit = cast_ray(max_hook_rope_length);
	var can_use_gas = _gas_meter > 0.0;
	
	var hotspot = _cursor.get_size() / 2.0;
	
	var normal = Color(1.0, 1.0, 1.0);
	var red = Color(1.0, 0.0, 0.0);
	
	_shade_cursor(normal if can_hit and can_use_gas else red);
	
	# Convert to a texture usable as a cursor.
	var cursor = ImageTexture.new();
	cursor.create_from_image(_cursor);
	
	Input.set_custom_mouse_cursor(cursor, Input.CURSOR_ARROW, hotspot);


func _update_ui():
	var gas_meter = $UI/BottomRight/GasMeter;
	gas_meter.value = _gas_meter / starting_gas_capacity;
	
	var gas_gauge_format = "%.2f / %.2f" % [_gas_meter, starting_gas_capacity];
	gas_meter.get_node("Gauge").text = gas_gauge_format;
	
	var speedometer = $UI/BottomRight/Speedometer;
	var velocity_coefficient = _velocity.length() / red_velocity;
	
	speedometer.value = velocity_coefficient;
	
	var speedometer_color = Color(0.0, 0.5, 0.0);
	
	if velocity_coefficient > 0.5:
		speedometer_color.r = min(velocity_coefficient - 0.5, 1.0);
	
	if velocity_coefficient > 1.0:
		speedometer_color.g = min(velocity_coefficient - 1.0, 0.0);
	
	speedometer["custom_styles/fg"].bg_color = speedometer_color;
	
	speedometer.get_node("Gauge").text = "%.2f m/s" % _velocity.length();
	
	var position_label = $UI/Position;
	
	var position = global_transform.origin;
	var format = "X: %.2f; Y: %.2f; Z: %.2f\nFPS: %.2f";
	
	var fps = Engine.get_frames_per_second();
	
	position_label.text = format % [position.x, position.y, position.z, fps];


func _adjust_for_camera(delta):
	# Turn the whole body for horizontal rotation.
	rotate_y(-_turn_direction);
	
	var arm = $SpringArm;
	
	# Only pan the camera arm.
	arm.rotate_x(-_pan_direction);
	
	# Zoom in/out.
	if Input.is_action_pressed("pan_camera"):
		arm.spring_length -= zoom_distance * delta * _scroll_delta;
		arm.spring_length = clamp(arm.spring_length, min_zoom, max_zoom);
	
	# Limit the rotation.
	arm.rotation.x = clamp(arm.rotation.x, -PI / 2.0, PI / 2.0);
	
	# Reset for the next frame.
	_turn_direction = 0.0;
	_pan_direction = 0.0;


func _grapple(delta):
	# Can't create a grappling hook without gas.
	var can_use_gas = _gas_meter > 0.0;
	
	# Prevent weird hook behaviour when the mouse is captured.
	var panning = Input.is_action_pressed("pan_camera");
	
	if Input.is_action_just_pressed("attach_hook"):
		_is_hook_on = not _is_hook_on; # toggle
	
	if _hook_end and not panning:
		# Fiddle with the hook length.
		_adjusted_rope_length -= hook_retraction_speed * delta * _scroll_delta;
		_adjusted_rope_length = clamp(_adjusted_rope_length, 1, max_hook_rope_length);
	
	# Break the hook if it gets too short.
	if _hook_end and get_rope_length() <= min_hook_rope_length:
		_is_hook_on = false;
	
	if not _is_hook_on:
		_hook_end = null;
		_hooked_entity = null;
		return;
	
	# Shift the hook's end according to the hooked entity's movement.
	if _hooked_entity:
		var their_position = _hooked_entity["them"].global_transform.origin;
		_hook_end = their_position + _hooked_entity["offset"];
	
	if _hook_end:
		var rope = _hook_end - global_transform.origin;
		var stretching_coefficient = get_rope_length() / _adjusted_rope_length;
		stretching_coefficient = min(stretching_coefficient, max_hook_rope_stretching);
		_velocity += rope.normalized() * 9.8 * stretching_coefficient * delta;
	elif not panning and can_use_gas:
		# Create a new grappling hook if it doesn't exist.
		var hook_target = cast_ray(max_hook_rope_length);
		
		if hook_target:
			_hook_end = hook_target["position"];
			_hooked_entity = {"them": hook_target["collider"]};
			
			# Calculate the hook's offset in the entity.
			if _hooked_entity["them"]:
				var their_transform = _hooked_entity["them"].global_transform;
				_hooked_entity["offset"] = _hook_end - their_transform.origin;
			
			_adjusted_rope_length = get_rope_length();
		else:
			_is_hook_on = false;


func get_rope_length():
	return (_hook_end - global_transform.origin).length();


# Cast a ray from mouse cursor position.
func cast_ray(length):
	var space = get_world().direct_space_state;
	
	var camera = $SpringArm/Camera;
	
	var from = camera.project_ray_origin(_mouse_position);
	var to = from + camera.project_ray_normal(_mouse_position) * length;
	
	return space.intersect_ray(from, to, [self]);
