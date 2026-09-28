extends RefCounted
## Shared UI/CLI/export validation. Export preferences never mutate a .mpfx.
const KEYS := ["render_target","pixels_per_unit","flip_y","blend_mode","sprite"]
const BLENDS := ["effect","alpha","additive","opaque","cutout"]

static func normalize(options: Dictionary) -> Dictionary:
	for key in options:
		if key not in KEYS: return {"error":"Unknown export option: " + str(key)}
	var target = options.get("render_target","3d")
	if target not in ["3d","2d"]: return {"error":"Render target must be 3d or 2d"}
	if target == "3d":
		for key in KEYS.slice(1):
			if options.has(key): return {"error":"2D export option requires --render-target 2d: " + key}
	var units = options.get("pixels_per_unit",100.0)
	if not (units is int or units is float) or not is_finite(float(units)) or units <= 0 or units > 3.4028234e38:
		return {"error":"Pixels Per Unit must be positive and finite"}
	if not options.get("flip_y",true) is bool: return {"error":"Flip Y must be true or false"}
	if options.get("blend_mode","effect") not in BLENDS: return {"error":"Unsupported blend mode"}
	var sprite = options.get("sprite","")
	if not sprite is String: return {"error":"Sprite must be an absolute PNG path"}
	if not sprite.is_empty() and (not sprite.is_absolute_path() or sprite.get_extension().to_lower() != "png"):
		return {"error":"Sprite must be an absolute PNG path"}
	return {"error":"","values":{"render_target":target,"pixels_per_unit":float(units),"flip_y":options.get("flip_y",true),"blend_mode":options.get("blend_mode","effect"),"sprite":sprite}}

static func load_sprite(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"error":"Sprite file does not exist: " + path}
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 24 or bytes.size() > 64*1024*1024 or bytes.slice(0,8) != PackedByteArray([137,80,78,71,13,10,26,10]):
		return {"error":"Invalid or oversized PNG sprite"}
	# Bound decoded allocation before decompressing PNG.
	var width := 0
	var height := 0
	for i in 4:
		width = (width << 8) | bytes[16+i]
		height = (height << 8) | bytes[20+i]
	if width < 1 or height < 1 or width > 8192 or height > 8192 or width*height > 16777216:
		return {"error":"Sprite exceeds 8192px per side / 16 megapixel limit"}
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK: return {"error":"Cannot decode PNG sprite"}
	return {"error":"","image":image}
