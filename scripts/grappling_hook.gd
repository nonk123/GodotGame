extends Generic6DOFJoint

# Rope's end point, in absolute coordinates.
var end = Vector3();

# Rope's start, in absolute coordinates.
# Currently attached to the parent node.
var start setget ,get_start;

# Material to draw the rope with.
var material;

# Hook rope's length.
var length setget ,get_length;


func _ready():
	material = SpatialMaterial.new();
	material.albedo_color = Color(0.0, 0.0, 0.0, 1.0);


func _process(delta):
	var rope = $Rope;
	
	rope.material_override = material;
	
	rope.clear();
	
	# Draw a line from current position to the end.
	rope.begin(Mesh.PRIMITIVE_LINES);
	
	# Adjust to local coordinates.
	var origin = get_parent_spatial().transform.origin;
	var y_axis = Vector3(0.0, 1.0, 0.0);
	var parent_transform = get_parent_spatial().transform;
	var parent_y_rotation = parent_transform.basis.get_euler().y;
	
	var actual_end = (end - origin).rotated(y_axis, -parent_y_rotation);
	
	rope.add_vertex(Vector3());
	rope.add_vertex(actual_end);
	
	rope.end();


func get_start():
	return get_parent_spatial().transform.origin;


func get_length():
	return (self.end - self.start).length();
