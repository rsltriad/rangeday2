extends "res://test/player.gd"
## Networked player: the local one is camera + FPS hands (authority = its peer);
## everyone else sees an animated body. Health/kills are decided by the server.

signal local_died(killer_id: int)
signal local_hp_changed(hp: float)
signal local_respawned

const MAX_HP := 100.0
const Account := preload("res://main/account.gd")
const BOT_ID_BASE := 100000
const TEAM_COLORS := [Color(0.7, 0.12, 0.1), Color(0.12, 0.3, 0.8)]

var peer_id := 1
var team := 0
var pname := ""
var hp := MAX_HP
var dead := false
var is_auth := false
var is_bot := false
var bot_move := Vector3.ZERO
var bot_sprint := false
var bot_jump := false
var input_blocked := false
var frozen := false # round freeze time (bomb mode): can look, can't move or shoot
var carrying_bomb := false
var _e_held := false
# replicated by the MultiplayerSynchronizer (authority -> everyone)
var cam_pitch := 0.0
var anim := "Pistol_Idle"
var aiming := false

var _last_anim := ""
var _shoot_t := 0.0
var _hurt_t := 0.0
var _skin_weapon: Node = null
var _skin_id := "?"
var cheat_aim := false
var cheat_vision := false
var _key_b := false
var _key_v := false
var _esp_t := 0.0

@onready var fps_hands: Node3D = $Camera3D/FpsHands
@onready var body: Node3D = $Body
@onready var anim_player: AnimationPlayer = $Body/Model.find_child("AnimationPlayer", true, false)
@onready var body_mesh: MeshInstance3D = $Body/Model.find_child("Mannequin", true, false)
@onready var skeleton: Skeleton3D = $Body/Model.find_child("Skeleton3D", true, false)
@onready var name_label: Label3D = $NameLabel
@onready var col_shape: CollisionShape3D = $CollisionShape3D

func _enter_tree() -> void:
	peer_id = name.to_int()
	is_bot = peer_id >= BOT_ID_BASE
	set_multiplayer_authority(1 if is_bot else peer_id)

func _ready() -> void:
	is_auth = is_multiplayer_authority() and not is_bot
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
		if not (is_bot and multiplayer.is_server()):
			set_physics_process(false)
	else:
		fps_hands.firing.connect(func(): _shoot_t = 0.12)
	if is_bot and multiplayer.is_server():
		var brain := preload("res://main/bot_brain.gd").new()
		brain.name = "Brain"
		add_child(brain)
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
	_update_hands()

func flag_shot() -> void: # bots: mark a shot so the shoot animation syncs
	_shoot_t = 0.15

func _update_hands() -> void:
	if not is_auth: return
	fps_hands.process_mode = Node.PROCESS_MODE_DISABLED if (input_blocked or dead or frozen) else Node.PROCESS_MODE_INHERIT

@rpc("any_peer", "call_local", "reliable")
func set_frozen(v: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1 and not multiplayer.is_server(): return
	frozen = v
	_update_hands()

@rpc("any_peer", "call_local", "reliable")
func set_bomb_carrier(v: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1 and not multiplayer.is_server(): return
	carrying_bomb = v
	name_label.text = pname + ("  [BOMB]" if v else "")

# ---------- input / movement (authority only) ----------
func _input(event: InputEvent) -> void:
	if not is_auth or dead or input_blocked: return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera.rotation.x = clampf(camera.rotation.x + deg_to_rad(event.relative.y * MOUSE_SENSITIVITY * -1), clamp_min, clamp_max)
		rotate_y(deg_to_rad(event.relative.x * MOUSE_SENSITIVITY * -1))

func _process(delta: float) -> void:
	if is_bot:
		if multiplayer.is_server():
			_shoot_t = maxf(_shoot_t - delta, 0.0)
			_choose_anim()
		if anim != _last_anim:
			_last_anim = anim
			anim_player.play(anim, 0.15)
		_aim_spine()
		return
	if is_auth:
		if not dead and not input_blocked:
			super(delta)
		else:
			_apply_fov()
		cam_pitch = camera.rotation.x
		aiming = fps_hands.ads
		_shoot_t = maxf(_shoot_t - delta, 0.0)
		_choose_anim()
		if fps_hands.weapon != _skin_weapon or Account.equipped != _skin_id:
			_skin_weapon = fps_hands.weapon
			_skin_id = Account.equipped
			Account.apply_weapon_skin(fps_hands)
		_cheats(delta)
		var e := Input.is_physical_key_pressed(KEY_E) and not dead and not input_blocked and not frozen
		if e != _e_held:
			_e_held = e
			var bomb := get_tree().current_scene.get_node_or_null("Bomb")
			if bomb:
				if multiplayer.is_server(): bomb.interact_from(peer_id, e)
				else: bomb.interact.rpc_id(1, e)
	else:
		if anim != _last_anim:
			_last_anim = anim
			anim_player.play(anim, 0.15)
		_aim_spine()

func _physics_process(delta: float) -> void:
	if dead or input_blocked or frozen:
		if not is_on_floor():
			velocity.y -= gravity * delta
		velocity.y = minf(velocity.y, JUMP_VELOCITY)
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		move_and_slide()
		if global_position.y > 12.0 or global_position.y < -8.0:
			global_position = Vector3(0, 1.5, 0) if not is_inside_tree() else get_tree().current_scene.pick_spawn(team)
			velocity = Vector3.ZERO
		return
	if is_bot:
		if not is_on_floor():
			velocity.y -= gravity * delta
		elif bot_jump:
			velocity.y = JUMP_VELOCITY
		bot_jump = false
		var sp := SPEED * (2.2 if bot_sprint else 1.1)
		velocity.x = bot_move.x * sp
		velocity.z = bot_move.z * sp
		velocity.y = minf(velocity.y, JUMP_VELOCITY) # depenetration can catapult; never fly
		running = bot_sprint
		move_and_slide()
		if global_position.y > 12.0 or global_position.y < -8.0:
			# escaped the map (squeezed between colliders): put the bot back on its spawn side
			global_position = get_tree().current_scene.pick_spawn(team)
			velocity = Vector3.ZERO
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

# ---------- admin cheats (B = auto aim, V = vision) ----------
func _cheats(delta: float) -> void:
	if not Account.is_admin: return
	var b := Input.is_physical_key_pressed(KEY_B)
	if b and not _key_b:
		cheat_aim = not cheat_aim
		_cheat_note("AUTO AIM %s" % ("ON" if cheat_aim else "OFF"))
	_key_b = b
	var vv := Input.is_physical_key_pressed(KEY_V)
	if vv and not _key_v:
		cheat_vision = not cheat_vision
		_cheat_note("VISION %s" % ("ON" if cheat_vision else "OFF"))
		if not cheat_vision:
			_esp(false)
	_key_v = vv
	if cheat_aim and not dead and not input_blocked and not frozen:
		_auto_aim(delta)
	if cheat_vision:
		_esp_t -= delta
		if _esp_t <= 0.0:
			_esp_t = 0.4
			_esp(true)

func _cheat_note(t: String) -> void:
	var g := get_tree().current_scene
	if g and g.get("center_label"):
		g.center_label.modulate = Color(1, 0.9, 0.3)
		g.center_label.text = t
		get_tree().create_timer(1.2).timeout.connect(func(): if g.center_label.text == t: g.center_label.text = "")

func _auto_aim(delta: float) -> void:
	var best: Node3D = null
	var best_d := 70.0
	var space := get_world_3d().direct_space_state
	for q in get_parent().get_children():
		if q == self or q.dead or q.team == team: continue
		var d: float = global_position.distance_to(q.global_position)
		if d >= best_d: continue
		var ray := PhysicsRayQueryParameters3D.create(camera.global_position, q.global_position + Vector3(0, 1.2, 0), 1)
		ray.exclude = [get_rid()]
		var hit := space.intersect_ray(ray)
		if hit.has("collider") and hit.collider == q:
			best = q
			best_d = d
	if best == null: return
	var to := best.global_position + Vector3(0, 1.35, 0) - camera.global_position
	var want_yaw := atan2(-to.x, -to.z)
	var k := minf(16.0 * delta, 1.0)
	rotation.y = lerp_angle(rotation.y, want_yaw, k)
	var want_pitch := clampf(atan2(to.y, Vector2(to.x, to.z).length()), clamp_min, clamp_max)
	camera.rotation.x = lerpf(camera.rotation.x, want_pitch, k)

func _esp(on: bool) -> void:
	for q in get_parent().get_children():
		if q == self or q.body_mesh == null: continue
		if on:
			if q.body_mesh.material_override == null:
				var m := StandardMaterial3D.new()
				m.no_depth_test = true
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.albedo_color = Color(1, 0.15, 0.1) if q.team != team else Color(0.3, 1.0, 0.3)
				q.body_mesh.material_override = m
			q.name_label.no_depth_test = true
		else:
			q.body_mesh.material_override = null
			q.name_label.no_depth_test = false

# ---------- damage (server authoritative) ----------
func _on_fps_hands_give_damage(obj: Node3D, damage: float, point: Vector3) -> void:
	super(obj, damage, point)
	if obj != self and obj.has_method("net_hit"):
		if multiplayer.is_server():
			obj.net_hit(damage, peer_id)
		else:
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
		if game.mode == "tdm":
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
			_update_hands()
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
		_update_hands()
		fps_hands.visible = true
		if fps_hands.ads:
			fps_hands.aim(false)
		$UI/CenterContainer/Crosshair.visible = true
		local_hp_changed.emit(hp)
		local_respawned.emit()
	else:
		_last_anim = ""
