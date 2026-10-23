extends RefCounted
## Card buttons shared by the Home and Create screens: a picture on top and a
## caption row underneath, on the wooden button style.


## A card showing an image's thumbnail and title, plus an optional right-hand badge.
static func image_card(id: String, badge := "") -> Button:
	var card := _card()
	var box: VBoxContainer = card.get_child(0)
	var pic := TextureRect.new()
	pic.texture = Game.load_thumb(id)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pic)
	box.add_child(_caption(Game.title_of(id), badge))
	return card


## A card with a centred icon on a felt panel, for actions like Take Photo.
static func action_card(icon: Texture2D, text: String) -> Button:
	var card := _card()
	var box: VBoxContainer = card.get_child(0)
	var mat := TextureRect.new()
	mat.texture = Game.TEX_FELT
	mat.stretch_mode = TextureRect.STRETCH_TILE
	mat.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	mat.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(mat)
	var pic := TextureRect.new()
	pic.texture = icon
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.offset_top = 12
	pic.offset_bottom = -12
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat.add_child(pic)
	box.add_child(_caption(text, ""))
	return card


static func _card() -> Button:
	var card := Button.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_top = 10
	box.offset_right = -10
	box.offset_bottom = -10
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	return card


static func _caption(text: String, badge: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name := Label.new()
	name.text = text
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.clip_text = true
	name.add_theme_color_override("font_color", Game.COLOR_INK)
	name.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	row.add_child(name)
	if badge != "":
		var b := Label.new()
		b.text = badge
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_color_override("font_color", Color("#7a2f19"))
		b.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
		row.add_child(b)
	return row


## Heading over a deep carved groove that runs the full width, used between
## card sections.
static func divider(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 34)
	box.add_child(l)
	var line := Control.new()
	line.custom_minimum_size.y = 14
	line.draw.connect(func() -> void:
		var w := line.size.x
		# Shadowed upper lip, dark channel, then a lit lower edge.
		line.draw_rect(Rect2(0, 2, w, 3), Color(0.1, 0.05, 0.02, 0.85))
		line.draw_rect(Rect2(0, 5, w, 4), Color(0.2, 0.1, 0.04, 0.6))
		line.draw_rect(Rect2(0, 9, w, 3), Color(1, 0.9, 0.72, 0.5)))
	line.resized.connect(line.queue_redraw)
	box.add_child(line)
	return box
