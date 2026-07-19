shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley;

uniform sampler2D albedo_texture : source_color;

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb * COLOR.rgb;
	ALPHA = tex.a * COLOR.a;
}
