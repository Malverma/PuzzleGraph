extends Control
## Horizontally scrolling tray of unplaced pieces. Only visible slots are drawn.
## Input is routed here by play.gd.

const MIN_CELL := 130.0
const FRICTION := 0.02  # velocity multiplier per second while flinging
const TRAY_TEX_SCALE := 0.75

var model: PuzzleModel
var texture: Texture2D
var scroll := 0.0
var velocity := 0.0
var rows := 1
var cell := 100.0
var hint_id := -1
var hint_time := 0.0
var _scroll_tween: Tween


func _ready() -> void:
	clip_contents = true
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(_layout)


func setup(m: PuzzleModel, tex: Texture2D) -> void:
	model = m
	texture = tex
	_layout()


func _layout() -> void:
	rows = clampi(int(size.y / MIN_CELL), 1, 4)
	cell = size.y / rows
	scroll = clampf(scroll, 0.0, max_scroll())
	queue_redraw()


func refresh() -> void:
	scroll = clampf(scroll, 0.0, max_scroll())
	queue_redraw()


func max_scroll() -> float:
	if model == null:
		return 0.0
	var columns := ceili(model.tray.size() / float(rows))
	return maxf(0.0, columns * cell - size.x)


func scroll_by(dx: float) -> void:
	_stop_tween()
	scroll = clampf(scroll + dx, 0.0, max_scroll())
	queue_redraw()


func fling(v: float) -> void:
	velocity = v


func stop() -> void:
	velocity = 0.0
	_stop_tween()


func _stop_tween() -> void:
	if _scroll_tween and _scroll_tween.is_valid():
		_scroll_tween.kill()


func scroll_to_index(i: int) -> void:
	stop()
	var target := clampf((i / rows) * cell + cell * 0.5 - size.x * 0.5, 0.0, max_scroll())
	_scroll_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_scroll_tween.tween_method(_set_scroll, scroll, target, 0.4)


func _set_scroll(v: float) -> void:
	scroll = v
	queue_redraw()


func index_at(local: Vector2) -> int:
	if model == null or local.y < 0.0 or local.y >= size.y:
		return -1
	var i := int((local.x + scroll) / cell) * rows + int(local.y / cell)
	return i if i >= 0 and i < model.tray.size() else -1


## Slot a dropped piece should be inserted at.
func insert_index_at(local: Vector2) -> int:
	var col := int((local.x + scroll) / cell)
	var row := clampi(int(local.y / cell), 0, rows - 1)
	return clampi(col * rows + row, 0, model.tray.size())


func thumb_scale() -> float:
	return cell * 0.86 / model.pieces.max_extent


func set_hint(id: int) -> void:
	hint_id = id
	hint_time = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if absf(velocity) > 5.0:
		var before := scroll
		scroll_by(velocity * delta)
		velocity *= pow(FRICTION, delta)
		if scroll == before:
			velocity = 0.0
	if hint_id >= 0:
		hint_time += delta
		queue_redraw()


func _draw() -> void:
	# Walnut tray bed that slides with the scroll, with a recessed top edge.
	var tw := Game.TEX_TRAY.get_width() * TRAY_TEX_SCALE
	var off := fposmod(scroll, tw)
	Game.draw_tiled(self, Game.TEX_TRAY, Rect2(-off, 0.0, size.x + tw, size.y), TRAY_TEX_SCALE)
	for k in 6:
		draw_rect(Rect2(0.0, k * 3.0, size.x, 3.0), Color(0, 0, 0, 0.4 - k * 0.065))
	if model == null:
		return
	var n := model.tray.size()
	if n == 0:
		var font := get_theme_default_font()
		var msg := "All pieces are on the board"
		var fs := 26
		var w := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2((size.x - w) * 0.5, size.y * 0.5), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Game.COLOR_TEXT_DIM)
		return
	var ps := model.pieces
	var s := thumb_scale()
	var first_col := int(scroll / cell)
	var last_col := int((scroll + size.x) / cell)
	var pulse := 0.55 + 0.45 * sin(hint_time * 6.0)
	for col in range(first_col, last_col + 1):
		for row in rows:
			var i := col * rows + row
			if i >= n:
				break
			var id := model.tray[i]
			var slot_center := Vector2(col * cell - scroll + cell * 0.5, row * cell + cell * 0.5)
			var origin := slot_center - ps.bounds[id].get_center() * s
			draw_set_transform(origin, 0.0, Vector2(s, s))
			draw_mesh(ps.meshes[id], texture)
			draw_polyline(ps.closed_outlines[id], Color(0, 0, 0, 0.5), -1.0)
			if id == hint_id:
				draw_polyline(ps.closed_outlines[id], Color(Game.COLOR_HINT, 0.5 + 0.5 * pulse), 4.0 / s)
	draw_set_transform(Vector2.ZERO)
