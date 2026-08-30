class_name Menu
extends Control
## LAN lobby: host or join by IP. Connection state lives here; match state lives in Game.

const PORT := 7777
static var my_name := ""
static var is_host := false
static var mode := "tdm" # "tdm" | "bomb"

var name_edit: LineEdit
var ip_edit: LineEdit
var status: Label

func _ready() -> void:
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
	mode_pick.add_item("Team Deathmatch  —  Yard", 0)
	mode_pick.add_item("Bomb Defusal  —  Compound", 1)
	mode_pick.selected = 1 if mode == "bomb" else 0
	mode_pick.item_selected.connect(func(i): mode = "bomb" if i == 1 else "tdm")
	box.add_child(mode_pick)
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
