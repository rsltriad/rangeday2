extends GPUParticles3D

func resize(size:Vector3) -> void:
	draw_pass_1.size.x = size.x
	draw_pass_1.size.y = size.y

func _ready():
	emitting = true

func _on_finished():
	queue_free()
