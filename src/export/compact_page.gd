extends RefCounted
## Lossless shared-channel crop. Offsets stay in the locked export canvas.
## Godot's native atlas packer supplies placement; no per-consumer repacking.
static func pack(images: Array, frames: Array, canvas: Array, maximum: int = 4096) -> Dictionary:
	var crops: Array[Rect2i] = []
	var sizes: Array[Vector2i] = []
	for frame in frames:
		var original := Rect2i(int(frame.rect[0]), int(frame.rect[1]), int(frame.rect[2]), int(frame.rect[3]))
		var bounds := Rect2i()
		for image: Image in images:
			var used := image.get_region(original).get_used_rect()
			if used.has_area():
				bounds = bounds.merge(used) if bounds.has_area() else used
		frame["empty"] = not bounds.has_area()
		if not bounds.has_area():
			bounds = Rect2i(0, 0, 1, 1)
		frame["offset"] = [bounds.position.x, bounds.position.y]
		frame["source_size"] = canvas.duplicate()
		crops.append(Rect2i(original.position + bounds.position, bounds.size))
		sizes.append(bounds.size)
	var atlas: Dictionary = Geometry2D.make_atlas(sizes)
	var points: Array = []
	var extent := Vector2i.ZERO
	for i in frames.size():
		var position := Vector2i(atlas.points[i])
		# Preserve a valid bounded placement for pathological very wide/tall input.
		if atlas.size.x > maximum or atlas.size.y > maximum:
			position = Vector2i(frames[i].rect[0], frames[i].rect[1])
		points.append(position)
		extent = extent.max(position + crops[i].size)
	var packed: Array = []
	for image: Image in images:
		var output := Image.create(extent.x, extent.y, false, Image.FORMAT_RGBA8)
		output.fill(Color.TRANSPARENT)
		for i in frames.size():
			if not frames[i].empty:
				output.blit_rect(image, crops[i], points[i])
		packed.append(output)
	for i in frames.size():
		frames[i].rect = [points[i].x, points[i].y, crops[i].size.x, crops[i].size.y]
	return {"images": packed, "size": [extent.x, extent.y]}
