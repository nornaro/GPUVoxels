shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.15, 0.35, 0.38, 0.78);
uniform vec4 deep_color : source_color = vec4(0.02, 0.08, 0.12, 0.95);
uniform vec4 foam_color : source_color = vec4(0.7, 0.75, 0.8, 0.85);
uniform float wave_speed : hint_range(0.0, 3.0) = 0.5;
uniform float wave_strength : hint_range(0.0, 0.05) = 0.006;
uniform float shore_foam_width : hint_range(0.0, 1.0) = 0.15;

varying float v_height_above_floor;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	float t = TIME * wave_speed;

	float wave1 = sin(VERTEX.x * 1.8 + t * 1.0) * wave_strength;
	float wave2 = sin(VERTEX.z * 2.2 + t * 0.7) * wave_strength * 0.6;
	float wave3 = cos((VERTEX.x + VERTEX.z) * 1.2 + t * 0.5) * wave_strength * 0.4;
	float wave4 = sin(VERTEX.x * 4.0 - VERTEX.z * 3.0 + t * 1.5) * wave_strength * 0.2;
	VERTEX.y += wave1 + wave2 + wave3 + wave4;

	float dx = wave_strength * 1.8 * cos(VERTEX.x * 1.8 + t * 1.0)
	         + wave_strength * 0.4 * cos((VERTEX.x + VERTEX.z) * 1.2 + t * 0.5)
	         - wave_strength * 0.4 * sin(VERTEX.x * 4.0 - VERTEX.z * 3.0 + t * 1.5);
	float dz = wave_strength * 2.2 * cos(VERTEX.z * 2.2 + t * 0.7)
	         + wave_strength * 0.4 * cos((VERTEX.x + VERTEX.z) * 1.2 + t * 0.5)
	         + wave_strength * 0.6 * cos(VERTEX.x * 4.0 - VERTEX.z * 3.0 + t * 1.5);
	NORMAL = normalize(vec3(-dx, 1.0, -dz));
}

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float fresnel = pow(1.0 - max(dot(normalize(NORMAL), view_dir), 0.0), 3.0);
	fresnel = clamp(fresnel, 0.0, 0.6);

	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, 0.5 + fresnel);
	ALPHA = mix(deep_color.a, shallow_color.a, 0.5 + fresnel);

	float t = TIME * 0.3;
	float sparkle = noise((MODEL_MATRIX * vec4(VERTEX, 1.0)).xz * 20.0 + t * 1.5);
	sparkle = pow(sparkle, 12.0);
	ALBEDO += vec3(sparkle * 0.04);

	METALLIC = 0.0;
	ROUGHNESS = 0.3;
	SPECULAR = 0.4;
}
