@tool
extends CompositorEffect
class_name PixelateV1

var rd := RenderingServer.get_rendering_device()
var shader: RID
var pipeline: RID

func _init() -> void:
	var shader_file := preload("res://render/pixelate/pixelateV1.glsl")
	var shader_spirv := shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	var render_scene_buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	var size := render_scene_buffers.get_internal_size()

	var push_constants := PackedByteArray()
	push_constants.resize(16)
	push_constants.encode_float(0, size.x)
	push_constants.encode_float(4, size.y)

	var color_layer_uniform := RDUniform.new()
	color_layer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	color_layer_uniform.binding = 0
	color_layer_uniform.add_id(render_scene_buffers.get_color_layer(0))

	var bindings: Array[RDUniform] = [color_layer_uniform]

	var groups := Vector3i((size.x - 1.0) / 8.0 + 1.0, (size.y - 1.0) / 8.0 + 1.0, 1)
	var uniform_set := rd.uniform_set_create(bindings, shader, 0)
	var compute_list := rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	rd.compute_list_dispatch(compute_list, groups.x, groups.y, groups.z)
	rd.compute_list_end()

	rd.free_rid(uniform_set)
