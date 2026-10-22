extends Node
## Dev tool: drives every screen and saves screenshots.
## Run: godot --path . -- --autoshot=/some/dir   (add --headless for a logic-only run)

var out_dir := ""


func _ready() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[autoshot] (headless) ", name)
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("[autoshot] saved ", name)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _play(previous_id := 0) -> Node:
	for i in 200:
		var scene := get_tree().current_scene
		if scene and scene.get_instance_id() != previous_id and scene.get("running") == true:
			return scene
		await _wait(0.05)
	push_error("[autoshot] play scene never became ready")
	return get_tree().current_scene


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	for id in ["img_01", "img_02", "img_03", "img_04", "img_05"]:
		Game.delete_save(id)
	_resize(Vector2i(540, 960))
	await _wait(0.8)
	await _shot("01_home")

	Game.image_id = "img_03"
	Game.go(Game.SCENE_SETUP)
	await _wait(0.8)
	await _shot("02_setup")

	# Fresh Random Cut puzzle, partially solved.
	Game.image_id = "img_03"
	Game.new_puzzle(256, CutGenerator.Style.RANDOM)
	Game.go(Game.SCENE_PLAY)
	var play := await _play()
	await _wait(0.3)
	await _shot("03_play_start")
	var model: PuzzleModel = play.model
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 120:
		var id: int = model.tray.pop_back()
		model.lock(id)
	for k in 25:
		var id: int = model.tray.pop_back()
		var ws: Rect2 = play.board.workspace
		model.put_on_board(id, Vector2(rng.randf_range(ws.position.x, ws.end.x), rng.randf_range(ws.end.y - 500, ws.end.y - 100)))
	play.board.refresh()
	play.tray.refresh()
	play._update_counts()
	await _wait(0.2)
	await _shot("04_play_progress")

	play.board.set_view(3.0, model.pieces.puzzle_size * 0.5)
	await _wait(0.2)
	await _shot("05_zoom_minimap")

	play.give_hint()
	await _wait(0.8)
	await _shot("06_hint")

	# Simulated drag of a tray piece onto its home spot via real input events.
	play._clear_hint()
	play.tray.stop()
	play.tray.scroll = 0.0
	play.board.set_view(1.0, play.board.workspace.get_center())
	await _wait(0.1)
	var tray_before: int = model.tray.size()
	var id0: int = model.tray[0]
	var start: Vector2 = play.tray.global_position + Vector2(play.tray.cell * 0.5, play.tray.cell * 0.5)
	_touch(start, true)
	await _wait(0.05)
	_drag(start + Vector2(0, -40))
	await _wait(0.05)
	var target: Vector2 = play.board.global_position + play.board.world_to_screen(model.pieces.centers[id0]) - play._drag_offset
	_drag(target)
	await _wait(0.05)
	_touch(target, false)
	await _wait(0.1)
	print("[autoshot] drag test: tray %d -> %d, piece %d state=%d (2 = locked)" % [tray_before, model.tray.size(), id0, model.state[id0]])

	play.save_game(true)
	print("[autoshot] save exists: ", Game.has_save("img_03"), " progress: ", Game.save_progress("img_03"), "%")

	# Resume from save and verify state.
	var locked_before: int = model.locked.size()
	var old_id := play.get_instance_id()
	Game.go(Game.SCENE_HOME)
	await _wait(0.6)
	await _shot("07_home_continue")
	Game.image_id = "img_03"
	Game.resume_saved()
	Game.go(Game.SCENE_PLAY)
	play = await _play(old_id)
	print("[autoshot] resume: locked %d -> %d, loose=%d" % [locked_before, play.model.locked.size(), play.model.loose.size()])

	# Landscape layout.
	_resize(Vector2i(1280, 720))
	await _wait(0.8)
	await _shot("08_landscape")
	play.board.set_view(2.5, play.model.pieces.puzzle_size * 0.4)
	play.give_hint()
	await _wait(0.8)
	await _shot("08b_landscape_zoom_hint")
	_resize(Vector2i(540, 960))
	await _wait(0.8)
	await _shot("08c_back_to_portrait")

	# Ribbon cut, 1024 pieces, zoomed in on a solved area.
	Game.image_id = "img_01"
	Game.new_puzzle(1024, CutGenerator.Style.RIBBON)
	var t0 := Time.get_ticks_msec()
	Game.go(Game.SCENE_PLAY)
	play = await _play(play.get_instance_id())
	print("[autoshot] 1024 ribbon ready in %d ms" % (Time.get_ticks_msec() - t0))
	model = play.model
	for k in 600:
		model.lock(model.tray.pop_back())
	play.board.refresh()
	play.tray.refresh()
	play.board.set_view(4.0, model.pieces.puzzle_size * 0.5)
	await _wait(0.3)
	await _shot("09_ribbon_1024_zoom")

	# Completion.
	while not model.tray.is_empty():
		model.lock(model.tray.pop_back())
	play.board.refresh()
	play.tray.refresh()
	play._update_counts()
	play._complete_puzzle()
	await _wait(1.2)
	await _shot("10_complete")
	print("[autoshot] done")
	get_tree().quit()


## Tiling window managers ignore resize requests, so float our own window first.
func _resize(sz: Vector2i) -> void:
	if OS.has_environment("HYPRLAND_INSTANCE_SIGNATURE"):
		var target := "pid:%d" % OS.get_process_id()
		OS.execute("hyprctl", ["dispatch", "setfloating", target])
		OS.execute("hyprctl", ["dispatch", "resizewindowpixel", "exact %d %d,%s" % [sz.x, sz.y, target]])
	else:
		DisplayServer.window_set_size(sz)


func _touch(p: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = get_viewport().get_final_transform() * p
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(p: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = get_viewport().get_final_transform() * p
	Input.parse_input_event(e)
