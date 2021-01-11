class_name Generator
extends Spatial


# World size in meters.
export(float) var world_size = 1024.0

# World height in meters.
export(float) var world_height = 256.0

# Seed used in generating this world.
var world_seed


func _ready():
	seed(world_seed)


# Take a point in the XZ plane and return the snapped Vector3.
# Operates on global coordinates.
func snap_to_the_ground(point_xz):
	var from = Vector3(point_xz.x, world_height, point_xz.y)
	var to = Vector3(point_xz.x, -1.0, point_xz.y)
	
	var space = get_world().direct_space_state
	var intersection = space.intersect_ray(from, to)
	
	if intersection:
		return intersection["position"]
