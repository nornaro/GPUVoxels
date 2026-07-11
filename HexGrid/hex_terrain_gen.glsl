#[compute]
#version 450

layout(local_size_x = 64) in;

// Params buffer (binding 0) - all floats to match GDScript PackedFloat32Array
layout(set = 0, binding = 0, std430) readonly restrict buffer Params {
	float noise_seed;
	float noise_freq;
	float tile_count;
	float _pad;
} params;

// Input: tile coordinates packed as [q0, r0, s0, q1, r1, s1, ...]
layout(set = 0, binding = 1, std430) readonly restrict buffer InputCoords {
	int data[];
} input_buf;

// Output: [elevation0, type_index0, noise_val0, elevation1, ...]
layout(set = 0, binding = 2, std430) restrict buffer OutputData {
	float data[];
} output_buf;

// --- Simplex 2D noise (Ashima/webgl-noise, MIT) ---

vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289(((x * 34.0) + 1.0) * x); }

float snoise(vec2 v) {
	const vec4 C = vec4(
		0.211324865405187,   // (3.0-sqrt(3.0))/6.0
		0.366025403784439,   // 0.5*(sqrt(3.0)-1.0)
		-0.577350269189626,  // -1.0 + 2.0 * C.x
		0.024390243902439    // 1.0 / 41.0
	);
	vec2 i  = floor(v + dot(v, C.yy));
	vec2 x0 = v - i + dot(i, C.xx);
	vec2 i1;
	i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec4 x12 = x0.xyxy + C.xxzz;
	x12.xy -= i1;
	i = mod289(i);
	vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
	vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
	m = m * m;
	m = m * m;
	vec3 x = 2.0 * fract(p * C.www) - 1.0;
	vec3 h = abs(x) - 0.5;
	vec3 ox = floor(x + 0.5);
	vec3 a0 = x - ox;
	m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
	vec3 g;
	g.x = a0.x * x0.x + h.x * x0.y;
	g.yz = a0.yz * x12.xz + h.yz * x12.yw;
	return 130.0 * dot(m, g);
}

// --- Terrain classification (matches CPU fallback) ---

float remap(float value, float in_min, float in_max, float out_min, float out_max) {
	float t = clamp((value - in_min) / (in_max - in_min), 0.0, 1.0);
	return mix(out_min, out_max, t);
}

void main() {
	uint idx = gl_GlobalInvocationID.x;
	if (idx >= uint(params.tile_count)) return;

	int q = input_buf.data[idx * 3 + 0];
	int r = input_buf.data[idx * 3 + 1];

	// Seed offset: same approach as FastNoiseLite (seed offset per axis)
	float fx = float(q) * params.noise_freq;
	float fy = float(r) * params.noise_freq;
	// Apply seed as integer offset (matches FastNoiseLite behavior)
	fx += params.noise_seed * 0.1;
	fy += params.noise_seed * 0.1;

	float nval = snoise(vec2(fx, fy));

	// Classify terrain (must match CPU version exactly)
	int type_idx = 0;
	float elevation;

	if (nval < -0.2) {
		type_idx = 1;
		elevation = remap(nval, -1.0, -0.2, 0.15, 0.4);
	} else if (nval > 0.5) {
		type_idx = 2;
		elevation = remap(nval, 0.5, 1.0, 1.8, 4.0);
	} else if (nval > 0.25) {
		type_idx = 3;
		elevation = remap(nval, 0.25, 0.5, 1.0, 1.8);
	} else {
		type_idx = 0;
		elevation = remap(nval, -0.2, 0.25, 0.6, 1.2);
	}

	output_buf.data[idx * 3 + 0] = elevation;
	output_buf.data[idx * 3 + 1] = float(type_idx);
	output_buf.data[idx * 3 + 2] = nval;
}
