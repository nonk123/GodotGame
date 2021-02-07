extends Spatial


# Rope's start in global coordinates.
var rope_start

onready var rope = $Rope


func _ready():
	rope.material_override = SpatialMaterial.new()


func _process(_delta):
	var relative_end = rope_start - global_transform.origin
	var relative_start = Vector3()
	
	var parent_rotation = get_parent_spatial().rotation
	rope.rotation.y = -parent_rotation.y
	
	rope.clear()
	rope.material_override.albedo_color = Color(0.0, 0.0, 0.0)
	
	rope.begin(Mesh.PRIMITIVE_LINES)
	rope.add_vertex(relative_start)
	rope.add_vertex(relative_end)
	rope.end()


# Return the parent's (and thus, the hook's) velocity.
func get_velocity():
	var parent = get_parent()
	
	if "velocity" in parent:
		return parent.velocity
	else:
		return Vector3() # assumes the parent is a static body
