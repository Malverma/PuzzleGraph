extends Control
## Create Puzzle: pick an image from the device, a default background, or one
## of the player's earlier images, then continue to Setup. Holding one of the
## player's images lifts it so it can be dragged to a new spot, or onto the
## trash can to delete it along with any save made from it.

const Cards := preload("res://scripts/ui/cards.gd")
const CardSorter := preload("res://scripts/ui/card_sorter.gd")
const GAP := 20
const FILTERS := ["*.png, *.jpg, *.jpeg, *.webp ; Images ; image/png, image/jpeg, image/webp"]

var _margin: MarginContainer
var _scroll: ScrollContainer
var _grids: Array[GridContainer] = []
var _cards: Array[Button] = []
var _status: Label
var _file_dialog: FileDialog
var _mine: VBoxContainer
var _sorter: CardSorter


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(Game.table_bg())
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_margin.add_child(_scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 16)
	_scroll.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	col.add_child(header)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(120, 64)
	back.pressed.connect(_back)
	header.add_child(back)
	var title := Label.new()
	title.text = "Create Puzzle"
	title.add_theme_font_size_override("font_size", 36)
	header.add_child(title)

	var pick := Button.new()
	pick.text = "Choose Image from Device"
	pick.icon = preload("res://assets/ui/icon_create.png")
	pick.expand_icon = true
	pick.custom_minimum_size.y = 96
	pick.add_theme_constant_override("icon_max_width", 64)
	for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		pick.add_theme_color_override(c, Color.WHITE)
	pick.pressed.connect(_pick_file)
	col.add_child(pick)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Game.COLOR_TEXT_DIM)
	_status.add_theme_font_size_override("font_size", 22)
	_status.hide()
	col.add_child(_status)

	_add_section(col, "Default Backgrounds", Game.catalog.filter(func(e: Dictionary) -> bool: return not e.get("user", false)))
	var mine := Game.catalog.filter(func(e: Dictionary) -> bool: return e.get("user", false))
	if not mine.is_empty():
		_mine = _add_section(col, "Your Images", mine)
		var layer := Control.new()
		layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(layer)
		_sorter = CardSorter.new(_scroll, _mine.get_child(1), layer, func(c: Button) -> Button:
			return Cards.image_card(c.get_meta("id")))
		_sorter.reordered.connect(_save_order)
		_sorter.deleted.connect(_on_deleted)
		add_child(_sorter)
	resized.connect(_layout)
	_layout()


## A divider and a grid of image cards. Returns the section; the grid is its second child.
func _add_section(col: VBoxContainer, heading: String, entries: Array) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 16)
	col.add_child(section)
	section.add_child(Cards.divider(heading))
	var grid := GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	section.add_child(grid)
	_grids.append(grid)
	for e in entries:
		var card := Cards.image_card(e.id)
		card.set_meta("id", e.id)
		card.pressed.connect(_choose.bind(String(e.id)))
		grid.add_child(card)
		_cards.append(card)
	return section


func _choose(id: String) -> void:
	if _sorter and _sorter.blocks_press():
		return
	Game.image_id = id
	Game.setup_back = Game.SCENE_CREATE
	Game.go(Game.SCENE_SETUP)


# --- Device file ----------------------------------------------------------------

func _pick_file() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("Choose an image", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
				PackedStringArray(FILTERS), _on_native_picked)
		return
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
		_file_dialog.use_native_dialog = false
		_file_dialog.file_selected.connect(_load_file)
		add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.9)


func _on_native_picked(ok: bool, paths: PackedStringArray, _filter: int) -> void:
	if ok and not paths.is_empty():
		_load_file.call_deferred(paths[0])


func _load_file(path: String) -> void:
	_show_status("Loading image...")
	await get_tree().process_frame
	var img := Game.image_from_bytes(FileAccess.get_file_as_bytes(path))
	if img == null:
		_show_status("That file couldn't be opened as a PNG, JPEG or WebP image.")
		return
	if mini(img.get_width(), img.get_height()) < 256:
		_show_status("That image is too small for a puzzle (at least 256 px a side).")
		return
	var id := Game.import_image(img, Game.new_image_title("Image"))
	if id == "":
		_show_status("Couldn't save the image.")
		return
	_choose(id)


func _show_status(text: String) -> void:
	_status.text = text
	_status.show()


func _layout() -> void:
	var pad := 28.0
	var safe := Game.safe_insets(get_viewport()).x
	for side in ["left", "right", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, int(pad))
	_margin.add_theme_constant_override("margin_top", int(pad + safe))
	var width := size.x - pad * 2.0
	var columns := clampi(int(width / 300.0), 2, 5)
	for g in _grids:
		g.columns = columns
	var card_w := (width - GAP * (columns - 1)) / columns
	for card in _cards:
		card.custom_minimum_size = Vector2(0, card_w * 0.75 + 64.0)
	if _sorter:
		var bottom := Game.safe_insets(get_viewport()).y
		_sorter.place_trash(size - Vector2(pad, pad + bottom))


func _on_deleted(card: Button) -> void:
	Game.delete_user_image(String(card.get_meta("id")))
	_cards.erase(card)
	_mine.visible = _mine.get_child(1).get_child_count() > 0


func _save_order() -> void:
	var ids: Array[String] = []
	for c in _mine.get_child(1).get_children():
		ids.append(String(c.get_meta("id")))
	Game.set_image_order(ids)


func _back() -> void:
	Game.go(Game.SCENE_HOME)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
