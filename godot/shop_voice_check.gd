extends SceneTree
var game:Node3D
var failures:Array[String]=[]
func _initialize() -> void:
	create_timer(90).timeout.connect(func():push_error("SHOP_VOICE_TIMEOUT");quit(1))
	call_deferred("run")
func check(ok:bool,label:String) -> void:
	if not ok:failures.append(label);push_error("SHOP_VOICE_FAIL: "+label)
func run() -> void:
	game=load("res://main.tscn").instantiate();root.add_child(game);await create_timer(3).timeout
	game.set_physics_process(false);game.story.set_process(false)
	check(game.town.shops.size()==5,"five shops")
	var shop:Node3D=game.town.shops[3]
	var box:AABB=game.town.footprints.back()
	for i in game.town.footprints.size()-1:
		check(not box.intersects(game.town.footprints[i]),"new store no building overlap %d"%i)
	var world_box:AABB=shop.global_transform*shop.get_child(0).get_aabb()
	for door in game.home_visits.doors:
		check(not world_box.grow(.33).has_point(door.landing+Vector3.UP),"new store preserves home entrance "+str(door.id))
	var at:Vector3=shop.to_global(Vector3(2.8,.12,0));game.player.global_position=at;game.camera.position=Vector3.UP*1.65;game.camera.look_at(shop.to_global(Vector3(1.55,1.25,0)))
	check(game.shop_visits.nearby_shop()==3,"real exterior door")
	var query:=PhysicsShapeQueryParameters3D.new();var capsule:=CapsuleShape3D.new();capsule.height=1.75;capsule.radius=.32
	query.shape=capsule;query.collision_mask=1|4|8;query.transform.origin=at+Vector3.UP*.875;query.exclude=[game.player.get_rid()]
	check(game.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),"clear entrance")
	var local:Vector3=game.town.to_local(at);var population:Node=game.town.population
	var goal:int=population.nearest_point(Vector2(local.x,local.z));var start:int=population.nearest_point(Vector2(0,38))
	check(not population.graph.get_point_path(start,goal).is_empty(),"store connected to walk network")
	query.transform.origin=game.town.to_global(Vector3(population.graph.get_point_position(goal).x,.12,population.graph.get_point_position(goal).y))+Vector3.UP*.875
	query.motion=at+Vector3.UP*.875-query.transform.origin
	check(game.get_world_3d().direct_space_state.cast_motion(query)[0]>.99,"walk network reaches entrance")
	game.interact();await game.shop_visits.transition_finished
	var room:Node3D=game.shop_visits.rooms[3]
	check(room.props.is_empty() and room.checkout==null,"empty room no shelves products or counter")
	check(room.cashier.character_id=="erlan","male seller")
	var ui:Node=game.story_ui
	ui._register_actors();ui.open_chat("cashier_3")
	check(ui.job_button.disabled and "1 000 000" in ui.job_button.text,"million price visible")
	check(not game.story.purchase_shop(),"insufficient funds cannot buy")
	game.story.money=1000000;ui._update_job_button();check(not ui.job_button.disabled,"funded buyer enabled")
	ui._job_action();check(ui.purchase_confirm.visible and not game.story.owns_shop,"confirm before purchase")
	ui.purchase_confirm.hide();ui.purchase_confirm.confirmed.emit()
	check(game.story.owns_shop and game.story.money==0,"one million debited")
	check(not game.story.purchase_shop(),"no duplicate purchase")
	var path:="user://shop_voice_test_%d.json"%OS.get_process_id();game.story.write_progress(path);game.story.owns_shop=false
	check(game.story.load_progress(path) and game.story.owns_shop,"ownership saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game.speech.transcript.emit("Сәлеметсіз бе",{"text":"Сәлеметсіз бе"})
	check(ui.draft.text=="Сәлеметсіз бе" and not ui.waiting,"speech becomes editable draft no autosend")
	ui.practice_phrase();check(not game.speech.expected.is_empty(),"repeat exercise")
	game.speech.transcript.emit("Сәлеметсіз бе",{"practice":{"expected":"Сәлеметсіз бе","word_match":100}})
	check("айтылым бағасы емес" in ui.voice_status.text,"word match not fake pronunciation score")
	if "--voice-live" in OS.get_cmdline_user_args():
		game.speech.ensure_service()
		for tick in 150:
			if game.speech.service_ready:break
			await create_timer(.2).timeout
		check(game.speech.service_ready,"real local speech server ready")
		game.speech.speak("Сәлеметсіз бе! Мен қазақ тілін үйреніп жүрмін.","cashier_3")
		for tick in 150:
			if not game.speech.working:break
			await create_timer(.2).timeout
		check(game.speech.speaker.stream!=null and game.speech.speaker.stream.data.size()>1000,"real TTS audio received by Godot")
		game.speech.stop()
		var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../voice/test_phrase.json"))
		game.speech.post("stt",fixture)
		for tick in 150:
			if not game.speech.working:break
			await create_timer(.2).timeout
		check("қазақ" in ui.draft.text and "100%" in ui.voice_status.text,"real ASR arrives in editable chat with exercise feedback")
	if DisplayServer.get_name()!="headless":
		await process_frame;await process_frame
		check(Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(ui.chat.get_global_rect()),"chat fits real viewport")
		for button in [ui.mic_button,ui.listen_button,ui.practice_button,ui.send_button,ui.job_button]:
			check(ui.chat.get_global_rect().encloses(button.get_global_rect()),"voice and chat buttons visible "+button.text)
	ui.close_modal();check(not game.speech.recording and not game.speech.speaker.playing,"close stops capture and speech")
	game.shop_visits._transition(-1);await game.shop_visits.transition_finished
	ui.selected_shop=3;ui.open_phone();ui._phone_page("map");ui.map_view.update_route()
	check(ui.map_view.reachable and ui.map_view.target_name=="Менің дүкенім","fourth shop map route")
	ui.close_modal()
	print("SHOP_VOICE_CHECK_DONE | failures=",failures)
	for player in game.find_children("*","AudioStreamPlayer",true,false):player.stop()
	for player in game.find_children("*","AudioStreamPlayer3D",true,false):player.stop()
	game.soundscape.set_process(false);game.soundscape.set_physics_process(false);await create_timer(.15).timeout
	game.queue_free();await create_timer(.2).timeout;quit(0 if failures.is_empty() else 1)
