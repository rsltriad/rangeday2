shader_type spatial;
// Red dot reticle: the dot is drawn exactly where the camera's centre ray crosses
// the glass plane, so it always sits on the crosshair / bullet path (parallax-free).
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 dot_color : source_color = vec4(1.0, 0.12, 0.08, 1.0);
uniform float aperture_radius = 0.0086; // local units (metres at scale 1)
uniform float dot_radius = 0.0011;
uniform float intensity = 2.2;
uniform float fov = 70.0; // must match the weapon viewmodel shader

varying vec3 local_pos;
varying vec3 cam_local;
varying vec3 fwd_local;

void vertex() {
	local_pos = VERTEX;
	mat4 inv_model = inverse(MODEL_MATRIX);
	cam_local = (inv_model * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
	vec3 fwd_world = -INV_VIEW_MATRIX[2].xyz;
	fwd_local = normalize((inv_model * vec4(fwd_world, 0.0)).xyz);
	// Fixed-FOV viewmodel projection (same as addons/fps-hands/shader.gdshader).
	float scale = 1.0 / tan(fov * 0.5 * PI / 180.0);
	PROJECTION_MATRIX[0][0] = scale / (VIEWPORT_SIZE.x / VIEWPORT_SIZE.y);
	PROJECTION_MATRIX[1][1] = -scale;
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX.xyz, 1.0);
	POSITION.z = mix(POSITION.z, 0, -2);
}

void fragment() {
	float a = 0.0;
	if (abs(fwd_local.z) > 0.05) {
		float t = -cam_local.z / fwd_local.z;
		vec2 hit = (cam_local + fwd_local * t).xy;  // where the view axis pierces the glass
		float r = length(local_pos.xy - hit);
		float core = 1.0 - smoothstep(dot_radius * 0.55, dot_radius, r);
		float glow = exp(-(r * r) / (dot_radius * dot_radius * 6.0)) * 0.35;
		float in_glass = 1.0 - smoothstep(aperture_radius * 0.92, aperture_radius, length(local_pos.xy));
		a = (core + glow) * in_glass * (t > 0.0 ? 1.0 : 0.0);
	}
	ALBEDO = dot_color.rgb * a * intensity;
	ALPHA = clamp(a * 1.5, 0.0, 1.0);
}
