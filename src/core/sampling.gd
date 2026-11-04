extends RefCounted
## Deterministic animation sampling independent of render frame rate.

const MAX_SAMPLES := 1000000

## Zero means invalid or too large. This never allocates the sample array.
static func sample_count(start: float, end: float, fps: float, loop: bool) -> int:
	if not is_finite(start) or not is_finite(end) or not is_finite(fps):
		return 0
	if fps <= 0.0 or start < 0.0 or end < start:
		return 0
	if is_equal_approx(start, end):
		return 1
	var frames: float = ceil((end - start) * fps - 0.0000001) + (0.0 if loop else 1.0)
	if not is_finite(frames) or frames < 1.0 or frames > MAX_SAMPLES:
		return 0
	return int(frames)

static func times(start: float, end: float, fps: float, loop: bool) -> Array[float]:
	var result: Array[float] = []
	var count := sample_count(start, end, fps, loop)
	if count == 0:
		return result
	if is_equal_approx(start, end):
		return [start]
	for index in count:
		result.append(end if not loop and index == count - 1 else start + float(index) / fps)
	return result
