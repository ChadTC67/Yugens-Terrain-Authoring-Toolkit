shader_type spatial;
render_mode diffuse_toon, depth_draw_opaque;

group_uniforms Visuals.Palette;
// Palette data is provided via lookup textures (see mst_terrain.gdshaderinc for details).
uniform sampler2D palette_colors_tex : filter_nearest;
uniform sampler2D palette_weights_tex : filter_nearest;
uniform sampler2D palette_meta_tex : filter_nearest;
group_uniforms;

group_uniforms Visuals.Textures;
uniform sampler2D grass_texture_1 : source_color, filter_nearest;
uniform sampler2D grass_texture_2 : source_color, filter_nearest;
uniform sampler2D grass_texture_3 : source_color, filter_nearest;
uniform sampler2D grass_texture_4 : source_color, filter_nearest;
uniform sampler2D grass_texture_5 : source_color, filter_nearest;
uniform sampler2D grass_texture_6 : source_color, filter_nearest;
group_uniforms;

group_uniforms Visuals.Texture_Mode;
uniform bool use_grass_tex_2 = true;
uniform bool use_grass_tex_3 = true;
uniform bool use_grass_tex_4 = true;
uniform bool use_grass_tex_5 = true;
uniform bool use_grass_tex_6 = true;
group_uniforms;

group_uniforms Visuals.Color_Mode;
uniform bool use_base_color_1 = false;
uniform bool use_base_color_2 = false;
uniform bool use_base_color_3 = false;
uniform bool use_base_color_4 = false;
uniform bool use_base_color_5 = false;
uniform bool use_base_color_6 = false;
group_uniforms;


group_uniforms Effects.Experimental;
uniform bool is_merge_round = false;
uniform float blade_variation : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float wall_threshold : hint_range(0.0, 0.5) = 0.0;
group_uniforms;

group_uniforms Effects.GlobalNoise;
uniform float global_noise_scale = 0.037;
uniform float global_noise_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float global_noise_scroll = 0.0;
uniform vec2 wind_direction = vec2(1.0, 1.0);
uniform float wind_speed = 0.14;
uniform sampler2D global_noise_texture : hint_default_white, repeat_enable, filter_linear;

// Palette color selection always uses the global-noise texture (internally remapped).
group_uniforms;

group_uniforms CellShading;
uniform bool use_cell_shading = true;
uniform vec4 shadow_color : source_color;
uniform int bands : hint_range(1, 10) = 5;
uniform float shadow_intensity : hint_range(-1.0, 0.5, 0.05) = 0.0;
group_uniforms;

group_uniforms VertexPaint;
varying vec3 world_origin;
varying vec3 vertex_normal;
group_uniforms;


varying float v_brightness;
varying vec3 v_grass_color;
varying vec3 model_origin;
varying vec3 instance_color;
varying float instance_sprite_id;
varying flat int instance_id;

// ------------- Wind Choices --------------

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float cheap_noise(vec2 p) {
	vec2 warp = vec2(
		noise(p + vec2(1.7, 9.2)),
		noise(p + vec2(8.3, 2.8)));
	return noise(p + warp * 0.4) * 0.6 + noise(p * 2.1 + vec2(5.2, 1.3)) * 0.4;
}


vec4 _palette_meta(int slot) {
	slot = clamp(slot, 0, 255);
	float v = (float(slot) + 0.5) / 256.0;
	return texture(palette_meta_tex, vec2(0.5, v));
}

int _palette_count(int slot) {
	return int(round(_palette_meta(slot).r * 255.0));
}

int _palette_blend_mode(int slot) {
	return int(round(_palette_meta(slot).g * 255.0));
}

vec4 sample_palette_entry(int slot, int color_idx) {
	slot = clamp(slot, 0, 255);
	int idx = clamp(color_idx, 0, 7);
	float u = (float(idx) + 0.5) / 8.0;
	float v = (float(slot) + 0.5) / 256.0;
	return texture(palette_colors_tex, vec2(u, v));
}

float sample_palette_weight(int slot, int color_idx) {
	slot = clamp(slot, 0, 255);
	int idx = clamp(color_idx, 0, 7);
	float u = (float(idx) + 0.5) / 8.0;
	float v = (float(slot) + 0.5) / 256.0;
	return max(texture(palette_weights_tex, vec2(u, v)).r, 0.0);
}

vec3 get_grass_palette_color(int slot, vec2 world_xz, float world_y) {
	slot = clamp(slot, 0, 255);
	int color_count = _palette_count(slot);
	if (color_count <= 0) return vec3(0.392, 0.471, 0.318);
	if (color_count == 1) return sample_palette_entry(slot, 0).rgb;

	float n = 0.0;
	// Internal remap for palette blending: fixed higher-frequency sampling + inverted.
	// This keeps the UI Global Noise settings independent of palette blending behavior.
	float palette_gn_scale = 0.002;
	vec2 scroll = vec2(0.0);
	if (global_noise_scroll > 0.0) {
		vec2 dir = normalize(wind_direction);
		scroll = dir * TIME * wind_speed * 3.0 * global_noise_scroll;
	}
	vec2 uv = fract((world_xz + scroll) * palette_gn_scale);
	n = 1.0 - texture(global_noise_texture, uv).r;
	n = smoothstep(0.0, 1.0, n);

	int mode = _palette_blend_mode(slot);

	// Weighted distribution (values are normalized per slot).
	float ws[8];
	float total = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i < color_count) {
			float w = sample_palette_weight(slot, i);
			ws[i] = w;
			total += w;
		} else {
			ws[i] = 0.0;
		}
	}
	if (total <= 0.0001) {
		total = float(color_count);
		for (int i = 0; i < 8; i++) {
			ws[i] = (i < color_count) ? 1.0 : 0.0;
		}
	}

	float x = clamp(n, 0.0, 1.0) * total;
	int i0 = 0;
	float start = 0.0;
	float w0 = ws[0];
	float cum = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= color_count) break;
		float wi = ws[i];
		if (x < cum + wi || i == color_count - 1) {
			i0 = i;
			start = cum;
			w0 = wi;
			break;
		}
		cum += wi;
	}
	int i1 = min(i0 + 1, color_count - 1);
	float t = 0.0;
	if (w0 > 0.00001) t = clamp((x - start) / w0, 0.0, 1.0);

	if (mode == 1) {
		// Retro: hard snap
		return sample_palette_entry(slot, i0).rgb;
	} else if (mode == 2) {
		// Dithered (weight-aware)
		vec2 dither_coord = floor(vec2(
			world_xz.x + world_y * 0.7,
			world_xz.y + world_y * 1.3) * 8.0);
		float dither = hash(dither_coord);
		float sel = step(dither, t);
		return mix(sample_palette_entry(slot, i0), sample_palette_entry(slot, i1), sel).rgb;
	} else if (mode == 3) {
		// Stipple (weight-aware)
		float seam = 0.08;
		if (t < 0.5 - seam) return sample_palette_entry(slot, i0).rgb;
		else if (t > 0.5 + seam) return sample_palette_entry(slot, i1).rgb;
		else {
			vec3 checker_coord = floor(vec3(world_xz.x, world_y, world_xz.y) * 12.0);
			float checker = mod(checker_coord.x + checker_coord.y + checker_coord.z, 2.0);
			return checker > 0.5 ? sample_palette_entry(slot, i1).rgb : sample_palette_entry(slot, i0).rgb;
		}
	} else {
		// Gradient (weight-aware)
		return mix(sample_palette_entry(slot, i0), sample_palette_entry(slot, i1), smoothstep(0.0, 1.0, t)).rgb;
	}
}

void vertex() {

	// Billboarding
	vec3 instance_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	vec3 cam_z = normalize(CAMERA_DIRECTION_WORLD);
	vec3 cam_y = vec3(0.0, 1.0, 0.0);
	vec3 cam_x = cross(cam_y, cam_z);
	if (length(cam_x) < 0.001) {
		cam_x = vec3(1.0, 0.0, 0.0);
	}
	cam_x = normalize(cam_x);
	cam_y = normalize(cross(cam_z, cam_x));

	mat3 spherical_billboard = mat3(cam_x, cam_y, cam_z);

	float slotx = length(MODEL_MATRIX[0].xyz);
	float sloty = length(MODEL_MATRIX[1].xyz);
	float slotz = length(MODEL_MATRIX[2].xyz);

	float h = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	float height_mult = mix(0.75, 1.25, h);
	sloty *= mix(1.0, height_mult, blade_variation);

	vec3 scaled_local = vec3(VERTEX.x * slotx, VERTEX.y * sloty, VERTEX.z * slotz);
	vec3 billboarded_vertex = spherical_billboard * scaled_local;
	vec3 world_position = instance_origin + billboarded_vertex;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_position, 1.0);

	model_origin = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	instance_color = INSTANCE_CUSTOM.rgb;
	instance_sprite_id = INSTANCE_CUSTOM.a;
	instance_id = INSTANCE_ID;
	
	vec3 _gc;
	if (instance_sprite_id > 0.9)
		_gc = use_base_color_6 ? get_grass_palette_color(5, world_origin.xz, world_origin.y) : instance_color * get_grass_palette_color(5, world_origin.xz, world_origin.y);
	else if (instance_sprite_id > 0.7)
		_gc = use_base_color_5 ? get_grass_palette_color(4, world_origin.xz, world_origin.y) : instance_color * get_grass_palette_color(4, world_origin.xz, world_origin.y);
	else if (instance_sprite_id > 0.5)
		_gc = use_base_color_4 ? get_grass_palette_color(3, world_origin.xz, world_origin.y) : instance_color * get_grass_palette_color(3, world_origin.xz, world_origin.y);
	else if (instance_sprite_id > 0.3)
		_gc = use_base_color_3 ? get_grass_palette_color(2, world_origin.xz, world_origin.y) : instance_color * get_grass_palette_color(2, world_origin.xz, world_origin.y);
	else if (instance_sprite_id > 0.1)
		_gc = use_base_color_2 ? get_grass_palette_color(1, world_origin.xz, world_origin.y) : instance_color * get_grass_palette_color(1, world_origin.xz, world_origin.y);
	else
		_gc = use_base_color_1 ? get_grass_palette_color(0, world_origin.xz, world_origin.y) : instance_color * get_grass_palette_color(0, world_origin.xz, world_origin.y);
	v_grass_color = _gc;
	
	v_brightness = 1.0;

	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vertex_normal = world_normal;
}

void fragment() {
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec4 grass_tex = texture(grass_texture_1, UV);

	vec3 grass_color = v_grass_color;
	int tex_id = 1;
	if (instance_sprite_id > 0.9) tex_id = 6;
	else if (instance_sprite_id > 0.7) tex_id = 5;
	else if (instance_sprite_id > 0.5) tex_id = 4;
	else if (instance_sprite_id > 0.3) tex_id = 3;
	else if (instance_sprite_id > 0.1) tex_id = 2;


	ALBEDO = grass_color;

	if (global_noise_strength > 0.0) {
		vec2 scroll = vec2(0.0);
		if (global_noise_scroll > 0.0) {
			vec2 dir = normalize(wind_direction);
			scroll = dir * TIME * wind_speed * 3.0 * global_noise_scroll;
		}
		vec2 uv = fract((world_origin.xz + scroll) * global_noise_scale);
		float gn = texture(global_noise_texture, uv).r;
		// Centered multiplier: darkens and brightens around 1.0.
		float mult = mix(1.0 - global_noise_strength, 1.0 + global_noise_strength, clamp(gn, 0.0, 1.0));
		ALBEDO *= max(mult, 0.0);
	}

	float w_threshold = wall_threshold;
	if (is_merge_round && wall_threshold <= 0.0)
		w_threshold -= 1.5;
	if (dot(vertex_normal, vec3(0.0, 1.0, 0.0)) > w_threshold) {
		if (tex_id == 2) {
			ALPHA = use_grass_tex_2 ? texture(grass_texture_2, UV).a : 0.0;
		} else if (tex_id == 3) {
			ALPHA = use_grass_tex_3 ? texture(grass_texture_3, UV).a : 0.0;
		} else if (tex_id == 4) {
			ALPHA = use_grass_tex_4 ? texture(grass_texture_4, UV).a : 0.0;
		} else if (tex_id == 5) {
			ALPHA = use_grass_tex_5 ? texture(grass_texture_5, UV).a : 0.0;
		} else if (tex_id == 6) {
			ALPHA = use_grass_tex_6 ? texture(grass_texture_6, UV).a : 0.0;
		} else {
			ALPHA = grass_tex.a;
		}
	} else {
		ALPHA = 0.0;
	}

	if (ALPHA < 0.1) discard;

	ALBEDO *= v_brightness;

	LIGHT_VERTEX = model_origin;
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	NdotL = clamp(NdotL, 0.0, 1.0);

	float toon_light;
	if (use_cell_shading) {
		float stepped = ceil(NdotL * float(bands)) / float(bands);
		toon_light = mix(shadow_intensity, 0.3, stepped);
	} else {
		toon_light = NdotL * 0.3;
	}

	toon_light *= ATTENUATION;
	vec3 light_color = mix(shadow_color.rgb, LIGHT_COLOR.rgb, toon_light);
	DIFFUSE_LIGHT += light_color;
}