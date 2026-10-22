class_name PuzzleModel
extends RefCounted
## Where every piece currently is: in the tray, loose on the board, or locked.

enum { IN_TRAY, ON_BOARD, LOCKED }

var pieces: PieceSet
var state := PackedByteArray()
## Board position (piece centre) of pieces that are ON_BOARD.
var pos := PackedVector2Array()
## Tray order, front to back.
var tray: Array[int] = []
## Loose board pieces in draw order; the last one is on top.
var loose: Array[int] = []
var locked: Array[int] = []


func _init(piece_set: PieceSet) -> void:
	pieces = piece_set
	state.resize(pieces.count)
	pos.resize(pieces.count)
	reset()


## Every piece back into the tray in a new shuffled order.
func reset() -> void:
	state.fill(IN_TRAY)
	loose.clear()
	locked.clear()
	tray.clear()
	for i in pieces.count:
		tray.append(i)
	tray.shuffle()


func remaining() -> int:
	return pieces.count - locked.size()


func is_complete() -> bool:
	return locked.size() == pieces.count


func take_from_tray(index: int) -> int:
	return tray.pop_at(index)


func put_in_tray(id: int, index: int) -> void:
	state[id] = IN_TRAY
	tray.insert(clampi(index, 0, tray.size()), id)


func take_from_board(id: int) -> void:
	loose.erase(id)


func put_on_board(id: int, p: Vector2) -> void:
	state[id] = ON_BOARD
	pos[id] = p
	loose.append(id)


func lock(id: int) -> void:
	state[id] = LOCKED
	pos[id] = pieces.centers[id]
	locked.append(id)


func unplaced() -> Array[int]:
	var out: Array[int] = []
	for i in pieces.count:
		if state[i] != LOCKED:
			out.append(i)
	return out


func to_save() -> Array:
	var tray_index := {}
	for i in tray.size():
		tray_index[tray[i]] = i
	var loose_index := {}
	for i in loose.size():
		loose_index[loose[i]] = i
	var out := []
	for id in pieces.count:
		match state[id]:
			LOCKED:
				out.append({ "id": id, "state": "LOCKED" })
			ON_BOARD:
				out.append({ "id": id, "state": "BOARD", "x": snappedf(pos[id].x, 0.1),
						"y": snappedf(pos[id].y, 0.1), "z": loose_index[id] })
			_:
				out.append({ "id": id, "state": "TRAY", "trayIndex": tray_index[id] })
	return out


## Restores from `to_save()` output. Returns false if the data doesn't match this puzzle.
func load_save(list: Array) -> bool:
	if list.size() != pieces.count:
		return false
	state.fill(IN_TRAY)
	locked.clear()
	var tray_entries := []
	var loose_entries := []
	for e in list:
		var id := int(e.get("id", -1))
		if id < 0 or id >= pieces.count:
			return false
		match String(e.get("state", "TRAY")):
			"LOCKED":
				lock(id)
			"BOARD":
				state[id] = ON_BOARD
				pos[id] = Vector2(float(e.get("x", 0.0)), float(e.get("y", 0.0)))
				loose_entries.append([int(e.get("z", 0)), id])
			_:
				tray_entries.append([int(e.get("trayIndex", 0)), id])
	tray_entries.sort()
	loose_entries.sort()
	tray.clear()
	for t in tray_entries:
		tray.append(t[1])
	loose.clear()
	for l in loose_entries:
		loose.append(l[1])
	return true
