extends Node3D
## Herbe en MultiMesh répartie sur les triangles « herbe » du terrain.
## - 3 variantes de touffes (herbe_01/02/03) choisies selon un bruit ;
## - un bruit de densité crée des zones denses, clairsemées et des clairières ;
## - une couche « proche » plus dense, visible seulement près du joueur ;
## - couleur d'instance aléatoire (touffes plus jaunes / plus sombres) ;
## - aucune herbe autour des arbres et des rochers (nœuds « Arbre* » / « Roche* »).
## Aucune collision, aucune ombre portée.

const MESHES := [
	preload("res://assets/models/herbe_01.glb"),
	preload("res://assets/models/herbe_02.glb"),
	preload("res://assets/models/herbe_03.glb"),
]
const GRASS_SHADER := preload("res://grass.gdshader")

@export_group("Densité")
## Touffes par m² dans les zones les plus denses (couche lointaine).
@export var density: float = 2.0
## Fraction de la densité conservée dans les zones clairsemées (0 = vide).
@export_range(0.0, 1.0) var sparse_factor: float = 0.2
## Touffes par m² supplémentaires près du joueur (couche proche).
@export var near_density: float = 4.0
@export_group("Distances")
## Distance (m) d'affichage de la couche lointaine.
@export var view_distance: float = 55.0
## Distance (m) d'affichage de la couche proche (très dense).
@export var near_view_distance: float = 22.0
@export_group("Bruit")
## Fréquence du bruit de densité (plus petit = zones plus grandes).
@export var density_noise_frequency: float = 0.035
## Fréquence du bruit des clairières.
@export var clearing_noise_frequency: float = 0.022
## Seuil des clairières (0.3 = nombreuses, 0.6 = rares).
@export_range(0.0, 1.0) var clearing_threshold: float = 0.42
@export var variant_noise_frequency: float = 0.06
@export_group("Touffes")
@export var min_scale: float = 0.8
@export var max_scale: float = 1.4
@export var tree_clearance: float = 1.1
@export var random_seed: int = 12345
## Nom du matériau de la terre dans le terrain (pas d'herbe dessus).
@export var dirt_material_name: String = "Terre"

var tuft_count: int = 0
var _obstacles: Array[Vector3] = []  # x, z, rayon
var _n_density := FastNoiseLite.new()
var _n_clear := FastNoiseLite.new()
var _n_variant := FastNoiseLite.new()
var _n_color := FastNoiseLite.new()


func _ready() -> void:
	var terrain := get_node("../Terrain")
	var terrain_mesh: MeshInstance3D = terrain.find_children("*", "MeshInstance3D", true, false)[0]

	var meshes: Array[Mesh] = []
	for s in MESHES:
		var root := (s as PackedScene).instantiate()
		meshes.append(_find_mesh(root))
		root.free()

	for n in get_parent().get_children():
		if n.name.begins_with("Arbre") or n.name.begins_with("Roche"):
			_obstacles.append(Vector3(n.global_position.x, n.global_position.z, n.get_meta("clearance", tree_clearance)))

	_setup_noise(_n_density, density_noise_frequency, random_seed)
	_setup_noise(_n_clear, clearing_noise_frequency, random_seed + 1)
	_setup_noise(_n_variant, variant_noise_frequency, random_seed + 2)
	_setup_noise(_n_color, 0.03, random_seed + 3)

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var far_mat := _make_material(38.0, view_distance - 3.0)
	var near_mat := _make_material(near_view_distance - 9.0, near_view_distance + 1.0)

	var layers := [
		{"density": density, "chunk": 25.0, "range": view_distance, "mat": far_mat, "name": "Loin"},
		{"density": near_density, "chunk": 12.5, "range": near_view_distance, "mat": near_mat, "name": "Pres"},
	]
	var terrain_xform := terrain_mesh.global_transform
	var mesh := terrain_mesh.mesh
	for layer in layers:
		var chunks := _scatter(mesh, terrain_xform, rng, layer["density"], layer["chunk"])
		_build_chunks(chunks, meshes, layer)
	print("Herbe : %d touffes" % tuft_count)


func _setup_noise(n: FastNoiseLite, freq: float, s: int) -> void:
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.seed = s


func _make_material(fade_start: float, fade_end: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GRASS_SHADER
	m.set_shader_parameter("fade_start", fade_start)
	m.set_shader_parameter("fade_end", fade_end)
	return m


## Multiplicateur de densité (0..1) en un point : zones denses, clairsemées, clairières.
func _density_at(x: float, z: float) -> float:
	var d := smoothstep(-0.3, 0.4, _n_density.get_noise_2d(x, z))
	var m := lerpf(sparse_factor, 1.0, d)
	var c := smoothstep(clearing_threshold - 0.1, clearing_threshold + 0.08, _n_clear.get_noise_2d(x, z))
	return m * (1.0 - 0.96 * c)


func _pick_variant(x: float, z: float, rng: RandomNumberGenerator) -> int:
	var v := _n_variant.get_noise_2d(x, z)
	var r := rng.randf()
	if v > 0.15:  # zones « fleuries » : plus de grandes herbes
		return 2 if r < 0.45 else (0 if r < 0.85 else 1)
	if v < -0.15:  # zones d'herbe rase dense
		return 1 if r < 0.65 else (0 if r < 0.95 else 2)
	return 0 if r < 0.65 else (1 if r < 0.9 else 2)


func _scatter(mesh: Mesh, xform: Transform3D, rng: RandomNumberGenerator, dens: float, chunk: float) -> Dictionary:
	var chunks := {}  # Vector3i(cx, cz, variante) -> Array de [Transform3D, Color] (local au bloc)
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
			var n := int(floor(area * dens + rng.randf()))
			for k in n:
				var u := rng.randf()
				var v := rng.randf()
				if u + v > 1.0:
					u = 1.0 - u
					v = 1.0 - v
				var p := a + (b - a) * u + (c - a) * v
				if rng.randf() > _density_at(p.x, p.z):
					continue
				if _blocked(p.x, p.z):
					continue
				var variant := _pick_variant(p.x, p.z, rng)
				var sc := rng.randf_range(min_scale, max_scale)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.8, 1.25), sc))
				# couleur d'instance : plus jaune / plus sombre, par plages + hasard
				var t := clampf(0.5 + 0.7 * _n_color.get_noise_2d(p.x, p.z) + rng.randf_range(-0.25, 0.25), 0.0, 1.0)
				var col := Color(lerpf(0.72, 1.3, t), lerpf(0.82, 1.12, t), lerpf(0.9, 0.65, t))
				col = col * rng.randf_range(0.9, 1.08)
				col.a = 1.0
				var key := Vector3i(floori(p.x / chunk), floori(p.z / chunk), variant)
				if not chunks.has(key):
					chunks[key] = []
				var centre := Vector3((key.x + 0.5) * chunk, 0.0, (key.y + 0.5) * chunk)
				chunks[key].append([Transform3D(basis, p - Vector3(0, 0.02, 0) - centre), col])
	return chunks


func _blocked(x: float, z: float) -> bool:
	for o in _obstacles:
		var dx := x - o.x
		var dz := z - o.y
		if dx * dx + dz * dz < o.z * o.z:
			return true
	return false


func _build_chunks(chunks: Dictionary, meshes: Array[Mesh], layer: Dictionary) -> void:
	var chunk: float = layer["chunk"]
	for key in chunks:
		var list: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = meshes[key.z]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
		tuft_count += list.size()
		var inst := MultiMeshInstance3D.new()
		inst.name = "%s_%d_%d_v%d" % [layer["name"], key.x, key.y, key.z]
		inst.multimesh = mm
		inst.material_override = layer["mat"]
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# bloc placé à son centre : la distance d'affichage est mesurée jusqu'au bloc
		inst.position = Vector3((key.x + 0.5) * chunk, 0.0, (key.y + 0.5) * chunk)
		inst.visibility_range_end = float(layer["range"]) + chunk * 0.75
		inst.extra_cull_margin = 0.5
		add_child(inst)


func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return node.mesh
	for c in node.get_children():
		var m := _find_mesh(c)
		if m != null:
			return m
	return null
