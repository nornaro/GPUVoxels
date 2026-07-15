#version 450

layout(local_size_x = 10, local_size_y = 10) in;

layout(set = 0, binding = 0, std430) readonly buffer Params {
	float chunk_size;
	float batch_size;
	float noise_freq;
	float noise_seed;
	float detail_freq;
	float detail_seed;
	float fractal_octaves;
	float fractal_lacunarity;
	float fractal_gain;
	float detail_octaves;
	float detail_lacunarity;
	float detail_gain;
	float _pad0;
	float _pad1;
	float _pad2;
	float _pad3;
};

layout(set = 0, binding = 1, std430) readonly buffer Origins {
	ivec2 chunk_origins[];
};

layout(set = 0, binding = 2, std430) writeonly buffer Output {
	float data[];
};

vec3 mod289v3(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289v2(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289v3(((x * 34.0) + 1.0) * x); }

float snoise(vec2 v) {
	const vec4 C = vec4(0.211324865405187, 0.366025403784439,
	                     -0.577350269189626, 0.024390243902439);
	vec2 i = floor(v + dot(v, C.yy));
	vec2 x0 = v - i + dot(i, C.xx);
	vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec4 x12 = x0.xyxy + C.xxzz;
	x12.xy -= i1;
	i = mod289v2(i);
	vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0))
		+ i.x + vec3(0.0, i1.x, 1.0));
	vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy),
		dot(x12.zw, x12.zw)), 0.0);
	m = m * m;
	m = m * m;
	vec3 x_ = 2.0 * fract(p * C.www) - 1.0;
	vec3 h = abs(x_) - 0.5;
	vec3 ox = floor(x_ + 0.5);
	vec3 a0 = x_ - ox;
	m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
	vec3 g;
	g.x = a0.x * x0.x + h.x * x0.y;
	g.yz = a0.yz * x12.xz + h.yz * x12.yw;
	return 130.0 * dot(m, g);
}

float fbm(vec2 pos, int seed, int octaves, float lacunarity, float gain) {
	float value = 0.0;
	float amplitude = 1.0;
	float frequency = 1.0;
	for (int i = 0; i < octaves; i++) {
		vec2 offset = vec2(float(seed + i * 7919) * 0.0137,
		                   float(seed + i * 6271) * 0.0253);
		value += snoise(pos * frequency + offset) * amplitude;
		frequency *= lacunarity;
		amplitude *= gain;
	}
	return value;
}

int elevation_to_biome(float e) {
	if (e < -0.5) return 0;
	if (e < -0.3) return 1;
	if (e < -0.15) return 2;
	if (e < 0.2) return 3;
	if (e < 0.4) return 4;
	return 5;
}

void main() {
	int ics = int(chunk_size);
	int ibs = int(batch_size);
	int chunk_id = int(gl_WorkGroupID.z);
	if (chunk_id >= ibs) return;

	ivec2 cell = ivec2(gl_LocalInvocationID.xy);
	if (cell.x >= ics || cell.y >= ics) return;

	ivec2 origin = chunk_origins[chunk_id] * ics;
	int q = origin.x + cell.x;
	int r = origin.y + cell.y;
	vec2 pos = vec2(float(q), float(r));

	float elevation = fbm(pos * noise_freq, int(noise_seed),
		int(fractal_octaves), fractal_lacunarity, fractal_gain);
	int biome = elevation_to_biome(elevation);

	float sub_heights[13];
	sub_heights[0] = round(elevation * 10.0) / 10.0;

	for (int i = 0; i < 6; i++) {
		float angle = radians(30.0 + 60.0 * float(i));
		vec2 sub_pos = pos + vec2(cos(angle), sin(angle)) * 0.57735026919;
		float detail = fbm(sub_pos * detail_freq, int(detail_seed),
			int(detail_octaves), detail_lacunarity, detail_gain) * 0.15;
		sub_heights[i + 1] = round((elevation + detail) * 10.0) / 10.0;
	}

	for (int i = 0; i < 6; i++) {
		float angle = radians(60.0 * float(i));
		vec2 sub_pos = pos + vec2(cos(angle), sin(angle)) * 1.0;
		float detail = fbm(sub_pos * detail_freq, int(detail_seed),
			int(detail_octaves), detail_lacunarity, detail_gain) * 0.15;
		sub_heights[i + 7] = round((elevation + detail) * 10.0) / 10.0;
	}

	float sum = 0.0;
	for (int i = 0; i < 13; i++) sum += sub_heights[i];
	elevation = round(sum / 13.0 * 10.0) / 10.0;

	int cells_per_chunk = ics * ics;
	int cell_idx = cell.x * ics + cell.y;
	int idx = (chunk_id * cells_per_chunk + cell_idx) * 15;
	data[idx] = elevation;
	data[idx + 1] = float(biome);
	for (int i = 0; i < 13; i++) {
		data[idx + 2 + i] = sub_heights[i];
	}
}
