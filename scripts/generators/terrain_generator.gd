extends "generator.gd"


const HTerrain = preload("res://addons/zylann.hterrain/hterrain.gd")
const HTerrainData = preload("res://addons/zylann.hterrain/hterrain_data.gd")
const HTerrainTextureSet = preload("res://addons/zylann.hterrain/hterrain_texture_set.gd")

const texture_set = preload("res://resources/terrain_textures.tres")

# The terrain occupies this much of world height.
export(float) var steepness = 0.4

# Scaling applied to the ground texture.
export(float) var uv_scale = 10.0


func _ready():
	var terrain_data = HTerrainData.new()
	terrain_data.resize(int(world_size) + 1)
	
	var noisy = OpenSimplexNoise.new()
	noisy.seed = world_seed
	noisy.period = world_size / 2.0
	
	var heightmap = terrain_data.get_image(HTerrainData.CHANNEL_HEIGHT)
	
	heightmap.lock()
	
	for x in range(heightmap.get_width()):
		for y in range(heightmap.get_height()):
			var noise_value = noisy.get_noise_2d(x, y)
			var positive_noise_value = (noise_value + 1) * 0.5
			var height = positive_noise_value * world_height * steepness
			
			heightmap.set_pixel(x, y, Color(height, 0.0, 0.0))
	
	heightmap.unlock()
	
	var modified_region = Rect2(Vector2(), heightmap.get_size())
	terrain_data.notify_region_change(modified_region, HTerrainData.CHANNEL_HEIGHT)
	
	var terrain_node = HTerrain.new()
	terrain_node.name = "HTerrain"
	terrain_node.set_shader_type(HTerrain.SHADER_CLASSIC4_LITE)
	terrain_node.set_shader_param("u_ground_uv_scale", uv_scale)
	terrain_node.set_data(terrain_data)
	terrain_node.set_texture_set(texture_set)
	terrain_node.set_chunk_size(16) # somehow results in a better framerate
	terrain_node.connect("ready", self, "_set_up_player_spawn")
	add_child(terrain_node)


# Prevents players from spawning underground.
func _set_up_player_spawn():
	var players = get_node("/root/World/Players")
	var their_xz = Vector2(players.translation.x, players.translation.z)
	
	var snapped = snap_to_the_ground(their_xz)
	snapped.y += steepness
	
	players.global_transform.origin = snapped
