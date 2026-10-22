extends Node2D
## Pulsing highlight of the hinted piece's target spot (and the piece itself
## when it is loose on the board).

var board: Control


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	board.hint_time += delta
	queue_redraw()


func _draw() -> void:
	var id: int = board.hint_id
	if id < 0 or board.model == null:
		return
	var model: PuzzleModel = board.model
	var ps := model.pieces
	var pulse := 0.55 + 0.45 * sin(board.hint_time * 6.0)
	var width: float = 4.0 / board.view_scale()
	var gold := Game.COLOR_HINT
	draw_set_transform(ps.centers[id])
	draw_colored_polygon(ps.outlines[id], Color(gold, 0.25 + 0.2 * pulse))
	draw_polyline(ps.closed_outlines[id], Color(gold, 0.5 + 0.5 * pulse), width)
	if model.state[id] == PuzzleModel.ON_BOARD:
		draw_set_transform(model.pos[id])
		draw_polyline(ps.closed_outlines[id], Color(gold, 0.5 + 0.5 * pulse), width * 1.6)
	draw_set_transform(Vector2.ZERO)
