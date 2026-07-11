shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// --- Tile color (simple, seamless, world-space) ---
uniform vec4 base_color : source_color = vec4(0.45, 0.65, 0.35, 1.0);
uniform sampler2D detail_noise : filter_linear, repeat_enable;
uniform float detail_tiling : hint_range(0.1, 20.0) = 4.0;

uniform vec4 color_grass : source_color = vec4(0.35, 0.62, 0.28, 1.0);
uniform vec4 color_dirt : source_color = vec4(0.55, 0.4, 0.25, 1.0);
uniform vec4 color_stone : source_color = vec4(0.55, 0.53, 0.5, 1.0);
uniform vec4 color_sand : source_color = vec4(0.76, 0.7, 0.5, 1.0);
uniform vec4 color_water : source_color = vec4(0.2, 0.4, 0.75, 1.0);

uniform float tile_type : hint_range(0.0, 4.0) = 0.0;

// --- Terrain depth layer (continuous across map, world-space only) ---
uniform sampler2D normal_map : filter_linear, repeat_enable;
uniform float normal_strength : hint_range(0.0, 4.0) = 0.4;
uniform float normal_tiling : hint_range(0.1, 20.0) = 3.0;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.75;
uniform float flat_mode : hint_range(0.0, 1.0) = 0.0;

// --- Selection ---
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float select_highlight = 0.0;
uniform vec4 select_color : source_color = vec4(1.0, 0.95, 0.3, 1.0);

vec3 procedural_normal(vec2 uv, float strength) {
	vec2 ps = vec2(1.0 / 256.0);
	float h0 = texture(detail_noise, uv).r;
	float hx = texture(detail_noise, uv + vec2(ps.x, 0.0)).r;
	float hy = texture(detail_noise, uv + vec2(0.0, ps.y)).r;
	vec3 n = normalize(vec3((h0 - hx) * strength, 1.0, (h0 - hy) * strength));
	return n;
}

void fragment() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 tiled_uv = world_pos.xz;

	// --- Color: simple seamless, world-space ---
	float detail = texture(detail_noise, tiled_uv * detail_tiling).r;
	float detail2 = texture(detail_noise, tiled_uv * detail_tiling * 0.5 + vec2(17.3, 31.7)).r;

	vec3 terrain_col;

	if (tile_type < 0.5) {
		terrain_col = mix(color_grass.rgb, color_dirt.rgb, smoothstep(0.1, 0.5, detail) * 0.3);
		terrain_col = mix(terrain_col, color_sand.rgb, smoothstep(0.3, 0.6, detail2) * 0.15);
	} else if (tile_type < 1.5) {
		terrain_col = color_water.rgb;
		terrain_col += vec3(0.02) * sin(world_pos.x * 2.0 + world_pos.z * 1.5);
	} else if (tile_type < 2.5) {
		terrain_col = mix(color_stone.rgb, color_dirt.rgb, smoothstep(0.0, 0.4, detail) * 0.25);
		terrain_col *= 0.9 + detail2 * 0.2;
	} else if (tile_type < 3.5) {
		terrain_col = mix(color_dirt.rgb, color_grass.rgb, smoothstep(0.2, 0.6, detail) * 0.2);
		terrain_col = mix(terrain_col, color_sand.rgb, smoothstep(0.3, 0.7, detail2) * 0.15);
	} else {
		terrain_col = mix(color_sand.rgb, color_dirt.rgb, smoothstep(0.1, 0.5, detail) * 0.2);
		terrain_col *= 0.95 + detail2 * 0.1;
	}

	terrain_col *= tint_color.rgb;
	terrain_col = mix(terrain_col, select_color.rgb, select_highlight * 0.35);

	ALBEDO = terrain_col;

	// --- Normal + roughness layer: world-space, seamless across all tiles ---
	float detail3 = texture(detail_noise, tiled_uv * detail_tiling * 1.5 + vec2(53.1, 11.9)).r;
	float detail4 = texture(detail_noise, tiled_uv * detail_tiling * 3.0 + vec2(91.7, 67.3)).r;

	vec2 normal_uv = tiled_uv * normal_tiling;
	vec3 n_from_map = texture(normal_map, normal_uv).rgb * 2.0 - 1.0;

	float proc_str = mix(normal_strength * 40.0, normal_strength * 80.0, flat_mode);
	vec3 n_procedural = procedural_normal(tiled_uv * detail_tiling * 0.7, proc_str);

	vec3 final_normal = mix(n_from_map, n_procedural, 0.3);
	final_normal = normalize(final_normal);
	final_normal.xy *= mix(normal_strength, normal_strength * 2.5, flat_mode);
	final_normal = normalize(final_normal);

	float rough_var = detail * 0.15 + detail2 * 0.1;
	float flat_rough = detail3 * 0.15 + detail4 * 0.1;

	NORMAL = final_normal;
	ROUGHNESS = clamp(roughness_base + rough_var + flat_rough * flat_mode, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.2;
}
