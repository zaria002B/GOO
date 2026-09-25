shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// --- Look ---
uniform vec4 albedo_color : source_color = vec4(0.2, 0.9, 0.45, 0.85);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.12;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.6;

// --- Idle jiggle (always active, gives the "alive" jelly look) ---
uniform float idle_amplitude : hint_range(0.0, 0.2) = 0.03;
uniform float idle_frequency : hint_range(0.0, 10.0) = 2.4;

// --- Impact ripple (triggered from script on landing / hard stops) ---
uniform float impact_amplitude : hint_range(0.0, 1.0) = 0.0;
uniform float impact_time : hint_range(0.0, 20.0) = 999.0;
uniform float impact_frequency : hint_range(0.0, 40.0) = 16.0;
uniform float impact_decay : hint_range(0.0, 30.0) = 7.0;

// Cheap deterministic per-vertex pseudo-random hash, so each point on the
// surface jiggles slightly out of phase with its neighbors instead of the
// whole mesh breathing in lockstep like a balloon.
float hash13(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	vec3 n = NORMAL;
	float phase = hash13(VERTEX) * 6.2831853;

	float idle = sin(TIME * idle_frequency + phase) * idle_amplitude;

	float envelope = exp(-impact_decay * impact_time);
	float ripple = sin(impact_frequency * impact_time - length(VERTEX) * 6.0) * impact_amplitude * envelope;

	VERTEX += n * (idle + ripple);
}

void fragment() {
	ALBEDO = albedo_color.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	ALPHA = albedo_color.a;

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = albedo_color.rgb * fresnel * rim_strength;
}
