#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) readonly uniform image2D full_res_color;
layout(rgba16f, set = 0, binding = 1) writeonly uniform image2D pixel_art_color;

void main() {
	ivec2 pixel_art_size = imageSize(pixel_art_color);
	ivec2 full_res_size = imageSize(full_res_color);
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);

	if (uv.x >= pixel_art_size.x || uv.y >= pixel_art_size.y)
		return;

	// Map this pixel-art pixel to its center in full-res space
	vec2 uv_normalized = (vec2(uv) + 0.5) / vec2(pixel_art_size);
	ivec2 full_res_uv = ivec2(uv_normalized * vec2(full_res_size));

	imageStore(pixel_art_color, uv, imageLoad(full_res_color, full_res_uv));
}
