extends Control
## Full-screen layer that draws the piece currently being dragged, so it can
## move freely between the tray and the board.

const LIFT := 1.05

var model: PuzzleModel
var texture: Texture2D
var piece_id := -1
var piece_pos := Vector2.ZERO
var piece_scale := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_anchors_preset(Control.PRESET_FULL_RECT)


func show_piece(id: int, at: Vector2, scale_px: float) -> void:
	piece_id = id
	piece_pos = at
	piece_scale = scale_px
	queue_redraw()


func move_to(at: Vector2) -> void:
	piece_pos = at
	queue_redraw()


func hide_piece() -> void:
	piece_id = -1
	queue_redraw()


func _draw() -> void:
	if piece_id < 0:
		return
	var ps := model.pieces
	var s := piece_scale * LIFT
	draw_set_transform(piece_pos + Vector2(6, 10), 0.0, Vector2(s, s))
	draw_mesh(ps.meshes[piece_id], texture, Transform2D.IDENTITY, Color(0, 0, 0, 0.4))
	draw_set_transform(piece_pos, 0.0, Vector2(s, s))
	draw_mesh(ps.meshes[piece_id], texture)
	draw_polyline(ps.closed_outlines[piece_id], Color(0, 0, 0, 0.6), -1.0)
	draw_set_transform(Vector2.ZERO)
