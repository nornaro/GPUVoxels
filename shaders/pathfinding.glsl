#[compute]
#version 450

layout(local_size_x = 1) in;

layout(set = 0, binding = 0, std430) buffer Params {
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
	float height_step;
	float height_exp;
	float grid_radius;
};

layout(set = 0, binding = 1, std430) buffer Request {
	int data[4]; // q, r, slot, status (0=free, 1=pending, 2=done)
} request;

layout(set = 0, binding = 2, std430) buffer Result {
	int data[361]; // path_length + 120 * 3 hex coords
} result;

const int MAX_STEPS = 120;
const int SEARCH_RAD = 2;
const int TARGET_RAD = 2;
const float WATER_LINE = 0.25;
const float BEACH_LINE = 0.35;
const float SNOW_LINE = 0.72;

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
	float freq = 1.0;
	for (int i = 0; i < 8; i++) {
		if (i >= octaves) break;
		float n = perlin_noise(pos * freq + vec2(float(i) * 31.7, float(i) * 47.3) * seed * 0.001, seed + float(i) * 17.0);
		value += n * amplitude;
		freq *= lacunarity;
		amplitude *= gain;
	}
	return value;
}

float compute_elevation(float q, float r, float seed, float freq) {
	vec2 pos = vec2(q, r) * freq;
	vec2 q_warp = vec2(
		fbm(pos + vec2(0.0, 0.0), seed + 100.0, 3, 2.0, 0.5),
		fbm(pos + vec2(5.2, 1.3), seed + 200.0, 3, 2.0, 0.5)
	);
	vec2 warped = pos + warp_strength * q_warp;
	float elevation = fbm(warped, seed, int(fractal_octaves), fractal_lacunarity, fractal_gain);
	float detail = fbm(pos * (detail_freq / noise_freq), seed + 500.0,
		int(detail_octaves), detail_lacunarity, detail_gain);
	elevation = (elevation + detail * 0.3) * 0.5 + 0.5;
	return clamp(elevation, 0.0, 1.0);
}

float compute_moisture(float q, float r, float seed, float freq) {
	vec2 pos = vec2(q, r) * freq;
	float m = fbm(pos, seed, 4, 2.0, 0.5);
	return clamp(m * 0.5 + 0.5, 0.0, 1.0);
}

int get_biome(float elevation, float moisture) {
	if (elevation < WATER_LINE) return 0;
	if (elevation < BEACH_LINE) return 1;
	if (elevation > SNOW_LINE) return 5;
	if (moisture < 0.25) return 2;
	if (moisture < 0.55) return 3;
	return 4;
}

float get_height(float elevation) {
	return pow(max(height_step * elevation, 0.001), height_exp);
}

int cube_max(ivec3 c) {
	int ax = abs(c.x);
	int ay = abs(c.y);
	int az = abs(c.z);
	return max(max(ax, ay), az);
}

uint hash_int(int v) {
	uint n = uint(v);
	n = (n << 13u) ^ n;
	n = (n * (n * n * 15731u + 789221u) + 1376312589u) & 0x7FFFFFFFu;
	return n;
}

float hash_float(int v) {
	return float(hash_int(v)) / 2147483647.0;
}

void main() {
	int status = request.data[3];
	if (status != 1) return;

	int q0 = request.data[0];
	int r0 = request.data[1];
	int slot = request.data[2];
	int s0 = -q0 - r0;

	int radius = int(grid_radius + 0.5);
	float seed = noise_seed;
	float freq = noise_freq;

	ivec3 current = ivec3(q0, r0, s0);
	bool on_land = false;
	int path_len = 0;

	int result_offset = 0;
	result.data[result_offset] = 0;

	int candidates_x[25];
	int candidates_y[25];
	int candidates_z[25];

	for (int step = 0; step < MAX_STEPS; step++) {
		int cd = cube_max(current);
		if (cd <= TARGET_RAD) {
			result.data[result_offset] = path_len + 1;
			path_len++;
			break;
		}

		int cand_count = 0;
		int best_dist = cd;

		for (int dq = -SEARCH_RAD; dq <= SEARCH_RAD; dq++) {
			for (int dr = -SEARCH_RAD; dr <= SEARCH_RAD; dr++) {
				int ds = -dq - dr;
				if (cube_max(ivec3(dq, dr, ds)) > SEARCH_RAD) continue;
				if (dq == 0 && dr == 0) continue;

				ivec3 cand = current + ivec3(dq, dr, ds);
				int c_dist = cube_max(cand);
				if (c_dist > best_dist) continue;
				if (c_dist > radius) continue;

				float elev = compute_elevation(float(cand.x), float(cand.y), seed, freq);
				float moist = compute_moisture(float(cand.x), float(cand.y), moisture_seed, moisture_freq);
				int biome = get_biome(elev, moist);
				if (on_land && (biome == 0 || biome == 1)) continue;

				if (c_dist < best_dist) {
					cand_count = 0;
					best_dist = c_dist;
				}
				candidates_x[cand_count] = cand.x;
				candidates_y[cand_count] = cand.y;
				candidates_z[cand_count] = cand.z;
				cand_count++;
			}
		}

		if (cand_count == 0) break;

		uint rnd = hash_int(current.x * 73856093 + current.y * 19349663 + current.z * 83492791);
		int pick_idx = int(rnd % uint(cand_count));
		ivec3 pick = ivec3(
			candidates_x[pick_idx],
			candidates_y[pick_idx],
			candidates_z[pick_idx]
		);

		if (!on_land) {
			float pe = compute_elevation(float(pick.x), float(pick.y), seed, freq);
			float pm = compute_moisture(float(pick.x), float(pick.y), moisture_seed, moisture_freq);
			int pb = get_biome(pe, pm);
			if (pb != 0) on_land = true;
		}

		current = pick;
		result.data[result_offset + path_len * 3 + 1] = current.x;
		result.data[result_offset + path_len * 3 + 2] = current.y;
		result.data[result_offset + path_len * 3 + 3] = current.z;
		path_len++;
	}

	result.data[result_offset] = path_len;
	request.data[3] = 2;
}
