extends Control
## Overview of the whole workspace shown while zoomed in. Tapping or dragging
## on it moves the board's viewport (input routed from play.gd).

const MARGIN := 12.0

var board: Control
var _view_rect: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_view_rect = Control.new()
	_view_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view_rect.draw.connect(_draw_view_rect)
	add_child(_view_rect)


func layout() -> void:
	var ws: Rect2 = board.workspace
	if not ws.has_area():
		return
	var w := minf(board.size.x * 0.3, 280.0)
	var h := w * ws.size.y / ws.size.x
	var max_h := board.size.y * 0.3
	if h > max_h:
		w *= max_h / h
		h = max_h
	size = Vector2(w, h)
	position = board.size - size - Vector2(MARGIN, MARGIN)
	refresh()


func _scale() -> float:
	return size.x / board.workspace.size.x


func world_from_local(local: Vector2) -> Vector2:
	return board.workspace.position + local / _scale()


func refresh() -> void:
	queue_redraw()
	update_view()


func update_view() -> void:
	if _view_rect:
		_view_rect.queue_redraw()


func _draw() -> void:
	var model: PuzzleModel = board.model
	if model == null or not board.workspace.has_area():
		return
	var s := _scale()
	var origin: Vector2 = -board.workspace.position * s
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	var ps := model.pieces
	draw_rect(Rect2(origin, ps.puzzle_size * s), Game.COLOR_FRAME)
	for id in model.locked:
		draw_mesh(ps.meshes[id], board.texture, Transform2D(0.0, Vector2(s, s), 0.0, origin + ps.centers[id] * s))
	var dot := maxf(2.0, ps.cell.x * s * 0.5)
	for id in model.loose:
		draw_rect(Rect2(origin + model.pos[id] * s - Vector2(dot, dot) * 0.5, Vector2(dot, dot)), Color(1, 1, 1, 0.7))
	for f in model.folders:
		draw_rect(Rect2(origin + f.pos * s - Vector2(dot, dot), Vector2(dot, dot) * 2.0), Color(Game.COLOR_HINT, 0.85))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.35), false, 1.0)


func _draw_view_rect() -> void:
	if board.model == null or not board.workspace.has_area():
		return
	var s := _scale()
	var r: Rect2 = board.visible_world_rect()
	r.position = (r.position - board.workspace.position) * s
	r.size *= s
	_view_rect.draw_rect(r, Game.COLOR_HINT, false, 2.0)
