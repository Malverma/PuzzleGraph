extends Node2D
## Draws the frame, locked pieces and loose pieces in world coordinates.
## Only redrawn when pieces change; panning/zooming just moves this node.

const LOOSE_OUTLINE := Color(0, 0, 0, 0.55)
const LOCKED_OUTLINE := Color(0, 0, 0, 0.12)
const SHADOW := Color(0, 0, 0, 0.35)
## Screen pixels per texture pixel for the table and felt at zoom 1.
const TABLE_SCALE := 0.8
const FELT_SCALE := 0.8


var board: Control


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func _draw() -> void:
	var model: PuzzleModel = board.model
	if model == null:
		return
	var ps := model.pieces
	var tex: Texture2D = board.texture
	var frame := Rect2(Vector2.ZERO, ps.puzzle_size)
	# Tabletop under everything; scales with the world so it zooms with the pieces.
	var px: float = 1.0 / board.base_scale()
	var ws: Rect2 = board.workspace
	var table := ws.grow(maxf(ws.size.x, ws.size.y) * 0.25)
	var tile := Game.TEX_TABLE.get_size() * TABLE_SCALE * px
	table.position = (table.position / tile).floor() * tile
	table.end = (table.end / tile).ceil() * tile
	Game.draw_tiled(self, Game.TEX_TABLE, table, TABLE_SCALE * px)
	# Felt mat inside a raised walnut rim, with a soft shadow on the table.
	var rim := ps.cell.y * 0.12
	for k in 4:
		draw_rect(frame.grow(rim + (k + 1) * rim * 0.35), Color(0, 0, 0, 0.09))
	var rim_rect := frame.grow(rim)
	Game.draw_tiled(self, Game.TEX_TRAY, rim_rect, TABLE_SCALE * px)
	draw_rect(rim_rect, Color(0, 0, 0, 0.55), false, 2.0 * px)
	draw_rect(rim_rect.grow(-2.0 * px), Color(1, 0.85, 0.6, 0.18), false, 2.0 * px)
	Game.draw_tiled(self, Game.TEX_FELT, frame, FELT_SCALE * px)
	draw_rect(frame, Color(0, 0, 0, 0.5), false, 3.0 * px)

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
