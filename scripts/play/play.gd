extends Control
## Play screen: top bar, board, divider, tray. Owns the puzzle model, routes
## all touch input, and handles hints, saving, reset and completion.

const Board := preload("res://scripts/play/board.gd")
const Tray := preload("res://scripts/play/tray.gd")
const DragOverlay := preload("res://scripts/play/drag_overlay.gd")

enum Mode { NONE, PIECE_DRAG, PAN, PINCH, TRAY_PENDING, TRAY_SCROLL, DIVIDER, MINIMAP }
enum MenuItem { HINT, SAVE, RESET, EXIT }

const TOP_BAR_H := 60.0
const DIVIDER_H := 64.0
const DRAG_SLOP := 14.0
const TAP_MS := 300
const DOUBLE_TAP_MS := 320
const LONG_PRESS_MS := 350
## Snap distance as a fraction of the piece (cell) width, in board units.
const SNAP_TOLERANCE := 0.25
const AUTOSAVE_SECONDS := 60.0
const SNAP_SAVE_MS := 5000
const HINT_SECONDS := 4.0
const TRAY_RATIO_MIN := 0.15
const TRAY_RATIO_MAX := 0.5
const DEFAULT_TRAY_RATIO := { "portrait": 0.35, "landscape": 0.25 }

var pieces: PieceSet
var model: PuzzleModel
var texture: Texture2D
var elapsed := 0.0
var hints_used := 0
var running := false
var paused := false
var completed := false
var menu_open := false
## True when the puzzle has changed since the last successful save.
var unsaved := false

var board: Board
var tray: Tray

var _thread: Thread
var _autosave_timer := 0.0
var _last_save_ms := -100000
var _save_pending := false
var _hint_left := 0.0
var _shown_second := -1
var _tray_ratio := 0.35

# Gesture state
var _mode := Mode.NONE
var _touches := {}
var _primary := -1
var _press_pos := Vector2.ZERO
var _press_ms := 0
var _anchor := Vector2.ZERO
var _pinch_d0 := 1.0
var _pinch_z0 := 1.0
var _drag_id := -1
var _drag_offset := Vector2.ZERO
var _pending_index := -1
var _last_x := 0.0
var _last_vx := 0.0
var _last_tap_ms := -100000
var _last_tap_pos := Vector2.ZERO

# Nodes
var _top_bar: PanelContainer
var _top_style: StyleBoxTexture
var _title: Label
## Gap between the title and the right-hand items; holds a centred camera hole.
var _title_gap: Control
var _top_h := TOP_BAR_H
var _timer_label: Label
var _saved_label: Label
var _menu: MenuButton
var _divider: PanelContainer
var _count_label: Label
var _tray_buttons: HBoxContainer
var _bottom_pad: Control
var _overlay: DragOverlay
var _toast: Label
var _loading: Control
var _progress: ProgressBar
var _reset_dialog: ConfirmationDialog
var _exit_dialog: ConfirmationDialog
var _sound: AudioStreamPlayer


func _ready() -> void:
	if Game.get_entry(Game.image_id).is_empty():
		Game.go(Game.SCENE_HOME)
		return
	_build_ui()
	resized.connect(_layout)
	_layout()
	_start_generation.call_deferred()


func _exit_tree() -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null


# --- Generation ---------------------------------------------------------------

func _start_generation() -> void:
	texture = Game.load_puzzle_texture(Game.image_id)
	var aspect := float(texture.get_width()) / texture.get_height()
	var size_world := Vector2(Game.PUZZLE_HEIGHT * aspect, Game.PUZZLE_HEIGHT)
	var grid := CutGenerator.grid_for(Game.piece_target, aspect)
	pieces = PieceSet.new()
	_thread = Thread.new()
	_thread.start(pieces.compute.bind(grid, size_world, Game.cut_style, Game.seed_value))


func _finish_generation() -> void:
	pieces.build_meshes()
	model = PuzzleModel.new(pieces)
	var save := Game.resume
	Game.resume = {}
	var resumed := false
	if not save.is_empty():
		resumed = model.load_save(save.get("pieces", []))
		if resumed:
			elapsed = float(save.get("elapsedMs", 0)) / 1000.0
			hints_used = int(save.get("hintsUsed", 0))
		else:
			push_warning("Save does not match this puzzle; starting fresh")
			model.reset()
	board.setup(model, texture)
	tray.setup(model, texture)
	_overlay.model = model
	_overlay.texture = texture
	if resumed:
		var b: Dictionary = save.get("board", {})
		board.set_view(float(b.get("zoom", 1.0)), Vector2(float(b.get("panX", 0.0)), float(b.get("panY", 0.0))))
	_loading.hide()
	_menu.disabled = false
	running = true
	_update_counts()
	_update_timer(true)


# --- Frame loop ---------------------------------------------------------------

func _process(delta: float) -> void:
	if _thread:
		_progress.value = pieces.progress * 100.0
		if not _thread.is_alive():
			_thread.wait_to_finish()
			_thread = null
			_finish_generation()
		return
	if not running:
		return
	if not paused:
		elapsed += delta
		_update_timer()
		_autosave_timer += delta
		if _autosave_timer >= AUTOSAVE_SECONDS:
			save_game(false)
	if _save_pending and Time.get_ticks_msec() - _last_save_ms >= SNAP_SAVE_MS:
		save_game(false)
	if _mode == Mode.TRAY_PENDING and _pending_index >= 0 \
			and Time.get_ticks_msec() - _press_ms >= LONG_PRESS_MS:
		_pick_from_tray(_pending_index, _touches.get(_primary, _press_pos))
	if board.hint_id >= 0:
		_hint_left -= delta
		if _hint_left <= 0.0:
			_clear_hint()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			paused = true
			_finish_drag()
			if running:
				save_game(false)
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			paused = false
		NOTIFICATION_WM_CLOSE_REQUEST:
			_finish_drag()
			if running:
				save_game(false)
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_leave()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_leave()


func _leave(save := true) -> void:
	_finish_drag()
	if running and save:
		save_game(false)
	running = false
	Game.go(Game.SCENE_HOME)


## Menu "Exit to Main Menu": leaves directly when everything is saved,
## otherwise asks first.
func _request_exit() -> void:
	_finish_drag()
	if unsaved:
		_exit_dialog.popup_centered(Vector2i(600, 0))
	else:
		_leave(false)




# --- UI construction ----------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(Game.table_bg())

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)

	_top_bar = PanelContainer.new()
	_top_style = Game.wood("panel", 20)
	_top_style.content_margin_right = 12
	_top_style.content_margin_bottom = 0
	# Run the plank off the top and sides of the screen so only its lower edge shows.
	_top_style.expand_margin_top = Game.WOOD_MARGIN
	_top_style.expand_margin_left = Game.WOOD_MARGIN
	_top_style.expand_margin_right = Game.WOOD_MARGIN
	_top_bar.add_theme_stylebox_override("panel", _top_style)
	vbox.add_child(_top_bar)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	_top_bar.add_child(bar)
	_title = Label.new()
	_title.text = Game.title_of(Game.image_id)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.clip_text = true
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_title)
	_title_gap = Control.new()
	_title_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_gap.hide()
	bar.add_child(_title_gap)
	_saved_label = Label.new()
	_saved_label.text = "Saved"
	_saved_label.add_theme_color_override("font_color", Game.COLOR_ACCENT.lightened(0.3))
	_saved_label.add_theme_font_size_override("font_size", 22)
	_saved_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_saved_label.modulate.a = 0.0
	bar.add_child(_saved_label)
	_timer_label = Label.new()
	_timer_label.text = "00:00"
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_label.add_theme_color_override("font_color", Game.COLOR_TEXT_DIM)
	bar.add_child(_timer_label)
	_menu = MenuButton.new()
	_menu.icon = Game.menu_icon
	_menu.flat = false
	_menu.disabled = true
	_menu.custom_minimum_size = Vector2(72, 52)
	_menu.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_menu)
	var popup := _menu.get_popup()
	popup.add_item("Hint", MenuItem.HINT)
	popup.add_item("Save Puzzle", MenuItem.SAVE)
	popup.add_separator()
	popup.add_item("Reset Puzzle", MenuItem.RESET)
	popup.add_separator()
	popup.add_item("Exit to Main Menu", MenuItem.EXIT)
	popup.id_pressed.connect(_on_menu)
	popup.about_to_popup.connect(func() -> void: menu_open = true)
	popup.popup_hide.connect(func() -> void: menu_open = false)

	board = Board.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(board)

	_divider = PanelContainer.new()
	var div_style := Game.wood("panel", 20)
	div_style.content_margin_top = 0
	div_style.content_margin_bottom = 0
	div_style.expand_margin_left = Game.WOOD_MARGIN
	div_style.expand_margin_right = Game.WOOD_MARGIN
	_divider.add_theme_stylebox_override("panel", div_style)
	_divider.custom_minimum_size.y = DIVIDER_H
	vbox.add_child(_divider)
	var div_row := HBoxContainer.new()
	_divider.add_child(div_row)
	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 22)
	_count_label.add_theme_color_override("font_color", Game.COLOR_TEXT_DIM)
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	div_row.add_child(_count_label)
	var grip := Control.new()
	grip.custom_minimum_size = Vector2(80, 0)
	grip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grip.draw.connect(_draw_grip.bind(grip))
	div_row.add_child(grip)
	_tray_buttons = HBoxContainer.new()
	_tray_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tray_buttons.alignment = BoxContainer.ALIGNMENT_END
	_tray_buttons.add_theme_constant_override("separation", 8)
	div_row.add_child(_tray_buttons)
	_tray_buttons.add_child(_tray_button("Sort Edges", _sort_edges))
	_tray_buttons.add_child(_tray_button("Scramble", _scramble_tray))

	tray = Tray.new()
	vbox.add_child(tray)
	_bottom_pad = Control.new()
	vbox.add_child(_bottom_pad)

	_overlay = DragOverlay.new()
	add_child(_overlay)

	_toast = Label.new()
	_toast.add_theme_stylebox_override("normal", Game._box(Color(0, 0, 0, 0.75), 24, 24))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	add_child(_toast)

	_loading = _build_loading()
	add_child(_loading)

	_reset_dialog = ConfirmationDialog.new()
	_reset_dialog.title = "Reset Puzzle"
	_reset_dialog.dialog_text = "Reset puzzle? All progress will be lost."
	_reset_dialog.ok_button_text = "Reset"
	_reset_dialog.confirmed.connect(_do_reset)
	add_child(_reset_dialog)

	_exit_dialog = ConfirmationDialog.new()
	_exit_dialog.title = "Leave Puzzle"
	_exit_dialog.dialog_text = "Your latest progress isn't saved. Are you sure you want to leave?"
	_exit_dialog.dialog_autowrap = true
	_exit_dialog.ok_button_text = "Leave"
	_exit_dialog.confirmed.connect(_leave.bind(false))
	# No title-bar close button; Cancel is the way out.
	var no_icon := ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
	_exit_dialog.add_theme_icon_override("close", no_icon)
	_exit_dialog.add_theme_icon_override("close_pressed", no_icon)
	add_child(_exit_dialog)

	_sound = AudioStreamPlayer.new()
	_sound.stream = Game.snap_sound
	add_child(_sound)


func _tray_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := Game.wood("selected" if state.contains("pressed") else "button", 14)
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		b.add_theme_stylebox_override(state, sb)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(action)
	return b


func _build_loading() -> Control:
	var layer := Game.table_bg()
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	center.add_child(col)
	var label := Label.new()
	label.text = "Cutting %d pieces..." % _actual_count()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(label)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(420, 24)
	_progress.show_percentage = false
	col.add_child(_progress)
	return layer


func _actual_count() -> int:
	var thumb := Game.load_thumb(Game.image_id)
	var aspect := 4.0 / 3.0
	if thumb:
		aspect = float(thumb.get_width()) / thumb.get_height()
	var g := CutGenerator.grid_for(Game.piece_target, aspect)
	return g.x * g.y


func _draw_grip(grip: Control) -> void:
	var c := grip.size * 0.5
	for dy in [-6.0, 0.0, 6.0]:
		grip.draw_line(Vector2(c.x - 26, c.y + dy), Vector2(c.x + 26, c.y + dy), Game.COLOR_TEXT_DIM, 3.0, true)


func _layout() -> void:
	var landscape := size.x > size.y
	var key := "landscape" if landscape else "portrait"
	_tray_ratio = float(Game.get_setting("tray_ratio_" + key, DEFAULT_TRAY_RATIO[key]))
	var safe := _safe_insets()
	var hole := Game.top_cutout(get_viewport())
	var centred := hole.has_area() and hole.position.x > size.x * 0.25 and hole.end.x < size.x * 0.75
	if centred:
		# Share the row with a centred camera hole: title to its left, timer and
		# menu to its right, instead of pushing the whole bar below it.
		_top_style.content_margin_top = 0
		_top_h = maxf(TOP_BAR_H, hole.end.y + 4.0)
		_title.size_flags_horizontal = Control.SIZE_FILL
		_title.custom_minimum_size.x = maxf(0.0, hole.position.x - _top_style.content_margin_left - 12.0)
		_title_gap.show()
	else:
		_top_style.content_margin_top = safe.x
		_top_h = TOP_BAR_H + safe.x
		_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_title.custom_minimum_size.x = 0
		_title_gap.hide()
	_top_bar.custom_minimum_size.y = _top_h
	_bottom_pad.custom_minimum_size.y = safe.y
	_apply_tray_ratio(_tray_ratio)


func _available_height() -> float:
	var safe := _safe_insets()
	return size.y - _top_h - DIVIDER_H - safe.y


func _apply_tray_ratio(ratio: float) -> void:
	_tray_ratio = clampf(ratio, TRAY_RATIO_MIN, TRAY_RATIO_MAX)
	tray.custom_minimum_size.y = roundf(_available_height() * _tray_ratio)


## Top and bottom safe-area insets (notch, gesture bar) in viewport units.
func _safe_insets() -> Vector2:
	return Game.safe_insets(get_viewport())


# --- Input --------------------------------------------------------------------

func _blocked() -> bool:
	return not running or completed or menu_open or _reset_dialog.visible or _exit_dialog.visible


func _input(event: InputEvent) -> void:
	if _blocked():
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_touches[e.index] = e.position
			if _touches.size() == 1:
				_begin_single(e.index, e.position)
			elif _touches.size() == 2 and (_mode == Mode.PAN or _mode == Mode.NONE):
				_begin_pinch()
		else:
			_touches.erase(e.index)
			_end_touch(e.index, e.position)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		var step := 0.0
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			step = 1.0
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step = -1.0
		if step != 0.0:
			if _in(board, mb.position):
				board.zoom_at(mb.position - board.global_position, board.zoom * pow(1.15, step))
			elif _in(tray, mb.position):
				tray.scroll_by(-step * tray.cell)
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		if _in(board, mg.position):
			board.zoom_at(mg.position - board.global_position, board.zoom * mg.factor)
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		if _in(board, pg.position):
			board.pan_pixels(-pg.delta * 12.0)


func _in(c: Control, p: Vector2) -> bool:
	return c.get_global_rect().has_point(p)


func _board_local(p: Vector2) -> Vector2:
	return p - board.global_position


func _begin_single(idx: int, pos: Vector2) -> void:
	_primary = idx
	_press_pos = pos
	_press_ms = Time.get_ticks_msec()
	_mode = Mode.NONE
	if _in(board, pos):
		if board.minimap.visible and _in(board.minimap, pos):
			_mode = Mode.MINIMAP
			_minimap_jump(pos)
			return
		var wp := board.screen_to_world(_board_local(pos))
		var id := board.piece_at(wp)
		if id >= 0:
			var screen := board.global_position + board.world_to_screen(model.pos[id])
			model.take_from_board(id)
			board.refresh()
			_begin_drag(id, pos, screen - pos)
		else:
			_mode = Mode.PAN
			_anchor = wp
	elif _in(tray, pos):
		tray.stop()
		_mode = Mode.TRAY_PENDING
		_pending_index = tray.index_at(pos - tray.global_position)
	elif _tray_buttons.get_children().any(func(btn: Control) -> bool: return _in(btn, pos)):
		pass  # Sort / Scramble buttons handle their own taps.
	elif _in(_divider, pos):
		_mode = Mode.DIVIDER


func _begin_pinch() -> void:
	var pts := _touches.values()
	if not (_in(board, pts[0]) and _in(board, pts[1])):
		return
	_mode = Mode.PINCH
	_pinch_d0 = maxf(1.0, (pts[0] as Vector2).distance_to(pts[1]))
	_pinch_z0 = board.zoom
	_anchor = board.screen_to_world(_board_local((pts[0] + pts[1]) * 0.5))


func _on_drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index):
		return
	_touches[e.index] = e.position
	match _mode:
		Mode.PIECE_DRAG:
			if e.index == _primary:
				_overlay.move_to(e.position + _drag_offset)
		Mode.PAN:
			if e.index == _primary:
				board.set_zoom_anchored(board.zoom, _anchor, _board_local(e.position))
		Mode.PINCH:
			if _touches.size() >= 2:
				var pts := _touches.values()
				var d := maxf(1.0, (pts[0] as Vector2).distance_to(pts[1]))
				board.set_zoom_anchored(_pinch_z0 * d / _pinch_d0, _anchor, _board_local((pts[0] + pts[1]) * 0.5))
		Mode.TRAY_PENDING:
			if e.index != _primary:
				return
			var delta := e.position - _press_pos
			if delta.length() > DRAG_SLOP:
				if -delta.y > absf(delta.x) and _pending_index >= 0:
					_pick_from_tray(_pending_index, e.position)
				else:
					_mode = Mode.TRAY_SCROLL
					tray.scroll_by(-delta.x)
					_last_x = e.position.x
					_last_vx = e.velocity.x
		Mode.TRAY_SCROLL:
			if e.index == _primary:
				tray.scroll_by(_last_x - e.position.x)
				_last_x = e.position.x
				_last_vx = e.velocity.x
		Mode.DIVIDER:
			var bottom := size.y - _safe_insets().y
			_apply_tray_ratio((bottom - e.position.y - DIVIDER_H * 0.5) / _available_height())
		Mode.MINIMAP:
			_minimap_jump(e.position)


func _end_touch(idx: int, pos: Vector2) -> void:
	match _mode:
		Mode.PIECE_DRAG:
			if idx == _primary:
				_drop_piece(pos)
		Mode.PINCH:
			if _touches.size() == 1:
				_primary = _touches.keys()[0]
				_anchor = board.screen_to_world(_board_local(_touches[_primary]))
				_mode = Mode.PAN
			elif _touches.is_empty():
				_mode = Mode.NONE
		Mode.PAN:
			if idx == _primary:
				_check_double_tap(pos)
				_mode = Mode.NONE
		Mode.TRAY_SCROLL:
			if idx == _primary:
				tray.fling(-_last_vx)
				_mode = Mode.NONE
		Mode.DIVIDER:
			if idx == _primary:
				var key := "landscape" if size.x > size.y else "portrait"
				Game.set_setting("tray_ratio_" + key, _tray_ratio)
				_mode = Mode.NONE
		_:
			if idx == _primary:
				_mode = Mode.NONE


func _check_double_tap(pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if pos.distance_to(_press_pos) >= DRAG_SLOP or now - _press_ms >= TAP_MS:
		return
	if now - _last_tap_ms < DOUBLE_TAP_MS and pos.distance_to(_last_tap_pos) < 60.0:
		board.toggle_zoom(_board_local(pos))
		_last_tap_ms = -100000
	else:
		_last_tap_ms = now
		_last_tap_pos = pos


func _minimap_jump(pos: Vector2) -> void:
	var mm: Control = board.minimap
	board.center_on(mm.world_from_local(pos - mm.global_position))


# --- Pieces -------------------------------------------------------------------

func _pick_from_tray(index: int, finger: Vector2) -> void:
	var id := model.take_from_tray(index)
	tray.refresh()
	var lift := maxf(pieces.max_extent * board.view_scale() * 0.6, 56.0)
	_begin_drag(id, finger, Vector2(0.0, -lift))
	_update_counts()


func _begin_drag(id: int, finger: Vector2, offset: Vector2) -> void:
	_mode = Mode.PIECE_DRAG
	_drag_id = id
	_drag_offset = offset
	_overlay.show_piece(id, finger + offset, board.view_scale())
	if id == board.hint_id:
		_clear_hint()
	Game.vibrate(10)


func _drop_piece(finger: Vector2) -> void:
	var id := _drag_id
	_drag_id = -1
	_mode = Mode.NONE
	_overlay.hide_piece()
	if _in(tray, finger) or _in(_divider, finger):
		model.put_in_tray(id, tray.insert_index_at(finger - tray.global_position))
		tray.refresh()
	else:
		var wp := board.screen_to_world(_board_local(finger + _drag_offset))
		if wp.distance_to(pieces.centers[id]) <= pieces.cell.x * SNAP_TOLERANCE:
			model.lock(id)
			_on_snap()
		else:
			model.put_on_board(id, board.clamp_to_workspace(wp))
	unsaved = true
	board.refresh()
	_update_counts()
	if model.is_complete():
		_complete_puzzle()


## Drops whatever is being dragged where it is (used before saving / leaving).
func _finish_drag() -> void:
	if _drag_id >= 0:
		_drop_piece(_overlay.piece_pos - _drag_offset)
	_touches.clear()
	_mode = Mode.NONE


func _on_snap() -> void:
	_sound.play()
	Game.vibrate(25)
	if Time.get_ticks_msec() - _last_save_ms >= SNAP_SAVE_MS:
		save_game(false)
	else:
		_save_pending = true


func _update_counts() -> void:
	_count_label.text = "%d in tray · %d / %d placed" % [model.tray.size(), model.locked.size(), pieces.count]


func _sort_edges() -> void:
	if not running or model.tray.is_empty():
		return
	model.sort_tray_edges()
	_after_tray_reorder("Edge pieces first")


func _scramble_tray() -> void:
	if not running or model.tray.is_empty():
		return
	model.shuffle_tray()
	_after_tray_reorder("Tray scrambled")


func _after_tray_reorder(message: String) -> void:
	unsaved = true
	tray.stop()
	tray.scroll = 0.0
	tray.refresh()
	_show_toast(message)


func _update_timer(force := false) -> void:
	var sec := int(elapsed)
	if sec == _shown_second and not force:
		return
	_shown_second = sec
	_timer_label.text = format_time(sec)


static func format_time(sec: int) -> String:
	if sec >= 3600:
		return "%d:%02d:%02d" % [sec / 3600, (sec / 60) % 60, sec % 60]
	return "%02d:%02d" % [sec / 60, sec % 60]


# --- Menu ---------------------------------------------------------------------

func _on_menu(id: int) -> void:
	match id:
		MenuItem.HINT:
			give_hint()
		MenuItem.SAVE:
			save_game(true)
		MenuItem.RESET:
			_reset_dialog.popup_centered(Vector2i(560, 0))
		MenuItem.EXIT:
			_request_exit()


func give_hint() -> void:
	var options := model.unplaced()
	if options.is_empty():
		return
	var id: int = options.pick_random()
	hints_used += 1
	unsaved = true
	board.set_hint(id)
	tray.set_hint(id)
	_hint_left = HINT_SECONDS
	var b := pieces.bounds[id]
	var margin := pieces.cell.x * 0.5
	var rect := Rect2(b.position + pieces.centers[id], b.size).grow(margin)
	if model.state[id] == PuzzleModel.ON_BOARD:
		rect = rect.merge(Rect2(b.position + model.pos[id], b.size).grow(margin))
	else:
		tray.scroll_to_index(model.tray.find(id))
	board.bring_into_view(rect)


func _clear_hint() -> void:
	board.set_hint(-1)
	tray.set_hint(-1)


func _do_reset() -> void:
	_clear_hint()
	model.reset()
	elapsed = 0.0
	hints_used = 0
	_save_pending = false
	unsaved = true
	Game.delete_save(Game.image_id)
	board.reset_view()
	board.refresh()
	tray.scroll = 0.0
	tray.refresh()
	_update_counts()
	_update_timer(true)
	_show_toast("Puzzle reset")


# --- Saving -------------------------------------------------------------------

func save_data() -> Dictionary:
	return {
		"schemaVersion": Game.SAVE_SCHEMA,
		"imageId": Game.image_id,
		"pieceTarget": Game.piece_target,
		"cutStyle": CutGenerator.STYLE_KEYS[Game.cut_style],
		"seed": Game.seed_value,
		"elapsedMs": int(elapsed * 1000.0),
		"hintsUsed": hints_used,
		"board": { "zoom": snappedf(board.zoom, 0.001), "panX": snappedf(board.center.x, 0.1),
				"panY": snappedf(board.center.y, 0.1) },
		"placed": model.locked.size(),
		"total": pieces.count,
		"pieces": model.to_save(),
		"savedAt": Time.get_datetime_string_from_system(true) + "Z",
	}


func save_game(manual: bool) -> void:
	_autosave_timer = 0.0
	_last_save_ms = Time.get_ticks_msec()
	_save_pending = false
	if model == null or completed:
		return
	if _drag_id >= 0:
		_finish_drag()
	var ok := Game.write_save(Game.image_id, save_data())
	if ok:
		unsaved = false
	if manual:
		_show_toast("Puzzle saved" if ok else "Could not save puzzle")
	elif ok:
		_saved_label.modulate.a = 1.0
		create_tween().tween_property(_saved_label, "modulate:a", 0.0, 1.2).set_delay(0.6)


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.reset_size()
	_toast.position = Vector2((size.x - _toast.size.x) * 0.5, board.global_position.y + board.size.y - _toast.size.y - 28.0)
	_toast.modulate.a = 1.0
	create_tween().tween_property(_toast, "modulate:a", 0.0, 0.5).set_delay(1.4)


# --- Completion ---------------------------------------------------------------

func _complete_puzzle() -> void:
	completed = true
	running = false
	_clear_hint()
	Game.delete_save(Game.image_id)
	board.animate_to(1.0, board.workspace.get_center(), 0.6)
	Game.vibrate(60)

	var layer := ColorRect.new()
	layer.color = Color(0, 0, 0, 0.55)
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	var confetti := CPUParticles2D.new()
	confetti.position = Vector2(size.x * 0.5, -20)
	confetti.amount = 160
	confetti.lifetime = 3.5
	confetti.one_shot = true
	confetti.explosiveness = 0.85
	confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	confetti.emission_rect_extents = Vector2(size.x * 0.5, 10)
	confetti.direction = Vector2.DOWN
	confetti.spread = 30.0
	confetti.initial_velocity_min = 150.0
	confetti.initial_velocity_max = 420.0
	confetti.gravity = Vector2(0, 380)
	confetti.angular_velocity_min = -360.0
	confetti.angular_velocity_max = 360.0
	confetti.scale_amount_min = 6.0
	confetti.scale_amount_max = 12.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color("#ff5e5e"), Color("#ffd34d"), Color("#4ade80"), Color("#4a90d9"), Color("#c084fc")])
	confetti.color_initial_ramp = ramp
	layer.add_child(confetti)
	confetti.emitting = true

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Puzzle complete!"
	title.add_theme_font_size_override("font_size", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	for line in [
		"Time: " + format_time(int(elapsed)),
		"Hints used: %d" % hints_used,
		"%d pieces · %s" % [pieces.count, CutGenerator.STYLE_NAMES[Game.cut_style]],
	]:
		var l := Label.new()
		l.text = line
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", Game.COLOR_TEXT_DIM)
		col.add_child(l)
	var again := Button.new()
	again.text = "Play Again"
	again.custom_minimum_size = Vector2(420, 72)
	again.pressed.connect(_play_again)
	col.add_child(again)
	var other := Button.new()
	other.text = "Choose Another Image"
	other.custom_minimum_size = Vector2(420, 72)
	other.pressed.connect(func() -> void: Game.go(Game.SCENE_HOME))
	col.add_child(other)


func _play_again() -> void:
	Game.new_puzzle(Game.piece_target, Game.cut_style)
	Game.go(Game.SCENE_PLAY)
