shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// For now, using simple per-material colors
// The instance_data texture approach will be enabled later with GPU instancing

uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float select_highlight = 0.0;

uniform vec4 base_color : source_color = vec4(0.45, 0.65, 0.35, 1.0);
uniform float height_shade : hint_range(0.0, 1.0) = 0.15;
uniform vec4 select_color : source_color = vec4(1.0, 0.95, 0.3, 1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.75;

void fragment() {
	float height_factor = clamp(1.0 - (1.0 - UV.y) * height_shade, 0.5, 1.0);
	vec3 albedo = base_color.rgb * tint_color.rgb * height_factor;
	albedo = mix(albedo, select_color.rgb, select_highlight * 0.35);
	ALBEDO = albedo;
	ROUGHNESS = roughness_val;
	METALLIC = 0.0;
	SPECULAR = 0.2;
}
