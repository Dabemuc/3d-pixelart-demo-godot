#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Full-res inputs (read via samplers — depth/normal can't be bound as image2D)
layout(rgba16f, set = 0, binding = 0) readonly uniform image2D full_res_color;
layout(set = 0, binding = 1) uniform sampler2D full_res_depth;
layout(set = 0, binding = 2) uniform sampler2D full_res_normal;

// Pixel-art outputs (written as storage images)
layout(rgba16f, set = 0, binding = 3) writeonly uniform image2D pixel_art_color;
layout(r32f,   set = 0, binding = 4) writeonly uniform image2D pixel_art_depth;
layout(rgba16f, set = 0, binding = 5) writeonly uniform image2D pixel_art_normal;

void main() {
	ivec2 pixel_art_size = imageSize(pixel_art_color);
	ivec2 full_res_size  = imageSize(full_res_color);
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);

	if (uv.x >= pixel_art_size.x || uv.y >= pixel_art_size.y)
		return;

	// Cell center in normalized [0, 1] space
	vec2 uv_norm = (vec2(uv) + 0.5) / vec2(pixel_art_size);

	// Color — imageLoad at cell center in full-res texel space
	ivec2 full_res_uv = ivec2(uv_norm * vec2(full_res_size));
	imageStore(pixel_art_color, uv, imageLoad(full_res_color, full_res_uv));

	// Depth — sampled as float, stored raw (non-linear is fine for edge detection)
	float depth = texture(full_res_depth, uv_norm).r;
	imageStore(pixel_art_depth, uv, vec4(depth, 0.0, 0.0, 1.0));

	// Normal — stored as [0,1] xyz, remap to [-1,1] and normalize
	vec3 normal = normalize(texture(full_res_normal, uv_norm).xyz * 2.0 - 1.0);
	imageStore(pixel_art_normal, uv, vec4(normal, 1.0));
}
