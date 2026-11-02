extends Node
signal changed
const SAVE:="user://story_v1.json"
const DAY_SECONDS:=600.0
var game:Node3D
const SHOP_PRICE:=1000000
var owns_shop:=false
var money:=250
var elapsed:=0.0
var current_day:=1
var meals:=0
var food_credit:=0
var toilet_done:=false
var hands_clean:=false
var dinner_done:=false
var stamina:=100.0
var exhausted:=false
var employer:=-1
var delivery_id:=""
var home_id:=""
var pending_payment:=0
var delivery_reward:=0
var salon_phase:=-1 # -1 none, 1 item to pick up at BEREKE, 2 carrying it to the salon
var salon_item:=""
var salon_reward:=0
const SALON_ITEMS=["Шампунь","Сақын бояуы","Сақын лагы","Тұрақтандырғыш","Сабын пен мақта"]
var bonuses:=0
var deliveries:=0
var histories:Dictionary={}
var legacy_histories:Dictionary={}
var ledger:Array=[{"text":"Жолдан қалған ақша","amount":250}]
var save_clock:=0.0
var loaded:=false
var resume_location:Dictionary={}

func _ready() -> void:
	game=get_parent()
	if not game.automated:load_progress()
	if not delivery_id.is_empty() and delivery_index()<0:delivery_id=""
	while not game.town.population.ready_for_walk:await get_tree().physics_frame
	_assign_home()
	if not delivery_id.is_empty() and (delivery_reward<700 or delivery_reward>1500):delivery_reward=quote_for(delivery_index(),employer)
	if not loaded and not game.automated and home_index()>=0:
		var room:Node3D=game.home_visits.rooms[game.home_visits.doors[home_index()].variant]
		var at:Vector3=room.to_global(room.entry)
		resume_location={"kind":"home","door_id":home_id,"position":[at.x,at.y,at.z],"yaw":0,"pitch":0}
	changed.emit()

func load_progress(path:String=SAVE) -> bool:
	if FileAccess.file_exists(path):
		var value=JSON.parse_string(FileAccess.get_file_as_string(path))
		if value is Dictionary and value.get("version",0)==1:
			money=maxi(0,int(value.get("money",250)));elapsed=maxf(0,float(value.get("elapsed",0)))
			if int(value.get("routine_version",0))>=1:
				current_day=maxi(1,int(value.get("day",1)))
				elapsed=clampf(elapsed,0,999)
			else:
				# Keep the old day's number and all progress; begin the new schedule at 09:00.
				current_day=1+int((elapsed+1120.0/1440.0*DAY_SECONDS)/DAY_SECONDS)
				elapsed=0
			meals=clampi(int(value.get("meals",0)),0,20)
			food_credit=maxi(0,int(value.get("food_credit",0)))
			toilet_done=bool(value.get("toilet_done",false));hands_clean=bool(value.get("hands_clean",false));dinner_done=bool(value.get("dinner_done",false))
			stamina=clampf(float(value.get("stamina",100)),0,100);exhausted=bool(value.get("exhausted",false))
			employer=clampi(int(value.get("employer",-1)),-1,2)
			delivery_id=str(value.get("delivery_id",""));deliveries=maxi(0,int(value.get("deliveries",0)))
			salon_phase=clampi(int(value.get("salon_phase",-1)),-1,2)
			salon_item=str(value.get("salon_item",""));salon_reward=maxi(0,int(value.get("salon_reward",0)))
			home_id=str(value.get("home_id",""));pending_payment=maxi(0,int(value.get("pending_payment",0)))
			bonuses=maxi(0,int(value.get("bonuses",0)))
			delivery_reward=maxi(0,int(value.get("delivery_reward",0)))
			# Preserve old conversations in the save; the Kazakh edition starts a fresh chat.
			legacy_histories=value.get("histories",{}) if value.get("histories") is Dictionary else {}
			histories=value.get("kk_histories",{}) if value.get("kk_histories") is Dictionary else {}
			if value.get("ledger") is Array:
				ledger=value.ledger
				for entry in ledger:
					var label:String=str(entry.get("text",""))
					if label=="Остаток после дороги":entry.text="Жолдан қалған ақша"
					elif label.begins_with("Доставка №"):entry.text=label.replace("Доставка №","Жеткізу №").replace("день","күн")
			resume_location=value.get("location",{}) if value.get("location") is Dictionary else {}
			owns_shop=bool(value.get("owns_shop",false))
			loaded=true
			return true
	return false

func _assign_home() -> void:
	if home_index()>=0:return
	# A real, walkable apartment entrance near arrival, never the current customer.
	var best:=INF
	var graph:AStar2D=game.town.population.graph
	var origin:Vector3=game.player.position
	var local_origin:Vector3=game.town.to_local(origin)
	var start:int=game.town.population.nearest_point(Vector2(local_origin.x,local_origin.z))
	for d in game.home_visits.doors:
		if int(d.variant)<2 or d.id==delivery_id:continue
		var local:Vector3=game.town.to_local(d.landing)
		var finish:int=game.town.population.nearest_point(Vector2(local.x,local.z))
		if graph.get_point_position(finish).distance_to(Vector2(local.x,local.z))>2.6:continue
		if graph.get_point_path(start,finish).is_empty():continue
		var distance:float=d.landing.distance_squared_to(origin)
		if distance<best:best=distance;home_id=str(d.id)

func work_open() -> bool:return elapsed<DAY_SECONDS
func advance(delta:float) -> void:
	var was_open:=work_open()
	elapsed=minf(999,elapsed+maxf(0,delta))
	if was_open and not work_open():
		toilet_done=false;hands_clean=false;dinner_done=false
		changed.emit()
func _process(delta:float) -> void:
	if not game.captured or game.menu_active() or game.shop_visits.busy or game.home_visits.busy:return
	if is_instance_valid(game.daily_life) and game.daily_life.busy:return
	advance(delta);save_clock+=delta
	if save_clock>=15:save_clock=0;save()
func day() -> int:return current_day
func clock_text() -> String:
	var minutes:=mini(1439,540+int(elapsed*540.0/DAY_SECONDS))
	return "%02d:%02d"%[minutes/60,minutes%60]
func evening_objective() -> String:
	if meals<=0 and not dinner_done:return "Ауысым аяқталды. Дүкен кассасынан кешкі ас сатып ал · 200 ₸."
	if not toilet_done:return "Үйге қайт. Дәретханаға бар · E."
	if not hands_clean:return "Жуынатын бөлмеде қолыңды жу · E."
	if not dinner_done:return "Үстелге барып, кешкі асыңды іш · E."
	return "Креслода демал немесе төсекке барып ұйықта · E."
func buy_meal() -> bool:
	if not game.shop_visits.inside() or game.shop_visits.current_shop>=3 or meals>=20:return false
	# A meal on account prevents a penniless evening from blocking the story.
	if money<200:
		if meals>0 or dinner_done:return false
		food_credit+=200
		ledger.append({"text":"Кешкі ас · кейін төлеу", "amount":0})
	else:
		money-=200;ledger.append({"text":"Кешкі ас", "amount":-200})
	meals+=1
	while ledger.size()>20:ledger.pop_front()
	save();changed.emit();return true
func sleep_ready() -> bool:
	return not work_open() and delivery_id.is_empty() and toilet_done and hands_clean and dinner_done
func next_morning() -> bool:
	if not sleep_ready():return false
	current_day+=1;elapsed=0;toilet_done=false;hands_clean=false;dinner_done=false
	stamina=100;exhausted=false;changed.emit();return true
func movement_speed(delta:float,moving:bool,wants_run:bool) -> float:
	if exhausted and stamina>=30:exhausted=false
	var sprinting:=moving and wants_run and not exhausted and stamina>0
	stamina=clampf(stamina+(-12.5 if sprinting else 9.0)*delta,0,100)
	if stamina<=0:exhausted=true
	return 5.4 if sprinting and not exhausted else 1.85
func shop_name(index:int) -> String:
	if index==3:return "Менің дүкенім" if owns_shop else "Бос дүкен"
	if index==4:return "ANA BEAUTY"
	return ["BEREKE","DÜKEN","KÖRŞI"][clampi(index,0,2)]
func purchase_shop() -> bool:
	if owns_shop or money<SHOP_PRICE or game.shop_visits.current_shop!=3 or game.shop_visits.busy:return false
	money-=SHOP_PRICE;owns_shop=true
	ledger.append({"text":"Дүкен сатып алу","amount":-SHOP_PRICE})
	while ledger.size()>20:ledger.pop_front()
	save();changed.emit();return true
func objective() -> String:
	if pending_payment>0:return "%s дүкеніне оралып, %d ₸ еңбекақыңды ал."%[shop_name(employer),pending_payment]
	if not work_open() and delivery_id.is_empty() and salon_phase<0:return evening_objective()
	if employer<0:return "BEREKE дүкеніне барып, Ерланмен жұмыс туралы сөйлес."
	if not delivery_id.is_empty():return address()+": үйге кіріп, тапсырысты бер. Еңбекақы: %d ₸."%delivery_reward
	if salon_phase==1:return "BEREKE дүкеніне барып, касса жағында салон тапсырысын алыңыз (E). Зат: %s."%salon_item
	if salon_phase==2:return "«ANA BEAUTY» салонына кіріп, қабылдаушы Аружанға %s беріңіз (E). Сыйы: %d ₸."%[salon_item,salon_reward]
	return shop_name(employer)+" дүкенінен келесі тапсырысты ал."
func address_for(index:int) -> String:
	if index<0 or index>=game.home_visits.doors.size():return ""
	var d:Dictionary=game.home_visits.doors[index]
	return "%d-үй, %s-кіреберіс"%[int(d.building_index)+1,str(d.id).get_slice("_",2)]
func address() -> String:return address_for(delivery_index())
func door_index(id:String) -> int:
	for i in game.home_visits.doors.size():
		if game.home_visits.doors[i].id==id:return i
	return -1
func home_index() -> int:return door_index(home_id)
func delivery_index() -> int:return door_index(delivery_id)
func can_enter(index:int) -> bool:
	return index>=0 and (index==home_index() or (not delivery_id.is_empty() and index==delivery_index()))
func hire(shop:int) -> bool:
	if employer>=0 or shop!=0:return false
	employer=shop;save();changed.emit();return true
func collect(shop:int) -> bool:
	if not work_open() or employer!=shop or not delivery_id.is_empty() or pending_payment>0:return false
	var graph:AStar2D=game.town.population.graph
	if graph.get_point_count()==0:return false
	var origin:Vector3=game.town.shops[shop].position
	var from:int=game.town.population.nearest_point(Vector2(origin.x,origin.z))
	var candidates:Array[Dictionary]=[]
	for d in game.home_visits.doors:
		if d.id==home_id:continue
		var local:Vector3=game.town.to_local(d.landing)
		var to:int=game.town.population.nearest_point(Vector2(local.x,local.z))
		var path:PackedVector2Array=graph.get_point_path(from,to)
		if path.size()<3 or path[-1].distance_to(Vector2(local.x,local.z))>2.6:continue
		var dist:=Vector2(origin.x,origin.z).distance_to(Vector2(local.x,local.z))
		if dist>18 and dist<85:candidates.append(d)
	if candidates.is_empty():return false
	delivery_id=str(candidates[posmod(deliveries*17+shop*7,candidates.size())].id)
	delivery_reward=quote_for(delivery_index(),shop)
	save();changed.emit();return true
func reward_for_distance(metres:float) -> int:
	# A known fixed quote, rounded to 50 tenge; no time pressure or random payouts.
	return clampi(roundi((700.0+clampf((metres-30.0)/150.0,0,1)*800.0)/50.0)*50,700,1500)
func quote_for(index:int,shop:int) -> int:
	if index<0 or shop<0 or shop>2:return 700
	var origin:Vector3=game.town.shops[shop].position
	var target:Vector3=game.town.to_local(game.home_visits.doors[index].landing)
	var graph:AStar2D=game.town.population.graph
	if graph.get_point_count()==0:return 700
	var from:int=game.town.population.nearest_point(Vector2(origin.x,origin.z))
	var to:int=game.town.population.nearest_point(Vector2(target.x,target.z))
	var path:PackedVector2Array=graph.get_point_path(from,to)
	var metres:=0.0
	for i in range(1,path.size()):metres+=path[i-1].distance_to(path[i])*preload("res://district_layout.gd").ENVIRONMENT_SCALE
	return reward_for_distance(metres)
func can_deliver() -> bool:
	if delivery_id.is_empty() or not game.home_visits.inside() or game.home_visits.busy:return false
	if game.home_visits.current_door!=delivery_index():return false
	if not is_instance_valid(game.story_ui) or game.story_ui.is_modal():return false
	return game.home_visits.is_recipient(game.story_ui.ray_target())
func deliver() -> bool:
	if not can_deliver():return false
	delivery_id="";deliveries+=1;pending_payment+=delivery_reward;delivery_reward=0
	game.home_visits.delivery_done=true
	save();changed.emit();return true
# --- Salon delivery: a separate short job for the ANA BEAUTY shop -----------
func take_salon_order(shop:int) -> bool:
	if shop!=4 or salon_phase>=0 or employer<0 or not work_open() or not delivery_id.is_empty():return false
	salon_phase=1
	salon_item=SALON_ITEMS[posmod(deliveries*5+current_day,5)]
	salon_reward=900+posmod(deliveries*7+current_day*3,11)*50 # 900..1400
	save();changed.emit();return true
func try_salon_pickup() -> bool:
	if salon_phase!=1 or not game.shop_visits.inside() or game.shop_visits.busy:return false
	if game.shop_visits.current_shop!=0:return false
	var room:Node3D=game.shop_visits.rooms[0]
	if not is_instance_valid(room.checkout):return false
	var local:Vector3=room.to_local(game.player.global_position)
	if local.distance_to(room.checkout_approach)>2.4:return false
	salon_phase=2
	save();changed.emit();return true
func can_deliver_salon() -> bool:
	if salon_phase!=2 or not game.shop_visits.inside() or game.shop_visits.busy:return false
	if game.shop_visits.current_shop!=4:return false
	if not is_instance_valid(game.story_ui) or game.story_ui.is_modal():return false
	return game.story_ui.ray_target()=="cashier_4"
func deliver_salon() -> bool:
	if not can_deliver_salon():return false
	salon_phase=-1
	money+=salon_reward;bonuses+=5
	ledger.append({"text":"Салон жеткізу · %s · %d-күн"%[salon_item,day()],"amount":salon_reward})
	salon_item="";salon_reward=0
	while ledger.size()>20:ledger.pop_front()
	save();changed.emit();return true

func claim_payment(shop:int) -> bool:
	if shop!=employer or pending_payment<=0:return false
	if not game.shop_visits.inside() or game.shop_visits.current_shop!=shop:return false
	money+=pending_payment;bonuses+=10
	ledger.append({"text":"Жеткізу №%d · %d-күн"%[deliveries,day()],"amount":pending_payment})
	pending_payment=0
	if food_credit>0:
		var repayment:=mini(money,food_credit);money-=repayment;food_credit-=repayment
		ledger.append({"text":"Азық-түлік қарызын өтеу","amount":-repayment})
	while ledger.size()>20:ledger.pop_front()
	save();changed.emit();return true
func context_text() -> String:
	return "Натан Астанаға жаңадан келді, қазақша үйреніп жүр. Арманы — өз дүкенін ашу. %d-күн, сағат %s. Ақшасы %d теңге, бонустары %d. Жұмыс орны: %s. Жеткізілген тапсырыс: %d. Қазіргі міндет: %s. Әр жеткізуге 700–1500 теңге, нақты сома тапсырыс берілгенде бекітіледі. Өз пәтері: %s. Бөтен үйге тек тапсырыспен кіреді. Еңбекақыны жеткізген соң дүкенге қайтып алады. Ауысым 09:00–18:00: 10 нақты минут. 18:00-ден кейін жаңа тапсырыс берілмейді, алынғанын аяқтауға болады. Кешкі ас кез келген дүкен кассасында E арқылы 200 теңге тұрады. Үйде дәретхана, қол жуу, үстелде тамақтану және төсекке ұйықтау E арқылы орындалады. Ұйқыдан кейін келесі күн 09:00-де басталады. Бос дүкеннің иесі Ермек оны 1 000 000 теңгеге сатады. Сатып алу тек ойын батырмасы арқылы болады; сөзіңмен ақша не кілт берме. «ANA BEAUTY» салонында қабылдаушы Аружан, стилист Дана және қызметкер Асхат жұмыс істейді, клиенттер келеді; олармен қазақша сөйлесуге болады. Салон тапсырысы: BEREKE кассасынан зат алып (E), салон қабылдаушысына бересің (E), 900–1400 теңге + 5 бонус. Жиһаз және тауар сатып алу келесі кезеңде қосылады. Меншік күйі: %s. Оқиғаның кейінгі тараулары әзірше ашылған жоқ."%[day(),clock_text(),money,bonuses,shop_name(employer) if employer>=0 else "жоқ",deliveries,objective(),address_for(home_index()),"Натандікі" if owns_shop else "сатылуда"]
func save() -> void:
	if game.automated:return
	write_progress()
func write_progress(path:String=SAVE) -> bool:
	if is_instance_valid(game) and game.is_inside_tree() and (game.session_started or game.automated) and not game.menu_active():resume_location=game.capture_location()
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify({"owns_shop":owns_shop,"version":1,"routine_version":1,"day":current_day,"meals":meals,"food_credit":food_credit,"toilet_done":toilet_done,"hands_clean":hands_clean,"dinner_done":dinner_done,"stamina":stamina,"exhausted":exhausted,"location":resume_location,"money":money,"elapsed":elapsed,"employer":employer,"delivery_id":delivery_id,"home_id":home_id,"pending_payment":pending_payment,"delivery_reward":delivery_reward,"salon_phase":salon_phase,"salon_item":salon_item,"salon_reward":salon_reward,"bonuses":bonuses,"deliveries":deliveries,"histories":legacy_histories,"kk_histories":histories,"ledger":ledger}));file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))==OK
func _exit_tree() -> void:
	if is_instance_valid(game):save()
