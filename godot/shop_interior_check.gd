extends SceneTree
var game:Node3D
var visits:Node
var capture:bool="--capture" in OS.get_cmdline_user_args()
func _initialize():call_deferred("run")
func require(ok:bool,message:String) -> bool:
	if not ok:push_error("SHOP_CHECK_FAIL: "+message);quit(1)
	return ok
func snap(label:String) -> void:
	if not capture:return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../previews/shop_interior_"+label+".png"))
func run() -> void:
	game=load("res://main.tscn").instantiate();root.add_child(game)
	await create_timer(2).timeout
	visits=game.shop_visits
	if not require(visits.rooms.size()==5,"five interiors (3 shops + empty shop + salon)"):return
	game.set_physics_process(false)
	for i in 3:
		var shop:Node3D=game.town.shops[i]
		var inward:Vector3=-shop.global_basis.x.normalized()
		var angle:=atan2(-inward.x,-inward.z)
		visits.place_player(shop.to_global(Vector3(-2.8,.12,0)),angle)
		if not require(visits.nearby_shop()==-1,"no entrance through rear wall"):return
		visits.place_player(shop.to_global(Vector3(2.8,.12,2.5)),angle)
		if not require(visits.nearby_shop()==-1,"no entrance through window"):return
		visits.place_player(shop.to_global(Vector3(2.8,.12,0)),angle)
		if not require(visits.nearby_shop()==i,"door reachable "+str(i)):return
		await snap("door_%d"%i)
		visits.interact()
		if not require(visits.busy,"E begins transition"):return
		visits.interact() # Held/repeated E must not start a second transition.
		await visits.transition_finished
		if not require(visits.current_shop==i and game.town.player==null,"correct separate interior"):return
		var room:Node3D=visits.rooms[i]
		if not require(game.player.position.distance_to(room.to_global(Vector3(0,.08,4.5)))<.01,"safe spawn"):return
		if not require(game.camera.environment==room.interior_environment,"indoor lighting"):return
		var shelf_count:=0
		var product_count:=0
		var occupied:Dictionary={}
		for prop in room.props:
			if str(prop.get_meta("asset_id","")).begins_with("shelf"):shelf_count+=1
			if not str(prop.get_meta("asset_id","")).begins_with("grocery"):continue
			product_count+=1
			if not require(prop.has_meta("shelf"),"no products on checkout"):return
			var shelf:Node3D=prop.get_meta("shelf")
			var box:AABB=(shelf.global_transform.affine_inverse()*prop.global_transform)*prop.mesh.get_aabb()
			if not require(box.position.x>=-.605 and box.end.x<=.596 and box.position.z>=-.182 and box.end.z<=.234,"product fits shelf footprint"):return
			var board:float=prop.get_meta("board_y")/shelf.scale.y
			if not require(absf(box.position.y-board)<.012,"product rests on board"):return
			if not occupied.has(shelf):occupied[shelf]=[]
			for previous in occupied[shelf]:
				if not require(not box.intersects(previous),"products do not overlap"):return
			occupied[shelf].append(box)
		if not require(shelf_count==12 and product_count==144,"full aligned shelving layout"):return
		var space:=game.get_world_3d().direct_space_state
		for endpoint in [Vector3(-6,1.5,4),Vector3(6,1.5,4),Vector3(0,1.5,-7),Vector3(0,1.5,7),Vector3(0,5,4),Vector3(0,-2,4)]:
			var ray:=PhysicsRayQueryParameters3D.create(room.to_global(Vector3(0,1.5,4)),room.to_global(endpoint),1)
			if not require(not space.intersect_ray(ray).is_empty(),"solid room shell"):return
		var shape:=CapsuleShape3D.new();shape.radius=.32;shape.height=1.75
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.collision_mask=1
		query.transform=Transform3D(Basis.IDENTITY,room.to_global(Vector3(0,.96,4.5)))
		if not require(space.intersect_shape(query).is_empty(),"spawn outside colliders"):return
		query.motion=Vector3(0,0,-9)
		if not require(space.cast_motion(query)[0]>.99,"central aisle walkable"):return
		var approach:Vector3=room.checkout_approach
		var toward_counter:Vector3=room.checkout.position-approach;toward_counter.y=0
		if not require(game.player.test_move(Transform3D(Basis.IDENTITY,room.to_global(approach)),toward_counter),"counter collision"):return
		if not require(room.cashier.animation.has_animation("idle") and room.cashier.global_basis.get_scale().is_equal_approx(Vector3.ONE),"human-scale animated cashier"):return
		query.motion=Vector3.ZERO;query.exclude=[room.cashier_body.get_rid()]
		query.transform.origin=room.cashier.global_position+Vector3(0,.9,0)
		if not require(space.intersect_shape(query).is_empty(),"cashier clear of counter and walls"):return
		query.exclude=[];query.transform.origin=room.to_global(approach)+Vector3(0,.88,0)
		if not require(space.intersect_shape(query).is_empty(),"customer approach clear"):return

		await snap("room_%d"%i)
		if capture:
			visits.place_player(room.to_global(approach),0)
			game.camera.look_at(room.cashier.global_position+Vector3(0,1.45,0))
			await snap("cashier_%d"%i)
		if capture and i==0:
			visits.place_player(room.to_global(Vector3(0,.08,-.2)),.55)
			await snap("shelves")
			visits.place_player(room.to_global(Vector3(0,.08,4.2)),-.9)
			await snap("counter")
		visits.reset_inside()
		game.yaw=PI;game.camera.rotation.y=PI
		if not require(visits.at_exit(),"exit reachable"):return
		await snap("exit_%d"%i)
		visits.interact();await visits.transition_finished
		if not require(not visits.inside() and game.town.visible and game.town.player==game.player,"street restored"):return
		if not require(game.player.position.distance_to(shop.to_global(Vector3(2.8,.12,0)))<.01,"returns to same shop"):return
		if not require(game.camera.environment==null and game.player.velocity==Vector3.ZERO,"camera and velocity restored"):return
		print("SHOP_ROUND_TRIP_PASS | ",shop.get_meta("shop_title")," | walls/floor/ceiling | clear aisle | counter collision | same street door")
	print("SHOP_INTERIOR_CHECK_PASS | 3 shelved shops (empty shop + salon covered by other checks) | E transition guard | original human size")
	quit()
