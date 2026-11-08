class_name Grid
extends RefCounted
## Static coordinate math for a rectangular square grid.
##
## Pure functions only — no state, no engine access. Iteration orders are
## fixed and documented because they are part of the determinism contract:
## replays must never depend on incidental ordering.

## Cardinal directions in fixed clockwise order: north, east, south, west.
## This order is load-bearing — neighbor expansion order affects tie-breaking
## in pathfinding, which must be reproducible for replays.
const CARDINAL_DIRS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]


## Manhattan (taxicab) distance between `a` and `b`.
static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## The four cardinal neighbors of `c`, in CARDINAL_DIRS order (N, E, S, W).
## Not bounds-filtered — callers clip against map dimensions.
static func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in CARDINAL_DIRS:
		out.append(c + d)
	return out


## True if `c` lies inside a `width` x `height` grid with origin (0, 0).
static func in_bounds(c: Vector2i, width: int, height: int) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


## Row-major flat index of `c` in a grid `width` tiles wide.
static func idx(c: Vector2i, width: int) -> int:
	return c.y * width + c.x


## Inverse of idx(): the coord for row-major flat index `i`. Requires i >= 0.
static func from_idx(i: int, width: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(i % width, i / width)


## All coords whose manhattan distance from `center` lies in
## [min_range, max_range] — the diamond annulus used for attack and vision
## ranges. Requires 0 <= min_range <= max_range. Not bounds-filtered.
## Deterministic order: row by row top to bottom, left to right within a row.
static func coords_in_range(center: Vector2i, min_range: int, max_range: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy: int in range(-max_range, max_range + 1):
		var span: int = max_range - absi(dy)
		for dx: int in range(-span, span + 1):
			if absi(dx) + absi(dy) >= min_range:
				out.append(center + Vector2i(dx, dy))
	return out
