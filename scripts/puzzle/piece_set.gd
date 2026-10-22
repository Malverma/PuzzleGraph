class_name PieceSet
extends RefCounted
## Geometry for every piece of one puzzle: outlines, triangulation, meshes.
##
## `compute()` is pure math and runs on a worker thread; `build_meshes()`
## touches the RenderingServer and must run on the main thread.

var cols := 0
var rows := 0
var count := 0
var puzzle_size := Vector2.ZERO
var cell := Vector2.ZERO
## Correct ("home") position of each piece: the centre of its grid cell.
var centers := PackedVector2Array()
## Outlines relative to the piece centre.
var outlines: Array[PackedVector2Array] = []
## Same as `outlines` with the first point repeated, for draw_polyline().
var closed_outlines: Array[PackedVector2Array] = []
var indices: Array[PackedInt32Array] = []
## Local bounding box of each outline.
var bounds: Array[Rect2] = []
var meshes: Array[ArrayMesh] = []
## Largest bounding-box side over all pieces (used to size tray thumbnails).
var max_extent := 0.0
## 0..1, written by compute() so the UI can show progress.
var progress := 0.0


func compute(grid: Vector2i, size: Vector2, style: int, seed_value: int) -> void:
	cols = grid.x
	rows = grid.y
	count = cols * rows
	puzzle_size = size
	cell = Vector2(size.x / cols, size.y / rows)
	var data := CutGenerator.generate(cols, rows, size, style, seed_value)
	progress = 0.3
	centers = data.centers
	var abs_outlines: Array[PackedVector2Array] = data.outlines
	for i in count:
		var src := abs_outlines[i]
		var local := PackedVector2Array()
		local.resize(src.size())
		var rect := Rect2(src[0] - centers[i], Vector2.ZERO)
		for k in src.size():
			local[k] = src[k] - centers[i]
			rect = rect.expand(local[k])
		outlines.append(local)
		var closed := local.duplicate()
		closed.append(local[0])
		closed_outlines.append(closed)
		var tri := Geometry2D.triangulate_polygon(local)
		if tri.is_empty():
			push_warning("Piece %d could not be triangulated; using Delaunay fallback" % i)
			tri = Geometry2D.triangulate_delaunay(local)
		indices.append(tri)
		bounds.append(rect)
		max_extent = maxf(max_extent, maxf(rect.size.x, rect.size.y))
		if i % 32 == 0:
			progress = 0.3 + 0.7 * float(i) / count
	progress = 1.0


func build_meshes() -> void:
	meshes.clear()
	for i in count:
		var local := outlines[i]
		var uv := PackedVector2Array()
		uv.resize(local.size())
		for k in local.size():
			uv[k] = (local[k] + centers[i]) / puzzle_size
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = local
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_INDEX] = indices[i]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		meshes.append(mesh)


## True if `local_point` (relative to the piece centre) is inside piece `id`.
func contains(id: int, local_point: Vector2) -> bool:
	return bounds[id].has_point(local_point) and Geometry2D.is_point_in_polygon(local_point, outlines[id])
