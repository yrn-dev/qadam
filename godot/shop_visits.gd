extends Node
signal transition_finished
const Room=preload("res://shop_room.gd")
const SalonRoom=preload("res://salon_room.gd")
var game:Node3D
var rooms:Array[Node3D]=[]
var current_shop:=-1
var busy:=false
var prompt:Label
var fade:ColorRect
var return_position:=Vector3.ZERO
var return_yaw:=0.0

func _ready() -> void:
	game=get_parent()
	for i in game.town.shops.size():
		var room:=Node3D.new();room.set_script(SalonRoom if i==4 else Room);room.name="ShopInterior_%d"%i
		game.add_child(room);room.position=Vector3(i*30,-100,0)
		room.build(str(game.town.shops[i].get_meta("shop_title")),i);rooms.append(room)
	var layer:=CanvasLayer.new();layer.layer=10;add_child(layer)
	prompt=Label.new();prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.grow_horizontal=Control.GROW_DIRECTION_BOTH;prompt.offset_top=-85;prompt.offset_bottom=-40
	prompt.offset_left=-300;prompt.offset_right=300;prompt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size",23)
	prompt.add_theme_color_override("font_outline_color",Color("14232a"));prompt.add_theme_constant_override("outline_size",8)
	layer.add_child(prompt)
	fade=ColorRect.new();fade.color=Color(0,0,0,0);fade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade);fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func inside() -> bool:return current_shop>=0

func nearby_shop() -> int:
	if is_instance_valid(game.home_visits) and (game.home_visits.inside() or game.home_visits.busy):return -1
	if inside() or busy or game.overview:return -1
	for i in game.town.shops.size():
		var shop:Node3D=game.town.shops[i]
		var local:Vector3=shop.to_local(game.player.global_position)
		# Only the actual front door, never the window, rear wall or roof.
		if local.x<1.5 or local.x>3.45 or absf(local.z)>.95 or absf(local.y)>1.3:continue
		var target:Vector3=shop.to_global(Vector3(1.55,1.25,0))
		if -game.camera.global_basis.z.dot((target-game.camera.global_position).normalized())>.3:return i
	return -1

func at_exit() -> bool:
	if not inside():return false
	var at:Vector3=rooms[current_shop].to_local(game.player.global_position)
	if absf(at.x)>1.2 or at.z<3.9 or at.z>5.8 or absf(at.y)>.8:return false
	var target:Vector3=rooms[current_shop].to_global(Room.EXIT)
	return -game.camera.global_basis.z.dot((target-game.camera.global_position).normalized())>.3

func _process(delta:float) -> void:
	if is_instance_valid(game.story) and rooms.size()>3:
		rooms[3].sale_sign.text="СІЗДІҢ ДҮКЕНІҢІЗ" if game.story.owns_shop else "САТЫЛАДЫ · 1 000 000 ₸"
		rooms[3].title=game.story.shop_name(3);game.town.shops[3].set_meta("shop_title",rooms[3].title)
	for i in rooms.size():rooms[i].update_cashier(game.camera,delta,i==current_shop and game.captured)
	prompt.text=""
	if busy or not game.captured or game.overview or (is_instance_valid(game.story_ui) and game.story_ui.is_modal()):return
	if inside():
		if at_exit():prompt.text="E  ·  Көшеге шығу"
	else:
		var target:=nearby_shop()
		if target>=0:prompt.text="E  ·  Кіру: "+str(game.town.shops[target].get_meta("shop_title"))

func interact() -> void:
	if is_instance_valid(game.home_visits) and (game.home_visits.inside() or game.home_visits.busy):return
	if busy or not game.captured or game.overview:return
	if inside():
		if at_exit():_transition(-1)
	else:
		var target:=nearby_shop()
		if target>=0:_transition(target)

func place_player(at:Vector3,angle:float) -> void:
	game.player.global_position=at;game.player.velocity=Vector3.ZERO
	game.camera.position=Vector3(0,1.65,0);game.yaw=angle;game.pitch=0
	game.camera.rotation=Vector3(0,angle,0);game.overview=false

func _transition(target:int) -> void:
	busy=true;prompt.text="";game.player.velocity=Vector3.ZERO
	var tween:=create_tween();tween.tween_property(fade,"color:a",1.0,.14)
	await tween.finished
	if target>=0:
		var shop:Node3D=game.town.shops[target]
		return_position=shop.to_global(Vector3(2.8,.12,0))
		var outward:Vector3=shop.global_basis.x.normalized()
		return_yaw=atan2(-outward.x,-outward.z)
		current_shop=target;game.set_street_active(false);game.town.player=null
		rooms[target].visible=true;game.camera.environment=rooms[target].interior_environment
		place_player(rooms[target].to_global(Room.ENTRY),0)
	else:
		rooms[current_shop].visible=false;current_shop=-1
		game.set_street_active(true);game.town.player=game.player;game.camera.environment=null
		place_player(return_position,return_yaw)
	await get_tree().physics_frame
	tween=create_tween();tween.tween_property(fade,"color:a",0.0,.18)
	await tween.finished
	busy=false;transition_finished.emit()

func reset_inside() -> void:
	place_player(rooms[current_shop].to_global(Room.ENTRY),0)
