extends Spatial


# Rope's start in global coordinates.
var rope_start

onready var _rope = $Rope


func _ready():
	_rope.material_override = SpatialMaterial.new()


func _process(_delta):
	var relative_end = rope_start - global_transform.origin
	var relative_start = Vector3()
	
	var parent_rotation = get_parent_spatial().rotation
	_rope.rotation.y = -parent_rotation.y
	
	_rope.clear()
	_rope.material_override.albedo_color = Color(0.0, 0.0, 0.0)
	
	_rope.begin(Mesh.PRIMITIVE_LINES)
	_rope.add_vertex(relative_start)
	_rope.add_vertex(relative_end)
	_rope.end()


# Return the parent's (and thus, the hook's) velocity.
func get_velocity():
	var parent = get_parent()
	
	if "velocity" in parent:
		return parent.velocity
	else:
		return Vector3() # assumes the parent is a static body
