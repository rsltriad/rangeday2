shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform float fov = 70.0;
uniform vec4 albedo : source_color = vec4(0.55, 0.72, 0.9, 0.16);
void vertex() {
	float scale = 1.0 / tan(fov * 0.5 * PI / 180.0);
	PROJECTION_MATRIX[0][0] = scale / (VIEWPORT_SIZE.x / VIEWPORT_SIZE.y);
	PROJECTION_MATRIX[1][1] = -scale;
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX.xyz, 1.0);
	POSITION.z = mix(POSITION.z, 0, -2);
}
void fragment() {
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a;
	ROUGHNESS = 0.05;
	METALLIC = 0.2;
}
