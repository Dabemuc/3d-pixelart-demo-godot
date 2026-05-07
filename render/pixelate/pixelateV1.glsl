#[compute]
#version 450

// Group definition: 8x8x1 threads per group
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant) uniform push_constants {
	vec2 raster_size;
	vec2 _pad;
} parameters;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;

const vec2 TARGET_RESOLUTION = vec2(640.0, 360.0);

void main() {
	vec2 size = parameters.raster_size;
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy); // Pixel coordinates of this thread

    // Discard the thread if its out of bounds
	if (uv.x >= size.x || uv.y >= size.y)
		return;

    // Normalize uv to [0, 1]
	vec2 uv_normalized = vec2(uv) / size;

	// Point filter downsample: sample from the center of the pixel-art cell
	vec2 pixel_art_cell = floor(uv_normalized * TARGET_RESOLUTION); // Get coordinates of the pixel-art cell this thread falls into
	vec2 cell_center_uv = (pixel_art_cell + 0.5) / TARGET_RESOLUTION;   // Get the normalized ([0, 1]) coordinates of the center of that cell

    // Sample the color from the original image at the center of the pixel-art cell
	vec4 color = imageLoad(color_image, ivec2(cell_center_uv * size));

    // Write the sampled color to the output image at the thread's pixel coordinates
	imageStore(color_image, uv, color);
}
