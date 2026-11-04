shader_type spatial;

// Damier procédural pour percevoir le déplacement sur un sol plat.
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = floor(world_pos.xz);
	float k = mod(cell.x + cell.y, 2.0);
	ALBEDO = mix(vec3(0.30, 0.38, 0.30), vec3(0.42, 0.50, 0.42), k);
	ROUGHNESS = 1.0;
}
