extends Node
## Recorded CC0 ambience and spatial vehicle audio. No change to traffic simulation.
const PREFIX := "Nazerke "
const MAX_ENGINES := 8
const SETTINGS := "user://audio.cfg"
var game:Node3D
var streams:Dictionary={}
var engines:Array[Dictionary]=[]
var selected:Array[int]=[]
var street:AudioStreamPlayer
var music:AudioStreamPlayer
var room_tone:AudioStreamPlayer
var steps:AudioStreamPlayer
var door:AudioStreamPlayer
var bell:AudioStreamPlayer
var panel:PanelContainer
var mute_button:CheckButton
var volumes:Dictionary={"Master":.8,"Music":.65,"Street":.8,"Foley":.8}
var muted:=false
var pause_gain:=0.0
var voice_duck:=1.0
var voice_held:=0.0
var street_gain:=0.0
var music_gain:=0.0
var room_gain:=0.0
var context:="street"
var shop_id:=-1
var music_positions:=[0.0,20.0,40.0,0.0,25.0]
var selection_clock:=0.0
var last_position:=Vector3.ZERO
var step_distance:=0.0
var last_step:=-1
var next_foot:=0
var foot_variants:=[-1,-1]
var step_moving:=false
var air_time:=0.0
var fall_speed:=0.0
var step_guard:=.25
var grounded:=false
var step_count:=0
var door_count:=0
var rng:=RandomNumberGenerator.new()

func _ready() -> void:
	game=get_parent();name="DistrictAudio";rng.seed=90317
	var config:=ConfigFile.new()
	if config.load(SETTINGS)==OK:
		for key in volumes:volumes[key]=clampf(float(config.get_value("volume",key,volumes[key])),0,1)
		muted=bool(config.get_value("volume","muted",false))
	for key in ["Master","Music","Street","Foley","Room"]:
		AudioServer.add_bus();var index:=AudioServer.bus_count-1
		AudioServer.set_bus_name(index,PREFIX+key)
		AudioServer.set_bus_send(index,"Master" if key=="Master" else PREFIX+"Master")
	var limiter:=AudioEffectLimiter.new();limiter.ceiling_db=-2.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(PREFIX+"Master"),limiter)
	# Dedicated voice bus: gentle low-cut + presence shelf, so dialogue stays
	# clean and clear above the neighbourhood.
	AudioServer.add_bus();var voice_index:=AudioServer.bus_count-1
	AudioServer.set_bus_name(voice_index,PREFIX+"Voice")
	AudioServer.set_bus_send(voice_index,PREFIX+"Master")
	var high_pass:=AudioEffectHighPassFilter.new();high_pass.cutoff_hz=110.0
	AudioServer.add_bus_effect(voice_index,high_pass)
	var filter:=AudioEffectLowPassFilter.new();filter.cutoff_hz=650
	AudioServer.add_bus_effect(AudioServer.get_bus_index(PREFIX+"Room"),filter)
	for file in ["street","engine","shop_music","shop_bell","door_open","door_close"]:
		_load_stream(file,file in ["street","engine","shop_music"])
	for surface in ["concrete","wood"]:
		for i in 6:_load_stream("step_%s_%d"%[surface,i],false)
	street=_player("StreetAmbience","street","Street");street.play()
	music=_player("ShopMusic","shop_music","Music")
	room_tone=_player("MuffledOutside","street","Room");room_tone.play(17)
	steps=_player("Footsteps","step_concrete_0","Foley");steps.max_polyphony=2
	door=_player("Door","door_open","Foley")
	bell=_player("ShopBell","shop_bell","Foley")
	for car in game.town.vehicles:
		var engine:=AudioStreamPlayer3D.new();engine.name="Engine_%d"%car.id
		engine.stream=streams.engine;engine.bus=PREFIX+"Street"
		engine.unit_size=3.0;engine.max_distance=48.0;engine.max_db=-6
		engine.attenuation_filter_cutoff_hz=5000;engine.attenuation_filter_db=-14
		engine.volume_db=-80;add_child(engine)
		engines.append({"player":engine,"car":car,"gain":0.0,"blocked":false,
			"pitch":.78 if car.half>1.9 else rng.randf_range(.92,1.04)})
	last_position=game.player.global_position
	_settings_panel();_apply_volumes()
	print("DISTRICT_AUDIO_READY | recorded ambience | spatial engines max=8 | shop music | footsteps | doors")

func _load_stream(file:String,loop:bool) -> void:
	var sample:AudioStreamOggVorbis=load("res://audio/"+file+".ogg")
	assert(sample!=null,"Missing audio: "+file)
	sample.loop=loop;streams[file]=sample

func _player(label:String,sample:String,bus:String) -> AudioStreamPlayer:
	var node:=AudioStreamPlayer.new();node.name=label;node.stream=streams[sample]
	node.bus=PREFIX+bus;node.volume_db=-80;add_child(node);return node

func _gain(node:Node,value:float) -> void:
	node.volume_db=linear_to_db(maxf(value,.0001))

func _apply_volumes() -> void:
	for key in ["Music","Street","Foley"]:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(PREFIX+key),linear_to_db(maxf(volumes[key],.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(PREFIX+"Room"),linear_to_db(maxf(volumes.Street,.0001)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index(PREFIX+"Master"),muted or volumes.Master<=0)

func _save() -> void:
	var config:=ConfigFile.new()
	for key in volumes:config.set_value("volume",key,volumes[key])
	config.set_value("volume","muted",muted);config.save(SETTINGS)

func toggle_mute() -> void:
	muted=not muted;mute_button.set_pressed_no_signal(muted);_apply_volumes();_save()

func _settings_panel() -> void:
	var layer:=CanvasLayer.new();layer.layer=20;add_child(layer)
	panel=PanelContainer.new();panel.position=Vector2(20,282);panel.custom_minimum_size.x=350
	var style:=StyleBoxFlat.new();style.bg_color=Color(.04,.075,.09,.96);style.set_corner_radius_all(8)
	style.content_margin_left=18;style.content_margin_right=18;style.content_margin_top=16;style.content_margin_bottom=16
	panel.add_theme_stylebox_override("panel",style);layer.add_child(panel)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",10);panel.add_child(box)
	var title:=Label.new();title.text="ДЫБЫС · КЕШКІ АУДАН";box.add_child(title)
	var labels:={"Master":"Жалпы дыбыс","Music":"Дүкендегі әуен","Street":"Көше және көліктер","Foley":"Қадамдар мен есіктер"}
	for key in labels:
		var row:=HBoxContainer.new();box.add_child(row)
		var label:=Label.new();label.text=labels[key];label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(label)
		var percent:=Label.new();percent.text="%d%%"%roundi(volumes[key]*100);row.add_child(percent)
		var slider:=HSlider.new();slider.min_value=0;slider.max_value=100;slider.step=1;slider.value=volumes[key]*100;box.add_child(slider)
		slider.value_changed.connect(func(value:float):
			volumes[key]=value/100.0;percent.text="%d%%"%int(value);_apply_volumes();_save())
	mute_button=CheckButton.new();mute_button.text="Дыбыссыз · M";mute_button.button_pressed=muted;box.add_child(mute_button)
	mute_button.toggled.connect(func(value:bool):muted=value;_apply_volumes();_save())
	var hint:=Label.new();hint.text="Esc — ойынды жалғастыру";box.add_child(hint)
	panel.visible=false

func _change_context(next:String,next_shop:int) -> void:
	if shop_id>=0:music_positions[shop_id]=music.get_playback_position()
	var was_shop:=context=="shop"
	context=next;shop_id=next_shop
	if context=="shop":
		music.stream_paused=false;music.play(music_positions[shop_id])
		if game.captured:_gain(bell,.16);bell.play()
	elif was_shop:music.stream_paused=false # Finish the fade before suspending playback.
	if game.captured:
		door.stream=streams.door_close if context=="street" else streams.door_open
		_gain(door,.38);door.play();door_count+=1
	step_distance=0;last_position=game.player.global_position;grounded=false
	step_moving=false;air_time=0;fall_speed=0;step_guard=.25

func _process(delta:float) -> void:
	var next_shop:int=game.shop_visits.current_shop
	var next:="shop" if next_shop>=0 else ("home" if game.home_visits.inside() else "street")
	if next!=context or next_shop!=shop_id:_change_context(next,next_shop)
	panel.visible=not game.captured and not game.automated and not game.menu_active() and not (is_instance_valid(game.story_ui) and game.story_ui.is_modal())
	pause_gain=move_toward(pause_gain,1.0 if game.captured else 0.0,delta*4)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(PREFIX+"Master"),linear_to_db(maxf(volumes.Master*pause_gain,.0001)))
	street_gain=move_toward(street_gain,1.0 if context=="street" else 0.0,delta*1.7)
	music_gain=move_toward(music_gain,1.0 if context=="shop" else 0.0,delta*1.25)
	room_gain=move_toward(room_gain,0.0 if context=="street" else 1.0,delta)
	_gain(street,.48*street_gain);_gain(music,.75*music_gain);_gain(room_tone,.035*room_gain)
	street.stream_paused=pause_gain<.001 or street_gain<.001
	room_tone.stream_paused=pause_gain<.001 or room_gain<.001
	music.stream_paused=pause_gain<.001 or music_gain<.001
	# While a character speaks, the whole neighbourhood fades away so only a
	# clean voice is heard; it returns gently after the line ends.
	var voice:bool=is_instance_valid(game.speech) and game.speech.speaker.playing
	voice_held=0.85 if voice else maxf(0.0,voice_held-delta)
	var duck_target:float=0.02 if voice_held>0.0 else 1.0
	voice_duck=move_toward(voice_duck,duck_target,delta*(10.0 if duck_target<voice_duck else 2.0))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(PREFIX+"Street"),linear_to_db(maxf(volumes.Street*voice_duck,.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(PREFIX+"Music"),linear_to_db(maxf(volumes.Music*voice_duck,.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(PREFIX+"Foley"),linear_to_db(maxf(volumes.Foley*voice_duck,.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(PREFIX+"Room"),linear_to_db(maxf(volumes.Street*voice_duck,.0001)))
	if not game.captured:steps.stop()
	_update_engines(delta)

func _physics_process(delta:float) -> void:
	_update_steps(delta)

func _select_engines() -> void:
	selected.clear()
	if context!="street" or not game.captured:return
	var candidates:Array[Dictionary]=[]
	for i in engines.size():
		var distance:float=game.camera.global_position.distance_squared_to(engines[i].car.node.global_position)
		if distance<44*44:candidates.append({"id":i,"distance":distance})
	candidates.sort_custom(func(a:Dictionary,b:Dictionary):return a.distance<b.distance)
	for i in mini(MAX_ENGINES,candidates.size()):
		var index:int=candidates[i].id;selected.append(index)
		var source:Vector3=engines[index].car.node.global_position+Vector3.UP*.8
		var query:=PhysicsRayQueryParameters3D.create(game.camera.global_position,source,1)
		engines[index].blocked=not game.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _update_engines(delta:float) -> void:
	selection_clock-=delta
	if selection_clock<=0:selection_clock=.15;_select_engines()
	for i in engines.size():
		var entry:Dictionary=engines[i];var engine:AudioStreamPlayer3D=entry.player
		var enabled:bool=i in selected and context=="street" and game.captured
		var speed:float=clampf(entry.car.speed/entry.car.cruise,0,1)
		var target:float=(.20+.40*speed)*( .3 if entry.blocked else 1.0) if enabled else 0.0
		entry.gain=move_toward(entry.gain,target,delta*1.4)
		engine.global_position=entry.car.node.global_position+Vector3.UP*.8
		engine.pitch_scale=lerpf(engine.pitch_scale,entry.pitch*(.85+.48*speed),minf(1,delta*3))
		_gain(engine,entry.gain*street_gain)
		# A hard voice budget includes outgoing fades; a new voice waits for a free slot.
		if entry.gain>.001 and not engine.playing and active_engine_count()<MAX_ENGINES:
			engine.play(rng.randf()*streams.engine.get_length())
		elif entry.gain<=.001 and engine.playing:engine.stop()

func active_engine_count() -> int:
	var count:=0
	for entry in engines:
		if entry.player.playing:count+=1
	return count

func _update_steps(delta:float) -> void:
	var at:Vector3=game.player.global_position
	var distance:=Vector2(at.x-last_position.x,at.z-last_position.z).length()
	last_position=at
	var on_floor:bool=game.player.is_on_floor()
	step_guard=maxf(0,step_guard-delta)
	if not game.captured or game.overview or game.shop_visits.busy or game.home_visits.busy or distance>1.0:
		step_distance=0;grounded=on_floor;step_moving=false
		air_time=0;fall_speed=0;step_guard=.18;return
	if step_guard>0:
		grounded=on_floor;return
	if not on_floor:
		air_time+=delta;fall_speed=maxf(fall_speed,-game.player.velocity.y)
		grounded=false;step_distance=0;step_moving=false;return
	if not grounded and air_time>.12 and fall_speed>1.5:
		_step(clampf(.12+fall_speed*.018,.16,.29))
		step_distance=0;step_guard=.12
	grounded=on_floor
	air_time=0;fall_speed=0
	# Collision recovery / a passing NPC must not sound like the player walking.
	var walking_input:=Input.get_vector("left","right","forward","back").length_squared()>.01
	if distance<.003 or not walking_input:
		step_distance=0;step_moving=false;return
	var speed:=distance/maxf(delta,.001)
	var running:=speed>3.0
	var stride:=1.65 if running else .78
	if not step_moving:step_distance=stride-.55;step_moving=true
	step_distance+=distance
	if step_distance>=stride and step_guard<=0:
		step_distance=fmod(step_distance,stride);_step(.29 if running else .22)

func _step(gain:float) -> void:
	var variant:=rng.randi_range(0,1)
	if variant>=foot_variants[next_foot]:variant+=1
	foot_variants[next_foot]=variant
	var index:=next_foot*3+variant
	next_foot=1-next_foot
	last_step=index
	steps.stream=streams["step_%s_%d"%["wood" if context=="home" else "concrete",index]]
	steps.pitch_scale=rng.randf_range(.98,1.02)
	_gain(steps,gain*rng.randf_range(.94,1.03));steps.play();step_count+=1

func _exit_tree() -> void:
	for key in ["Room","Foley","Street","Music","Voice","Master"]:
		var index:=AudioServer.get_bus_index(PREFIX+key)
		if index>0:AudioServer.remove_bus(index)
