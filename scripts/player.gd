extends KinematicBody

# A character accelerates by this much when he walks. In m * s^(-2).
export var walking_acceleration = 20.0

# A character cannot walk faster than this value. m/s.
export var max_walking_speed = 12.0

# Impulse applied when a jump is made. m/s.
export var jump_power = 15.0

# Impulse applied when the player dashes. m/s.
export var dash_power = 60.0

# Friction coefficient applied to walking.
export var walking_friction = 1.2

# Used in air resistance calculations. Not meant to be realistic.
export var drag_coefficient = 0.15

# Player's mass in kg (?). Only used in drag calculations.
export var mass = 10.0

# How many abstract units of gas can be held at a time.
export var max_gas_capacity = 100

# Regenerate this much gas every second
export var gas_regen = 0.5

# Doing a dash costs this much gas.
export var dash_cost = 5.0

# If the grappling hook rope gets this short, it snaps.
export var min_hook_rope_length = 5.0

# Maximum grappling distance, in meters.
export var max_hook_rope_length = 100.0

# How fast the hook retracts with each scroll, in m * u/s.
export var hook_retraction_speed = 20.0

# Higher values result in more tension.
export var hook_rope_stiffness = 1.2

# Maximum force the hook rope can withstand.
export var hook_rope_toughness = 200.0

# Relative mouse coordinates are scaled by this much when panning.
export var mouse_sensitivity = 0.01

# Each mouse wheel event registers this many scroll units.
export var scroll_sensitivity = 5.0

# How much to zoom in/out, in m * u/s.
export var zoom_distance = 3.0

# The camera arm cannot get shorter than this many meters.
export var min_zoom = 1.0

# The camera arm cannot get longer than this many meters.
export var max_zoom = 10.0

# Velocity vector used in physics calculations.
var velocity = Vector3()

# Mouse position for use in raycasting.
var mouse_position = Vector2()

# If positive, the player is turning right. If negative, turning left.
# Value of zero means no turning. Modified by mouse input.
var turn_direction = 0.0

# If positive, pan the camera upwards. If negative, pan downwards.
# Value of zero means no panning. Modified by mouse input.
var pan_direction = 0.0

# How much scrolling was requested.
var scroll_value = 0.0

# Hook rope length regulated with the scroll wheel.
var wound_rope_length = max_hook_rope_length

# Currently attached hook.
var hook_node

# How much gas we have at the moment.
var gas_meter = max_gas_capacity

# Custom cursor image.
var cursor_image = preload("res://textures/cursor.png")

# The cylinder color, bestowed upon us by the server.
var our_color

# Previously calculated drag acceleration for use in HUD metrics.
var _drag

# Used in calculating the hook's end position with the entity's movement.
var _last_hooked_entity_position

# Used to prevent re-shading the cursor every frame.
var _last_cursor_shade = Color()


func _ready():
	var our_material = SpatialMaterial.new()
	our_material.albedo_color = our_color
	
	if is_network_master():
		$SpringArm/Camera.make_current()
		add_child(preload("res://entities/hud.tscn").instance())
	
	$Shape/Model.material = our_material


# Only useful for mouse events.
func _input(event):
	if is_network_master():
		if event is InputEventMouseMotion:
			mouse_position = event.position
			
			if Input.is_action_pressed("pan_camera"):
				# Capture the mouse to properly control the camera.
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				
				turn_direction = event.relative.x * mouse_sensitivity
				pan_direction = event.relative.y * mouse_sensitivity
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		elif event is InputEventMouseButton:
			match event.button_index:
				BUTTON_WHEEL_UP:
					scroll_value += scroll_sensitivity
				BUTTON_WHEEL_DOWN:
					scroll_value -= scroll_sensitivity


func _physics_process(delta):
	# Each player runs their own physics routine, but not others'.
	if not is_network_master():
		return
	
	var want_to_reset = Input.is_action_just_pressed("reset_myself")
	var want_to_jump = Input.is_action_just_pressed("jump")
	var want_to_dash = Input.is_action_just_pressed("dash")
	
	if want_to_reset:
		reset()
	
	if is_on_floor() and want_to_jump:
		velocity.y += jump_power
	
	# Apply gravity.
	velocity.y -= 9.8 * delta
	
	if want_to_dash:
		try_to_dash()
	
	if is_on_floor():
		walk_by_sliding(delta)
	
	run_grappling_hook_updates(delta)
	
	_drag = velocity.normalized() * calculate_drag()
	velocity -= _drag * delta
	
	velocity = move_and_slide(velocity, Vector3(0.0, 1.0, 0.0))
	
	# Don't forget about gas regeneration.
	gas_meter += gas_regen * delta
	gas_meter = min(gas_meter, max_gas_capacity)
	
	rpc_unreliable("receive_physics", transform.origin)


func _process(delta):
	if hook_node:
		hook_node.rope_start = global_transform.origin
	
	# The rest accepts input.
	if not is_network_master():
		return
	
	var want_to_quit = Input.is_action_just_pressed("quit")
	
	if want_to_quit:
		get_tree().quit(0)
	
	pan_the_camera(delta)
	run_smart_cursor()
	update_hud()
	
	# Scroll value applies to the current frame only.
	scroll_value = 0.0


# Update everyone's instance of this player.
puppet func receive_physics(new_origin):
	transform.origin = new_origin


func try_to_dash():
	var dash_vector = get_movement_direction() * dash_power
	
	var we_dashed = dash_vector.length_squared() > 0.0
	var have_enough_gas = gas_meter >= dash_cost
	
	if we_dashed and have_enough_gas:
		velocity.x += dash_vector.x
		velocity.z += dash_vector.y
		
		rpc("drain_gas_meter", dash_cost)


func walk_by_sliding(delta):
	var movement = get_movement_direction() * walking_acceleration * delta
	
	var xz_velocity = Vector2(velocity.x, velocity.z)
	var cos_between = xz_velocity.normalized().dot(movement)
	
	# We can walk in the direction opposite of our velocity.
	var counteracting = cos_between <= 0.0
	var speeding = velocity.length() > max_walking_speed
	
	if counteracting or not speeding:
		velocity.x += movement.x
		velocity.z += movement.y
	
	# Simulate friction.
	var normal_acceleration = walking_friction * 9.8 * delta
	velocity -= velocity.normalized() * normal_acceleration


func calculate_drag():
	# Drag is a force, so we divide by mass to get acceleration.
	return 0.5 * velocity.length_squared() * drag_coefficient / mass


puppetsync func drain_gas_meter(by):
	var gas_node = get_node_or_null("Gas")
	
	if not gas_node:
		gas_node = preload("res://entities/gas.tscn").instance()
		add_child(gas_node)
	
	# Reset the gas effect's lifetime.
	gas_node.death_timer = 0.5
	
	gas_meter -= by
	gas_meter = max(0.0, gas_meter)


func reset():
	# With y == 0.0 you will get stuck if you're moving.
	translation = Vector3(0.0, 0.01, 0.0)
	velocity = Vector3()
	gas_meter = max_gas_capacity
	rpc("break_hook")


# Return movement vector in XZ plane. X = left/right, Y = forward/backward.
func get_movement_direction():
	var movement = Vector2()
	
	if Input.is_action_pressed("move_left"):
		movement.x -= 1.0
	
	if Input.is_action_pressed("move_right"):
		movement.x += 1.0
	
	# Keep in mind, the camera lines up with _negative_ Z.
	# Forwards is backwards in this case.
	
	if Input.is_action_pressed("move_forward"):
		movement.y -= 1.0
	
	if Input.is_action_pressed("move_backward"):
		movement.y += 1.0
	
	# Rotate to line up with the XZ plane.
	return movement.rotated(-rotation.y).normalized()


func run_smart_cursor():
	var can_hit = cast_ray(max_hook_rope_length)
	
	var hotspot = cursor_image.get_size() / 2.0
	
	var normal = Color(1.0, 1.0, 1.0)
	var red = Color(1.0, 0.0, 0.0)
	
	shade_cursor(normal if can_hit else red)
	
	# Convert to a texture usable as a cursor.
	var cursor_texture = ImageTexture.new()
	cursor_texture.create_from_image(cursor_image)
	
	Input.set_custom_mouse_cursor(cursor_texture, Input.CURSOR_ARROW, hotspot)


func update_hud():
	var gas_bar = $HUD/BottomRight/GasBar
	gas_bar.value = gas_meter / max_gas_capacity
	
	var gas_gauge_format = "%.2f / %.2f" % [gas_meter, max_gas_capacity]
	gas_bar.get_node("Gauge").text = gas_gauge_format
	
	var speedometer = $HUD/BottomRight/Speedometer
	speedometer.value = velocity.length()
	
	var speedometer_color = Color(0.0, 0.8, 0.0)
	
	var drag_factor = _drag.length() / (velocity.length() + _drag.length())
	
	speedometer_color.r = min(drag_factor, 1.0)
	
	if drag_factor > 0.5:
		speedometer_color.r = min(drag_factor, 1.0)
		speedometer_color.g = clamp(1 - drag_factor, 0.0, 1.0)
	
	speedometer["custom_styles/fg"].bg_color = speedometer_color
	
	speedometer.get_node("Gauge").text = "%.2f m/s" % velocity.length()
	
	var position = global_transform.origin
	var fps = Engine.get_frames_per_second()
	
	var format = "X: %.2f Y: %.2f Z: %.2f\nFPS: %.2f"
	
	$HUD/Position.text = format % [position.x, position.y, position.z, fps]


func pan_the_camera(delta):
	# Turn the whole body for horizontal rotation.
	rotate_y(-turn_direction)
	
	var arm = $SpringArm
	
	# Only pan the camera arm.
	arm.rotate_x(-pan_direction)
	
	# Zoom in/out.
	if Input.is_action_pressed("pan_camera"):
		arm.spring_length -= zoom_distance * delta * scroll_value
		arm.spring_length = clamp(arm.spring_length, min_zoom, max_zoom)
	
	# Limit the rotation.
	arm.rotation.x = clamp(arm.rotation.x, -PI / 2.0, PI / 2.0)
	
	# Reset for the next frame.
	turn_direction = 0.0
	pan_direction = 0.0


func run_grappling_hook_updates(delta):
	# Prevent weird hook behaviour when the mouse is captured.
	var panning = Input.is_action_pressed("pan_camera")
	
	if not panning:
		adjust_hook_length(delta)
	
	var want_to_attach = Input.is_action_just_pressed("attach_hook")
	
	if want_to_attach:
		var already_attached = hook_node
		var can_attach = not already_attached and not panning
		
		if already_attached:
			rpc("break_hook")
		elif can_attach:
			var target = cast_ray(max_hook_rope_length)
			
			if target:
				var collider_path = target["collider"].get_path()
				var end_position = target["position"]
				
				rpc("attach_hook", collider_path, end_position)
	
	if get_hook_end():
		var rope_direction = get_rope_vector().normalized()
		velocity += rope_direction * calculate_tension() * delta
		
		if velocity.length() > hook_rope_toughness:
			rpc("break_hook")


# Return the hook's end position, or null if it isn't attached.
func get_hook_end():
	if hook_node:
		return hook_node.global_transform.origin
	else:
		return null


func get_rope_vector():
	var hook_start = global_transform.origin
	return get_hook_end() - hook_start


func adjust_hook_length(delta):
	wound_rope_length -= hook_retraction_speed * scroll_value * delta
	wound_rope_length = clamp(wound_rope_length, min_hook_rope_length, max_hook_rope_length)


# Assumes there's no hook attached already.
puppetsync func attach_hook(collider_path, end_position):
	var collider = get_node(collider_path)
	
	hook_node = preload("res://entities/grappling_hook.tscn").instance()
	
	# Convert to relative coordinates.
	var their_position = collider.global_transform.origin
	hook_node.translate(end_position - their_position)
	
	collider.add_child(hook_node)
	
	wound_rope_length = get_rope_vector().length()


puppetsync func break_hook():
	if hook_node:
		hook_node.queue_free()


# Rope tension keeps the player in the air.
func calculate_tension():
	var rope = get_rope_vector()
	var theta = Vector3.UP.angle_to(rope)
	
	var total_velocity = velocity + hook_node.get_velocity()
	
	var centripetal = total_velocity.length_squared() / rope.length()
	var stretching = rope.length() / wound_rope_length
	var tension = centripetal * stretching * hook_rope_stiffness + 9.8 * sin(theta)
	
	return tension


# Cast a ray from mouse cursor position.
func cast_ray(length):
	var space = get_world().direct_space_state
	
	var camera = $SpringArm/Camera
	
	var from = camera.project_ray_origin(mouse_position)
	var to = from + camera.project_ray_normal(mouse_position) * length
	
	return space.intersect_ray(from, to, [self])


# Modify image data directly to replace non-transparent pixels with color.
func shade_cursor(color):
	# Don't re-shade into the same color.
	if _last_cursor_shade == color:
		return
	
	cursor_image.lock()
	
	for x in range(cursor_image.get_width()):
		for y in range(cursor_image.get_height()):
			if cursor_image.get_pixel(x, y).a == 1.0:
				cursor_image.set_pixel(x, y, color)
	
	cursor_image.unlock()
	
	_last_cursor_shade = color
