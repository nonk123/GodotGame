extends Spatial


# How many seconds does it take to go day -> night -> day.
export(float) var cycle_length = 600.0

# The time assigned to this node when it is created. Defaults to midday.
export(float) var starting_time = cycle_length / 4.0

# The minimum energy of the ambient light.
export(float, 0.0, 1.0) var minimum_light = 0.05

# The maximum energy of the ambient light.
export(float, 0.0, 1.0) var maximum_light = 0.95

# Time since day or night begun. Reset every time day comes.
onready var current_time = starting_time

onready var _light_node = $Light

onready var _environment = $Environment.environment


func _ready():
	_environment.background_sky.sun_longitude = 0.0


func _process(delta):
	var sun_angle = 2.0 * PI * current_time / cycle_length
	
	var energy = 0.5 * sin(sun_angle) + 0.5
	var light = clamp(energy, minimum_light, maximum_light)
	
	_environment.ambient_light_energy = light
	_light_node.light_energy = light
	
	# Rotate the light and the visible sun around.
	_light_node.rotation.x = sun_angle
	_environment.background_sky.sun_latitude = rad2deg(sun_angle)
	
	current_time += delta
	
	# The leftover time (e.g., if the frame took an hour to render) is
	# transferred onto the next day.
	while current_time >= cycle_length:
		current_time -= cycle_length
