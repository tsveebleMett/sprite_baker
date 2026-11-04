extends RefCounted
## Self-contained fixture: rigid bone attachments and a genuinely skinned cape.

static func default_parts(kind: String) -> Array:
	var body := _part("body", "body", "Body", 0, 0)
	if kind != "creature":
		return [body]
	return [body, _part("cape", "cape", "Cape", 1, 1),
		_part("helmet", "head", "Rig/HeadSocket/Helmet", 2, 2),
		_part("weapon", "hand", "Rig/HandSocket/Weapon", 3, 2)]

static func _part(id: String, slot: String, path: String, priority: int, region: int) -> Dictionary:
	return {"id": id, "slot": slot, "variant": "base", "node_path": path,
		"source": "", "attachment_bone": "", "position": [0, 0, 0],
		"rotation_degrees": [0, 0, 0], "scale": [1, 1, 1], "priority": priority,
		"regions": ["cloth", "leather", "metal"], "material_regions": {"0": region},
		"mask_texture": ""}

static func create(kind: String) -> Node3D:
	var result := Node3D.new()
	result.name = "Demo"
	var body := Node3D.new()
	body.name = "Body"
	result.add_child(body)
	if kind == "item":
		_sword(body)
		return result
	if kind == "prop":
		_prop(body)
		return result
	_creature(body)
	var rig := _rig()
	result.add_child(rig)
	_attachments(rig)
	result.add_child(_cape(rig))
	result.add_child(_animation_player())
	return result

static func _material(value: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(value, value, value)
	material.roughness = 0.72
	material.metallic = metallic
	return material

static func _mesh(parent: Node3D, name: String, mesh: Mesh, at: Vector3,
		value: float = 0.65) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = name
	result.mesh = mesh
	result.position = at
	result.material_override = _material(value)
	parent.add_child(result)
	return result

static func _box(parent: Node3D, name: String, size: Vector3, at: Vector3,
		value: float = 0.65) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, name, mesh, at, value)

static func _sphere(parent: Node3D, name: String, radius: float, at: Vector3,
		value: float = 0.65) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return _mesh(parent, name, mesh, at, value)

static func _creature(body: Node3D) -> void:
	var torso := CapsuleMesh.new()
	torso.radius = 0.32
	torso.height = 0.9
	_mesh(body, "Torso", torso, Vector3(0, 1.05, 0), 0.72)
	_sphere(body, "Head", 0.27, Vector3(0, 1.75, 0), 0.8)
	_box(body, "Belt", Vector3(0.65, 0.12, 0.49), Vector3(0, 0.8, 0), 0.35)
	for side in [-1.0, 1.0]:
		_box(body, "LegL" if side < 0 else "LegR", Vector3(0.22, 0.55, 0.26),
			Vector3(side * 0.18, 0.4, 0), 0.5)
		_box(body, "BootL" if side < 0 else "BootR", Vector3(0.26, 0.18, 0.4),
			Vector3(side * 0.18, 0.1, -0.06), 0.3)
		_box(body, "ArmL" if side < 0 else "ArmR", Vector3(0.18, 0.55, 0.22),
			Vector3(side * 0.42, 1.2, 0), 0.6)
	_box(body, "Eyes", Vector3(0.28, 0.055, 0.055), Vector3(0, 1.8, -0.25), 0.08)

static func _rig() -> Skeleton3D:
	var rig := Skeleton3D.new()
	rig.name = "Rig"
	for bone_name in ["root", "head", "hand.R", "cape"]:
		rig.add_bone(bone_name)
	for bone in range(1, 4):
		rig.set_bone_parent(bone, 0)
	rig.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, 1.75, 0)))
	rig.set_bone_rest(2, Transform3D(Basis.IDENTITY, Vector3(0.55, 1.25, 0)))
	rig.set_bone_rest(3, Transform3D(Basis.IDENTITY, Vector3(0, 1.4, 0.25)))
	rig.reset_bone_poses()
	return rig

static func _attachments(rig: Skeleton3D) -> void:
	var head := BoneAttachment3D.new()
	head.name = "HeadSocket"
	head.bone_name = "head"
	rig.add_child(head)
	var helmet := Node3D.new()
	helmet.name = "Helmet"
	head.add_child(helmet)
	_box(helmet, "Crown", Vector3(0.61, 0.28, 0.56), Vector3(0, 0.19, 0), 0.8)
	_box(helmet, "Ridge", Vector3(0.1, 0.18, 0.48), Vector3(0, 0.39, 0), 0.4)
	var alternate := Node3D.new()
	alternate.name = "HelmetAlt"
	head.add_child(alternate)
	_sphere(alternate, "Cap", 0.33, Vector3(0, 0.13, 0), 0.75)
	var hand := BoneAttachment3D.new()
	hand.name = "HandSocket"
	hand.bone_name = "hand.R"
	rig.add_child(hand)
	var weapon := Node3D.new()
	weapon.name = "Weapon"
	hand.add_child(weapon)
	_sword(weapon)

static func _sword(parent: Node3D) -> void:
	_box(parent, "Grip", Vector3(0.075, 0.28, 0.075), Vector3(0, 0.06, 0), 0.3)
	_box(parent, "Guard", Vector3(0.34, 0.06, 0.1), Vector3(0, 0.23, 0), 0.65)
	_box(parent, "Blade", Vector3(0.12, 0.75, 0.035), Vector3(0, 0.63, 0), 0.9)

static func _prop(body: Node3D) -> void:
	_box(body, "Crate", Vector3(1.2, 1.0, 1.2), Vector3(0, 0.5, 0), 0.55)
	for x in [-0.43, 0.43]:
		_box(body, "Band" + str(x), Vector3(0.12, 1.05, 1.25), Vector3(x, 0.52, 0), 0.3)
	_sphere(body, "Stone", 0.28, Vector3(0.1, 1.25, 0), 0.8)

static func _cape(rig: Skeleton3D) -> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.32, 1.5, 0.3), Vector3(0.32, 1.5, 0.3),
		Vector3(-0.43, 0.45, 0.38), Vector3(0.43, 0.45, 0.38)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 1, 2, 3])
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var cape := MeshInstance3D.new()
	cape.name = "Cape"
	cape.mesh = mesh
	cape.skeleton = NodePath("../Rig")
	var skin := Skin.new()
	skin.add_named_bind("root", rig.get_bone_global_rest(0).affine_inverse())
	skin.add_named_bind("cape", rig.get_bone_global_rest(3).affine_inverse())
	cape.skin = skin
	var material := _material(0.85)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cape.material_override = material
	return cape

static func _animation_player() -> AnimationPlayer:
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var animation := Animation.new()
	animation.length = 1.0
	animation.loop_mode = Animation.LOOP_LINEAR
	var hand := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(hand, NodePath("Rig:hand.R"))
	animation.position_track_insert_key(hand, 0.0, Vector3(0.55, 1.25, -0.65))
	animation.position_track_insert_key(hand, 0.5, Vector3(-0.3, 1.1, 0.65))
	animation.position_track_insert_key(hand, 1.0, Vector3(0.55, 1.25, -0.65))
	var cape := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(cape, NodePath("Rig:cape"))
	animation.rotation_track_insert_key(cape, 0.0, Quaternion(Vector3.RIGHT, -0.15))
	animation.rotation_track_insert_key(cape, 0.5, Quaternion(Vector3.RIGHT, 0.2))
	animation.rotation_track_insert_key(cape, 1.0, Quaternion(Vector3.RIGHT, -0.15))
	var library := AnimationLibrary.new()
	library.add_animation("idle", animation)
	player.add_animation_library("", library)
	return player
