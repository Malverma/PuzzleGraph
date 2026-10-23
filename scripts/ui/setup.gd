extends Control
## Puzzle setup: choose piece count and cut style, then start. Starting over an
## image that has a save asks before overwriting it.

const CutPreview := preload("res://scripts/ui/cut_preview.gd")

var _target := 256
var _style := CutGenerator.Style.RIBBON
var _aspect := 4.0 / 3.0
var _body: BoxContainer
var _margin: MarginContainer
var _exact_label: Label
## Piece-count buttons, in PIECE_TARGETS order; their labels follow the style.
var _count_buttons: Array[Button] = []
var _overwrite_dialog: ConfirmationDialog
var _has_save := false


func _ready() -> void:
	if Game.get_entry(Game.image_id).is_empty():
		Game.go(Game.SCENE_HOME)
		return
	_target = int(Game.get_setting("setup_pieces", 256))
	_style = maxi(0, CutGenerator.find_style(str(Game.get_setting("setup_style", "RIBBON"))))
	var thumb := Game.load_thumb(Game.image_id)
	if thumb:
		_aspect = float(thumb.get_width()) / thumb.get_height()
	_has_save = Game.has_save(Game.image_id)

	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(Game.table_bg())
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	_margin.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	col.add_child(header)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(120, 64)
	back.pressed.connect(_back)
	header.add_child(back)
	var title := Label.new()
	title.text = Game.title_of(Game.image_id)
	title.add_theme_font_size_override("font_size", 36)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	header.add_child(title)

	_body = BoxContainer.new()
	_body.add_theme_constant_override("separation", 28)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)

	var pic := TextureRect.new()
	pic.texture = thumb
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(pic)

	var options := VBoxContainer.new()
	options.add_theme_constant_override("separation", 14)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(options)

	options.add_child(_heading("Pieces"))
	var counts := HBoxContainer.new()
	counts.add_theme_constant_override("separation", 10)
	options.add_child(counts)
	var count_group := ButtonGroup.new()
	for t in Game.PIECE_TARGETS:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = count_group
		b.button_pressed = t == _target
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 72
		b.pressed.connect(_set_target.bind(t))
		counts.add_child(b)
		_count_buttons.append(b)
	_exact_label = Label.new()
	_exact_label.add_theme_color_override("font_color", Game.COLOR_TEXT_DIM)
	_exact_label.add_theme_font_size_override("font_size", 22)
	options.add_child(_exact_label)

	options.add_child(_heading("Cut style"))
	var styles := GridContainer.new()
	styles.columns = 3
	styles.add_theme_constant_override("h_separation", 14)
	styles.add_theme_constant_override("v_separation", 14)
	options.add_child(styles)
	var style_group := ButtonGroup.new()
	for s in CutGenerator.STYLE_KEYS.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = style_group
		b.button_pressed = s == _style
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 200
		b.pressed.connect(_set_style.bind(s))
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 10
		box.offset_top = 10
		box.offset_right = -10
		box.offset_bottom = -8
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(box)
		var preview := CutPreview.new()
		preview.style = s
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(preview)
		var name := Label.new()
		name.text = CutGenerator.STYLE_NAMES[s]
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name.add_theme_color_override("font_color", Game.COLOR_INK)
		name.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
		box.add_child(name)
		styles.add_child(b)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	options.add_child(spacer)

	# Saved puzzles are continued from Home, so Setup only starts new ones.
	var start := Button.new()
	start.text = "Start New" if _has_save else "Start"
	start.custom_minimum_size.y = 84
	Game.make_accent(start)
	start.pressed.connect(_start)
	options.add_child(start)

	_overwrite_dialog = ConfirmationDialog.new()
	_overwrite_dialog.title = "Start New"
	_overwrite_dialog.dialog_text = "Overwrite saved progress?"
	_overwrite_dialog.ok_button_text = "Overwrite"
	_overwrite_dialog.confirmed.connect(_launch_new)
	add_child(_overwrite_dialog)

	_update_exact()
	resized.connect(_layout)
	_layout()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 30)
	return l


func _layout() -> void:
	_body.vertical = size.x <= size.y
	var safe := Game.safe_insets(get_viewport()).x
	for side in ["left", "right", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 28)
	_margin.add_theme_constant_override("margin_top", int(28 + safe))


func _set_target(t: int) -> void:
	_target = t
	_update_exact()


func _set_style(s: int) -> void:
	_style = s
	_update_exact()


## Exact piece counts for the chosen style, and a note on its layout.
func _update_exact() -> void:
	for i in _count_buttons.size():
		var g := CutGenerator.layout_for(Game.PIECE_TARGETS[i], _aspect, _style)
		_count_buttons[i].text = str(CutGenerator.piece_count(g, _style))
	var g := CutGenerator.layout_for(_target, _aspect, _style)
	match _style:
		CutGenerator.Style.RIBBON, CutGenerator.Style.RANDOM:
			_exact_label.text = "%d × %d grid" % [g.x, g.y]
		CutGenerator.Style.ANGULAR:
			_exact_label.text = "Honeycomb, about %d × %d" % [g.x, g.y]
		_:
			_exact_label.text = "Irregular pieces, about %d × %d" % [g.x, g.y]


func _start() -> void:
	if _has_save:
		_overwrite_dialog.popup_centered(Vector2i(560, 0))
	else:
		_launch_new()


func _launch_new() -> void:
	Game.set_setting("setup_pieces", _target)
	Game.set_setting("setup_style", CutGenerator.STYLE_KEYS[_style])
	Game.delete_save(Game.image_id)
	Game.new_puzzle(_target, _style)
	Game.go(Game.SCENE_PLAY)


func _back() -> void:
	Game.go(Game.setup_back)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
