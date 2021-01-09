extends "res://scripts/generators/generator.gd"


# How much of the world is filled with trees.
export(float) var density = 0.05

# Minimum spacing between each tree.
export(float) var private_space = 32.0

# Each tree is placed this deep into the ground.
export(float) var sinking_in = 3.0

# Trees generated so far. They are instantiated after the array is filled.
var _points = []


func _ready():
	# Create a margin around the world borders.
	var min_coordinate = private_space
	var max_coordinate = world_size - private_space
	
	var trees_count = world_size * density
	
	# Brute-force approach to non-overlapping circles.
	while len(_points) < int(trees_count):
		var x = rand_range(min_coordinate, max_coordinate)
		var y = rand_range(min_coordinate, max_coordinate)
		
		var point = Vector2(x, y)
		
		if placement_allowed(point):
			_points.append(point)
	
	for point in _points:
		var position = snap_to_the_ground(point)
		var node = preload("res://entities/big_tree.tscn").instance()
		
		node.translate(position + Vector3.DOWN * sinking_in)
		node.rotate_y(2 * PI * randf()) # random rotation in radians
		
		add_child(node)


func placement_allowed(point):
	for other_point in _points:
		if point.distance_to(other_point) <= private_space:
			return false
	
	return true
