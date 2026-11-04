extends RefCounted
## Owns an isolated model instance. Sampling never advances live gameplay.

const Demo = preload("res://src/scene/demo.gd")
const Geometry = preload("res://src/scene/posed_geometry.gd")

var root: Node3D
var error := ""
var parts: Dictionary = {}
var players: Array[AnimationPlayer] = []
var skeletons: Array[Skeleton3D] = []
var _meshes: Array[MeshInstance3D] = []
var _rest_nodes: Dictionary = {}
var _rig_targets: Dictionary = {}
var _part_offsets: Dictionary = {}
var _rest_blends: Dictionary = {}

func load_asset(config: Dictionary) -> bool:
	dispose()
	error = ""
	root = _load_source(str(config.get("source", "")))
	if root == null:
		return false
	_collect(root)
	if not error.is_empty():
		return _fail(error)
	for item in config.get("parts", []):
		if not _register_part(item):
			return _fail(error)
	for selected in config.get("animations", []):
		var animation_name := str(selected.get("name", ""))
		if not animation_name.is_empty() and not _has_animation(animation_name):
			return _fail("Animation '%s' was not found in the source scene." % animation_name)
		for player in players:
			if not animation_name.is_empty() and player.has_animation(animation_name):
				var clip := player.get_animation(animation_name)
				if not _validate_animation(clip, animation_name):
					return _fail(error)
				var length := clip.length
				if float(selected.get("end", 0.0)) > length + 0.00001:
					return _fail("Animation '%s' ends at %.3fs; the requested range exceeds it." % [animation_name, length])
	for player in players:
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.autoplay = ""
		player.stop()
	_cache_transforms(root)
	show_part("")
	return true

func _validate_animation(clip: Animation, name: String) -> bool:
	var supported := [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D,
		Animation.TYPE_SCALE_3D, Animation.TYPE_BLEND_SHAPE]
	for track in range(clip.get_track_count()):
		if clip.track_is_enabled(track) and clip.track_get_type(track) not in supported:
			error = "Animation '%s' contains unsupported track '%s'. Only 3D position, rotation, scale and blend-shape tracks are supported." % [name, clip.track_get_path(track)]
			return false
	return true

func _load_source(path: String) -> Node3D:
	if path.begins_with("demo://"):
		var kind := path.trim_prefix("demo://")
		if kind not in ["creature", "item", "prop"]:
			error = "Unknown demo asset: " + kind
			return null
		return Demo.create(kind)
	if not path.begins_with("res://") or not ResourceLoader.exists(path):
		error = "Source scene was not imported into the project: " + path
		return null
	var resource := load(path)
	if not resource is PackedScene:
		error = "Source must be an imported 3D scene: " + path
		return null
	var instance: Node = resource.instantiate()
	if not instance is Node3D:
		instance.free()
		error = "Source scene root must be Node3D: " + path
		return null
	return instance as Node3D

func _collect(node: Node) -> void:
	# These imported scenes are data sources, not running game scenes.
	# Strip node scripts before they enter the tree so _ready cannot change a bake.
	if node.get_script() != null:
		node.set_script(null)
	if node is Camera3D:
		node.current = false
	if node is Light3D:
		node.visible = false
	if node is VisualInstance3D and not node is MeshInstance3D and not node is Light3D:
		error = "Unsupported source visual '%s' (%s). Convert it to MeshInstance3D before baking." % [node.name, node.get_class()]
	if node is WorldEnvironment:
		node.environment = null
		node.camera_attributes = null
	if node is MeshInstance3D and not _meshes.has(node):
		_meshes.append(node)
	if node is Skeleton3D and not skeletons.has(node):
		skeletons.append(node)
	if node is AnimationPlayer and not players.has(node):
		players.append(node)
	if node is AnimationTree:
		node.active = false
	if node is SkeletonModifier3D:
		node.active = false
	# Source scripts must not drive animation while a frame is captured.
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_collect(child)

func _register_part(definition: Dictionary) -> bool:
	var id := str(definition.get("id", ""))
	if id.is_empty() or parts.has(id):
		error = "Every part needs a unique nonempty id: " + id
		return false
	var part_root: Node3D
	if not str(definition.get("source", "")).is_empty():
		part_root = _attach_source(definition)
	else:
		var node_path := str(definition.get("node_path", ""))
		part_root = root.get_node_or_null(NodePath(node_path)) as Node3D
		if part_root == null:
			error = "Part '%s' refers to missing Node3D '%s'." % [id, node_path]
			return false
		_register_offset(part_root, definition)
	if part_root == null:
		return false
	var selected: Array[MeshInstance3D] = []
	_find_meshes(part_root, selected)
	if selected.is_empty():
		error = "Part '%s' contains no mesh geometry." % id
		return false
	for mesh in selected:
		if not _validate_mesh_ancestors(mesh, selected, id):
			return false
		if not _validate_mesh(mesh, id):
			return false
		for existing in parts.values():
			if existing.has(mesh):
				error = "Mesh '%s' belongs to more than one part." % mesh.name
				return false
	parts[id] = selected
	return true

func _validate_mesh_ancestors(mesh: MeshInstance3D, selected: Array[MeshInstance3D], part_id: String) -> bool:
	var ancestor: Node = mesh.get_parent()
	while ancestor != null:
		if ancestor is MeshInstance3D and not selected.has(ancestor):
			error = "Part '%s' has mesh ancestor '%s' outside the same part. Select the ancestor and its children as one part, or reparent the meshes under separate Node3D groups." % [part_id, root.get_path_to(ancestor)]
			return false
		if ancestor == root:
			break
		ancestor = ancestor.get_parent()
	return true

func _apply_offset(node: Node3D, definition: Dictionary) -> void:
	node.position += _vector(definition.get("position", [0, 0, 0]))
	node.rotation_degrees += _vector(definition.get("rotation_degrees", [0, 0, 0]))
	node.scale *= _vector(definition.get("scale", [1, 1, 1]))

func _register_offset(node: Node3D, definition: Dictionary) -> void:
	_part_offsets[node] = {"original": node.transform, "definition": definition.duplicate(true)}
	_apply_offset(node, definition)

func _validate_mesh(mesh: MeshInstance3D, part_id: String) -> bool:
	if mesh.mesh == null:
		error = "Part '%s' contains an empty mesh." % part_id
		return false
	if mesh.material_overlay != null:
		error = "Part '%s' uses a material overlay, which cannot be reproduced in data passes." % part_id
		return false
	for surface in range(mesh.mesh.get_surface_count()):
		var material := mesh.get_active_material(surface)
		if material is ShaderMaterial:
			error = "Custom ShaderMaterial is unsupported for reproducible data passes: " + part_id
			return false
		if material is BaseMaterial3D:
			if material.uv1_triplanar or material.heightmap_enabled or material.proximity_fade_enabled or material.grow or material.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED:
				error = "Part '%s' uses unsupported triplanar, heightmap, grow or fade material features." % part_id
				return false
			if material.transparency not in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR]:
				error = "Part '%s' uses blended transparency. Use opaque or alpha-scissor materials." % part_id
				return false
	if not Geometry.validate_skin(mesh).is_empty():
		error = "Part '%s': %s" % [part_id, Geometry.validate_skin(mesh)]
		return false
	return true

func _attach_source(definition: Dictionary) -> Node3D:
	var external := _load_source(str(definition.source))
	if external == null:
		return null
	external.name = "Part_" + str(definition.id)
	var bone_name := str(definition.get("attachment_bone", ""))
	var host: Node3D = root
	if not bone_name.is_empty():
		var rig := _find_bone_skeleton(bone_name)
		if rig == null:
			external.free()
			error = "Attachment bone '%s' was not found in the base rig." % bone_name
			return null
		var socket := BoneAttachment3D.new()
		socket.name = "Socket_" + str(definition.id)
		socket.bone_name = bone_name
		rig.add_child(socket)
		host = socket
	host.add_child(external)
	_register_offset(external, definition)
	if not _bind_external_rig(external, bone_name):
		external.free()
		return null
	_collect(external)
	if not error.is_empty():
		return null
	return external

func _bind_external_rig(external: Node3D, bone_name: String) -> bool:
	var external_rigs: Array[Skeleton3D] = []
	_find_rigs(external, external_rigs)
	if external_rigs.is_empty():
		return true
	if not bone_name.is_empty():
		error = "Skinned parts cannot also use a rigid bone attachment. Leave attachment_bone empty."
		return false
	if skeletons.is_empty():
		error = "Skinned equipment requires a compatible base Skeleton3D."
		return false
	var target := skeletons[0]
	for source in external_rigs:
		if not _compatible(source, target):
			return false
		if not _relative_transform(source).is_equal_approx(_relative_transform(target)):
			error = "Equipment skeleton transform differs from the base rig. Apply transforms before export."
			return false
		_rig_targets[source] = target
	var meshes: Array[MeshInstance3D] = []
	_find_meshes(external, meshes)
	for mesh in meshes:
		var source := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if source == null:
			continue
		var skin := mesh.skin.duplicate() as Skin if mesh.skin != null else source.create_skin_from_rest_transforms()
		for bind in range(skin.get_bind_count()):
			var name := str(skin.get_bind_name(bind))
			if name.is_empty():
				if skin.get_bind_bone(bind) < 0 or skin.get_bind_bone(bind) >= source.get_bone_count():
					error = "Equipment contains an invalid skin binding."
					return false
				name = source.get_bone_name(skin.get_bind_bone(bind))
			if target.find_bone(name) < 0:
				error = "Equipment skin references a missing bone: " + name
				return false
			skin.set_bind_name(bind, name)
			skin.set_bind_bone(bind, target.find_bone(name))
		mesh.skin = skin
		mesh.skeleton = mesh.get_path_to(target)
	# External players would otherwise compete with the family's animation.
	_disable_external_players(external)
	return true

func _relative_transform(node: Node3D) -> Transform3D:
	var result := node.transform
	var ancestor := node.get_parent()
	while ancestor != null and ancestor != root:
		if ancestor is Node3D:
			result = ancestor.transform * result
		ancestor = ancestor.get_parent()
	return result

func _compatible(source: Skeleton3D, target: Skeleton3D) -> bool:
	if source.get_bone_count() != target.get_bone_count():
		error = "Equipment skeleton has a different bone count; automatic retargeting is unsupported."
		return false
	for index in range(source.get_bone_count()):
		var name := source.get_bone_name(index)
		var destination := target.find_bone(name)
		if destination < 0 or not source.get_bone_rest(index).is_equal_approx(target.get_bone_rest(destination)):
			error = "Equipment bone '%s' has a missing or incompatible rest transform." % name
			return false
		var source_parent := source.get_bone_parent(index)
		var target_parent := target.get_bone_parent(destination)
		var source_parent_name := source.get_bone_name(source_parent) if source_parent >= 0 else ""
		var target_parent_name := target.get_bone_name(target_parent) if target_parent >= 0 else ""
		if source_parent_name != target_parent_name:
			error = "Equipment bone '%s' has an incompatible parent." % name
			return false
	return true

func _disable_external_players(node: Node) -> void:
	for child in node.get_children():
		if child is AnimationPlayer:
			child.free()
		else:
			_disable_external_players(child)

func _find_bone_skeleton(name: String) -> Skeleton3D:
	for rig in skeletons:
		if rig.find_bone(name) >= 0:
			return rig
	return null

func _find_rigs(node: Node, result: Array[Skeleton3D]) -> void:
	if node is Skeleton3D:
		result.append(node)
	for child in node.get_children():
		_find_rigs(child, result)

func _find_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_find_meshes(child, result)

func _cache_transforms(node: Node) -> void:
	if node is Node3D:
		_rest_nodes[node] = _part_offsets[node].original if _part_offsets.has(node) else node.transform
	if node is MeshInstance3D and node.mesh is ArrayMesh:
		var values: Array[float] = []
		for index in range(node.mesh.get_blend_shape_count()):
			values.append(node.get_blend_shape_value(index))
		_rest_blends[node] = values
	for child in node.get_children():
		_cache_transforms(child)

func discover() -> Dictionary:
	var nodes: Array[String] = []
	var bones: Array[String] = []
	var animations: Array[Dictionary] = []
	if root == null:
		return {"nodes": nodes, "bones": bones, "animations": animations}
	for mesh in _meshes:
		nodes.append(str(root.get_path_to(mesh)))
	for rig in skeletons:
		for index in range(rig.get_bone_count()):
			var name := str(rig.get_bone_name(index))
			if not bones.has(name):
				bones.append(name)
	var seen: Array[String] = []
	for player in players:
		for name in player.get_animation_list():
			if name == "RESET" or seen.has(name):
				continue
			seen.append(name)
			var animation := player.get_animation(name)
			animations.append({"name": name, "length": animation.length,
				"loop": animation.loop_mode != Animation.LOOP_NONE})
	return {"nodes": nodes, "bones": bones, "animations": animations}

func _has_animation(name: String) -> bool:
	for player in players:
		if player.has_animation(name):
			return true
	return false

func sample(animation: Dictionary, time: float, direction_radians: float) -> void:
	if root == null:
		return
	# Reset both node transforms and bone poses to avoid stale tracks between clips.
	for node in _rest_nodes:
		node.transform = _rest_nodes[node]
	for mesh in _rest_blends:
		for index in range(_rest_blends[mesh].size()):
			mesh.set_blend_shape_value(index, _rest_blends[mesh][index])
	for rig in skeletons:
		rig.reset_bone_poses()
	var name := str(animation.get("name", ""))
	for player in players:
		if not name.is_empty() and player.has_animation(name):
			player.play(name)
			player.seek(time, true, true)
	for node in _part_offsets:
		_apply_offset(node, _part_offsets[node].definition)
	root.transform = Transform3D(Basis(Vector3.UP, direction_radians), Vector3.ZERO) * root.transform
	for source in _rig_targets:
		var target: Skeleton3D = _rig_targets[source]
		for bone in range(source.get_bone_count()):
			var target_bone := target.find_bone(source.get_bone_name(bone))
			source.set_bone_pose(bone, target.get_bone_pose(target_bone))
	for rig in skeletons:
		rig.force_update_all_bone_transforms()
	_update_attachments(root)

func _update_attachments(node: Node) -> void:
	if node is BoneAttachment3D:
		node.on_skeleton_update()
	for child in node.get_children():
		_update_attachments(child)

func show_part(part_id: String) -> void:
	for mesh in _meshes:
		mesh.visible = false
	for id in parts:
		if part_id.is_empty() or id == part_id:
			for mesh in parts[id]:
				mesh.visible = true
				_show_parents(mesh)

func _show_parents(mesh: MeshInstance3D) -> void:
	var ancestor: Node = mesh.get_parent()
	while ancestor != null:
		if ancestor is Node3D and not ancestor is Light3D:
			ancestor.visible = true
		if ancestor == root:
			break
		ancestor = ancestor.get_parent()

func posed_vertices() -> PackedVector3Array:
	var result := PackedVector3Array()
	for meshes in parts.values():
		for mesh in meshes:
			result.append_array(Geometry.vertices(mesh))
	return result

func dispose() -> void:
	if is_instance_valid(root):
		root.free()
	root = null
	parts = {}
	players = []
	skeletons = []
	_meshes = []
	_rest_nodes = {}
	_rig_targets = {}
	_part_offsets = {}
	_rest_blends = {}

func _fail(message: String) -> bool:
	dispose()
	error = message
	return false

func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
