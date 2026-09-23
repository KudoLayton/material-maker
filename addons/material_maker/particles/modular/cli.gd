extends Node
## Portable authoring CLI. No UI, config save, source checkout or Python required.
const Document = preload("document.gd")
const Compiler = preload("compiler.gd")
const Exporter = preload("exporter.gd")
const EXAMPLES := "res://material_maker/examples/modular_particles/"
const TEMPLATES := ["basic_fountain", "box_turbulence", "sphere_burst", "user_parameters", "mmtest"]
const OPTIONS := {
	"capabilities": [], "inspect": ["input"], "create": ["template", "output"],
	"validate": ["input"], "export": ["input", "output", "effect-id", "capacity"]
}
var report := {"contract_version":1,"command":"","ok":false,"exit_code":0,"diagnostics":[],"data":{}}
var report_path := ""

func fail(code: int, stage: String, message: String) -> void:
	report.exit_code = code
	report.diagnostics.append({"stage":stage,"message":message})

static func path_error(path: String) -> String:
	if not path.is_absolute_path() or path.begins_with("res://") or path.begins_with("user://"):
		return "Use an absolute filesystem path: " + path
	if ".." in path.replace("\\","/").split("/"):
		return "Parent traversal is not allowed: " + path
	var current := path.simplify_path().trim_suffix("/")
	while not current.is_empty():
		var parent := current.get_base_dir()
		if parent == current: break
		var dir := DirAccess.open(parent)
		if dir != null and dir.is_link(current.get_file()): return "Linked path is not allowed: " + current
		current = parent
	return ""

static func within(path: String, directory: String) -> bool:
	return path.to_lower() == directory.to_lower() or path.to_lower().begins_with(directory.to_lower().trim_suffix("/") + "/")

func parse(args: PackedStringArray) -> Dictionary:
	var options := {}
	var index := 0
	while index < args.size():
		var name: String = args[index]
		if not name.begins_with("--") or index + 1 >= args.size() or args[index+1].begins_with("--"):
			fail(2,"arguments","Expected --option value: " + name)
			return {}
		name = name.trim_prefix("--")
		if options.has(name):
			fail(2,"arguments","Duplicate option: " + name)
			return {}
		options[name] = args[index+1]
		index += 2
	var command: String = options.get("mpfx-command", "")
	report.command = command
	if not OPTIONS.has(command):
		fail(2,"arguments","Unknown command: " + command)
		return {}
	for name in options:
		if name not in ["mpfx-command","report"] and name not in OPTIONS[command]:
			fail(2,"arguments","Unsupported option for %s: %s" % [command,name])
			return {}
	for required in OPTIONS[command]:
		if required != "capacity" and not options.has(required):
			fail(2,"arguments","Missing --" + required)
			return {}
	for name in ["input","output","report"]:
		if not options.has(name): continue
		var problem := path_error(options[name])
		if not problem.is_empty():
			fail(2,"arguments",problem)
			return {}
		options[name] = str(options[name]).replace("\\","/").simplify_path().trim_suffix("/")
	if options.has("report"):
		var path: String = options.report
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path) or not DirAccess.dir_exists_absolute(path.get_base_dir()):
			fail(5,"report","Report must be a new file in an existing directory: " + path)
			return {}
		if (options.has("input") and within(path,options.input)) or (options.has("output") and within(path,options.output)):
			fail(2,"arguments","Report must be separate from input and output")
			return {}
		report_path = path
	return options

func read_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		fail(5,"read","Input does not exist: " + path)
		return {}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		fail(5,"read","Cannot read input: " + path)
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		fail(3,"parse","JSON line %d: %s" % [parser.get_error_line(),parser.get_error_message()])
		return {}
	if not parser.data is Dictionary:
		fail(3,"parse","Expected an effect object")
		return {}
	var document: Dictionary = parser.data
	var problem := Document.shape_error(document)
	if not problem.is_empty():
		fail(3,"document",problem)
		return {}
	return document

func compile_document(document: Dictionary) -> Dictionary:
	var graphs := {}
	for id in document.modules:
		var module: Dictionary = document.modules[id]
		if module.has("mm_graph"):
			if module.mm_graph.get("type") != "graph" or not module.mm_graph.get("nodes") is Array or not module.mm_graph.get("connections") is Array:
				fail(3,"graph","Malformed module graph: " + str(id))
				break
			var graph = await mm_loader.create_gen(module.mm_graph)
			if graph == null:
				fail(3,"graph","Cannot load module graph: " + str(id))
				break
			graphs[id] = graph
	var compiled := {}
	if report.exit_code == 0:
		compiled = Compiler.new().compile(document,graphs)
		report.diagnostics.append_array(compiled.errors)
		for warning in compiled.get("warnings",[]):
			var diagnostic: Dictionary = warning.duplicate(true)
			diagnostic.severity = "warning"
			report.diagnostics.append(diagnostic)
		if not compiled.errors.is_empty(): report.exit_code = 3
	for graph in graphs.values(): graph.free()
	return compiled

func capabilities() -> Dictionary:
	var checksums := {}
	for name in Exporter.RUNTIME:
		checksums[name] = FileAccess.get_sha256("res://addons/mm_gpu_particles/" + name)
	return {"app_version":ProjectSettings.get_setting("application/config/actual_release",""),
		"engine":Engine.get_version_info().string,"target":"4.7.2","document_version":2,"effect_version":2,
		"module_version":1,"export_manifest_version":1,"templates":TEMPLATES,
		"modules":Document.load_file("res://material_maker/panels/modular_particles/standard/catalog.json").get("modules",[]),
		"runtime_id":JSON.stringify(checksums).sha256_text(),"runtime_files":checksums,
		"gpu_export_requires":"Forward+ / Vulkan RenderingDevice"}

func execute(options: Dictionary) -> void:
	var command: String = report.command
	if command == "capabilities":
		report.data = capabilities()
		return
	if command == "create":
		if options.template not in TEMPLATES:
			fail(2,"arguments","Unknown template: " + str(options.template))
			return
		if FileAccess.file_exists(options.output) or DirAccess.dir_exists_absolute(options.output):
			fail(5,"create","Refusing to overwrite existing output")
			return
		if not DirAccess.dir_exists_absolute(str(options.output).get_base_dir()):
			fail(5,"create","Output parent directory must exist")
			return
		var template_path: String = EXAMPLES + options.template + ".mpfx"
		if not FileAccess.file_exists(template_path):
			template_path = OS.get_executable_path().get_base_dir().path_join("examples/modular_particles/" + options.template + ".mpfx")
		var document := read_document(template_path)
		if report.exit_code != 0: return
		if Document.save_file(options.output,document) != OK:
			fail(5,"create","Cannot save document")
			return
		report.data = {"path":options.output,"sha256":FileAccess.get_sha256(options.output),"document_version":2}
		return
	var document := read_document(options.input)
	if report.exit_code != 0: return
	if command == "inspect":
		report.data = document
		return
	var capacity := int(document.get("preview_capacity",4096))
	if options.has("capacity"):
		if not str(options.capacity).is_valid_int() or int(options.capacity) < 1:
			fail(2,"arguments","Capacity must be a positive integer")
			return
		capacity = int(options.capacity)
	if command == "export":
		if not Exporter.valid_effect_id(options["effect-id"]):
			fail(2,"arguments","Invalid effect ID")
			return
		if within(options.input,options.output):
			fail(2,"arguments","Export output must not contain the source document")
			return
		if FileAccess.file_exists(options.output):
			fail(5,"export","Export destination is a file")
			return
		if RenderingServer.get_current_rendering_method() != "forward_plus" or RenderingServer.get_current_rendering_driver_name() != "vulkan" or RenderingServer.get_rendering_device() == null:
			fail(4,"environment","Export requires Forward+ / Vulkan RenderingDevice; headless validation is not GPU compilation")
			return
	var compiled := await compile_document(document)
	if report.exit_code != 0: return
	report.data = {"document_version":2,"effect_version":compiled.effect.format_version,"source_hash":compiled.effect.source_hash,
		"parameters":compiled.effect.parameters,"user_parameters":compiled.effect.user_parameters,"gpu_compiled":false}
	if command == "export":
		var size_problem: String = preload("res://addons/mm_gpu_particles/gpu_state.gd").size_error(compiled.effect,capacity)
		if not size_problem.is_empty():
			fail(3,"capacity",size_problem)
			return
		var result := await Exporter.new().export_bundle(compiled.effect,options.output,capacity,options["effect-id"])
		if not result.error.is_empty():
			fail(3 if result.error.begins_with("Compute compilation failed") else 5,"export",result.error)
			return
		report.data.merge({"gpu_compiled":true,"output":options.output,"manifest":result.manifest,"effect_id":options["effect-id"]},true)

func run(args: PackedStringArray) -> void:
	var options := parse(args)
	if report.exit_code == 0:
		var engine := Engine.get_version_info()
		if engine.major != 4 or engine.minor != 7 or engine.patch != 2 or engine.status != "stable":
			fail(4,"environment","Godot 4.7.2 stable required")
		else:
			await execute(options)
	report.ok = report.exit_code == 0
	if not report_path.is_empty():
		# Recheck ownership after any asynchronous compiler/export work.
		if FileAccess.file_exists(report_path) or DirAccess.dir_exists_absolute(report_path) or not path_error(report_path).is_empty():
			fail(5,"report","Report path changed during command")
		else:
			if Document.save_file(report_path,report) != OK: fail(5,"report","Cannot write JSON report")
	report.ok = report.exit_code == 0
	print("MM_VFX_REPORT ",JSON.stringify(report))
	await mm_renderer.thread_run(func():
		if is_instance_valid(mm_renderer.rendering_device):
			mm_renderer.rendering_device.free()
			mm_renderer.rendering_device = null)
	await mm_renderer.stop_rendering_thread()
	# The renderer's error handler is an Object, not a RefCounted/owned Node.
	if is_instance_valid(mm_renderer.shader_error_handler):
		mm_renderer.shader_error_handler.free()
		mm_renderer.shader_error_handler = null
	get_tree().quit(report.exit_code)
