@tool
extends CompositorEffect
class_name PosterizeV1

var rd := RenderingServer.get_rendering_device()
var shader: RID
var pipeline: RID

@export var hue_posterization_count: int = 0
@export var hue_skip_zero: bool = false
@export var saturation_posterization_count: int = 0
@export var saturation_skip_zero: bool = false
@export var value_posterization_count: int = 0
@export var value_skip_zero: bool = false

func _init() -> void:
	var shader_file := preload("res://render/posterize/posterizeV1.glsl")
	var shader_spirv := shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

func _render_callback(_callback_type: int, _render_data: RenderData) -> void:
	var pixel_art_size := PixelArtBuffers.TARGET_SIZE

	var push_constants := PackedByteArray()
	push_constants.resize(16)
	push_constants.encode_u32(0, hue_posterization_count)
	push_constants.encode_u32(4, saturation_posterization_count)
	push_constants.encode_u32(8, value_posterization_count)
	var flags := 0
	if hue_skip_zero: flags |= 1
	if saturation_skip_zero: flags |= 2
	if value_skip_zero: flags |= 4
	push_constants.encode_u32(12, flags)

	var color_uniform := RDUniform.new()
	color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	color_uniform.binding = 0
	color_uniform.add_id(PixelArtBuffers.ensure_color(rd))

	var bindings: Array[RDUniform] = [color_uniform]
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
