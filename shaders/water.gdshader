shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.12, 0.15, 0.18, 0.75);
uniform vec4 deep_color : source_color = vec4(0.03, 0.04, 0.05, 0.92);
uniform float wave_speed : hint_range(0.0, 3.0) = 0.6;
uniform float wave_strength : hint_range(0.0, 0.05) = 0.008;

varying float v_depth_factor;
varying vec3 v_world_pos;

void vertex() {
	float t = TIME * wave_speed;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	float wave1 = sin(VERTEX.x * 1.8 + t * 1.0) * wave_strength;
	float wave2 = sin(VERTEX.z * 2.2 + t * 0.7) * wave_strength * 0.6;
	float wave3 = cos((VERTEX.x + VERTEX.z) * 1.2 + t * 0.5) * wave_strength * 0.4;
	float wave4 = sin(VERTEX.x * 4.0 - VERTEX.z * 3.0 + t * 1.5) * wave_strength * 0.2;
	float total_wave = wave1 + wave2 + wave3 + wave4;
	VERTEX.y += total_wave;

	float dx = wave_strength * 1.8 * cos(VERTEX.x * 1.8 + t * 1.0)
	         + wave_strength * 0.4 * cos((VERTEX.x + VERTEX.z) * 1.2 + t * 0.5)
	         - wave_strength * 0.4 * sin(VERTEX.x * 4.0 - VERTEX.z * 3.0 + t * 1.5);
	float dz = wave_strength * 2.2 * cos(VERTEX.z * 2.2 + t * 0.7)
	         + wave_strength * 0.4 * cos((VERTEX.x + VERTEX.z) * 1.2 + t * 0.5)
	         + wave_strength * 0.6 * cos(VERTEX.x * 4.0 - VERTEX.z * 3.0 + t * 1.5);
	NORMAL = normalize(vec3(-dx, 1.0, -dz));
}

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float fresnel = pow(1.0 - max(dot(normalize(NORMAL), view_dir), 0.0), 4.0);
	fresnel = clamp(fresnel, 0.0, 1.0);

	vec4 col = mix(deep_color, shallow_color, fresnel * 0.6 + 0.2);

	float t = TIME * 0.15;
	float sparkle = pow(max(sin(v_world_pos.x * 12.0 + t * 2.0) * sin(v_world_pos.z * 10.0 + t * 1.5), 0.0), 16.0);
	col.rgb += vec3(sparkle * 0.12);

	ALBEDO = col.rgb;
	ALPHA = col.a;
	METALLIC = 0.2;
	ROUGHNESS = 0.1;
	SPECULAR = 0.8;
}
