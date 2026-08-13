group_uniforms Effects.Wind;
uniform sampler2D wind_noise_texture : hint_default_white, repeat_enable, filter_linear;
uniform float wind_direction_degrees : hint_range(0.0, 360.0, 0.1) = 45.0;
uniform float wind_speed : hint_range(0.0, 1.0, 0.01) = 0.08;
uniform float wind_strength : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float wind_scale : hint_range(0.005, 1.0, 0.005) = 0.037;
uniform float wind_gust_strength : hint_range(0.0, 2.0, 0.01) = 0.35;
uniform float wind_gust_speed : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform int wind_mode = 0;
group_uniforms;

vec2 mst_get_wind_direction() {
	// The editor angle is the source of truth: 0 degrees is +Z and angles turn
	// clockwise around the spherical Y axis. This keeps the shader and editor
	// gizmo using the same wind direction convention.
	float angle_radians = radians(wind_direction_degrees);
	return vec2(sin(angle_radians), cos(angle_radians));
}

float mst_sample_wind_sway_at_time(vec2 world_xz, float seed, float sample_time) {
	vec2 dir = mst_get_wind_direction();
	// Wind scale is independent from terrain texturing scale and directly controls
	// the world-space frequency of the wind noise map.
	float scale = max(wind_scale, 0.005);
	float time_scroll = sample_time * wind_speed;
	vec2 base_uv = fract(world_xz * scale + dir * time_scroll + vec2(seed, seed * 0.73));
	float base_wind = texture(wind_noise_texture, base_uv).r * 2.0 - 1.0;
	vec2 cross_dir = vec2(-dir.y, dir.x);
	vec2 gust_uv = fract(world_xz * (scale * 0.35) + dir * (sample_time * max(wind_gust_speed, 0.001) * 0.35) + vec2(seed * 1.31, seed * 2.17));
	float gust_mask = texture(wind_noise_texture, gust_uv).r;
	vec2 turbulent_uv = fract(world_xz * (scale * 1.85) + cross_dir * (time_scroll * 0.65) + vec2(seed * 2.07, seed * 0.61));
	float turbulent = texture(wind_noise_texture, turbulent_uv).r * 2.0 - 1.0;
	float gust_amp = mix(0.55, 1.0 + wind_gust_strength, gust_mask);
	if (wind_mode == 1) {
		return base_wind * wind_strength * gust_amp;
	}
	if (wind_mode == 2) {
		float blend = clamp(0.35 + gust_mask * 0.45, 0.0, 1.0);
		return mix(base_wind, turbulent, blend) * wind_strength * mix(0.75, 1.0 + wind_gust_strength, gust_mask);
	}
	return base_wind * wind_strength;
}

float mst_sample_wind_sway(vec2 world_xz, float seed) {
	return mst_sample_wind_sway_at_time(world_xz, seed, TIME);
}

vec2 mst_sample_wind_vector_at_time(vec2 world_xz, float seed, float sample_time) {
	vec2 dir = mst_get_wind_direction();
	vec2 cross_dir = vec2(-dir.y, dir.x);
	float sway = mst_sample_wind_sway_at_time(world_xz, seed, sample_time);
	float turbulent_mix = (wind_mode == 2) ? 0.35 : 0.0;
	return normalize(mix(dir, cross_dir, turbulent_mix)) * sway;
}

vec2 mst_sample_wind_vector(vec2 world_xz, float seed) {
	return mst_sample_wind_vector_at_time(world_xz, seed, TIME);
}
