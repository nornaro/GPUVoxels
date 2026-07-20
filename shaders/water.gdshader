shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

uniform vec4 shallow_color : source_color = vec4(0.14, 0.18, 0.22, 0.72);
uniform vec4 deep_color : source_color = vec4(0.03, 0.04, 0.06, 0.92);
uniform vec4 foam_color : source_color = vec4(0.55, 0.6, 0.65, 0.85);
uniform float wave_speed : hint_range(0.0, 3.0) = 0.5;
uniform float wave_strength : hint_range(0.0, 0.05) = 0.006;
uniform float shore_foam_width : hint_range(0.0, 1.0) = 0.15;
uniform float max_depth : hint_range(0.1, 5.0) = 1.5;

varying float v_water_depth;
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
	float depth_raw = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec3 worldBehind = upos.xyz / upos.w;

	float water_surface_y = v_world_pos.y;
	float thickness = max(water_surface_y - worldBehind.y, 0.0);
	float depth_ratio = clamp(thickness / max_depth, 0.0, 1.0);

	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float fresnel = pow(1.0 - max(dot(normalize(NORMAL), view_dir), 0.0), 4.0);
	fresnel = clamp(fresnel, 0.0, 1.0);

	vec4 col = mix(deep_color, shallow_color, (1.0 - depth_ratio) * 0.7 + fresnel * 0.3);

	vec3 screen_color = textureLod(screen_texture, SCREEN_UV, depth_ratio * 2.0).rgb;
	col.rgb = mix(screen_color * col.rgb, col.rgb, depth_ratio * 0.6 + 0.15);

	float shore_edge = 1.0 - smoothstep(0.0, shore_foam_width, thickness);
	float t = TIME * 0.3;
	float shore_noise = sin(v_world_pos.x * 8.0 + t * 2.0) * sin(v_world_pos.z * 7.0 + t * 1.5) * 0.5 + 0.5;
	float foam_mask = shore_edge * shore_noise;
	col.rgb = mix(col.rgb, foam_color.rgb, foam_mask * foam_color.a);

	float sparkle = pow(max(sin(v_world_pos.x * 15.0 + t * 3.0) * sin(v_world_pos.z * 13.0 + t * 2.0), 0.0), 20.0);
	col.rgb += vec3(sparkle * 0.08 * (1.0 - depth_ratio));

	ALBEDO = col.rgb;
	ALPHA = col.a;
	METALLIC = 0.15;
	ROUGHNESS = 0.12;
	SPECULAR = 0.7;
}
