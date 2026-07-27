shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float noise_freq : hint_range(0.001, 0.1) = 0.008;
uniform float noise_seed = 42.0;
uniform int noise_octaves : hint_range(1, 8) = 6;
uniform float noise_lacunarity = 2.0;
uniform float noise_gain = 0.5;
uniform float water_level = 0.32;
uniform float grid_line_width : hint_range(0.0, 0.5) = 0.08;
uniform float height_step : hint_range(0.0, 50.0, 0.1) = 5.0;
uniform float height_exp : hint_range(0.1, 5.0, 0.1) = 1.0;

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
	float e_norm = CUSTOM0.r;
	v_biome = CUSTOM0.g * 10.0;
	v_elevation = e_norm;

	float h;
	if (v_biome < 1.5) {
		h = water_level * height_step;
	} else {
		h = pow(max(e_norm, 0.001), height_exp) * height_step;
		h = max(h, water_level * height_step + 0.001);
	}

	VERTEX.y = h;

	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	v_world_xz = vec3(wp.x, 0.0, wp.z);
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
		col = vec3(0.45 + v, 0.35 + v, 0.18 + v);
		ROUGHNESS = 0.85;
	} else {
		float snow = smoothstep(0.65, 1.0, v_elevation);
		col = mix(vec3(0.55 + v, 0.55 + v, 0.58 + v), vec3(0.95), snow);
		ROUGHNESS = mix(0.7, 0.35, snow);
	}

	float sdf = hex_grid_line(v_world_xz.xz, 1.1547);
	float line = 1.0 - smoothstep(0.0, grid_line_width, abs(sdf));
	col = mix(col, vec3(0.0), line * 0.7);

	ALBEDO = col;
}
