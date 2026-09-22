extends Node
const S = preload("standard_checks.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func start(doc: Dictionary, capacity: int = 16):
	var result := await S.compile(doc)
	check(result.errors.is_empty(),"compile: "+str(result.errors))
	if result.effect == null: return null
	var particles = await S.start(self,result.effect,capacity)
	check(particles.ready_for_simulation,"GPU shader: "+particles.error_text)
	if not particles.ready_for_simulation:
		await S.dispose(particles)
		return null
	return particles
func step(particles, count: int = 1) -> Dictionary:
	for i in count:
		particles.advance(1.0/60.0)
		await S.frames(get_tree(),1)
	return await S.snapshot(particles)
func run() -> void:
	check(S.L.catalog().size() == 12,"twelve catalog modules")
	var all := S.document(["initialize_particle","box_location","sphere_location","add_velocity","add_velocity_in_cone"],["gravity","drag","curl_noise","solve_motion","color_over_life","scale_over_life","kill_particles"])
	var first := await S.compile(all)
	var repeated := await S.compile(all)
	check(first.errors.is_empty() and repeated.errors.is_empty(),"all 12 compose: "+str(first.errors))
	if first.effect != null and repeated.effect != null:
		check(first.effect.source_hash == repeated.effect.source_hash,"all 12 stable shader hash")
		var particles = await start(all)
		if particles != null:
			particles.emit_burst(4)
			var snapshot := await step(particles,3)
			check(snapshot.count == 4 and S.vector(particles,snapshot,"position").is_finite(),"composed pipeline finite and alive")
			await S.dispose(particles)
	await motion()
	await distributions()
	await appearance()
	await curl()
	await variants_and_world()
	print("MODULAR_STANDARD_GPU ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	await mm_renderer.stop_rendering_thread()
	get_tree().quit(0 if failures == 0 else 1)

func motion() -> void:
	var doc := S.document(["initialize_particle","add_velocity"],["gravity","gravity","drag","solve_motion"],{"initialize_particle":{"velocity":[1,2,3]},"add_velocity":{"velocity":[0,1,0]},"drag":{"drag":2.0}})
	var particles = await start(doc)
	if particles == null: return
	particles.emit_burst(1)
	var position := Vector3.ZERO
	var velocity := Vector3(1,3,3)
	for tick in 20:
		velocity = (velocity+Vector3(0,-19.62,0)/60.0)*exp(-2.0/60.0)
		position += velocity/60.0
		var snapshot := await step(particles)
		check(S.vector(particles,snapshot,"velocity").distance_to(velocity)<0.00003,"velocity semi-implicit step "+str(tick))
		check(S.vector(particles,snapshot,"position").distance_to(position)<0.00003,"position semi-implicit step "+str(tick))
		check(S.vector(particles,snapshot,S.attribute_id(doc,"acceleration")) == Vector3.ZERO and S.value(particles,snapshot,S.attribute_id(doc,"drag")) == 0.0,"accumulators reset step "+str(tick))
	await S.dispose(particles)
	# Disabled second force and negative drag contribute nothing; first frame still integrates.
	doc.stages.update[1].enabled = false
	S.instance(doc,"drag").parameters.drag = -5.0
	particles = await start(doc)
	if particles == null: return
	particles.emit_burst(1)
	var snapshot := await step(particles)
	check(S.vector(particles,snapshot,"velocity").distance_to(Vector3(1,3-9.81/60,3))<0.00001,"disabled force and negative drag")
	check(absf(S.value(particles,snapshot,"age")-1.0/60)<0.000001,"first step Age semantics preserved")
	await S.dispose(particles)

func distributions() -> void:
	for mode in ["box","sphere","surface","cone","edge","negative_range"]:
		var spawn: Array = ["initialize_particle"]
		var overrides := {"initialize_particle":{"position_offset":[2,3,4]}}
		match mode:
			"box":
				spawn.append("box_location")
				overrides.box_location = {"center":[1,0,0],"size":[-2,4,6],"seed":91}
			"sphere","surface":
				spawn.append("sphere_location")
				overrides.sphere_location = {"radius":2.0,"surface_only":mode == "surface","seed":17}
			"cone":
				spawn.append("add_velocity_in_cone")
				overrides.add_velocity_in_cone = {"axis":[0,0,0],"half_angle":30.0,"speed_min":5.0,"speed_max":2.0,"seed":33}
			"negative_range":
				spawn.append("add_velocity_in_cone")
				overrides.initialize_particle.merge({"override_lifetime":true,"lifetime_min":3.0,"lifetime_max":-3.0},true)
				overrides.add_velocity_in_cone = {"half_angle":0.0,"speed_min":3.0,"speed_max":-3.0}
			"edge":
				spawn.append_array(["box_location","sphere_location","add_velocity_in_cone"])
				overrides.box_location = {"size":[0,0,0]}
				overrides.sphere_location = {"radius":-1.0}
				overrides.add_velocity_in_cone = {"half_angle":-10.0,"speed_min":-3.0,"speed_max":-1.0}
		var doc := S.document(spawn,[],overrides)
		var particles = await start(doc,4096)
		if particles == null: continue
		particles.emit_burst(4096)
		var snapshot := await step(particles)
		check(snapshot.count>4000 if mode == "negative_range" else snapshot.count == 4096,"sampling population "+mode)
		var bounds := true
		var average := Vector3.ZERO
		var statistic := 0.0
		var lifetime_sum := 0.0
		for i in 4096:
			var point := S.vector(particles,snapshot,"position",i)-Vector3(2,3,4)
			var velocity := S.vector(particles,snapshot,"velocity",i)
			match mode:
				"box":
					point -= Vector3(1,0,0)
					bounds = bounds and absf(point.x)<=1.00001 and absf(point.y)<=2.00001 and absf(point.z)<=3.00001
				"sphere": bounds = bounds and point.length()<=2.00001
				"surface": bounds = bounds and absf(point.length()-2)<0.00001
				"cone":
					bounds = bounds and velocity.length()>=1.99999 and velocity.length()<=5.00001 and velocity.normalized().y>=cos(deg_to_rad(30.0))-0.00001
					statistic += velocity.normalized().y
				"negative_range":
					bounds = bounds and absf(velocity.x)<0.00001 and absf(velocity.z)<0.00001 and velocity.y>=0 and velocity.y<=3.00001
					statistic += velocity.y
					lifetime_sum += S.value(particles,snapshot,"lifetime",i)
				"edge": bounds = bounds and point == Vector3.ZERO and velocity == Vector3.ZERO
			average += point
			if mode == "sphere": statistic += pow(point.length()/2,3)
		check(bounds,"sampling bounds and degenerate safeguards "+mode)
		check((average/4096).length()<0.08,"unbiased spatial mean "+mode)
		if mode == "sphere": check(absf(statistic/4096-0.5)<0.025,"sphere uniform volume radius cubed")
		if mode == "cone": check(absf(statistic/4096-(1+cos(deg_to_rad(30.0)))/2)<0.005,"cone uniform solid angle")
		if mode == "negative_range": check(absf(statistic/4096-1.5)<0.07 and absf(lifetime_sum/4096-1.5)<0.07,"clamp negative endpoints before sampling, no artificial mass at zero")
		particles.restart()
		await S.frames(get_tree())
		particles.emit_burst(4096)
		var replay := await step(particles)
		check(replay.data == snapshot.data,"fixed seed restart byte-identical "+mode)
		await S.dispose(particles)

func appearance() -> void:
	var doc := S.document(["initialize_particle"],["color_over_life","scale_over_life","kill_particles"],{"initialize_particle":{"color":[0.8,0.6,0.4,0.5],"scale":[2,3,4],"override_lifetime":true,"lifetime_min":2.0,"lifetime_max":2.0}})
	var particles = await start(doc,1)
	if particles == null: return
	particles.emit_burst(1)
	for tick in 30:
		var snapshot := await step(particles)
		if tick in [0,9,29]:
			var factor := 1.0-(tick+1)/120.0
			var color: Array = S.value(particles,snapshot,"color")
			check(absf(color[0]-0.8)<0.00001 and absf(color[3]-0.5*factor)<0.00002,"initial Color times Gradient, noncumulative")
			check(S.vector(particles,snapshot,"scale").distance_to(Vector3(2,3,4)*factor)<0.00003,"initial Scale times Curve, noncumulative")
			check(S.value(particles,snapshot,"lifetime") == 2.0,"explicit lifetime override")
			check(S.value(particles,snapshot,S.attribute_id(doc,"initial_color")) == [float(0.8),float(0.6),float(0.4),0.5] or absf(S.value(particles,snapshot,S.attribute_id(doc,"initial_color"))[0]-0.8)<0.00001,"initial Color preserved")
	var kill_id: String = S.instance(doc,"kill_particles").id
	particles.set_parameter(kill_id+"/kill",true)
	var killed := await step(particles)
	check(killed.count == 0 and not S.value(particles,killed,"alive"),"Kill updates GPU compaction count")
	particles.set_parameter(kill_id+"/kill",false)
	check((await step(particles)).count == 0,"Kill false cannot resurrect")
	particles.emit_burst(1)
	var reused := await step(particles)
	check(reused.count == 1 and absf(S.value(particles,reused,"age")-1.0/60)<0.000001,"dead slot reuse resets lifetime state")
	check(S.vector(particles,reused,S.attribute_id(doc,"acceleration")) == Vector3.ZERO,"reused slot resets accumulated acceleration")
	await S.dispose(particles)
	for lifetime in [0.0,-3.0]:
		S.instance(doc,"initialize_particle").parameters.lifetime_min = lifetime
		S.instance(doc,"initialize_particle").parameters.lifetime_max = lifetime
		particles = await start(doc,1)
		if particles == null: continue
		particles.emit_burst(1)
		check((await step(particles)).count == 0,"nonpositive lifetime dies safely")
		await S.dispose(particles)

func variants_and_world() -> void:
	var doc := S.document(["initialize_particle"],["curl_noise","curl_noise","solve_motion","color_over_life","color_over_life","scale_over_life","scale_over_life"])
	var second_curl: Dictionary = doc.modules[doc.stages.update[1].module]
	var nested: Dictionary = second_curl.mm_graph.nodes.filter(func(n): return n.name == "Curl3D")[0]
	var noise: Dictionary = nested.nodes.filter(func(n): return n.name == "PotentialNoise")[0]
	noise.parameters.persistence = 0.25
	var color: Dictionary = doc.modules[doc.stages.update[4].module].mm_graph.nodes.filter(func(n): return n.name == "LifeGradient")[0]
	for point in color.parameters.gradient.points:
		point.r = 0.25
		point.g = 0.5
	var curve: Dictionary = doc.modules[doc.stages.update[6].module].mm_graph.nodes.filter(func(n): return n.name == "LifeCurve")[0]
	for point in curve.parameters.curve.points:
		point.y = 0.75
		point.ls = 0.0
		point.rs = 0.0
	var particles = await start(doc)
	if particles != null:
		particles.emit_burst(1)
		var snapshot := await step(particles)
		check(absf(S.value(particles,snapshot,"color")[0]-0.25)<0.00001,"different Gradient copies have independent shader symbols")
		check(S.vector(particles,snapshot,"scale").distance_to(Vector3.ONE*0.75)<0.00001,"different Curve copies have independent shader symbols")
		await S.dispose(particles)
	doc = S.document(["initialize_particle","box_location","sphere_location"],[],{"initialize_particle":{"position_offset":[1,2,3]},"box_location":{"size":[0,0,0],"center":[2,0,0]},"sphere_location":{"radius":0.0,"center":[0,4,0]}})
	var compiled := await S.compile(doc)
	check(compiled.errors.is_empty(),"world offset compile")
	if compiled.effect == null: return
	for space in [0,1]:
		particles = await S.start(self,compiled.effect,1,{"simulation_space":space,"position":Vector3(10,20,30)})
		check(particles.ready_for_simulation,"space GPU ready")
		if particles.ready_for_simulation:
			particles.emit_burst(1)
			var snapshot := await step(particles)
			var expected := Vector3(3,6,3)+(Vector3(10,20,30) if space == 1 else Vector3.ZERO)
			check(S.vector(particles,snapshot,"position").distance_to(expected)<0.00001,"Location preserves Local/World spawn origin")
			check(S.value(particles,snapshot,"lifetime") == 4.0,"default Initialize preserves Emitter lifetime")
		await S.dispose(particles)

func curl() -> void:
	var doc := S.document(["initialize_particle","box_location"],["curl_noise","solve_motion"],{"box_location":{"size":[4,4,4]}})
	var particles = await start(doc,256)
	if particles == null: return
	particles.emit_burst(256)
	var snapshot := await step(particles)
	var finite := true
	var energy := Vector3.ZERO
	for i in 256:
		var velocity := S.vector(particles,snapshot,"velocity",i)
		finite = finite and velocity.is_finite()
		energy += velocity.abs()
	check(finite and energy.x>0.1 and energy.y>0.1 and energy.z>0.1,"3D Curl finite with all three components")
	await S.dispose(particles)
	for parameter in ["strength","frequency"]:
		S.instance(doc,"curl_noise").parameters = {parameter:0.0}
		particles = await start(doc,16)
		if particles == null: continue
		particles.emit_burst(16)
		snapshot = await step(particles)
		var zero := true
		for i in 16: zero = zero and S.vector(particles,snapshot,"velocity",i) == Vector3.ZERO
		check(zero,"Curl no contribution for zero "+parameter)
		await S.dispose(particles)
