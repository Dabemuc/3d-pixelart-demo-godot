#[compute]
#version 450

// One thread per output pixel, tiled in 8x8 blocks
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant) uniform push_constants {
	mat4 inv_proj_mat; // inverse camera projection, used to linearise depth
	vec2 raster_size;
} parameters;

// Binding 0: color is read-write (image); depth and normal_roughness are read-only (sampler2D)
layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_texture;
layout(set = 0, binding = 2) uniform sampler2D normal_roughness_texture;

// Reconstructs view-space depth from the hardware depth buffer (non-linear, stored in [0,1])
float get_linear_depth(vec2 uv) {
	float raw_depth = texture(depth_texture, uv).r;
	// Expand UV to NDC [-1,1] and combine with raw depth to form a clip-space position
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw_depth);
	// Unproject to view space using the inverse projection matrix
	vec4 view = parameters.inv_proj_mat * vec4(ndc, 1.0);
	view.xyz /= view.w; // perspective divide
	return -view.z;     // view space Z is negative looking forward; negate for positive distance
}

// Decodes the packed normal and roughness from Godot's forward_clustered G-buffer
vec4 get_normal_roughness(vec2 uv) {
	vec4 normal_roughness = texture(normal_roughness_texture, uv);
	float roughness = normal_roughness.w;
	// Godot encodes roughness symmetrically: values above 0.5 are mirrored back to [0, 0.5]
	if (roughness > 0.5)
		roughness = 1.0 - roughness;
	// Scale from the stored [0, 127/255] range back to [0, 1]
	roughness /= (127.0 / 255.0);
	// Normals are stored as [0,1]; remap to [-1,1] and re-normalise after interpolation
	return vec4(normalize(normal_roughness.xyz * 2.0 - 1.0), roughness);
}

const vec2 TARGET_RESOLUTION = vec2(640.0, 360.0); // pixel-art canvas size

const float DITHER_AMOUNT = 0.2;
const float NUM_COLORS = 16.0;
// Pre-computed: dividing by NUM_COLORS² maps the 0-15 Bayer index to a [-0.5, 0.5] offset
const float INV_NUM_COLORS_SQUARED = 1.0 / (NUM_COLORS * NUM_COLORS);
// Standard 4x4 ordered Bayer matrix (indices 0-15, row-major)
const mat4 BAYER_MATRIX = mat4(
	vec4(0.0, 8.0, 2.0, 10.0), vec4(12.0, 4.0, 14.0, 6.0), vec4(3.0, 11.0, 1.0, 9.0), vec4(15.0, 7.0, 13.0, 5.0)
);

void main() {
	vec2 size = parameters.raster_size;
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
	vec2 uv_normalized = uv / size;

	// Discard threads that fall outside the render target (overhang from ceiling-division dispatch)
	if (uv.x >= size.x || uv.y >= size.y)
		return;

	// Step 1 — Pixelation: snap each screen pixel to the nearest pixel-art pixel centre
	vec2 rounded_uv = floor(uv_normalized * TARGET_RESOLUTION) / TARGET_RESOLUTION;
	// +1 pixel offset avoids sampling the left/top border texel which can be uninitialised
	vec4 screen_color = imageLoad(color_image, ivec2(floor(rounded_uv * size)) + 1);

	// Step 2 — Ordered dithering: offset the color slightly before quantisation
	// Map the pixel-art pixel coordinate to a 4x4 repeating Bayer cell
	ivec2 map_coord = ivec2(mod(rounded_uv * TARGET_RESOLUTION, 4.0));
	// Threshold is centred around 0 so it both brightens and darkens evenly
	float dither = BAYER_MATRIX[map_coord.x][map_coord.y] * INV_NUM_COLORS_SQUARED - 0.5;
	vec4 dithered_color = screen_color + dither * DITHER_AMOUNT;

	// Step 3 — Color quantisation: round to the nearest of NUM_COLORS discrete levels per channel
	vec4 quantized_color = vec4((floor(screen_color * (NUM_COLORS - 1.0) + 0.5) / (NUM_COLORS - 1.0)).rgb, 1.0);

	// Step 4 — Edge detection: sample the current pixel plus its right and bottom neighbours
	// (all snapped to the pixel-art grid, so neighbours are one pixel-art pixel apart)
	vec2 uv_samples[3] = {
		rounded_uv,
		rounded_uv + vec2(1.0, 0.0) / TARGET_RESOLUTION,
		rounded_uv + vec2(0.0, 1.0) / TARGET_RESOLUTION
	};

	float dc = get_linear_depth(uv_samples[0]);
	float d0 = get_linear_depth(uv_samples[1]);
	float d1 = get_linear_depth(uv_samples[2]);

	vec3 nc = get_normal_roughness(uv_samples[0]).xyz;
	vec3 n0 = get_normal_roughness(uv_samples[1]).xyz;
	vec3 n1 = get_normal_roughness(uv_samples[2]).xyz;

	// Depth edge: adaptive threshold (dc/8 + 0.1) grows with distance to avoid false edges on far geometry
	float depth_difference = abs(dc - d0) + abs(dc - d1);
	float depth_border = 1.0 - clamp(step(dc / 8.0 + 0.1, depth_difference), 0.0, 1.0);

	// Normal edge: only fire where depth is continuous (< 0.1 difference) to avoid duplicating depth edges.
	// The asymmetric step() selectors (nc.x vs n0.x, n1.y vs nc.y) assign each shared edge to one
	// side only, preventing double-darkening at corners.
	float normal_difference = distance(nc, n0) * step(nc.x, n0.x) + distance(nc, n1) * step(n1.y, nc.y);
	float normal_border = step(dc / 12.0, normal_difference * step(depth_difference, 0.1));

	// Step 5 — Composite: depth edges darken to black; normal edges darken an additional 2.5×
	imageStore(color_image, ivec2(uv), depth_border * (1.0 + normal_border * 2.5) * quantized_color);
}
