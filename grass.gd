extends Node3D
## Répartit des touffes d'herbe (MultiMesh) sur les triangles « herbe » du terrain.
## Aucune collision. Les touffes sont découpées en blocs pour que la distance
## d'affichage (visibility_range_end) retire les blocs lointains.

const GRASS_SCENE := preload("res://assets/models/herbe_01.glb")
const GRASS_SHADER := preload("res://grass.gdshader")

## Touffes par m² de terrain vert.
@export var density: float = 1.2
## Distance (m) au-delà de laquelle un bloc d'herbe n'est plus affiché.
@export var view_distance: float = 55.0
## Taille (m) d'un bloc d'herbe.
@export var chunk_size: float = 25.0
## Distance (m) autour des troncs sans herbe.
@export var tree_clearance: float = 1.1
@export var min_scale: float = 0.7
@export var max_scale: float = 1.5
@export var random_seed: int = 12345
## Nom du matériau de la terre dans le terrain (pas d'herbe dessus).
@export var dirt_material_name: String = "Terre"

var tuft_count: int = 0


func _ready() -> void:
	var terrain := get_node("../Terrain")
	var terrain_mesh: MeshInstance3D = terrain.find_children("*", "MeshInstance3D", true, false)[0]
	var grass_root := GRASS_SCENE.instantiate()
	var tuft_mesh := _find_mesh(grass_root)
	grass_root.free()
	if tuft_mesh == null:
		push_error("herbe_01.glb : mesh introuvable")
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed

	var trees: Array[Vector2] = []
	for n in get_parent().get_children():
		if n.name.begins_with("Arbre"):
			trees.append(Vector2(n.global_position.x, n.global_position.z))

	var xform := terrain_mesh.global_transform
	var mesh := terrain_mesh.mesh
	var chunks := {}  # Vector2i -> Array[Transform3D]
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		if mat != null and mat.resource_name == dirt_material_name:
			continue
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		var count: int = idx.size() if idx != null else verts.size()
		for i in range(0, count, 3):
			var a := xform * (verts[idx[i]] if idx != null else verts[i])
			var b := xform * (verts[idx[i + 1]] if idx != null else verts[i + 1])
			var c := xform * (verts[idx[i + 2]] if idx != null else verts[i + 2])
			var area := (b - a).cross(c - a).length() * 0.5
			var n := int(floor(area * density + rng.randf()))
			for k in n:
				var u := rng.randf()
				var v := rng.randf()
				if u + v > 1.0:
					u = 1.0 - u
					v = 1.0 - v
				var p := a + (b - a) * u + (c - a) * v
				var p2 := Vector2(p.x, p.z)
				var blocked := false
				for t in trees:
					if t.distance_to(p2) < tree_clearance:
						blocked = true
						break
				if blocked:
					continue
				var sc := rng.randf_range(min_scale, max_scale)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.8, 1.2), sc))
				var key := Vector2i(floori(p.x / chunk_size), floori(p.z / chunk_size))
				if not chunks.has(key):
					chunks[key] = []
				chunks[key].append(Transform3D(basis, p - Vector3(0, 0.02, 0) - _chunk_centre(key)))

	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	tuft_count = 0
	for key in chunks:
		var list: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = tuft_mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		tuft_count += list.size()
		var inst := MultiMeshInstance3D.new()
		inst.name = "Chunk_%d_%d" % [key.x, key.y]
		inst.multimesh = mm
		inst.material_override = mat
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# le bloc est placé à son centre : la distance est mesurée jusqu'au bloc
		inst.position = _chunk_centre(key)
		inst.visibility_range_end = view_distance + chunk_size * 0.7
		inst.extra_cull_margin = 0.5
		add_child(inst)
	print("Herbe : %d touffes dans %d blocs" % [tuft_count, chunks.size()])


func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return node.mesh
	for c in node.get_children():
		var m := _find_mesh(c)
		if m != null:
			return m
	return null


func _chunk_centre(key: Vector2i) -> Vector3:
	return Vector3((key.x + 0.5) * chunk_size, 0.0, (key.y + 0.5) * chunk_size)
