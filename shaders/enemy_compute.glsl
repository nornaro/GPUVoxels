#[compute]
#version 450

layout(local_size_x = 256) in;

layout(set = 0, binding = 0, std430) buffer EnemyData {
	float data[];
} enemy;

layout(set = 0, binding = 1, std430) buffer PathData {
	float data[];
} path;

layout(set = 0, binding = 2, rgba32f) uniform writeonly image2D pos_image;

layout(push_constant) uniform Params {
	float delta;
	float count_f;
	float tex_width_f;
	float _pad;
};

const int E_STRIDE = 16;

int eidx(int i, int offset) {
	return i * E_STRIDE + offset;
}

void main() {
	int i = int(gl_GlobalInvocationID.x);
	int count = int(count_f);
	int tex_width = int(tex_width_f);
	if (i >= count) return;

	int dead_off = eidx(i, 5);
	if (enemy.data[dead_off] > 0.5) {
		ivec2 coord = ivec2(i % tex_width, i / tex_width);
		imageStore(pos_image, coord, vec4(0.0, -999.0, 0.0, 0.0));
		return;
	}

	int lt_off = eidx(i, 11);
	float t = enemy.data[lt_off];
	t += delta / max(enemy.data[eidx(i, 1)], 0.001);

	if (t >= 1.0) {
		t -= 1.0;
		int idx = int(enemy.data[eidx(i, 2)]) + 1;
		int plen = int(enemy.data[eidx(i, 4)]);

		if (idx >= plen - 1) {
			enemy.data[dead_off] = 1.0;
			ivec2 coord = ivec2(i % tex_width, i / tex_width);
			imageStore(pos_image, coord, vec4(
				enemy.data[eidx(i, 12)],
				enemy.data[eidx(i, 13)],
				enemy.data[eidx(i, 14)],
				enemy.data[eidx(i, 15)]
			));
			return;
		}

		enemy.data[eidx(i, 2)] = float(idx);

		enemy.data[eidx(i, 8)]  = enemy.data[eidx(i, 12)];
		enemy.data[eidx(i, 9)]  = enemy.data[eidx(i, 13)];
		enemy.data[eidx(i, 10)] = enemy.data[eidx(i, 14)];

		int poff = int(enemy.data[eidx(i, 3)]);
		int next = idx + 1;
		enemy.data[eidx(i, 12)] = path.data[(poff + next) * 3 + 0];
		enemy.data[eidx(i, 13)] = path.data[(poff + next) * 3 + 1];
		enemy.data[eidx(i, 14)] = path.data[(poff + next) * 3 + 2];
	}

	enemy.data[lt_off] = t;

	float fx = enemy.data[eidx(i, 8)];
	float fy = enemy.data[eidx(i, 9)];
	float fz = enemy.data[eidx(i, 10)];
	float tx = enemy.data[eidx(i, 12)];
	float ty = enemy.data[eidx(i, 13)];
	float tz = enemy.data[eidx(i, 14)];

	float px = fx + (tx - fx) * t;
	float py = fy + (ty - fy) * t;
	float pz = fz + (tz - fz) * t;
	float ci = enemy.data[eidx(i, 15)];

	ivec2 coord = ivec2(i % tex_width, i / tex_width);
	imageStore(pos_image, coord, vec4(px, py, pz, ci));
}
