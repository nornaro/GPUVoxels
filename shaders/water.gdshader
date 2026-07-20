shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.15, 0.75, 0.85, 0.55);
uniform vec4 deep_color : source_color = vec4(0.04, 0.28, 0.45, 0.92);
uniform float wave_speed : hint_range(0.0, 5.0) = 0.8;
uniform float wave_strength : hint_range(0.0, 0.04) = 0.004;

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

	float wave1 = sin(VERTEX.x * 2.5 + t * 1.2) * wave_strength;
	float wave2 = sin(VERTEX.z * 3.0 + t * 0.9) * wave_strength * 0.7;
	float wave3 = cos((VERTEX.x + VERTEX.z) * 1.8 + t * 0.6) * wave_strength * 0.5;
	float wave4 = sin(VERTEX.x * 5.0 - VERTEX.z * 4.0 + t * 1.8) * wave_strength * 0.3;
	VERTEX.y += wave1 + wave2 + wave3 + wave4;

	float dx = wave_strength * 2.5 * cos(VERTEX.x * 2.5 + t * 1.2)
	         + wave_strength * 0.9 * cos((VERTEX.x + VERTEX.z) * 1.8 + t * 0.6)
	         - wave_strength * 1.2 * sin(VERTEX.x * 5.0 - VERTEX.z * 4.0 + t * 1.8);
	float dz = wave_strength * 3.0 * cos(VERTEX.z * 3.0 + t * 0.9)
	         + wave_strength * 0.9 * cos((VERTEX.x + VERTEX.z) * 1.8 + t * 0.6)
	         + wave_strength * 1.2 * cos(VERTEX.x * 5.0 - VERTEX.z * 4.0 + t * 1.8);
	vec3 n = normalize(vec3(-dx, 1.0, -dz));
	NORMAL = n;

	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal_interp = (MODEL_MATRIX * vec4(n, 0.0)).xyz;
}

void fragment() {
	// COLOR.g: 1.0 = water, 0.0 = land (make invisible)
	float is_water = step(0.5, COLOR.g);

	vec3 N = normalize(v_normal_interp);
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_pos);

	float fresnel = pow(1.0 - max(dot(N, V), 0.0), 3.0);
	fresnel = clamp(fresnel, 0.0, 0.9);

	float depth = COLOR.r;

	ALBEDO = mix(shallow_color.rgb, deep_color.rgb, depth);
	ALBEDO += fresnel * vec3(0.2, 0.35, 0.3);

	float base_alpha = mix(shallow_color.a, deep_color.a, depth);

	float t = TIME * 0.5;
	float shimmer1 = noise(v_world_pos.xz * 8.0 + t * 0.6);
	float shimmer2 = noise(v_world_pos.xz * 16.0 - t * 0.9);
	float shimmer = shimmer1 * 0.6 + shimmer2 * 0.4;
	shimmer = pow(shimmer, 4.0);
	ALBEDO += vec3(0.18, 0.3, 0.25) * shimmer;

	ALPHA = base_alpha * is_water;

	METALLIC = 0.1;
	ROUGHNESS = 0.2;
	SPECULAR = 0.6;
}
