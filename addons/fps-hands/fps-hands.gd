@icon("icon.svg")
extends Node3D

signal give_damage(obj:Node3D, damage:float, point:Vector3)
signal update_ammo(magazine:int, inventory_ammo:int, ammo_type:String)
signal aiming(ads:bool)
signal firing()
signal reloading()
signal meleeing()
signal taking_weapon()

#region Export vars
@export var inventory : Dictionary = {
	"weapons" = [[0,-1],],
	"ammo" = {
		"none" = 0,
		"9mm" = 0,
		"rifle" = 0,
		"shell" = 0,
	},
}
@export var melee_damage : float = 100
@export var left_handed : bool = false
@export var realistic_reloading : bool = false
@export var auto_reload : bool = false
@export var show_muzzle_smoke : bool = true
@export var breath_while_ads : bool = true
@export_flags_3d_physics var collision_mask = 1
@export_group("Camera")
@export var camera : Camera3D
@export var ads_dynamic_fov : bool = true
## Viewmodel (gun + sight) FOV used by the weapon shaders at the hip / when aiming.
## Lower ADS value = the sight fills more of the screen.
@export var viewmodel_fov : float = 70.0
@export var ads_viewmodel_fov : float = 42.0
@export var recoil : bool = true
@export_subgroup("Recoil configs")
## What to rotate on X axis with recoil (most of the time the camera)
@export var node_recoil_x : Node3D
## What to rotate on Y axis with recoil (most of the time the character)
@export var node_recoil_y : Node3D
## How many seconds recoil have to be
@export var recoil_time : float = .2
@export var recoil_x_clamp_max : float = 1.4
@export var recoil_x_clamp_min : float = -1.4
@export_subgroup("")
@export var sway : bool = true
@export_subgroup("Sway configs")
@export var sway_look_sens : float = 50.0
@export var sway_move_sens : float = 80.0
@export_subgroup("")
@export var shake : bool = true
@export_subgroup("Shake configs")
@export var shake_strength : float = 0.5
@export var shake_decay : float = 3.0
@export var shake_max_offset := Vector2(.01, .01)
@export var shake_max_roll : float = 0.01
@export_group("Multipliers")
@export var delta_multiplier : float = 1.0
@export var damage_multiplier : float = 1.0
@export_group("Actions")
@export var action_fire : String = "fire"
@export var action_reload : String = "reload"
@export var action_melee : String = "melee"
@export var action_ads : String = "aim"
@export var action_next_weapon : String = "next_weapon"
@export var action_previous_weapon : String = "previous_weapon"
#endregion

# Plugin scene nodes
var FireRayCast : RayCast3D
var MeleeRayCast : RayCast3D

var bulletholeScene : PackedScene = preload("decals/bullethole/bullethole.tscn")
var scratchScene : PackedScene = preload("decals/scratch/scratch.tscn")
var muzzleFlashScene : PackedScene = preload("muzzleflash/MuzzleFlash.tscn")
var muzzleSmokeScene : PackedScene = preload("muzzlesmoke/MuzzleSmoke.tscn")
var bulletScene : PackedScene = preload("res://addons/fps-hands/bullet/bullet.tscn")

var weapons : Array[PackedScene] = [
	preload("fps-knife/fps-knife.tscn"),
	preload("fps-c19/fps-c19.tscn"),
	preload("fps-smg45/fps-smg45.tscn"),
	preload("fps-ak/fps-ak.tscn"),
	preload("fps-lmg63/fps-lmg63.tscn"),
	preload("fps-sawnoff/fps-sawnoff.tscn"),
]
var weapon_index : int # current weapon index
var weapon_change : int # weapon to take after hide weapon
var weapon : Node3D
var animation : AnimationTree
var state_machine : AnimationNodeStateMachinePlayback
var idle_anim_speed : float
var muzzlePoint : Node3D

var start_pos : Vector3
var ads_pos : Vector3
var ads_target : Vector3 # ads_pos corrected so the sight's AimPoint sits on the camera axis
var aim_point : Node3D = null
var vm_materials : Array[ShaderMaterial] = []
var vm_fov : float = 70.0
var ads : bool = false
var start_fov : float

var max_magazine : int
var magazine : int

var sway_rotation_target : Vector3
var recoiling : Vector2 = Vector2.ZERO
var recoil_target : Vector2
var recoil_to_left : bool = false
var shake_current : float = 0.0

# Add nodes and settings to plugin scene
func _enter_tree() -> void:
	MeleeRayCast = RayCast3D.new()
	MeleeRayCast.target_position = Vector3(0, 0, 1/scale.z)
	MeleeRayCast.collision_mask = collision_mask
	MeleeRayCast.exclude_parent = true
	add_child(MeleeRayCast)
	
	FireRayCast = RayCast3D.new()
	FireRayCast.target_position = Vector3(0,0,0)
	FireRayCast.collision_mask = collision_mask
	FireRayCast.exclude_parent = true
	add_child(FireRayCast)


func _ready() -> void:
	if sway and camera:
		top_level = true
	if ads_dynamic_fov and camera:
		start_fov = camera.fov
	take_weapon(0)


func _set_vm_fov(v:float) -> void:
	vm_fov = v
	for m in vm_materials:
		m.set_shader_parameter("fov", v)

func _travel(state:String) -> void:
	if animation:
		animation.process_mode = Node.PROCESS_MODE_INHERIT
	state_machine.travel(state)

func update_inventory():
	inventory["weapons"][weapon_index][1] = magazine
	update_ammo.emit(magazine, inventory["ammo"][weapon.get_meta("ammo_type", "none")], weapon.get_meta("ammo_type", "none"))

func aim(toggle:bool=true) -> void:
	if toggle and (state_machine.get_current_node() != "idle" and state_machine.get_current_node() != "fire"):
		return
	
	if !ads and toggle:
		ads = true
	elif ads:
		ads = false
	
	aiming.emit(ads)

func reload() -> void:
	if inventory["ammo"][weapon.get_meta("ammo_type", "none")] > 0:
		if magazine > 0 and "reload_full" in animation.get_animation_list():
			_travel("reload_full")
		else:
			_travel("reload")

func add_decal(pos:Vector3, normal:Vector3, decal:PackedScene, father:Node3D) -> void:
	var bullethole : Decal = decal.instantiate()
	father.add_child(bullethole)
	bullethole.global_position = pos
	if normal != Vector3.UP:
		bullethole.look_at(pos + Vector3.UP, normal)
	bullethole.rotate(normal, randf_range(0, 2*PI))

func melee_attack(raycast:RayCast3D, damage:float) -> void:
	var collider = raycast.get_collider()
	if collider != null:
		damage *= damage_multiplier
		
		if collider is RigidBody3D or collider is CharacterBody3D:
			give_damage.emit(collider, damage, raycast.get_collision_point())
		
		if not (collider is CharacterBody3D):
			add_decal(raycast.get_collision_point(), raycast.get_collision_normal(), scratchScene, collider)

#region Gun fire mechanics
func _on_bullet_collision(obj:Node3D, damage:float, point:Vector3, collision_normal:Vector3) -> void:
	if obj is RigidBody3D or obj is CharacterBody3D:
		give_damage.emit(obj, damage*damage_multiplier, point)
	if not (obj is CharacterBody3D):
		add_decal(point, collision_normal, bulletholeScene, obj)

func fire_bullet(look_at_dir:Vector3, damage:float) -> void:
	if muzzlePoint:
		var bullet_instance : Node3D = bulletScene.instantiate()
		bullet_instance.position = muzzlePoint.global_position
		bullet_instance.transform.basis = get_parent().global_transform.basis
		bullet_instance.damage = damage
		bullet_instance.distance = weapon.get_meta("range")
		bullet_instance.collision_mask = collision_mask
		bullet_instance.connect("collision", _on_bullet_collision)
		
		bullet_instance.look_at_from_position(muzzlePoint.global_position, look_at_dir, Vector3.UP)
		
		get_tree().root.add_child(bullet_instance)

func random_direction_in_cone(forward:Vector3, max_angle_deg:float) -> Vector3:
	var max_angle_rad = deg_to_rad(max_angle_deg)
	var axis = forward.normalized()
	
	# Basis vector creation
	var basis_1: Vector3
	var basis_2: Vector3
	if abs(axis.dot(Vector3.UP)) > 0.99:
		basis_1 = Vector3.RIGHT
		basis_2 = Vector3.FORWARD
	else:
		basis_1 = axis.cross(Vector3.UP).normalized()
		basis_2 = axis.cross(basis_1).normalized()
	
	# Random angle generation
	var cos_theta = cos(max_angle_rad) + (1.0 - cos(max_angle_rad)) * randf()
	var sin_theta = sqrt(1.0 - cos_theta * cos_theta)
	var phi = randf() * TAU
	
	# Component calculations
	var x = sin_theta * cos(phi)
	var y = sin_theta * sin(phi)
	
	# Final vector construction
	var result = (axis * cos_theta + basis_1 * x + basis_2 * y).normalized()
	
	return result

func fire_spread(raycast:RayCast3D, bullets_count:int, spread_deg:float, damage:float) -> void:
	var ray_origin = raycast.global_transform.origin
	var ray_forward = raycast.global_transform.basis.z.normalized()
	var distance: float
	var dir : Vector3
	
	# Aim at the center of the screen
	if raycast.is_colliding():
		distance = raycast.global_position.distance_to(raycast.get_collision_point())
	else:
		distance = 100.0
	
	for i in bullets_count:
		dir = random_direction_in_cone(ray_forward, spread_deg)
		fire_bullet(ray_origin + dir * distance, damage)

func fire_single(raycast:RayCast3D, spread_deg:float, multiplier:float, damage:float) -> void:
	var ray_forward: Vector3 = raycast.global_transform.basis.z.normalized()
	var ray_up: Vector3      = raycast.global_transform.basis.y.normalized()
	var ray_right: Vector3   = -raycast.global_transform.basis.x.normalized()
	var distance: float
	# Random offsets
	var offset_x = randf_range(-spread_deg, spread_deg) * multiplier
	var offset_y = randf_range(-spread_deg, spread_deg) * multiplier
	
	var dir = ray_forward.rotated(ray_up, deg_to_rad(offset_x))
	dir = dir.rotated(ray_right, deg_to_rad(offset_y)).normalized()
	
	# Aim at the center of the screen
	if raycast.is_colliding():
		distance = raycast.global_position.distance_to(raycast.get_collision_point())
	else:
		distance = 100.0
	
	fire_bullet(raycast.global_transform.origin + dir * distance, damage)

func fire_bullet_calculate(raycast:RayCast3D, damage:float) -> void:
	var bullets_to_fire = weapon.get_meta("bullet_count", 1)
	damage /= bullets_to_fire
	
	if bullets_to_fire > 1:
		var spread_deg = weapon.get_meta("spread", 10.0)
		var mult = 0.6 if ads else 1.0
		fire_spread(raycast, bullets_to_fire, spread_deg * mult, damage)
	else:
		var spread_deg = weapon.get_meta("spread", 1.0)
		var mult = 0.1 if ads else 1.0
		fire_single(raycast, spread_deg, mult, damage)
#endregion

func muzzle_flash():
	if muzzlePoint:
		var muzzleFlash : Node3D = muzzleFlashScene.instantiate()
		muzzleFlash.resize(scale)
		muzzlePoint.add_child(muzzleFlash)

func muzzle_smoke():
	if muzzlePoint and show_muzzle_smoke:
		var muzzleSmoke : Node3D = muzzleSmokeScene.instantiate()
		muzzleSmoke.resize(scale)
		muzzlePoint.add_child(muzzleSmoke)

func add_recoil():
	if recoil and weapon.get_meta("recoil_x",0)+weapon.get_meta("recoil_y",0)>0:
		recoiling = Vector2(recoil_time, recoil_time)
		
		var recoil_x:float = randf_range(weapon.get_meta("recoil_x",0)*.2, weapon.get_meta("recoil_x",0))
		var recoil_y:float = randf_range(-weapon.get_meta("recoil_y",0), weapon.get_meta("recoil_y",0))
		
		recoil_target.x = clampf(node_recoil_x.rotation.x + recoil_x, recoil_x_clamp_min, recoil_x_clamp_max)
		recoil_target.y = node_recoil_y.rotation.y + recoil_y
		
		if recoil_y >= 0:
			recoil_to_left = true
		else:
			recoil_to_left = false

func add_camera_shake(amount:float):
	if shake and camera and weapon.get_meta("recoil_x",0)+weapon.get_meta("recoil_y",0)>0:
		shake_current = min(shake_current+amount, 1.0)

func camera_shake():
	if shake and camera:
		var amount = pow(shake_current, 2)
		if ads:
			amount *= 0.3
		camera.rotation.z = shake_max_roll * amount * randf_range(-1, 1)
		camera.h_offset = shake_max_offset.x * amount * randf_range(-1, 1)
		camera.v_offset = shake_max_offset.y * amount * randf_range(-1, 1)
		
		# Tune weapon shake based on size (which changes distance from camera)
		# We are using global_position beacuse of top_level
		global_position = to_global(Vector3(
			to_local(global_position).x - camera.h_offset - (camera.h_offset * scale.x),
			to_local(global_position).y + camera.v_offset - (camera.v_offset * scale.y),
			to_local(global_position).z
		))

func take_weapon(inventory_index:int) -> void:
	inventory_index = wrapi(inventory_index, 0, inventory["weapons"].size())
	var inventory_weapon = inventory["weapons"][inventory_index]
	var index = inventory_weapon[0] # Weapon index of weapons array
	index = clampi(index, 0, weapons.size()-1)
	
	# Add weapon to scene in there is none
	if !weapon or !weapon.is_inside_tree():
		weapon = weapons[index].instantiate()
		weapon.visible = false # avoid first frame in wrong position
		if left_handed:
			weapon.position.x = -weapon.position.x
			weapon.scale.x = -weapon.scale.x
		add_child(weapon)
	# If it's the same as the current weapon, do nothing
	elif weapon_index == inventory_index:
		return
	# If there is already a weapon, hide it then change it
	else:
		weapon_change = inventory_index
		_travel("hide")
		return
	
	weapon_index = inventory_index
	weapon_change = inventory_index
	animation = weapon.get_node("AnimationTree")
	state_machine = animation["parameters/playback"]
	idle_anim_speed = animation.tree_root.get_node("idle").timeline_length
	muzzlePoint = weapon.find_child("MuzzlePoint")
	
	start_pos = weapon.position
	ads_pos = weapon.get_meta("ads_pos", start_pos)
	ads_target = ads_pos
	aim_point = weapon.find_child("AimPoint", true, false)
	vm_materials.clear()
	for mi in weapon.find_children("*", "MeshInstance3D", true, false):
		if mi.material_override is ShaderMaterial and mi.material_override.get_shader_parameter("fov") != null:
			vm_materials.append(mi.material_override)
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var m = mi.get_active_material(i)
				if m is ShaderMaterial and m.get_shader_parameter("fov") != null and not vm_materials.has(m):
					vm_materials.append(m)
	_set_vm_fov(vm_fov)
	
	max_magazine = weapon.get_meta("max_magazine",0)
	magazine = inventory_weapon[1]
	if magazine == -1:
		magazine = max_magazine
	update_inventory()
	
	FireRayCast.target_position.z = weapon.get_meta("range") / scale.z
	
	animation.connect("animation_finished", _on_animation_tree_animation_finished)
	animation.connect("animation_started", _on_animation_tree_animation_started)

func hide_weapon() -> void:
	animation.disconnect("animation_finished", _on_animation_tree_animation_finished)
	animation.disconnect("animation_started", _on_animation_tree_animation_started)
	if weapon_change != weapon_index:
		weapon.connect("tree_exited", take_weapon.bind(weapon_change))
	weapon.queue_free()

func _input(_event) -> void:
	if weapon != null:
		# Single fire
		if !weapon.get_meta("auto", false):
			if Input.is_action_just_pressed(action_fire) and (magazine > 0 or max_magazine == 0):
				_travel("fire")
			elif auto_reload and Input.is_action_just_pressed(action_fire) and magazine == 0 and max_magazine > 0:
				reload()
		
		# Actions
		if Input.is_action_just_pressed(action_melee):
			_travel("melee")
		if Input.is_action_just_pressed(action_reload) and magazine != max_magazine:
			reload()
		if Input.is_action_just_pressed(action_ads):
			aim()
		if Input.is_action_just_pressed(action_next_weapon):
			take_weapon(weapon_index+1)
		if Input.is_action_just_pressed(action_previous_weapon):
			take_weapon(weapon_index-1)

func _process(delta) -> void:
	# Sway runs at render rate (not physics rate) so the gun never trails a frame
	# behind the camera on fast flicks; lag is also hard-clamped to a few degrees.
	if sway and camera:
		sway_rotation_target = camera.global_rotation.reflect(Vector3(0,1,0))
		sway_rotation_target.y -= PI
		if ads:
			rotation = sway_rotation_target
		else:
			var sway_k := minf(delta*sway_look_sens, 1.0)
			rotation.y = _lag_clamp(lerp_angle(rotation.y, sway_rotation_target.y, sway_k), sway_rotation_target.y)
			rotation.x = _lag_clamp(lerp_angle(rotation.x, sway_rotation_target.x, sway_k), sway_rotation_target.x)
			rotation.z = _lag_clamp(lerp_angle(rotation.z, sway_rotation_target.z, sway_k), sway_rotation_target.z)
		position = camera.global_position
	if weapon != null:
		# Hard-disable breathing while aiming: pause the whole animation tree when
		# idle + ADS. _travel() re-activates it for fire/reload/melee/switch.
		if animation and !breath_while_ads:
			if ads and state_machine.get_current_node() == "idle" and not Input.is_action_pressed(action_fire):
				animation.process_mode = Node.PROCESS_MODE_DISABLED
			else:
				animation.process_mode = Node.PROCESS_MODE_INHERIT
		# Sight alignment: while aiming and the gun is still (idle, animation paused),
		# measure where the sight's AimPoint sits relative to the camera axis and shift
		# the ADS target so it lands exactly on it (dot == crosshair == bullet path).
		if ads and is_instance_valid(aim_point) and camera and animation and animation.process_mode == Node.PROCESS_MODE_DISABLED:
			var cl := camera.to_local(aim_point.global_position)
			var err_world := camera.global_transform.basis * Vector3(cl.x, cl.y, 0.0)
			var err_local := global_transform.basis.inverse() * err_world
			ads_target = Vector3(weapon.position.x - err_local.x, weapon.position.y - err_local.y, ads_pos.z)
		elif not ads:
			ads_target = ads_pos
		# Viewmodel zoom (gun shader FOV) follows the ADS state
		var want_fov := ads_viewmodel_fov if ads else viewmodel_fov
		if absf(vm_fov - want_fov) > 0.01:
			_set_vm_fov(lerpf(vm_fov, want_fov, minf(weapon.get_meta("delta",1.5)*delta_multiplier*delta*4.0, 1.0)))
		# ADS animation
		if ads and weapon.position != ads_target:
			weapon.position = weapon.position.move_toward(ads_target, weapon.get_meta("delta",1.5)*delta_multiplier*delta)
			if ads_dynamic_fov:
				camera.fov = lerpf(camera.fov, start_fov-30, weapon.get_meta("delta",1.5)*delta_multiplier*delta)
		if !ads and weapon.position != start_pos:
			weapon.position = weapon.position.move_toward(start_pos, weapon.get_meta("delta",1.5)*delta_multiplier*delta)
			if ads_dynamic_fov:
				camera.fov = lerpf(camera.fov, start_fov, weapon.get_meta("delta",1.5)*delta_multiplier*delta)
		
		# Automatic fire
		if weapon.get_meta("auto", false):
			if Input.is_action_pressed(action_fire) and (magazine > 0 or max_magazine == 0):
				_travel("fire")
			elif auto_reload and Input.is_action_pressed(action_fire) and magazine == 0 and max_magazine > 0:
				reload()

const MAX_SWAY_LAG := 0.09 # ~5 degrees max trail on fast flicks
func _lag_clamp(value:float, target:float) -> float:
	var diff := wrapf(value - target, -PI, PI)
	return target + clampf(diff, -MAX_SWAY_LAG, MAX_SWAY_LAG)

func _physics_process(delta) -> void:
	# Recoil
	if recoiling.x + recoiling.y > 0 and recoil and node_recoil_x and node_recoil_y:
		# If player moves camera more than recoil, we don't need it
		if node_recoil_x.rotation.x > recoil_target.x:
			recoiling.x = 0
		elif recoiling.x > 0:
			recoiling.x -= delta
			node_recoil_x.rotation.x = lerp_angle(node_recoil_x.rotation.x, recoil_target.x, delta*15)
		
		# Y recoil must be faster to avoid interrupting too much camera movement
		if recoiling.y > 0 and ((recoil_to_left and node_recoil_y.rotation.y < recoil_target.y) or \
		  (not recoil_to_left and node_recoil_y.rotation.y > recoil_target.y)):
			recoiling.y /= 2
			recoiling.y -= delta
			node_recoil_y.rotation.y = lerp_angle(node_recoil_y.rotation.y, recoil_target.y, delta*25)
	# Shake
	if shake and camera and shake_current > 0:
		shake_current = max(shake_current - shake_decay * delta, 0)
		camera_shake()

func _on_animation_tree_animation_finished(anim_name: StringName) -> void:
	# Reload magazine
	if anim_name == "reload" or anim_name == "reload_full":
		if realistic_reloading:
			if inventory["ammo"][weapon.get_meta("ammo_type", "none")] >= max_magazine:
				inventory["ammo"][weapon.get_meta("ammo_type", "none")] -= max_magazine
				magazine = max_magazine
			else:
				magazine = inventory["ammo"][weapon.get_meta("ammo_type", "none")]
				inventory["ammo"][weapon.get_meta("ammo_type", "none")] = 0
		else:
			if inventory["ammo"][weapon.get_meta("ammo_type", "none")] >= max_magazine-magazine:
				inventory["ammo"][weapon.get_meta("ammo_type", "none")] -= max_magazine-magazine
				magazine = max_magazine
			else:
				magazine += inventory["ammo"][weapon.get_meta("ammo_type", "none")]
				inventory["ammo"][weapon.get_meta("ammo_type", "none")] = 0
		update_inventory()
	# Remove weapon
	if anim_name == "hide":
		hide_weapon()
	# Stop recoil
	if anim_name == "fire":
		recoiling = Vector2.ZERO

func _on_animation_tree_animation_started(anim_name: StringName) -> void:
	# Show weapon on animationTree start
	if anim_name == "take" and !weapon.visible:
		weapon.visible = true
	# If any animation other than idle and fire starts, do not aim
	if anim_name != "idle" and anim_name != "fire":
		aim(false)
	if anim_name == "fire":
		firing.emit()
		if max_magazine != 0:
			magazine -= 1
			update_inventory()
		if weapon.get_meta("melee", false):
			melee_attack(FireRayCast, weapon.get_meta("damage"))
		else:
			fire_bullet_calculate(FireRayCast, weapon.get_meta("damage"))
		muzzle_flash()
		muzzle_smoke()
		add_recoil()
		add_camera_shake(shake_strength)
	if anim_name == "melee":
		meleeing.emit()
		melee_attack(MeleeRayCast, melee_damage)
	if anim_name == "take":
		taking_weapon.emit()
	if anim_name == "reload" or anim_name == "reload_full":
		reloading.emit()
