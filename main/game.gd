extends Node3D
## Team deathmatch match: players, teams, kills, spawns, HUD. Server (host) is authoritative.

const KILLS_TO_WIN := 30
const RESPAWN_TIME := 4.0
const TEAM_NAMES := ["RED", "BLUE"]
const TEAM_COLORS := [Color(0.9, 0.25, 0.2), Color(0.25, 0.5, 1.0)]
const NetPlayerScene := preload("res://main/NetPlayer.tscn")
const MenuScript := preload("res://main/menu.gd")
# Two ends of the yard (map is 50 x 100 m, long axis = Z).
const SPAWNS := [
	[Vector3(-12, 1.5, 40), Vector3(-6, 1.5, 40), Vector3(0, 1.5, 40), Vector3(6, 1.5, 40), Vector3(12, 1.5, 40)],
	[Vector3(-12, 1.5, -40), Vector3(-6, 1.5, -40), Vector3(0, 1.5, -40), Vector3(6, 1.5, -40), Vector3(12, 1.5, -40)],
]

var players := {} # peer_id -> {name, team, kills, deaths}
var scores := [0, 0]
var match_over := false

@onready var players_root: Node3D = $Players
var hud: CanvasLayer
var score_label: Label
var feed_box: VBoxContainer
var hp_label: Label
var center_label: Label
var board: PanelContainer
var board_text: RichTextLabel
var pause_panel: PanelContainer
var paused := false

func _ready() -> void:
	_build_map_collision()
	_build_hud()
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	print("[game] ready as peer ", multiplayer.get_unique_id(), " server=", multiplayer.is_server(), " peers=", multiplayer.get_peers())
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(id): print("[game] peer connected ", id))
		_register(1, MenuScript.my_name)
	else:
		register.rpc_id(1, MenuScript.my_name)

# ---------- map ----------
func _build_map_collision() -> void:
	for mi in $Map.find_children("*", "MeshInstance3D", true, false):
		mi.create_trimesh_collision()

func pick_spawn(team: int) -> Vector3:
	var list: Array = SPAWNS[clampi(team, 0, 1)]
	return list[randi() % list.size()]

# ---------- players / teams (server) ----------
@rpc("any_peer", "reliable")
func register(pname: String) -> void:
	if not multiplayer.is_server(): return
	_register(multiplayer.get_remote_sender_id(), pname)

func _register(id: int, pname: String) -> void:
	print("[game] register ", id, " ", pname)
	if players.has(id): return
	var a := 0
	var b := 0
	for p in players.values():
		if p.team == 0: a += 1
		else: b += 1
	var team := 0 if a <= b else 1
	players[id] = {"name": pname, "team": team, "kills": 0, "deaths": 0}
	sync_state.rpc(players, scores, match_over)
	feed.rpc("%s joined %s" % [pname, TEAM_NAMES[team]])
	# Late joiner learns about everyone already in the match.
	if id != 1:
		for p in players_root.get_children():
			spawn_player.rpc_id(id, p.peer_id, p.team, p.position, p.pname)
	spawn_player.rpc(id, team, pick_spawn(team), pname)

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server(): return
	if players.has(id):
		feed.rpc("%s left" % players[id].name)
		players.erase(id)
		sync_state.rpc(players, scores, match_over)
	despawn_player.rpc(id)

func same_team(a: int, b: int) -> bool:
	return players.has(a) and players.has(b) and players[a].team == players[b].team

func report_kill(victim: int, killer: int) -> void: # server
	if not players.has(victim): return
	players[victim].deaths += 1
	var vname: String = players[victim].name
	if killer != victim and players.has(killer):
		players[killer].kills += 1
		scores[players[killer].team] += 1
		feed.rpc("%s killed %s" % [players[killer].name, vname])
	else:
		feed.rpc("%s died" % vname)
	sync_state.rpc(players, scores, match_over)
	if not match_over:
		for t in 2:
			if scores[t] >= KILLS_TO_WIN:
				match_over = true
				show_winner.rpc(t)
				get_tree().create_timer(8.0).timeout.connect(_restart_match)

func _restart_match() -> void: # server
	scores = [0, 0]
	for p in players.values():
		p.kills = 0
		p.deaths = 0
	match_over = false
	sync_state.rpc(players, scores, match_over)
	feed.rpc("New match!")
	for p in players_root.get_children():
		p.force_respawn.rpc(pick_spawn(p.team))

# ---------- replicated to everyone ----------
@rpc("authority", "call_local", "reliable")
func sync_state(p: Dictionary, s: Array, over: bool) -> void:
	players = p
	scores = s
	match_over = over
	_refresh_hud()

@rpc("authority", "call_local", "reliable")
func feed(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	feed_box.add_child(l)
	while feed_box.get_child_count() > 6:
		feed_box.get_child(0).free()
	get_tree().create_timer(6.0).timeout.connect(func(): if is_instance_valid(l): l.queue_free())

@rpc("authority", "call_local", "reliable")
func spawn_player(id: int, team: int, pos: Vector3, pname: String) -> void:
	if players_root.has_node(str(id)): return
	var p := NetPlayerScene.instantiate()
	p.name = str(id)
	p.team = team
	p.pname = pname
	p.position = pos
	players_root.add_child(p)
	if id == multiplayer.get_unique_id():
		p.local_died.connect(_on_local_died)
		p.local_hp_changed.connect(func(h): hp_label.text = "HP %d" % int(h))
		p.local_respawned.connect(func(): center_label.text = "")

@rpc("authority", "call_local", "reliable")
func despawn_player(id: int) -> void:
	var n := players_root.get_node_or_null(str(id))
	if n: n.queue_free()

@rpc("authority", "call_local", "reliable")
func show_winner(team: int) -> void:
	center_label.text = "%s TEAM WINS\nnew match in a few seconds" % TEAM_NAMES[team]
	center_label.modulate = TEAM_COLORS[team]

# ---------- HUD ----------
func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 5
	add_child(hud)
	score_label = Label.new()
	score_label.add_theme_font_size_override("font_size", 30)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	score_label.position = Vector2(-200, 12)
	score_label.size = Vector2(400, 40)
	hud.add_child(score_label)
	feed_box = VBoxContainer.new()
	feed_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	feed_box.position = Vector2(-330, 16)
	feed_box.size = Vector2(320, 200)
	hud.add_child(feed_box)
	hp_label = Label.new()
	hp_label.text = "HP 100"
	hp_label.add_theme_font_size_override("font_size", 34)
	hp_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hp_label.position = Vector2(24, -70)
	hud.add_child(hp_label)
	center_label = Label.new()
	center_label.add_theme_font_size_override("font_size", 40)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.set_anchors_preset(Control.PRESET_CENTER)
	center_label.position = Vector2(-400, -140)
	center_label.size = Vector2(800, 120)
	hud.add_child(center_label)
	board = PanelContainer.new()
	board.set_anchors_preset(Control.PRESET_CENTER)
	board.position = Vector2(-300, -200)
	board.size = Vector2(600, 400)
	board.visible = false
	board_text = RichTextLabel.new()
	board_text.bbcode_enabled = true
	board_text.custom_minimum_size = Vector2(600, 400)
	board.add_child(board_text)
	hud.add_child(board)
	pause_panel = PanelContainer.new()
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.position = Vector2(-160, -80)
	pause_panel.size = Vector2(320, 160)
	pause_panel.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pause_panel.add_child(v)
	var t := Label.new()
	t.text = "PAUSED  (Esc to resume)"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(_set_paused.bind(false))
	v.add_child(resume)
	var leave := Button.new()
	leave.text = "Leave match"
	leave.pressed.connect(_leave)
	v.add_child(leave)
	hud.add_child(pause_panel)
	var hint := Label.new()
	hint.text = "TAB scoreboard   ESC menu"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.position = Vector2(-240, -34)
	hud.add_child(hint)
	_refresh_hud()

func _refresh_hud() -> void:
	score_label.text = "[color=#e64d40]RED %d[/color]   %d BLUE" % [scores[0], scores[1]]
	score_label.text = "RED %d   -   %d BLUE" % [scores[0], scores[1]]
	var txt := ""
	for t in 2:
		txt += "[color=#%s][b]%s  %d[/b][/color]\n" % [TEAM_COLORS[t].to_html(false), TEAM_NAMES[t], scores[t]]
		for id in players:
			var p = players[id]
			if p.team == t:
				txt += "   %-16s  K %d   D %d\n" % [p.name, p.kills, p.deaths]
		txt += "\n"
	board_text.text = txt

func _on_local_died(killer_id: int) -> void:
	var who := "yourself"
	if players.has(killer_id) and killer_id != multiplayer.get_unique_id():
		who = players[killer_id].name
	center_label.modulate = Color.WHITE
	center_label.text = "Killed by %s\nrespawning..." % who

func _process(_delta: float) -> void:
	board.visible = Input.is_key_pressed(KEY_TAB)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_set_paused(not paused)

func _set_paused(v: bool) -> void:
	paused = v
	pause_panel.visible = v
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if v else Input.MOUSE_MODE_CAPTURED)
	var me := players_root.get_node_or_null(str(multiplayer.get_unique_id()))
	if me: me.set_input_blocked(v)

func _leave() -> void:
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().change_scene_to_file("res://main/Menu.tscn")

func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().change_scene_to_file("res://main/Menu.tscn")
