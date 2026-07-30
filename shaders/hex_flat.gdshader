shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float noise_freq : hint_range(0.001, 0.1) = 0.008;
uniform float noise_seed = 42.0;
uniform int noise_octaves : hint_range(1, 8) = 6;
uniform float noise_lacunarity = 2.0;
uniform float noise_gain = 0.5;
uniform float height_step : hint_range(0.5, 5.0, 0.1) = 3.0;
uniform float height_exp : hint_range(0.0, 4.0, 0.1) = 1.0;
uniform float height_scale : hint_range(0.0, 5.0, 0.01) = 1.0;

varying float v_elevation;
varying float v_biome;
varying vec3 v_world_xz;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float perlin(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i + vec2(0, 0)) - 0.5, hash(i + vec2(1, 0)) - 0.5, u.x),
		mix(hash(i + vec2(0, 1)) - 0.5, hash(i + vec2(1, 1)) - 0.5, u.x),
		u.y
	);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100.0);
	for (int i = 0; i < 8; i++) {
		if (i >= noise_octaves) break;
		v += a * perlin(p);
		p = p * noise_lacunarity + shift;
		a *= noise_gain;
	}
	return v;
}

void vertex() {
	float e_norm = CUSTOM0.r;
	v_biome = CUSTOM0.g * 10.0;
	v_elevation = e_norm;

	float h = height_scale * pow(max(height_step * e_norm, 0.001), height_exp);
	VERTEX.y = h;

	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	v_world_xz = vec3(wp.x, 0.0, wp.z);
}

vec3 biome_color(float b, float elev, float detail) {
	vec3 water = vec3(0.08, 0.35, 0.65);
	vec3 beach = vec3(0.76, 0.7, 0.45);
	vec3 grass = vec3(0.3 + detail, 0.65 + detail, 0.15 + detail);
	vec3 forest = vec3(0.18 + detail * 0.5, 0.45 + detail * 0.5, 0.1 + detail * 0.5);
	vec3 rocky = vec3(0.55 + detail, 0.55 + detail, 0.58 + detail);

	vec3 col = water;
	float blend = 0.15;

	col = mix(col, beach, smoothstep(0.5 - blend, 0.5 + blend, b));
	col = mix(col, grass, smoothstep(1.5 - blend, 1.5 + blend, b));
	col = mix(col, forest, smoothstep(2.5 - blend, 2.5 + blend, b));
	col = mix(col, rocky, smoothstep(3.5 - blend, 3.5 + blend, b));
	col = mix(col, vec3(0.95), smoothstep(4.5 - blend, 4.5 + blend, b));

	float snow = smoothstep(0.65, 0.95, elev);
	col = mix(col, vec3(0.95), snow * 0.7);

	return col;
}

void fragment() {
	float nz = fbm(v_world_xz.xz * 0.3 + 50.0) * 0.08;

	vec3 col = biome_color(v_biome, v_elevation, nz);

	vec3 water_col = vec3(0.08, 0.35, 0.65);
	if (v_biome < 0.5) {
		col = mix(col, water_col, 0.6);
		ALPHA = 1.0;
		METALLIC = 0.1;
		ROUGHNESS = 0.2;
		SPECULAR = 0.6;
	} else if (v_biome < 1.5) {
		ROUGHNESS = 0.7;
	} else if (v_biome < 3.5) {
		ROUGHNESS = 0.8;
	} else {
		float snow = smoothstep(0.65, 1.0, v_elevation);
		ROUGHNESS = mix(0.7, 0.35, snow);
	}

	ALBEDO = col;
}
