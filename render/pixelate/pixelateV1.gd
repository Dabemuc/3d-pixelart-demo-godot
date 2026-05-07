@tool
extends CompositorEffect
class_name PixelateV1

var rd := RenderingServer.get_rendering_device()
var shader: RID
var pipeline: RID
var nearest_sampler: RID

@export_range(0.0, 1.0) var outline_mask_threshold: float = 0.49
@export_range(0.0, 1.0) var crease_mask_threshold: float = 0.49

func _init() -> void:
	needs_normal_roughness = true

	var shader_file := preload("res://render/pixelate/pixelateV1.glsl")
	var shader_spirv := shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	nearest_sampler = rd.sampler_create(sampler_state)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if nearest_sampler.is_valid():
			rd.free_rid(nearest_sampler)

func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	var render_scene_buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	var pixel_art_size := PixelArtBuffers.TARGET_SIZE

	var color_in_uniform := RDUniform.new()
	color_in_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	color_in_uniform.binding = 0
	color_in_uniform.add_id(render_scene_buffers.get_color_layer(0))

	var depth_uniform := RDUniform.new()
	depth_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	depth_uniform.binding = 1
	depth_uniform.add_id(nearest_sampler)
	depth_uniform.add_id(render_scene_buffers.get_depth_layer(0))

	var normal_uniform := RDUniform.new()
	normal_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	normal_uniform.binding = 2
	normal_uniform.add_id(nearest_sampler)
	normal_uniform.add_id(render_scene_buffers.get_texture("forward_clustered", "normal_roughness"))

	var color_out_uniform := RDUniform.new()
	color_out_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	color_out_uniform.binding = 3
	color_out_uniform.add_id(PixelArtBuffers.ensure_color(rd))

	var depth_out_uniform := RDUniform.new()
	depth_out_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	depth_out_uniform.binding = 4
	depth_out_uniform.add_id(PixelArtBuffers.ensure_depth(rd))

	var normal_out_uniform := RDUniform.new()
	normal_out_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	normal_out_uniform.binding = 5
	normal_out_uniform.add_id(PixelArtBuffers.ensure_normal(rd))

	var mask_out_uniform := RDUniform.new()
	mask_out_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	mask_out_uniform.binding = 6
	mask_out_uniform.add_id(PixelArtBuffers.ensure_mask(rd))

	var bindings: Array[RDUniform] = [
		color_in_uniform, depth_uniform, normal_uniform,
		color_out_uniform, depth_out_uniform, normal_out_uniform, mask_out_uniform,
	]
	var groups := Vector3i(
		(pixel_art_size.x - 1) / 8 + 1,
		(pixel_art_size.y - 1) / 8 + 1,
		1
	)
	var uniform_set := rd.uniform_set_create(bindings, shader, 0)
	var compute_list := rd.compute_list_begin()

	var push_constants := PackedByteArray()
	push_constants.resize(16)
	push_constants.encode_float(0, outline_mask_threshold)
	push_constants.encode_float(4, crease_mask_threshold)
	push_constants.encode_float(8, 0.0)
	push_constants.encode_float(12, 0.0)

	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	rd.compute_list_dispatch(compute_list, groups.x, groups.y, groups.z)
	rd.compute_list_end()

	rd.free_rid(uniform_set)
