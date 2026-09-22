extends Node
const S = preload("standard_checks.gd")
const Library = preload("res://material_maker/panels/modular_particles/library.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func run() -> void:
	var doc := Library.new_document()
	check(doc.stages.spawn.map(func(i): return doc.modules[i.module].standard_module.catalog_id) == Library.DEFAULT_SPAWN,"new Spawn default stack")
	check(doc.stages.update.map(func(i): return doc.modules[i.module].standard_module.catalog_id) == Library.DEFAULT_UPDATE,"new Update default stack")
	check(doc.attributes.size() == 4 and doc.modules.size() == 6,"new document has exactly six modules and four roles")
	check(doc.emitter == S.D.create().emitter and doc.renderer == S.D.create().renderer,"existing emitter/renderer defaults retained")
	var other := Library.new_document()
	check(doc.stages.spawn[0].id != other.stages.spawn[0].id and doc.attributes[0].id != other.attributes[0].id,"fresh documents have independent stable IDs")
	doc.modules[doc.stages.spawn[0].module].name = "Changed"
	check(other.modules[other.stages.spawn[0].module].name == "Initialize Particle" and S.L.payload("initialize_particle").particle_module.definition.name == "Initialize Particle","new document never mutates packaged catalog")
	check(Library.defaults().has("initialize_velocity") and Library.defaults().has("integrate_velocity") and Library.catalog_entries().size() == 14,"legacy definitions remain available")
	var window = load("res://material_maker/main_window.tscn").instantiate()
	get_tree().root.add_child(window)
	get_tree().root.size = Vector2i(1500,1040)
	await S.frames(get_tree(),30)
	var editor = window.new_modular_particles()
	await S.frames(get_tree(),45)
	var result: Dictionary = await editor.compile_document()
	check(result.errors.is_empty() and result.warnings.is_empty(),"new UI document compiles without warnings")
	check(is_instance_valid(editor.preview) and editor.preview.ready_for_simulation,"new document GPU preview")
	check(editor.stack.get_item_text(0) == "Initialize Particle" and editor.stack.get_item_text(1) == "Add Velocity in Cone","new stack UI labels")
	check(editor.graph_edit.top_generator.get_node_or_null("Lifetime") != null,"initialization graph editable in existing canvas")
	var output_node
	for node in editor.graph_edit.get_children():
		if node is MMGraphNodeGeneric and node.generator != null and node.generator.get("settings") is Dictionary and node.generator.settings.get("kind") == "module_output": output_node = node
	check(output_node != null and editor.graph_edit.zoom>=0.5 and output_node.get_titlebar_hbox().modulate.a>0.99,"large catalog graph starts with readable labels and enabled controls")
	if output_node != null:
		var output_position: Vector2 = output_node.position_offset*editor.graph_edit.zoom-editor.graph_edit.scroll_offset
		check(Rect2(Vector2.ZERO,editor.graph_edit.size).has_point(output_position),"Module Output starts inside viewport")
	get_tree().root.get_texture().get_image().save_png("res://standard-initial-editor.png")
	if output_node != null:
		# Reproduce the queued-redraw interval during graph replacement without
		# destroying this fixture's actual authoring model.
		var actual_generator = output_node.generator
		var retired = preload("res://material_maker/panels/modular_particles/generator.gd").new()
		output_node.generator = retired
		retired.free()
		output_node.queue_redraw()
		await S.frames(get_tree(),3)
		check(not is_instance_valid(output_node.generator),"queued canvas redraw tolerates retired generator")
		output_node.generator = actual_generator
		output_node.queue_redraw()
		await S.frames(get_tree(),2)
	editor.viewport.get_texture().get_image().save_png("res://new-standard-preview.png")
	for name in ["basic_fountain","box_turbulence","sphere_burst"]:
		var path: String = "res://material_maker/examples/modular_particles/"+name+".mpfx"
		var bytes := FileAccess.get_file_as_bytes(path)
		check(await window.do_load_project(path),"open example "+name)
		editor = window.get_current_project()
		await S.frames(get_tree(),45)
		result = await editor.compile_document()
		check(result.errors.is_empty() and result.warnings.is_empty(),"example contracts "+name+": "+str(result.errors))
		check(is_instance_valid(editor.preview) and editor.preview.ready_for_simulation,"example GPU Preview "+name)
		if is_instance_valid(editor.preview) and editor.preview.ready_for_simulation:
			# A looping burst intentionally has an empty interval after Kill. Sample
			# a known simulation time instead of depending on wall-clock shader import.
			editor.preview.manual_processing = true
			editor.preview.restart()
			for frame in 180:
				await get_tree().process_frame
				if editor.preview.ready_for_simulation: break
			for tick in 20:
				editor.preview.advance(1.0/60.0)
				await S.frames(get_tree(),1)
			var snapshot := await S.snapshot(editor.preview)
			check(snapshot.count>0,"example has live GPU particles "+name)
			editor.viewport.get_texture().get_image().save_png("res://"+name+".png")
		editor.save_path = "res://"+name+"-roundtrip.mpfx"
		check(await editor.save(),"save example copy "+name)
		check(S.D.load_file(editor.save_path) == S.D.load_file(path),"opening/saving does not rewrite snapshots "+name)
		check(FileAccess.get_file_as_bytes(path) == bytes,"original example unchanged "+name)
		var test_doc: Dictionary = editor.document.duplicate(true)
		test_doc.emitter.merge({"rate":0.0,"loop":false,"bursts":[]},true)
		result = await S.compile(test_doc)
		var particles = await S.start(self,result.effect,128)
		check(particles.ready_for_simulation,"isolated example GPU shader "+name)
		if particles.ready_for_simulation:
			particles.emit_burst(128)
			particles.advance(1.0/60.0)
			await S.frames(get_tree())
			check((await S.snapshot(particles)).count == 128,"example manual 128 burst "+name)
			if name == "sphere_burst":
				for i in 92:
					particles.advance(1.0/60.0)
					await S.frames(get_tree(),1)
				check((await S.snapshot(particles)).count == 0,"example per-particle Age condition kills before lifetime")
		await S.dispose(particles)
	print("MODULAR_STANDARD_EXAMPLES ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	mm_globals.set_config("confirm_quit",false)
	mm_globals.set_config("confirm_close_project",false)
	window.quit()
