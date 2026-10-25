shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, alpha_to_coverage;

// Graded toward assets/reference/leaf-standard/ivy_leaf_standard.jpg (LEAF_STANDARD.md):
// deep green blade, pale yellow-green veins with strong contrast, satin surface.

uniform sampler2D albedo_tex : source_color;
uniform sampler2D normal_tex : hint_normal;
uniform sampler2D roughness_tex : hint_default_white;
uniform float alpha_scissor_threshold = 0.5;
uniform float alpha_edge_soft = 0.06;
uniform float normal_scale = 0.7;
uniform float roughness_floor = 0.34;
uniform float roughness_tex_scale = 0.9;
uniform float specular_amount = 0.45;
// Blade: scan colour darkened and saturated.
uniform float blade_gain = 0.55;
uniform float blade_saturation = 1.35;
// Veins: pale scan pixels (linear luma) pushed toward vein_color.
uniform float vein_luma_lo = 0.22;
uniform float vein_luma_hi = 0.48;
uniform float vein_strength = 0.72;
uniform vec3 vein_color : source_color = vec3(0.74, 0.82, 0.52);
// Atlas leaves are mirrored about u = 0.5 (symmetrize_leaf_atlas), so the midrib is exactly there.
uniform float midrib_strength = 0.55;
uniform float midrib_width_base = 0.012;
uniform float midrib_width_tip = 0.004;
uniform vec3 healthy_tint = vec3(0.92, 1.0, 0.88);
uniform vec3 weathered_tint = vec3(0.88, 0.96, 0.82);
uniform vec3 petiole_color : source_color = vec3(0.62, 0.74, 0.38);
uniform vec3 backlight = vec3(0.30, 0.45, 0.18);

varying vec4 rect_uv;


void vertex() {
	rect_uv = INSTANCE_CUSTOM;
}


void fragment() {
	// Petiole strip (LeafCupMesh UV v ∈ [1.5, 2.5]).
	if (UV.y > 1.25) {
		ALBEDO = petiole_color * COLOR.rgb;
		ROUGHNESS = 0.5;
		BACKLIGHT = backlight;
	} else {
		vec2 atlas_uv = rect_uv.xy + UV * rect_uv.zw;
		vec4 tex = texture(albedo_tex, atlas_uv);
		float a = tex.a;
		float edge = smoothstep(
			alpha_scissor_threshold - alpha_edge_soft,
			alpha_scissor_threshold + alpha_edge_soft,
			a);
		if (edge < 0.01) {
			discard;
		}
		vec3 lw = vec3(0.2126, 0.7152, 0.0722);
		float luma = dot(tex.rgb, lw);
		float vein = smoothstep(vein_luma_lo, vein_luma_hi, luma) * vein_strength;
		float mw = mix(midrib_width_tip, midrib_width_base, UV.y);
		float midrib = (1.0 - smoothstep(mw * 0.5, mw, abs(UV.x - 0.5))) * midrib_strength;
		vein = max(vein, midrib * smoothstep(0.0, 0.12, UV.y));
		vec3 blade = tex.rgb * blade_gain;
		blade = max(mix(vec3(dot(blade, lw)), blade, blade_saturation), vec3(0.0));
		blade *= rect_uv.x > 0.5 ? weathered_tint : healthy_tint;
		vec3 albedo = mix(blade, vein_color, vein);
		ALBEDO = albedo * COLOR.rgb;
		ALPHA = a * edge;
		vec3 nmap = texture(normal_tex, atlas_uv).rgb;
		nmap.xy = (nmap.xy - 0.5) * normal_scale + 0.5;
		NORMAL_MAP = nmap;
		ROUGHNESS = max(roughness_floor, texture(roughness_tex, atlas_uv).r * roughness_tex_scale);
		BACKLIGHT = backlight * edge;
	}
	SPECULAR = specular_amount;
}
