extends Node
signal feedback(words:String)
signal transcript(words:String,details:Dictionary)
signal changed
const VOICE_REVISION="issai-high-v1-speed095"
const BUILT_LINES="res://assets/voice_lines/"+VOICE_REVISION
const USER_LINES="user://voice_cache/"+VOICE_REVISION
var cache_dir:=USER_LINES
var cache_hits:=0
var cache_writes:=0
const URL="http://127.0.0.1:18765"
var game:Node
var recording:=false
var working:=false
var started_at:=0.0
var bus:=-1
var recorder:AudioEffectRecord
var mic:AudioStreamPlayer
var speaker:AudioStreamPlayer
var request:HTTPRequest
var health:HTTPRequest
var serial:=0
var enabled:=true
var expected:=""
var process_id:=-1
var startup_attempts:=0
var service_ready:=false
var last_words:=""
var last_actor:=""
var pending_words:=""
var pending_actor:=""
var last_voice_check:=0.0
var voice_peak_rms:=0.0
var voice_quiet_since:=0.0

func _ready() -> void:
	game=get_parent();speaker=AudioStreamPlayer.new();add_child(speaker)
	var voice_bus:=AudioServer.get_bus_index("Nazerke Voice")
	var master_bus:=AudioServer.get_bus_index("Nazerke Master")
	speaker.bus="Nazerke Voice" if voice_bus>=0 else ("Nazerke Master" if master_bus>=0 else "Master")
	speaker.volume_db=6.0 # 200% — dialogue clearly louder than the world
	var config:=ConfigFile.new()
	if config.load("user://voice.cfg")==OK:enabled=bool(config.get_value("voice","enabled",true))
	if not game.automated:get_tree().create_timer(3.0).timeout.connect(ensure_service) # keep the voice service warm

func ensure_service() -> void:
	if game.automated and not "--voice-live" in OS.get_cmdline_user_args():return
	if is_instance_valid(health):return
	if startup_attempts>=15:feedback.emit("Дауыс қызметі іске қосылмады. Мәтінмен жалғастыруға болады.");return
	startup_attempts+=1
	health=HTTPRequest.new();health.timeout=2;add_child(health)
	health.request_completed.connect(func(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray):
		health.queue_free();health=null
		var data=JSON.parse_string(body.get_string_from_utf8()) if not body.is_empty() else null
		service_ready=result==HTTPRequest.RESULT_SUCCESS and code==200 and data is Dictionary and data.get("service","")=="nazerke-kazakh-voice" and data.get("ready",false)
		if service_ready:
			startup_attempts=0
			if not pending_words.is_empty():var words:=pending_words;pending_words="";speak(words,pending_actor)
			return
		if result!=HTTPRequest.RESULT_SUCCESS and (process_id<0 or not OS.is_process_running(process_id)):
			var python:=preload("res://runtime_paths.gd").python()
			if not FileAccess.file_exists(python):feedback.emit("Дауыс моделі орнатылмаған. Мәтінмен сөйлесуге болады.");return
			process_id=OS.create_process(python,[preload("res://runtime_paths.gd").root_dir().path_join("voice/server.py")])
		if game.story_ui.is_modal():get_tree().create_timer(2).timeout.connect(ensure_service)
	)
	health.request(URL+"/health")

func stop() -> void:
	serial+=1;working=false;pending_words="";speaker.stop()
	if recording:recorder.set_recording_active(false);mic.stop();recording=false
	if is_instance_valid(request):request.cancel_request();request.queue_free();request=null
	changed.emit()

func set_enabled(value:bool) -> void:
	enabled=value
	if not enabled:speaker.stop();pending_words=""
	var config:=ConfigFile.new();config.set_value("voice","enabled",enabled);config.save("user://voice.cfg")

func speaker_id(actor:String) -> int:
	if game.story_ui.actors.has(actor):
		var character:String=game.story_ui.actors[actor].character_id
		return [2,3,4,5][posmod(actor.hash(),4)] if character in ["asel","dana","aruzhan"] else posmod(actor.hash(),2)
	return 1

func audio_key(words:String,sid:int) -> String:
	return (VOICE_REVISION+"\n"+str(sid)+"\n"+words.strip_edges().left(2500)).sha256_text()

func cached_audio(key:String) -> AudioStreamWAV:
	for folder in [BUILT_LINES,cache_dir]:
		var path:String=folder+"/"+key+".wav"
		if folder==BUILT_LINES and ResourceLoader.exists(path):
			var imported=load(path)
			if imported is AudioStreamWAV and not imported.data.is_empty():return imported
		if not FileAccess.file_exists(path):continue
		var audio:=AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
		if audio!=null and not audio.data.is_empty():return audio
	return null

func cache_audio(audio:AudioStreamWAV,key:String) -> void:
	var folder:=ProjectSettings.globalize_path(cache_dir)
	if DirAccess.make_dir_recursive_absolute(folder)!=OK:return
	var path:=folder+"/"+key+".wav"
	if audio.save_to_wav(path+".tmp.wav")==OK:
		if DirAccess.rename_absolute(path+".tmp.wav",path)==OK:cache_writes+=1

func speak(words:String,actor:String) -> void:
	last_words=words;last_actor=actor
	if not enabled or recording or words.strip_edges().is_empty():return
	var key:=audio_key(words,speaker_id(actor))
	var stored:=cached_audio(key)
	if stored!=null:
		stop();last_words=words;last_actor=actor;cache_hits+=1
		speaker.stream=stored;speaker.play();return
	if not service_ready:
		pending_words=words;pending_actor=actor;ensure_service();return
	stop();last_words=words;last_actor=actor
	post("tts",{"text":words.strip_edges().left(2500),"speaker":speaker_id(actor)})

func toggle_recording() -> void:
	if recording:finish_recording();return
	if game.story_ui.waiting:return
	if not service_ready:ensure_service();feedback.emit("Дауыс моделі іске қосылып жатыр. Сәл күте тұр.");return
	stop()
	if bus<0:
		AudioServer.add_bus();bus=AudioServer.bus_count-1;AudioServer.set_bus_name(bus,"NazerkeMicrophone")
		AudioServer.set_bus_mute(bus,true)
		recorder=AudioEffectRecord.new();recorder.format=AudioStreamWAV.FORMAT_16_BITS;AudioServer.add_bus_effect(bus,recorder)
		mic=AudioStreamPlayer.new();mic.stream=AudioStreamMicrophone.new();mic.bus="NazerkeMicrophone";add_child(mic)
	recorder.set_recording_active(true);mic.play();recording=true;started_at=Time.get_ticks_msec()/1000.0
	last_voice_check=0.0;voice_peak_rms=0.0;voice_quiet_since=0.0
	feedback.emit("Тыңдап тұрмын… Сөйлесіп болсаңыз — сәл үнсіз қалыңыз, мен өзім аяқтаймын.");changed.emit()

func finish_recording() -> void:
	if not recording:return
	recorder.set_recording_active(false);mic.stop();recording=false
	var audio:=recorder.get_recording()
	if audio==null or audio.data.size()<4000:feedback.emit("Дауыс естілмеді. Микрофонды тексеріп, қайталап көр.");changed.emit();return
	feedback.emit("Айтқаның мәтінге айналып жатыр…")
	post("stt",{"pcm":Marshalls.raw_to_base64(audio.data),"rate":audio.mix_rate,"channels":2 if audio.stereo else 1,"expected":expected})

func post(kind:String,data:Dictionary,retry:int=0) -> void:
	working=true;serial+=1;var token:=serial
	request=HTTPRequest.new();request.timeout=60;request.body_size_limit=16000000;add_child(request)
	request.request_completed.connect(func(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray):
		if token!=serial:return
		request.queue_free();request=null
		if code==503 and retry<20:
			get_tree().create_timer(.5).timeout.connect(func():
				if token==serial and game.story_ui.modal=="chat":post(kind,data,retry+1)
			)
			return
		working=false;changed.emit()
		if "--voice-live" in OS.get_cmdline_user_args():print("VOICE_HTTP | ",kind," | result=",result," code=",code," bytes=",body.size())
		if game.story_ui.modal!="chat":return
		if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
			if result!=HTTPRequest.RESULT_SUCCESS:service_ready=false;startup_attempts=0
			feedback.emit("Дауыс анық естілмеді немесе қызмет бос емес. Қайталап көр, не мәтін жаз." if kind=="stt" else "Дыбыстау қолжетімсіз. Жауапты мәтіннен оқуға болады.")
			return
		var value=JSON.parse_string(body.get_string_from_utf8())
		if not value is Dictionary:return
		if kind=="stt":transcript.emit(str(value.get("text","")),value)
		elif value.has("pcm"):
			var audio:=AudioStreamWAV.new();audio.format=AudioStreamWAV.FORMAT_16_BITS;audio.mix_rate=int(value.get("rate",22050));audio.stereo=false
			audio.data=Marshalls.base64_to_raw(value.pcm)
			if audio.data.is_empty():return
			cache_audio(audio,audio_key(str(data.get("text","")),int(data.get("speaker",0))))
			if enabled:speaker.stream=audio;speaker.play()
	)
	var error:=request.request(URL+"/"+kind,["Content-Type: application/json"],HTTPClient.METHOD_POST,JSON.stringify(data))
	if error!=OK:stop();feedback.emit("Дауыс қызметі қосылмады. Мәтінмен жалғастыра бер.")
	changed.emit()

func _process(_delta:float) -> void:
	if not recording:return
	var now:=Time.get_ticks_msec()/1000.0
	if now-started_at>=30:finish_recording();return
	if not game.captured:stop();return
	# Auto-stop right after the speaker pauses — no waiting for a button.
	if now-last_voice_check>=0.25:
		last_voice_check=now
		var tail:AudioStreamWAV=recorder.get_recording()
		if tail!=null and not tail.data.is_empty():
			var start:=tail.data.size()-int(tail.mix_rate*0.35)*2
			if start<0:start=0
			var sum:=0.0;var count:=0
			var end:=tail.data.size()-1
			var i:=start
			while i<=end:
				var s:int=tail.data[i] | (tail.data[i+1]<<8)
				if s>=32768:s-=65536
				sum+=s*s;count+=1;i+=8
			if count>0:
				var rms:=sqrt(sum/count)
				if rms>voice_peak_rms:voice_peak_rms=rms
				# Adaptive: quiet means 20% below the speaker's own peak level.
				var quiet_threshold:=maxf(25.0,voice_peak_rms*0.2)
				if rms>=quiet_threshold:voice_quiet_since=0.0
				elif voice_quiet_since<=0.0:voice_quiet_since=now
	# Auto-stop right after the speaker pauses — no waiting for a button.
	if voice_peak_rms>=40.0 and voice_quiet_since>0.0 and now-voice_quiet_since>1.15:finish_recording()

func _exit_tree() -> void:
	if is_instance_valid(mic):mic.stop()
	if recorder:recorder.set_recording_active(false)
	if bus>=0 and bus<AudioServer.bus_count:AudioServer.remove_bus(bus)
	if process_id>0 and OS.is_process_running(process_id):OS.kill(process_id)
