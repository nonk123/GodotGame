extends "generator.gd"


# How much of the world is filled with trees.
const DENSITY = 0.5

# The minimum spacing between each tree.
const PRIVATE_SPACE = 4.0

# Each tree is buried this deep into the ground.
const SINKING_IN = 1.0

# Deduced from DENSITY.
const TREES_COUNT = WORLD_SIZE * DENSITY

# Trees generated so far.
var points = []

# The tree mesh generated from CSG.
var mesh

# The collision shape each tree has.
var tree_shape

onready var trees = $Trees

onready var colliders = $Colliders


func _ready():
	prepare_mesh()
	generate()


# Extract the mesh from the CSGCombiner node.
func prepare_mesh():
	var csg = $Tree
	
	csg._update_shape()
	mesh = csg.get_meshes()[1]
	
	tree_shape = mesh.create_convex_shape()
	
	trees.multimesh = MultiMesh.new()
	
	trees.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	trees.multimesh.instance_count = TREES_COUNT
	
	trees.multimesh.mesh = mesh
	
	csg.queue_free()


func generate():
	# Create a margin around the world borders.
	var min_coordinate = PRIVATE_SPACE
	var max_coordinate = WORLD_SIZE - PRIVATE_SPACE
	
	# Brute-force approach to non-overlapping circles.
	while len(points) < int(TREES_COUNT):
		var x = rand_range(min_coordinate, max_coordinate)
		var y = rand_range(min_coordinate, max_coordinate)
		
		var point = Vector2(x, y)
		
		if placement_allowed(point):
			add_tree(point)
			points.append(point)


func placement_allowed(point):
	for other_point in points:
		if point.distance_to(other_point) <= PRIVATE_SPACE:
			return false
	
	return true


func add_tree(point):
	var position = snap_to_the_ground(point) + Vector3.DOWN * SINKING_IN
	
	var id = len(points)
	var transform = Transform(Basis.IDENTITY, position)
	
	trees.multimesh.set_instance_transform(id, transform)
	
	var shape_owner = colliders.create_shape_owner(self)
	colliders.shape_owner_add_shape(shape_owner, tree_shape)
	colliders.shape_owner_set_transform(shape_owner, transform)
