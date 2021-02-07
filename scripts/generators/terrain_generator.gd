extends "generator.gd"


const HTerrain = preload("res://addons/zylann.hterrain/hterrain.gd")
const HTerrainData = preload("res://addons/zylann.hterrain/hterrain_data.gd")
const HTerrainTextureSet = preload("res://addons/zylann.hterrain/hterrain_texture_set.gd")

const TEXTURE_SET = preload("res://resources/terrain_textures.tres")

# The terrain occupies this much of world height.
const STEEPNESS = 0.4

# Scaling applied to the ground texture.
const UV_SCALE = 10.0


func _ready():
	var terrain_data = HTerrainData.new()
	terrain_data.resize(WORLD_SIZE + 1)
	
	var noisy = OpenSimplexNoise.new()
	noisy.seed = world_seed
	noisy.period = WORLD_SIZE / 2.0
	
	var heightmap = terrain_data.get_image(HTerrainData.CHANNEL_HEIGHT)
	
	heightmap.lock()
	
	for x in range(heightmap.get_width()):
		for y in range(heightmap.get_height()):
			var noise_value = noisy.get_noise_2d(x, y)
			var positive_noise_value = (noise_value + 1) * 0.5
			var height = positive_noise_value * WORLD_HEIGHT * STEEPNESS
			
			heightmap.set_pixel(x, y, Color(height, 0.0, 0.0))
	
	heightmap.unlock()
	
	var modified_region = Rect2(Vector2(), heightmap.get_size())
	terrain_data.notify_region_change(modified_region, HTerrainData.CHANNEL_HEIGHT)
	
	var terrain_node = HTerrain.new()
	terrain_node.name = "HTerrain"
	terrain_node.set_shader_type(HTerrain.SHADER_CLASSIC4_LITE)
	terrain_node.set_shader_param("u_ground_uv_scale", UV_SCALE)
	terrain_node.set_data(terrain_data)
	terrain_node.set_texture_set(TEXTURE_SET)
	terrain_node.set_chunk_size(16) # somehow results in a better framerate
	terrain_node.connect("ready", self, "_set_up_entity_spawn")
	add_child(terrain_node)


# Prevents entities from spawning underground.
func _set_up_entity_spawn():
	var entities = get_node("/root/World/Entities")
	var their_xz = Vector2(entities.translation.x, entities.translation.z)
	
	var snapped = snap_to_the_ground(their_xz)
	snapped.y += STEEPNESS
	
	entities.global_transform.origin = snapped
