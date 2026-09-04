extends Node
## Bomb defusal (CS-style, simplified). Server authoritative; lives at Game/Bomb.
## Attackers plant at A or B (hold E inside the site), defenders defuse (hold E next to it).

const FREEZE_TIME := 5.0
const ROUND_TIME := 120.0
const BOMB_TIME := 40.0
const PLANT_TIME := 3.0
const DEFUSE_TIME := 5.0
const ROUND_END_TIME := 6.0
const ROUNDS_TO_WIN := 4
const HALF_ROUNDS := 3 # sides swap after this many rounds
const SITE_RADIUS := 5.0
const DEFUSE_RADIUS := 2.5
const PICKUP_RADIUS := 1.6
const EXPLOSION_RADIUS := 14.0

var game: Node3D
var active := false
# replicated state
var phase := "wait" # wait | freeze | live | planted | end
var time_left := 0.0
var carrier := 0
var planted_site := ""
var bomb_pos := Vector3.ZERO
var bomb_on_ground := false
var wins := [0, 0]
var round_no := 0
var attack_team := 0
var progress_peer := 0
var progress_kind := ""
var progress := 0.0
# server only
var holding := {}
var _sync_t := 0.0
var _winner := -1
var _reason := ""

var bomb_mesh: Node3D
var site_nodes := {}
var bomb_label: Label
var bar: ProgressBar

func setup(g: Node3D) -> void:
	game = g
	active = true
	for k in game.sites():
		var n := Node3D.new()
		n.position = game.sites()[k]
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = SITE_RADIUS
		cyl.bottom_radius = SITE_RADIUS
		cyl.height = 0.08
		disc.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.55, 0.1, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		disc.material_override = mat
		disc.position.y = 0.05
		n.add_child(disc)
		var lbl := Label3D.new()
		lbl.text = "SITE " + k
		lbl.font_size = 160
		lbl.pixel_size = 0.01
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.modulate = Color(1.0, 0.6, 0.15)
		lbl.outline_size = 20
		lbl.position.y = 4.0
		n.add_child(lbl)
		game.add_child(n)
		site_nodes[k] = n
	bomb_mesh = Node3D.new()
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.35, 0.2, 0.25)
	box.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.15, 0.15, 0.15)
	box.material_override = bmat
	box.position.y = 0.1
	bomb_mesh.add_child(box)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.1, 0.1)
	light.omni_range = 3.0
	light.light_energy = 2.0
	light.position.y = 0.3
	light.name = "Light"
	bomb_mesh.add_child(light)
	var blabel := Label3D.new()
	blabel.text = "BOMB"
	blabel.font_size = 64
	blabel.pixel_size = 0.01
	blabel.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	blabel.no_depth_test = true
	blabel.modulate = Color(1, 0.3, 0.2)
	blabel.position.y = 0.8
	bomb_mesh.add_child(blabel)
	bomb_mesh.visible = false
	game.add_child(bomb_mesh)
	# HUD
	bomb_label = Label.new()
	bomb_label.add_theme_font_size_override("font_size", 24)
	bomb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bomb_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bomb_label.position = Vector2(-400, 56)
	bomb_label.size = Vector2(800, 60)
	game.hud.add_child(bomb_label)
	bar = ProgressBar.new()
	bar.set_anchors_preset(Control.PRESET_CENTER)
	bar.position = Vector2(-150, 60)
	bar.size = Vector2(300, 22)
	bar.max_value = 1.0
	bar.visible = false
	game.hud.add_child(bar)
	if multiplayer.is_server():
		wins = [0, 0]
		round_no = 0
		attack_team = 0
		get_tree().create_timer(2.0).timeout.connect(start_round)

func is_attacker(team: int) -> bool:
	return team == attack_team

# ---------------- server round flow ----------------
func start_round() -> void:
	if not multiplayer.is_server() or not active: return
	round_no += 1
	if round_no == HALF_ROUNDS + 1:
		attack_team = 1 - attack_team
		game.feed.rpc("Halftime — sides swap! %s now attacks" % game.TEAM_NAMES[attack_team])
	phase = "freeze"
	time_left = FREEZE_TIME
	planted_site = ""
	bomb_on_ground = false
	holding.clear()
	_clear_progress()
	var attackers := []
	for p in game.players_root.get_children():
		p.force_respawn.rpc(game.pick_spawn(p.team))
		p.set_frozen.rpc(true)
		p.set_bomb_carrier.rpc(false)
		if is_attacker(p.team): attackers.append(p)
	carrier = attackers[randi() % attackers.size()].peer_id if attackers.size() > 0 else 0
	if carrier != 0:
		game.players_root.get_node(str(carrier)).set_bomb_carrier.rpc(true)
	bomb_hide.rpc()
	game.feed.rpc("Round %d — %s attack" % [round_no, game.TEAM_NAMES[attack_team]])
	_broadcast()

func _process(delta: float) -> void:
	if not active: return
	if bomb_mesh.visible:
		bomb_mesh.get_node("Light").light_energy = 2.0 if fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.5 else 0.2
	_update_hud()
	if not multiplayer.is_server(): return
	_server_tick(delta)

func _server_tick(delta: float) -> void:
	match phase:
		"freeze":
			time_left -= delta
			if time_left <= 0.0:
				phase = "live"
				time_left = ROUND_TIME
				for p in game.players_root.get_children(): p.set_frozen.rpc(false)
				_broadcast()
		"live":
			time_left -= delta
			_check_pickup()
			_check_plant(delta)
			if phase == "live":
				var alive := _alive_counts()
				if alive[attack_team] == 0 and _count_team(attack_team) > 0: _end_round(1 - attack_team, "attackers eliminated")
				elif alive[1 - attack_team] == 0 and _count_team(1 - attack_team) > 0: _end_round(attack_team, "defenders eliminated")
				elif time_left <= 0.0: _end_round(1 - attack_team, "time ran out")
		"planted":
			time_left -= delta
			_check_defuse(delta)
			if phase == "planted":
				var alive := _alive_counts()
				if time_left <= 0.0: _explode()
				elif alive[1 - attack_team] == 0 and _count_team(1 - attack_team) > 0: _end_round(attack_team, "defenders eliminated")
		"end":
			time_left -= delta
			if time_left <= 0.0:
				if _winner >= 0 and wins[_winner] >= ROUNDS_TO_WIN:
					game.show_winner.rpc(_winner)
					wins = [0, 0]
					round_no = 0
					attack_team = 0
					phase = "wait"
					time_left = 8.0
					_broadcast()
					get_tree().create_timer(8.0).timeout.connect(start_round)
				else:
					start_round()
	_sync_t += delta
	if _sync_t >= 0.5:
		_sync_t = 0.0
		_broadcast()

func _count_team(team: int) -> int:
	var n := 0
	for p in game.players_root.get_children():
		if p.team == team: n += 1
	return n

func _alive_counts() -> Array:
	var a := [0, 0]
	for p in game.players_root.get_children():
		if not p.dead: a[p.team] += 1
	return a

func _player(id: int) -> Node:
	return game.players_root.get_node_or_null(str(id))

func _check_pickup() -> void:
	if not bomb_on_ground: return
	for p in game.players_root.get_children():
		if not p.dead and is_attacker(p.team) and p.global_position.distance_to(bomb_pos) < PICKUP_RADIUS:
			bomb_on_ground = false
			carrier = p.peer_id
			p.set_bomb_carrier.rpc(true)
			bomb_hide.rpc()
			game.feed.rpc("%s picked up the bomb" % p.pname)
			_broadcast()
			return

func on_player_died(p: Node) -> void: # called by game.report_kill on the server
	if not active or phase == "wait" or phase == "end": return
	if p.peer_id == carrier and phase == "live":
		carrier = 0
		bomb_on_ground = true
		bomb_pos = p.global_position
		p.set_bomb_carrier.rpc(false)
		bomb_show.rpc(bomb_pos)
		game.feed.rpc("%s dropped the bomb" % p.pname)
		_broadcast()

func _site_at(pos: Vector3) -> String:
	for k in game.sites():
		var s: Vector3 = game.sites()[k]
		if Vector2(pos.x - s.x, pos.z - s.z).length() < SITE_RADIUS and absf(pos.y - s.y) < 4.0:
			return k
	return ""

func _check_plant(delta: float) -> void:
	var p := _player(carrier)
	if p == null or p.dead or not holding.get(carrier, false):
		if progress_kind == "plant": _clear_progress()
		return
	var site := _site_at(p.global_position)
	if site == "":
		if progress_kind == "plant": _clear_progress()
		return
	progress_peer = carrier
	progress_kind = "plant"
	progress += delta / PLANT_TIME
	if progress >= 1.0:
		phase = "planted"
		time_left = BOMB_TIME
		planted_site = site
		bomb_pos = p.global_position
		carrier = 0
		p.set_bomb_carrier.rpc(false)
		bomb_show.rpc(bomb_pos)
		game.feed.rpc("%s planted the bomb at %s" % [p.pname, site])
		_clear_progress()
		holding.clear()
	_broadcast_progress()

func _check_defuse(delta: float) -> void:
	var defuser: Node = null
	for id in holding:
		if not holding[id]: continue
		var p := _player(id)
		if p and not p.dead and not is_attacker(p.team) and p.global_position.distance_to(bomb_pos) < DEFUSE_RADIUS:
			defuser = p
			break
	if defuser == null:
		if progress_kind == "defuse": _clear_progress()
		return
	if progress_peer != defuser.peer_id: progress = 0.0
	progress_peer = defuser.peer_id
	progress_kind = "defuse"
	progress += delta / DEFUSE_TIME
	if progress >= 1.0:
		game.feed.rpc("%s defused the bomb" % defuser.pname)
		bomb_hide.rpc()
		_clear_progress()
		_end_round(1 - attack_team, "bomb defused")
	_broadcast_progress()

func _explode() -> void:
	explosion.rpc(bomb_pos)
	for p in game.players_root.get_children():
		if not p.dead and p.global_position.distance_to(bomb_pos) < EXPLOSION_RADIUS:
			p.hp = 0.0
			p.set_state.rpc(0.0, true, 0)
			game.report_kill(p.peer_id, 0)
	_end_round(attack_team, "bomb exploded")

func _end_round(winner: int, reason: String) -> void:
	if phase == "end": return
	phase = "end"
	time_left = ROUND_END_TIME
	_winner = winner
	_reason = reason
	wins[winner] += 1
	holding.clear()
	_clear_progress()
	round_over.rpc(winner, reason, wins)
	_broadcast()

func _clear_progress() -> void:
	progress = 0.0
	progress_kind = ""
	progress_peer = 0
	_broadcast_progress()

func _broadcast() -> void:
	sync_bomb.rpc(phase, time_left, carrier, planted_site, bomb_pos, bomb_on_ground, wins, round_no, attack_team)

func _broadcast_progress() -> void:
	sync_progress.rpc(progress_peer, progress_kind, progress)

# ---------------- rpcs ----------------
@rpc("any_peer", "reliable")
func interact(pressed: bool) -> void:
	if not multiplayer.is_server(): return
	holding[multiplayer.get_remote_sender_id()] = pressed

func interact_from(id: int, pressed: bool) -> void:
	holding[id] = pressed

@rpc("authority", "call_local", "unreliable_ordered")
func sync_bomb(p: String, t: float, c: int, site: String, bpos: Vector3, on_ground: bool, w: Array, rn: int, at: int) -> void:
	phase = p
	time_left = t
	carrier = c
	planted_site = site
	bomb_pos = bpos
	bomb_on_ground = on_ground
	wins = w
	round_no = rn
	attack_team = at

@rpc("authority", "call_local", "unreliable_ordered")
func sync_progress(peer: int, kind: String, frac: float) -> void:
	progress_peer = peer
	progress_kind = kind
	progress = frac

@rpc("authority", "call_local", "reliable")
func bomb_show(pos: Vector3) -> void:
	bomb_mesh.global_position = pos
	bomb_mesh.visible = true

@rpc("authority", "call_local", "reliable")
func bomb_hide() -> void:
	bomb_mesh.visible = false

const Account := preload("res://main/account.gd")

@rpc("authority", "call_local", "reliable")
func round_over(winner: int, reason: String, w: Array) -> void:
	wins = w
	var me = _player(multiplayer.get_unique_id())
	if me and me.team == winner and Account.logged_in:
		Account.add_coins(Account.COINS_ROUND_WIN)
	game.center_label.modulate = game.TEAM_COLORS[winner]
	game.center_label.text = "%s WIN THE ROUND\n%s" % [game.TEAM_NAMES[winner], reason]
	get_tree().create_timer(ROUND_END_TIME - 0.5).timeout.connect(func(): if game.center_label.text.ends_with(reason): game.center_label.text = "")

@rpc("authority", "call_local", "reliable")
func explosion(pos: Vector3) -> void:
	bomb_mesh.visible = false
	var fx := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = EXPLOSION_RADIUS * 0.5
	sph.height = EXPLOSION_RADIUS
	fx.mesh = sph
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 0.5, 0.1, 0.6)
	m.emission_enabled = true
	m.emission = Color(1, 0.4, 0.05)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fx.material_override = m
	fx.position = pos
	game.add_child(fx)
	var tw := fx.create_tween()
	tw.tween_property(fx, "scale", Vector3(2, 2, 2), 0.8)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.8)
	tw.tween_callback(fx.queue_free)

# ---------------- HUD ----------------
func _update_hud() -> void:
	var me := _player(multiplayer.get_unique_id())
	var mm := int(time_left) / 60
	var ss := int(time_left) % 60
	var role := ""
	if me:
		role = "  (you %s)" % ("attack" if is_attacker(me.team) else "defend")
	game.score_label.text = "R%d   RED %d  -  %d BLUE   %d:%02d" % [round_no, wins[0], wins[1], mm, ss]
	var txt := ""
	match phase:
		"wait": txt = "Waiting for the next match..."
		"freeze": txt = "Round starting..." + role
		"live":
			if me and me.peer_id == carrier: txt = "You have the BOMB — go to SITE A or B and hold E"
			elif bomb_on_ground and me and is_attacker(me.team): txt = "Bomb dropped — pick it up"
			elif me and is_attacker(me.team): txt = "Protect the bomb carrier" + role
			else: txt = "Stop the plant" + role
		"planted":
			txt = "BOMB PLANTED at %s — %d s" % [planted_site, int(ceil(time_left))]
			if me and not is_attacker(me.team): txt += "   (hold E at the bomb to defuse)"
		"end": txt = ""
	if me and me.dead and phase != "end" and phase != "wait":
		txt = "You are dead — waiting for the round to end"
	bomb_label.text = txt
	bomb_label.modulate = Color(1, 0.35, 0.3) if phase == "planted" else Color.WHITE
	bar.visible = progress_kind != "" and progress > 0.0
	bar.value = progress
