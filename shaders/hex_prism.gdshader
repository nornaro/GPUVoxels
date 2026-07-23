shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float noise_freq : hint_range(0.001, 0.1) = 0.008;
uniform float noise_seed = 42.0;
uniform int noise_octaves : hint_range(1, 8) = 6;
uniform float noise_lacunarity = 2.0;
uniform float noise_gain = 0.5;
uniform float max_height = 5.0;
uniform float water_level = 0.32;
uniform float grid_line_width : hint_range(0.0, 0.5) = 0.08;

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

float hex_sdf_flat_top(vec2 p, float inradius) {
	p = abs(p);
	return max(p.x * 0.86602540378 + p.y * 0.5, p.y) - inradius;
}

vec2 find_hex_center(vec2 p, float R) {
	float s3 = sqrt(3.0);
	float qf = (2.0 / 3.0 * p.x) / R;
	float rf = (-1.0 / 3.0 * p.x + s3 / 3.0 * p.y) / R;
	float sf = -qf - rf;

	float rq = round(qf);
	float rr = round(rf);
	float rs = round(sf);

	float dq = abs(rq - qf);
	float dr = abs(rr - rf);
	float ds = abs(rs - sf);

	if (dq > dr && dq > ds) {
		rq = -rr - rs;
	} else if (dr > ds) {
		rr = -rq - rs;
	} else {
		rs = -rq - rr;
	}

	return vec2(R * 1.5 * float(rq), R * s3 * (float(rr) + float(rq) * 0.5));
}

float hex_grid_line(vec2 p, float R) {
	vec2 center = find_hex_center(p, R);
	return hex_sdf_flat_top(p - center, R * 0.86602540378);
}

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec2 wxz = wp.xz;
	v_world_xz = vec3(wxz.x, 0.0, wxz.y);

	float e = fbm(wxz * noise_freq + noise_seed);
	e = e * 0.5 + 0.5;
	e = clamp(e, 0.0, 1.0);
	v_elevation = e;

	if (e < water_level * 0.5) v_biome = 0.0;
	else if (e < water_level) v_biome = 1.0;
	else if (e < water_level + 0.04) v_biome = 2.0;
	else if (e < 0.42) v_biome = 3.0;
	else if (e < 0.52) v_biome = 4.0;
	else if (e < 0.62) v_biome = 6.0;
	else if (e < 0.72) v_biome = 7.0;
	else if (e < 0.82) v_biome = 8.0;
	else if (e < 0.92) v_biome = 9.0;
	else v_biome = 10.0;

	float h = max(e * max_height, 0.05);
	VERTEX.y = h;
}

void fragment() {
	float v = fbm(v_world_xz.xz * 0.3 + 50.0) * 0.08;

	vec3 col;
	if (v_biome < 0.5) {
		col = vec3(0.04, 0.22, 0.45);
		ALPHA = 0.9;
		METALLIC = 0.1;
		ROUGHNESS = 0.2;
		SPECULAR = 0.6;
	} else if (v_biome < 1.5) {
		col = vec3(0.1, 0.55, 0.7);
		ALPHA = 0.7;
		METALLIC = 0.1;
		ROUGHNESS = 0.25;
		SPECULAR = 0.5;
	} else if (v_biome < 2.5) {
		col = vec3(0.76, 0.7, 0.45);
		ROUGHNESS = 0.7;
	} else if (v_biome < 3.5) {
		col = vec3(0.3 + v, 0.65 + v, 0.15 + v);
		ROUGHNESS = 0.8;
	} else if (v_biome < 4.5) {
		col = vec3(0.15 + v, 0.42 + v, 0.1 + v);
		ROUGHNESS = 0.85;
	} else if (v_biome < 5.5) {
		col = vec3(0.7, 0.5, 0.2);
		ROUGHNESS = 0.75;
	} else if (v_biome < 6.5) {
		col = vec3(0.55 + v, 0.38 + v, 0.18 + v);
		ROUGHNESS = 0.8;
	} else if (v_biome < 7.5) {
		col = vec3(0.45 + v, 0.44 + v, 0.42 + v);
		ROUGHNESS = 0.65;
	} else if (v_biome < 8.5) {
		col = vec3(0.62 + v, 0.6 + v, 0.58 + v);
		ROUGHNESS = 0.5;
	} else {
		col = vec3(0.85 + v * 0.5, 0.85 + v * 0.5, 0.88 + v * 0.5);
		ROUGHNESS = 0.35;
	}

	float sdf = hex_grid_line(v_world_xz.xz, 1.1547);
	float line = 1.0 - smoothstep(0.0, grid_line_width, abs(sdf));
	col = mix(col, vec3(0.0), line * 0.7);

	ALBEDO = col;
}
