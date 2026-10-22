extends SceneTree

func _initialize() -> void:
	var wheel_api = load("res://scripts/windows_wheel.gd")
	if load("res://main.tscn") == null:
		push_error("Windows main scene failed to load")
		quit(1)
		return
	quit(0 if wheel_api.verify_extension() else 1)
