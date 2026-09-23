extends RefCounted
## UI projection only: the persisted emitter dictionary remains authoritative.
const Document = preload("res://addons/material_maker/particles/modular/document.gd")

static func error(value: Dictionary) -> String:
	for key in ["rate","duration","lifetime"]:
		if not Document.valid_value("float",value.get(key)) or value[key] < 0: return "Invalid emitter " + key
	if value.duration <= 0: return "Duration must be positive"
	if not value.get("loop") is bool: return "Loop must be a boolean"
	if not value.get("bursts") is Array: return "Expected bursts array"
	for burst in value.bursts:
		if not burst is Dictionary or not Document.valid_value("float",burst.get("time")) or not Document.valid_value("uint",burst.get("count")): return "Invalid burst time/count"
		if burst.time < 0 or burst.time >= value.duration: return "Burst time must be inside Duration"
	return ""

static func mode(value: Dictionary) -> String:
	if not error(value).is_empty(): return "Custom"
	if value.loop and value.rate > 0 and value.bursts.is_empty(): return "Looping"
	if value.rate == 0 and value.bursts.size() == 1 and value.bursts[0].time == 0 and value.bursts[0].count > 0: return "Burst"
	return "Custom"

static func convert(value: Dictionary, target: String) -> Dictionary:
	var result := value.duplicate(true)
	result.duration = value.get("duration",1.0) if Document.valid_value("float",value.get("duration")) and value.duration > 0 else 1.0
	result.lifetime = value.get("lifetime",1.0) if Document.valid_value("float",value.get("lifetime")) and value.lifetime >= 0 else 1.0
	if target == "Looping":
		result.rate = value.get("rate",64.0) if Document.valid_value("float",value.get("rate")) and value.rate > 0 else 64.0
		result.loop = true
		result.bursts = []
	elif target == "Burst":
		var count := 64
		if value.get("bursts") is Array and not value.bursts.is_empty() and value.bursts[0] is Dictionary and Document.valid_value("uint",value.bursts[0].get("count")):
			count = maxi(1,int(value.bursts[0].count))
		result.rate = 0.0
		result.loop = false
		result.bursts = [{"time":0.0,"count":count}]
	return result

static func needs_restart(before: Dictionary, after: Dictionary) -> bool:
	return mode(before) != mode(after) or before.get("duration") != after.get("duration") or before.get("loop") != after.get("loop") or before.get("bursts") != after.get("bursts")
