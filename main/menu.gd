class_name Menu
extends Control
## LAN lobby: host or join by IP. Connection state lives here; match state lives in Game.

const PORT := 7777
const GameSettings = preload("res://main/settings.gd")
const Account = preload("res://main/account.gd")
static var my_name := ""
static var is_host := false
static var mode := "tdm" # "tdm" | "bomb"
static var bots := 4
static var map := "yard"

var name_edit: LineEdit
var ip_edit: LineEdit
var status: Label

var settings_panel: PanelContainer = null

func _ready() -> void:
	GameSettings.load_cfg()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var title := Label.new()
	title.text = "RANGE DAY 2  —  LAN TEAM DEATHMATCH"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_label("Your name"))
	name_edit = LineEdit.new()
	name_edit.text = my_name if my_name != "" else "Player%d" % (randi() % 900 + 100)
	name_edit.max_length = 16
	box.add_child(name_edit)
	box.add_child(_label("Host IP (to join)"))
	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.placeholder_text = "192.168.x.x"
	box.add_child(ip_edit)
	box.add_child(_label("Game mode (host picks)"))
	var mode_pick := OptionButton.new()
	mode_pick.add_item("Team Deathmatch", 0)
	mode_pick.add_item("Bomb Defusal", 1)
	mode_pick.selected = 1 if mode == "bomb" else 0
	mode_pick.item_selected.connect(func(i): mode = "bomb" if i == 1 else "tdm")
	box.add_child(mode_pick)
	box.add_child(_label("Map (host picks)"))
	var map_pick := OptionButton.new()
	map_pick.add_item("Yard", 0)
	map_pick.add_item("Compound", 1)
	map_pick.selected = 1 if map == "compound" else 0
	map_pick.item_selected.connect(func(i): map = "compound" if i == 1 else "yard")
	box.add_child(map_pick)
	var bot_row := HBoxContainer.new()
	var bot_lbl := Label.new()
	bot_lbl.text = "Robot players (host picks)"
	bot_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_row.add_child(bot_lbl)
	var bot_pick := SpinBox.new()
	bot_pick.min_value = 0
	bot_pick.max_value = 6
	bot_pick.value = bots
	bot_pick.value_changed.connect(func(v): bots = int(v))
	bot_row.add_child(bot_pick)
	box.add_child(bot_row)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var host_btn := Button.new()
	host_btn.text = "HOST GAME"
	host_btn.custom_minimum_size = Vector2(200, 44)
	host_btn.pressed.connect(_on_host)
	row.add_child(host_btn)
	var join_btn := Button.new()
	join_btn.text = "JOIN"
	join_btn.custom_minimum_size = Vector2(200, 44)
	join_btn.pressed.connect(_on_join)
	row.add_child(join_btn)
	var settings_btn := Button.new()
	settings_btn.text = "Settings"
	settings_btn.pressed.connect(_toggle_settings)
	box.add_child(settings_btn)
	var practice := Button.new()
	practice.text = "Practice range (offline)"
	practice.pressed.connect(func(): get_tree().change_scene_to_file("res://test/range.tscn"))
	box.add_child(practice)
	var ips: Array[String] = []
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			ips.append(a)
	box.add_child(_label("Your LAN IP (give this to friends): " + (", ".join(ips) if ips.size() > 0 else "not found")))
	box.add_child(_label("Port %d must be allowed through Windows Firewall on the host." % PORT))
	status = Label.new()
	status.modulate = Color(1, 0.85, 0.4)
	box.add_child(status)
	_build_account_ui()

var acc_box: PanelContainer = null

func _build_account_ui() -> void:
	if acc_box and is_instance_valid(acc_box): acc_box.queue_free()
	acc_box = PanelContainer.new()
	acc_box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	acc_box.position = Vector2(30, -240)
	acc_box.custom_minimum_size = Vector2(340, 0)
	add_child(acc_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	acc_box.add_child(v)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 20)
	v.add_child(title)
	if not Account.logged_in:
		title.text = "ACCOUNT — log in / register"
		var nm := LineEdit.new()
		nm.placeholder_text = "account name"
		v.add_child(nm)
		var pw := LineEdit.new()
		pw.placeholder_text = "password"
		pw.secret = true
		v.add_child(pw)
		var err := Label.new()
		err.modulate = Color(1, 0.5, 0.4)
		var btn := Button.new()
		btn.text = "LOG IN"
		btn.pressed.connect(func():
			var e := Account.login(nm.text, pw.text)
			if e == "": _build_account_ui()
			else: err.text = e)
		v.add_child(btn)
		v.add_child(err)
		v.add_child(_label("New name = new account. Kills earn coins,
coins open skin cases (%d each)." % Account.CASE_PRICE))
		return
	title.text = "%s   —   %d coins" % [Account.acc_name, Account.coins]
	var result := Label.new()
	result.add_theme_font_size_override("font_size", 18)
	var case_btn := Button.new()
	case_btn.text = "OPEN CASE  (%d coins)" % Account.CASE_PRICE
	case_btn.pressed.connect(func():
		var r: Array = Account.open_case()
		if r.is_empty():
			result.text = "not enough coins"
			result.modulate = Color(1, 0.5, 0.4)
		else:
			var info: Array = Account.SKINS[r[0]]
			result.text = "%s  (%s)%s" % [info[0], info[1], "  — duplicate, +%d coins" % Account.DUPE_REFUND if r[1] else "!"]
			result.modulate = Account.RARITY_COLORS[info[1]]
		_refresh_title(title))
	v.add_child(case_btn)
	v.add_child(result)
	v.add_child(_label("Your skins (click to equip):"))
	var grid := GridContainer.new()
	grid.columns = 2
	v.add_child(grid)
	_fill_skins(grid, title)
	if Account.is_admin:
		v.add_child(_label("— ADMIN —"))
		var pick := OptionButton.new()
		for id in Account.SKINS:
			pick.add_item("%s (%s)" % [Account.SKINS[id][0], Account.SKINS[id][1]])
		var gen := Button.new()
		gen.text = "GENERATE SKIN"
		gen.pressed.connect(func():
			Account.grant(Account.SKINS.keys()[pick.selected])
			_build_account_ui())
		v.add_child(pick)
		v.add_child(gen)
		var rich := Button.new()
		rich.text = "+1000 COINS"
		rich.pressed.connect(func():
			Account.add_coins(1000)
			_refresh_title(title))
		v.add_child(rich)
		v.add_child(_label("In game:  B = auto aim,  V = vision"))
	var out := Button.new()
	out.text = "Log out"
	out.pressed.connect(func():
		Account.logout()
		_build_account_ui())
	v.add_child(out)

func _refresh_title(title: Label) -> void:
	title.text = "%s   —   %d coins" % [Account.acc_name, Account.coins]

func _fill_skins(grid: GridContainer, title: Label) -> void:
	for c in grid.get_children(): c.queue_free()
	var none := Button.new()
	none.text = ("> " if Account.equipped == "" else "") + "No skin"
	none.pressed.connect(func():
		Account.equip("")
		_fill_skins(grid, title))
	grid.add_child(none)
	for id in Account.skins:
		var info: Array = Account.SKINS[id]
		var b := Button.new()
		b.text = ("> " if Account.equipped == id else "") + info[0]
		b.modulate = Account.RARITY_COLORS[info[1]]
		b.pressed.connect(func():
			Account.equip(id)
			_fill_skins(grid, title))
		grid.add_child(b)

func _toggle_settings() -> void:
	if settings_panel and is_instance_valid(settings_panel):
		settings_panel.queue_free()
		settings_panel = null
		return
	settings_panel = GameSettings.make_panel()
	settings_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	settings_panel.position = Vector2(-460, -180)
	add_child(settings_panel)

func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l

func _on_host() -> void:
	my_name = name_edit.text.strip_edges()
	if my_name == "": my_name = "Host"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 16)
	if err != OK:
		status.text = "Could not open port %d (error %d) — is another host running?" % [PORT, err]
		return
	multiplayer.multiplayer_peer = peer
	is_host = true
	get_tree().change_scene_to_file("res://main/Game.tscn")

func _on_join() -> void:
	my_name = name_edit.text.strip_edges()
	if my_name == "": my_name = "Player"
	var ip := ip_edit.text.strip_edges()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		status.text = "Bad address (error %d)" % err
		return
	multiplayer.multiplayer_peer = peer
	is_host = false
	status.text = "Connecting to %s ..." % ip
	multiplayer.connected_to_server.connect(_on_connected, CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(_on_failed, CONNECT_ONE_SHOT)

func _on_connected() -> void:
	get_tree().change_scene_to_file("res://main/Game.tscn")

func _on_failed() -> void:
	status.text = "Connection failed — check the IP and that the host is in the game."
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
