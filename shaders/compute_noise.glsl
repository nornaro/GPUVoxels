#[compute]
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
	float warp_strength;
	float moisture_freq;
	float moisture_seed;
	float _pad0;
};

layout(set = 0, binding = 1, std430) readonly buffer Origins {
	ivec2 chunk_origins[];
};

layout(set = 0, binding = 2, std430) writeonly buffer Output {
	float data[];
};

uint ihash(uint n) {
	n = (n << 13u) ^ n;
	return (n * (n * n * 15731u + 789221u) + 1376312589u) & 0x7FFFFFFFu;
}

vec2 hash2(vec2 p, float seed) {
	ivec2 ip = ivec2(floor(p));
	uint seed_bits = uint(seed * 43758.5453);
	uint ix = uint(ip.x) + seed_bits;
	uint iy = uint(ip.y) + seed_bits;
	uint h1 = ihash(ihash(iy + 127u) + ix);
	uint h2 = ihash(iy + ihash(ix + 311u));
	return vec2(float(h1 & 0xFFFFu) / 32767.5 - 1.0,
	            float(h2 & 0xFFFFu) / 32767.5 - 1.0);
}

float perlin_noise(vec2 p, float seed) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);

	float a = dot(hash2(i + vec2(0.0, 0.0), seed), f - vec2(0.0, 0.0));
	float b = dot(hash2(i + vec2(1.0, 0.0), seed), f - vec2(1.0, 0.0));
	float c = dot(hash2(i + vec2(0.0, 1.0), seed), f - vec2(0.0, 1.0));
	float d = dot(hash2(i + vec2(1.0, 1.0), seed), f - vec2(1.0, 1.0));

	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 pos, float seed, int octaves, float lacunarity, float gain) {
	float value = 0.0;
	float amplitude = 1.0;
	float frequency = 1.0;
	for (int i = 0; i < octaves; i++) {
		float n = perlin_noise(pos * frequency + vec2(float(i) * 31.7, float(i) * 47.3) * seed * 0.001, seed + float(i) * 17.0);
		value += n * amplitude;
		frequency *= lacunarity;
		amplitude *= gain;
	}
	return value;
}

void main() {
	int ics = int(chunk_size);
	int ibs = int(batch_size);
	int chunk_id = int(gl_WorkGroupID.z);
	if (chunk_id >= ibs) return;

	ivec2 cell = ivec2(gl_LocalInvocationID.xy);
	if (cell.x >= ics || cell.y >= ics) return;

	ivec2 origin = chunk_origins[chunk_id] * ics;
	float q = float(origin.x + cell.x);
	float r = float(origin.y + cell.y);

	vec2 pos = vec2(q, r) * noise_freq;
	float seed = noise_seed;

	vec2 q_warp = vec2(
		fbm(pos + vec2(0.0, 0.0), seed + 100.0, 3, 2.0, 0.5),
		fbm(pos + vec2(5.2, 1.3), seed + 200.0, 3, 2.0, 0.5)
	);
	vec2 warped = pos + warp_strength * q_warp;

	float elevation = fbm(warped, seed, int(fractal_octaves), fractal_lacunarity, fractal_gain);

	float detail = fbm(pos * (detail_freq / noise_freq), seed + 500.0,
		int(detail_octaves), detail_lacunarity, detail_gain);
	elevation = elevation + detail * 0.3;

	float moisture = fbm(vec2(q, r) * moisture_freq, moisture_seed,
		4, 2.0, 0.5);

	elevation = elevation * 0.5 + 0.5;
	elevation = clamp(elevation, 0.0, 1.0);
	moisture = moisture * 0.5 + 0.5;
	moisture = clamp(moisture, 0.0, 1.0);

	float sub_heights[13];
	sub_heights[0] = elevation;

	const float HEX_SIZE = 1.1547;
	const float INNER_DIST = HEX_SIZE * 0.57735026919;
	const float OUTER_DIST = HEX_SIZE;

	for (int i = 0; i < 6; i++) {
		float angle = radians(30.0 + 60.0 * float(i));
		float sub_q = q + cos(angle) * INNER_DIST;
		float sub_r = r + sin(angle) * INNER_DIST;
		vec2 sub_pos = vec2(sub_q, sub_r) * noise_freq;
		float sub_e = perlin_noise(sub_pos + warp_strength * vec2(
			perlin_noise(sub_pos + vec2(0.0, 0.0), seed + 100.0),
			perlin_noise(sub_pos + vec2(5.2, 1.3), seed + 200.0)
		), seed);
		float sub_d = perlin_noise(sub_pos * (detail_freq / noise_freq), seed + 500.0);
		sub_heights[i + 1] = clamp((sub_e + sub_d * 0.3) * 0.5 + 0.5, 0.0, 1.0);
	}

	for (int i = 0; i < 6; i++) {
		float angle = radians(60.0 * float(i));
		float sub_q = q + cos(angle) * OUTER_DIST;
		float sub_r = r + sin(angle) * OUTER_DIST;
		vec2 sub_pos = vec2(sub_q, sub_r) * noise_freq;
		float sub_e = perlin_noise(sub_pos + warp_strength * vec2(
			perlin_noise(sub_pos + vec2(0.0, 0.0), seed + 100.0),
			perlin_noise(sub_pos + vec2(5.2, 1.3), seed + 200.0)
		), seed);
		float sub_d = perlin_noise(sub_pos * (detail_freq / noise_freq), seed + 500.0);
		sub_heights[i + 7] = clamp((sub_e + sub_d * 0.3) * 0.5 + 0.5, 0.0, 1.0);
	}

	int cells_per_chunk = ics * ics;
	int cell_idx = cell.x * ics + cell.y;
	int idx = (chunk_id * cells_per_chunk + cell_idx) * 15;
	data[idx] = elevation;
	data[idx + 1] = moisture;
	for (int i = 0; i < 13; i++) {
		data[idx + 2 + i] = sub_heights[i];
	}
}
