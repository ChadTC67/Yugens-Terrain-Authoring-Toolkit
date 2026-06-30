shader_type spatial;
render_mode blend_mix, diffuse_toon, depth_draw_opaque;

uniform sampler2D texture_albedo : source_color, filter_nearest, repeat_enable;
uniform sampler2D tex_prefab_colormap : source_color;
uniform bool has_prefab_colormap = false;

group_uniforms Visuals.Normals;
uniform bool use_flat_normals = false;
group_uniforms;

group_uniforms CellShading;
uniform bool use_cell_shading = true;
uniform vec4 shadow_color : source_color;
uniform int bands : hint_range(1, 10) = 5;
uniform float shadow_intensity : hint_range(-1.0, 0.5, 0.05) = 0.0;
group_uniforms;

void vertex() {
	bool is_floor = dot(NORMAL, vec3(0.0, 1.0, 0.0)) > wall_threshold;
	if (use_flat_normals && is_floor)
		NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec4 color = texture(texture_albedo,UV2);
	ALBEDO = color.rgb;
	if (has_prefab_colormap) {
		vec4 col = texture(tex_prefab_colormap, UV);
		ALBEDO.rgb *= col.rgb;
		ALPHA *= col.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	NdotL = clamp(NdotL, 0.0, 1.0);

	float stepped = ceil(NdotL * float(bands)) / float(bands);
	float toon_light = mix(shadow_intensity, 0.3, stepped);
	toon_light = clamp(toon_light, 0.0, 1.0);

	vec3 light_color = mix(shadow_color.rgb, LIGHT_COLOR.rgb, toon_light);

	DIFFUSE_LIGHT += light_color * ATTENUATION;
}
