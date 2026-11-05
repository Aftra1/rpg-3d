shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Vent
uniform float wind_strength = 0.1;
uniform float wind_speed = 1.6;
uniform float wind_scale = 0.35;
uniform vec2 wind_direction = vec2(1.0, 0.4);
// Les brins rétrécissent entre fade_start et fade_end (mètres) avant de disparaître
uniform float fade_start = 38.0;
uniform float fade_end = 52.0;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / 0.4, 0.0, 1.0);
	vec2 dir = normalize(wind_direction);
	float phase = dot(world.xz, dir) * wind_scale + TIME * wind_speed;
	float sway = sin(phase) + 0.5 * sin(phase * 2.3 + world.z * 0.4);
	vec2 offset = dir * sway * wind_strength * h * h;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(offset.x, 0.0, offset.y);
	float d = distance(world, CAMERA_POSITION_WORLD);
	VERTEX.y *= 1.0 - smoothstep(fade_start, fade_end, d);
}

void fragment() {
	// COLOR = dégradé du modèle (base = couleur du sol) x couleur d'instance (variation par touffe)
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
