extends KinematicBody

# Gravity applied to the player, in m * s^(-2).
export var gravity = -20.0;

# Character movement speed in m/s.
export var movement_speed = 10;

# Movement speed while sprinting, in m/s.
export var sprint_speed = 20;

# Apply this much velocity when jumping.
export var jump_power = 20;

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


func _ready():
	# Capture the mouse.
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED);


# Only accept mouse events for now.
func _input(event):
	if event is InputEventMouseMotion:
		turn_direction = event.relative.x * mouse_sensitivity;
		pan_direction = event.relative.y * mouse_sensitivity;


func _physics_process(delta):
	if Input.is_action_just_pressed("quit"):
		get_tree().quit(0);
	
	# In m * s^(-1) by default, so we multiply by delta again.
	velocity.y += gravity * delta;
	
	var has_support = is_on_floor() || is_on_wall();
	
	if has_support && Input.is_action_just_pressed("jump"):
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
	
	velocity = move_and_slide(velocity, Vector3(0.0, 1.0, 0.0));


func _process(_delta):
	# Turn the whole body.
	rotate_y(-turn_direction);
	
	# Only pan the camera arm.
	$SpringArm.rotate_x(-pan_direction);
	
	# Limit the rotation.
	$SpringArm.rotation.x = clamp($SpringArm.rotation.x, -PI / 2.0, -PI / 8.0);
	
	# Reset for the next frame.
	turn_direction = 0.0;
	pan_direction = 0.0;
