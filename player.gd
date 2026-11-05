extends CharacterBody3D
## Joueur : déplacement ZQSD (AZERTY), saut Espace, caméra 3e personne à la souris.

const WALK_SPEED := 2.6
const RUN_SPEED := 4.7 # ≈ 1,8 × la marche (Shift)
const ACCELERATION := 40.0
const JUMP_VELOCITY := 6.5
const TURN_SPEED := 12.0 # plus grand = rotation plus rapide
const MOUSE_SENSITIVITY := 0.003
const PITCH_MIN := deg_to_rad(-75.0) # caméra haute, regarde vers le bas
const PITCH_MAX := deg_to_rad(15.0)  # caméra basse

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var model: Node3D = $Model # tourne seul ; la caméra n'en dépend pas
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var animation_tree: AnimationTree = $AnimationTree


func _ready() -> void:
	_setup_input_map()
	# Évite que le bras de caméra entre en collision avec le joueur lui-même.
	spring_arm.add_excluded_object(get_rid())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Actions définies par touche logique (keycode) : Z/Q/S/D sont donc bien
## les touches ZQSD d'un clavier AZERTY, quel que soit leur emplacement physique.
func _setup_input_map() -> void:
	_add_key_action("move_forward", KEY_Z)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_Q)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("run", KEY_SHIFT)


func _add_key_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.keycode = keycode
	InputMap.action_add_event(action, event)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotation.y -= event.relative.x * MOUSE_SENSITIVITY
		camera_pivot.rotation.x = clampf(
			camera_pivot.rotation.x - event.relative.y * MOUSE_SENSITIVITY,
			PITCH_MIN, PITCH_MAX)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	# Direction relative à l'orientation (yaw) de la caméra.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var yaw_basis := Basis(Vector3.UP, camera_pivot.rotation.y)
	var direction := yaw_basis * Vector3(input_dir.x, 0.0, input_dir.y)

	var speed := RUN_SPEED if Input.is_action_pressed("run") else WALK_SPEED
	var target := direction * speed
	velocity.x = move_toward(velocity.x, target.x, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCELERATION * delta)

	# Le modèle regarde vers -Z : on le tourne en douceur vers la direction du déplacement.
	if direction.length_squared() > 0.001:
		var target_yaw := atan2(-direction.x, -direction.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 1.0 - exp(-TURN_SPEED * delta))

	move_and_slide()

	# Le héros est animé selon sa vitesse réelle (après collisions) et le contact au sol.
	animation_tree.update_locomotion(Vector2(velocity.x, velocity.z).length(), is_on_floor())
