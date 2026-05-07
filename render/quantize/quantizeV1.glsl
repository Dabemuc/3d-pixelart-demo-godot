#[compute]
#version 450

// Group definition: 8x8x1 threads per group
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant) uniform push_constants {
	int palette_size;
	int use_lab;
	ivec2 _pad;
} parameters;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;

layout(set = 0, binding = 1, std430) readonly buffer PaletteBuffer {
	vec4 colors[];
} palette_buf;

// --- CIE Lab conversion ---

vec3 rgb2xyz(vec3 rgb) {
	rgb = pow(rgb, vec3(2.2));
	mat3 m = mat3(
		vec3(0.4124564, 0.2126729, 0.0193339),
		vec3(0.3575761, 0.7151522, 0.1191920),
		vec3(0.1804375, 0.0721750, 0.9503041)
	);
	return m * rgb;
}

vec3 xyz2lab(vec3 xyz) {
	xyz /= vec3(0.95047, 1.0, 1.08883);
	vec3 f = mix(
		7.787 * xyz + vec3(16.0 / 116.0),
		pow(xyz, vec3(1.0 / 3.0)),
		vec3(greaterThan(xyz, vec3(0.008856)))
	);
	return vec3(116.0 * f.y - 16.0, 500.0 * (f.x - f.y), 200.0 * (f.y - f.z));
}

vec3 rgb2lab(vec3 rgb) {
	return xyz2lab(rgb2xyz(rgb));
}

void main() {
	ivec2 size = imageSize(color_image);
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);

	// Discard threads that are out of bounds
	if (uv.x >= size.x || uv.y >= size.y)
		return;

	vec4 color = imageLoad(color_image, uv);

	// Find the nearest palette color
	vec3 compare_color = parameters.use_lab == 1 ? rgb2lab(color.rgb) : color.rgb;
	float best_dist = 1e9;
	vec3 best_color = palette_buf.colors[0].rgb;

	for (int i = 0; i < parameters.palette_size; i++) {
		vec3 palette_color = palette_buf.colors[i].rgb;
		vec3 compare_palette = parameters.use_lab == 1 ? rgb2lab(palette_color) : palette_color;
		vec3 diff = compare_color - compare_palette;
		float dist = dot(diff, diff);
		if (dist < best_dist) {
			best_dist = dist;
			best_color = palette_color;
		}
	}

	imageStore(color_image, uv, vec4(best_color, color.a));
}
