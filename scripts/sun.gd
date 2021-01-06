extends Spatial


# How many seconds does daytime last. The same value applies to night.
# This basically says how long does a 180° rotation of the sun take.
export(float) var day_length = 360.0;

# The time assigned to this node when it is created. Defaults to midday.
export(float) var starting_time = day_length / 2.0;

# Distance from the center of this node to the sun.
export(float) var sun_distance = 512;

# The maximum energy of the light node.
export(float, 0.0, 1.0) var max_energy = 0.75;

# Time since day or night begun. Reset every time day comes.
onready var current_time = starting_time;

onready var _background_sky = $Environment.environment.background_sky;

onready var _light_node = $Support/Light;


func _ready():
	_light_node.translation.z = -sun_distance;
	_background_sky.sun_longitude = 0.0;


func _process(delta):
	# current_time is up to twice as large as day_length, which results in a
	# full circle, 2PI.
	var sun_angle = PI * current_time / day_length;
	
	# Starts off weak, reaches its peak during midday, and diminishes after.
	# A textbook definition of the sine function.
	var energy = sin(sun_angle);
	
	# If the sun angle is greater than PI, the sin becomes negative.
	# Under-the-ground sun is, well, the moon, which means night has come.
	_light_node.light_negative = energy < 0.0;
	# Shadows light up with negative on. We don't want that.
	_light_node.shadow_enabled = not _light_node.light_negative;
	# Light energy cannot be negative and has a limit.
	_light_node.light_energy = min(abs(energy), max_energy);
	
	# Rotate the light and the visible sun around.
	$Support.rotation.x = sun_angle;
	_background_sky.sun_latitude = rad2deg(sun_angle); # to Godot: why degrees?
	
	current_time += delta;
	
	# The leftover time (e.g., if the frame took an hour to render) is
	# transferred onto the next day.
	while current_time >= day_length * 2:
		current_time -= day_length * 2;
