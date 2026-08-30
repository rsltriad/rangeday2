extends "res://test/player.gd"
## Networked player: the local one is camera + FPS hands (authority = its peer);
## everyone else sees an animated body. Health/kills are decided by the server.

signal local_died(killer_id: int)
signal local_hp_changed(hp: float)
signal local_respawned

const MAX_HP := 100.0
const TEAM_COLORS := [Color(0.7, 0.12, 0.1), Color(0.12, 0.3, 0.8)]

var peer_id := 1
var team := 0
var pname := ""
var hp := MAX_HP
var dead := false
var is_auth := false
var input_blocked := false
# replicated by the MultiplayerSynchronizer (authority -> everyone)
var cam_pitch := 0.0
var anim := "Pistol_Idle"
var aiming := false

var _last_anim := ""
var _shoot_t := 0.0
var _hurt_t := 0.0

@onready var fps_hands: Node3D = $Camera3D/FpsHands
@onready var body: Node3D = $Body
@onready var anim_player: AnimationPlayer = $Body/Model.find_child("AnimationPlayer", true, false)
@onready var body_mesh: MeshInstance3D = $Body/Model.find_child("Mannequin", true, false)
@onready var skeleton: Skeleton3D = $Body/Model.find_child("Skeleton3D", true, false)
@onready var name_label: Label3D = $NameLabel
@onready var col_shape: CollisionShape3D = $CollisionShape3D

func _enter_tree() -> void:
	peer_id = name.to_int()
	set_multiplayer_authority(peer_id)

func _ready() -> void:
	is_auth = is_multiplayer_authority()
	camera_start_position = camera.position
	camera.current = is_auth
	$UI.visible = is_auth
	body.visible = not is_auth
	name_label.visible = not is_auth
	name_label.text = pname
	name_label.modulate = TEAM_COLORS[team]
	if not is_auth:
		fps_hands.visible = false
		fps_hands.process_mode = Node.PROCESS_MODE_DISABLED
		set_physics_process(false)
	else:
		fps_hands.firing.connect(func(): _shoot_t = 0.12)
	_apply_team_color()
	for a in ["Death01", "Pistol_Shoot", "Hit_Chest"]:
		if anim_player.has_animation(a):
			anim_player.get_animation(a).loop_mode = Animation.LOOP_NONE
	for a in ["Pistol_Idle", "Pistol_Aim_Neutral", "Jog_Fwd", "Sprint", "Jump", "Idle"]:
		if anim_player.has_animation(a):
			anim_player.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	anim_player.play(anim)

func _apply_team_color() -> void:
	if body_mesh == null: return
	var main := StandardMaterial3D.new()
	main.albedo_color = TEAM_COLORS[team]
	main.roughness = 0.7
	body_mesh.set_surface_override_material(0, main)
	var joints := StandardMaterial3D.new()
	joints.albedo_color = TEAM_COLORS[team].darkened(0.55)
	body_mesh.set_surface_override_material(1, joints)

func set_input_blocked(v: bool) -> void:
	input_blocked = v
	fps_hands.process_mode = Node.PROCESS_MODE_DISABLED if (v or dead) else Node.PROCESS_MODE_INHERIT

# ---------- input / movement (authority only) ----------
func _input(event: InputEvent) -> void:
	if not is_auth or dead or input_blocked: return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera.rotation.x = clampf(camera.rotation.x + deg_to_rad(event.relative.y * MOUSE_SENSITIVITY * -1), clamp_min, clamp_max)
		rotate_y(deg_to_rad(event.relative.x * MOUSE_SENSITIVITY * -1))

func _process(delta: float) -> void:
	if is_auth:
		if not dead and not input_blocked:
			super(delta)
		cam_pitch = camera.rotation.x
		aiming = fps_hands.ads
		_shoot_t = maxf(_shoot_t - delta, 0.0)
		_choose_anim()
	else:
		if anim != _last_anim:
			_last_anim = anim
			anim_player.play(anim, 0.15)
		_aim_spine()

func _physics_process(delta: float) -> void:
	if dead or input_blocked:
		if not is_on_floor():
			velocity.y -= gravity * delta
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		move_and_slide()
		return
	super(delta)

func _choose_anim() -> void:
	var a := "Pistol_Idle"
	if dead:
		a = "Death01"
	elif not is_on_floor():
		a = "Jump"
	else:
		var hvel := Vector2(velocity.x, velocity.z).length()
		if hvel > 0.5:
			a = "Sprint" if running else "Jog_Fwd"
		elif _shoot_t > 0.0:
			a = "Pistol_Shoot"
		elif aiming:
			a = "Pistol_Aim_Neutral"
	anim = a

func _aim_spine() -> void:
	# Tilt the upper body with the synced camera pitch so remote players look up/down.
	if skeleton == null: return
	var idx := skeleton.find_bone("DEF-spine.003")
	if idx < 0: return
	var q := Quaternion(Vector3.RIGHT, -cam_pitch * 0.6)
	skeleton.set_bone_pose_rotation(idx, skeleton.get_bone_pose_rotation(idx) * q)

# ---------- damage (server authoritative) ----------
func _on_fps_hands_give_damage(obj: Node3D, damage: float, point: Vector3) -> void:
	super(obj, damage, point)
	if obj != self and obj.has_method("net_hit"):
		obj.net_hit.rpc_id(1, damage, peer_id)

@rpc("any_peer", "reliable")
func net_hit(damage: float, attacker: int) -> void:
	if not multiplayer.is_server() or dead: return
	var game := get_tree().current_scene
	if attacker != peer_id and game.same_team(attacker, peer_id): return # no friendly fire
	hp = maxf(hp - damage, 0.0)
	if hp <= 0.0:
		set_state.rpc(hp, true, attacker)
		game.report_kill(peer_id, attacker)
		get_tree().create_timer(game.RESPAWN_TIME).timeout.connect(_server_respawn)
	else:
		set_state.rpc(hp, false, attacker)

func _server_respawn() -> void:
	if not is_inside_tree(): return
	force_respawn.rpc(get_tree().current_scene.pick_spawn(team))

@rpc("any_peer", "call_local", "reliable")
func set_state(new_hp: float, is_dead: bool, attacker: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 and not multiplayer.is_server(): return
	hp = new_hp
	if is_auth:
		local_hp_changed.emit(hp)
	if is_dead and not dead:
		dead = true
		collision_layer = 0
		if is_auth:
			anim = "Death01"
			fps_hands.process_mode = Node.PROCESS_MODE_DISABLED
			fps_hands.visible = false
			$UI/CenterContainer/Crosshair.visible = false
			local_died.emit(attacker)
	elif not is_dead and not is_auth and anim_player.has_animation("Hit_Chest") and _last_anim != "Death01":
		anim_player.play("Hit_Chest", 0.1)
		_last_anim = ""

@rpc("any_peer", "call_local", "reliable")
func force_respawn(pos: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1 and not multiplayer.is_server(): return
	hp = MAX_HP
	dead = false
	collision_layer = 1
	velocity = Vector3.ZERO
	position = pos
	if is_auth:
		anim = "Pistol_Idle"
		fps_hands.process_mode = Node.PROCESS_MODE_INHERIT if not input_blocked else Node.PROCESS_MODE_DISABLED
		fps_hands.visible = true
		if fps_hands.ads:
			fps_hands.aim(false)
		$UI/CenterContainer/Crosshair.visible = true
		local_hp_changed.emit(hp)
		local_respawned.emit()
	else:
		_last_anim = ""
