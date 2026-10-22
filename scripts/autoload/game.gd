extends Node
## Global app state: image catalog, current puzzle selection, saves, settings, theme.

const PIECE_TARGETS: Array[int] = [64, 128, 256, 512, 1024]
const CATALOG_PATH := "res://puzzles/catalog.json"
const SAVE_DIR := "user://saves"
const SETTINGS_PATH := "user://settings.cfg"
## Puzzle world height in board units, independent of texture resolution.
const PUZZLE_HEIGHT := 3000.0
const SAVE_SCHEMA := 1

const COLOR_BG := Color("#14171c")
const COLOR_PANEL := Color("#1f2630")
const COLOR_PANEL_LIGHT := Color("#2d3440")
const COLOR_BOARD := Color("#232a33")
const COLOR_FRAME := Color("#2e3743")
const COLOR_TRAY := Color("#181d24")
const COLOR_ACCENT := Color("#4a90d9")
const COLOR_HINT := Color("#ffd34d")
const COLOR_TEXT := Color("#e8ecf1")
const COLOR_TEXT_DIM := Color("#9aa5b4")

const SCENE_HOME := "res://scenes/home.tscn"
const SCENE_SETUP := "res://scenes/setup.tscn"
const SCENE_PLAY := "res://scenes/play.tscn"

var catalog: Array[Dictionary] = []
var settings := ConfigFile.new()
var menu_icon: Texture2D
var snap_sound: AudioStreamWAV

# Current selection, filled in by the Setup screen before entering Play.
var image_id := ""
var piece_target := 256
var cut_style := CutGenerator.Style.RIBBON
var seed_value := 0
## Save data to restore when entering Play; empty for a fresh puzzle.
var resume: Dictionary = {}

var _thumbs := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	settings.load(SETTINGS_PATH)
	_load_catalog()
	get_tree().root.theme = _build_theme()
	menu_icon = _make_menu_icon()
	snap_sound = _make_snap_sound()
	if not catalog.is_empty():
		image_id = catalog[0].id
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autoshot="):
			var shot: Node = load("res://tests/autoshot.gd").new()
			shot.out_dir = arg.trim_prefix("--autoshot=")
			add_child(shot)


# --- Catalog & textures -----------------------------------------------------

func _load_catalog() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if data is Dictionary and data.get("images") is Array:
		for e in data.images:
			if e is Dictionary and e.has("id") and e.has("image"):
				catalog.append(e)
	if catalog.is_empty():
		push_error("Puzzle catalog missing or empty: " + CATALOG_PATH)


func get_entry(id: String) -> Dictionary:
	for e in catalog:
		if e.id == id:
			return e
	return {}


func title_of(id: String) -> String:
	return String(get_entry(id).get("title", id))


func load_thumb(id: String) -> Texture2D:
	if _thumbs.has(id):
		return _thumbs[id]
	var e := get_entry(id)
	var tex: Texture2D = null
	var thumb_path := String(e.get("thumb", ""))
	if thumb_path != "" and ResourceLoader.exists(thumb_path):
		tex = load(thumb_path)
	elif ResourceLoader.exists(String(e.get("image", ""))):
		var img := _image_from(load(e.image))
		img.resize(512, roundi(512.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_LANCZOS)
		tex = ImageTexture.create_from_image(img)
	_thumbs[id] = tex
	return tex


## Full-resolution puzzle texture, downsampled to the device budget, with mipmaps.
func load_puzzle_texture(id: String) -> Texture2D:
	var e := get_entry(id)
	var img := _image_from(load(e.image))
	var cap := max_texture_size()
	var longest := maxi(img.get_width(), img.get_height())
	if longest > cap:
		var k := float(cap) / longest
		img.resize(roundi(img.get_width() * k), roundi(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _image_from(tex: Texture2D) -> Image:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	if img.has_mipmaps():
		img.clear_mipmaps()
	return img


func is_low_memory_device() -> bool:
	if OS.has_feature("arm32") or OS.has_feature("x86_32"):
		return true
	var physical := int(OS.get_memory_info().get("physical", -1))
	return physical > 0 and physical < 3_500_000_000


func max_texture_size() -> int:
	return 2048 if is_low_memory_device() else 4096


# --- Saves --------------------------------------------------------------------

func save_path(id: String) -> String:
	return SAVE_DIR.path_join(id + ".json")


func has_save(id: String) -> bool:
	return FileAccess.file_exists(save_path(id))


func read_save(id: String) -> Dictionary:
	if not has_save(id):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path(id)))
	if data is Dictionary and int(data.get("schemaVersion", 0)) == SAVE_SCHEMA:
		return data
	return {}


## Atomic write: temp file then rename, so a crash never leaves a half-written save.
func write_save(id: String, data: Dictionary) -> bool:
	var path := save_path(id)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Could not write save: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		DirAccess.remove_absolute(path)
		err = DirAccess.rename_absolute(tmp, path)
	return err == OK


func delete_save(id: String) -> void:
	if has_save(id):
		DirAccess.remove_absolute(save_path(id))


## 0..100, or -1 if there is no save.
func save_progress(id: String) -> int:
	var data := read_save(id)
	if data.is_empty():
		return -1
	var total := maxi(1, int(data.get("total", 1)))
	return floori(100.0 * int(data.get("placed", 0)) / total)


# --- Settings -----------------------------------------------------------------

func get_setting(key: String, default: Variant) -> Variant:
	return settings.get_value("app", key, default)


func set_setting(key: String, value: Variant) -> void:
	settings.set_value("app", key, value)
	settings.save(SETTINGS_PATH)


# --- Navigation ---------------------------------------------------------------

func go(scene: String) -> void:
	get_tree().change_scene_to_file.call_deferred(scene)


## Prepares the selection for a brand-new puzzle on the current image.
func new_puzzle(target: int, style: int) -> void:
	piece_target = target
	cut_style = style
	seed_value = randi()
	resume = {}


## Prepares the selection from the current image's save. Returns false if there is none.
func resume_saved() -> bool:
	var data := read_save(image_id)
	if data.is_empty():
		return false
	piece_target = int(data.get("pieceTarget", 256))
	cut_style = CutGenerator.style_from_key(String(data.get("cutStyle", "RIBBON")))
	seed_value = int(data.get("seed", 0))
	resume = data
	return true


func vibrate(ms: int) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# --- Look & feel --------------------------------------------------------------

func _box(color: Color, radius: int, pad := 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	return sb


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 28
	var normal := _box(COLOR_PANEL_LIGHT, 14)
	var hover := _box(COLOR_PANEL_LIGHT.lightened(0.08), 14)
	var pressed := _box(COLOR_ACCENT, 14)
	var disabled := _box(COLOR_PANEL, 14)
	for type in ["Button", "MenuButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, COLOR_TEXT)
		t.set_color("font_hover_color", type, COLOR_TEXT)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, COLOR_TEXT)
		t.set_color("icon_normal_color", type, COLOR_TEXT)
	t.set_color("font_color", "Label", COLOR_TEXT)
	t.set_stylebox("panel", "PanelContainer", _box(COLOR_PANEL, 18, 24))
	t.set_stylebox("panel", "PopupMenu", _box(COLOR_PANEL_LIGHT, 12, 12))
	t.set_stylebox("hover", "PopupMenu", _box(COLOR_ACCENT, 8, 12))
	t.set_font_size("font_size", "PopupMenu", 32)
	t.set_constant("v_separation", "PopupMenu", 28)
	t.set_color("font_color", "PopupMenu", COLOR_TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("panel", "AcceptDialog", _box(COLOR_PANEL, 0, 24))
	t.set_stylebox("embedded_border", "Window", _box(COLOR_PANEL, 16, 8))
	t.set_stylebox("embedded_unfocused_border", "Window", _box(COLOR_PANEL, 16, 8))
	t.set_color("title_color", "Window", COLOR_TEXT)
	t.set_font_size("title_font_size", "Window", 28)
	t.set_stylebox("background", "ProgressBar", _box(COLOR_PANEL_LIGHT, 8, 0))
	t.set_stylebox("fill", "ProgressBar", _box(COLOR_ACCENT, 8, 0))
	return t


func _make_menu_icon() -> Texture2D:
	var img := Image.create_empty(40, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in [8, 18, 28]:
		img.fill_rect(Rect2i(4, y, 32, 4), Color.WHITE)
	return ImageTexture.create_from_image(img)


func _make_snap_sound() -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * 0.07)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var v := (sin(TAU * 900.0 * t) * 0.6 + sin(TAU * 1800.0 * t) * 0.25) * exp(-t * 70.0)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 20000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
