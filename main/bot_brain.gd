extends Node
## Server-side controller for one bot (child "Brain" of a bot NetPlayer, server only).

const ENGAGE_DIST := 30.0
const EYE := Vector3(0, 1.5, 0)

var p: CharacterBody3D # the bot NetPlayer
var target: Node3D = null
var objective := Vector3.ZERO
var has_objective := false
var think_cd := 0.0
var fire_cd := 0.0
var strafe_dir := 1.0
var strafe_cd := 0.0
var stuck_t := 0.0
var last_pos := Vector3.ZERO

func _ready() -> void:
	p = get_parent()
	last_pos = p.global_position

func _physics_process(delta: float) -> void:
	if p.dead or p.frozen or p.input_blocked:
		p.bot_move = Vector3.ZERO
		return
	think_cd -= delta
	fire_cd -= delta
	strafe_cd -= delta
	if think_cd <= 0.0:
		think_cd = 0.25
		_think()
	_act(delta)

func _game() -> Node3D:
	return get_tree().current_scene

func _think() -> void:
	# nearest living enemy with line of sight
	target = null
	var best := ENGAGE_DIST
	for q in _game().players_root.get_children():
		if q == p or q.dead or q.team == p.team: continue
		var d: float = p.global_position.distance_to(q.global_position)
		if d < best and _sees(q):
			best = d
			target = q
	_pick_objective()
	# stuck detection: repick wander spot and hop
	if p.global_position.distance_to(last_pos) < 0.35 and p.bot_move.length() > 0.1:
		stuck_t += 0.25
		if stuck_t > 1.2:
			stuck_t = 0.0
			p.bot_jump = true
			has_objective = false
	else:
		stuck_t = 0.0
	last_pos = p.global_position

func _sees(q: Node3D) -> bool:
	var space := p.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(p.global_position + EYE, q.global_position + Vector3(0, 1.2, 0), 1)
	ray.exclude = [p.get_rid()]
	var hit := space.intersect_ray(ray)
	return hit.has("collider") and hit.collider == q

func _pick_objective() -> void:
	var g := _game()
	if g.mode == "bomb":
		var b = g.get_node("Bomb")
		if b.phase == "live" and b.is_attacker(p.team):
			if b.carrier == p.peer_id:
				var site: Vector3 = b.SITES["A"] if p.global_position.distance_to(b.SITES["A"]) < p.global_position.distance_to(b.SITES["B"]) else b.SITES["B"]
				objective = site
				has_objective = true
				b.interact_from(p.peer_id, b._site_at(p.global_position) != "")
				return
			if b.bomb_on_ground and b.carrier == 0:
				objective = b.bomb_pos
				has_objective = true
				return
		if b.phase == "planted" and not b.is_attacker(p.team):
			objective = b.bomb_pos
			has_objective = true
			b.interact_from(p.peer_id, p.global_position.distance_to(b.bomb_pos) < b.DEFUSE_RADIUS - 0.4)
			return
		if b.phase == "planted" and b.is_attacker(p.team):
			objective = b.bomb_pos + Vector3(6, 0, 6)
			has_objective = true
			return
	if target:
		has_objective = false
		return
	if not has_objective or p.global_position.distance_to(objective) < 3.0:
		var lim := 34.0 if _game().mode == "bomb" else Vector2(20, 42).y
		objective = Vector3(randf_range(-20, 20), 0, randf_range(-lim, lim))
		has_objective = true

func _act(delta: float) -> void:
	var aim_point := Vector3.ZERO
	if target:
		aim_point = target.global_position + Vector3(0, 1.25, 0)
	elif has_objective:
		aim_point = objective + Vector3(0, 1.5, 0)
	# turn toward the aim point
	if aim_point != Vector3.ZERO:
		var flat := aim_point - p.global_position
		var want_yaw := atan2(-flat.x, -flat.z)
		p.rotation.y = lerp_angle(p.rotation.y, want_yaw, minf(7.0 * delta, 1.0))
		var eye := p.global_position + EYE
		p.cam_pitch = clampf(atan2(aim_point.y - eye.y, Vector2(flat.x, flat.z).length()), -1.2, 1.2)
	# movement
	var move := Vector3.ZERO
	if target:
		var d := p.global_position.distance_to(target.global_position)
		var fwd := (target.global_position - p.global_position).normalized()
		if strafe_cd <= 0.0:
			strafe_cd = randf_range(0.8, 1.8)
			strafe_dir = -strafe_dir if randf() < 0.6 else strafe_dir
		var side := fwd.cross(Vector3.UP) * strafe_dir
		if d > 16.0: move = fwd * 0.9 + side * 0.5
		elif d < 7.0: move = -fwd * 0.6 + side * 0.8
		else: move = side
		p.bot_sprint = false
		p.aiming = d < 20.0
	elif has_objective:
		move = (objective - p.global_position)
		move.y = 0
		move = move.normalized()
		p.bot_sprint = p.global_position.distance_to(objective) > 12.0
		p.aiming = false
	move.y = 0
	p.bot_move = move.normalized() if move.length() > 0.1 else Vector3.ZERO
	# fire
	if target and fire_cd <= 0.0:
		fire_cd = randf_range(0.45, 0.8)
		_shoot()

func _shoot() -> void:
	p.flag_shot() # animation on every peer via the synced anim state
	var eye := p.global_position + EYE
	var to := target.global_position + Vector3(0, 1.15, 0) - eye
	var d := to.length()
	var spread := deg_to_rad(1.4 + d * 0.14 + (3.0 if p.bot_move.length() > 0.1 else 0.0))
	var dir := to.normalized().rotated(Vector3.UP, randf_range(-spread, spread))
	dir = dir.rotated(dir.cross(Vector3.UP).normalized(), randf_range(-spread, spread))
	var space := p.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(eye, eye + dir * 60.0, 1)
	ray.exclude = [p.get_rid()]
	var hit := space.intersect_ray(ray)
	if hit.has("collider") and hit.collider.has_method("net_hit"):
		hit.collider.net_hit(randf_range(11.0, 17.0), p.peer_id)
