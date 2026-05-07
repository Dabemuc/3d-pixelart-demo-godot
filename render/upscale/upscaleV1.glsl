#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) writeonly uniform image2D full_res_color;
layout(rgba16f, set = 0, binding = 1) readonly uniform image2D pixel_art_color;

void main() {
	ivec2 full_res_size = imageSize(full_res_color);
	ivec2 pixel_art_size = imageSize(pixel_art_color);
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);

	if (uv.x >= full_res_size.x || uv.y >= full_res_size.y)
		return;

	// Nearest-neighbor: map full-res pixel back to pixel-art pixel
	vec2 uv_normalized = vec2(uv) / vec2(full_res_size);
	ivec2 pixel_art_uv = ivec2(uv_normalized * vec2(pixel_art_size));

	imageStore(full_res_color, uv, imageLoad(pixel_art_color, pixel_art_uv));
}
