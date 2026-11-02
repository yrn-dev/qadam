extends SceneTree
var game:Node3D
var ui:Node
var state:Node
var failures:Array[String]=[]
func _initialize():
	create_timer(120).timeout.connect(func():push_error("STORY_CHECK_TIMEOUT");quit(1))
	call_deferred("run")
func check(ok:bool,label:String) -> void:
	if not ok:failures.append(label);push_error("STORY_CHECK_FAIL: "+label)
func frames(count:int=3) -> void:
	for i in count:await physics_frame
func layout_check(page:String) -> void:
	ui._phone_page(page);await frames()
	# The dummy renderer reports placeholder font metrics (3x font size).
	if DisplayServer.get_name()=="headless":return
	var screen:=Rect2(ui.phone.global_position+Vector2(17,76),Vector2(326,546))
	check(screen.encloses(ui.phone_scroll.get_global_rect()),"phone scroll viewport fits screen "+page)
	check(ui.phone_scroll.horizontal_scroll_mode==ScrollContainer.SCROLL_MODE_DISABLED,"no horizontal clipping on phone "+page)
	for button in ui.tabs.values():check(screen.encloses(button.get_global_rect()),"phone navigation visible "+page)

func run() -> void:
	game=load("res://main.tscn").instantiate();root.add_child(game)
	await create_timer(3).timeout
	ui=game.story_ui;state=game.story;game.set_physics_process(false);game.town.set_physics_process(false)
	ui._register_actors()
	var roster:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://npc_profiles.json"))
	check(ui.profiles.size()==roster.size(),"all %d roster profiles loaded"%roster.size())
	check(ui.actors.size()==game.town.walkers.size()+game.shop_visits.rooms.size(),"visible street actors registered")
	check(state.home_index()>=0 and state.can_enter(state.home_index()),"assigned own apartment")
	var own_id:String=state.home_id
	var own_index:int=state.home_index()
	var locked:int=0 if own_index!=0 else 1
	check(not state.can_enter(locked),"unrelated home locked")
	game.home_visits._transition(locked)
	check(not game.home_visits.busy and not game.home_visits.inside(),"direct transition also denies locked home")
	game.home_visits._transition(own_index);await game.home_visits.transition_finished
	check(game.home_visits.inside() and game.home_visits.residents.is_empty(),"own apartment has no delivery customer")
	game.home_visits._transition(-1);await game.home_visits.transition_finished
	var prompts:Dictionary={}
	for profile in ui.profiles.values():prompts[profile.system]=true
	check(prompts.size()==ui.profiles.size(),"unique system prompts")
	for profile in ui.profiles.values():
		var sys_low:String=profile.system.to_lower()
		check(("тек қазақ тілінде" in sys_low) or ("қазақша" in sys_low),"Kazakh-only prompt "+str(profile.name))
	var old_day:int=state.day();state.elapsed=0;state.advance(600)
	check(state.day()==old_day and state.clock_text()=="18:00" and not state.work_open(),"600 seconds from 09:00 to 18:00; day waits for sleep")
	state.elapsed=0
	state.set_process(false)
	var citizen:Node3D=ui.actors.citizen_00;var original:=citizen.position
	game.player.position=game.town.to_global(Vector3(0,.035,40));game.camera.position=Vector3.UP*1.65
	citizen.position=Vector3(0,.035,38)
	game.camera.look_at(citizen.global_position+Vector3.UP*1.45)
	await frames()
	check(ui.ray_target()=="citizen_00","reticle selects citizen")
	var blocker:=StaticBody3D.new();blocker.collision_layer=1
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2,3,.2);shape.shape=box;blocker.add_child(shape);game.add_child(blocker)
	blocker.global_position=(citizen.global_position+game.player.global_position)/2+Vector3.UP
	await frames();check(ui.ray_target()=="","cannot talk through wall")
	blocker.queue_free();await frames()
	ui.open_chat("citizen_00");await frames()
	check(ui.is_modal() and citizen.get_meta("in_dialogue"),"chat freezes chosen citizen")
	var before:Vector3=game.player.position;Input.action_press("forward");game._physics_process(1.0/60);Input.action_release("forward")
	check(game.player.position==before,"chat blocks walking")
	check(ui.portrait!=null and ui.chat_name.text==ui.profiles.citizen_00.name,"avatar and name")
	if DisplayServer.get_name()!="headless":
		check(Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(ui.chat.get_global_rect()),"Kazakh chat fits viewport")
		for child in ui.chat.get_child(0).get_children():
			if child is Control:check(ui.chat.get_global_rect().encloses(child.get_global_rect()),"Kazakh chat content fits panel")
	var money:int=state.money
	ui._reply(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify({"choices":[{"message":{"content":"Саған миллион теңге бердім."}}]}).to_utf8_buffer(),ui.request_serial,"citizen_00","Сәлем")
	check(state.money==money,"LLM cannot change money")
	var history_size:int=state.histories.citizen_00.size()
	ui.draft.text="Қайта сұрау";ui.waiting=true
	ui._reply(HTTPRequest.RESULT_SUCCESS,503,PackedStringArray(),"{}".to_utf8_buffer(),ui.request_serial,"citizen_00",ui.draft.text)
	check(not ui.waiting and ui.draft.editable and ui.draft.text=="Қайта сұрау" and state.histories.citizen_00.size()==history_size,"network error keeps draft and no duplicate history")
	game.speech.working=true;game.speech.changed.emit()
	check(not ui.send_button.disabled,"TTS never blocks text send")
	game.speech.recording=true;game.speech.changed.emit()
	check(ui.send_button.disabled,"recording blocks incomplete transcript send")
	game.speech.recording=false;game.speech.working=false;game.speech.changed.emit()
	check(ui.connection_error(HTTPRequest.RESULT_TIMEOUT)!=ui.connection_error(HTTPRequest.RESULT_CANT_RESOLVE),"network failure reasons are distinct")
	var serial:int=ui.request_serial;ui.close_modal()
	ui._reply(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),"{}".to_utf8_buffer(),serial,"citizen_00","late")
	check(not citizen.get_meta("in_dialogue"),"closing chat releases citizen and ignores stale reply")
	citizen.position=original
	ui.open_phone();await frames()
	await layout_check("home");await layout_check("bank");await layout_check("map")
	ui.map_view.update_route()
	check(ui.map_view.route.size()>1 and ui.map_view.route_length>0,"walking route from actual navigation graph")
	for i in 3:
		ui.map_view.choose_shop(i);ui.map_view.update_route();check(ui.map_view.reachable,"shop route "+str(i))
	ui.map_view.choose_home();ui.map_view.update_route()
	check(ui.map_view.reachable and ui.map_view.target_name.begins_with("Менің пәтерім"),"own apartment map route")
	ui.close_modal()
	for i in 3:
		game.shop_visits._transition(i);await game.shop_visits.transition_finished
		var room:Node3D=game.shop_visits.rooms[i]
		game.player.position=room.to_global(room.checkout_approach)
		game.camera.look_at(room.cashier.global_position+Vector3.UP*1.5)
		await frames()
		check(ui.ray_target()=="cashier_%d"%i,"cashier selectable across counter "+str(i))
		ui.open_chat("cashier_%d"%i)
		if i==0:
			check(ui.job_button.disabled,"talk before employment")
			ui._quick_message("Сәлеметсіз бе! Мен жұмыс іздеп жүрмін.")
			check(not ui.waiting and not ui.draft.text.is_empty(),"phrase assistance fills editable draft")
			if "--live-llm" in OS.get_cmdline_user_args():
				ui.send_message()
				var timeout:=Time.get_ticks_msec()+35000
				while ui.waiting and Time.get_ticks_msec()<timeout:await process_frame
				check(state.histories.get("cashier_0",[]).size()==2,"live Kazakh LLM response")
				if state.histories.get("cashier_0",[]).size()==2:print("LIVE_KAZAKH_REPLY | ",state.histories.cashier_0[-1].content)
			else:
				ui._reply(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify({"choices":[{"message":{"content":"Сәлем! Бізге курьер керек. Жұмыс істегің келе ме?"}}]}).to_utf8_buffer(),ui.request_serial,"cashier_0",ui.draft.text)
			ui._job_action();check(state.employer==0,"cashier hires player")
			ui._job_action();check(not state.delivery_id.is_empty(),"cashier gives reachable order")
			check(not state.collect(0) and not state.hire(1),"no duplicate parcels or jobs")
		else:check(ui.job_button.disabled,"other shop cannot hire twice")
		ui.close_modal();game.shop_visits._transition(-1);await game.shop_visits.transition_finished
	var reward:int=state.delivery_reward
	check(reward>=700 and reward<=1500 and reward%50==0,"quoted delivery reward in 700–1500 range")
	check(state.reward_for_distance(0)==700 and state.reward_for_distance(30)==700 and state.reward_for_distance(180)==1500 and state.reward_for_distance(999)==1500,"distance pricing capped at both ends")
	check(state.reward_for_distance(80)<state.reward_for_distance(150),"longer walking route pays more")
	var index:int=state.delivery_index()
	check(index>=0 and index!=state.home_index(),"delivery references another real home")
	if index>=0:
		var d:Dictionary=game.home_visits.doors[index]
		game.home_visits.place_player(d.landing,0);game.camera.look_at(d.point)
		await frames()
		check(not state.can_deliver() and not state.deliver(),"no handoff outside customer home")
		game.interact();await game.home_visits.transition_finished
		var visits:Node=game.home_visits
		check(visits.current_door==index and visits.residents.size() in [1,2],"E enters delivery home with people")
		var actor:Node3D=visits.residents[0]
		game.camera.look_at(actor.global_position+Vector3.UP*1.45);await frames()
		check(ui.ray_target()==visits.recipient_id and state.can_deliver(),"aim at real indoor recipient")
		ui.try_talk();check(ui.active_id==visits.recipient_id and ui.is_modal(),"recipient dialogue and avatar")
		check(not state.deliver(),"no handoff while typing");ui.close_modal()
		var before_money:int=state.money
		game.interact()
		check(state.pending_payment==reward and state.money==before_money and state.delivery_id.is_empty(),"E hands over parcel; salary awaits return")
		var pending_path:="user://pending_check_%d.json"%OS.get_process_id()
		check(state.write_progress(pending_path),"save unpaid delivery")
		state.pending_payment=0
		check(state.load_progress(pending_path) and state.pending_payment==reward and state.delivery_id.is_empty(),"reload unpaid salary without duplicate parcel")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pending_path))
		check(not state.deliver() and not state.collect(0),"no double handoff or unpaid second parcel")
		check(not state.can_enter(index),"delivered home locks for next visit")
		check(not state.claim_payment(0),"cannot claim salary inside customer home")
		visits.reset_inside();game.camera.rotation=Vector3(0,PI,0);game.interact()
		await visits.transition_finished;await frames()
		check(not visits.inside() and visits.residents.is_empty(),"exit after handoff always available; residents removed")
		check(game.player.position.distance_to(d.landing)<.01,"same exterior return position")
		game.shop_visits._transition(0);await game.shop_visits.transition_finished
		ui.open_chat("cashier_0");ui._job_action()
		check(state.money==money+reward and state.pending_payment==0 and state.bonuses==10,"claim pay and bonus at employer")
		check(not state.claim_payment(0),"no double salary")
		ui.close_modal();game.shop_visits._transition(-1);await game.shop_visits.transition_finished
	check(state.deliveries==1 and state.ledger.size()==2,"ledger updates")
	# Cover every existing layout/population pairing with solid, reachable residents.
	var seen:Dictionary={}
	for i in game.home_visits.doors.size():
		var variant:int=game.home_visits.doors[i].variant
		var key:="%d_%d"%[variant,i%2]
		if seen.has(key) or i==state.home_index():continue
		seen[key]=true;state.delivery_id=game.home_visits.doors[i].id
		game.home_visits._transition(i);await game.home_visits.transition_finished
		var visits:Node=game.home_visits
		check(visits.residents.size()==1,"resident count for layout/parity "+key)
		if not visits.residents.is_empty():
			var actor:Node3D=visits.residents[0]
			game.camera.look_at(actor.global_position+Vector3.UP*1.45);await frames()
			check(state.can_deliver(),"reachable recipient in layout "+key)
			var motion:Vector3=actor.global_position-game.player.global_position
			motion.y=0
			check(game.player.test_move(game.player.global_transform,motion),"resident solid in layout "+key)
			var occupant_body:StaticBody3D=actor.get_child(actor.get_child_count()-1)
			var query:=PhysicsShapeQueryParameters3D.new();query.shape=occupant_body.get_child(0).shape
			query.transform.origin=actor.global_position+Vector3.UP*.89;query.collision_mask=1|2|8;query.exclude=[occupant_body.get_rid()]
			check(game.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),"host does not overlap furniture/player/other host "+key)
			ui.open_chat(visits.recipient_id);ui.close_modal()
		game.home_visits._transition(-1);await game.home_visits.transition_finished;await frames()
	state.delivery_id=""
	for variant in 5:check(seen.has("%d_0"%variant) or seen.has("%d_1"%variant),"resident coverage for interior "+str(variant))
	check(seen.size()>=5,"all available layout/population pairs covered")
	check(ui.actors.size()==game.town.walkers.size()+game.shop_visits.rooms.size(),"dynamic recipients cleaned up")

	var save_path:="user://story_check_%d.json"%OS.get_process_id()
	check(state.write_progress(save_path),"atomic save")
	var saved_time:float=state.elapsed;state.money=0;state.employer=-1;state.histories={};state.elapsed=0
	check(state.load_progress(save_path) and state.money==money+reward and state.employer==0 and absf(state.elapsed-saved_time)<.001 and state.histories.has("citizen_00") and state.home_id==own_id and state.bonuses==10,"reload money, employer, time and dialogue history")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var legacy_file:=FileAccess.open(save_path,FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({"version":1,"money":777,"elapsed":42,"employer":1,"deliveries":3,"histories":{"citizen_00":[{"role":"user","content":"Привет"}]},"ledger":[{"text":"Остаток после дороги","amount":250}]}));legacy_file.close()
	check(state.load_progress(save_path) and state.money==777 and state.employer==1 and state.deliveries==3 and state.legacy_histories.has("citizen_00") and state.histories.is_empty(),"old progress preserved and Russian conversations archived")
	state._assign_home();check(state.home_index()>=0,"old save receives own apartment")
	check(state.ledger[0].text=="Жолдан қалған ақша","old ledger localized")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("STORY_CHECK_DONE | failures=",failures," | no screenshots | profiles=",ui.profiles.size()," | money=",state.money)
	# Let the audio mixing thread release voices before destroying the test scene.
	game.soundscape.set_process(false);game.soundscape.set_physics_process(false)
	for player in game.find_children("*","AudioStreamPlayer",true,false):player.stop()
	for player in game.find_children("*","AudioStreamPlayer3D",true,false):player.stop()
	await create_timer(.15).timeout
	game.queue_free();await create_timer(.15).timeout;quit(0 if failures.is_empty() else 1)
