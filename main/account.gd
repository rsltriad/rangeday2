extends RefCounted
## Local accounts (per machine), coins, cases and weapon skins.
## Stored in user://accounts.cfg. The "admin" account (password "admin") can generate
## skins and unlocks hidden cheats in-game (B = auto aim, V = vision).

const PATH := "user://accounts.cfg"
const CASE_PRICE := 50
const COINS_PER_KILL := 10
const COINS_ROUND_WIN := 20
const DUPE_REFUND := 20

# id: [name, rarity, weight, tint color for the gun]
const SKINS := {
	"crimson":   ["Crimson",      "common",    22, Color(1.0, 0.25, 0.2)],
	"ocean":     ["Ocean",        "common",    22, Color(0.2, 0.55, 1.0)],
	"jungle":    ["Jungle",       "common",    22, Color(0.3, 0.85, 0.3)],
	"sand":      ["Desert Sand",  "common",    22, Color(0.9, 0.8, 0.45)],
	"violet":    ["Violet",       "rare",      12, Color(0.65, 0.3, 1.0)],
	"toxic":     ["Toxic",        "rare",      12, Color(0.55, 1.0, 0.1)],
	"sakura":    ["Sakura",       "rare",      12, Color(1.0, 0.55, 0.75)],
	"arctic":    ["Arctic",       "epic",       6, Color(0.75, 0.95, 1.0)],
	"midnight":  ["Midnight",     "epic",       6, Color(0.2, 0.2, 0.35)],
	"gold":      ["Gold",         "legendary",  2, Color(1.0, 0.85, 0.2)],
	"dragon":    ["Blood Dragon", "legendary",  2, Color(1.0, 0.1, 0.4)],
}
const RARITY_COLORS := {"common": Color(0.7, 0.7, 0.7), "rare": Color(0.35, 0.6, 1.0), "epic": Color(0.75, 0.4, 1.0), "legendary": Color(1.0, 0.75, 0.2)}

static var logged_in := false
static var acc_name := ""
static var is_admin := false
static var coins := 0
static var skins: Array = []
static var equipped := ""

static func _cfg() -> ConfigFile:
	var c := ConfigFile.new()
	c.load(PATH)
	return c

## Returns "" on success, else an error message.
static func login(nm: String, pass_word: String) -> String:
	nm = nm.strip_edges()
	if nm == "" or pass_word == "": return "enter a name and a password"
	var c := _cfg()
	var h := pass_word.sha256_text()
	if nm == "admin" and pass_word != "admin": return "wrong password"
	if c.has_section(nm):
		if c.get_value(nm, "pass") != h: return "wrong password"
	else:
		c.set_value(nm, "pass", h)
		c.set_value(nm, "coins", 100) # starter coins
		c.set_value(nm, "skins", [])
		c.set_value(nm, "equipped", "")
		c.save(PATH)
	logged_in = true
	acc_name = nm
	is_admin = nm == "admin"
	coins = c.get_value(nm, "coins", 100)
	skins = c.get_value(nm, "skins", [])
	equipped = c.get_value(nm, "equipped", "")
	return ""

static func logout() -> void:
	logged_in = false
	acc_name = ""
	is_admin = false
	coins = 0
	skins = []
	equipped = ""

static func save() -> void:
	if not logged_in: return
	var c := _cfg()
	c.set_value(acc_name, "coins", coins)
	c.set_value(acc_name, "skins", skins)
	c.set_value(acc_name, "equipped", equipped)
	c.save(PATH)

static func add_coins(n: int) -> void:
	if not logged_in: return
	coins += n
	save()

## Opens a case. Returns [skin_id, was_duplicate] or [] if it can't.
static func open_case() -> Array:
	if not logged_in or coins < CASE_PRICE: return []
	coins -= CASE_PRICE
	var total := 0
	for id in SKINS: total += SKINS[id][2]
	var roll := randi() % total
	var picked := ""
	for id in SKINS:
		roll -= SKINS[id][2]
		if roll < 0:
			picked = id
			break
	var dupe: bool = picked in skins
	if dupe: coins += DUPE_REFUND
	else: skins.append(picked)
	save()
	return [picked, dupe]

static func grant(id: String) -> void: # admin only
	if not is_admin or not SKINS.has(id): return
	if not (id in skins): skins.append(id)
	save()

static func equip(id: String) -> void:
	if id != "" and not (id in skins): return
	equipped = id
	save()

## Tints the gun parts of the current viewmodel weapon (local player only).
static func apply_weapon_skin(fps_hands: Node) -> void:
	if fps_hands == null or fps_hands.weapon == null: return
	var tint := Color.WHITE
	if logged_in and equipped != "" and SKINS.has(equipped):
		tint = SKINS[equipped][3]
	for mi in fps_hands.weapon.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null: continue
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(i)
			if m is ShaderMaterial and m.get_shader_parameter("albedo") != null:
				if m.resource_name.begins_with("arm"): continue # keep the hands
				if tint == Color.WHITE:
					mi.set_surface_override_material(i, null)
				else:
					var dup: ShaderMaterial = m.duplicate()
					dup.set_shader_parameter("albedo", tint)
					mi.set_surface_override_material(i, dup)
