extends RefCounted
## CPU counterpart of skeletal deformation, used only for fit and clipping checks.

static func validate_skin(instance: MeshInstance3D) -> String:
	var skeleton := instance.get_node_or_null(instance.skeleton) as Skeleton3D
	var skin := instance.skin
	if skin != null:
		if skeleton == null:
			return "Skin has no valid Skeleton3D."
		for bind in range(skin.get_bind_count()):
			var name := skin.get_bind_name(bind)
			var bone := skeleton.find_bone(name) if not name.is_empty() else skin.get_bind_bone(bind)
			if bone < 0 or bone >= skeleton.get_bone_count():
				return "Skin references a missing bone."
	for surface in range(instance.mesh.get_surface_count()):
		var arrays := instance.mesh.surface_get_arrays(surface)
		var bones = arrays[Mesh.ARRAY_BONES]
		if bones == null or bones.is_empty():
			continue
		if skeleton == null:
			return "Weighted geometry has no valid Skeleton3D."
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if weights == null or weights.size() != bones.size() or vertices.is_empty():
			return "Skin weights are malformed."
		var stride: int = bones.size() / vertices.size()
		if stride not in [4, 8] or bones.size() != stride * vertices.size():
			return "Skin must have four or eight influences per vertex."
		var bind_count := skin.get_bind_count() if skin != null else skeleton.get_bone_count()
		for vertex in range(vertices.size()):
			var total := 0.0
			for influence in range(stride):
				var offset := vertex * stride + influence
				var weight := float(weights[offset])
				if not is_finite(weight) or weight < 0.0:
					return "Skin weights must be finite and nonnegative."
				if weight > 0.0 and (bones[offset] < 0 or bones[offset] >= bind_count):
					return "Skin references an invalid bind index."
				total += weight
			if absf(total - 1.0) > 0.001:
				return "Skin weights must sum to one for every vertex."
	return ""

static func vertices(instance: MeshInstance3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	if instance.mesh == null:
		return result
	var skeleton := instance.get_node_or_null(instance.skeleton) as Skeleton3D
	var skin := instance.skin
	if skeleton != null and skin == null:
		skin = skeleton.create_skin_from_rest_transforms()
	for surface in range(instance.mesh.get_surface_count()):
		var arrays := instance.mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		points = _blend_shapes(instance, surface, points)
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var skinned := skeleton != null and skin != null and bones != null and weights != null
		var stride: int = bones.size() / points.size() if skinned and not points.is_empty() else 0
		for index in range(points.size()):
			if skinned and stride > 0:
				result.append(instance.global_transform * _skin_point(points[index], index, stride, bones, weights, skeleton, skin))
			else:
				result.append(instance.global_transform * points[index])
	return result

static func _skin_point(point: Vector3, index: int, stride: int, bones,
		weights, skeleton: Skeleton3D, skin: Skin) -> Vector3:
	var result := Vector3.ZERO
	var total := 0.0
	for influence in range(stride):
		var offset := index * stride + influence
		var weight := float(weights[offset])
		var bind := int(bones[offset])
		if weight <= 0.0 or bind < 0 or bind >= skin.get_bind_count():
			continue
		var bone_name := skin.get_bind_name(bind)
		var bone := skeleton.find_bone(bone_name) if not bone_name.is_empty() else skin.get_bind_bone(bind)
		if bone < 0 or bone >= skeleton.get_bone_count():
			continue
		result += (skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind) * point) * weight
		total += weight
	if total <= 0.0:
		result = point
	# Godot's skeleton compute pass writes deformed vertices in mesh-local space;
	# the spatial pass subsequently applies the MeshInstance's model transform.
	return result

static func _blend_shapes(instance: MeshInstance3D, surface: int,
		points: PackedVector3Array) -> PackedVector3Array:
	if not instance.mesh is ArrayMesh or instance.mesh.get_blend_shape_count() == 0:
		return points
	var output := points.duplicate()
	var shapes := instance.mesh.surface_get_blend_shape_arrays(surface)
	for shape in range(shapes.size()):
		var weight := instance.get_blend_shape_value(shape)
		if is_zero_approx(weight):
			continue
		var values: PackedVector3Array = shapes[shape][Mesh.ARRAY_VERTEX]
		for vertex in range(output.size()):
			if instance.mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED:
				output[vertex] += (values[vertex] - points[vertex]) * weight
			else:
				output[vertex] += values[vertex] * weight
	return output
