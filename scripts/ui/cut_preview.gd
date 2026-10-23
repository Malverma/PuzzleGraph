extends Control
## Small drawing of a cut style, used on the Setup screen: a few large pieces
## filled in alternating wood tones with crisp outlines, so the interlocking
## shapes read clearly at button size.

const PREVIEW_SIZE := Vector2(600, 420)
const GRID := Vector2i(4, 3)
## Creative curls are tight spirals, so it shows fewer, larger pieces to keep them open.
const GRID_CREATIVE := Vector2i(3, 2)
const FILLS: Array[Color] = [Color("#f3dfb6"), Color("#e2bd85"), Color("#ecd09c")]
const LINE_PX := 2.5

var style := CutGenerator.Style.RIBBON
var _outlines: Array[PackedVector2Array] = []
## Outlines mapped to screen pixels for the current size.
var _fills: Array[PackedVector2Array] = []
var _lines: Array[PackedVector2Array] = []
var _frame := Rect2()
var _grid := GRID


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid = GRID_CREATIVE if style == CutGenerator.Style.CREATIVE else GRID
	_outlines = CutGenerator.generate(_grid.x, _grid.y, PREVIEW_SIZE, style, 7).outlines
	resized.connect(_fit)
	_fit()


## Maps the outlines to pixels once per size, rather than drawing them under a
## scaling transform, so the outlines are drawn at exact pixel widths.
func _fit() -> void:
	var k := minf(size.x / PREVIEW_SIZE.x, size.y / PREVIEW_SIZE.y) * 0.94
	var offset := ((size - PREVIEW_SIZE * k) * 0.5).round()
	_frame = Rect2(offset, PREVIEW_SIZE * k)
	_fills.clear()
	_lines.clear()
	for poly in _outlines:
		var pts := PackedVector2Array()
		pts.resize(poly.size())
		for i in poly.size():
			pts[i] = offset + poly[i] * k
		_fills.append(pts)
		var closed := pts.duplicate()
		closed.append(pts[0])
		_lines.append(closed)
	queue_redraw()


func _draw() -> void:
	for i in _fills.size():
		draw_colored_polygon(_fills[i], FILLS[(i + i / _grid.x) % FILLS.size()])
	for line in _lines:
		draw_polyline(line, Game.COLOR_INK, LINE_PX, true)
	draw_rect(_frame, Game.COLOR_INK, false, LINE_PX + 0.5)
