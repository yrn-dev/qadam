extends SceneTree
var game:Node3D
var population:Node
var failures:Array[String]=[]
var capture:bool="--capture" in OS.get_cmdline_user_args()
func _initialize():call_deferred("run")
func check(ok:bool,label:String) -> void:
	if not ok:failures.append(label);push_error("CITIZEN_COLLISION_FAIL: "+label)
func pose(w:Dictionary,at:Vector3,target:Vector3,walking:bool=true) -> void:
	w.node.position=at;w.node.collision_layer=8;w.node.collision_mask=1|2|4|8
	w.path=PackedVector2Array([Vector2(target.x,target.z)]);w.index=0
	w.wait=0.0 if walking else 10000.0;w.speed=1.25;w.crossing=population.on_road(at)
	w.blocked_for=0.0;w.avoid_side=1.0
func simulate_pair(label:String,a:Vector3,b:Vector3,end_a:Vector3,end_b:Vector3,seconds:float=12) -> void:
	var first:Dictionary=game.town.walkers[0];var second:Dictionary=game.town.walkers[1]
	pose(first,a,end_a);pose(second,b,end_b)
	game.player.position=game.town.to_global(Vector3(0,.1,50))
	game.town.traffic.phase=6
	await physics_frame
	var smallest:=1000.0
	for tick in int(seconds*60):
		for w in [first,second]:
			if w.index>=w.path.size():w.wait=10000
		population.tick(1.0/60)
		smallest=minf(smallest,first.node.global_position.distance_to(second.node.global_position))
		await physics_frame
	check(smallest>=.714,"no overlap "+label+" distance="+str(smallest))
	check(first.node.position.distance_to(end_a)<.15 and second.node.position.distance_to(end_b)<.15,"both pass "+label+" positions="+str(first.node.position)+" / "+str(second.node.position))
	print("PAIR | ",label," | minimum separation=",smallest," | end=",first.node.position," / ",second.node.position)
func run() -> void:
	game=load("res://main.tscn").instantiate();root.add_child(game)
	await create_timer(2).timeout
	game.set_physics_process(false);game.town.set_physics_process(false)
	# Mirror the live game state after the start menu is dismissed (start_menu.gd):
	# controls are captured and citizens see the player as an obstacle.
	game.main_menu.active=false
	game.captured=true
	game.town.player=game.player
	population=game.town.population
	for w in game.town.walkers:
		check(w.node is CharacterBody3D,"physical citizen")
		check(w.node.global_basis.get_scale().is_equal_approx(Vector3.ONE),"human scale")
		w.wait=10000;w.node.collision_layer=0
		w.node.position=Vector3(100+w.id*2,.035,100)
	for car in game.town.vehicles:
		for body in car.node.find_children("*","CollisionObject3D",true,false):body.collision_layer=0
	var w:Dictionary=game.town.walkers[0]
	var origin:=Vector3(0,.035,32)
	pose(w,origin,origin,false)
	game.player.position=game.town.to_global(origin+Vector3(0,0,2))
	game.yaw=0;game.camera.position=Vector3.UP*1.65;game.camera.rotation=Vector3.ZERO
	await physics_frame
	Input.action_press("forward");Input.action_press("run")
	for i in 90:
		game._physics_process(1.0/60);await physics_frame
	Input.action_release("forward");Input.action_release("run")
	var separation:float=game.player.global_position.distance_to(w.node.global_position)
	check(separation>=.67 and separation<.85,"player stops at citizen capsule distance="+str(separation))
	check(game.player.position.z>w.node.global_position.z,"player cannot tunnel through NPC")
	# Render culling must never disable collisions.
	w.node.visible=false
	check(game.player.test_move(Transform3D(Basis.IDENTITY,game.town.to_global(origin+Vector3(0,0,2))),Vector3(0,0,-5)),"invisible NPC remains solid")
	w.node.visible=true
	await simulate_pair("head-on",Vector3(-2,.035,32),Vector3(2,.035,32),Vector3(2,.035,32),Vector3(-2,.035,32))
	await simulate_pair("crossing paths",Vector3(-2,.035,30),Vector3(2,.035,30),Vector3(2,.035,34),Vector3(-2,.035,34))
	await simulate_pair("pedestrian crossing",Vector3(-32,.035,8.4),Vector3(-22,.035,8.4),Vector3(-22,.035,8.4),Vector3(-32,.035,8.4),18)
	var second:Dictionary=game.town.walkers[1];second.node.collision_layer=0;second.wait=10000;second.node.position=Vector3(100,.035,100)
	pose(w,Vector3(0,.035,30),Vector3(0,.035,34))
	game.player.position=game.town.to_global(Vector3(0,.035,32))
	await physics_frame
	var minimum:=1000.0
	for tick in 720:
		if w.index>=w.path.size():w.wait=10000
		population.tick(1.0/60)
		minimum=minf(minimum,w.node.global_position.distance_to(game.player.global_position))
		await physics_frame
	check(minimum>=.67,"NPC cannot walk into player")
	check(w.node.position.distance_to(Vector3(0,.035,34))<.15,"NPC passes stationary player")
	print("PLAYER | NPC avoidance minimum separation=",minimum)
	if capture:
		pose(w,Vector3(-.6,.035,32),Vector3(0,.035,32),false)
		pose(second,Vector3(.6,.035,32),Vector3(0,.035,32),false)
		w.node.rotation.y=PI;second.node.rotation.y=PI
		game.player.position=game.town.to_global(Vector3(0,.035,35));game.camera.look_at(game.town.to_global(Vector3(0,1.0,32)))
		for i in 3:
			population.tick(1.0/60);await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../previews/solid_citizens.png"))
	print("CITIZEN_COLLISION_CHECK_","PASS" if failures.is_empty() else "FAIL"," | failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
