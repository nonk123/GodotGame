extends Node


# Time until death, in seconds.
export(float) var death_timer = 1.0


func _process(delta):
	if death_timer < 0.0:
		queue_free()
	else:
		death_timer -= delta
