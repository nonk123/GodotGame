extends Spatial


# Rope's start, in absolute coordinates.
# Currently attached to the parent node.
const start = Vector3();

# Rope's end point, in absolute coordinates.
var end;

# Material to draw the rope with.
var material;


func _ready():
	material = SpatialMaterial.new();
	material.albedo_color = Color(0.0, 0.0, 0.0, 1.0);


func _process(_delta):
	var rope = $Rope;
	
	rope.material_override = material;
	
	rope.clear();
	
	# Draw a line from current position to the end.
	rope.begin(Mesh.PRIMITIVE_LINES);
	
	var origin = get_parent_spatial().global_transform.origin;

	var parent_transform = get_parent_spatial().transform;
	var parent_y_rotation = parent_transform.basis.get_euler().y;
	
	var y_axis = Vector3(0.0, 1.0, 0.0);
	
	# Adjust to local coordinates.
	var relative_end = (end - origin).rotated(y_axis, -parent_y_rotation);
	
	rope.add_vertex(Vector3());
	rope.add_vertex(relative_end);
	
	rope.end();
