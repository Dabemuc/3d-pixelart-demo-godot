@tool
extends CompositorEffect
class_name OutlineV1

var rd := RenderingServer.get_rendering_device()
var shader: RID
var pipeline: RID

@export var depth_bias: float = 0.008
@export_range(0.0, 1.0) var outline_strength: float = 0.95
@export var normal_bias: float = 0.3
@export_range(0.0, 1.0) var crease_strength: float = 0.3
@export var debug_show_mask: bool = false

func _init() -> void:
	var shader_file := preload("res://render/outline/outlineV1.glsl")
	var shader_spirv := shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

func _render_callback(_callback_type: int, _render_data: RenderData) -> void:
	var pixel_art_size := PixelArtBuffers.TARGET_SIZE

	var push_constants := PackedByteArray()
	push_constants.resize(16)
	push_constants.encode_float(0,  depth_bias)
	push_constants.encode_float(4,  outline_strength)
	push_constants.encode_float(8,  normal_bias)
	push_constants.encode_float(12, crease_strength)
	# Append debug flag as a second 16-byte chunk
	push_constants.resize(32)
	push_constants.encode_u32(16, 1 if debug_show_mask else 0)
	push_constants.encode_u32(20, 0)
	push_constants.encode_u32(24, 0)
	push_constants.encode_u32(28, 0)

	var color_uniform := RDUniform.new()
	color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	color_uniform.binding = 0
	color_uniform.add_id(PixelArtBuffers.ensure_color(rd))

	var depth_uniform := RDUniform.new()
	depth_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	depth_uniform.binding = 1
	depth_uniform.add_id(PixelArtBuffers.ensure_depth(rd))

	var normal_uniform := RDUniform.new()
	normal_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	normal_uniform.binding = 2
	normal_uniform.add_id(PixelArtBuffers.ensure_normal(rd))

	var mask_uniform := RDUniform.new()
	mask_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	mask_uniform.binding = 3
	mask_uniform.add_id(PixelArtBuffers.ensure_mask(rd))

	var bindings: Array[RDUniform] = [color_uniform, depth_uniform, normal_uniform, mask_uniform]
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
