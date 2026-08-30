extends Node3D

func resize(size:Vector3) -> void:
	var omnilight: OmniLight3D = $OmniLight3D
	omnilight.scale *= size
	omnilight.omni_range *= size.x
	omnilight.light_size *= size.x

func _ready():
	scale *= randf_range(0.9, 1.1)
	rotation_degrees.z = randf_range(-10.0, 10.0)
