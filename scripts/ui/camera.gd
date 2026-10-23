extends Control
## Take Photo: live camera viewfinder, shutter, then Retake / Use Photo. The
## photo becomes a player image and continues to Setup.
##
## Camera frames arrive as an RGB texture or as separate Y and CbCr textures;
## a shader converts and rotates them into a SubViewport at the feed's
## resolution, which is both the preview and what the shutter captures.
## The feed's data type and rotation are re-read every frame: on Android the
## rotation is only known once frames arrive, and it changes with the screen.

const SHADER := """
shader_type canvas_item;
uniform sampler2D y_tex : filter_linear;
uniform sampler2D cbcr_tex : filter_linear;
uniform bool rgb = false;
// Clockwise quarter turns needed to show the camera image upright.
uniform int quarter = 0;
void fragment() {
	vec2 uv = UV;
	if (quarter == 1) {
		uv = vec2(UV.y, 1.0 - UV.x);
	} else if (quarter == 2) {
		uv = vec2(1.0) - UV;
	} else if (quarter == 3) {
		uv = vec2(1.0 - UV.y, UV.x);
	}
	vec3 c;
	if (rgb) {
		c = texture(y_tex, uv).rgb;
	} else {
		float y = texture(y_tex, uv).r;
		vec2 cbcr = texture(cbcr_tex, uv).rg - vec2(0.5);
		c = vec3(y + 1.402 * cbcr.y, y - 0.344136 * cbcr.x - 0.714136 * cbcr.y, y + 1.772 * cbcr.x);
	}
	COLOR = vec4(c, 1.0);
}
"""
## Largest preview/capture size requested from the camera (pixels).
const MAX_PIXELS := 1920 * 1440

var _feed: CameraFeed
var _viewport: SubViewport
var _material: ShaderMaterial
var _preview: TextureRect
var _message: Label
var _shutter: Button
var _retake: Button
var _use: Button
var _photo: Image
var _margin: MarginContainer
var _main_tex: CameraTexture
var _surface: ColorRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(Game.table_bg())
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
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
	title.text = "Take Photo"
	title.add_theme_font_size_override("font_size", 36)
	header.add_child(title)

	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(frame)
	var stack := Control.new()
	stack.clip_contents = true
	frame.add_child(stack)
	var mat := ColorRect.new()
	mat.color = Color("#1b120c")
	mat.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(mat)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_preview)
	_message = Label.new()
	_message.set_anchors_preset(Control.PRESET_FULL_RECT)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.text = "Starting camera..."
	stack.add_child(_message)

	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 20)
	col.add_child(bar)
	_shutter = Button.new()
	_shutter.text = "Take Photo"
	_shutter.custom_minimum_size = Vector2(320, 96)
	Game.make_accent(_shutter)
	_shutter.disabled = true
	_shutter.pressed.connect(_capture)
	bar.add_child(_shutter)
	_retake = Button.new()
	_retake.text = "Retake"
	_retake.custom_minimum_size = Vector2(220, 96)
	_retake.pressed.connect(_start_preview)
	bar.add_child(_retake)
	_use = Button.new()
	_use.text = "Use Photo"
	_use.custom_minimum_size = Vector2(260, 96)
	Game.make_accent(_use)
	_use.pressed.connect(_use_photo)
	bar.add_child(_use)
	_retake.hide()
	_use.hide()

	_viewport = SubViewport.new()
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var surface := ColorRect.new()
	_surface = surface
	_material = ShaderMaterial.new()
	_material.shader = Shader.new()
	_material.shader.code = SHADER
	surface.material = _material
	_viewport.add_child(surface)

	resized.connect(_layout)
	_layout()
	_open_camera()


func _layout() -> void:
	var pad := 28.0
	for side in ["left", "right", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, int(pad))
	_margin.add_theme_constant_override("margin_top", int(pad + Game.safe_insets(get_viewport()).x))


func _open_camera() -> void:
	if OS.get_name() == "Android" and not OS.request_permission("android.permission.CAMERA"):
		var result: Array = await _permission_result()
		if not result[1]:
			_fail("Camera permission was denied. Allow it in Settings to take photos.")
			return
	CameraServer.monitoring_feeds = true
	for i in 120:
		if CameraServer.get_feed_count() > 0:
			break
		await get_tree().process_frame
	if not is_inside_tree():
		return
	_feed = _pick_feed()
	if _feed == null:
		_fail("No camera found on this device.")
		return
	_choose_format()
	_start_preview()


func _permission_result() -> Array:
	while true:
		var r: Array = await _await_signal_args(get_tree().on_request_permissions_result)
		if String(r[0]).ends_with("CAMERA"):
			return r
	return ["", false]


func _await_signal_args(sig: Signal) -> Array:
	var out := []
	var cb := func(a: Variant, b: Variant) -> void: out.append_array([a, b])
	sig.connect(cb, CONNECT_ONE_SHOT)
	while out.is_empty():
		await get_tree().process_frame
	return out


func _pick_feed() -> CameraFeed:
	var feeds := CameraServer.feeds()
	for f in feeds:
		if f.get_position() == CameraFeed.FEED_BACK:
			return f
	return feeds[0] if not feeds.is_empty() else null


## Picks the largest format at or below MAX_PIXELS, preferring YUV_420_888:
## Godot's Android camera handles its row padding properly and hands it over
## as Y + CbCr textures, while its RGBA path ignores row padding, which breaks
## the picture on many phones.
func _choose_format() -> void:
	var best := -1
	var best_score := 0
	for i in _feed.formats.size():
		var f: Dictionary = _feed.formats[i]
		var px := int(f.get("width", 0)) * int(f.get("height", 0))
		var score := px + (1 << 30 if String(f.get("format", "")) == "YUV_420_888" else 0)
		if px <= MAX_PIXELS and score > best_score:
			best = i
			best_score = score
	if best >= 0:
		_feed.set_format(best, {})


func _start_preview() -> void:
	_photo = null
	_retake.hide()
	_use.hide()
	_shutter.show()
	_shutter.disabled = true
	_message.text = "Starting camera..."
	_message.show()
	_feed.feed_is_active = true
	for i in 300:
		if _feed.get_datatype() != CameraFeed.FEED_NOIMAGE:
			break
		await get_tree().process_frame
	if not is_inside_tree() or _photo != null:
		return
	if _feed.get_datatype() == CameraFeed.FEED_NOIMAGE:
		_fail("The camera didn't send any picture.")
		return
	_bind_feed()
	_message.hide()
	_shutter.disabled = false


func _bind_feed() -> void:
	var main := CameraTexture.new()
	main.camera_feed_id = _feed.get_id()
	main.which_feed = CameraServer.FEED_Y_IMAGE
	var cbcr := CameraTexture.new()
	cbcr.camera_feed_id = _feed.get_id()
	cbcr.which_feed = CameraServer.FEED_CBCR_IMAGE
	_material.set_shader_parameter("y_tex", main)
	_material.set_shader_parameter("cbcr_tex", cbcr)
	_main_tex = main
	_set_capture_size(Vector2i(1280, 960))
	_update_feed()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview.texture = _viewport.get_texture()


func _process(_delta: float) -> void:
	if _main_tex and _viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
		_update_feed()


## Follows the feed's data type, rotation and frame size, which are only known
## once frames arrive and change when the screen rotates.
func _update_feed() -> void:
	_material.set_shader_parameter("rgb", _feed.get_datatype() == CameraFeed.FEED_RGB)
	var q := _quarter_turns()
	_material.set_shader_parameter("quarter", q)
	var sz := Vector2i(_main_tex.get_width(), _main_tex.get_height())
	if sz.x < 2:
		return
	if q % 2 == 1:
		sz = Vector2i(sz.y, sz.x)
	if _viewport.size != sz:
		_set_capture_size(sz)


## Clockwise quarter turns from the feed transform. On Android it is a pure
## rotation by (sensor orientation - screen rotation); before the first frame it
## is still the default vertical flip, which Android frames don't need.
func _quarter_turns() -> int:
	var t := _feed.feed_transform
	if t.determinant() < 0.0:
		return 0
	return posmod(roundi(rad_to_deg(t.get_rotation()) / 90.0), 4)


func _set_capture_size(sz: Vector2i) -> void:
	_viewport.size = sz
	_surface.position = Vector2.ZERO
	_surface.size = Vector2(sz)


func _capture() -> void:
	_shutter.disabled = true
	await RenderingServer.frame_post_draw
	var img := _viewport.get_texture().get_image()
	_feed.feed_is_active = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if img == null or img.is_empty():
		_fail("Couldn't capture the photo.")
		return
	_photo = img
	_preview.texture = ImageTexture.create_from_image(img)
	Game.vibrate(20)
	_shutter.hide()
	_retake.show()
	_use.show()


func _use_photo() -> void:
	if _photo == null:
		return
	_use.disabled = true
	var id := Game.import_image(_photo, Game.new_image_title("Photo"))
	if id == "":
		_fail("Couldn't save the photo.")
		_use.disabled = false
		return
	Game.image_id = id
	Game.setup_back = Game.SCENE_HOME
	Game.go(Game.SCENE_SETUP)


func _fail(text: String) -> void:
	_message.text = text
	_message.show()
	_shutter.disabled = true


func _back() -> void:
	Game.go(Game.SCENE_HOME)


func _exit_tree() -> void:
	if _feed:
		_feed.feed_is_active = false
	CameraServer.monitoring_feeds = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
