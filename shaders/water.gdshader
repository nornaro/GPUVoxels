shader_type spatial;

uniform vec4 shallow_color : source_color = vec4(0.15, 0.18, 0.22, 0.7);
uniform vec4 deep_color : source_color = vec4(0.05, 0.06, 0.08, 0.85);
uniform float wave_speed : hint_range(0.0, 2.0) = 0.4;
uniform float wave_strength : hint_range(0.0, 0.1) = 0.015;
uniform float foam_threshold : hint_range(0.0, 1.0) = 0.7;

varying float wave_offset;

void vertex() {
	float t = TIME * wave_speed;
	float wave1 = sin(VERTEX.x * 2.0 + t) * wave_strength;
	float wave2 = sin(VERTEX.z * 3.0 + t * 1.3) * wave_strength * 0.7;
	float wave3 = cos((VERTEX.x + VERTEX.z) * 1.5 + t * 0.8) * wave_strength * 0.5;
	VERTEX.y += wave1 + wave2 + wave3;
	wave_offset = (wave1 + wave2 + wave3) / (wave_strength * 2.2);

	vec3 bitangent = cross(TANGENT, NORMAL);
	TANGENT = normalize(TANGENT + vec3(wave_strength * 2.0 * cos(VERTEX.x * 2.0 + t), 0.0, wave_strength * 2.0 * sin(VERTEX.z * 3.0 + t * 1.3)));
	bitangent = normalize(bitangent + vec3(0.0, 0.0, wave_strength * 2.0 * cos((VERTEX.x + VERTEX.z) * 1.5 + t * 0.8)));
	NORMAL = normalize(cross(TANGENT, bitangent));
}

void fragment() {
	float fresnel = pow(1.0 - dot(NORMAL, VIEW), 3.0);
	vec4 col = mix(deep_color, shallow_color, fresnel);

	float foam = smoothstep(foam_threshold - 0.1, foam_threshold, wave_offset);
	col = mix(col, vec4(0.6, 0.65, 0.7, 0.9), foam * 0.3);

	ALBEDO = col.rgb;
	ALPHA = col.a;
	METALLIC = 0.1;
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
}
