extends SceneTree
var failures:Array[String]=[]
func check(ok:bool,label:String):
	if not ok:failures.append(label);push_error("PORTABLE_FAIL | "+label)
func _initialize():
	create_timer(100).timeout.connect(func():print("PORTABLE_TIMEOUT");quit(1))
	call_deferred("run")
func run():
	var paths=load("res://runtime_paths.gd")
	check(FileAccess.file_exists(paths.python()),"bundled Python exists")
	check(FileAccess.file_exists(paths.root_dir().path_join("voice/server.py")),"speech server beside executable")
	check(not FileAccess.file_exists("user://story_v1.json"),"fresh game without copied progress")
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	while not game.town.population.ready_for_walk:await physics_frame
	game.set_physics_process(false);game.story.set_process(false)
	var ui=game.story_ui;ui._register_actors();ui.open_chat("citizen_00")
	check(not ui.api_key().is_empty(),"portable LLM config available")
	check(game.town.shops.size()==5 and game.home_visits.rooms.size()==5,"map and interiors loaded")
	game.speech.enabled=true;game.speech.speak(ui.profiles.citizen_00.greeting,"citizen_00")
	check(game.speech.cache_hits==1 and game.speech.speaker.playing,"baked voice loaded from PCK")
	if "--voice-live" in OS.get_cmdline_user_args():
		game.speech.ensure_service()
		for tick in 200:
			if game.speech.service_ready:break
			await create_timer(.2).timeout
		check(game.speech.service_ready,"bundled speech process starts")
		if game.speech.service_ready:
			game.speech.speak("Мен жаңа қалаға келдім. Бұл дүкен қай жерде?","citizen_00")
			for tick in 200:
				if not game.speech.working:break
				await create_timer(.2).timeout
			check(game.speech.cache_writes==1,"new speech synthesized and cached")
	print("PORTABLE_CHECK_DONE | OS=",OS.get_name()," failures=",failures)
	ui.close_modal()
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	game.queue_free();await create_timer(.3).timeout;quit(0 if failures.is_empty() else 1)
