extends Node3D
# ANA BEAUTY salon room. The layout follows the reference render:
# a counter with a long mirror and bottles along the west wall, two dark
# styling chairs facing the glass, a pink treatment curtain in the middle,
# a teal waiting row with a magazine table on the east, framed pictures,
# wooden floor, pink wainscot with a red trim line.
# The room is alive on its own: the receptionist keeps the counter, the
# stylist walks over and really cuts a client's hair (scissors and falling
# hair), an attendant keeps the floor tidy, and clients arrive, wait, sit,
# get styled and leave again.

const ASSETS="res://assets/cartoon/prepared/"
const ENTRY=Vector3(0,.08,4.5)
const EXIT=Vector3(0,1.2,5.82)
const WOOD=Color("96633a")
const WALL_UP=Color("f2f4f7")
const WALL_LOW=Color("f5c9d6")
const TRIM=Color("c2374a")
const TEAL=Color("7fc7b5")
const DARK=Color("2f2c36")
var title:=""
var layout_id:=4
var props:Array[MeshInstance3D]=[]
var interior_environment:Environment
var cashier:Node3D
var cashier_body:StaticBody3D
var checkout:MeshInstance3D
var checkout_approach:=Vector3(-2.5,.08,4.2)
var talkable_actors:Array=[]
# --- the living salon -----------------------------------------------------
var stylist:CharacterBody3D
var attendant:CharacterBody3D
var clients:Array[Dictionary]=[]
var chairs:Array[Dictionary]=[]
var scissors:MeshInstance3D
var scissors_on:=false
var snip_clock:=0.0
var clip_parts:Array[Dictionary]=[]
var next_arrival:=9.0
var cut_time:=0.0
var stylist_state:=0 # 0 home, 1 walking, 2 cutting
var stylist_target:Vector3=Vector3.ZERO
var stylist_client:=-1
var attendant_route:PackedVector3Array=[]
var attendant_index:=0
var attendant_wait:=0.0
var rng:=RandomNumberGenerator.new()

func block(label:String,at:Vector3,size:Vector3,color:Color,solid:bool=true) -> MeshInstance3D:
	var mesh:=MeshInstance3D.new();mesh.name=label
	var box:=BoxMesh.new();box.size=size;mesh.mesh=box
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.85
	mesh.material_override=material;add_child(mesh);mesh.position=at
	props.append(mesh)
	if solid:mesh.create_trimesh_collision()
	return mesh

func text_label(words:String,at:Vector3,size:int=52,angle:float=0,color:Color=Color("fff3d6")) -> Label3D:
	var label:=Label3D.new();label.text=words;label.font_size=size;label.pixel_size=.008
	label.modulate=color;label.outline_size=0;add_child(label);label.position=at;label.rotation.y=angle
	return label

func prop(id:String,at:Vector3,angle:float=0,factor:float=1,solid:bool=false) -> MeshInstance3D:
	var mesh:=MeshInstance3D.new();mesh.mesh=load(ASSETS+id+".res");mesh.name=id;mesh.set_meta("asset_id",id)
	add_child(mesh);mesh.position=at;mesh.rotation.y=angle;mesh.scale=Vector3.ONE*factor
	if solid:mesh.create_trimesh_collision()
	props.append(mesh)
	return mesh

func solid_box(at:Vector3,size:Vector3,label:String="Solid") -> StaticBody3D:
	var body:=StaticBody3D.new();body.name=label;body.collision_layer=1;body.position=at
	var cs:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;cs.shape=box
	body.add_child(cs);add_child(body)
	return body

func make_npc(character:String,outfit:int,at:Vector3,ry:float) -> CharacterBody3D:
	var n:=CharacterBody3D.new()
	n.set_script(preload("res://citizen_visual.gd"))
	n.character_id=character;n.outfit_variant=outfit;n.initial_motion="idle"
	n.collision_layer=1;n.collision_mask=0
	n.motion_mode=CharacterBody3D.MOTION_MODE_FLOATING
	var shape:=CollisionShape3D.new();var cap:=CapsuleShape3D.new()
	cap.radius=.3;cap.height=1.75;shape.shape=cap;shape.position.y=.875
	n.add_child(shape)
	add_child(n);n.position=at;n.rotation.y=ry
	return n

func _move_towards(node:CharacterBody3D,target:Vector3,speed:float,dt:float) -> bool:
	var dir:Vector3=target-node.position
	dir.y=0
	var dist:=dir.length()
	if dist<0.12:
		node.position.x=target.x;node.position.z=target.z
		return true
	dir/=dist
	node.position+=dir*minf(dist,speed*dt)
	node.rotation.y=lerp_angle(node.rotation.y,atan2(-dir.x,-dir.y),12.0*dt)
	return false

func build(_shop_title:String,_index:int) -> void:
	title="ANA BEAUTY"
	rng.randomize()
	# Shell: wood floor, white upper walls, pink wainscot with a red line.
	block("Floor",Vector3(0,-.12,0),Vector3(10.4,.24,12.4),WOOD)
	block("WestWall",Vector3(-5.1,1.8,0),Vector3(.2,3.6,12.4),WALL_UP)
	block("EastWall",Vector3(5.1,1.8,0),Vector3(.2,3.6,12.4),WALL_UP)
	block("BackWall",Vector3(0,1.8,-6.1),Vector3(10.4,3.6,.2),WALL_UP)
	block("FrontWall",Vector3(0,1.8,6.1),Vector3(10.4,3.6,.2),WALL_UP)
	block("Ceiling",Vector3(0,3.7,0),Vector3(10.4,.2,12.4),Color("eef0f2"))
	block("WainscotWest",Vector3(-5.05,.55,0),Vector3(.1,1.1,12),WALL_LOW,false)
	block("WainscotEast",Vector3(5.05,.55,0),Vector3(.1,1.1,12),WALL_LOW,false)
	block("WainscotBack",Vector3(0,.55,-6.05),Vector3(10.2,1.1,.1),WALL_LOW,false)
	block("WainscotFront",Vector3(0,.55,6.05),Vector3(10.2,1.1,.1),WALL_LOW,false)
	block("TrimWest",Vector3(-5.04,1.14,0),Vector3(.08,.07,12),TRIM,false)
	block("TrimEast",Vector3(5.04,1.14,0),Vector3(.08,.07,12),TRIM,false)
	block("TrimBack",Vector3(0,1.14,-6.04),Vector3(10.2,.07,.08),TRIM,false)
	block("TrimFront",Vector3(0,1.14,6.04),Vector3(10.2,.07,.08),TRIM,false)
	# Door (same frame as the other rooms, so ENTRY/EXIT keep working).
	block("DoorFrame",Vector3(0,1.32,5.92),Vector3(1.7,2.64,.13),TRIM)
	block("ExitDoor",Vector3(0,1.23,5.83),Vector3(1.38,2.46,.08),Color("d98ba3"))
	block("DoorGlass",Vector3(0,1.67,5.775),Vector3(1.08,1.05,.025),Color("a9d6d4"),false)
	block("DoorHandle",Vector3(-.48,1.0,5.70),Vector3(.07,.3,.1),Color("e6d9b3"),false)
	text_label("ШЫҒУ",Vector3(0,2.95,5.8),36,PI,TRIM)
	# Solid bodies: the player stays inside, NPCs never cross walls.
	solid_box(Vector3(-5.1,1.8,0),Vector3(.2,3.6,12.4),"WallBodyW")
	solid_box(Vector3(5.1,1.8,0),Vector3(.2,3.6,12.4),"WallBodyE")
	solid_box(Vector3(0,1.8,-6.1),Vector3(10.4,3.6,.2),"WallBodyB")
	solid_box(Vector3(-2.98,1.8,6.1),Vector3(4.24,3.6,.2),"WallBodyF1")
	solid_box(Vector3(2.98,1.8,6.1),Vector3(4.24,3.6,.2),"WallBodyF2")
	solid_box(Vector3(0,2.9,6.1),Vector3(1.7,1.6,.2),"WallBodyF3")
	# Reception counter: a free-standing island in the front of the room; the
	# cashier stands behind it, the door side stays open for the walk-in.
	solid_box(Vector3(-2.5,.5,3.0),Vector3(3.4,1.0,1.3),"CounterBody")
	block("CounterBase",Vector3(-2.5,.5,3.0),Vector3(3.4,.92,1.3),Color("f6f1ea"),false)
	block("CounterKick",Vector3(-2.5,.04,3.0),Vector3(3.2,.08,1.2),Color("c9b8a0"),false)
	block("CounterTop",Vector3(-2.5,1.0,3.0),Vector3(3.7,.1,1.6),Color("d9c8a8"),false)
	block("CounterBand",Vector3(-2.5,.55,3.66),Vector3(3.4,.5,.06),Color("f2a7c3"),false)
	text_label("ANA BEAUTY",Vector3(-2.5,.6,3.72),22,0,Color("8a3d5e"))
	# Register and products on the counter.
	block("RegisterBody",Vector3(-3.5,1.22,2.82),Vector3(.36,.26,.26),Color("3a3d45"),false)
	block("RegisterScreen",Vector3(-3.5,1.28,2.68),Vector3(.3,.2,.04),Color("7fc7b5"),false)
	block("Towels",Vector3(-3.95,1.16,3.2),Vector3(.42,.2,.3),Color("f6f4ef"),false)
	var bottle_colors:=[Color("3f7fd9"),Color("e8c33f"),Color("4caf72"),Color("d95f8a"),Color("8a5fd9"),Color("46b8c9")]
	for i in 6:
		var h:float=rng.randf_range(.18,.3)
		block("Bottle%d"%i,Vector3(-3.6+i*.4,1.05+h*.5,3.2),Vector3(.1,h,.1),bottle_colors[i],false)
	# Styling mirror on the west wall, centred on the two chairs in front of it.
	block("Mirror",Vector3(-4.97,1.9,-1.7),Vector3(.05,1.15,4.6),Color("c2dbe8"),false)
	block("MirrorFrameT",Vector3(-4.95,2.53,-1.7),Vector3(.07,.08,4.76),Color("f6f1ea"),false)
	block("MirrorFrameB",Vector3(-4.95,1.27,-1.7),Vector3(.07,.08,4.76),Color("f6f1ea"),false)
	block("MirrorFrameL",Vector3(-4.95,1.9,-4.04),Vector3(.07,1.34,.08),Color("f6f1ea"),false)
	block("MirrorFrameR",Vector3(-4.95,1.9,0.64),Vector3(.07,1.34,.08),Color("f6f1ea"),false)
	# Small vanity stand between the two styling chairs.
	block("StandTop",Vector3(-4.0,.92,-1.7),Vector3(.5,.05,.4),Color("f7f2ea"),false)
	block("StandLeg",Vector3(-4.0,.46,-1.7),Vector3(.12,.9,.12),Color("d8d2c8"),false)
	block("StandBase",Vector3(-4.0,.03,-1.7),Vector3(.34,.06,.3),Color("d8d2c8"),false)
	var vanity:=MeshInstance3D.new();vanity.name="VanityLight"
	var vs:=SphereMesh.new();vs.radius=.12;vs.height=.24;vanity.mesh=vs
	var vm:=StandardMaterial3D.new();vm.albedo_color=Color("fff2d8");vm.emission_enabled=true
	vm.emission=Color("ffe9b8");vm.emission_energy_multiplier=1.2
	vanity.material_override=vm;add_child(vanity);vanity.position=Vector3(-4.0,1.12,-1.7)
	props.append(vanity)
	# Two dark styling chairs facing the mirror — booth style, so a seated
	# client's legs hide behind the shell (the rig has no sit animation).
	for i in 2:
		var cz:float=-3.2 if i==0 else -0.2
		block("ChairShell%d"%i,Vector3(-3.4,.31,cz),Vector3(.68,.62,.68),DARK,false)
		block("ChairSeat%d"%i,Vector3(-3.4,.66,cz),Vector3(.7,.1,.7),Color("4a4553"),false)
		block("ChairBack%d"%i,Vector3(-3.08,1.05,cz),Vector3(.16,.85,.7),DARK,false)
		solid_box(Vector3(-3.4,.4,cz),Vector3(.8,1.0,.7),"ChairBody%d"%i)
		chairs.append({"pos":Vector3(-3.4,0,cz),"occupied":false,"client":-1})
	# Pink treatment curtain with a walk-through gap (soft panels, no bands).
	block("CurtainBar",Vector3(-2.35,2.75,-4.55),Vector3(5.3,.07,.07),Color("22242a"),false)
	for cx in [-4.6,-3.5,-1.2,-0.1]:
		block("Curtain",Vector3(cx,1.45,-4.55),Vector3(1.0,2.55,.14),Color("f4c1d1"),false)
	# Treatment corner behind the curtain: red chair, floor lamp, radiator.
	block("RedSeat",Vector3(-2.8,.45,-5.35),Vector3(.5,.12,.5),Color("c0392b"),false)
	block("RedBack",Vector3(-2.8,.85,-5.6),Vector3(.5,.6,.12),Color("c0392b"),false)
	block("LampPost",Vector3(-4.55,.65,-5.5),Vector3(.05,1.3,.05),Color("8a8f98"),false)
	var lamp:=block("LampShade",Vector3(-4.55,1.45,-5.5),Vector3(.34,.4,.34),Color("5b8dd9"),false)
	var lamp_mat:StandardMaterial3D=lamp.material_override
	lamp_mat.emission_enabled=true;lamp_mat.emission=Color("9cc4ff");lamp_mat.emission_energy_multiplier=.9
	for i in 6:block("Radiator%d"%i,Vector3(-4.5+i*.55,.3,-5.95),Vector3(.08,.5,.05),Color("aeb4bc"),false)
	# Waiting bench along the east wall — one continuous seat, not loose parts.
	block("BenchBase",Vector3(4.62,.16,-0.65),Vector3(.5,.32,3.9),Color("e8e8e8"),false)
	block("BenchSeat",Vector3(4.6,.4,-0.65),Vector3(.55,.1,4.0),TEAL,false)
	block("BenchBack",Vector3(4.92,.82,-0.65),Vector3(.1,.62,4.0),Color("e8e8e8"),false)
	solid_box(Vector3(4.65,.35,-0.65),Vector3(.6,.7,4.0),"BenchBody")
	block("CoffeeTop",Vector3(3.0,.44,2.7),Vector3(1.2,.07,.7),Color("8a5a33"),false)
	for dx in [-.52,.52]:
		for dz in [-.28,.28]:block("CoffeeLeg",Vector3(3.0+dx,.21,2.7+dz),Vector3(.06,.42,.06),Color("6d4526"),false)
	solid_box(Vector3(3.0,.25,2.7),Vector3(1.2,.5,.7),"CoffeeBody")
	var mag_colors:=[Color("d64541"),Color("f0c040"),Color("4a90d9")]
	for i in 3:
		var m:=block("Magazine%d"%i,Vector3(2.85+i*.28,.485,2.62+i*.05),Vector3(.32,.02,.42),mag_colors[i],false)
		m.rotation.y=rng.randf_range(-.5,.5)
		props.erase(m)
	# Framed pictures on the east wall.
	for i in 3:
		var cz:float=-2.6+i*1.3
		block("Frame%d"%i,Vector3(5.03,2.0,cz),Vector3(.06,1.0,.72),Color("1a1a1a"),false)
		block("Photo%d"%i,Vector3(5.015,2.0,cz),Vector3(.03,.86,.58),Color("cfd8dc"),false)
	# Two-tone area rug grounding the waiting side of the room.
	block("RugBase",Vector3(1.6,.008,1.2),Vector3(6.4,.02,5.0),Color("e8b7c6"),false)
	block("RugTop",Vector3(1.6,.02,1.2),Vector3(5.6,.02,4.2),Color("f6e8dc"),false)
	# Potted plants in the corners.
	for i in 2:
		var px:float=4.7 if i==0 else -4.6
		var pz:float=-5.4 if i==0 else 5.3
		block("PlantPot%d"%i,Vector3(px,.2,pz),Vector3(.4,.4,.4),Color("c2795a"),false)
		var leaf:=MeshInstance3D.new()
		var lm:=SphereMesh.new();lm.radius=.42;lm.height=.84;leaf.mesh=lm
		var lmat:=StandardMaterial3D.new();lmat.albedo_color=Color("4f9a5c");lmat.roughness=.9
		leaf.material_override=lmat;add_child(leaf);leaf.position=Vector3(px,.85,pz);leaf.scale=Vector3(1,1.15,1)
		props.append(leaf)
	# Pendant lamps.
	for i in 2:
		var lz:float=-2.6 if i==0 else 0.2
		block("LampCord",Vector3(-1.0,3.4,lz),Vector3(.03,.5,.03),Color("3a3d45"),false)
		var shade:=MeshInstance3D.new();shade.name="Pendant%d"%i
		var sphere:=SphereMesh.new();sphere.radius=.3;sphere.height=.6;sphere.radial_segments=9;sphere.rings=6
		shade.mesh=sphere
		var mat:=StandardMaterial3D.new();mat.albedo_color=Color("f7f3e8");mat.roughness=.7
		mat.emission_enabled=true;mat.emission=Color("ffecc0");mat.emission_energy_multiplier=1.1
		shade.material_override=mat;add_child(shade);shade.position=Vector3(-1.0,3.05,lz)
		var light:=OmniLight3D.new();add_child(light);light.position=Vector3(-1.0,2.8,lz)
		light.light_color=Color("ffe4ba");light.light_energy=1.15;light.omni_range=8
	# Sign and the scissors prop for the haircut.
	text_label("ANA BEAUTY SALON",Vector3(2.2,2.75,-5.94),46,0,Color("d1577f"))
	text_label("09:00–21:00",Vector3(2.2,2.3,-5.93),26,0,Color("8a6a72"))
	scissors=MeshInstance3D.new();scissors.name="Scissors";scissors.visible=false
	var blade:=BoxMesh.new();blade.size=Vector3(.02,.18,.07);scissors.mesh=blade
	var smat:=StandardMaterial3D.new();smat.albedo_color=Color("2c2f36");scissors.material_override=smat
	add_child(scissors)
	# --- staff and clients -------------------------------------------------
	cashier=Node3D.new();cashier.name="Cashier";cashier.set_script(preload("res://citizen_visual.gd"))
	cashier.character_id="aruzhan";cashier.outfit_variant=3;cashier.initial_motion="idle"
	add_child(cashier);cashier.position=Vector3(-2.5,.02,1.55);cashier.rotation.y=0.0
	cashier.animation.active=false
	cashier_body=StaticBody3D.new();cashier_body.name="CashierBody";cashier_body.collision_layer=1
	cashier.add_child(cashier_body)
	var cc:=CollisionShape3D.new();var cap2:=CapsuleShape3D.new()
	cap2.radius=.3;cap2.height=1.75;cc.shape=cap2;cc.position.y=.875
	cashier_body.add_child(cc)
	stylist=make_npc("dana",5,Vector3(-2.55,.02,-2.9),1.23)
	stylist.name="Stylist"
	attendant=make_npc("erlan",7,Vector3(1.5,.02,3.0),0)
	attendant.name="Attendant"
	attendant_route=PackedVector3Array([
		Vector3(1.5,0,3.0),Vector3(3.0,0,0.9),Vector3(2.2,0,-3.2),
		Vector3(-0.6,0,-2.2),Vector3(-2.2,0,0.6),Vector3(0.4,0,3.4)])
	var client_defs:=[["miras",4],["asel",2],["erlan",1]]
	for i in 3:
		var node:=make_npc(client_defs[i][0],client_defs[i][1],Vector3(0,.02,5.4),PI)
		node.name="Client_%d"%i
		node.visible=false
		node.collision_layer=0
		clients.append({"node":node,"state":"away","target":Vector3.ZERO,"timer":0.0,"chair":-1,"seat":Vector3.ZERO})
		# Opening scene: one client waiting, one already being cut.
		if i==0:
			node.visible=true;node.collision_layer=1
			node.position=Vector3(3.3,.02,-0.4)
			clients[i].state="waiting";clients[i].timer=6.0
		elif i==1:
			node.visible=true;node.collision_layer=1
			node.position=chairs[0].pos+Vector3(0,-.36,0)
			node.rotation.y=PI/2
			clients[i].state="cutting";clients[i].chair=0
			chairs[0].occupied=true;chairs[0].client=1
	_register_talkable()
	talkable_actors.append({"actor":cashier,"id":"cashier_4"})
	# Opening scene: client 1 is mid-cut in chair 0, client 0 waits.
	stylist_state=2;cut_time=12.0;stylist_client=1
	_scissors_on()
	interior_environment=Environment.new()
	interior_environment.background_mode=Environment.BG_COLOR
	interior_environment.background_color=Color("262e31")
	interior_environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	interior_environment.ambient_light_color=Color("fff0d4")
	interior_environment.ambient_light_energy=.65
	interior_environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	preload("res://static_batch.gd").build(self,props)
	visible=false

func _register_talkable() -> void:
	stylist.set_meta("npc_id","salon_stylist")
	attendant.set_meta("npc_id","salon_attendant")
	for i in clients.size():clients[i].node.set_meta("npc_id","salon_client_%d"%i)

func update_cashier(camera:Camera3D,delta:float,active:bool) -> void:
	if not is_instance_valid(cashier):return
	if not active:
		cashier.animation.active=false
		stylist.animation.active=false
		attendant.animation.active=false
		for c in clients:c.node.animation.active=false
		return
	cashier.update_detail(camera,delta)
	cashier.play_motion("idle")
	_sim(camera,delta)

func _sim(camera:Camera3D,dt:float) -> void:
	var all:Array=[stylist,attendant,cashier]
	for c in clients:all.append(c.node)
	for n in all:
		if n.visible:n.update_detail(camera,dt)
	# --- stylist: pick up a seated client, cut, return to the counter ------
	if stylist_state==0:
		var seated_index:=-1
		for i in clients.size():
			if clients[i].state=="sitting":seated_index=i;break
		if seated_index>=0:
			stylist_client=seated_index
			stylist_target=chairs[clients[seated_index].chair].pos+Vector3(.95,0,.3)
			stylist_state=1
		else:
			_move_towards(stylist,Vector3(-2.55,0,-1.6),1.1,dt)
	elif stylist_state==1:
		# The chosen client may have left while we were walking: re-target.
		var still_there:bool=stylist_client>=0 and clients[stylist_client].state=="sitting"
		if not still_there:
			stylist_client=-1
			for i in clients.size():
				if clients[i].state=="sitting":stylist_client=i;break
			if stylist_client>=0:
				stylist_target=chairs[clients[stylist_client].chair].pos+Vector3(.95,0,.3)
			else:stylist_state=0
		elif _move_towards(stylist,stylist_target,1.4,dt):
			stylist_state=2;cut_time=rng.randf_range(10.0,16.0)
			clients[stylist_client].state="cutting"
			_scissors_on()
	elif stylist_state==2:
		cut_time-=dt
		# Live cutting: bob toward the client's head, snip, drop hair.
		if stylist_client<0 or clients[stylist_client].state!="cutting":
			stylist_state=1;_scissors_off()
		else:
			var head:Vector3=clients[stylist_client].node.position+Vector3(0,1.6,0)
			var hand:Vector3=head+Vector3(.38,0,.06)
			var bob:float=sin(Time.get_ticks_msec()/1000.0*6.2)*.045
			stylist.position.y=.02+bob
			stylist.rotation.y=lerp_angle(stylist.rotation.y,1.1,10.0*dt)
			scissors.position=hand+Vector3(0,bob*.6,.05)
			scissors.rotation.z=sin(Time.get_ticks_msec()/1000.0*7.5)*.4
			snip_clock-=dt
			if snip_clock<=0:
				snip_clock=.55
				_spawn_clips(head)
			if cut_time<=0:
				var done:Dictionary=clients[stylist_client]
				var ch:Dictionary=chairs[done.chair]
				_scissors_off();stylist_state=1
				done.state="leaving";done.timer=0
				done.target=Vector3(1.3,0,5.0)
				ch.occupied=false;ch.client=-1
				done.chair=-1
	# --- clients -------------------------------------------------------------
	for i in clients.size():
		var c:Dictionary=clients[i]
		var node:CharacterBody3D=c.node
		match c.state:
			"away":pass
			"entering":
				if _move_towards(node,c.target,1.15,dt):
					c.state="waiting";c.timer=rng.randf_range(4.0,9.0)
				node.play_motion("walk")
			"waiting":
				node.play_motion("idle")
				c.timer-=dt
				var free_chair:=_free_chair()
				if free_chair>=0 and stylist_state!=2 and stylist_state!=1:
					var ch:Dictionary=chairs[free_chair]
					c.chair=free_chair;ch.occupied=true;ch.client=i
					c.state="to_chair";c.target=ch.pos
					node.play_motion("walk")
				elif c.timer<-12.0:
					c.state="leaving";c.target=Vector3(1.3,0,5.0)
					node.play_motion("walk")
				else:
					# Glance between the door and the chairs while waiting.
					var look:Vector3=Vector3(0,0,5.4) if int(c.timer/4.0)%2==0 else Vector3(-3.4,0,-3.2)
					node.rotation.y=lerp_angle(node.rotation.y,atan2(-(look-node.position).x,-(look-node.position).z),2.5*dt)
			"to_chair":
				if _move_towards(node,c.target,1.15,dt):
					c.state="sitting"
					node.position.y=-.36
					node.rotation.y=PI/2
					node.play_motion("idle")
				else:node.play_motion("walk")
			"sitting","cutting":
				node.play_motion("idle")
				node.position.y=-.36+sin(Time.get_ticks_msec()/1000.0*2.0)*.006
			"leaving":
				if _move_towards(node,c.target,1.15,dt):
					node.visible=false;node.collision_layer=0
					c.state="away";c.chair=-1
				else:node.play_motion("walk")
	# --- a new client sometimes walks in -------------------------------------
	next_arrival-=dt
	if next_arrival<=0:
		next_arrival=rng.randf_range(3.5,8.0)
		var busy:=0
		for c in clients:
			if c.state!="away":busy+=1
		if busy==0:next_arrival=minf(next_arrival,.5)
		if busy<3:
			var idx:=0
			for i in clients.size():
				if clients[i].state=="away":idx=i;break
			var node:CharacterBody3D=clients[idx].node
			node.visible=true;node.collision_layer=1
			node.position=Vector3(0,.02,5.4);node.rotation.y=PI
			clients[idx].state="entering";clients[idx].target=Vector3(3.3,0,-0.4)
	# --- attendant keeps the floor tidy ---------------------------------------
	if attendant_wait>0:
		attendant_wait-=dt
		attendant.play_motion("idle")
	else:
		if _move_towards(attendant,attendant_route[attendant_index],1.05,dt):
			attendant_index=(attendant_index+1)%attendant_route.size()
			attendant_wait=rng.randf_range(1.2,2.6)
		else:attendant.play_motion("walk")
	# --- falling hair clippings ------------------------------------------------
	for part in clip_parts.duplicate():
		part.life-=dt
		part.vel.y-=2.5*dt
		part.node.position+=part.vel*dt
		if part.life<=0 or part.node.position.y<.02:
			part.node.queue_free();clip_parts.erase(part)

func _free_chair() -> int:
	for i in chairs.size():
		if not chairs[i].occupied:return i
	return -1

func _scissors_on() -> void:
	scissors_on=true;scissors.visible=true;snip_clock=.3

func _scissors_off() -> void:
	scissors_on=false;scissors.visible=false
	for c in clients:
		if c.state=="cutting":c.state="sitting"
	stylist.position.y=.02

func _spawn_clips(head:Vector3) -> void:
	for i in 3:
		var q:=MeshInstance3D.new()
		var box:=BoxMesh.new();box.size=Vector3(.045,.008,.06);q.mesh=box
		var mat:=StandardMaterial3D.new();mat.albedo_color=Color("3a2a1e")
		q.material_override=mat
		q.position=head+Vector3(rng.randf_range(-.22,.22),rng.randf_range(-.05,.18),rng.randf_range(-.22,.22))
		q.rotation=Vector3(rng.randf()*3.14,rng.randf()*3.14,0)
		add_child(q)
		clip_parts.append({"node":q,"vel":Vector3(rng.randf_range(-.25,.25),-rng.randf_range(.4,.9),rng.randf_range(-.25,.25)),"life":1.0})

