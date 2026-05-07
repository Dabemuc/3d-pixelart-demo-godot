#[compute]
#version 450

// One thread per output pixel, tiled in 8x8 blocks
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant) uniform push_constants {
	mat4 inv_proj_mat; // inverse camera projection, used to linearise depth in mode 1
	vec2 raster_size;
	float mode;        // 0=Color, 1=Depth, 2=Normal, 3=Roughness
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
	// Normals are stored as [0,1]; remap to [-1,1], re-normalise, then back to [0,1] for display
	return vec4(normalize(normal_roughness.xyz * 2.0 - 1.0) * 0.5 + 0.5, roughness);
}

void main() {
	vec2 size = parameters.raster_size;
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
	vec2 uv_normalized = uv / size;

	// Discard threads that fall outside the render target (overhang from ceiling-division dispatch)
	if (uv.x >= size.x || uv.y >= size.y)
		return;

	vec4 color = imageLoad(color_image, uv);
	float depth = texture(depth_texture, uv_normalized).r; // raw (non-linear) hardware depth
	vec4 normal_roughness = get_normal_roughness(uv_normalized);

	switch (int(parameters.mode)) {
		case 0: // Original HDR color from the forward renderer
			imageStore(color_image, uv, vec4(color.rgb, 1.0));
			break;
		case 1: // Linear depth scaled for visibility; *12 spreads typical scene depth into [0,1]
			imageStore(color_image, uv, vec4(vec3(12.0 * depth - 0.1), 1.0));
			break;
		case 2: // World-space normals mapped from [-1,1] to [0,1] RGB
			imageStore(color_image, uv, vec4(normal_roughness.xyz, 1.0));
			break;
		case 3: // Roughness as greyscale
			imageStore(color_image, uv, vec4(vec3(normal_roughness.w), 1.0));
			break;
	}
}
