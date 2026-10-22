extends SceneTree
## Headless check: every piece count x style x several seeds yields valid,
## non-self-intersecting, triangulable pieces whose areas tile the puzzle.
## Run: godot --headless --path . -s res://tests/test_generator.gd

func _initialize() -> void:
	var size := Vector2(4000, 3000)
	var failures := 0
	for target in [64, 128, 256, 512, 1024]:
		var grid := CutGenerator.grid_for(target, size.x / size.y)
		for style in [CutGenerator.Style.RIBBON, CutGenerator.Style.RANDOM]:
			for seed_value in [1, 42, 977, 123456]:
				var t0 := Time.get_ticks_msec()
				var set := PieceSet.new()
				set.compute(grid, size, style, seed_value)
				var ms := Time.get_ticks_msec() - t0
				var area := 0.0
				var bad := 0
				for i in set.count:
					var poly := set.outlines[i]
					if Geometry2D.triangulate_polygon(poly).is_empty() or _self_intersects(poly):
						bad += 1
					area += absf(_area(poly))
				var area_err := absf(area - size.x * size.y) / (size.x * size.y)
				if bad > 0 or area_err > 1e-6:
					failures += 1
				print("%4d -> %2dx%2d=%4d  %-10s seed=%-6d  %4d ms  bad=%d  area_err=%.7f" % [
					target, grid.x, grid.y, set.count, CutGenerator.STYLE_NAMES[style], seed_value, ms, bad, area_err])
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)

func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var j := (i + 1) % p.size()
		a += p[i].x * p[j].y - p[j].x * p[i].y
	return a * 0.5

func _self_intersects(p: PackedVector2Array) -> bool:
	var n := p.size()
	for i in n:
		var a1 := p[i]; var a2 := p[(i + 1) % n]
		for j in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue
			var b1 := p[j]; var b2 := p[(j + 1) % n]
			if Geometry2D.segment_intersects_segment(a1, a2, b1, b2) != null:
				return true
	return false
