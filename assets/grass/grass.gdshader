shader_type spatial;
render_mode cull_disabled;

uniform vec3 color : source_color;
uniform vec3 color2 : source_color;
uniform vec3 accent_color1 : source_color;
uniform vec3 accent_color2 : source_color;
uniform sampler2D noise;
uniform float noiseScale = 20.0;
uniform float accent_probability1 = 0.05;
uniform float accent_probability2 = 0.05;

varying vec3 worldPos;
varying float instanceId;

float random(float seed) {
	return fract(sin(seed * 127.1 + 311.7) * 43758.5453123);
}

void vertex() {
	worldPos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	instanceId = float(INSTANCE_ID);
}

void fragment() {
	vec3 noiseLevel = texture(noise, worldPos.xz / noiseScale).rgb;
	ALBEDO = mix(color, color2, 1.0 - UV.y) * mix(color, color2, noiseLevel.r);

	float id_seed1 = random(round(instanceId));
	float id_seed2 = random(round(instanceId) + PI);
	if (id_seed1 < accent_probability1) {
		ALBEDO = accent_color1;
	} else if (id_seed2 < accent_probability2) {
		ALBEDO = accent_color2;
	}

	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = 1.0;
}
