extends Node
signal transition_finished
const Room=preload("res://home_room.gd")
var game:Node3D
var rooms:Array[Node3D]=[]
var doors:Array[Dictionary]=[]
var door_cells:Dictionary={}
var prompt_clock:=0.0
var current_home:=-1
var current_door:=-1
var busy:=false
var residents:Array[Node3D]=[]
var recipient_id:=""
var delivery_done:=false
var prompt:Label
var fade:ColorRect
var return_position:=Vector3.ZERO
var return_yaw:=0.0

func vector(values:Array) -> Vector3:return Vector3(values[0],values[1],values[2])
func variant_for(door:Dictionary) -> int:
	match str(door.model):
		"townhouse":return 0
		"solar_house":return 1
		"round_tower":return 3
		"square_tower":return 3 if int(door.building_index)%2==0 else 4
		_:return 2 if int(door.building_index)%2==0 else 4

func _ready() -> void:
	game=get_parent()
	var inventory:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://door_inventory.json"))
	for record in inventory.doors:
		if record.model=="cartoon_shop" or record.status!="accessible":continue
		var door:Dictionary=record.duplicate(true)
		door["point"]=vector(record.position_world);door["landing"]=vector(record.landing_world)
		door["normal"]=vector(record.outward_world);door["variant"]=variant_for(door)
		var cell:=Vector2i(floori(door.landing.x/8.0),floori(door.landing.z/8.0))
		if not door_cells.has(cell):door_cells[cell]=[]
		door_cells[cell].append(doors.size())
		doors.append(door)
	for i in 5:
		var room:=Node3D.new();room.set_script(Room);room.name="HomeInterior_%d"%i
		game.add_child(room);room.position=Vector3(i*30,-200,0);room.build(i);rooms.append(room)
	var layer:=CanvasLayer.new();layer.layer=11;add_child(layer)
	prompt=Label.new();layer.add_child(prompt);prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left=-380;prompt.offset_right=380;prompt.offset_top=-85;prompt.offset_bottom=-40
	prompt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;prompt.add_theme_font_size_override("font_size",23)
	prompt.add_theme_color_override("font_outline_color",Color("14232a"));prompt.add_theme_constant_override("outline_size",8)
	prompt.mouse_filter=Control.MOUSE_FILTER_IGNORE
	fade=ColorRect.new();fade.color=Color(0,0,0,0);fade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade);fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	print("HOME_ENTRANCES_READY | doors=",doors.size()," | layouts=",rooms.size())

func inside() -> bool:return current_home>=0
func nearby_home() -> int:
	if inside() or busy or game.overview or game.shop_visits.inside() or game.shop_visits.busy:return -1
	var best:=-1
	var nearest:=3.5
	var cell:=Vector2i(floori(game.player.global_position.x/8.0),floori(game.player.global_position.z/8.0))
	var candidates:Array=[]
	for x in [-1,0,1]:
		for z in [-1,0,1]:candidates.append_array(door_cells.get(cell+Vector2i(x,z),[]))
	for i in candidates:
		var d:Dictionary=doors[i]
		var offset:Vector3=game.player.global_position-d.landing
		if absf(offset.y)>1.1 or Vector2(offset.x,offset.z).length()>1.55:continue
		if (game.player.global_position-d.point).dot(d.normal)<.25:continue
		var sight:Vector3=d.point-game.camera.global_position
		if sight.length()>nearest or -game.camera.global_basis.z.dot(sight.normalized())<.55:continue
		# The approach must be visible: no interaction through an adjacent wall.
		var ray:=PhysicsRayQueryParameters3D.create(game.camera.global_position,d.landing+Vector3.UP*1.35,1)
		if not game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():continue
		nearest=sight.length();best=i
	return best

func at_exit() -> bool:
	if not inside():return false
	var room:Node3D=rooms[current_home]
	var local:Vector3=room.to_local(game.player.global_position)
	if absf(local.x)>1 or absf(local.y)>.8 or local.z<room.size.y/2-1.9:return false
	return -game.camera.global_basis.z.dot((room.to_global(room.exit_point)-game.camera.global_position).normalized())>.4

func _process(delta:float) -> void:
	for actor in residents:
		if game.captured:actor.update_detail(game.camera,delta)
		else:actor.animation.active=false
	if is_instance_valid(game.story_ui) and game.story_ui.is_modal():prompt.text="";return
	if busy or not game.captured or game.overview:prompt.text="";return
	prompt_clock-=delta
	if prompt_clock>0:return
	prompt_clock=.08
	prompt.text=""
	if inside():
		if at_exit():prompt.text="E  ·  Көшеге шығу"
		elif delivery_done:prompt.text="Тапсырыс берілді. Есіктен шығып, дүкенге орал."
	else:
		var door:=nearby_home()
		if door>=0:
			if door==game.story.home_index():prompt.text="E  ·  Менің пәтерім"
			elif game.story.can_enter(door):prompt.text="E  ·  Алушының үйіне кіру"
			else:prompt.text="Жеке тұрғын үй · Тапсырыссыз кіруге болмайды"

func interact() -> void:
	if busy or not game.captured or game.overview or game.shop_visits.inside() or game.shop_visits.busy:return
	if inside():
		if at_exit():_transition(-1)
	else:
		var door:=nearby_home()
		if door>=0 and game.story.can_enter(door):_transition(door)

func place_player(at:Vector3,angle:float) -> void:
	game.shop_visits.place_player(at,angle)

func _transition(target:int,resume:bool=false) -> void:
	if target>=doors.size():return
	var restoring:bool=resume and target>=0 and game.story.resume_location.get("door_id","")==str(doors[target].id) and game.story.pending_payment>0
	if busy or (target>=0 and (inside() or (not game.story.can_enter(target) and not restoring))):return
	if target<0 and not inside():return
	busy=true;prompt.text="";game.player.velocity=Vector3.ZERO
	var tween:=create_tween();tween.tween_property(fade,"color:a",1.0,.14);await tween.finished
	if target>=0:
		return_position=doors[target].landing if resume else game.player.global_position
		var outward:Vector3=doors[target].normal;return_yaw=atan2(-outward.x,-outward.z)
		current_door=target;current_home=int(doors[target].variant)
		game.set_street_active(false);game.town.player=null
		var room:Node3D=rooms[current_home];room.visible=true;game.camera.environment=room.interior_environment
		place_player(room.to_global(room.entry),0)
		delivery_done=restoring and game.story.delivery_id.is_empty()
		if target!=game.story.home_index():_spawn_residents(room,target)
	else:
		_clear_residents()
		rooms[current_home].visible=false;current_home=-1;current_door=-1;delivery_done=false
		game.set_street_active(true);game.town.player=game.player;game.camera.environment=null
		place_player(return_position,return_yaw)
	await get_tree().physics_frame
	tween=create_tween();tween.tween_property(fade,"color:a",0.0,.18);await tween.finished
	busy=false;transition_finished.emit()

func reset_inside() -> void:
	place_player(rooms[current_home].to_global(rooms[current_home].entry),0)

func is_recipient(id:String) -> bool:
	return not id.is_empty() and id==recipient_id and inside() and not delivery_done

func _clear_residents() -> void:
	for actor in residents:
		var id:String=actor.get_meta("npc_id","")
		game.story_ui.actors.erase(id)
		actor.queue_free()
	residents.clear();recipient_id=""

func _spawn_residents(room:Node3D,door:int) -> void:
	_clear_residents()
	# Clear foyer positions: keep the doorway and the player's capsule unobstructed.
	var candidates:Array[Vector3]=[]
	for z in [room.entry.z-1.55,room.entry.z-2.35,room.entry.z-.9]:
		for x in [0.0,-1.1,1.1,-2.0,2.0]:candidates.append(Vector3(x,.035,z))
	var occupied:Array[Vector3]=[]
	# One recipient per delivery visit; extra hosts look like a crowd bug.
	var wanted:=1
	for at in candidates:
		if residents.size()>=wanted:break
		if at.distance_to(room.entry)<1.25:continue
		var clear:=true
		for used in occupied:
			if at.distance_to(used)<1.1:clear=false
		if not clear:continue
		var world:Vector3=room.to_global(at)
		var query:=PhysicsShapeQueryParameters3D.new()
		var shape:=CapsuleShape3D.new();shape.radius=.38;shape.height=1.78
		query.shape=shape;query.collision_mask=1|2|8;query.transform.origin=world+Vector3.UP*.91
		if not game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():continue
		# Every host is reachable directly from the foyer, never behind a partition.
		var from:=Transform3D(Basis.IDENTITY,room.to_global(room.entry))
		if game.player.test_move(from,world-from.origin):continue
		var slot:=residents.size()
		var id:="resident_%s_%d"%[str(doors[door].id),slot]
		var profile:Dictionary=game.story_ui.resident_profile(id,door,slot)
		var actor:=Node3D.new();actor.set_script(preload("res://citizen_visual.gd"))
		actor.character_id=profile.character;actor.outfit_variant=profile.outfit;actor.initial_motion="idle"
		room.add_child(actor);actor.position=at;actor.rotation.y=PI
		actor.set_meta("npc_id",id)
		var body:=StaticBody3D.new();body.collision_layer=8;actor.add_child(body)
		var collision:=CollisionShape3D.new();collision.shape=shape;collision.position.y=.89;body.add_child(collision)
		game.story_ui.actors[id]=actor
		if slot==0:recipient_id=id
		residents.append(actor);occupied.append(at)
	if residents.is_empty():push_error("No clear delivery recipient position in home variant "+str(current_home))
