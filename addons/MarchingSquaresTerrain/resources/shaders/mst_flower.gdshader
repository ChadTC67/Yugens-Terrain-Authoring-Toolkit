shader_type spatial;
render_mode diffuse_toon, depth_draw_opaque, cull_disabled;

group_uniforms Albedo;
uniform sampler2D flower_texture : source_color, filter_nearest;
uniform bool use_custom_color = true;
uniform bool should_billboard = false;
group_uniforms;

group_uniforms RNG;
uniform float rng_height_range : hint_range(0.0, 2.0, 0.1) = 0.0;
uniform float rng_size_range : hint_range(0.0, 1.0, 0.1) = 0.0;
group_uniforms;

group_uniforms Shading;
uniform vec4 shadow_color : source_color;
uniform int bands : hint_range(1, 10) = 5;
uniform float shadow_intensity : hint_range(-1.0, 0.5, 0.05) = 0.0;
group_uniforms;

group_uniforms Animations.Settings;
uniform bool animate_active = true;
uniform float fps : hint_range(0.0, 30.0, 1.0)= 0.0;
group_uniforms;

group_uniforms Animations.Wind;
uniform sampler2D wind_texture : source_color;
uniform vec2 wind_direction = vec2(1.0, 1.0);
uniform float wind_scale = 0.02;
uniform float wind_speed = 0.15;
group_uniforms;

varying vec3 model_origin;
varying vec4 instance_color;
varying vec3 light_vertex_position;

float randf_from_id(float id) {
	return fract(sin(id * 12.9898) * 43758.5453);
}

void vertex() {
	float rand_factor = randf_from_id(float(INSTANCE_ID));
	
	if (rng_height_range > 0.0) {
		float y_offset = rand_factor * rng_height_range;
		VERTEX.y += y_offset;
	}
	if (rng_size_range > 0.0) {
		float size_factor = 1.0 + (rand_factor * 2.0 - 1.0) * rng_size_range * 0.5;
		VERTEX.xz *= size_factor;
	}
	
	float rand_angle = rand_factor * TAU;
	float s = sin(rand_angle);
	float c = cos(rand_angle);
	if (!should_billboard) {
		mat2 rand_rot = mat2(vec2(c, -s), vec2(s, c));
		VERTEX.xz *= rand_rot;
	}
	if (animate_active && VERTEX.y > 0.0) {
		float left_to_right_mult = 0.2;
		// Individual sprite movement animations
		if (fps > 0.0) {
			// Insert custom logic here for rotated sprites
		}
		else {
			// Wind animations (make sure you apply a texture in the shader parameters)
			float wind_time = TIME * wind_speed;
			vec2 scroll = wind_time * wind_direction;
			
			vec3 world_pos = MODEL_MATRIX[3].xyz;
			vec2 wind_uv = (world_pos.xy * wind_scale) + scroll;
			
			float wind_value = texture(wind_texture, wind_uv).r;
			
			float wind = wind_value * left_to_right_mult;
			
			float bend_factor = clamp(VERTEX.y, 0.0, 1.0);
			VERTEX += vec3(wind, 0.0, 0.0) * bend_factor;
		}
	}
	// Billboarding: this needs to happen AFTER other animations
	if (should_billboard) {
		vec3 cam_z = normalize(CAMERA_DIRECTION_WORLD);
		vec3 cam_y = vec3(0.0, 1.0, 0.0);
		vec3 cam_x = cross(cam_y, cam_z);
		if (length(cam_x) < 0.001) {
			cam_x = vec3(1.0, 0.0, 0.0);
		}
		cam_x = normalize(cam_x);
		cam_y = normalize(cross(cam_z, cam_x));
		mat3 spherical_billboard = mat3(cam_x, cam_y, cam_z);
		
		vec3 billboarded_vertex = spherical_billboard * VERTEX;
		
		vec3 instance_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		vec3 world_position = instance_origin + billboarded_vertex;
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_position, 1.0);
	}
	else {
		vec3 instance_origin = MODEL_MATRIX[3].xyz;
		vec3 world_vertex = 
			MODEL_MATRIX[0].xyz * VERTEX.z +
			MODEL_MATRIX[1].xyz * -VERTEX.x +
			MODEL_MATRIX[2].xyz * VERTEX.y;
		
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(instance_origin + world_vertex, 1.0);
		NORMAL = normalize(
			MODEL_MATRIX[0].xyz * NORMAL.z +
			MODEL_MATRIX[1].xyz * NORMAL.x +
			MODEL_MATRIX[2].xyz * NORMAL.y
		);
		light_vertex_position = (VIEW_MATRIX * vec4(instance_origin + world_vertex, 1.0)).xyz;
	}
	
	model_origin = (MODELVIEW_MATRIX * vec4(0.,0.,0.,1.)).xyz;
	instance_color = INSTANCE_CUSTOM;
}

void fragment() {
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec4 flower_tex = texture(flower_texture, UV);
	vec3 flower_color = use_custom_color ? flower_tex.rgb * instance_color.rgb : flower_tex.rgb;
	
	ALBEDO = flower_color;
	ALPHA = flower_tex.a * instance_color.a;
	
	if (ALPHA < 0.1) discard;
	
	if (should_billboard)
		LIGHT_VERTEX = model_origin;
	else
		LIGHT_VERTEX = light_vertex_position;
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	NdotL = clamp(NdotL, 0.0, 1.0);
	
	float stepped = ceil(NdotL * float(bands)) / float(bands);
	float toon_light = mix(shadow_intensity, 0.3, stepped);
	
	toon_light *= ATTENUATION;
	
	vec3 light_color = mix(shadow_color.rgb, LIGHT_COLOR.rgb, toon_light);
	
	DIFFUSE_LIGHT += light_color;
}
