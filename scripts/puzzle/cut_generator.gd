class_name CutGenerator
extends RefCounted
## Procedurally cuts a puzzle into piece outlines.
##
## Both styles share the same grid topology (cols x rows) so every interior
## edge is computed once and reused by the two pieces on either side of it,
## which guarantees neighbouring pieces fit exactly.

enum Style { RIBBON, RANDOM }

const STYLE_KEYS: Array[String] = ["RIBBON", "RANDOM"]
const STYLE_NAMES: Array[String] = ["Ribbon Cut", "Random Cut"]

## Line segments used to flatten each cubic Bézier of an edge (3 per edge).
const CURVE_STEPS := 8
## Max grid-vertex displacement for Random Cut, as a fraction of a cell.
const RANDOM_JITTER := 0.12


## Grid that gives close-to-square pieces for an image with `aspect` = w / h.
static func grid_for(target: int, aspect: float) -> Vector2i:
	var rows := maxi(1, roundi(sqrt(target / aspect)))
	var cols := maxi(1, roundi(target / float(rows)))
	return Vector2i(cols, rows)


static func style_from_key(key: String) -> int:
	var i := STYLE_KEYS.find(key)
	return i if i >= 0 else Style.RIBBON


## Returns { "outlines": Array[PackedVector2Array], "centers": PackedVector2Array }.
## Outlines are in puzzle coordinates (0..size); piece id = row * cols + col.
static func generate(cols: int, rows: int, size: Vector2, style: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cell := Vector2(size.x / cols, size.y / rows)
	var unit := minf(cell.x, cell.y)
	var random := style == Style.RANDOM
	var vstride := rows + 1

	# Grid vertices, index c * (rows + 1) + r. Border vertices only slide along the border.
	var verts := PackedVector2Array()
	verts.resize((cols + 1) * vstride)
	for c in cols + 1:
		for r in rows + 1:
			var p := Vector2(c * cell.x, r * cell.y)
			if random:
				if c > 0 and c < cols:
					p.x += rng.randf_range(-RANDOM_JITTER, RANDOM_JITTER) * cell.x
				if r > 0 and r < rows:
					p.y += rng.randf_range(-RANDOM_JITTER, RANDOM_JITTER) * cell.y
			verts[c * vstride + r] = p

	# Ribbon Cut: pieces alternate in a checkerboard between type A (tabs left
	# and right, blanks top and bottom) and type B (tabs top and bottom).
	# A sign of +1 pushes the knob along the edge normal, which points down for
	# horizontal edges and left for vertical edges.

	# Horizontal edges: index c * (rows + 1) + r, from vertex (c, r) to (c + 1, r).
	var h_edges: Array[PackedVector2Array] = []
	h_edges.resize(cols * vstride)
	for c in cols:
		for r in rows + 1:
			var a := verts[c * vstride + r]
			var b := verts[(c + 1) * vstride + r]
			if r == 0 or r == rows:
				h_edges[c * vstride + r] = PackedVector2Array([a, b])
				continue
			var s: float
			if random:
				s = 1.0 if rng.randf() < 0.5 else -1.0
			else:
				# Knob points down when the piece above is type B.
				s = 1.0 if (c + r - 1) % 2 == 1 else -1.0
			h_edges[c * vstride + r] = _edge(a, b, s, unit, random, rng)

	# Vertical edges: index c * rows + r, from vertex (c, r) to (c, r + 1).
	var v_edges: Array[PackedVector2Array] = []
	v_edges.resize((cols + 1) * rows)
	for c in cols + 1:
		for r in rows:
			var a := verts[c * vstride + r]
			var b := verts[c * vstride + r + 1]
			if c == 0 or c == cols:
				v_edges[c * rows + r] = PackedVector2Array([a, b])
				continue
			var s: float
			if random:
				s = 1.0 if rng.randf() < 0.5 else -1.0
			else:
				# Knob points left when the piece on the right is type A.
				s = 1.0 if (c + r) % 2 == 0 else -1.0
			v_edges[c * rows + r] = _edge(a, b, s, unit, random, rng)

	var outlines: Array[PackedVector2Array] = []
	var centers := PackedVector2Array()
	for r in rows:
		for c in cols:
			outlines.append(_piece_outline(c, r, cols, rows, h_edges, v_edges))
			centers.append((verts[c * vstride + r] + verts[(c + 1) * vstride + r]
					+ verts[(c + 1) * vstride + r + 1] + verts[c * vstride + r + 1]) * 0.25)

	# Repair: random jitter can occasionally make two knobs of one piece collide.
	# Re-cut the interior edges of any piece that is not a simple polygon with
	# progressively smaller knobs. Deterministic, since it continues the same RNG.
	var edge_scale := {}  # edge key -> knob scale
	var check: Array[int] = []
	for i in cols * rows:
		check.append(i)
	for pass_i in 8:
		var bad: Array[int] = []
		for id in check:
			if not _is_simple(outlines[id]):
				bad.append(id)
		if bad.is_empty():
			break
		var touched := {}
		for id in bad:
			var c := id % cols
			var r := id / cols
			# [key, is_horizontal, edge index, neighbour piece id]
			var edges := [
				["h%d" % (c * vstride + r), true, c * vstride + r, id - cols if r > 0 else -1],
				["h%d" % (c * vstride + r + 1), true, c * vstride + r + 1, id + cols if r < rows - 1 else -1],
				["v%d" % (c * rows + r), false, c * rows + r, id - 1 if c > 0 else -1],
				["v%d" % ((c + 1) * rows + r), false, (c + 1) * rows + r, id + 1 if c < cols - 1 else -1],
			]
			for e in edges:
				if e[3] < 0:
					continue  # border edge, already straight
				var k: float = edge_scale.get(e[0], 1.0) * 0.75
				edge_scale[e[0]] = k
				var list: Array[PackedVector2Array] = h_edges if e[1] else v_edges
				var old := list[e[2]]
				# Keep the knob direction: compare the midpoint offset sign.
				var a := old[0]
				var b := old[old.size() - 1]
				var n := Vector2(-(b - a).y, (b - a).x)
				var s := 1.0 if (old[old.size() / 2] - (a + b) * 0.5).dot(n) >= 0.0 else -1.0
				list[e[2]] = _edge(a, b, s, unit * k, random, rng, true)
				touched[id] = true
				touched[e[3]] = true
		check.clear()
		for id in touched:
			outlines[id] = _piece_outline(id % cols, id / cols, cols, rows, h_edges, v_edges)
			check.append(id)
	return { "outlines": outlines, "centers": centers }


## Appends an edge's points except its final point (the next edge starts there).
static func _piece_outline(c: int, r: int, cols: int, rows: int,
		h_edges: Array[PackedVector2Array], v_edges: Array[PackedVector2Array]) -> PackedVector2Array:
	var vstride := rows + 1
	var poly := PackedVector2Array()
	_append(poly, h_edges[c * vstride + r], false)        # top, left -> right
	_append(poly, v_edges[(c + 1) * rows + r], false)     # right, top -> bottom
	_append(poly, h_edges[c * vstride + r + 1], true)     # bottom, right -> left
	_append(poly, v_edges[c * rows + r], true)            # left, bottom -> top
	return poly


## True if the outline has no self-intersections. Checks only segments whose
## bounding boxes overlap, bucketed on a coarse grid, so it stays fast.
static func _is_simple(p: PackedVector2Array) -> bool:
	var n := p.size()
	var rect := Rect2(p[0], Vector2.ZERO)
	for q in p:
		rect = rect.expand(q)
	const BUCKETS := 8
	var bs := rect.size / BUCKETS + Vector2(0.001, 0.001)
	var grid := {}
	for i in n:
		var a := p[i]
		var b := p[(i + 1) % n]
		var lo := ((a.min(b) - rect.position) / bs).floor()
		var hi := ((a.max(b) - rect.position) / bs).floor()
		for gx in range(int(lo.x), int(hi.x) + 1):
			for gy in range(int(lo.y), int(hi.y) + 1):
				var key := gx * 64 + gy
				if not grid.has(key):
					grid[key] = []
				for j in grid[key]:
					if absi(i - j) <= 1 or absi(i - j) == n - 1:
						continue
					if Geometry2D.segment_intersects_segment(a, b, p[j], p[(j + 1) % n]) != null:
						return false
				grid[key].append(i)
	return true


static func _append(poly: PackedVector2Array, edge: PackedVector2Array, reversed: bool) -> void:
	var n := edge.size()
	if reversed:
		for i in range(n - 1, 0, -1):
			poly.append(edge[i])
	else:
		for i in n - 1:
			poly.append(edge[i])


## One interior edge with a knob. Based on the classic three-Bézier tab shape:
## the knob is positioned along the edge in absolute units and sized by `unit`
## (the smaller cell dimension) so short edges never get oversized knobs.
static func _edge(a: Vector2, b: Vector2, s: float, unit: float, random: bool,
		rng: RandomNumberGenerator, calm := false) -> PackedVector2Array:
	var d := b - a
	var length := d.length()
	var along := d / length
	var normal := Vector2(-along.y, along.x) * s

	var j := 0.05 if random else 0.015
	var t := rng.randf_range(0.085, 0.115) if random else rng.randf_range(0.097, 0.103)
	var ja := rng.randf_range(-j, j)
	var jb := rng.randf_range(-0.07, 0.07) if random else rng.randf_range(-j, j)
	var jc := rng.randf_range(-j, j)
	var jd := rng.randf_range(-j, j)
	var je := rng.randf_range(-j, j)
	var bow := rng.randf_range(-0.06, 0.06) if random else 0.0
	if calm:
		# Repair pass: centred knob, no bow.
		jb = 0.0
		bow = 0.0
	var mid := (0.5 + jb) * length

	# (distance along the edge, offset across the edge in units of `unit`)
	var ctrl: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(0.2 * length, ja),
		Vector2(mid + jd * unit, -t + jc),
		Vector2(mid - t * unit, t + jc),
		Vector2(mid + (-2.0 * t - jd) * unit, 3.0 * t + jc),
		Vector2(mid + (2.0 * t - jd) * unit, 3.0 * t + jc),
		Vector2(mid + t * unit, t + jc),
		Vector2(mid + jd * unit, -t + jc),
		Vector2(0.8 * length, je),
		Vector2(length, 0.0),
	]
	var pts := PackedVector2Array()
	pts.resize(ctrl.size())
	for i in ctrl.size():
		var u := ctrl[i].x
		var w := ctrl[i].y + bow * sin(PI * clampf(u / length, 0.0, 1.0))
		pts[i] = a + along * u + normal * (w * unit)

	var out := PackedVector2Array([a])
	for k in [0, 3, 6]:
		for i in range(1, CURVE_STEPS + 1):
			out.append(pts[k].bezier_interpolate(pts[k + 1], pts[k + 2], pts[k + 3], i / float(CURVE_STEPS)))
	out[out.size() - 1] = b
	return out
