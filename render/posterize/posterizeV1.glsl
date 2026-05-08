#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant) uniform push_constants {
	uint hue_posterization_count;
    uint saturation_posterization_count;
    uint value_posterization_count;
    uint flags; // bit 0: hue skip zero, bit 1: sat skip zero, bit 2: val skip zero
} parameters;

layout(rgba16f, set = 0, binding = 0) uniform image2D pixel_art_color;

vec3 rgb_to_hsv(vec3 c) {
    float cmax = max(c.r, max(c.g, c.b));
    float cmin = min(c.r, min(c.g, c.b));
    float delta = cmax - cmin;

    float v = cmax;
    float s = (cmax < 0.0001) ? 0.0 : delta / cmax;
    float h = 0.0;
    if (delta > 0.0001) {
        if (cmax == c.r)      h = mod((c.g - c.b) / delta, 6.0) / 6.0;
        else if (cmax == c.g) h = ((c.b - c.r) / delta + 2.0) / 6.0;
        else                  h = ((c.r - c.g) / delta + 4.0) / 6.0;
    }
    return vec3(h, s, v);
}

vec3 hsv_to_rgb(vec3 hsv) {
    float h = hsv.x * 6.0;
    float s = hsv.y;
    float v = hsv.z;
    float i = floor(h);
    float f = h - i;
    float p = v * (1.0 - s);
    float q = v * (1.0 - f * s);
    float t = v * (1.0 - (1.0 - f) * s);
    int sector = int(mod(i, 6.0));
    if (sector == 0) return vec3(v, t, p);
    if (sector == 1) return vec3(q, v, p);
    if (sector == 2) return vec3(p, v, t);
    if (sector == 3) return vec3(p, q, v);
    if (sector == 4) return vec3(t, p, v);
                     return vec3(v, p, q);
}

// hsv posterization if step counts are non-zero. alpha channel is left unchanged.
void main(){
    ivec2 pixel_coords = ivec2(gl_GlobalInvocationID.xy);
    vec4 color = imageLoad(pixel_art_color, pixel_coords);

    vec3 hsv = rgb_to_hsv(color.rgb);

    if (parameters.hue_posterization_count != 0) {
        float step = 1.0 / float(parameters.hue_posterization_count);
        hsv.x = floor(hsv.x / step) * step;
        if ((parameters.flags & 1u) != 0u) hsv.x = max(hsv.x, step);
    }
    if (parameters.saturation_posterization_count != 0) {
        float step = 1.0 / float(parameters.saturation_posterization_count);
        hsv.y = floor(hsv.y / step) * step;
        if ((parameters.flags & 2u) != 0u) hsv.y = max(hsv.y, step);
    }
    if (parameters.value_posterization_count != 0) {
        float step = 1.0 / float(parameters.value_posterization_count);
        hsv.z = floor(hsv.z / step) * step;
        if ((parameters.flags & 4u) != 0u) hsv.z = max(hsv.z, step);
    }

    imageStore(pixel_art_color, pixel_coords, vec4(hsv_to_rgb(hsv), color.a));
}
