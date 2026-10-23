class_name CutGenerator
extends RefCounted
## Procedurally cuts a puzzle into piece outlines.
##
## Every interior edge is computed once and reused by the two pieces on either
## side of it, which guarantees neighbouring pieces fit exactly.
##
## Ribbon and Random share a cols x rows grid (`generate()` below). Octagon and
## Wavy are built by the generic cell builder (`_build_cells()`): a layout
## gives cell polygons, a profile function shapes each shared edge, and a
## repair pass re-cuts pieces whose knobs collide. New styles only need a
## layout and/or an edge profile.

enum Style { RIBBON, RANDOM, OCTAGON, WAVY }

const STYLE_KEYS: Array[String] = ["RIBBON", "RANDOM", "OCTAGON", "WAVY"]
const STYLE_NAMES: Array[String] = ["Ribbon Cut", "Random Cut", "Octagon Cut", "Wavy Cut"]

## Line segments used to flatten each cubic Bézier of an edge (3 per edge).
const CURVE_STEPS := 8
## Max grid-vertex displacement for Random Cut, as a fraction of a cell.
const RANDOM_JITTER := 0.12


## Grid that gives close-to-square pieces for an image with `aspect` = w / h.
static func grid_for(target: int, aspect: float) -> Vector2i:
	var rows := maxi(1, roundi(sqrt(target / aspect)))
	var cols := maxi(1, roundi(target / float(rows)))
	return Vector2i(cols, rows)


## Layout grid for a style. Octagon Cut adds a diamond at every interior grid
## corner, so it uses a smaller grid whose total lands near `target`, keeping
## cells within 25% of square.
static func layout_for(target: int, aspect: float, style: int) -> Vector2i:
	if style != Style.OCTAGON:
		return grid_for(target, aspect)
	var best := Vector2i(2, 2)
	var best_d := 1 << 30
	for r in range(1, 64):
		var base := maxi(1, roundi(r * aspect))
		for c: int in [base - 1, base, base + 1]:
			if c < 1:
				continue
			var stretch := (aspect / c) * r  # cell width / height
			if stretch < 0.8 or stretch > 1.25:
				continue
			var d := absi(piece_count(Vector2i(c, r), style) - target)
			if d < best_d:
				best_d = d
				best = Vector2i(c, r)
	return best


## Number of pieces a layout grid produces for a style.
static func piece_count(grid: Vector2i, style: int) -> int:
	if style == Style.OCTAGON:
		return grid.x * grid.y + (grid.x - 1) * (grid.y - 1)
	return grid.x * grid.y


static func style_from_key(key: String) -> int:
	var i := STYLE_KEYS.find(key)
	return i if i >= 0 else Style.RIBBON


## Returns { "outlines": Array[PackedVector2Array], "centers": PackedVector2Array,
## "border": PackedByteArray (1 = piece touches the outer edge) }.
## Outlines are in puzzle coordinates (0..size). For grid styles piece
## id = row * cols + col.
static func generate(cols: int, rows: int, size: Vector2, style: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if style == Style.OCTAGON:
		return _octagon(cols, rows, size, rng)
	if style == Style.WAVY:
		return _wavy(cols, rows, size, rng)
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
	var border := PackedByteArray()
	for r in rows:
		for c in cols:
			border.append(1 if r == 0 or c == 0 or r == rows - 1 or c == cols - 1 else 0)
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
	return { "outlines": outlines, "centers": centers, "border": border }


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


# --- Generic cell builder (Octagon, Wavy) -------------------------------------

## Vertices closer than this (puzzle units) are merged, so cells computed
## separately agree on shared corners despite float error.
const SNAP := 0.5
## Repair passes; each one shrinks the knobs of edges around broken pieces.
const REPAIR_PASSES := 6


## Builds pieces from clockwise (y down) cell polygons that tile `size`.
## `profile.call(i, j, length, level)` returns the shape of the edge shared by
## cells i < j as local points (u along the edge 0..1, v across it in units of
## the edge length, +v into cell i), excluding the start point and ending at
## (1, 0). `level` rises when the edge must be re-cut more calmly.
static func _build_cells(cells: Array[PackedVector2Array], size: Vector2, profile: Callable) -> Dictionary:
	# Merge corners into shared vertices.
	var verts := PackedVector2Array()
	var buckets := {}
	var polys: Array[PackedInt32Array] = []
	for cell in cells:
		var ids := PackedInt32Array()
		for p in cell:
			var v := _snap_vertex(p, verts, buckets)
			if ids.is_empty() or (ids[ids.size() - 1] != v and ids[0] != v):
				ids.append(v)
		polys.append(ids)

	# Shared edges: key -> [first cell, from, to, second cell].
	var n := verts.size()
	var edges := {}
	for i in polys.size():
		var ids := polys[i]
		for k in ids.size():
			var a := ids[k]
			var b := ids[(k + 1) % ids.size()]
			var key := mini(a, b) * n + maxi(a, b)
			if edges.has(key):
				edges[key][3] = i
			else:
				edges[key] = [i, a, b, -1]

	var border := PackedByteArray()
	border.resize(polys.size())
	var curves := {}   # key -> world points from the first cell's start to end
	var levels := {}
	for key in edges:
		var e: Array = edges[key]
		if e[3] < 0:
			border[e[0]] = 1
			continue
		levels[key] = 0
		curves[key] = _edge_curve(verts[e[1]], verts[e[2]], profile.call(e[0], e[3], verts[e[1]].distance_to(verts[e[2]]), 0))

	var outlines: Array[PackedVector2Array] = []
	var centers := PackedVector2Array()
	for i in polys.size():
		outlines.append(_cell_outline(i, polys[i], n, verts, edges, curves))
		centers.append(_centroid(cells[i]))

	# Repair: re-cut the edges of pieces that are not simple polygons, calmer each pass.
	var check: Array[int] = []
	for i in polys.size():
		check.append(i)
	for pass_i in REPAIR_PASSES:
		var touched := {}
		for i in check:
			if _is_simple(outlines[i]):
				continue
			var ids := polys[i]
			for k in ids.size():
				var a := ids[k]
				var b := ids[(k + 1) % ids.size()]
				var key := mini(a, b) * n + maxi(a, b)
				if not curves.has(key):
					continue
				var e: Array = edges[key]
				levels[key] += 1
				var length := verts[e[1]].distance_to(verts[e[2]])
				curves[key] = _edge_curve(verts[e[1]], verts[e[2]], profile.call(e[0], e[3], length, levels[key]))
				touched[e[0]] = true
				touched[e[3]] = true
		if touched.is_empty():
			break
		check.clear()
		for i in touched:
			outlines[i] = _cell_outline(i, polys[i], n, verts, edges, curves)
			check.append(i)
	return { "outlines": outlines, "centers": centers, "border": border }


static func _snap_vertex(p: Vector2, verts: PackedVector2Array, buckets: Dictionary) -> int:
	var cx := floori(p.x / (SNAP * 4.0))
	var cy := floori(p.y / (SNAP * 4.0))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for v: int in buckets.get(Vector2i(cx + dx, cy + dy), []):
				if verts[v].distance_to(p) <= SNAP:
					return v
	verts.append(p)
	var k := Vector2i(cx, cy)
	if not buckets.has(k):
		buckets[k] = []
	buckets[k].append(verts.size() - 1)
	return verts.size() - 1


static func _cell_outline(i: int, ids: PackedInt32Array, n: int, verts: PackedVector2Array,
		edges: Dictionary, curves: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in ids.size():
		var a := ids[k]
		var b := ids[(k + 1) % ids.size()]
		var key := mini(a, b) * n + maxi(a, b)
		if not curves.has(key):
			out.append(verts[a])
			continue
		var curve: PackedVector2Array = curves[key]
		_append(out, curve, edges[key][0] != i)
	return out


## Maps a local profile onto the segment a -> b; first point a, last point b.
static func _edge_curve(a: Vector2, b: Vector2, local: PackedVector2Array) -> PackedVector2Array:
	var d := b - a
	var normal := Vector2(-d.y, d.x)
	var out := PackedVector2Array([a])
	for q in local:
		out.append(a + d * q.x + normal * q.y)
	out[out.size() - 1] = b
	return out


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var area := 0.0
	var c := Vector2.ZERO
	for k in poly.size():
		var p := poly[k]
		var q := poly[(k + 1) % poly.size()]
		var cr := p.x * q.y - q.x * p.y
		area += cr
		c += (p + q) * cr
	return c / (3.0 * area) if absf(area) > 1e-6 else poly[0]


## Keeps the part of `poly` where n.dot(p) <= c.
static func _clip(poly: PackedVector2Array, nrm: Vector2, c: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in poly.size():
		var p := poly[k]
		var q := poly[(k + 1) % poly.size()]
		var fp := nrm.dot(p) - c
		var fq := nrm.dot(q) - c
		if fp <= 1e-6:
			out.append(p)
		if (fp > 1e-6) != (fq > 1e-6):
			out.append(p + (q - p) * (fp / (fp - fq)))
	return out


# --- Edge profiles ---------------------------------------------------------------

## Classic three-Bézier tab from (0, 0) to (1, 0) in local edge units,
## bulging toward +v when `inward` (into the first cell), else -v. `size` is
## the knob size as a fraction of the edge; `steps` points per curve.
static func _knob(rng: RandomNumberGenerator, inward: bool, size: float, jitter: float, steps: int) -> PackedVector2Array:
	var t := size * rng.randf_range(0.92, 1.08)
	var a := rng.randf_range(-jitter, jitter)
	var b := rng.randf_range(-jitter, jitter)
	var c := rng.randf_range(-jitter, jitter)
	var d := rng.randf_range(-jitter, jitter)
	var e := rng.randf_range(-jitter, jitter)
	var s := 1.0 if inward else -1.0
	var p: Array[Vector2] = [
		Vector2(0, 0), Vector2(0.2, a), Vector2(0.5 + b + d, -t + c), Vector2(0.5 - t + b, t + c),
		Vector2(0.5 - 2.0 * t + b - d, 3.0 * t + c), Vector2(0.5 + 2.0 * t + b - d, 3.0 * t + c),
		Vector2(0.5 + t + b, t + c), Vector2(0.5 + b + d, -t + c), Vector2(0.8, e), Vector2(1, 0),
	]
	var out := PackedVector2Array()
	for k in [0, 3, 6]:
		for i in range(1, steps + 1):
			var q := p[k].bezier_interpolate(p[k + 1], p[k + 2], p[k + 3], i / float(steps))
			out.append(Vector2(q.x, q.y * s))
	return out


## Smooth low-amplitude wobble v(u), zero at both ends: [k1, k2, k3, phase].
static func _wave(rng: RandomNumberGenerator, amp: float) -> PackedFloat32Array:
	return PackedFloat32Array([rng.randf_range(-amp, amp), rng.randf_range(-amp, amp) / 2.0,
			rng.randf_range(-amp, amp) / 3.0, rng.randf_range(0.0, PI)])


static func _wave_at(w: PackedFloat32Array, u: float) -> float:
	return sin(PI * u) * (w[0] * sin(PI * u) + w[1] * sin(2.0 * PI * u + w[3]) + w[2] * sin(3.0 * PI * u + w[3]))


## A gently waving edge with no knob.
static func _wavy_line(rng: RandomNumberGenerator, amp: float, steps: int) -> PackedVector2Array:
	var w := _wave(rng, amp)
	var out := PackedVector2Array()
	for i in range(1, steps + 1):
		var u := i / float(steps)
		out.append(Vector2(u, _wave_at(w, u)))
	return out


# --- Octagon Cut ------------------------------------------------------------------

## Truncated-square tiling: an octagon for every grid cell and a diamond at
## every interior grid corner. Diamonds are nudged, resized and turned a
## little; border corners slide along the border so it stays straight. Every
## shared edge gets a knob; diamond knobs mostly push into the octagons, and
## long octagon edges sometimes carry two.
static func _octagon(cols: int, rows: int, size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var cs := Vector2(size.x / cols, size.y / rows)
	var unit := minf(cs.x, cs.y)
	var k0 := unit / (2.0 + sqrt(2.0))
	var shift := 0.07
	var dia := {}  # Vector2i(c, r) -> [N, E, S, W]
	for r in range(1, rows):
		for c in range(1, cols):
			var center := Vector2(c * cs.x, r * cs.y) + Vector2(rng.randf_range(-shift, shift), rng.randf_range(-shift, shift)) * unit
			var k := k0 * (1.0 + rng.randf_range(-0.25, 0.25))
			var ang := deg_to_rad(rng.randf_range(-14.0, 14.0))
			var pts := []
			for q in [Vector2(0, -k), Vector2(k, 0), Vector2(0, k), Vector2(-k, 0)]:
				pts.append(center + q.rotated(ang))
			dia[Vector2i(c, r)] = pts
	var top := {}
	var bot := {}
	for c in range(1, cols):
		top[c] = Vector2(c * cs.x + rng.randf_range(-shift, shift) * unit, 0.0)
		bot[c] = Vector2(c * cs.x + rng.randf_range(-shift, shift) * unit, size.y)
	var left := {}
	var right := {}
	for r in range(1, rows):
		left[r] = Vector2(0.0, r * cs.y + rng.randf_range(-shift, shift) * unit)
		right[r] = Vector2(size.x, r * cs.y + rng.randf_range(-shift, shift) * unit)
	var names := { "N": 0, "E": 1, "S": 2, "W": 3 }
	var corner := func(r: int, c: int, first: String, second: String) -> Array:
		if (r == 0 or r == rows) and (c == 0 or c == cols):
			return [Vector2(c * cs.x, r * cs.y)]
		if r == 0:
			return [top[c]]
		if r == rows:
			return [bot[c]]
		if c == 0:
			return [left[r]]
		if c == cols:
			return [right[r]]
		var d: Array = dia[Vector2i(c, r)]
		return [d[names[first]], d[names[second]]]

	var cells: Array[PackedVector2Array] = []
	var is_diamond: Array[bool] = []
	for r in rows:
		for c in cols:
			var poly := PackedVector2Array()
			for p in corner.call(r, c, "S", "E") + corner.call(r, c + 1, "W", "S") \
					+ corner.call(r + 1, c + 1, "N", "W") + corner.call(r + 1, c, "E", "N"):
				poly.append(p)
			cells.append(poly)
			is_diamond.append(false)
	for r in range(1, rows):
		for c in range(1, cols):
			cells.append(PackedVector2Array(dia[Vector2i(c, r)]))
			is_diamond.append(true)

	var profile := func(i: int, j: int, length: float, level: int) -> PackedVector2Array:
		if level >= 4 or length < unit * 0.08:
			return _wavy_line(rng, 0.02, 4)
		var calm := pow(0.75, level)
		var bow := _wave(rng, 0.05 * calm)
		var pts := PackedVector2Array()
		if is_diamond[j]:
			var ks := clampf(0.055 * unit / length, 0.08, 0.15) * rng.randf_range(0.8, 1.2) * calm
			pts = _knob(rng, rng.randf() < 0.8, ks, 0.05 * calm, CURVE_STEPS)
		elif length > 0.65 * unit and rng.randf() < 0.35 and level == 0:
			var inward := rng.randf() < 0.5
			for half in [0.0, 0.5]:
				var ks := clampf(0.06 * unit / (length / 2.0), 0.10, 0.16) * rng.randf_range(0.85, 1.15)
				for q in _knob(rng, inward, ks, 0.05, CURVE_STEPS):
					pts.append(Vector2(half + q.x / 2.0, q.y / 2.0))
				inward = not inward
		else:
			var ks := clampf(0.055 * unit / length, 0.08, 0.12) * rng.randf_range(0.8, 1.25) * calm
			pts = _knob(rng, rng.randf() < 0.5, ks, 0.05 * calm, CURVE_STEPS)
		for k in pts.size():
			pts[k] = Vector2(pts[k].x, pts[k].y + _wave_at(bow, pts[k].x))
		return pts
	return _build_cells(cells, size, profile)


# --- Wavy Cut ---------------------------------------------------------------------

## Voronoi cells around jittered grid points (irregular, mostly 5-7 sided).
## Edges meander and carry 0-3 bulbous knobs that often alternate direction,
## for the laser-cut wooden puzzle look.
static func _wavy(cols: int, rows: int, size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var cs := Vector2(size.x / cols, size.y / rows)
	var unit := minf(cs.x, cs.y)
	var seeds := PackedVector2Array()
	for r in rows:
		for c in cols:
			seeds.append(Vector2(c + 0.5 + rng.randf_range(-0.3, 0.3), r + 0.5 + rng.randf_range(-0.3, 0.3)) * cs)
	var frame := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	var cells: Array[PackedVector2Array] = []
	for r in rows:
		for c in cols:
			var si := seeds[r * cols + c]
			var poly := frame
			# Voronoi neighbours of a jittered grid point lie within two cells.
			for rr in range(maxi(0, r - 2), mini(rows, r + 3)):
				for cc in range(maxi(0, c - 2), mini(cols, c + 3)):
					if rr == r and cc == c:
						continue
					var sj := seeds[rr * cols + cc]
					poly = _clip(poly, sj - si, (sj.length_squared() - si.length_squared()) * 0.5)
			cells.append(poly)

	var profile := func(_i: int, _j: int, length: float, level: int) -> PackedVector2Array:
		if level >= 4:
			return _wavy_line(rng, 0.03, 6)
		var calm := pow(0.7, level)
		var knobs := 3 if length > 1.4 * unit else 2 if length > 0.75 * unit else 1 if length > 0.3 * unit else 0
		if level >= 2:
			knobs = mini(knobs, 1)
		var meander := _wave(rng, 0.16 * calm)
		if knobs == 0:
			var line := _wavy_line(rng, 0.08 * calm, 8)
			for k in line.size():
				line[k] = Vector2(line[k].x, line[k].y + _wave_at(meander, line[k].x) * 0.5)
			return line
		var inward := rng.randf() < 0.5
		var pts := PackedVector2Array()
		for m in knobs:
			var a := m / float(knobs)
			var span := 1.0 / knobs
			var ks := clampf(0.065 * unit / (length / knobs), 0.10, 0.17) * calm
			for q in _knob(rng, inward, ks, 0.07 * calm, 6):
				pts.append(Vector2(a + q.x * span, q.y * span))
			if rng.randf() < 0.75:
				inward = not inward
		for k in pts.size():
			pts[k] = Vector2(pts[k].x, pts[k].y + _wave_at(meander, pts[k].x))
		return pts
	return _build_cells(cells, size, profile)
