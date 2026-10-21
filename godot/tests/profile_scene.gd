extends SceneTree

const State = preload("res://scripts/state.gd")
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass a scene JSON path after --")
		quit(1)
		return
	var importer := State.new()
	var state := importer.import_json(FileAccess.get_file_as_string(args[0]))
	if state.is_empty():
		push_error(importer.error)
		quit(1)
		return
	var game := Main.new()
	game.maze = state.maze
	game.player = state.player
	game.balls = state.balls
	var times: Array[int] = []
	for tick in range(1200):
		game.maze.impacts.clear()
		var start := Time.get_ticks_usec()
		game.step_world(1.0 / 120.0, 1.0, 0.0, 1.0)
		times.append(Time.get_ticks_usec() - start)
	var total := 0
	for time in times:
		total += time
	times.sort()
	print("SCENE PHYSICS: ticks=", times.size(), " mean_us=", total / float(times.size()), " p95_us=", times[int(times.size() * 0.95)], " max_us=", times.back())
	print("FINAL PLAYER: ", game.player.room, " ", game.player.p, " ", game.player.velocity)
	game.free()
	quit()
