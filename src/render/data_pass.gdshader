shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, cull_disabled;

uniform int pass_kind = 1;
uniform float depth_near = 0.05;
uniform float depth_far = 20.0;
uniform vec3 region = vec3(0.0);
uniform sampler2D mask_map : filter_nearest, repeat_enable;
uniform bool has_mask = false;
uniform sampler2D albedo_map : filter_nearest, repeat_enable;
uniform bool has_albedo = false;
uniform float alpha_factor = 1.0;
uniform float alpha_cutoff = 0.5;
uniform bool use_cutout = false;
uniform bool use_vertex_alpha = false;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform vec3 calibration_bytes = vec3(0.0);
varying float view_depth;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	vec2 source_uv = UV * uv_scale.xy + uv_offset.xy;
	float source_alpha = alpha_factor;
	if (use_vertex_alpha) { source_alpha *= COLOR.a; }
	if (has_albedo) { source_alpha *= texture(albedo_map, source_uv).a; }
	if (use_cutout && source_alpha < alpha_cutoff) { discard; }
	vec3 bytes = region;
	if (pass_kind == 1 && has_mask) { bytes = texture(mask_map, source_uv).rgb; }
	if (pass_kind == 2) {
		float normalized = clamp((view_depth - depth_near) / (depth_far - depth_near), 0.0, 1.0);
		uint packed = min(uint(floor(normalized * 16777215.0 + 0.5)), 16777215u);
		bytes = vec3(float((packed >> 16u) & 255u), float((packed >> 8u) & 255u), float(packed & 255u)) / 255.0;
	}
	if (pass_kind == 3) { bytes = calibration_bytes; }
	// Forward+ writes sRGB at the end. Cancel only that transfer for data bytes.
	ALBEDO = OUTPUT_IS_SRGB ? bytes : srgb_to_linear(bytes);
}
