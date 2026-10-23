class_name CutGenerator
extends RefCounted
## Procedurally cuts a puzzle into piece outlines.
##
## Every interior edge is computed once and reused by the two pieces on either
## side of it, which guarantees neighbouring pieces fit exactly.
##
## Ribbon and Random share a cols x rows grid (`generate()` below). The other
## styles are built by the generic cell builder (`_build_cells()`): a layout
## gives cell polygons, a profile function shapes each shared edge, and a
## repair pass re-cuts pieces whose knobs collide. New styles only need a
## layout and/or an edge profile.

enum Style { RIBBON, RANDOM, WAVY, ANGULAR, CREATIVE, FANTASY }

const STYLE_KEYS: Array[String] = ["RIBBON", "RANDOM", "WAVY", "ANGULAR", "CREATIVE", "FANTASY"]
const STYLE_NAMES: Array[String] = ["Ribbon Cut", "Random Cut", "Wavy Cut", "Angular Cut", "Creative Cut", "Fantasy Cut"]

## Line segments used to flatten each cubic Bézier of an edge (3 per edge).
const CURVE_STEPS := 8
## Max grid-vertex displacement for Random Cut, as a fraction of a cell.
const RANDOM_JITTER := 0.12


## Grid that gives close-to-square pieces for an image with `aspect` = w / h.
static func grid_for(target: int, aspect: float) -> Vector2i:
	var rows := maxi(1, roundi(sqrt(target / aspect)))
	var cols := maxi(1, roundi(target / float(rows)))
	return Vector2i(cols, rows)


## Layout grid for a style. Every style currently cuts one piece per grid
## cell; a style whose pieces don't map 1:1 to cells would adjust it here.
static func layout_for(target: int, aspect: float, _style: int) -> Vector2i:
	return grid_for(target, aspect)


## Number of pieces a layout grid produces for a style.
static func piece_count(grid: Vector2i, _style: int) -> int:
	return grid.x * grid.y


## -1 for keys of retired styles (saves made with them can't be rebuilt).
static func find_style(key: String) -> int:
	return STYLE_KEYS.find(key)


## Returns { "outlines": Array[PackedVector2Array], "centers": PackedVector2Array,
## "border": PackedByteArray (1 = piece touches the outer edge) }.
## Outlines are in puzzle coordinates (0..size). For grid styles piece
## id = row * cols + col.
static func generate(cols: int, rows: int, size: Vector2, style: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	match style:
		Style.WAVY:
			return _wavy(cols, rows, size, rng)
		Style.ANGULAR:
			return _angular(cols, rows, size, rng)
		Style.CREATIVE:
			return _creative(cols, rows, size, rng)
		Style.FANTASY:
			return _fantasy(cols, rows, size, rng)
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


## True if the outline has no self-intersections.
static func _is_simple(p: PackedVector2Array) -> bool:
	return _crossings(p, true).is_empty()


## Indices of segments that cross another segment of the outline (empty for
## a simple polygon); with `first_only` it stops at the first crossing.
## Only segments sharing a cell of a coarse grid are compared, so it stays fast.
static func _crossings(p: PackedVector2Array, first_only := false) -> PackedInt32Array:
	var hits := PackedInt32Array()
	var n := p.size()
	var lo_all := p[0]
	var hi_all := p[0]
	for q in p:
		lo_all = lo_all.min(q)
		hi_all = hi_all.max(q)
	const B := 8
	var bs := (hi_all - lo_all) / B + Vector2(0.001, 0.001)
	var grid: Array[PackedInt32Array] = []
	grid.resize(B * B)
	for i in n:
		var a := p[i]
		var b := p[(i + 1) % n]
		var lo := Vector2i(((a.min(b) - lo_all) / bs).floor())
		var hi := Vector2i(((a.max(b) - lo_all) / bs).floor())
		for gx in range(lo.x, mini(hi.x, B - 1) + 1):
			for gy in range(lo.y, mini(hi.y, B - 1) + 1):
				var cell := grid[gx * B + gy]
				for j in cell:
					var gap := i - j
					if gap <= 1 or gap == n - 1:
						continue
					if Geometry2D.segment_intersects_segment(a, b, p[j], p[(j + 1) % n]) != null:
						hits.append(i)
						hits.append(j)
						if first_only:
							return hits
				cell.append(i)
				grid[gx * B + gy] = cell
	return hits


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


# --- Generic cell builder (Wavy, Angular, Creative, Fantasy) -------------------------------------

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
	var owners: Array[PackedInt32Array] = []  # per outline point: key of the edge it belongs to
	var centers := PackedVector2Array()
	for i in polys.size():
		var owner := PackedInt32Array()
		outlines.append(_cell_outline(i, polys[i], n, verts, edges, curves, owner))
		owners.append(owner)
		centers.append(_centroid(cells[i]))

	# Repair: re-cut, calmer each pass, only the edges whose curves cross in
	# a piece that is not a simple polygon, so neighbours keep their shapes.
	var check: Array[int] = []
	for i in polys.size():
		check.append(i)
	for pass_i in REPAIR_PASSES:
		var touched := {}
		var redo := {}
		for i in check:
			for seg in _crossings(outlines[i]):
				var key: int = owners[i][seg]
				if curves.has(key):
					redo[key] = true
		for key: int in redo:
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
			var owner := PackedInt32Array()
			outlines[i] = _cell_outline(i, polys[i], n, verts, edges, curves, owner)
			owners[i] = owner
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


## Outline of cell i. `owner` receives, for every point, the key of the edge
## whose segment starts there.
static func _cell_outline(i: int, ids: PackedInt32Array, n: int, verts: PackedVector2Array,
		edges: Dictionary, curves: Dictionary, owner: PackedInt32Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in ids.size():
		var a := ids[k]
		var b := ids[(k + 1) % ids.size()]
		var key := mini(a, b) * n + maxi(a, b)
		var before := out.size()
		if not curves.has(key):
			out.append(verts[a])
		else:
			var curve: PackedVector2Array = curves[key]
			_append(out, curve, edges[key][0] != i)
		for m in out.size() - before:
			owner.append(key)
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


# --- Wavy Cut ---------------------------------------------------------------------

## Voronoi cells around jittered grid points (irregular, mostly 5-7 sided).
## Edges meander and carry 0-3 bulbous knobs that often alternate direction,
## for the laser-cut wooden puzzle look.
static func _wavy(cols: int, rows: int, size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var cs := Vector2(size.x / cols, size.y / rows)
	var unit := minf(cs.x, cs.y)
	var cells := _voronoi(_jittered_seeds(cols, rows, cs, 0.3, rng), cols, rows, size, 2)

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


# --- Voronoi layouts ----------------------------------------------------------------

## One seed per grid cell, at the cell centre moved by up to ±`jitter` cells.
static func _jittered_seeds(cols: int, rows: int, cs: Vector2, jitter: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var seeds := PackedVector2Array()
	for r in rows:
		for c in cols:
			seeds.append(Vector2(c + 0.5 + rng.randf_range(-jitter, jitter), r + 0.5 + rng.randf_range(-jitter, jitter)) * cs)
	return seeds


## Voronoi cells of `seeds` (one per grid cell, row-major), clipped to the
## puzzle. Only seeds within `reach` grid cells are tested as neighbours,
## which is exact as long as no seed strays further than that from its cell.
static func _voronoi(seeds: PackedVector2Array, cols: int, rows: int, size: Vector2, reach: int) -> Array[PackedVector2Array]:
	var frame := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	var cells: Array[PackedVector2Array] = []
	for r in rows:
		for c in cols:
			var si := seeds[r * cols + c]
			var poly := frame
			for rr in range(maxi(0, r - reach), mini(rows, r + reach + 1)):
				for cc in range(maxi(0, c - reach), mini(cols, c + reach + 1)):
					if rr == r and cc == c:
						continue
					var sj := seeds[rr * cols + cc]
					poly = _clip(poly, sj - si, (sj.length_squared() - si.length_squared()) * 0.5)
			cells.append(poly)
	return cells


## Adds the wobble `w` to the v of every point.
static func _add_wave(pts: PackedVector2Array, w: PackedFloat32Array) -> PackedVector2Array:
	for k in pts.size():
		pts[k] = Vector2(pts[k].x, pts[k].y + _wave_at(w, pts[k].x))
	return pts


## Places `feature` (local points of one sub-edge, ending at (1, 0)) into
## span m of n equal spans of the edge.
static func _append_span(out: PackedVector2Array, feature: PackedVector2Array, m: int, n: int) -> void:
	var span := 1.0 / n
	for q in feature:
		out.append(Vector2((m + q.x) * span, q.y * span))


# --- Angular Cut --------------------------------------------------------------------

## Honeycomb of cells whose every edge is bent into a deep chevron with a
## rounded tip (sometimes a zigzag), with no knobs. Neighbouring chevrons give
## the interlocking boomerang and three-armed pieces of laser-cut wood puzzles.
static func _angular(cols: int, rows: int, size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var cs := Vector2(size.x / cols, size.y / rows)
	var unit := minf(cs.x, cs.y)
	# Every other row shifted half a cell gives hexagonal cells.
	var seeds := PackedVector2Array()
	for r in rows:
		var shift := 0.25 if r % 2 == 0 else 0.75
		for c in cols:
			seeds.append(Vector2(c + shift + rng.randf_range(-0.06, 0.06), r + 0.5 + rng.randf_range(-0.06, 0.06)) * cs)
	var cells := _voronoi(seeds, cols, rows, size, 2)

	var profile := func(_i: int, _j: int, length: float, level: int) -> PackedVector2Array:
		if level >= 3 or length < 0.18 * unit:
			return _wavy_line(rng, 0.03, 4)
		var calm := pow(0.6, level)
		var s := 1.0 if rng.randf() < 0.5 else -1.0
		var corners: Array[Vector2] = [Vector2.ZERO]
		if level == 0 and length > 0.45 * unit and rng.randf() < 0.3:
			var d := rng.randf_range(0.24, 0.3)
			corners.append(Vector2(rng.randf_range(0.27, 0.33), s * d))
			corners.append(Vector2(rng.randf_range(0.67, 0.73), -s * d))
		else:
			corners.append(Vector2(0.5 + rng.randf_range(-0.1, 0.1), s * rng.randf_range(0.42, 0.52) * calm))
		corners.append(Vector2(1, 0))
		return _rounded_polyline(corners, 0.4, 6)
	return _build_cells(cells, size, profile)


## Polyline through `corners` (first (0, 0), last (1, 0)) with every inner
## corner rounded by a quadratic curve starting `cut` of the way along each
## leg. Excludes the first point.
static func _rounded_polyline(corners: Array[Vector2], cut: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in range(1, corners.size() - 1):
		var p := corners[k]
		var a := p.lerp(corners[k - 1], cut)
		var b := p.lerp(corners[k + 1], cut)
		out.append(a)
		for i in range(1, steps + 1):
			var t := i / float(steps)
			out.append(a.lerp(p, t).lerp(p.lerp(b, t), t))
	out.append(corners[corners.size() - 1])
	return out


# --- Creative Cut -------------------------------------------------------------------

## Irregular cells whose edges sway and carry curled, swirling hooks (and
## the odd round knob), like hand-cut artisan puzzles.
static func _creative(cols: int, rows: int, size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var cs := Vector2(size.x / cols, size.y / rows)
	var unit := minf(cs.x, cs.y)
	var cells := _voronoi(_jittered_seeds(cols, rows, cs, 0.3, rng), cols, rows, size, 2)

	var profile := func(_i: int, _j: int, length: float, level: int) -> PackedVector2Array:
		if level >= 4:
			return _wavy_line(rng, 0.03, 6)
		var calm := pow(0.75, level)
		var n := 2 if length > 1.5 * unit else 1 if length > 0.3 * unit else 0
		if level >= 2:
			n = mini(n, 1)
		if n == 0:
			return _add_wave(_wavy_line(rng, 0.06, 8), _wave(rng, 0.25))
		var pts := PackedVector2Array()
		for m in n:
			var sub := length / n
			var inward := rng.randf() < 0.5
			var sway := _wave(rng, 0.3 * calm)
			if rng.randf() < 0.85 and level < 3:
				var radius := clampf(0.15 * unit / sub, 0.12, 0.3) * rng.randf_range(0.85, 1.15) * calm
				_append_span(pts, _curl(rng, inward, radius, sway), m, n)
			else:
				var ks := clampf(0.06 * unit / sub, 0.10, 0.16) * calm
				_append_span(pts, _add_wave(_knob(rng, inward, ks, 0.06 * calm, 6), sway), m, n)
		return pts
	return _build_cells(cells, size, profile)


## Edge from (0, 0) to (1, 0) with a hook that rises from the edge and curls
## round in a tightening spiral, like a breaking wave. `radius` is the curl
## radius as a fraction of the edge. The base line follows the wobble `sway`;
## the hook moves with it rigidly so the spiral never shears into itself.
## Excludes the first point.
static func _curl(rng: RandomNumberGenerator, inward: bool, radius: float, sway: PackedFloat32Array) -> PackedVector2Array:
	var hand := 1.0 if rng.randf() < 0.5 else -1.0
	var sweep := deg_to_rad(rng.randf_range(210.0, 290.0))
	var hw := radius * 0.34          # half the stroke width at the root
	var stem := radius * 1.15        # height where the curl starts
	var root := 0.5 - 0.75 * radius + rng.randf_range(-0.05, 0.05)
	# Centre line of the stroke, drawn curling to the right (+u) and mirrored for hand < 0.
	var line := PackedVector2Array([Vector2(root, 0.0), Vector2(root, stem * 0.5)])
	var o := Vector2(root + radius, stem)
	const N := 10
	for k in N + 1:
		var t := k / float(N)
		var th := PI - sweep * t
		line.append(o + Vector2(cos(th), sin(th)) * radius * (1.0 - 0.45 * t))
	var width := func(k: int) -> float:
		return hw * (1.0 - 0.3 * maxf(0.0, (k - 2) / float(N)))
	# Outer side out to the tip, a round cap, then the inner side back.
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for k in line.size():
		var tg := (line[mini(k + 1, line.size() - 1)] - line[maxi(k - 1, 0)]).normalized()
		var nrm := Vector2(-tg.y, tg.x)
		left.append(line[k] + nrm * width.call(k))
		right.append(line[k] - nrm * width.call(k))
	var last := line.size() - 1
	var end_tan := (line[last] - line[last - 1]).normalized()
	var end_n := Vector2(-end_tan.y, end_tan.x)
	var tab := PackedVector2Array(left)
	for i in range(1, 4):
		var a := PI * i / 4.0
		tab.append(line[last] + (end_n * cos(a) + end_tan * sin(a)) * width.call(last))
	for k in range(last, -1, -1):
		tab.append(right[k])
	if hand < 0.0:
		# Mirroring flips the winding, so walk the tab backwards.
		var mirrored := PackedVector2Array()
		for k in range(tab.size() - 1, -1, -1):
			mirrored.append(Vector2(1.0 - tab[k].x, tab[k].y))
		tab = mirrored
	var s := 1.0 if inward else -1.0
	var start := tab[0].x
	var end := tab[tab.size() - 1].x
	var lift := _wave_at(sway, (start + end) * 0.5)
	var out := PackedVector2Array()
	const BASE := 3
	for i in range(1, BASE):
		var u := start * i / float(BASE)
		out.append(Vector2(u, _wave_at(sway, u)))
	for q in tab:
		out.append(Vector2(q.x, q.y * s + lift))
	for i in range(1, BASE + 1):
		var u := lerpf(end, 1.0, i / float(BASE))
		out.append(Vector2(u, _wave_at(sway, u)))
	return out


# --- Fantasy Cut --------------------------------------------------------------------

## Wildly irregular pieces: strongly scattered (but not crowded) cells of
## varied size, edges that swing widely and carry up to four knobs of mixed
## sizes that lean at odd angles, plus the occasional round lobe.
static func _fantasy(cols: int, rows: int, size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var cs := Vector2(size.x / cols, size.y / rows)
	var unit := minf(cs.x, cs.y)
	var seeds := _jittered_seeds(cols, rows, cs, 0.42, rng)
	# Push apart seeds that landed too close, so no piece is tiny.
	var dmin := 0.55 * unit
	for it in 3:
		for r in rows:
			for c in cols:
				var i := r * cols + c
				for rr in range(r, mini(rows, r + 2)):
					for cc in range(maxi(0, c - 1), mini(cols, c + 2)):
						var j := rr * cols + cc
						if j <= i:
							continue
						var d := seeds[j] - seeds[i]
						var dl := d.length()
						if dl < dmin and dl > 1e-3:
							var push := d / dl * (dmin - dl) * 0.5
							seeds[i] -= push
							seeds[j] += push
		for k in seeds.size():
			seeds[k] = seeds[k].clamp(cs * 0.05, size - cs * 0.05)
	var cells := _voronoi(seeds, cols, rows, size, 3)

	var profile := func(_i: int, _j: int, length: float, level: int) -> PackedVector2Array:
		if level >= 4:
			return _wavy_line(rng, 0.04, 6)
		var calm := pow(0.7, level)
		var n := 4 if length > 1.5 * unit else 3 if length > 1.0 * unit else 2 if length > 0.55 * unit else 1 if length > 0.25 * unit else 0
		if level >= 2:
			n = mini(n, 1)
		var swing := _wave(rng, 0.22 * calm)
		if n == 0:
			return _add_wave(_wavy_line(rng, 0.08, 8), swing)
		var pts := PackedVector2Array()
		for m in n:
			var sub := length / n
			var inward := rng.randf() < 0.5
			if rng.randf() < 0.15 and level == 0:
				# A round lobe with no neck.
				var lobe := PackedVector2Array()
				var h := rng.randf_range(0.12, 0.2) * (1.0 if inward else -1.0)
				for i in range(1, 9):
					var u := i / 8.0
					lobe.append(Vector2(u, h * sin(PI * u)))
				_append_span(pts, lobe, m, n)
				continue
			var ks := clampf(0.06 * unit / sub, 0.09, 0.19) * rng.randf_range(0.7, 1.3) * calm
			var knob := _knob(rng, inward, ks, 0.08 * calm, 6)
			# Lean the knob by shearing it along the edge.
			var lean := rng.randf_range(-0.5, 0.5) * calm
			for k in knob.size():
				knob[k] = Vector2(knob[k].x + lean * absf(knob[k].y), knob[k].y)
			_append_span(pts, knob, m, n)
		return _add_wave(pts, swing)
	return _build_cells(cells, size, profile)
