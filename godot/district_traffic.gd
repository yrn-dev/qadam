extends Node
const Layout=preload("res://district_layout.gd")
# Shared intersections, queue following and physical stop lines on the real road network.
var town:Node3D
var vehicles:Array[Dictionary]=[]
var signals:Array[Dictionary]=[]
var pedestrian_signals:Array[Node3D]=[]
var turn_signal:Node3D
var clock:=0.0
var phase:=7
var phase_time:=0.0
var durations:=[18.0,3.0,2.0,10.0,3.0,2.0,10.0,2.0]
var gate_passages:=0
var exit_blocks:=0
var max_stop_time:=0.0
var phase_max_time:=0.0
var routes:Dictionary={}
var stopped_events:=0
var max_queue:=0
var cycles:=0
var pedestrian_hold:=false
var ped_hold_time:=0.0
var minimum_gap:=1000.0

func _ready() -> void:
	town=get_parent()
	for lane in 2:
		var x:=28.8 if lane==0 else 25.2
		var z:=Layout.ROAD_END+1.8 if lane==0 else Layout.ROAD_END-1.8
		var points:Array[Vector3]=[Vector3(-x,0,-z+4),Vector3(-x,0,z-4),Vector3(-x+4,0,z),Vector3(x-4,0,z),Vector3(x,0,z-4),Vector3(x,0,-z+4),Vector3(x-4,0,-z),Vector3(-x+4,0,-z)]
		if lane==1:points.reverse()
		_add_route(points,10,lane)
	var cross:Array[Vector3]=[Vector3(-28.8,0,-Layout.ROAD_END+2.2),Vector3(-28.8,0,-3),Vector3(-24,0,1.8),Vector3(24,0,1.8),Vector3(28.8,0,-3),Vector3(28.8,0,-Layout.ROAD_END+2.2),Vector3(24.8,0,-Layout.ROAD_END-1.8),Vector3(-24.8,0,-Layout.ROAD_END-1.8)]
	_add_route(cross,6,2)
	_configure_gates()
	town.vehicles=vehicles
	for center in [-27.0,27.0]:
		for axis in 2:
			for sign_dir in [-1,1]:
				# At the right-hand curb, facing approaching traffic.
				var at:=Vector3(center-sign_dir*5,0,-sign_dir*11) if axis==0 else Vector3(center-sign_dir*11,0,sign_dir*5)
				var facing:=Vector3(0,0,-sign_dir) if axis==0 else Vector3(-sign_dir,0,0)
				var head:=Node3D.new();head.set_script(preload("res://solid_signal.gd"))
				head.name="TrafficSignal";town.add_child(head);head.position=at
				var has_turn:bool=axis==0 and center<0 and sign_dir==1
				head.configure(facing,Vector3(sign_dir,0,0) if axis==0 else Vector3.ZERO,has_turn)
				signals.append({"node":head,"axis":axis,"facing":facing})
				if axis==0:pedestrian_signals.append(head)
				if has_turn:turn_signal=head
	_update_signals()

func _add_route(points:Array[Vector3],count:int,route:int) -> void:
	var total:=0.0
	for i in points.size():total+=points[i].distance_to(points[(i+1)%points.size()])
	for i in count:
		var id:="bus" if i%6==0 else "blue_car"
		var s:float=fposmod((i+.32+route*.19)*total/count,total)
		var at:Dictionary=town.sample(points,s)
		# Move a new spawn forward until it clears cars from shared sections.
		for attempt in 100:
			var clear:bool=not (absf(at.at.z)<17 and absf(absf(at.at.x)-27)<10)
			for other in vehicles:
				if other.node.position.distance_to(at.at)<8:clear=false;break
			if clear:break
			s=fposmod(s+2.3,total);at=town.sample(points,s)
		# Cancel the district scale for the authored vehicle and its child collider.
		var n:Node3D=town.asset(id,at.at+Vector3(0,.035,0),1/Layout.ENVIRONMENT_SCALE)
		n.rotation.y=atan2(-at.dir.x,-at.dir.z)
		if id=="blue_car":
			var colors:=[Color("438b99"),Color("c78b67"),Color("91a68a"),Color("d5c295"),Color("8f91b6")]
			for mesh in n.find_children("*","MeshInstance3D",true,false):
				for surface in mesh.mesh.get_surface_count():
					var source:Material=mesh.get_active_material(surface)
					if source is StandardMaterial3D and source.albedo_texture:
						var material:=ShaderMaterial.new()
						material.shader=preload("res://car_paint.gdshader")
						material.set_shader_parameter("original_atlas",source.albedo_texture)
						material.set_shader_parameter("original_color",source.albedo_color)
						material.set_shader_parameter("paint",colors[(i+route)%colors.size()])
						mesh.set_surface_override_material(surface,material)
		var body:StaticBody3D=town.collision(Vector3.ZERO,Vector3(2.85 if id=="bus" else 2.05,1.8,5.2 if id=="bus" else 4.8),"TrafficCollider",4)
		town.remove_child(body);n.add_child(body);body.position=Vector3(0,1,0)
		vehicles.append({"node":n,"points":points,"s":s,"length":total,"speed":0.0,"cruise":5.0+(i%4)*.45,"travel":0.0,"half":(2.6 if id=="bus" else 2.4)/Layout.ENVIRONMENT_SCALE,"width":(1.455 if id=="bus" else 1.03)/Layout.ENVIRONMENT_SCALE,"route":route,"dir":at.dir,"stopped":false,"id":vehicles.size(),"active_gate":{},"wait_time":0.0,"stop_time":0.0,"max_stop":0.0,"passages":0})

func allows(axis:int) -> bool:
	return phase==0 if axis==0 else phase==3

func pedestrians_allowed() -> bool:
	return phase==6

func _update_signals() -> void:
	for head in signals:
		var state:=0
		if allows(head.axis):state=2
		elif (head.axis==0 and phase==1) or (head.axis==1 and phase==4):state=1
		head.node.set_main(state)
	for head in pedestrian_signals:head.set_pedestrian(pedestrians_allowed())
	if is_instance_valid(turn_signal):turn_signal.set_turn(allows(1))

func status() -> String:
	if phase==6:return "Жаяу жүргіншілер өтеді · көліктер күтеді"
	if phase in [0,1]:return "Даңғылда қозғалыс · жаяу жүргіншілер күтеді"
	if phase in [3,4]:return "Көлденең көшеде қозғалыс · жаяу жүргіншілер күтеді"
	return "Қиылыс босатылуда"

func _distance_on_route(points:Array[Vector3],point:Vector3) -> float:
	var best:=INF
	var result:=0.0
	var offset:=0.0
	for i in points.size():
		var a:Vector3=points[i]
		var d:Vector3=points[(i+1)%points.size()]-a
		var along:float=clampf((point-a).dot(d)/d.length_squared(),0,1)
		var error:float=(a+d*along).distance_squared_to(point)
		if error<best:best=error;result=offset+along*d.length()
		offset+=d.length()
	return result

func _configure_gates() -> void:
	var definitions:={
		0:[[0,Vector3(-28.8,0,-11),Vector3(-28.8,0,11),0,false],[1,Vector3(28.8,0,11),Vector3(28.8,0,-11),0,false]],
		1:[[0,Vector3(-25.2,0,11),Vector3(-25.2,0,-11),0,false],[1,Vector3(25.2,0,-11),Vector3(25.2,0,11),0,false]],
		2:[[0,Vector3(-28.8,0,-11),Vector3(-16,0,1.8),0,true],[1,Vector3(16,0,1.8),Vector3(28.8,0,-11),1,true]]}
	for route_id in 3:
		var points:Array[Vector3]=[]
		for car in vehicles:
			if car.route==route_id:points=car.points;break
		routes[route_id]=[]
		for d in definitions[route_id]:
			routes[route_id].append({"junction":d[0],"s":_distance_on_route(points,d[1]),"exit_s":_distance_on_route(points,d[2]),"axis":d[3],"turn":d[4]})

func _green_for(car:Dictionary,gate:Dictionary) -> bool:
	# A left turn shares the main green and yields to approaching oncoming cars.
	# The extra arrow provides a protected opportunity in the transverse phase.
	return allows(gate.axis) or (car.route==2 and gate.junction==0 and phase==3)

func _junction_clear(gate:Dictionary,car:Dictionary) -> bool:
	for other in vehicles:
		if other.id==car.id or other.active_gate.is_empty():continue
		var active:Dictionary=other.active_gate
		if active.junction!=gate.junction:continue
		if active.turn or gate.turn or active.axis!=gate.axis:return false
	return true

func _exit_free(car:Dictionary,gate:Dictionary) -> bool:
	var exit:Dictionary=town.sample(car.points,fposmod(gate.exit_s+car.half+1,car.length))
	for other in vehicles:
		if other.id==car.id:continue
		var diff:Vector3=other.node.position-exit.at
		if absf(diff.dot(exit.dir.cross(Vector3.UP)))<2.6 and absf(diff.dot(exit.dir))<car.half+other.half+1 and other.speed<1.5:
			return false
	return true

func _turn_priority(junction:int) -> bool:
	if junction!=0:return false
	for other in vehicles:
		if other.route==2 and other.wait_time>7 and other.node.position.z< -10 and other.node.position.z> -19 and other.node.position.x< -26:return true
	return false

func _can_enter(car:Dictionary,gate:Dictionary) -> bool:
	if not _green_for(car,gate):return false
	if not _junction_clear(gate,car):return false
	if not _exit_free(car,gate):exit_blocks+=1;return false
	if gate.junction==0 and car.route==2 and phase==0 and car.wait_time<=7:
		for other in vehicles:
			if other.route==1 and absf(other.node.position.x+25.2)<1 and other.node.position.z> -11 and other.node.position.z<26:
				return false
	elif gate.junction==0 and car.route==1 and _turn_priority(0):return false
	return true

func tick(delta:float) -> void:
	clock+=delta
	phase_time+=delta
	phase_max_time=maxf(phase_max_time,phase_time)
	pedestrian_hold=false
	var pedestrian_demand:=false
	for w in town.walkers:
		if w.get("crossing",false):pedestrian_hold=true
		if w.get("waiting_signal",false):pedestrian_demand=true
	var occupied:=false
	for car in vehicles:
		if not car.active_gate.is_empty():
			var progress:float=fposmod(car.s-car.active_gate.s,car.length)
			var needed:float=fposmod(car.active_gate.exit_s-car.active_gate.s,car.length)+car.half+1.0
			# Before the stop line, progress wraps around; retain the reservation.
			if progress>needed and progress<car.length*.5:
				car.active_gate={};car.passages+=1;gate_passages+=1
			else:occupied=true
	var in_clearance:bool=phase in [2,5,7]
	if in_clearance and pedestrian_hold:ped_hold_time+=delta
	elif not in_clearance:ped_hold_time=0.0
	# A stuck walker must not hold the intersection forever: after 4 s the
	# phase advances; approaching cars still yield to anyone on the road.
	var hold_clearance:bool=in_clearance and (occupied or (pedestrian_hold and ped_hold_time<4.0))
	if phase_time>=durations[phase] and not hold_clearance:
		phase_time=0
		phase=(phase+1)%durations.size()
		if phase==6 and not pedestrian_demand:phase=7
		if phase==0:cycles+=1
		_update_signals()
	var queue:=0
	for car in vehicles:
		var at:Dictionary=town.sample(car.points,car.s)
		car.dir=at.dir
	for car in vehicles:
		var at:Dictionary=town.sample(car.points,car.s)
		var direction:Vector3=at.dir
		var clearance:=1000.0
		for other in vehicles:
			if other.id==car.id:continue
			var diff:Vector3=other.node.position-at.at
			var ahead:float=diff.dot(direction)
			var lateral:float=absf(diff.dot(direction.cross(Vector3.UP)))
			if ahead>0 and lateral<2.65 and direction.dot(other.dir)>-.4:
				clearance=minf(clearance,ahead-car.half-other.half-1.1)
		var waiting_at_gate:=false
		if car.active_gate.is_empty():
			for gate in routes[car.route]:
				var distance:float=fposmod(gate.s-car.s,car.length)-car.half
				if distance>42 or distance< -.1:continue
				var allowed:bool=_can_enter(car,gate)
				if not allowed:
					clearance=minf(clearance,maxf(0,distance))
					if distance<2:waiting_at_gate=true
				elif distance<maxf(2,car.speed*car.speed/7.0+1):
					car.active_gate=gate.duplicate()
					car.wait_time=0
		# A red pedestrian signal prevents fresh arrivals from holding the crossing forever.
		if phase in [5,6,7] and absf(direction.x)>.8:
			var ahead:float=(Vector3(0,0,0)-at.at).dot(direction)
			if absf(at.at.z)<4 and ahead>2.5+car.half-.05:clearance=minf(clearance,ahead-2.5-car.half)
		if is_instance_valid(town.player):clearance=_person_gap(at.at,direction,town.to_local(town.player.global_position),car.half,clearance)
		for w in town.walkers:clearance=_person_gap(at.at,direction,w.node.position,car.half,clearance)
		var target:float=minf(car.cruise,sqrt(maxf(0,2*2.5*clearance)))
		car.speed=move_toward(car.speed,target,(1.65 if target>car.speed else 4.5)*delta)
		car.step=minf(car.speed*delta,maxf(clearance,0))
		car.wait_time=car.wait_time+delta if waiting_at_gate else 0.0
		# Distance per frame is not a stopped-speed threshold. At 60 Hz the
		# first acceleration step is <3 mm: resetting speed there locked every
		# vehicle at rest forever, while the old 20 Hz test happened to pass.
		car.speed=minf(car.speed,car.step/maxf(delta,.000001))
		if car.speed<.05:
			queue+=1;car.stop_time+=delta
			car.max_stop=maxf(car.max_stop,car.stop_time)
			max_stop_time=maxf(max_stop_time,car.stop_time)
			if not car.stopped:stopped_events+=1
			car.stopped=true
		else:car.stopped=false;car.stop_time=0
	max_queue=maxi(queue,max_queue)
	for car in vehicles:
		car.s=fposmod(car.s+car.step,car.length)
		car.travel+=car.step
		var at:Dictionary=town.sample(car.points,car.s)
		car.node.position=at.at+Vector3(0,.035,0)
		# Align the long chassis to the road beneath its front and rear axles.
		# Delayed yaw at a corner swept the nose into the oncoming lane.
		var front:Dictionary=town.sample(car.points,fposmod(car.s+car.half,car.length))
		var rear:Dictionary=town.sample(car.points,fposmod(car.s-car.half,car.length))
		var heading:Vector3=(front.at-rear.at).normalized()
		car.node.rotation.y=atan2(-heading.x,-heading.z)

func _person_gap(at:Vector3,direction:Vector3,person:Vector3,half:float,current:float) -> float:
	var diff:=person-at
	var ahead:=diff.dot(direction)
	if ahead>0 and absf(diff.dot(direction.cross(Vector3.UP)))<1.9:
		return minf(current,ahead-half-.75)
	return current
