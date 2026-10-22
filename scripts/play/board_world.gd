extends Node2D
## Draws the frame, locked pieces and loose pieces in world coordinates.
## Only redrawn when pieces change; panning/zooming just moves this node.

const LOOSE_OUTLINE := Color(0, 0, 0, 0.55)
const LOCKED_OUTLINE := Color(0, 0, 0, 0.12)
const SHADOW := Color(0, 0, 0, 0.35)

var board: Control


func _draw() -> void:
	var model: PuzzleModel = board.model
	if model == null:
		return
	var ps := model.pieces
	var tex: Texture2D = board.texture
	var frame := Rect2(Vector2.ZERO, ps.puzzle_size)
	draw_rect(frame, Game.COLOR_FRAME)
	draw_rect(frame, Color(1, 1, 1, 0.18), false, -1.0)

	for id in model.locked:
		draw_set_transform(ps.centers[id])
		draw_mesh(ps.meshes[id], tex)
	for id in model.locked:
		draw_set_transform(ps.centers[id])
		draw_polyline(ps.closed_outlines[id], LOCKED_OUTLINE, -1.0)

	var shadow_offset := ps.cell * 0.04
	for id in model.loose:
		draw_set_transform(model.pos[id] + shadow_offset)
		draw_mesh(ps.meshes[id], tex, Transform2D.IDENTITY, SHADOW)
		draw_set_transform(model.pos[id])
		draw_mesh(ps.meshes[id], tex)
		draw_polyline(ps.closed_outlines[id], LOOSE_OUTLINE, -1.0)
	draw_set_transform(Vector2.ZERO)
