extends Node
## Loads update packs (update*.pck next to the executable) on top of the base game.
## Only files that changed are shipped in a patch; they override the base RangeDay2.pck.
## Runs first (first autoload) so the main scene already sees the patched files.

func _init() -> void:
	var dir := OS.get_executable_path().get_base_dir()
	var names: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("update") and f.ends_with(".pck"):
			names.append(f)
	names.sort()
	for f in names:
		var ok := ProjectSettings.load_resource_pack(dir.path_join(f), true)
		print("[patcher] ", f, ": ", "applied" if ok else "FAILED")
