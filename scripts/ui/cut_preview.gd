extends Control
## Small line drawing of a cut style, used on the Setup screen.

const PREVIEW_SIZE := Vector2(600, 400)

var style := CutGenerator.Style.RIBBON
var _lines: Array[PackedVector2Array] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var data := CutGenerator.generate(6, 4, PREVIEW_SIZE, style, 7)
	for poly: PackedVector2Array in data.outlines:
		var closed := poly.duplicate()
		closed.append(poly[0])
		_lines.append(closed)


func _draw() -> void:
	var k := minf(size.x / PREVIEW_SIZE.x, size.y / PREVIEW_SIZE.y) * 0.92
	var offset := (size - PREVIEW_SIZE * k) * 0.5
	draw_rect(Rect2(offset, PREVIEW_SIZE * k), Color(1, 1, 1, 0.06))
	draw_set_transform(offset, 0.0, Vector2(k, k))
	for line in _lines:
		draw_polyline(line, Game.COLOR_TEXT, 1.5 / k, true)
	draw_set_transform(Vector2.ZERO)
