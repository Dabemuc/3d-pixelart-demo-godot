@tool
extends CompositorEffect
class_name SampleEffect

# Debug visualisation mode; packed into push constants and read by the shader's switch statement
@export_enum("Color", "Depth", "Normal", "Roughness") var mode := 0

var rd := RenderingServer.get_rendering_device()
var shader: RID
var pipeline: RID
var depth_sampler: RID
var normal_roughness_sampler: RID

func _init() -> void:
	# Request the forward_clustered normal/roughness G-buffer; without this flag it won't exist
	needs_normal_roughness = true
	var shader_file := preload("sample_effect.glsl")
	# Compile GLSL to SPIR-V at load time, then upload to the GPU driver
	var shader_spirv := shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

	# Default RDSamplerState gives nearest-neighbour + clamp, appropriate for buffer reads
	depth_sampler = rd.sampler_create(RDSamplerState.new())
	normal_roughness_sampler = rd.sampler_create(RDSamplerState.new())

func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	var render_scene_buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	var size := render_scene_buffers.get_internal_size()

	# The depth visualisation mode reconstructs linear depth, so it needs the inverse projection
	var inv_proj_mat := render_data.get_render_scene_data().get_cam_projection().inverse()
	var inv_proj_mat_array := PackedVector4Array([inv_proj_mat.x, inv_proj_mat.y, inv_proj_mat.z, inv_proj_mat.w])
	# mode is packed into the z component of the second vec4 to satisfy push_constant alignment
	var raster_size := PackedFloat32Array([size.x, size.y, mode, 0.0])

	# Push constants are the fastest path for per-frame scalar data (no descriptor overhead)
	var push_constants := inv_proj_mat_array.to_byte_array()
	push_constants.append_array(raster_size.to_byte_array())

	# Color is bound as a read-write image so the shader can overwrite pixels in-place
	var color_layer_uniform := RDUniform.new()
	color_layer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	color_layer_uniform.binding = 0
	color_layer_uniform.add_id(render_scene_buffers.get_color_layer(0))

	# Depth and normal/roughness are read-only, so a combined sampler+texture binding is sufficient
	var depth_layer_uniform := RDUniform.new()
	depth_layer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	depth_layer_uniform.binding = 1
	depth_layer_uniform.add_id(depth_sampler)
	depth_layer_uniform.add_id(render_scene_buffers.get_depth_layer(0))

	var normal_roughness_layer_uniform := RDUniform.new()
	normal_roughness_layer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	normal_roughness_layer_uniform.binding = 2
	normal_roughness_layer_uniform.add_id(normal_roughness_sampler)
	normal_roughness_layer_uniform.add_id(render_scene_buffers.get_texture("forward_clustered", "normal_roughness"))

	var bindings: Array[RDUniform] = [
		color_layer_uniform,
		depth_layer_uniform,
		normal_roughness_layer_uniform
	]

	# Ceiling division: ensures every pixel is covered even when size is not a multiple of 8
	var groups := Vector3i((size.x - 1.0) / 8.0 + 1.0, (size.y - 1.0) / 8.0 + 1.0, 1)
	# Uniform sets must be recreated each frame because scene buffer texture RIDs can change
	var uniform_set := rd.uniform_set_create(bindings, shader, 0)
	var compute_list := rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	rd.compute_list_dispatch(compute_list, groups.x, groups.y, groups.z)
	rd.compute_list_end()

	# Free immediately; the set holds references to transient texture RIDs
	rd.free_rid(uniform_set)
