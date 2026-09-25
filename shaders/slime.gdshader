shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.35, 0.85, 0.5, 0.55);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.6;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.2;
uniform float specular_val : hint_range(0.0, 1.0) = 0.8;

// Constant subtle surface ripple, independent of the SoftBody3D physics.
// This is what keeps the mesh looking "alive" even when standing still,
// since the physics sim alone only reacts to jump/land/rolling.
uniform float wobble_amplitude : hint_range(0.0, 0.1) = 0.015;
uniform float wobble_speed : hint_range(0.0, 10.0) = 3.0;
uniform float wobble_scale : hint_range(1.0, 20.0) = 8.0;

void vertex() {
	float wave = sin(TIME * wobble_speed
		+ VERTEX.x * wobble_scale
		+ VERTEX.y * wobble_scale
		+ VERTEX.z * wobble_scale);
	VERTEX += NORMAL * wave * wobble_amplitude;
}

void fragment() {
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a;
	RIM = rim_amount;
	ROUGHNESS = roughness_val;
	METALLIC = 0.05;
	SPECULAR = specular_val;
}
