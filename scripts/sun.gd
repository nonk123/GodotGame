extends Spatial


# How many seconds does it take to go day -> night -> day.
const CYCLE_LENGTH = 600.0

# The minimum energy of the ambient light.
const MINIMUM_LIGHT = 0.05

# The maximum energy of the ambient light.
const MAXIMUM_LIGHT = 0.95

# Time since day or night begun. Reset every time day comes. Default: midday.
puppetsync var current_time = CYCLE_LENGTH / 4.0

onready var light_node = $Light

onready var environment = $Environment.environment


func _ready():
	environment.background_sky.sun_longitude = 0.0


func _process(delta):
	var sun_angle = 2.0 * PI * current_time / CYCLE_LENGTH
	
	var energy = 0.5 * sin(sun_angle) + 0.5
	var light = clamp(energy, MINIMUM_LIGHT, MAXIMUM_LIGHT)
	
	environment.ambient_light_energy = light
	light_node.light_energy = light
	
	# Rotate the light and the visible sun around.
	light_node.rotation.x = sun_angle
	environment.background_sky.sun_latitude = rad2deg(sun_angle)
	
	while current_time >= CYCLE_LENGTH:
		current_time -= CYCLE_LENGTH
	
	if get_tree().network_peer and is_network_master():
		rset_unreliable("current_time", current_time + delta)
