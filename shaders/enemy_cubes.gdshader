shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D pos_texture : filter_nearest, repeat_disable;
uniform int tex_width = 256;

const vec3 COLOR_RED    = vec3(0.85, 0.25, 0.20);
const vec3 COLOR_ORANGE = vec3(0.90, 0.60, 0.15);
const vec3 COLOR_GREEN  = vec3(0.30, 0.70, 0.25);
const vec3 COLOR_BLUE   = vec3(0.25, 0.45, 0.80);

varying float v_id_color;

void vertex() {
	int iid = INSTANCE_ID;
	ivec2 coord = ivec2(iid % tex_width, iid / tex_width);
	vec4 data = texelFetch(pos_texture, coord, 0);

	if (data.y < -100.0) {
		VERTEX = vec3(0.0);
		v_id_color = 0.0;
	} else {
		VERTEX = data.xyz + VERTEX;
		v_id_color = data.w;
	}
}

void fragment() {
	float ci = floor(v_id_color + 0.5);
	vec3 col;
	if (ci < 0.5) {
		col = COLOR_RED;
	} else if (ci < 1.5) {
		col = COLOR_ORANGE;
	} else if (ci < 2.5) {
		col = COLOR_GREEN;
	} else {
		col = COLOR_BLUE;
	}
	ALBEDO = col;
	METALLIC = 0.1;
	ROUGHNESS = 0.8;
}
