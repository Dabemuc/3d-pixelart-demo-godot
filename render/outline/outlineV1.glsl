#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant) uniform push_constants {
	float depth_bias;       // min depth difference to count as a silhouette edge
	float outline_strength; // how much to darken edge pixels [0, 1]
	float normal_bias;      // min normal difference to count as a crease
	float crease_strength;  // how much to brighten crease pixels [0, 1]
} parameters;

layout(rgba16f, set = 0, binding = 0) uniform image2D pixel_art_color;
layout(r32f,    set = 0, binding = 1) readonly uniform image2D pixel_art_depth;
layout(rgba16f, set = 0, binding = 2) readonly uniform image2D pixel_art_normal;

const ivec2 NEIGHBORS[4] = ivec2[](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));

bool neighbor_creates_silhouette(float center_depth, ivec2 uv, ivec2 size) {
	if (uv.x < 0 || uv.x >= size.x || uv.y < 0 || uv.y >= size.y)
		return false;
	float neighbor_depth = imageLoad(pixel_art_depth, uv).r;
	// Directional check: only darken the closer (foreground) pixel.
	// In Godot's reversed-Z buffer, closer = higher depth value.
	return (center_depth - neighbor_depth) > parameters.depth_bias;
}

bool neighbor_creates_crease(vec3 center_normal, float center_depth, ivec2 uv, ivec2 size) {
	if (uv.x < 0 || uv.x >= size.x || uv.y < 0 || uv.y >= size.y)
		return false;

	// Skip if the depth difference is too large — that's a silhouette, not a crease
	float neighbor_depth = imageLoad(pixel_art_depth, uv).r;
	if (abs(center_depth - neighbor_depth) > parameters.depth_bias * 0.25)
		return false;

	vec3 neighbor_normal = imageLoad(pixel_art_normal, uv).rgb;
	float normal_diff = 1.0 - dot(center_normal, neighbor_normal);

	// Only highlight the side facing the camera more (center z >= neighbor z)
	return normal_diff > parameters.normal_bias && center_normal.z >= neighbor_normal.z;
}

void main() {
	ivec2 size = imageSize(pixel_art_color);
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);

	if (uv.x >= size.x || uv.y >= size.y)
		return;

	float center_depth  = imageLoad(pixel_art_depth, uv).r;
	vec3  center_normal = imageLoad(pixel_art_normal, uv).rgb;

	bool is_silhouette = false;
	bool is_crease     = false;

	for (int i = 0; i < 4; i++) {
		ivec2 n = uv + NEIGHBORS[i];
		if (!is_silhouette && neighbor_creates_silhouette(center_depth, n, size))
			is_silhouette = true;
		if (!is_crease && neighbor_creates_crease(center_normal, center_depth, n, size))
			is_crease = true;
	}

	if (is_silhouette || is_crease) {
		vec4 color = imageLoad(pixel_art_color, uv);
		if (is_silhouette)
			color.rgb *= (1.0 - parameters.outline_strength);
		else
			color.rgb = min(color.rgb + parameters.crease_strength, vec3(1.0));
		imageStore(pixel_art_color, uv, color);
	}
}
