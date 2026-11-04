extends RefCounted

const Passes = preload("res://src/render/material_passes.gd")
var viewport: SubViewport
var camera: Camera3D
var world: Node3D
var materials = Passes.new()
var error := ""

func setup(parent: Node, config: Dictionary, asset: Node3D) -> void:
	viewport = SubViewport.new()
	viewport.name = "BakeViewport"
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	viewport.use_debanding = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	parent.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	world.add_child(asset)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0, 0, 0, 0)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = config.get("lighting", {}).get("ambient", 0.4)
	settings.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	settings.tonemap_exposure = 1.0
	settings.glow_enabled = false
	settings.ssao_enabled = false
	settings.ssil_enabled = false
	settings.ssr_enabled = false
	environment.environment = settings
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = config.get("lighting", {}).get("energy", 1.0)
	light.shadow_enabled = true
	world.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	world.add_child(camera)
	camera.current = true
	set_profile(config.profile)

func set_profile(profile: Dictionary) -> void:
	viewport.size = Vector2i(int(profile.target_size[0]), int(profile.target_size[1])) * int(profile.supersample)
	var target := Vector3(profile.camera_target[0], profile.camera_target[1], profile.camera_target[2])
	var elevation := deg_to_rad(float(profile.elevation))
	var azimuth := deg_to_rad(float(profile.azimuth))
	var offset := Vector3(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation))
	camera.position = target + offset * float(profile.camera_distance)
	camera.look_at(target, Vector3.UP)
	camera.size = profile.camera_size
	camera.near = profile.near
	camera.far = profile.far

func capture(kind: int) -> Image:
	materials.apply(kind)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image != null and not image.is_empty():
		image.convert(Image.FORMAT_RGBA8)
	return image

func restore_preview() -> void:
	materials.apply(0)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func dispose() -> void:
	if is_instance_valid(viewport):
		viewport.free()

func projected_pivot() -> Array:
	var pivot := camera.unproject_position(Vector3.ZERO)
	return [pivot.x, pivot.y]
