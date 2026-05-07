@tool
extends CompositorEffect
class_name UpscaleV1

var rd := RenderingServer.get_rendering_device()
var shader: RID
var pipeline: RID

func _init() -> void:
	var shader_file := preload("res://render/upscale/upscaleV1.glsl")
	var shader_spirv := shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	var render_scene_buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	var full_res_size := render_scene_buffers.get_internal_size()

	var full_res_uniform := RDUniform.new()
	full_res_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	full_res_uniform.binding = 0
	full_res_uniform.add_id(render_scene_buffers.get_color_layer(0))

	var pixel_art_uniform := RDUniform.new()
	pixel_art_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	pixel_art_uniform.binding = 1
	pixel_art_uniform.add_id(PixelArtBuffers.ensure_color(rd))

	var bindings: Array[RDUniform] = [full_res_uniform, pixel_art_uniform]
	var groups := Vector3i(
		(full_res_size.x - 1) / 8 + 1,
		(full_res_size.y - 1) / 8 + 1,
		1
	)
	var uniform_set := rd.uniform_set_create(bindings, shader, 0)
	var compute_list := rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, groups.x, groups.y, groups.z)
	rd.compute_list_end()

	rd.free_rid(uniform_set)
