@tool
extends CompositorEffect
class_name QuantizeV1

var rd := RenderingServer.get_rendering_device()
var shader: RID
var pipeline: RID
var palette_buffer: RID

@export var use_lab: bool = true
@export_enum("resurrect_8", "resurrect_64", "aap_64", "mushroom", "citrink", "blk_nx64", "db32", "rct2") var palette: String = "resurrect_8":
	set(v):
		palette = v
		_queue_palette_upload(Palettes.ALL[v])

var _pending_palette: PackedByteArray
var _palette_dirty := false

func _init() -> void:
	var shader_file := preload("res://render/quantize/quantizeV1.glsl")
	var shader_spirv := shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)
	_queue_palette_upload(Palettes.ALL[palette])

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if palette_buffer.is_valid():
			rd.free_rid(palette_buffer)

func _queue_palette_upload(colors: Array) -> void:
	var data := PackedByteArray()
	data.resize(colors.size() * 16)
	for i in colors.size():
		var c: Color = colors[i]
		data.encode_float(i * 16 + 0,  c.r)
		data.encode_float(i * 16 + 4,  c.g)
		data.encode_float(i * 16 + 8,  c.b)
		data.encode_float(i * 16 + 12, 0.0)
	_pending_palette = data
	_palette_dirty = true

func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	if _palette_dirty:
		if palette_buffer.is_valid():
			rd.free_rid(palette_buffer)
		palette_buffer = rd.storage_buffer_create(_pending_palette.size(), _pending_palette)
		_palette_dirty = false

	var pixel_art_size := PixelArtBuffers.TARGET_SIZE

	var push_constants := PackedByteArray()
	push_constants.resize(16)
	push_constants.encode_s32(0, Palettes.ALL[palette].size())
	push_constants.encode_s32(4, 1 if use_lab else 0)

	var color_uniform := RDUniform.new()
	color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	color_uniform.binding = 0
	color_uniform.add_id(PixelArtBuffers.ensure_color(rd))

	var palette_uniform := RDUniform.new()
	palette_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	palette_uniform.binding = 1
	palette_uniform.add_id(palette_buffer)

	var bindings: Array[RDUniform] = [color_uniform, palette_uniform]
	var groups := Vector3i(
		(pixel_art_size.x - 1) / 8 + 1,
		(pixel_art_size.y - 1) / 8 + 1,
		1
	)
	var uniform_set := rd.uniform_set_create(bindings, shader, 0)
	var compute_list := rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	rd.compute_list_dispatch(compute_list, groups.x, groups.y, groups.z)
	rd.compute_list_end()

	rd.free_rid(uniform_set)
