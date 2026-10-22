extends SceneTree
## Loads every script so parse/compile errors are printed. Run headless.

func _initialize() -> void:
	var bad := 0
	for path in _scripts("res://scripts") + _scripts("res://tests"):
		var s: Script = load(path)
		if s == null or not s.can_instantiate():
			print("FAILED: ", path)
			bad += 1
	print("compile check: %d failed" % bad)
	quit(bad)

func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out
