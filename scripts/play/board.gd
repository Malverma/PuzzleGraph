extends Control
## The puzzle board: a zoomable, pannable workspace holding the target frame,
## locked pieces and loose pieces. Input is routed here by play.gd.

signal view_changed

const MAX_ZOOM := 8.0
const MINIMAP_ZOOM := 1.5
const BoardWorld := preload("res://scripts/play/board_world.gd")
const HintLayer := preload("res://scripts/play/hint_layer.gd")
const Minimap := preload("res://scripts/play/minimap.gd")
const FolderLayer := preload("res://scripts/play/folder_layer.gd")
## Folder size as a multiple of the largest piece, but never smaller than
## FOLDER_MIN_PX on screen so it stays easy to tap.
const FOLDER_SCALE := 1.2
const FOLDER_MIN_PX := 112.0

var model: PuzzleModel
var texture: Texture2D
var zoom := 1.0
## World point shown at the centre of the board.
var center := Vector2.ZERO
## Area pieces may be placed in: the frame plus a margin, stretched to the board's aspect.
var workspace := Rect2()
var hint_id := -1
var hint_time := 0.0
## What a dragged piece would drop into: a folder index or a loose piece id (-1 = none).
var drop_folder := -1
var drop_piece := -1

var world: Node2D
var hint_layer: Node2D
var folder_layer: Node2D
var minimap: Control
var _tween: Tween
var _anim_from := [1.0, Vector2.ZERO]
var _anim_to := [1.0, Vector2.ZERO]


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	world = BoardWorld.new()
	world.board = self
	add_child(world)
	folder_layer = FolderLayer.new()
	folder_layer.board = self
	world.add_child(folder_layer)
	hint_layer = HintLayer.new()
	hint_layer.board = self
	world.add_child(hint_layer)
	minimap = Minimap.new()
	minimap.board = self
	add_child(minimap)
	resized.connect(_on_resized)


func setup(m: PuzzleModel, tex: Texture2D) -> void:
	model = m
	texture = tex
	_update_workspace()
	center = workspace.get_center()
	zoom = 1.0
	_apply()
	minimap.layout()
	refresh()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Game.COLOR_BOARD)


func refresh() -> void:
	world.queue_redraw()
	folder_layer.queue_redraw()
	minimap.refresh()


func _on_resized() -> void:
	if model == null:
		return
	_update_workspace()
	world.queue_redraw()
	# Keep loose pieces reachable when the workspace shrinks (e.g. after rotation).
	var changed := false
	for id in model.loose:
		var p := clamp_to_workspace(model.pos[id])
		if p != model.pos[id]:
			model.pos[id] = p
			changed = true
	for f in model.folders:
		var p := clamp_to_workspace(f.pos)
		if p != f.pos:
			f.pos = p
			changed = true
	_apply()
	if changed:
		refresh()
	minimap.layout()


func _update_workspace() -> void:
	if model == null or size.x < 1.0 or size.y < 1.0:
		return
	var ps := model.pieces.puzzle_size
	var margin := maxf(ps.y * 0.05, model.pieces.max_extent * 0.6)
	var r := Rect2(-Vector2(margin, margin), ps + Vector2(margin, margin) * 2.0)
	var aspect := size.x / size.y
	if r.size.x / r.size.y < aspect:
		var extra := (r.size.y * aspect - r.size.x) * 0.5
		r = r.grow_individual(extra, 0.0, extra, 0.0)
	else:
		var extra := (r.size.x / aspect - r.size.y) * 0.5
		r = r.grow_individual(0.0, extra, 0.0, extra)
	workspace = r


func base_scale() -> float:
	if not workspace.has_area():
		return 1.0
	return minf(size.x / workspace.size.x, size.y / workspace.size.y)


## Screen pixels per world unit.
func view_scale() -> float:
	return base_scale() * zoom


func _apply() -> void:
	if not workspace.has_area():
		return
	var s := view_scale()
	var half := size / s * 0.5
	for axis in 2:
		if half[axis] * 2.0 >= workspace.size[axis]:
			center[axis] = workspace.get_center()[axis]
		else:
			center[axis] = clampf(center[axis], workspace.position[axis] + half[axis], workspace.end[axis] - half[axis])
	world.scale = Vector2(s, s)
	world.position = size * 0.5 - center * s
	if model and not model.folders.is_empty():
		folder_layer.queue_redraw()
	minimap.visible = zoom > MINIMAP_ZOOM
	minimap.update_view()
	view_changed.emit()


func screen_to_world(local: Vector2) -> Vector2:
	return (local - world.position) / world.scale.x


func world_to_screen(p: Vector2) -> Vector2:
	return p * world.scale.x + world.position


func visible_world_rect() -> Rect2:
	return Rect2(screen_to_world(Vector2.ZERO), size / view_scale())


func clamp_to_workspace(p: Vector2) -> Vector2:
	return p.clamp(workspace.position, workspace.end)


## Zooms to `z` while keeping world point `anchor` under board-local point `local`.
func set_zoom_anchored(z: float, anchor: Vector2, local: Vector2) -> void:
	_stop_tween()
	zoom = clampf(z, 1.0, MAX_ZOOM)
	center = anchor - (local - size * 0.5) / view_scale()
	_apply()


func zoom_at(local: Vector2, z: float) -> void:
	set_zoom_anchored(z, screen_to_world(local), local)


func pan_pixels(delta: Vector2) -> void:
	_stop_tween()
	center -= delta / view_scale()
	_apply()


func center_on(p: Vector2) -> void:
	_stop_tween()
	center = p
	_apply()


func set_view(z: float, c: Vector2) -> void:
	_stop_tween()
	zoom = clampf(z, 1.0, MAX_ZOOM)
	center = c
	_apply()


func animate_to(z: float, c: Vector2, duration := 0.35) -> void:
	_stop_tween()
	_anim_from = [zoom, center]
	_anim_to = [clampf(z, 1.0, MAX_ZOOM), c]
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_animate_step, 0.0, 1.0, duration)


func _animate_step(t: float) -> void:
	zoom = lerpf(_anim_from[0], _anim_to[0], t)
	center = (_anim_from[1] as Vector2).lerp(_anim_to[1], t)
	_apply()


func _stop_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null


func reset_view() -> void:
	animate_to(1.0, workspace.get_center())


## Double-tap: toggle between 1x and 3x centred on the tapped point.
func toggle_zoom(local: Vector2) -> void:
	if zoom > MINIMAP_ZOOM:
		animate_to(1.0, workspace.get_center())
	else:
		animate_to(3.0, screen_to_world(local))


## Pans/zooms (never zooming in further than now) so `rect` is fully visible.
func bring_into_view(rect: Rect2) -> void:
	if visible_world_rect().encloses(rect):
		return
	var fit := minf(size.x / rect.size.x, size.y / rect.size.y) / base_scale()
	animate_to(minf(zoom, fit), rect.get_center(), 0.5)


## Topmost loose piece under world point `p`, with a little slack for fingers.
func piece_at(p: Vector2) -> int:
	var ps := model.pieces
	for i in range(model.loose.size() - 1, -1, -1):
		var id := model.loose[i]
		if ps.contains(id, p - model.pos[id]):
			return id
	var slack := maxf(ps.cell.x * 0.35, 28.0 / view_scale())
	var best := -1
	var best_d := INF
	for id in model.loose:
		var d := p.distance_to(model.pos[id])
		if d < slack and d < best_d:
			best = id
			best_d = d
	return best


## Loose piece whose outline contains world point `p` (no finger slack), or -1.
func piece_under(p: Vector2) -> int:
	var ps := model.pieces
	for i in range(model.loose.size() - 1, -1, -1):
		var id := model.loose[i]
		if ps.contains(id, p - model.pos[id]):
			return id
	return -1


func folder_size() -> float:
	return maxf(model.pieces.max_extent * FOLDER_SCALE, FOLDER_MIN_PX / view_scale())


func folder_rect(f: int) -> Rect2:
	var s := folder_size()
	return Rect2(model.folders[f].pos - Vector2(s, s) * 0.5, Vector2(s, s))


## Topmost folder under world point `p`, or -1. `skip` ignores one folder.
func folder_at(p: Vector2, skip := -1) -> int:
	for f in range(model.folders.size() - 1, -1, -1):
		if f != skip and folder_rect(f).has_point(p):
			return f
	return -1


func set_drop_target(folder: int, piece: int) -> void:
	if folder == drop_folder and piece == drop_piece:
		return
	drop_folder = folder
	drop_piece = piece
	folder_layer.queue_redraw()


## Placed piece under `p` (world), or -1. Loose pieces are checked first by piece_at.
func placed_piece_at(p: Vector2) -> int:
	var ps := model.pieces
	for i in range(model.locked.size() - 1, -1, -1):
		var id := model.locked[i]
		if ps.contains(id, p - ps.centers[id]):
			return id
	return -1


func set_hint(id: int) -> void:
	hint_id = id
	hint_time = 0.0
	hint_layer.set_process(id >= 0)
	hint_layer.queue_redraw()
