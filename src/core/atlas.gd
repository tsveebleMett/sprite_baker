extends RefCounted
## Fixed cells preserve common pivots. Pages never split an individual frame.

static func layout(frame_count: int, directions: int, cell_size: Vector2i, max_size: int = 4096) -> Dictionary:
	if frame_count <= 0 or directions <= 0 or cell_size.x <= 0 or cell_size.y <= 0:
		return {}
	if max_size <= 0 or cell_size.x > max_size or cell_size.y > max_size:
		return {}
	if frame_count * directions > 1000000:
		return {}
	var columns := maxi(1, int(max_size / cell_size.x))
	var rows := maxi(1, int(max_size / cell_size.y))
	var pages: Array = []
	var frames: Array = []
	for direction_start in range(0, directions, rows):
		for frame_start in range(0, frame_count, columns):
			var page_columns := mini(columns, frame_count - frame_start)
			var page_rows := mini(rows, directions - direction_start)
			var page_index := pages.size()
			pages.append({"size": [page_columns * cell_size.x, page_rows * cell_size.y]})
			for row in page_rows:
				for column in page_columns:
					frames.append({
						"frame": frame_start + column,
						"direction": direction_start + row,
						"page": page_index,
						"rect": [column * cell_size.x, row * cell_size.y, cell_size.x, cell_size.y],
					})
	return {"pages": pages, "frames": frames}
