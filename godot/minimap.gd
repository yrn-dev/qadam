extends Control
# Round district map in the bottom-left corner. The whole neighbourhood is
# always visible (north stays up): every shop with its name, the player's
# home, the player themselves, and the active delivery target with the
# walking route — so you always know where you are and where to go.
const SIZE:=240.0
const RING:=116.0
var game:Node3D
var refresh:=0.0
var pulse:=0.0
var target_local:Vector2=Vector2.ZERO
var has_target:=false
var route:=PackedVector2Array()
var sub:SubViewport
var map_view:MapView
var pl:Vector3=Vector3.ZERO
# Pixels per metre: the whole district (140 m deep) fits into the round frame.
var px_per_m:float=(RING*2.0-20.0)/140.0

class MapView extends Control:
	var mm
	func to_screen(m:Vector2) -> Vector2:
		return Vector2(mm.SIZE/2,mm.SIZE/2)+Vector2(m.x,m.y)*mm.px_per_m
	func label(pos:Vector2,text:String,color:Color) -> void:
		var w:float=ThemeDB.fallback_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
		draw_rect(Rect2(pos+Vector2(-w*0.5-5,-9),Vector2(w+10,15)),Color(0.03,0.06,0.08,0.78))
		draw_string(ThemeDB.fallback_font,pos+Vector2(-w*0.5,3.5),text,HORIZONTAL_ALIGNMENT_LEFT,w,11,color)
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,Vector2(mm.SIZE,mm.SIZE)),Color("141f2c"))
		# District ground
		draw_rect(Rect2(to_screen(Vector2(-54,-70)),Vector2(108,140)*mm.px_per_m),Color("223640"))
		# Roads
		var roads:=[Rect2(-31,-58,8,116),Rect2(23,-58,8,116),Rect2(-31,-58,62,8),Rect2(-31,50,62,8),Rect2(-31,-4,62,8)]
		for road in roads:
			var r:Rect2=road
			draw_rect(Rect2(to_screen(r.position),r.size*mm.px_per_m),Color("5a6d73"))
		# Zebra crossings
		var zebra:=Color(1,1,1,0.5)
		for i in 8:
			var z:float=-5.25+i*1.4
			draw_rect(Rect2(to_screen(Vector2(-0.75,z)),Vector2(1.5,0.7)*mm.px_per_m),zebra)
		for sx in [-27.0,27.0]:
			for sz in [-8.4,8.4]:
				for i in 8:
					var x:float=sx-5.25+i*1.4
					draw_rect(Rect2(to_screen(Vector2(x,sz-0.75)),Vector2(0.7,1.5)*mm.px_per_m),zebra)
		# Buildings
		for box in mm.game.town.footprints:
			var b:AABB=box
			var corner:Vector2=to_screen(Vector2(b.position.x,b.position.z))-Vector2(b.size.x,b.size.z)*mm.px_per_m*0.5
			draw_rect(Rect2(corner,Vector2(b.size.x,b.size.z)*mm.px_per_m),Color("40505c"))
		# Shops — named, so they are always findable
		if is_instance_valid(mm.game.story):
			for i in mm.game.town.shops.size():
				var sp:Vector3=mm.game.town.shops[i].position
				var p:=to_screen(Vector2(sp.x,sp.z))
				draw_circle(p,5,Color("0b1720"))
				draw_circle(p,3.5,Color("75d4ab"))
				label(p+Vector2(0,-11),mm.game.story.shop_name(i),Color("c8f5e5"))
		# Player's home
		if is_instance_valid(mm.game.story) and mm.game.story.home_index()>=0:
			var hd:Dictionary=mm.game.home_visits.doors[mm.game.story.home_index()]
			var hp:=to_screen(Vector2(hd.landing.x,hd.landing.z))
			draw_circle(hp,5,Color("0b1720"))
			draw_circle(hp,3.5,Color("bd9ef5"))
			label(hp+Vector2(0,-11),"ҮЙІМ",Color("e0d4fa"))
		# Delivery target (pulsing)
		if mm.has_target:
			var tp:=to_screen(mm.target_local)
			var ph:float=fposmod(mm.pulse,1.6)/1.6
			draw_arc(tp,5.0+5.0*ph,0,TAU,24,Color("edb761",0.7*(1.0-ph)),1.5)
			draw_circle(tp,6.5,Color("182b32"))
			draw_circle(tp,5,Color("edb761"))
		# Route to the target
		if mm.route.size()>1:
			var line:=PackedVector2Array()
			for point in mm.route:line.append(to_screen(point))
			draw_polyline(line,Color("f4c77d",0.85),2.0,true)
		# Player: blue arrow at the real position, pointing where they look
		var p:=to_screen(Vector2(mm.pl.x,mm.pl.z))
		var forward:=Vector2(-sin(mm.game.yaw),-cos(mm.game.yaw))
		var side:=Vector2(-forward.y,forward.x)
		draw_circle(p,7.5,Color("123047"))
		draw_colored_polygon(PackedVector2Array([p+forward*10,p-forward*5.5+side*5,p-forward*2,p-forward*5.5-side*5]),Color("79cafa"))

func _ready() -> void:
	custom_minimum_size=Vector2(SIZE,SIZE)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	sub=SubViewport.new()
	sub.size=Vector2i(int(SIZE),int(SIZE))
	sub.transparent_bg=true
	sub.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(sub)
	map_view=MapView.new()
	map_view.mm=self
	map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub.add_child(map_view)
	var tex:=TextureRect.new()
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.texture=sub.get_texture()
	tex.stretch_mode=TextureRect.STRETCH_SCALE
	tex.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var mat:=ShaderMaterial.new()
	var sh:=Shader.new()
	sh.code="shader_type canvas_item;void fragment(){float d=length(UV-vec2(0.5))*2.0;vec4 c=texture(TEXTURE,UV);c.a*=1.0-smoothstep(0.985,1.0,d);COLOR=c;}"
	mat.shader=sh
	tex.material=mat
	add_child(tex)

func _draw() -> void:
	draw_circle(Vector2(SIZE/2,SIZE/2),SIZE/2,Color(0.05,0.09,0.12,0.9))
	draw_arc(Vector2(SIZE/2,SIZE/2),RING,0,TAU,72,Color("79cafa",0.55),2.0)
	draw_arc(Vector2(SIZE/2,SIZE/2),SIZE/2-0.5,0,TAU,72,Color(1,1,1,0.12),1.0)
	draw_rect(Rect2(Vector2(SIZE/2-14,8),Vector2(28,16)),Color(0.03,0.06,0.08,0.78))
	draw_string(ThemeDB.fallback_font,Vector2(SIZE/2-10,20),"СҚ",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color(1,1,1,0.75))

func player_local() -> Vector3:
	var world:Vector3=game.player.global_position
	if game.shop_visits.inside():world=game.shop_visits.return_position
	elif game.home_visits.inside():world=game.home_visits.return_position
	return game.town.to_local(world)

func _process(delta:float) -> void:
	var hide:bool=game.menu_active() or (is_instance_valid(game.story_ui) and game.story_ui.is_modal())
	visible=not hide
	sub.render_target_update_mode=SubViewport.UPDATE_DISABLED if hide else SubViewport.UPDATE_ALWAYS
	if hide:return
	pl=player_local()
	pulse+=delta
	refresh-=delta
	if refresh<=0:
		refresh=0.5
		_update_target()
	map_view.queue_redraw()

func _update_target() -> void:
	has_target=false
	route.clear()
	if not is_instance_valid(game) or game.town.shops.is_empty():return
	var story:Node=game.story
	if is_instance_valid(story) and story.salon_phase==1:
		_route_to(game.town.to_local(game.town.shops[0].to_global(Vector3(4.1,0,0))))
		return
	if is_instance_valid(story) and story.salon_phase==2:
		_route_to(game.town.to_local(game.town.shops[4].to_global(Vector3(4.1,0,0))))
		return
	if not is_instance_valid(story) or story.delivery_id.is_empty():return
	var d:Dictionary=game.home_visits.doors[story.delivery_index()]
	_route_to(game.town.to_local(d.landing))
func _route_to(point_local:Vector3) -> void:
	target_local=Vector2(point_local.x,point_local.z)
	has_target=true
	var graph:AStar2D=game.town.population.graph
	if graph.get_point_count()==0:return
	var from:int=game.town.population.nearest_point(Vector2(pl.x,pl.z))
	var to:int=game.town.population.nearest_point(target_local)
	route=graph.get_point_path(from,to)
