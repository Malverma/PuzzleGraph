extends Control
## Home / image select: a grid of the bundled images. Images with a save
## show a "Continue" badge with progress.

const GAP := 20

var _grid: GridContainer
var _cards: Array[Button] = []
var _margin: MarginContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(Game.table_bg())

	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_margin.add_child(col)

	var title := Label.new()
	title.text = "Puzzle Graph"
	title.add_theme_font_size_override("font_size", 56)
	col.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Choose an image"
	subtitle.add_theme_color_override("font_color", Game.COLOR_TEXT_DIM)
	col.add_child(subtitle)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	scroll.add_child(_grid)

	for entry in Game.catalog:
		var card := _make_card(entry)
		_grid.add_child(card)
		_cards.append(card)
	resized.connect(_layout)
	_layout()


func _make_card(entry: Dictionary) -> Button:
	var id: String = entry.id
	var card := Button.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.pressed.connect(_open.bind(id))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_top = 10
	box.offset_right = -10
	box.offset_bottom = -10
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var pic := TextureRect.new()
	pic.texture = Game.load_thumb(id)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pic)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var name := Label.new()
	name.text = Game.title_of(id)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.clip_text = true
	name.add_theme_color_override("font_color", Game.COLOR_INK)
	name.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	row.add_child(name)
	var progress := Game.save_progress(id)
	if progress >= 0:
		var badge := Label.new()
		badge.text = "Continue · %d%%" % progress
		badge.add_theme_font_size_override("font_size", 22)
		badge.add_theme_color_override("font_color", Color("#7a2f19"))
		badge.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
		row.add_child(badge)
	return card


func _layout() -> void:
	var pad := 28.0
	var safe := _safe_top()
	_margin.add_theme_constant_override("margin_left", int(pad))
	_margin.add_theme_constant_override("margin_right", int(pad))
	_margin.add_theme_constant_override("margin_top", int(pad + safe))
	_margin.add_theme_constant_override("margin_bottom", int(pad))
	var width := size.x - pad * 2.0
	var columns := clampi(int(width / 300.0), 1, 5)
	_grid.columns = columns
	var card_w := (width - GAP * (columns - 1)) / columns
	for card in _cards:
		card.custom_minimum_size = Vector2(0, card_w * 0.75 + 64.0)


func _safe_top() -> float:
	if not OS.has_feature("mobile"):
		return 0.0
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	return DisplayServer.get_display_safe_area().position.y * get_viewport_rect().size.y / win.y


func _open(id: String) -> void:
	Game.image_id = id
	Game.go(Game.SCENE_SETUP)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
