class_name Generator
extends Spatial


# World size in meters.
const WORLD_SIZE = 1024

# World height in meters.
const WORLD_HEIGHT = 256.0

# Seed used in generating this world.
var world_seed


func _ready():
	seed(world_seed)


# Take a point in the XZ plane and return the snapped Vector3.
# Operates on global coordinates.
func snap_to_the_ground(point_xz):
	var from = Vector3(point_xz.x, WORLD_HEIGHT, point_xz.y)
	var to = Vector3(point_xz.x, -1.0, point_xz.y)
	
	var space = get_world().direct_space_state
	var intersection = space.intersect_ray(from, to)
	
	if intersection:
		return intersection["position"]
