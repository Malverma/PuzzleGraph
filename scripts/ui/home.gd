extends Control
## Home: Take Photo and Create Puzzle cards side by side, then a divider and the
## saved puzzles (tap one to continue it).

const Cards := preload("res://scripts/ui/cards.gd")
const GAP := 20
const ICON_CAMERA := preload("res://assets/ui/icon_camera.png")
const ICON_CREATE := preload("res://assets/ui/icon_create.png")

var _actions: GridContainer
var _grid: GridContainer
var _cards: Array[Button] = []
var _margin: MarginContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(Game.table_bg())

	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_margin.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 16)
	scroll.add_child(col)

	var title := Label.new()
	title.text = "Puzzle Graph"
	title.add_theme_font_size_override("font_size", 48)
	col.add_child(title)

	_actions = _make_grid()
	col.add_child(_actions)
	var photo := Cards.action_card(ICON_CAMERA, "Take Photo")
	photo.pressed.connect(func() -> void: Game.go(Game.SCENE_CAMERA))
	var create := Cards.action_card(ICON_CREATE, "Create Puzzle")
	create.pressed.connect(func() -> void: Game.go(Game.SCENE_CREATE))
	for card in [photo, create]:
		_actions.add_child(card)
		_cards.append(card)

	col.add_child(Cards.divider("Saved Puzzles"))
	var saved := Game.saved_ids()
	if saved.is_empty():
		var none := Label.new()
		none.text = "No saved puzzles yet. Start one above."
		none.add_theme_color_override("font_color", Game.COLOR_TEXT_DIM)
		none.add_theme_font_size_override("font_size", 24)
		col.add_child(none)
	_grid = _make_grid()
	col.add_child(_grid)
	for id in saved:
		var card := Cards.image_card(id, "%d%%" % Game.save_progress(id))
		card.pressed.connect(_continue.bind(id))
		_grid.add_child(card)
		_cards.append(card)
	resized.connect(_layout)
	_layout()


func _make_grid() -> GridContainer:
	var g := GridContainer.new()
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", GAP)
	g.add_theme_constant_override("v_separation", GAP)
	return g


func _continue(id: String) -> void:
	Game.image_id = id
	if Game.resume_saved():
		Game.go(Game.SCENE_PLAY)


func _layout() -> void:
	var pad := 28.0
	var safe := _safe_top()
	_margin.add_theme_constant_override("margin_left", int(pad))
	_margin.add_theme_constant_override("margin_right", int(pad))
	# The title sits at the top left, clear of a centred camera hole, so only
	# the cards need to start below the cutout.
	_margin.add_theme_constant_override("margin_top", int(maxf(8.0, safe - 64.0)))
	_margin.add_theme_constant_override("margin_bottom", int(pad))
	var width := size.x - pad * 2.0
	var columns := clampi(int(width / 300.0), 2, 5)
	_actions.columns = columns
	_grid.columns = columns
	var card_w := (width - GAP * (columns - 1)) / columns
	for card in _cards:
		card.custom_minimum_size = Vector2(0, card_w * 0.75 + 64.0)


func _safe_top() -> float:
	return Game.safe_insets(get_viewport()).x


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
