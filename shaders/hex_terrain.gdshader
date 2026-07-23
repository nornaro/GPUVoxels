shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform bool show_grid = false;
uniform float grid_line_width : hint_range(0.001, 0.1) = 0.04;
uniform vec4 shallow_color : source_color = vec4(0.15, 0.75, 0.85, 0.55);
uniform vec4 deep_color : source_color = vec4(0.04, 0.28, 0.45, 0.92);
uniform float wave_speed : hint_range(0.0, 5.0) = 0.8;
uniform float wave_strength : hint_range(0.0, 0.1) = 0.008;
uniform bool unshaded_mode = false;

varying vec3 v_local_pos;
varying vec3 v_world_pos;
varying vec4 v_custom_data;

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

float sd_hex(vec2 p, float r) {
	const vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
	p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
	p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

void vertex() {
	v_local_pos = VERTEX;
	v_custom_data = INSTANCE_CUSTOM;
	float is_water = INSTANCE_CUSTOM.r;

	if (is_water > 0.5) {
		v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float t = TIME * wave_speed;
		float w1 = sin(v_world_pos.x * 2.5 + t * 1.2) * wave_strength;
		float w2 = sin(v_world_pos.z * 3.0 + t * 0.9) * wave_strength * 0.7;
		float w3 = cos((v_world_pos.x + v_world_pos.z) * 1.8 + t * 0.6) * wave_strength * 0.5;
		float w4 = sin(v_world_pos.x * 5.0 - v_world_pos.z * 4.0 + t * 1.8) * wave_strength * 0.3;
		VERTEX.y += w1 + w2 + w3 + w4;
	} else {
		v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	}
}

void fragment() {
	float is_water = v_custom_data.r;
	float water_depth = v_custom_data.g;

	if (is_water > 0.5) {
		float t = TIME * 0.5;
		float s1 = noise(v_world_pos.xz * 8.0 + t * 0.6);
		float s2 = noise(v_world_pos.xz * 16.0 - t * 0.9);
		float shimmer = pow(s1 * 0.6 + s2 * 0.4, 4.0);
		ALBEDO = mix(shallow_color.rgb, deep_color.rgb, water_depth);
		ALBEDO += vec3(0.18, 0.3, 0.25) * shimmer;
		ALPHA = mix(shallow_color.a, deep_color.a, water_depth);
		METALLIC = 0.1;
		ROUGHNESS = 0.2;
		SPECULAR = 0.6;
	} else {
		ALBEDO = COLOR.rgb;
		ALPHA = 1.0;
	}

	if (show_grid && v_local_pos.y > 0.4) {
		float d = sd_hex(vec2(v_local_pos.x, v_local_pos.z), 0.866);
		if (abs(d) < grid_line_width) {
			ALBEDO *= 0.35;
		}
	}

	if (unshaded_mode) {
		EMISSION = ALBEDO;
	}
}
