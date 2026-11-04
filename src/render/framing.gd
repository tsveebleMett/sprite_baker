extends RefCounted

const Sampling = preload("res://src/core/sampling.gd")

static func samples(config: Dictionary) -> Array:
	var result: Array = []
	for animation in config.animations:
		for time in Sampling.times(animation.start, animation.end, config.fps, animation.loop):
			for direction in int(config.profile.directions):
				result.append({"animation": animation, "time": time,
					"direction": direction * TAU / int(config.profile.directions)})
	return result

static func camera_bounds(vertices: PackedVector3Array, camera: Camera3D) -> AABB:
	var inverse := camera.global_transform.affine_inverse()
	var bounds := AABB(inverse * vertices[0], Vector3.ZERO)
	for vertex in vertices:
		bounds = bounds.expand(inverse * vertex)
	return bounds

static func fit(bounds: AABB, camera: Camera3D, profile: Dictionary) -> Dictionary:
	var result := profile.duplicate(true)
	var center := bounds.get_center()
	var target := camera.global_transform * center
	var aspect := float(profile.target_size[0]) / float(profile.target_size[1])
	result.camera_target = [target.x, target.y, target.z]
	result.camera_size = maxf(0.1, maxf(bounds.size.y, bounds.size.x / aspect) * 1.12)
	result.camera_distance = maxf(10.0, bounds.size.z + 2.0)
	result.near = 0.05
	result.far = result.camera_distance + bounds.size.z * 0.5 + 2.0
	result.locked = true
	# Every explicit fit creates a new compatibility identity for the entire family.
	result.id = "profile-" + JSON.stringify(result).sha256_text().substr(0, 16)
	return result

static func fits(bounds: AABB, camera: Camera3D, profile: Dictionary) -> bool:
	var height := camera.size
	var width := height * float(profile.target_size[0]) / float(profile.target_size[1])
	var tolerance := 0.00001
	return bounds.position.x >= -width * 0.5 - tolerance \
		and bounds.end.x <= width * 0.5 + tolerance \
		and bounds.position.y >= -height * 0.5 - tolerance \
		and bounds.end.y <= height * 0.5 + tolerance \
		and -bounds.end.z >= camera.near - tolerance \
		and -bounds.position.z <= camera.far + tolerance
