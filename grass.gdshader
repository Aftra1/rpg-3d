shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Réglages du vent
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.6;
uniform float wind_scale = 0.35;
uniform vec2 wind_direction = vec2(1.0, 0.4);
// Couleur multipliée par le dégradé du modèle (vertex color)
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
// Les brins rétrécissent entre fade_start et fade_end (mètres) pour éviter l'apparition brutale
uniform float fade_start = 38.0;
uniform float fade_end = 52.0;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / 0.4, 0.0, 1.0);
	float phase = dot(world.xz, normalize(wind_direction)) * wind_scale + TIME * wind_speed;
	float sway = sin(phase) + 0.5 * sin(phase * 2.3 + world.z * 0.4);
	vec2 offset = normalize(wind_direction) * sway * wind_strength * h * h;
	// la pointe se déplace dans le repère monde ; on convertit en repère local
	vec3 off_world = vec3(offset.x, 0.0, offset.y);
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * off_world);
	float d = distance(world, CAMERA_POSITION_WORLD);
	float k = 1.0 - smoothstep(fade_start, fade_end, d);
	VERTEX.y *= k;
}

void fragment() {
	ALBEDO = COLOR.rgb * tint;
	ROUGHNESS = 1.0;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
