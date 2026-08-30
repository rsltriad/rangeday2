@tool
extends Node3D
## Tube red dot sight (model: "Red Dot Sight" by Pichuliru, Poly Pizza, CC0).
## Child "AimPoint" marks the optical centre; fps-hands.gd aligns it to the camera axis in ADS.

@export var riser_height: float = 0.0:
	set(v):
		riser_height = v
		_update_riser()

@onready var _lift: Node3D = $Lift
@onready var _model: Node3D = $Lift/Model
var _riser: MeshInstance3D

const FLAT_SHADER := preload("res://addons/fps-hands/reddot/viewmodel_flat.gdshader")
const GLASS_SHADER := preload("res://addons/fps-hands/reddot/viewmodel_glass.gdshader")

func _flat(color: Color, rough := 0.6, metal := 0.3) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FLAT_SHADER
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("metallic", metal)
	m.set_shader_parameter("fov", 70.0)
	return m

func _ready() -> void:
	# Re-material the model with the fixed-FOV viewmodel shaders so it stays glued to
	# the gun (which uses the same projection). Surface 2 = M_PCL_Flat_Glass -> see-through.
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(i)
			var col: Color = src.albedo_color if src is BaseMaterial3D else Color(0.1, 0.1, 0.1)
			if i == 2:
				var g := ShaderMaterial.new()
				g.shader = GLASS_SHADER
				g.render_priority = 1
				g.set_shader_parameter("fov", 70.0)
				mi.set_surface_override_material(i, g)
			else:
				mi.set_surface_override_material(i, _flat(col))
	var ret: MeshInstance3D = $Lift/Reticle
	if ret.mesh and ret.mesh.material is ShaderMaterial:
		ret.mesh.material.set_shader_parameter("fov", 70.0)
	_update_riser()

func _update_riser() -> void:
	if not is_inside_tree():
		return
	if _riser == null:
		_riser = MeshInstance3D.new()
		_riser.name = "Riser"
		_riser.material_override = _flat(Color(0.06, 0.06, 0.06), 0.7, 0.2)
		add_child(_riser)
	_lift.position = Vector3(0, maxf(riser_height, 0.0), 0)
	if riser_height <= 0.0:
		_riser.visible = false
		return
	_riser.visible = true
	var box := BoxMesh.new()
	box.size = Vector3(0.022, riser_height, 0.05)
	_riser.mesh = box
	_riser.position = Vector3(0, riser_height * 0.5, 0.004)
