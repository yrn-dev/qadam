extends Control
signal destination_selected(label:String)
const Layout=preload("res://district_layout.gd")
var game:Node3D
var selected_shop:=0
var selected_home:=false
var home_marker:=Vector2(-100,-100)
var route:=PackedVector2Array()
var route_length:=0.0
var refresh:=0.0
var zoom:=1.0
var pan:=Vector2.ZERO
var dragging:=false
var drag_distance:=0.0
var marker_positions:Array[Vector2]=[]
var target_name:=""
var reachable:=true

func _ready() -> void:
	clip_contents=true;mouse_filter=Control.MOUSE_FILTER_STOP
	custom_minimum_size=Vector2(270,290)
func player_local() -> Vector3:
	var world:Vector3=game.player.global_position
	if game.shop_visits.inside():world=game.shop_visits.return_position
	elif game.home_visits.inside():world=game.home_visits.return_position
	return game.town.to_local(world)
func scale_factor() -> float:return minf((size.x-28)/108.0,(size.y-28)/140.0)*zoom
func map_point(point:Vector2) -> Vector2:return size/2+point*scale_factor()+pan
func choose_shop(index:int) -> void:
	selected_home=false;selected_shop=index;target_name=game.story.shop_name(index);refresh=0
	destination_selected.emit(target_name);queue_redraw()
func choose_home() -> void:
	selected_home=true;target_name="Менің пәтерім";refresh=0
	destination_selected.emit(target_name);queue_redraw()
func center_map() -> void:zoom=1;pan=Vector2.ZERO;queue_redraw()
func update_route() -> void:
	if game.town.shops.is_empty():return
	var origin:=player_local()
	var target:Vector3
	if selected_home and game.story.home_index()>=0:
		target=game.town.to_local(game.home_visits.doors[game.story.home_index()].landing)
		target_name="Менің пәтерім · "+game.story.address_for(game.story.home_index())
	elif selected_shop==3:
		target=game.town.to_local(game.town.shops[3].to_global(Vector3(2.8,.12,0)));target_name=game.story.shop_name(3)
	elif selected_shop==4:
		target=game.town.to_local(game.town.shops[4].to_global(Vector3(4.1,.12,0)));target_name=game.story.shop_name(4)
	elif not game.story.delivery_id.is_empty():
		var d:Dictionary=game.home_visits.doors[game.story.delivery_index()]
		target=game.town.to_local(d.landing);target_name=game.story.address()
	else:
		if game.story.pending_payment>0:selected_shop=game.story.employer
		if selected_shop<0:
			if game.story.employer>=0:selected_shop=game.story.employer
			else:
				var closest:=INF
				for i in game.town.shops.size():
					var distance:float=game.town.shops[i].position.distance_squared_to(origin)
					if distance<closest:closest=distance;selected_shop=i
		target=game.town.to_local(game.town.shops[selected_shop].to_global(Vector3(2.8,.12,0)))
		target_name=game.story.shop_name(selected_shop)
	var graph:AStar2D=game.town.population.graph
	if graph.get_point_count()==0:return
	var from:int=game.town.population.nearest_point(Vector2(origin.x,origin.z))
	var to:int=game.town.population.nearest_point(Vector2(target.x,target.z))
	route=graph.get_point_path(from,to);reachable=not route.is_empty();route_length=0
	for i in range(1,route.size()):route_length+=route[i-1].distance_to(route[i])*Layout.ENVIRONMENT_SCALE
func _process(delta:float) -> void:
	if not is_visible_in_tree():return
	refresh-=delta
	if refresh<=0:refresh=.5;update_route()
	queue_redraw()
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("172a32"))
	if not is_instance_valid(game):return
	var scale:=scale_factor()
	draw_rect(Rect2(map_point(Vector2(-54,-70)),Vector2(108,140)*scale),Color("263c3d"))
	var roads:=[Rect2(-31,-58,8,116),Rect2(23,-58,8,116),Rect2(-31,-58,62,8),Rect2(-31,50,62,8),Rect2(-31,-4,62,8)]
	for road in roads:draw_rect(Rect2(map_point(road.position),road.size*scale),Color("56676b"))
	for box in game.town.footprints:
		draw_rect(Rect2(map_point(Vector2(box.position.x,box.position.z)),Vector2(box.size.x,box.size.z)*scale),Color("9a9987"))
	if route.size()>1:
		var line:=PackedVector2Array()
		for point in route:line.append(map_point(point))
		draw_polyline(line,Color("f4c77d"),3,true)
	marker_positions.clear()
	for i in game.town.shops.size():
		var at:Vector3=game.town.shops[i].position
		var point:=map_point(Vector2(at.x,at.z));marker_positions.append(point)
		draw_circle(point,8,Color("0b1720"));draw_circle(point,5,Color("75d4ab"))
		draw_string(ThemeDB.fallback_font,point+Vector2(9,-6),game.story.shop_name(i),HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("f5eedb"))
	if not game.story.delivery_id.is_empty():
		var at:Vector3=game.town.to_local(game.home_visits.doors[game.story.delivery_index()].landing)
		var p:=map_point(Vector2(at.x,at.z));draw_circle(p,9,Color("edb761"));draw_circle(p,4,Color("182b32"))
	if game.story.home_index()>=0:
		var home_at:Vector3=game.town.to_local(game.home_visits.doors[game.story.home_index()].landing)
		home_marker=map_point(Vector2(home_at.x,home_at.z))
		draw_circle(home_marker,8,Color("bd9ef5"))
		draw_string(ThemeDB.fallback_font,home_marker+Vector2(9,13),"ҮЙІМ",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("e0d4fa"))
	var at:=player_local();var p:=map_point(Vector2(at.x,at.z))
	var forward:=Vector2(-sin(game.yaw),-cos(game.yaw));var side:=Vector2(-forward.y,forward.x)
	draw_circle(p,9,Color("183a54"))
	draw_colored_polygon(PackedVector2Array([p+forward*10,p-forward*6+side*5,p-forward*3,p-forward*6-side*5]),Color("79cafa"))
	draw_string(ThemeDB.fallback_font,Vector2(size.x-24,20),"СҚ",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
	draw_line(Vector2(size.x-20,27),Vector2(size.x-20,40),Color.WHITE,1.5)
	draw_string(ThemeDB.fallback_font,Vector2(9,size.y-10),"50 м",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("bfcdd1"))
	draw_line(Vector2(46,size.y-14),Vector2(46+50/Layout.ENVIRONMENT_SCALE*scale,size.y-14),Color("bfcdd1"),2)
func _gui_input(event:InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:zoom=minf(2.7,zoom*1.15);accept_event()
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:zoom=maxf(1,zoom/1.15);accept_event()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:dragging=true;drag_distance=0
			else:
				dragging=false
				if drag_distance<8:
					if event.position.distance_to(home_marker)<18:choose_home();accept_event();return
					for i in marker_positions.size():
						if event.position.distance_to(marker_positions[i])<18:choose_shop(i);break
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		pan+=event.relative;pan=pan.clamp(-size*.8,size*.8);drag_distance+=event.relative.length();accept_event()
	queue_redraw()
