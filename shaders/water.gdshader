shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.2, 0.5, 0.7, 0.82);
uniform vec4 deep_color : source_color = vec4(0.04, 0.15, 0.35, 0.95);
uniform float wave_speed : hint_range(0.0, 3.0) = 0.5;
uniform float wave_strength : hint_range(0.0, 0.05) = 0.006;

varying vec3 v_world_pos;
varying vec3 v_normal_interp;

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
	vec3 n = normalize(vec3(-dx, 1.0, -dz));
	NORMAL = n;

	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal_interp = (MODEL_MATRIX * vec4(n, 0.0)).xyz;
}

void fragment() {
	vec3 N = normalize(v_normal_interp);
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_pos);

	float fresnel = pow(1.0 - max(dot(N, V), 0.0), 4.0);
	fresnel = clamp(fresnel, 0.0, 1.0);

	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, 0.45 + fresnel * 0.55);
	ALPHA = 1.0;

	float t = TIME;

	float shimmer1 = noise(v_world_pos.xz * 12.0 + t * 0.8);
	float shimmer2 = noise(v_world_pos.xz * 24.0 - t * 1.2);
	float shimmer3 = noise(v_world_pos.xz * 6.0 + t * 0.3);
	float shimmer = shimmer1 * 0.5 + shimmer2 * 0.3 + shimmer3 * 0.2;
	shimmer = pow(shimmer, 3.0);

	ALBEDO += vec3(0.15, 0.2, 0.25) * shimmer * (0.6 + fresnel * 0.4);

	METALLIC = 0.3;
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
}
