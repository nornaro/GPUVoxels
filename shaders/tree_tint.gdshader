shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley;

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap;
uniform int season : hint_range(0, 3) = 1;
uniform bool is_evergreen = false;

varying vec3 world_pos;

float hash(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x),
			mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
			mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y),
		f.z
	);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * noise3d(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec3 base_albedo = tex.rgb;
	float n = fbm(world_pos * 2.5);
	float n2 = fbm(world_pos * 4.0 + 100.0);
	float height_factor = clamp(world_pos.y * 0.6, 0.0, 1.0);
	vec3 result = base_albedo;

	if (is_evergreen) {
		if (season == 0) {
			result = base_albedo * vec3(0.35, 0.95, 0.4);
		} else if (season == 1) {
			result = base_albedo * vec3(0.25, 0.85, 0.3);
		} else if (season == 2) {
			result = base_albedo * vec3(0.4, 0.8, 0.35);
		} else {
			vec3 green = base_albedo * vec3(0.4, 0.8, 0.45);
			vec3 snow = vec3(0.92, 0.95, 0.98);
			float snow_mask = smoothstep(0.4, 0.8, height_factor) * smoothstep(0.35, 0.65, n);
			result = mix(green, snow, snow_mask * 0.7);
			float snow_spots = smoothstep(0.55, 0.7, n2) * smoothstep(0.3, 0.6, height_factor);
			result = mix(result, snow, snow_spots * 0.4);
		}
	} else {
		if (season == 0) {
			vec3 leaf = base_albedo * vec3(0.5, 1.1, 0.45);
			vec3 flower = vec3(1.0, 0.75, 0.85);
			vec3 flower2 = vec3(0.95, 0.6, 0.9);
			float flower_mask = smoothstep(0.5, 0.7, n) * smoothstep(0.4, 0.7, height_factor);
			result = mix(leaf, mix(flower, flower2, n2), flower_mask * 0.7);
		} else if (season == 1) {
			vec3 leaf = base_albedo * vec3(0.2, 0.8, 0.22);
			vec3 fruit = vec3(0.95, 0.25, 0.15);
			vec3 fruit2 = vec3(1.0, 0.6, 0.1);
			float fruit_mask = smoothstep(0.6, 0.75, n) * smoothstep(0.2, 0.5, height_factor);
			result = mix(leaf, mix(fruit, fruit2, n2), fruit_mask * 0.8);
		} else if (season == 2) {
			vec3 green = base_albedo * vec3(0.55, 0.8, 0.15);
			vec3 yellow = vec3(0.95, 0.8, 0.15);
			vec3 orange = vec3(0.95, 0.5, 0.1);
			vec3 red = vec3(0.85, 0.2, 0.12);
			float t = n * 0.7 + n2 * 0.3;
			vec3 autumn = mix(mix(green, yellow, smoothstep(0.2, 0.45, t)),
							  mix(orange, red, smoothstep(0.55, 0.8, t)),
							  smoothstep(0.45, 0.55, t));
			float leaf_drop = smoothstep(0.0, 0.3, height_factor) * n2;
			result = mix(autumn, base_albedo * vec3(0.5, 0.35, 0.2), leaf_drop * 0.4);
		} else {
			vec3 bare = base_albedo * vec3(0.55, 0.4, 0.28);
			vec3 snow = vec3(0.92, 0.95, 0.98);
			float snow_mask = smoothstep(0.5, 0.85, height_factor) * smoothstep(0.3, 0.6, n);
			result = mix(bare, snow, snow_mask * 0.8);
			float snow_patches = smoothstep(0.5, 0.65, n2) * smoothstep(0.2, 0.5, height_factor);
			result = mix(result, snow, snow_patches * 0.5);
		}
	}

	ALBEDO = result;
}
