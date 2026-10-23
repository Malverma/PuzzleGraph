class_name PuzzleModel
extends RefCounted
## Where every piece currently is: in the tray, loose on the board, locked,
## or tucked into a folder that sits on the board.

enum { IN_TRAY, ON_BOARD, LOCKED, IN_FOLDER }

var pieces: PieceSet
var state := PackedByteArray()
## Board position (piece centre) of pieces that are ON_BOARD.
var pos := PackedVector2Array()
## Tray order, front to back.
var tray: Array[int] = []
## Loose board pieces in draw order; the last one is on top.
var loose: Array[int] = []
var locked: Array[int] = []
## Piece folders on the board, drawn above loose pieces; the last one is on top.
## Each is { "pos": Vector2 (centre), "ids": Array[int], "color": 0..FOLDER_COLORS-1 }.
## There is one folder per colour at most, so FOLDER_COLORS is also the folder limit.
var folders: Array[Dictionary] = []
const FOLDER_COLORS := 5


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
	folders.clear()
	tray.clear()
	for i in pieces.count:
		tray.append(i)
	tray.shuffle()


func remaining() -> int:
	return pieces.count - locked.size()


func is_complete() -> bool:
	return locked.size() == pieces.count


## Edge pieces to the front of the tray: top row (left to right), left column
## (top to bottom), right column (top to bottom), bottom row (left to right).
## Interior pieces follow in their current order.
func sort_tray_edges() -> void:
	var cols := pieces.cols
	var rows := pieces.rows
	var key := {}
	for i in tray.size():
		var id := tray[i]
		var c := id % cols
		var r := id / cols
		var group := 4
		var minor := i
		if r == 0:
			group = 0
			minor = c
		elif c == 0:
			group = 1
			minor = r
		elif c == cols - 1:
			group = 2
			minor = r
		elif r == rows - 1:
			group = 3
			minor = c
		key[id] = group * 1_000_000 + minor
	tray.sort_custom(func(a: int, b: int) -> bool: return key[a] < key[b])


func shuffle_tray() -> void:
	tray.shuffle()


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


## Lifts a placed piece off its spot so it can be moved again.
func unlock(id: int) -> void:
	locked.erase(id)
	state[id] = ON_BOARD


# --- Folders ------------------------------------------------------------------

func can_make_folder() -> bool:
	return folders.size() < FOLDER_COLORS


## Folder colours not used by any folder yet.
func free_colors() -> Array[int]:
	var out: Array[int] = []
	for c in FOLDER_COLORS:
		if not folders.any(func(f: Dictionary) -> bool: return f.color == c):
			out.append(c)
	return out


## Puts loose piece `target` and the dragged piece `id` into a new folder of
## colour `color` where `target` was. Returns the folder's index.
func make_folder(target: int, id: int, color: int) -> int:
	loose.erase(target)
	state[target] = IN_FOLDER
	state[id] = IN_FOLDER
	var ids: Array[int] = [target, id]
	folders.append({ "pos": pos[target], "ids": ids, "color": color })
	return folders.size() - 1


func add_to_folder(f: int, id: int) -> void:
	state[id] = IN_FOLDER
	folders[f].ids.append(id)


## Takes the piece at `index` out of folder `f`. A folder left with one piece
## turns back into that loose piece; an empty one is removed.
func take_from_folder(f: int, index: int) -> int:
	var folder: Dictionary = folders[f]
	var id: int = folder.ids.pop_at(index)
	if folder.ids.size() <= 1:
		folders.remove_at(f)
		if folder.ids.size() == 1:
			put_on_board(folder.ids[0], folder.pos)
	return id


## Moves folder `f` to the top of the draw order. Returns its new index.
func raise_folder(f: int) -> int:
	folders.append(folders.pop_at(f))
	return folders.size() - 1


## Moves every piece of folder `f` into folder `into`.
func merge_folders(f: int, into: int) -> void:
	folders[into].ids.append_array(folders[f].ids)
	folders.remove_at(f)


## Empties folder `f` into the tray starting at `index`.
func folder_to_tray(f: int, index: int) -> void:
	var ids: Array[int] = folders[f].ids
	folders.remove_at(f)
	for i in ids.size():
		put_in_tray(ids[i], index + i)


func folder_of(id: int) -> int:
	for f in folders.size():
		if id in folders[f].ids:
			return f
	return -1


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
	var folder_index := {}
	for f in folders.size():
		for i in folders[f].ids.size():
			folder_index[folders[f].ids[i]] = [f, i]
	var out := []
	for id in pieces.count:
		match state[id]:
			LOCKED:
				out.append({ "id": id, "state": "LOCKED" })
			ON_BOARD:
				out.append({ "id": id, "state": "BOARD", "x": snappedf(pos[id].x, 0.1),
						"y": snappedf(pos[id].y, 0.1), "z": loose_index[id] })
			IN_FOLDER:
				out.append({ "id": id, "state": "FOLDER", "folder": folder_index[id][0], "folderIndex": folder_index[id][1] })
			_:
				out.append({ "id": id, "state": "TRAY", "trayIndex": tray_index[id] })
	return out


## Folder positions, in the order `to_save()` numbers them.
func folders_to_save() -> Array:
	var out := []
	for f in folders:
		out.append({ "x": snappedf(f.pos.x, 0.1), "y": snappedf(f.pos.y, 0.1), "color": f.color })
	return out


## Restores from `to_save()` / `folders_to_save()` output. Returns false if the
## data doesn't match this puzzle. Pieces of a folder that no longer exists go
## back to the tray.
func load_save(list: Array, folder_list: Array = []) -> bool:
	if list.size() != pieces.count:
		return false
	state.fill(IN_TRAY)
	locked.clear()
	var tray_entries := []
	var loose_entries := []
	var folder_entries := []
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
			"FOLDER":
				var f := int(e.get("folder", -1))
				if f >= 0 and f < folder_list.size():
					state[id] = IN_FOLDER
					folder_entries.append([f, int(e.get("folderIndex", 0)), id])
				else:
					tray_entries.append([pieces.count, id])
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
	folders.clear()
	folder_entries.sort()
	var by_folder := {}
	for fe in folder_entries:
		if not by_folder.has(fe[0]):
			var d: Dictionary = folder_list[fe[0]]
			var ids: Array[int] = []
			by_folder[fe[0]] = { "pos": Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0))), "ids": ids,
					"color": posmod(int(d.get("color", fe[0])), FOLDER_COLORS) }
			folders.append(by_folder[fe[0]])
		by_folder[fe[0]].ids.append(fe[2])
	# A folder saved with a single piece is just a loose piece.
	for f in range(folders.size() - 1, -1, -1):
		if folders[f].ids.size() == 1:
			put_on_board(folders[f].ids[0], folders[f].pos)
			folders.remove_at(f)
	return true
