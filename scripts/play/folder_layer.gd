extends Node2D
## Draws the piece folders on the board (above loose pieces) with a count
## badge, and highlights whatever a dragged piece would drop into.

## Strip of the app icon's puzzle piece in each folder colour, one square cell each.
const ICONS := preload("res://assets/ui/piece_folders.png")
const HIGHLIGHT := Color("#ffd34d")

var board: Control


func _ready() -> void:
	# Pixel art: keep the folder icon crisp at any zoom.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	var model: PuzzleModel = board.model
	if model == null:
		return
	var ps := model.pieces
	var px: float = 1.0 / board.view_scale()
	if board.drop_piece >= 0:
		var id: int = board.drop_piece
		draw_set_transform(model.pos[id])
		draw_polyline(ps.closed_outlines[id], HIGHLIGHT, 5.0 * px)
		draw_set_transform(Vector2.ZERO)
	var font := ThemeDB.fallback_font
	for f in model.folders.size():
		var r: Rect2 = board.folder_rect(f)
		if f == board.drop_folder:
			draw_circle(r.get_center(), r.size.x * 0.56, Color(HIGHLIGHT, 0.35))
			draw_arc(r.get_center(), r.size.x * 0.56, 0.0, TAU, 48, HIGHLIGHT, 5.0 * px)
		var cell := float(ICONS.get_height())
		draw_texture_rect_region(ICONS, r, Rect2(model.folders[f].color * cell, 0.0, cell, cell))
		# Piece count in a dark badge at the top right.
		var n := str(model.folders[f].ids.size())
		var fs := maxi(8, int(r.size.x * 0.22))
		var badge_r := r.size.x * 0.17
		var c := r.position + Vector2(r.size.x * 0.86, r.size.y * 0.14)
		draw_circle(c, badge_r + r.size.x * 0.02, Color("#2a170c"))
		draw_circle(c, badge_r, Color("#7a2f19"))
		var w := font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c + Vector2(-w * 0.5, fs * 0.36), n, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Game.COLOR_TEXT)
