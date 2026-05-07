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

// --- CIE Lab conversion ---

vec3 rgb2xyz(vec3 rgb) {
	rgb = pow(rgb, vec3(2.2));
	mat3x3 m = mat3x3(
		0.4124564, 0.2126729, 0.0193339,
		0.3575761, 0.7151522, 0.1191920,
		0.1804375, 0.0721750, 0.9503041
	);
	return m * rgb;
}

vec3 xyz2lab(vec3 xyz) {
	// D65 white point
	xyz /= vec3(0.95047, 1.0, 1.08883);

	vec3 f = mix(7.787 * xyz + vec3(16.0 / 116.0), pow(xyz, vec3(1.0 / 3.0)), vec3(greaterThan(xyz, vec3(0.008856))));

	return vec3(
		116.0 * f.y - 16.0,
		500.0 * (f.x - f.y),
		200.0 * (f.y - f.z)
	);
}

vec3 rgb2lab(vec3 rgb) {
	return xyz2lab(rgb2xyz(rgb));
}

// --- Palette ---
// 8-color palette (Resurrect 8 by Kerrie Lake)
const int PALETTE_SIZE = 8;
const vec3 PALETTE[PALETTE_SIZE] = vec3[](
	vec3(0.114, 0.067, 0.122),  // #1d1127
	vec3(0.302, 0.133, 0.188),  // #4d2230
	vec3(0.671, 0.243, 0.224),  // #ab3e39
	vec3(0.933, 0.620, 0.310),  // #ee9e4f
	vec3(0.988, 0.945, 0.694),  // #fcf1b1
	vec3(0.388, 0.729, 0.565),  // #63ba90
	vec3(0.141, 0.380, 0.549),  // #24618c
	vec3(0.067, 0.133, 0.251)   // #11223f
);


void main() {
	vec2 size = parameters.raster_size;
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);

	// Discard threads that are out of bounds
	if (uv.x >= size.x || uv.y >= size.y)
		return;

	// Normalize uv to [0, 1]
	vec2 uv_normalized = vec2(uv) / size;

	// Point filter downsample: sample from the center of the pixel-art cell
	vec2 pixel_art_cell = floor(uv_normalized * TARGET_RESOLUTION);
	vec2 cell_center_uv = (pixel_art_cell + 0.5) / TARGET_RESOLUTION;

	vec4 color = imageLoad(color_image, ivec2(cell_center_uv * size));

	// Find the nearest palette color in CIE Lab space
	vec3 lab_color = rgb2lab(color.rgb);
	float best_dist = 1e9;
	vec3 best_color = PALETTE[0];

	for (int i = 0; i < PALETTE_SIZE; i++) {
		vec3 diff = lab_color - rgb2lab(PALETTE[i]);
		float dist = dot(diff, diff);
		if (dist < best_dist) {
			best_dist = dist;
			best_color = PALETTE[i];
		}
	}

	imageStore(color_image, uv, vec4(best_color, color.a));
}
