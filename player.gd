extends CharacterBody3D
## Joueur : déplacement ZQSD (AZERTY), saut Espace, caméra 3e personne à la souris.

const SPEED := 6.0
const ACCELERATION := 40.0
const JUMP_VELOCITY := 6.5
const MOUSE_SENSITIVITY := 0.003
const PITCH_MIN := deg_to_rad(-75.0) # caméra haute, regarde vers le bas
const PITCH_MAX := deg_to_rad(15.0)  # caméra basse

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D


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

	var target := direction * SPEED
	velocity.x = move_toward(velocity.x, target.x, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCELERATION * delta)

	move_and_slide()
