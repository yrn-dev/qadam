extends Node3D
# Buildings and vehicles are extracted from POLYGON Mini in this project.
# Traffic uses authored Kenney signal models (CC0).
# Baiterek, cartoon citizens and Shop Cartoon are borrowed from astana3d.
const Layout=preload("res://district_layout.gd")
const KIT := "res://assets/nazerke_kit/"
var assets := {}
var static_visuals:Array[MeshInstance3D]=[]
var surface_materials:Dictionary={}
var buildings: Array[Node3D] = []
var vehicles: Array[Dictionary] = []
var walkers: Array[Dictionary] = []
var player: Node3D
var landmark: Node3D
var time := 0.0
var traffic:Node
var population:Node
var footprints:Array[AABB]=[]
var paused:=false
var shops:Array[Node3D]=[]
var shop_approaches:Array[Vector3]=[]
var parked_vehicles:Array[Node3D]=[]

func asset(id:String, at:Vector3, scale_by:float=1, angle:float=0, solid:bool=false) -> Node3D:
	if not assets.has(id): assets[id]=load(KIT+id+".glb")
	var n:Node3D=assets[id].instantiate()
	n.name=id
	n.set_meta("source_model","polygon_mini_free.glb / "+id)
	add_child(n)
	n.position=at
	n.scale=Vector3.ONE*scale_by
	n.rotation.y=angle
	if id=="blue_car":
		for child in n.get_children():
			if child is Node3D:child.rotation.y+=.68658856+PI
	if id not in ["blue_car","bus"]:
		for mesh in n.find_children("*","MeshInstance3D",true,false):static_visuals.append(mesh)
	if solid:
		for m in n.find_children("*","MeshInstance3D",true,false): m.create_trimesh_collision()
	return n

func collision(at:Vector3,size:Vector3,label:String="Solid",layer:int=1) -> StaticBody3D:
	var body:=StaticBody3D.new()
	body.name=label
	body.position=at
	body.collision_layer=layer
	var cs:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=size
	cs.shape=shape
	body.add_child(cs)
	add_child(body)
	return body

func surface(at:Vector3,size:Vector2,color:String="") -> Node3D:
	var n:=asset("road_tile",at)
	n.scale=Vector3(size.x/4.327,1,size.y/5.373)
	if color!="":
		if not surface_materials.has(color):
			var shared:=StandardMaterial3D.new();shared.albedo_color=Color(color);shared.roughness=1
			surface_materials[color]=shared
		var material:StandardMaterial3D=surface_materials[color]
		for m in n.find_children("*","MeshInstance3D",true,false):m.material_override=material
	return n

func building(id:String,x:float,z:float,angle:float=0,scale_by:float=1) -> void:
	var n:=asset(id,Vector3(x,.03,z),scale_by,angle,true)
	buildings.append(n)
	var box:=AABB()
	var first:=true
	for mesh in n.find_children("*","MeshInstance3D",true,false):
		var b:AABB=(global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb()
		box=b if first else box.merge(b)
		first=false
	footprints.append(box)

func cartoon_shop(title:String,at:Vector3,angle:float) -> void:
	var root:=Node3D.new();root.name="Shop_"+title;add_child(root)
	root.position=at;root.rotation.y=angle
	root.set_meta("shop_title",title)
	root.set_meta("source_model","astana3d / Shop Cartoon by Saar Designer")
	var mesh:=MeshInstance3D.new();mesh.mesh=preload("res://assets/shops/shop.res");root.add_child(mesh)
	mesh.create_trimesh_collision();static_visuals.append(mesh)
	buildings.append(root);shops.append(root)
	footprints.append((global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb())
	# Original frontage faces +X; leave a clear public approach outside the model.
	shop_approaches.append(to_local(root.to_global(Vector3(4.1,0,0))))
	var label:=Label3D.new();label.text=title;label.font_size=64;label.pixel_size=.009
	label.modulate=Color("fff1ce");label.outline_size=4;label.outline_modulate=Color("263d43")
	label.position=Vector3(1.95,2.8,0);label.rotation.y=PI/2;root.add_child(label)

func _gable_mesh(depth:float,base_y:float,apex_y:float,length:float) -> Mesh:
	# Ridge along local Z (parallel to the street); the pediment triangles
	# face the building ends (+/-Z) and the slopes overhang front and back.
	var mesh:=ArrayMesh.new()
	var d2:=depth*0.5;var l2:=length*0.5
	var pos:=PackedVector3Array([
		Vector3(-d2,base_y,-l2),Vector3(d2,base_y,-l2),Vector3(0,apex_y,-l2),
		Vector3(-d2,base_y,l2),Vector3(d2,base_y,l2),Vector3(0,apex_y,l2)])
	var idx:=PackedInt32Array([0,2,1,3,4,5,1,4,5,1,5,2,0,3,5,0,5,2])
	var nrm:=PackedVector3Array();var uv:=PackedVector2Array()
	for i in 6:nrm.append(Vector3.ZERO);uv.append(Vector2.ZERO)
	var arr:Array=[]
	for i in Mesh.ARRAY_MAX:arr.append(null)
	arr[0]=pos;arr[1]=nrm;arr[4]=uv;arr[12]=idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arr)
	return mesh

func _facade_box(root:Node3D,label:String,p:Vector3,s:Vector3,col:Color) -> MeshInstance3D:
	var m:=MeshInstance3D.new();m.name=label
	var b:=BoxMesh.new();b.size=s;m.mesh=b
	var mat:=StandardMaterial3D.new();mat.albedo_color=col;mat.roughness=.9
	m.material_override=mat;root.add_child(m);m.position=p
	static_visuals.append(m)
	return m

func salon_facade(title:String,at:Vector3,angle:float) -> void:
	# Faithful low-poly build of the "Ana Beauty Salon" reference: pink gabled
	# house, white sign board, striped awning, window with a flower box and a
	# pink door with a yellow knob. Front faces local +X like every other shop.
	var root:=Node3D.new();root.name="Shop_"+title;add_child(root)
	root.position=at;root.rotation.y=angle
	root.set_meta("shop_title",title)
	root.set_meta("source_model","procedural facade (ref: Ana Beauty Salon by endomirebus, sketchfab.com, CC-BY)")
	buildings.append(root);shops.append(root)
	shop_approaches.append(to_local(root.to_global(Vector3(4.1,0,0))))
	var pink:=Color("f2a7c3");var white:=Color("faf6f0")
	var roofc:=Color("cf6b9e");var fascia:=Color("f9cfe2")
	_facade_box(root,"SalonBase",Vector3(0,.25,0),Vector3(5.3,.5,7.2),Color("d98bb0"))
	_facade_box(root,"SalonBody",Vector3(0,1.85,0),Vector3(5.2,3.0,7.0),pink)
	for sx in [-1,1]:
		for sz in [-1,1]:_facade_box(root,"SalonTrim",Vector3(sx*2.55,1.85,sz*3.45),Vector3(.22,3.2,.22),Color("ece7e2"))
	# Gabled roof like the reference: ridge runs along the street (local Z),
	# pink slopes overhang the front and back walls, pediments sit on the ends.
	var gable:=MeshInstance3D.new();gable.name="SalonGable"
	gable.mesh=_gable_mesh(5.9,3.3,4.5,7.5)
	var gmat:=StandardMaterial3D.new();gmat.albedo_color=roofc;gmat.roughness=.95
	gmat.cull_mode=BaseMaterial3D.CULL_DISABLED
	gable.material_override=gmat;root.add_child(gable);static_visuals.append(gable)
	_facade_box(root,"EaveFasciaF",Vector3(2.95,3.22,0),Vector3(.18,.18,7.6),fascia)
	_facade_box(root,"EaveFasciaB",Vector3(-2.95,3.22,0),Vector3(.18,.18,7.6),fascia)
	for ez in [-3.76,3.76]:
		for sgn in [-1,1]:
			var edge:=MeshInstance3D.new()
			var eb:=BoxMesh.new();eb.size=Vector3(3.3,.14,.14);edge.mesh=eb
			var em:=StandardMaterial3D.new();em.albedo_color=fascia;em.roughness=.9
			edge.material_override=em;root.add_child(edge)
			edge.position=Vector3(sgn*1.475,3.9,ez)
			edge.rotation.z=atan2(1.2,-sgn*2.95)
			static_visuals.append(edge)
	# Shop name in white, like the reference lettering.
	var sign:=Label3D.new();sign.text="Ana";sign.font_size=64;sign.pixel_size=.011
	sign.modulate=Color("ffffff");sign.outline_size=5;sign.outline_modulate=Color("b05583")
	sign.position=Vector3(2.72,3.02,0);sign.rotation.y=PI/2;root.add_child(sign)
	var sign2:=Label3D.new();sign2.text="Beauty Salon";sign2.font_size=26;sign2.pixel_size=.0085
	sign2.modulate=Color("ffffff");sign2.outline_size=3;sign2.outline_modulate=Color("b05583")
	sign2.position=Vector3(2.7,2.72,0);sign2.rotation.y=PI/2;root.add_child(sign2)
	# Window on the street-left side (local -Z) with a daisy flower box.
	_facade_box(root,"WindowGlass",Vector3(2.6,1.5,-1.45),Vector3(.06,1.4,2.6),Color("9fb8cc"))
	_facade_box(root,"WindowFrameL",Vector3(2.62,1.5,-2.83),Vector3(.12,1.62,.16),white)
	_facade_box(root,"WindowFrameR",Vector3(2.62,1.5,-0.07),Vector3(.12,1.62,.16),white)
	_facade_box(root,"WindowFrameT",Vector3(2.62,2.33,-1.45),Vector3(.12,.16,2.92),white)
	_facade_box(root,"WindowFrameB",Vector3(2.62,.67,-1.45),Vector3(.12,.16,2.92),white)
	_facade_box(root,"FlowerPlanter",Vector3(2.72,.78,-1.45),Vector3(.3,.24,2.9),Color("58b368"))
	for i in 4:
		var petal:=MeshInstance3D.new()
		var pm:=SphereMesh.new();pm.radius=.16;pm.height=.32;pm.radial_segments=8;pm.rings=6;petal.mesh=pm
		var pmat:=StandardMaterial3D.new();pmat.albedo_color=Color("ffffff");pmat.roughness=.8
		petal.material_override=pmat;root.add_child(petal)
		petal.position=Vector3(2.84,1.02,-2.3+i*.6);petal.scale=Vector3(1,.95,1)
		static_visuals.append(petal)
		var core:=MeshInstance3D.new()
		var cm:=SphereMesh.new();cm.radius=.06;cm.height=.12;cm.radial_segments=7;cm.rings=5;core.mesh=cm
		var cmat:=StandardMaterial3D.new();cmat.albedo_color=Color("f4c542");cmat.roughness=.8
		core.material_override=cmat;root.add_child(core);core.position=Vector3(2.9,1.02,-2.3+i*.6)
		static_visuals.append(core)
	# Striped awning over the window.
	var awning:=Node3D.new();awning.name="Awning";awning.position=Vector3(2.8,2.3, -1.45);awning.rotation.z=-.25;root.add_child(awning)
	for i in 6:
		var stripe:=MeshInstance3D.new()
		var b:=BoxMesh.new();b.size=Vector3(1.1,.06,.46);stripe.mesh=b
		var mat:=StandardMaterial3D.new();mat.albedo_color=white if i%2==0 else pink;mat.roughness=.95
		stripe.material_override=mat;awning.add_child(stripe);stripe.position=Vector3(0,0,-1.15+i*.46)
		static_visuals.append(stripe)
	# Pink door with a glass pane, yellow knob and a white step on the right.
	_facade_box(root,"SalonDoor",Vector3(2.6,1.15,0.9),Vector3(.08,2.3,1.0),Color("e58fb4"))
	_facade_box(root,"DoorGlass",Vector3(2.66,1.85,0.9),Vector3(.05,.9,.7),Color("9fb8cc"))
	_facade_box(root,"DoorFrameL",Vector3(2.62,1.15,0.32),Vector3(.12,2.5,.12),white)
	_facade_box(root,"DoorFrameR",Vector3(2.62,1.15,1.48),Vector3(.12,2.5,.12),white)
	_facade_box(root,"DoorFrameT",Vector3(2.62,2.42,0.9),Vector3(.12,.14,1.3),white)
	_facade_box(root,"DoorStep",Vector3(2.72,.06,0.9),Vector3(.6,.12,1.35),white)
	var knob:=MeshInstance3D.new()
	var ks:=SphereMesh.new();ks.radius=.055;ks.height=.11;knob.mesh=ks
	var kmat:=StandardMaterial3D.new();kmat.albedo_color=Color("f4c542")
	knob.material_override=kmat;root.add_child(knob);knob.position=Vector3(2.7,1.05,0.52)
	static_visuals.append(knob)
	# Symmetric extents, so the axis-aligned body matches the rotated facade (PI).
	collision(Vector3(at.x,1.7,at.z),Vector3(5.3,3.4,7.2),"SalonBody")
	footprints.append(AABB(Vector3(at.x-2.65,at.y,at.z-3.6),Vector3(5.3,3.4,7.2)))

func road(a:Vector3,b:Vector3,width:float=8) -> void:
	var length:=a.distance_to(b)
	var count:=ceili(length/8)
	for i in count:
		var p:=a.lerp(b,(float(i)+.5)/count)
		p.y=.021
		var n:=surface(p,Vector2(width,length/count+.015))
		n.rotation.y=0 if absf(a.x-b.x)<.1 else PI/2

func _ready() -> void:
	scale=Vector3.ONE*Layout.ENVIRONMENT_SCALE
	# The same original paving mesh spans the horizon: no exposed edge or void.
	surface(Vector3(0,-.012,-22),Vector2(1600,1600),"596461")
	surface(Vector3(0,0,0),Vector2(130,170),"8a8c82")
	collision(Vector3(0,-.5,0),Vector3(180,1,220),"ContinuousGround")
	for x in [-27.0,27.0]:road(Vector3(x,0,-Layout.ROAD_END),Vector3(x,0,Layout.ROAD_END),7.4)
	for z in [-Layout.ROAD_END,0.0,Layout.ROAD_END]:road(Vector3(-30.7,0,z),Vector3(30.7,0,z),7.4)
	for x in [-27.0,27.0]:
		for z in [-Layout.ROAD_END,0.0,Layout.ROAD_END]:surface(Vector3(x,.026,z),Vector2(7.4,7.4),"343d44")
	# Narrow inner courtyards; their passages are connected to the sidewalks.
	for x in [-11.7,11.7]:
		for z in [-24.0,24.0]:surface(Vector3(x,.008,z),Vector2(19.5,33),"718269")
	building("townhouse",-11.7,-30,0,.94)
	building("solar_house",11.7,-30,PI,1.02)
	building("apartment",-11.7,30,PI,.96)
	building("shops",11.7,30,0,1.13)
	building("shops",-11.7,-12,0,1.10)
	building("townhouse",11.7,-12,PI,.94)
	building("solar_house",-11.7,13,0,1.0)
	building("apartment",11.7,13,PI,.96)
	for site in Layout.SHOP_SITES:cartoon_shop(site[0],site[1],site[2])
	# Closely spaced frontages, with a second row closing the view between them.
	for side in [-1,1]:
		for i in 7:
			if side==-1 and i==3:continue # Central-west plot belongs to the cartoon shop.
			var id:String=["round_tower","apartment","shops","townhouse","apartment","shops","square_tower"][i]
			# Open a fitted northwest shop gap, then close the central frontage around DÜKEN.
			var frontage_z:float=[-58,-32,-13.5,0,15.5,36,54][i] if side==-1 else -54+i*18
			building(id,side*41.5,frontage_z,PI/2 if i in [1,2,3,4] else 0,1.0)
		for i in 15:
			building("square_tower",side*58,-84+i*12,0,1.25)
			buildings.back().scale.y*=.83+(i%4)*.12
		for i in 9:
			building("round_tower" if i%3==0 else "apartment",side*74,-84+i*21,PI/2,1.2)
	for z in [-68.0,68.0]:
		for i in 7:
			var x:float=-45+i*15
			building("shops" if i==3 else "apartment",x,z,PI if z>0 else 0,1.05)
		for i in 8:
			building("townhouse",-53+i*15,z+signf(z)*15,0,1.1)
	# A familiar silhouette above the northern rooftops, outside the playable district.
	landmark=load("res://assets/models/baiterek.glb").instantiate()
	landmark.name="Baiterek_Backdrop"
	add_child(landmark)
	var bounds:=AABB()
	var first:=true
	for m in landmark.find_children("*","MeshInstance3D",true,false):
		var box:AABB=(global_transform.affine_inverse()*m.global_transform)*m.get_aabb()
		bounds=box if first else bounds.merge(box)
		first=false
	var factor:=48.0/bounds.size.y
	landmark.scale=Vector3.ONE*factor
	landmark.position=Vector3(0,0,-98)-Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*factor
	landmark.set_meta("source_model","astana3d/assets/models/baiterek.glb")
	for z in [-Layout.HALF_DEPTH,Layout.HALF_DEPTH]:collision(Vector3(0,15,z),Vector3(112,30,1),"DistrictBoundary")
	for x in [-Layout.HALF_WIDTH,Layout.HALF_WIDTH]:collision(Vector3(x,15,0),Vector3(1,30,Layout.HALF_DEPTH*2),"DistrictBoundary")
	for x in [-4.0,4.0]:
		for z in [-40.0,-22.0,22.0,40.0]:asset("tree",Vector3(x,0,z),.8,float(z))
	for x in [-22.0,22.0,-32.5,32.5]:
		for z in [-47.0,-29.0,-14.0,14.0,29.0,47.0]:
			if x==32.5 and z==-29:continue # keep the ANA BEAUTY frontage clear
			var lamp_z:float=-50.5 if x==-32.5 and z==-47 else z
			asset("lamp",Vector3(x,0,lamp_z),1,PI if x<0 else 0,true)
			var light:=OmniLight3D.new()
			light.position=Vector3(x,4.0,lamp_z)
			light.light_color=Color("ffcc87")
			light.light_energy=.8
			light.omni_range=8
			add_child(light)
	for x in [-34.0,34.0]:
		for z in [-58.0,-33.0,33.0,58.0]:asset("small_tree",Vector3(x,0,z),1.1)
	# Markings are flat instances of the project's existing road surface.
	for x in [-27.0,27.0]:
		for z in [-8.0,8.0]:
			for stripe in 7:surface(Vector3(x-3+stripe,.035,z),Vector2(.5,2.0),"c9c6ad")
	for stripe in 7:surface(Vector3(0,.035,-3+stripe),Vector2(2,.5),"c9c6ad")
	# Real source cars in parking pockets; their fronts use the same corrected axis.
	park_car(Vector3(-21.8,.035,41.5),0)
	park_car(Vector3(21.8,.035,-41.5),PI)
	# Appended after existing buildings so saved residential IDs remain stable.
	cartoon_shop("",Vector3(-40,.035,28.35),PI/2)
	shops.back().set_meta("shop_title","Бос дүкен")
	# ANA BEAUTY salon: pink gabled house on the east frontage (see facade below).
	salon_facade("ANA BEAUTY",Vector3(35.9,.035,-29),PI)
	traffic=Node.new()
	traffic.set_script(preload("res://district_traffic.gd"))
	add_child(traffic)
	population=Node.new()
	population.set_script(preload("res://district_population.gd"))
	add_child(population)
	preload("res://static_batch.gd").build(self,static_visuals,28.0)
	print("DENSE_DISTRICT_READY | buildings=",buildings.size()," | authored Nazerke models | cartoon citizens")

func sample(points:Array[Vector3],distance:float) -> Dictionary:
	for i in points.size():
		var a:Vector3=points[i]
		var b:Vector3=points[(i+1)%points.size()]
		var length:=a.distance_to(b)
		if distance<=length:return {"at":a.lerp(b,distance/length),"dir":(b-a).normalized()}
		distance-=length
	return {"at":points[0],"dir":Vector3.FORWARD}

func _physics_process(delta:float) -> void:
	if paused:return
	time+=delta
	traffic.tick(delta)
	population.tick(delta)

func park_car(at:Vector3,angle:float) -> void:
	# Authored road mesh makes a marked pocket outside the moving lanes.
	surface(Vector3(at.x,.028,at.z),Vector2(2.3,5.2),"626b6b")
	for side in [-1,1]:
		surface(Vector3(at.x+side*1.1,.036,at.z),Vector2(.07,5.1),"c9c6ad")
		surface(Vector3(at.x,.036,at.z+side*2.55),Vector2(2.2,.07),"c9c6ad")
	var car:=asset("blue_car",at,1/Layout.ENVIRONMENT_SCALE,angle,true)
	car.name="ParkedCar_%d"%parked_vehicles.size()
	parked_vehicles.append(car)
	# Use transformed vertices: rotating a precomputed source AABB overestimates width.
	var bounds:=AABB();var first:=true
	for mesh in car.find_children("*","MeshInstance3D",true,false):
		var transform:Transform3D=global_transform.affine_inverse()*mesh.global_transform
		for surface_id in mesh.mesh.get_surface_count():
			for vertex in mesh.mesh.surface_get_arrays(surface_id)[Mesh.ARRAY_VERTEX]:
				var point:Vector3=transform*vertex
				if first:bounds=AABB(point,Vector3.ZERO);first=false
				else:bounds=bounds.expand(point)
	car.set_meta("local_bounds",bounds)
	footprints.append(bounds)
