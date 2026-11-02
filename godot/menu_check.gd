extends SceneTree
var game:Node3D
var errors:Array[String]=[]
func _initialize() -> void:
	create_timer(180).timeout.connect(func():push_error("MENU_CHECK_TIMEOUT");quit(1))
	call_deferred("run")
func check(ok:bool,words:String) -> void:
	if not ok:errors.append(words);push_error(words)
func frames(count:int=3) -> void:
	for i in count:await physics_frame
func run() -> void:
	game=load("res://main.tscn").instantiate();root.add_child(game);await create_timer(3).timeout
	game.story.resume_location={} # The menu flow is tested with a fresh session; the real save is exercised later via the isolated test file.
	var menu:Node=game.main_menu
	var at:Vector3=game.player.global_position;var elapsed:float=game.story.elapsed
	var money:int=game.story.money;var old_camera:Transform3D=game.camera.transform
	menu.open_menu();await frames()
	check(menu.active and menu.camera.current and not game.captured,"start menu captures controls")
	var camera_at:Vector3=menu.camera.position;await create_timer(.5).timeout
	check(menu.camera.position.distance_to(camera_at)>.05,"slow city camera moves")
	Input.action_press("forward");game.interact();await frames();Input.action_release("forward")
	check(game.player.global_position==at and game.story.money==money and game.story.elapsed==elapsed,"menu cannot move player, advance story clock or spend money")
	check(not game.story_ui.get_child(0).visible and not game.hud.get_parent().visible and not game.soundscape.panel.visible,"clean menu without gameplay HUD")
	menu.moving=false;camera_at=menu.camera.position;await frames();check(menu.camera.position==camera_at,"stop camera option")
	menu.help.show();await frames()
	if DisplayServer.get_name()!="headless":
		var viewport:=Rect2(Vector2.ZERO,root.get_visible_rect().size)
		check(viewport.encloses(menu.help.get_global_rect()),"help panel fits")
		for button in menu.screen.find_children("*","Button",true,false):
			check(viewport.encloses(button.get_global_rect()),"menu button visible: "+button.text)
			check(button.size.y>=44,"large menu hit target")
	menu.play.pressed.emit();await frames()
	check(not menu.active and game.camera.current and game.captured,"play button enters game")
	check(game.camera.transform==old_camera,"play restores player camera")
	check(game.story.money==money,"menu preserves save state")
	# Manual button and S use an isolated file; never touch the player's real save.
	menu.save_path="user://menu_save_check_%d.json"%OS.get_process_id()
	game.set_physics_process(false);game.set_capture(false);await frames()
	check(menu.pause_root.visible,"Esc pause menu appears")
	menu.save_button.pressed.emit()
	check(FileAccess.file_exists(menu.save_path) and menu.save_status.text.begins_with("Сақталды"),"manual save button and confirmation")
	var snapshot=JSON.parse_string(FileAccess.get_file_as_string(menu.save_path))
	check(snapshot.location.kind=="street" and snapshot.money==money,"manual save stores location and money")
	var key:=InputEventKey.new();key.pressed=true;key.physical_keycode=KEY_S;menu._input(key)
	check(menu.save_status.text.begins_with("Сақталды"),"S saves only on pause")
	game.set_capture(true)
	var own:int=game.story.home_index();game.home_visits._transition(own);await game.home_visits.transition_finished
	game.yaw=.4;game.pitch=.1;game.camera.rotation=Vector3(.1,.4,0)
	game.set_capture(false);await frames();check(menu.save_current(),"save inside own apartment")
	var home_at:Vector3=game.player.position
	game.home_visits._transition(-1);await game.home_visits.transition_finished
	check(game.story.load_progress(menu.save_path),"load manual save")
	await game.restore_saved_place();await frames()
	check(game.home_visits.current_door==own and game.player.position.distance_to(home_at)<.02 and absf(game.yaw-.4)<.001,"resume in saved apartment with camera direction")
	game.home_visits._transition(-1);await game.home_visits.transition_finished
	# Restore a delivered customer's room without reopening its public door.
	# Normalize the story clock first: the live save may sit in the evening, when
	# collect() refuses to open new jobs and the transition would never start.
	game.story.elapsed=0;game.story.delivery_id="";game.story.pending_payment=0
	game.set_capture(true);game.story.hire(0);game.story.collect(0)
	var customer:int=game.story.delivery_index()
	check(customer>=0,"delivery candidate assigned from deterministic state")
	if customer<0:
		print("MENU_CHECK_DONE | errors=",errors," | aborted: no candidate")
		game.soundscape.set_process(false);game.soundscape.set_physics_process(false)
		game.queue_free();await create_timer(.15).timeout;quit(1)
	game.home_visits._transition(customer);await game.home_visits.transition_finished
	game.story.delivery_id="";game.story.pending_payment=900;game.home_visits.delivery_done=true
	game.set_capture(false);await frames();check(menu.save_current(),"save after handoff before leaving")
	game.home_visits._transition(-1);await game.home_visits.transition_finished
	game.story.load_progress(menu.save_path);await game.restore_saved_place();await frames()
	check(game.home_visits.current_door==customer and game.home_visits.delivery_done and not game.story.can_enter(customer),"resume handed-off visit without unlocking door")
	game.home_visits.reset_inside();game.camera.rotation=Vector3(0,PI,0)
	check(game.home_visits.at_exit(),"exit still available after reload")
	game.home_visits._transition(-1);await game.home_visits.transition_finished
	DirAccess.remove_absolute(ProjectSettings.globalize_path(menu.save_path))
	print("MENU_CHECK_DONE | errors=",errors," | no screenshots")
	game.soundscape.set_process(false);game.soundscape.set_physics_process(false)
	for sound in game.find_children("*","AudioStreamPlayer",true,false):sound.stop()
	for sound in game.find_children("*","AudioStreamPlayer3D",true,false):sound.stop()
	await create_timer(.15).timeout;game.queue_free();await create_timer(.15).timeout;quit(0 if errors.is_empty() else 1)
