extends Node
const Library = preload("res://material_maker/panels/modular_particles/library.gd")
const Document = preload("res://addons/material_maker/particles/modular/document.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)

func frames(count: int = 8) -> void:
	for frame in count: await get_tree().process_frame

func _ready() -> void: run.call_deferred()

func fixture() -> Dictionary:
	var data := Library.legacy_document()
	var module: Dictionary = data.modules.initialize_velocity
	for index in 18:
		module.inputs.append({"id":"extra_%d" % index,"name":"Long_Module_Input_Name_%d" % index,"type":"float","default":0.25})
	return data

func inside(inner: Rect2, outer: Rect2) -> bool:
	return outer.grow(1.0).encloses(inner)

func check_inputs(editor, dock: Control, expect_fit: bool) -> void:
	var scroll: ScrollContainer = editor.particle_panes["Module Inputs"]
	check(inside(dock.get_global_rect(),get_tree().root.get_visible_rect()),"dock stays inside window")
	check(inside(scroll.get_global_rect(),dock.get_global_rect()),"input viewport stays inside dock")
	check(scroll.clip_contents and dock.clip_contents,"viewport clips drawing and input at dock boundary")
	check(scroll.get_v_scroll_bar().visible,"many inputs have vertical scroll")
	if expect_fit:
		check(not scroll.get_h_scroll_bar().visible,"normal dock needs no horizontal scroll")
		for row in editor.input_box.get_children():
			if row.is_queued_for_deletion(): continue
			for control in row.get_children():
				var rect: Rect2 = control.get_global_rect()
				check(rect.position.x >= dock.global_position.x-1 and rect.end.x <= dock.get_global_rect().end.x+1,"input control fits dock: "+control.name)
	else:
		check(scroll.get_h_scroll_bar().visible or scroll.get_child(0).size.x <= scroll.size.x,"narrow dock fits or scrolls horizontally instead of overflowing")
	# Every last-row action remains reachable even in a narrow/short dock.
	var last: Control = editor.input_box.get_child(editor.input_box.get_child_count()-1)
	scroll.ensure_control_visible(last.get_node("EditUser"))
	await frames()
	var button: Control = last.get_node("EditUser")
	check(inside(button.get_global_rect(),scroll.get_global_rect()),"last input action can be scrolled into view")

func same_layout(actual, expected) -> bool:
	# Integer pixel allocation may round one pixel differently after restoring
	# a non-default window size; topology, active tabs and proportions persist.
	if actual is Dictionary and expected is Dictionary:
		if actual.size() != expected.size(): return false
		for key in actual:
			if not expected.has(key): return false
			if key in ["w","h"]:
				if absf(float(actual[key])-float(expected[key])) > 1.0: return false
			elif not same_layout(actual[key],expected[key]): return false
		return true
	if actual is Array and expected is Array:
		if actual.size() != expected.size(): return false
		for index in actual.size():
			if not same_layout(actual[index],expected[index]): return false
		return true
	return actual == expected

func run() -> void:
	var window = load("res://material_maker/main_window.tscn").instantiate()
	get_tree().root.add_child(window)
	await frames(30)
	get_tree().root.size = Vector2i(1440,960)
	await frames()
	var layout = window.layout
	var flex = layout.get_node("FlexibleLayout")
	var material_before: Dictionary = flex.serialize()
	var editor = window.new_modular_particles()
	await frames(40)
	editor.apply_document(fixture())
	await frames(60)
	check(window.get_current_mode() == "particle","particle has separate layout")
	check(editor.graph_edit.get_parent() == editor,"graph remains in project tab")
	var inputs: Control = layout.get_panel("Module Inputs")
	var users: Control = layout.get_panel("User Parameters")
	var stack: Control = layout.get_panel("Module Stack")
	var preview: Control = layout.get_panel("Particle Preview")
	check(inputs.global_position.x < editor.global_position.x and inputs.global_position.y < users.global_position.y,"left inputs over Users/Attributes")
	check(stack.global_position.x > editor.global_position.x and stack.global_position.y < preview.global_position.y,"right stack over preview")
	check(editor.graph_edit.size.y > get_tree().root.size.y*0.65,"central graph uses full height")
	await check_inputs(editor,inputs,true)
	var scroll: ScrollContainer = editor.particle_panes["Module Inputs"]
	scroll.scroll_vertical = 0
	await frames()
	RenderingServer.force_draw()
	get_tree().root.get_texture().get_image().save_png("res://dock-1440.png")
	# Actual split drag, not just resizing a child independently of its window.
	var input_tab = inputs.get_meta("flex_node")
	var root_split = input_tab.parent.get_ref().parent.get_ref()
	root_split.drag(0,int(root_split.rect.position.x+170))
	await frames()
	await check_inputs(editor,inputs,false)
	RenderingServer.force_draw()
	get_tree().root.get_texture().get_image().save_png("res://dock-narrow.png")
	layout.reset_panels()
	await frames()
	get_tree().root.size = Vector2i(1024,720)
	await frames(20)
	await check_inputs(editor,inputs,false)
	RenderingServer.force_draw()
	get_tree().root.get_texture().get_image().save_png("res://dock-1024.png")
	get_tree().root.content_scale_factor = 1.25
	get_tree().root.size = Vector2i(1600,1000)
	await frames(20)
	await check_inputs(editor,inputs,false)
	RenderingServer.force_draw()
	get_tree().root.get_texture().get_image().save_png("res://dock-scaled.png")
	get_tree().root.content_scale_factor = 1.0
	get_tree().root.size = Vector2i(1440,960)
	await frames(20)
	layout.reset_panels()
	await frames()
	var row: Control = editor.input_box.get_child(1)
	var value: LineEdit = row.get_node("InputValue")
	value.text_submitted.emit("3.5")
	await frames()
	check(editor.document.stages.spawn[0].parameters.extra_0 == 3.5,"input edit works while docked")
	editor.undoredo.undo()
	await frames()
	var particle_before: Dictionary = flex.serialize()
	var second = window.new_modular_particles()
	await frames(45)
	check(inputs.source == second.pane_home,"second particle tab owns displayed controls")
	check(scroll.get_parent() == editor.pane_home and not scroll.is_visible_in_tree(),"inactive particle controls parked and hidden")
	window.projects_panel.get_projects().current_tab = editor.get_index()
	await frames(20)
	check(inputs.source == editor.pane_home and scroll.is_visible_in_tree(),"first particle tab rebinds controls")
	check(flex.serialize() == particle_before,"particle tab switch preserves layout")
	# Keep material/paint presets independent of the particle layout.
	window.projects_panel.get_projects().current_tab = 0
	await frames(20)
	check(window.get_current_mode() == "material","material mode restored")
	check(flex.serialize() == material_before,"material layout preserved exactly")
	check(scroll.get_parent() == editor.pane_home and not scroll.is_visible_in_tree(),"material tab hides particle panes")
	layout.change_mode("paint")
	await frames()
	var paint_before: Dictionary = flex.serialize()
	layout.change_mode("particle")
	await frames()
	layout.change_mode("paint")
	await frames()
	check(same_layout(flex.serialize(),paint_before),"paint layout preserved across particle mode")
	layout.change_mode("material")
	window.projects_panel.get_projects().current_tab = editor.get_index()
	await frames(20)
	check(flex.serialize() == particle_before,"particle layout restored after other modes")
	for panel in layout.panels.values():
		check(panel.is_inside_tree(),"registered panel has a tree owner: "+panel.name)
	# Closing a dock must not orphan its live GPU content.
	layout.set_panel_visible("Particle Preview",false)
	check(preview.is_inside_tree() and not preview.is_visible_in_tree(),"closed preview is owned and hidden")
	layout.set_panel_visible("Particle Preview",true)
	await frames()
	check(preview.is_visible_in_tree(),"closed preview can reopen")
	# Closing the active effect must rebind/return panes before freeing the tab.
	editor.queue_free()
	await frames(30)
	check(not is_instance_valid(editor),"active effect tab freed safely")
	for panel in layout.panels.values():
		check(panel.is_inside_tree(),"panel survives project close: "+panel.name)
	print("MODULAR_DOCK_LAYOUT ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	mm_globals.set_config("confirm_quit",false)
	mm_globals.set_config("confirm_close_project",false)
	await window.quit()
	get_tree().quit(0 if failures == 0 else 1)
