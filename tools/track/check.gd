## Type-checks every GDScript file under scripts/ and tests/ in one live engine run.
##
## Run standalone with `--check-only --script`, a script can never see this project's
## autoloads (Purse, CircuitSession, LoadoutHolder, IncomeRunner): those globals are only
## registered when the SceneTree actually starts, which `--check-only` skips. Any script
## that references one by its autoload name fails with a bogus "Identifier not found"
## there even though it is correct. Running as `--script` (this file, extending SceneTree)
## instead makes autoloads live before `_initialize()` runs, so a plain `load()` per file
## compiles it the same way the running game would - see docs/engine-setup.md.
extends SceneTree

func _initialize() -> void:
	var failed: Array[String] = []
	for rel in _find_scripts():
		var path := "res://" + rel
		var script: GDScript = load(path)
		var err := script.reload()
		# ERR_ALREADY_IN_USE: this script already has live instances (an autoload, or a
		# field initializer that instantiated it eagerly).
		# reload() refuses to touch it, but the mere existence of an instance proves the
		# engine already compiled this exact on-disk source successfully during its own
		# startup, moments before this loop ran - so it is a pass, not a skip.
		if err != OK and err != ERR_ALREADY_IN_USE:
			failed.append(rel)
			print("check: FAILED ", rel)
	if failed.is_empty():
		quit(0)
		return
	print("")
	print("check: ", failed.size(), " script(s) failed the type check: ", ", ".join(failed))
	quit(1)

func _find_scripts() -> Array[String]:
	var out: Array[String] = []
	var tops: Array[String] = ["scripts", "tests"]
	for top in tops:
		_walk(top, out)
	out.sort()
	return out

func _walk(dir: String, out: Array[String]) -> void:
	var da := DirAccess.open("res://" + dir)
	if da == null:
		return
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name == "." or name == "..":
			name = da.get_next()
			continue
		var rel := dir + "/" + name
		if da.current_is_dir():
			_walk(rel, out)
		elif name.ends_with(".gd"):
			out.append(rel)
		name = da.get_next()
	da.list_dir_end()
