extends AnimationTree
## Animation du héros : machine à états idle / walk / run / jump avec fondus enchaînés.
## L'arbre est construit ici (pas de ressource à éditer à la main) ; `player.gd` appelle
## `update_locomotion()` à chaque frame physique.

## Vitesse (m/s) à laquelle les animations Mixamo font avancer le personnage telles quelles.
## Sert à régler la vitesse de lecture pour que les pieds ne glissent pas :
## vitesse_de_lecture = vitesse_réelle / vitesse_naturelle.
@export var walk_anim_speed: float = 1.60
@export var run_anim_speed: float = 5.31
## Seuils de changement d'état (m/s).
@export var idle_threshold: float = 0.4
## Au-dessus de cette vitesse on passe de walk à run.
@export var run_threshold: float = 3.6
## Durée (s) des fondus entre animations.
@export var blend_time: float = 0.2
@export var jump_blend_time: float = 0.12
## Bornes de la vitesse de lecture (évite une animation figée ou frénétique).
@export var min_play_speed: float = 0.6
@export var max_play_speed: float = 2.0

const FPS := 30.0
const STATES := ["idle", "walk", "run", "jump"]

var _playback: AnimationNodeStateMachinePlayback
var _current := "idle"


func _ready() -> void:
	var player: AnimationPlayer = get_node(anim_player)
	# Boucles. La dernière image exportée duplique la première : on la retire de la durée
	# pour que la boucle soit continue (sinon micro-arrêt à chaque cycle).
	for n in ["idle", "walk", "run"]:
		var a := player.get_animation(n)
		a.loop_mode = Animation.LOOP_LINEAR
		a.length = maxf(a.length - 1.0 / FPS, 1.0 / FPS)
	player.get_animation("jump").loop_mode = Animation.LOOP_NONE

	var sm := AnimationNodeStateMachine.new()
	var x := 0.0
	for s in STATES:
		var node := AnimationNodeAnimation.new()
		node.animation = s
		sm.add_node(s, node, Vector2(x, 0))
		x += 200.0
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition("Start", "idle", start)
	# Toutes les transitions sont possibles (travel() choisit le chemin direct).
	for a in STATES:
		for b in STATES:
			if a == b:
				continue
			var t := AnimationNodeStateMachineTransition.new()
			t.xfade_time = jump_blend_time if (a == "jump" or b == "jump") else blend_time
			sm.add_transition(a, b, t)

	var tree := AnimationNodeBlendTree.new()
	tree.add_node("states", sm, Vector2(0, 0))
	tree.add_node("speed", AnimationNodeTimeScale.new(), Vector2(300, 0))
	tree.connect_node("speed", 0, "states")
	tree.connect_node("output", 0, "speed")
	tree_root = tree
	# L'animation avance au même rythme que le déplacement (physique) : pas de décalage ni de saccade.
	callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	active = true
	_playback = get("parameters/states/playback")


## `h_speed` : vitesse horizontale (m/s) ; `on_floor` : le joueur touche le sol.
func update_locomotion(h_speed: float, on_floor: bool) -> void:
	if _playback == null:
		return
	var target := "idle"
	if not on_floor:
		target = "jump"
	elif h_speed > run_threshold:
		target = "run"
	elif h_speed > idle_threshold:
		target = "walk"
	if target != _current:
		_current = target
		_playback.travel(target)

	# Vitesse de lecture : les pieds avancent à la même vitesse que le sol défile.
	var scale := 1.0
	match _current:
		"walk":
			scale = clampf(h_speed / walk_anim_speed, min_play_speed, max_play_speed)
		"run":
			scale = clampf(h_speed / run_anim_speed, min_play_speed, max_play_speed)
	set("parameters/speed/scale", scale)
