extends Node
## Hold-to-move for one grid of cards inside a ScrollContainer, shared by the
## Home and Create screens. Holding a card lifts it so it can be dragged to a
## new spot, or onto a trash can that appears in the bottom-right corner.
## Emits `reordered` after a move and `deleted(card)` after a card is dropped
## on the trash (the card is already out of the grid and will be freed).

signal reordered
signal deleted(card: Button)

const ICON_TRASH := preload("res://assets/ui/icon_trash.png")
const ICON_TRASH_OPEN := preload("res://assets/ui/icon_trash_open.png")
## Hold time before a card lifts; moving further than HOLD_SLOP first scrolls instead.
const HOLD_MS := 350
const HOLD_SLOP := 16.0
const LIFT_SCALE := 1.06
const TRASH_SIZE := 144.0
## Distance from the top or bottom edge where a held card scrolls the list.
const EDGE_SCROLL := 140.0
const EDGE_SPEED := 1200.0

var _scroll: ScrollContainer
var _grid: GridContainer
var _layer: Control
## Builds the floating copy of a card that follows the finger.
var _make_float: Callable
var _trash: Control

## Card under the finger while waiting to see if it is a hold or a scroll.
var _pending: Button
var _touch := -1
var _press_pos := Vector2.ZERO
var _press_ms := 0
var _finger := Vector2.ZERO
## Card being moved. It stays in the grid, faded, to mark where it will land.
var _held: Button
var _float: Button
var _grab := Vector2.ZERO
var _over_trash := false
## Stops the release that ends a hold from also pressing the card.
var _block_press := false


## `layer` is a full-screen, mouse-ignoring Control drawn above `scroll`.
func _init(scroll: ScrollContainer, grid: GridContainer, layer: Control, make_float: Callable) -> void:
	_scroll = scroll
	_grid = grid
	_layer = layer
	_make_float = make_float
	_trash = Control.new()
	_trash.size = Vector2(TRASH_SIZE, TRASH_SIZE)
	_trash.pivot_offset = _trash.size * 0.5
	_trash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_trash.draw.connect(_draw_trash)
	_trash.hide()
	_layer.add_child(_trash)


## True while a card is held, or for the release that ended a hold. Card
## press handlers should ignore the press then.
func blocks_press() -> bool:
	return _block_press or _held != null


## Puts the trash can's bottom-right corner at `corner` (layer coordinates).
func place_trash(corner: Vector2) -> void:
	_trash.position = corner - _trash.size


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pending = null
		_touch = -1
		if _held:
			_over_trash = false
			_drop()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch < 0 and not _held:
			_block_press = false
			var card := _card_at(event.position)
			if card:
				_touch = event.index
				_pending = card
				_press_pos = event.position
				_finger = event.position
				_press_ms = Time.get_ticks_msec()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			_pending = null
			if _held:
				_drop()
	elif event is InputEventScreenDrag and event.index == _touch:
		_finger = event.position
		if _pending and _finger.distance_to(_press_pos) > HOLD_SLOP:
			_pending = null
		if _held:
			_move_held()
	# While a card is held, keep the drag away from the scroll container and buttons.
	if _held and (event is InputEventScreenDrag or event is InputEventMouseMotion):
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _pending and Time.get_ticks_msec() - _press_ms >= HOLD_MS:
		_lift(_pending)
	if not _held or _over_trash:
		return
	var r := _scroll.get_global_rect()
	var v := 0.0
	if _finger.y < r.position.y + EDGE_SCROLL:
		v = -EDGE_SPEED * (1.0 - (_finger.y - r.position.y) / EDGE_SCROLL)
	elif _finger.y > r.end.y - EDGE_SCROLL:
		v = EDGE_SPEED * (1.0 - (r.end.y - _finger.y) / EDGE_SCROLL)
	if v != 0.0:
		var before := _scroll.scroll_vertical
		_scroll.scroll_vertical += int(clampf(v, -EDGE_SPEED, EDGE_SPEED) * delta)
		if _scroll.scroll_vertical != before:
			_reorder()


func _card_at(pos: Vector2) -> Button:
	if not _scroll.get_global_rect().has_point(pos) or not _grid.is_visible_in_tree():
		return null
	for c: Button in _grid.get_children():
		if not c.is_queued_for_deletion() and c.get_global_rect().has_point(pos):
			return c
	return null


func _lift(card: Button) -> void:
	_pending = null
	_held = card
	_block_press = true
	var rect := card.get_global_rect()
	_grab = _finger - rect.position
	_float = _make_float.call(card)
	_float.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float.custom_minimum_size = rect.size
	_float.size = rect.size
	_float.pivot_offset = _grab
	_layer.add_child(_float)
	_layer.move_child(_trash, -1)
	_float.position = rect.position
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_float, "scale", Vector2.ONE * LIFT_SCALE, 0.15)
	t.tween_property(_float, "rotation_degrees", 2.0, 0.15)
	card.modulate = Color(0.35, 0.22, 0.14, 0.45)

	_over_trash = false
	_trash.scale = Vector2.ONE * 0.6
	_trash.modulate.a = 0.0
	_trash.show()
	_trash.queue_redraw()
	var tt := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tt.tween_property(_trash, "scale", Vector2.ONE, 0.2)
	tt.tween_property(_trash, "modulate:a", 1.0, 0.15)
	Game.vibrate(30)


func _move_held() -> void:
	_float.position = _finger - _grab
	var over := _trash.get_global_rect().grow(24).has_point(_finger)
	if over != _over_trash:
		_over_trash = over
		_trash.queue_redraw()
		var t := create_tween().set_parallel()
		t.tween_property(_trash, "scale", Vector2.ONE * (1.2 if over else 1.0), 0.1)
		t.tween_property(_float, "modulate", Color(1, 0.55, 0.5, 0.75) if over else Color.WHITE, 0.1)
		# Shrink toward the finger so the can stays visible underneath.
		t.tween_property(_float, "scale", Vector2.ONE * (0.45 if over else LIFT_SCALE), 0.1)
		Game.vibrate(15)
	if not over:
		_reorder()


## Moves the held card's slot to wherever the finger is over another card.
func _reorder() -> void:
	for c: Button in _grid.get_children():
		if c != _held and c.get_global_rect().has_point(_finger):
			_grid.move_child(_held, c.get_index())
			return


func _drop() -> void:
	var card := _held
	var f := _float
	_held = null
	_float = null
	if _over_trash:
		_over_trash = false
		_grid.remove_child(card)
		deleted.emit(card)
		card.queue_free()
		Game.vibrate(40)
		var t := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		f.pivot_offset = f.size * 0.5
		t.tween_property(f, "position", _trash.position + _trash.size * 0.5 - f.size * 0.5, 0.18)
		t.tween_property(f, "scale", Vector2.ONE * 0.05, 0.18)
		t.tween_property(f, "modulate:a", 0.0, 0.18)
		t.chain().tween_callback(f.queue_free)
	else:
		reordered.emit()
		var t := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(f, "position", card.global_position, 0.15)
		t.tween_property(f, "scale", Vector2.ONE, 0.15)
		t.tween_property(f, "rotation_degrees", 0.0, 0.15)
		t.chain().tween_callback(func() -> void:
			card.modulate = Color.WHITE
			f.queue_free())
	var tt := create_tween().set_parallel()
	tt.tween_property(_trash, "scale", Vector2.ONE * 0.6, 0.15)
	tt.tween_property(_trash, "modulate:a", 0.0, 0.15)
	tt.chain().tween_callback(func() -> void:
		if not _held:
			_trash.hide())


## The trash can on a dark round shadow, lid open while a card hovers over it.
func _draw_trash() -> void:
	var c := _trash.size * 0.5
	_trash.draw_circle(c + Vector2(0, 4), c.x, Color(0.08, 0.04, 0.02, 0.45))
	_trash.draw_circle(c, c.x - 4, Color(0.55, 0.16, 0.1, 0.9) if _over_trash else Color(0.18, 0.1, 0.05, 0.85))
	var icon := ICON_TRASH_OPEN if _over_trash else ICON_TRASH
	var s := _trash.size.x * 0.72
	_trash.draw_texture_rect(icon, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false)
