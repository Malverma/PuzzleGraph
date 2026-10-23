extends SceneTree
## Draws the pixel-art trash can used on Home while a saved puzzle is held:
## assets/ui/icon_trash.png (closed) and icon_trash_open.png (lid tipped up).
## 32x32 art, saved pre-scaled 4x like the other icons.
## Run: godot --headless -s tools/gen_trash_icon.gd

const SIZE := 32
const SCALE := 4
const OUT := Color("#2b1a12")
const DARK := Color("#4a5160")
const MID := Color("#6c7586")
const LIGHT := Color("#949db0")
const HIGH := Color("#c4ccd8")
const INSIDE := Color("#1c120c")
const SHADOW := Color(0, 0, 0, 0.3)


func _init() -> void:
	_save(_draw(false), "res://assets/ui/icon_trash.png")
	_save(_draw(true), "res://assets/ui/icon_trash_open.png")
	quit()


func _draw(open: bool) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	# Floor shadow.
	for x in range(8, 24):
		img.set_pixel(x, 30, SHADOW)
	# Body: tapers 2 px per side from the rim down, with vertical ribs.
	for y in range(13, 30):
		var t := (y - 13) / 8
		var l := 6 + t
		var r := 25 - t
		for x in range(l, r + 1):
			var c := MID
			if x == l or x == r or y == 29:
				c = OUT
			elif y == 28:
				c = DARK
			elif x == l + 1:
				c = HIGH
			elif x == r - 1:
				c = DARK
			elif (x - 8) % 4 == 0 and y > 14 and y < 27:
				c = DARK
			elif (x - 8) % 4 == 1 and y > 14 and y < 27:
				c = LIGHT
			img.set_pixel(x, y, c)
	# Rim.
	for x in range(5, 27):
		img.set_pixel(x, 12, OUT)
	if open:
		for x in range(7, 25):
			img.set_pixel(x, 13, INSIDE)
			img.set_pixel(x, 14, INSIDE if x > 7 and x < 24 else img.get_pixel(x, 14))
	# Lid: 24 wide, 4 tall; open tips it up on the right, lifted off the rim.
	var lift := 2 if open else 0
	for x in range(4, 28):
		var dy := _tilt(x, lift, open)
		for row in 4:
			var y := 8 + row + dy
			var c := LIGHT
			if row == 0 or row == 3 or x == 4 or x == 27:
				c = OUT
			elif row == 1:
				c = HIGH if x < 26 else MID
			elif x >= 26:
				c = MID
			img.set_pixel(x, y, c)
	# Handle on top of the lid's middle.
	for x in range(12, 20):
		var dy := _tilt(x, lift, open)
		img.set_pixel(x, 5 + dy, OUT)
		if x == 12 or x == 13 or x == 18 or x == 19:
			img.set_pixel(x, 6 + dy, OUT)
			img.set_pixel(x, 7 + dy, OUT)
		elif x > 13 and x < 18:
			img.set_pixel(x, 6 + dy, LIGHT)
	return img


## Vertical offset of the lid at column x.
func _tilt(x: int, lift: int, open: bool) -> int:
	return -lift - ((x - 4) / 6 if open else 0)


func _save(img: Image, path: String) -> void:
	img.resize(SIZE * SCALE, SIZE * SCALE, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
	print("wrote ", path)
