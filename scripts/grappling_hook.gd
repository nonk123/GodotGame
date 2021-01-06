extends Spatial


# Rope's end point, in absolute coordinates.
var end;

# Used for drawing the line.
onready var material = SpatialMaterial.new();


func _ready():
	material.albedo_color = Color(0.0, 0.0, 0.0);


func _process(_delta):
	var rope = $Rope;
	var hook = $Rope/Hook;
	
	var start = Vector3(0.0, 0.5, 0.0);
	
	hook.global_transform.origin = end;
	
	var parent_rotation = get_parent_spatial().rotation;
	rope.rotation.y = -parent_rotation.y;
	
	rope.clear();
	rope.material_override = material;
	
	rope.begin(Mesh.PRIMITIVE_LINES);
	rope.add_vertex(start);
	rope.add_vertex(end - global_transform.origin);
	rope.end();
