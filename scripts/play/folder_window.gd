extends Control
## Window listing the pieces inside one board folder. It pops out of the
## folder itself (below it when there is room, otherwise above) with a tail
## pointing back at it. Pieces are dragged out of it onto the board or tray;
## the grid scrolls vertically when it doesn't fit. Input is routed here by play.gd.

const PAD := 24.0
const HEADER_H := 76.0
const MIN_CELL := 140.0
const CLOSE_R := 30.0
const MAX_W := 720.0
## Gap kept between the window and the screen edges.
const EDGE := 16.0
const TAIL_W := 44.0
const TAIL_H := 22.0

var model: PuzzleModel
var texture: Texture2D
## Folder shown, or -1 when closed.
var folder := -1
var scroll := 0.0
var cell := MIN_CELL
var columns := 3
var panel := Rect2()
## Returns the folder's rect on screen, so the window can follow it.
var _anchor: Callable
## Tail triangle from the panel edge to the folder.
var _tail := PackedVector2Array()
var _style: StyleBoxTexture
var _wood := Color("#b0703f")
var _grid: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = Game.wood("panel", 20)
	var tex_img := _style.texture.get_image()
	if tex_img:
		if tex_img.is_compressed():
			tex_img.decompress()
		_wood = tex_img.get_pixel(tex_img.get_width() / 2, tex_img.get_height() / 2)
	_grid = Control.new()
	_grid.clip_contents = true
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_grid.draw.connect(_draw_grid)
	add_child(_grid)
	resized.connect(_layout)
	hide()


## Opens folder `f`; `anchor` returns the folder's screen rect.
func open(f: int, anchor: Callable) -> void:
	folder = f
	_anchor = anchor
	scroll = 0.0
	show()
	_layout()
	# Grow out of the folder.
	pivot_offset = _tail[1] if _tail.size() == 3 else panel.get_center()
	scale = Vector2.ONE * 0.4
	modulate.a = 0.0
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector2.ONE, 0.2)
	t.tween_property(self, "modulate:a", 1.0, 0.12)


func close() -> void:
	folder = -1
	hide()


func is_open() -> bool:
	return folder >= 0


func _ids() -> Array:
	return model.folders[folder].ids if is_open() and folder < model.folders.size() else []


func _layout() -> void:
	if not is_open():
		return
	var a: Rect2 = _anchor.call()
	var pw := minf(size.x - EDGE * 2.0, MAX_W)
	var inner := pw - PAD * 2.0
	columns = maxi(3, int(inner / MIN_CELL))
	cell = inner / columns
	var rows := ceili(_ids().size() / float(columns))
	var want := HEADER_H + rows * cell + PAD
	var below := size.y - EDGE - (a.end.y + TAIL_H)
	var above := a.position.y - TAIL_H - EDGE
	var down := want <= below or below >= above
	var room := below if down else above
	var grid_h := minf(rows * cell, maxf(cell, room - HEADER_H - PAD))
	var ph := HEADER_H + grid_h + PAD
	var x := clampf(a.get_center().x - pw * 0.5, EDGE, size.x - EDGE - pw)
	var y := a.end.y + TAIL_H if down else a.position.y - TAIL_H - ph
	y = clampf(y, EDGE, maxf(EDGE, size.y - EDGE - ph))
	panel = Rect2(x, y, pw, ph)
	var tx := clampf(a.get_center().x, panel.position.x + TAIL_W, panel.end.x - TAIL_W)
	var edge_y := panel.position.y if down else panel.end.y
	var tip := Vector2(tx, a.end.y if down else a.position.y)
	_tail = PackedVector2Array([Vector2(tx - TAIL_W * 0.5, edge_y), tip, Vector2(tx + TAIL_W * 0.5, edge_y)])
	_grid.position = panel.position + Vector2(PAD, HEADER_H)
	_grid.size = Vector2(inner, grid_h)
	scroll = clampf(scroll, 0.0, max_scroll())
	queue_redraw()
	_grid.queue_redraw()


func refresh() -> void:
	_layout()


func max_scroll() -> float:
	return maxf(0.0, ceili(_ids().size() / float(columns)) * cell - _grid.size.y)


func scroll_by(dy: float) -> void:
	scroll = clampf(scroll + dy, 0.0, max_scroll())
	_grid.queue_redraw()


func in_panel(p: Vector2) -> bool:
	return panel.has_point(p)


func on_close(p: Vector2) -> bool:
	return p.distance_to(_close_center()) <= CLOSE_R + 12.0


func _close_center() -> Vector2:
	return Vector2(panel.end.x - PAD - CLOSE_R, panel.position.y + HEADER_H * 0.5)


## Index (within the folder) of the piece under screen point `p`, or -1.
func index_at(p: Vector2) -> int:
	var local := p - _grid.global_position
	if not Rect2(Vector2.ZERO, _grid.size).has_point(local):
		return -1
	var col := int(local.x / cell)
	var row := int((local.y + scroll) / cell)
	var i := row * columns + col
	return i if col < columns and i < _ids().size() else -1


## Screen position of the centre of slot `i`.
func slot_center(i: int) -> Vector2:
	return _grid.global_position + Vector2((i % columns + 0.5) * cell, (i / columns + 0.5) * cell - scroll)


func _draw() -> void:
	if not is_open():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.3))
	draw_rect(panel.grow(6.0), Color(0, 0, 0, 0.35))
	# Tail back to the folder, under the panel so it joins the wood edge.
	var outline := _tail.duplicate()
	var dir := (_tail[1] - (_tail[0] + _tail[2]) * 0.5).normalized()
	outline[0] -= Vector2(3, 0)
	outline[2] += Vector2(3, 0)
	outline[1] += dir * 3.0
	draw_colored_polygon(outline, Color(0.1, 0.05, 0.02, 0.9))
	draw_colored_polygon(_tail, _wood)
	_style.draw(get_canvas_item(), panel)
	var font := get_theme_default_font()
	var n := _ids().size()
	var title := "Folder · %d pieces" % n
	draw_string(font, panel.position + Vector2(PAD, HEADER_H * 0.5 + 12.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Game.COLOR_TEXT)
	var c := _close_center()
	draw_circle(c, CLOSE_R, Color(0.16, 0.08, 0.04, 0.85))
	var k := CLOSE_R * 0.42
	draw_line(c - Vector2(k, k), c + Vector2(k, k), Game.COLOR_TEXT, 5.0, true)
	draw_line(c + Vector2(-k, k), c + Vector2(k, -k), Game.COLOR_TEXT, 5.0, true)
	# Sunken felt bed behind the pieces.
	var bed := Rect2(_grid.position, _grid.size).grow(6.0)
	Game.draw_tiled(self, Game.TEX_FELT, bed, 0.8)
	draw_rect(bed, Color(0, 0, 0, 0.45), false, 3.0)


func _draw_grid() -> void:
	if not is_open():
		return
	var ids := _ids()
	var ps := model.pieces
	var s := cell * 0.84 / ps.max_extent
	var first := int(scroll / cell) * columns
	var last := mini(ids.size(), (int((scroll + _grid.size.y) / cell) + 1) * columns)
	for i in range(first, last):
		var id: int = ids[i]
		var center := Vector2((i % columns + 0.5) * cell, (i / columns + 0.5) * cell - scroll)
		_grid.draw_set_transform(center - ps.bounds[id].get_center() * s, 0.0, Vector2(s, s))
		_grid.draw_mesh(ps.meshes[id], texture)
		_grid.draw_polyline(ps.closed_outlines[id], Color(0, 0, 0, 0.5), -1.0)
	_grid.draw_set_transform(Vector2.ZERO)
	if max_scroll() > 0.0:
		# Thin scroll indicator on the right edge.
		var h := _grid.size.y * _grid.size.y / (max_scroll() + _grid.size.y)
		var y := (_grid.size.y - h) * scroll / max_scroll()
		_grid.draw_rect(Rect2(_grid.size.x - 6.0, y, 4.0, h), Color(1, 1, 1, 0.45))
