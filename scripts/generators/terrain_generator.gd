extends "res://scripts/generators/generator.gd"


const HTerrain = preload("res://addons/zylann.hterrain/hterrain.gd")
const HTerrainData = preload("res://addons/zylann.hterrain/hterrain_data.gd")
const HTerrainTextureSet = preload("res://addons/zylann.hterrain/hterrain_texture_set.gd")

const texture_set = preload("res://resources/terrain_textures.tres")

# The terrain occupies this much of world height.
export(float) var steepness = 0.3

# Scaling applied to the ground texture.
export(float) var uv_scale = 10.0

# OpenSimplexNoise instance currently in use
var _noise


func _ready():
	var terrain_data = HTerrainData.new()
	terrain_data.resize(int(world_size) + 1)
	
	var heightmap = terrain_data.get_image(HTerrainData.CHANNEL_HEIGHT)
	var normalmap = terrain_data.get_image(HTerrainData.CHANNEL_NORMAL)
	var splatmap = terrain_data.get_image(HTerrainData.CHANNEL_SPLAT)
	
	_noise = OpenSimplexNoise.new()
	_noise.seed = get_parent().current_seed
	_noise.period = world_size / 2.0
	
	heightmap.lock()
	normalmap.lock()
	splatmap.lock()
	
	for x in range(heightmap.get_width()):
		for y in range(heightmap.get_height()):
			var height = noise(x, y)
			heightmap.set_pixel(x, y, Color(height, 0.0, 0.0))
			
			var height_right = noise(x + 1.0, y)
			var height_forward = noise(x, y + 1.0)
			
			# No idea how this formula works, but OK.
			var normal = Vector3(height - height_right, 1.0, height_forward - height).normalized()
			normalmap.set_pixel(x, y, HTerrainData.encode_normal(normal))
			
			var slope = 4.0 * normal.dot(Vector3.UP) - 2.0
			var their_pixel = splatmap.get_pixel(x, y)
			splatmap.set_pixel(x, y, their_pixel * slope)
	
	heightmap.unlock()
	normalmap.unlock()
	splatmap.unlock()
	
	var modified_region = Rect2(Vector2(), heightmap.get_size())
	
	terrain_data.notify_region_change(modified_region, HTerrainData.CHANNEL_HEIGHT)
	terrain_data.notify_region_change(modified_region, HTerrainData.CHANNEL_NORMAL)
	terrain_data.notify_region_change(modified_region, HTerrainData.CHANNEL_SPLAT)
	
	var terrain_node = HTerrain.new()
	terrain_node.set_shader_type(HTerrain.SHADER_CLASSIC4)
	terrain_node.set_shader_param("u_ground_uv_scale", uv_scale)
	terrain_node.set_data(terrain_data)
	terrain_node.set_texture_set(texture_set)
	terrain_node.set_chunk_size(16) # somehow results in a better framerate
	add_child(terrain_node)
	
	var players = get_parent().get_node("Players")
	var their_translation = players.translation
	var their_xz = Vector2(their_translation.x, their_translation.z)
	
	# Players shouldn't spawn underground.
	var snapped = snap_to_the_ground(their_xz)
	snapped.y += steepness
	
	players.translation = snapped


# Return a noise value in terms of (intended) world height.
func noise(x, y):
	var noise_value = _noise.get_noise_2d(x, y)
	var positive_noise_value = (noise_value + 1) * 0.5
	var height = positive_noise_value * world_height * steepness
	
	return height
