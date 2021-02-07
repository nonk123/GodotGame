extends "generator.gd"


# How much of the world is filled with trees.
const DENSITY = 0.1

# Minimum spacing between each tree.
const PRIVATE_SPACE = 32.0

# Each tree is placed this deep into the ground.
const SINKING_IN = 3.0

# Trees generated so far.
var _points = []


func _ready():
	# Create a margin around the world borders.
	var min_coordinate = PRIVATE_SPACE
	var max_coordinate = WORLD_SIZE - PRIVATE_SPACE
	
	var trees_count = WORLD_SIZE * DENSITY
	
	# Brute-force approach to non-overlapping circles.
	while len(_points) < int(trees_count):
		var x = rand_range(min_coordinate, max_coordinate)
		var y = rand_range(min_coordinate, max_coordinate)
		
		var point = Vector2(x, y)
		
		if placement_allowed(point):
			_points.append(point)
			add_tree(point)


func placement_allowed(point):
	for other_point in _points:
		if point.distance_to(other_point) <= PRIVATE_SPACE:
			return false
	
	return true


func add_tree(point):
	var node = preload("res://entities/big_tree.tscn").instance()
	var position = snap_to_the_ground(point)
	
	node.translate(position + Vector3.DOWN * SINKING_IN)
	node.rotate_y(TAU * randf()) # random rotation in radians
	
	add_child(node)
