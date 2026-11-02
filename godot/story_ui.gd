extends CanvasLayer
const UI=preload("res://ui_theme.gd")
const API_URL:="https://llm.alem.ai/v1/chat/completions"
var game:Node3D
var profiles:Dictionary={}
var actors:Dictionary={}
var target_id:=""
var active_id:=""
var modal:=""
var reticle:Label
var hint:Label
var task:Label
var clock_label:Label
var overlay:Control
var phone:Control
var phone_content:VBoxContainer
var phone_clock:Label
var phone_page:="home"
var phone_balance:Label
var phone_task:Label
var map_view:Control
var map_status:Label
var selected_shop:=0
var selected_home:=false
var phrase_help:Label
var chat:PanelContainer
var chat_name:Label
var chat_role:Label
var messages:RichTextLabel
var draft:LineEdit
var send_button:Button
var job_button:Button
var status:Label
var portrait_holder:SubViewportContainer
var portrait:SubViewport
var request:HTTPRequest
var request_serial:=0
var waiting:=false
var pending_text:=""
var request_started:=0
var refresh:=0.0
var aim_clock:=0.0
var phone_scroll:ScrollContainer
var tabs:Dictionary={}
var info:PanelContainer
var phrase_button:Button
var purchase_confirm:ConfirmationDialog
var mic_button:Button
var listen_button:Button
var practice_button:Button
var voice_toggle:CheckButton
var voice_status:Label

func _ready() -> void:
	game=get_parent();layer=30
	profiles=JSON.parse_string(FileAccess.get_file_as_string("res://npc_profiles.json"))
	var theme:=UI.make(false)
	var root:=Control.new();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.theme=theme;add_child(root)
	reticle=Label.new();reticle.text="•";reticle.add_theme_font_size_override("font_size",26)
	reticle.add_theme_color_override("font_outline_color",Color("14212a"));reticle.add_theme_constant_override("outline_size",5)
	root.add_child(reticle);reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER);reticle.position-=Vector2(6,19);reticle.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hint=Label.new();root.add_child(hint);hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left=-350;hint.offset_right=350;hint.offset_top=-130;hint.offset_bottom=-95
	hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hint.add_theme_color_override("font_outline_color",Color("102029"));hint.add_theme_constant_override("outline_size",6)
	info=PanelContainer.new();root.add_child(info);info.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	info.offset_left=20;info.offset_right=385;info.offset_top=96;info.offset_bottom=0
	info.add_theme_stylebox_override("panel",_style(Color(.04,.08,.1,.9),12))
	var info_box:=VBoxContainer.new();info.add_child(info_box)
	clock_label=_label(info_box,"",16);task=_label(info_box,"",16);task.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	task.custom_minimum_size.x=305
	_label(info_box,"F — телефон · Сол жақ батырма — сөйлесу",13)
	overlay=Control.new();root.add_child(overlay);overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	var shade:=ColorRect.new();shade.color=Color(0,.02,.04,.25);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;overlay.add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_phone();_build_chat();overlay.hide();phone.hide();chat.hide()
	game.story.changed.connect(_story_changed)
	_register_actors()

func _style(color:Color,padding:int=16) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=color;style.set_corner_radius_all(14)
	style.content_margin_left=padding;style.content_margin_right=padding;style.content_margin_top=padding;style.content_margin_bottom=padding
	return style
func _label(parent:Node,words:String,font_size:int=17) -> Label:
	var label:=Label.new();label.text=words;label.add_theme_font_size_override("font_size",font_size);parent.add_child(label);return label
func _button(parent:Node,words:String,callback:Callable) -> Button:
	var button:=Button.new();button.text=words;button.custom_minimum_size.y=44;button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;parent.add_child(button);button.pressed.connect(callback);return button
func is_modal() -> bool:return not modal.is_empty()
func _register_actors() -> void:
	for w in game.town.walkers:
		var id:="citizen_%02d"%int(w.id)
		if not actors.has(id):actors[id]=w.node;w.node.set_meta("npc_id",id)
	for i in game.shop_visits.rooms.size():
		var room:Node3D=game.shop_visits.rooms[i]
		var actor:Node3D=room.cashier
		var id:="cashier_%d"%i;actors[id]=actor;actor.set_meta("npc_id",id)
		# The salon keeps its own living staff: stylist, attendant and clients.
		if "talkable_actors" in room:
			for pair in room.talkable_actors:
				if not actors.has(pair.id):actors[pair.id]=pair.actor;pair.actor.set_meta("npc_id",pair.id)

func ray_target() -> String:
	if game.overview or game.shop_visits.busy or game.home_visits.busy:return ""
	var from:Vector3=game.camera.global_position
	var query:=PhysicsRayQueryParameters3D.create(from,from-game.camera.global_basis.z*3.4,1|8)
	var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():return ""
	var node:Node=hit.collider
	while node!=null:
		if node.has_meta("npc_id"):return str(node.get_meta("npc_id"))
		node=node.get_parent()
	return ""
func try_talk() -> bool:
	if is_modal() or not game.captured or game.daily_life.busy or game.daily_life.seated:return false
	var id:=ray_target()
	if id.is_empty():return false
	open_chat(id);return true
func _physics_process(delta:float) -> void:
	aim_clock-=delta
	if aim_clock>0:return
	aim_clock=.1
	target_id=ray_target() if not is_modal() and game.captured else ""
	reticle.visible=game.captured and not is_modal() and not game.overview
	reticle.modulate=Color("8cddbb") if not target_id.is_empty() else Color.WHITE
	hint.text="Сол жақ батырма · Сөйлесу — "+str(profiles[target_id].name) if not target_id.is_empty() else ""
	if not is_modal() and game.captured and game.story.can_deliver():hint.text="E · Тапсырысты беру — "+game.story.address()
	elif not is_modal() and game.captured and game.story.can_deliver_salon():hint.text="E · Салонға тапсырысты беру — Аружан"
func _process(delta:float) -> void:
	refresh-=delta
	if refresh>0:return
	refresh=.3;_register_actors()
	if waiting and modal=="chat":
		status.text=str(profiles[active_id].name)+" жауап жазып жатыр… %d с"%int((Time.get_ticks_msec()-request_started)/1000)
	clock_label.text="%d-КҮН  ·  %s  ·  %d ₸"%[game.story.day(),game.story.clock_text(),game.story.money]
	task.text="ЖАҢА БАСТАУ\n"+game.story.objective() if game.story.deliveries==0 else game.story.objective()
	phone_clock.text=game.story.clock_text()+"                        ▴  94%"
	if is_instance_valid(phone_balance):phone_balance.text="%d ₸"%game.story.money
	if is_instance_valid(phone_task):phone_task.text=game.story.objective()
	if is_instance_valid(map_status) and is_instance_valid(map_view):
		map_status.text=map_view.target_name+"\n"+("Жаяу · %d м"%roundi(map_view.route_length) if map_view.reachable else "Бағыт әзірше қолжетімсіз")

func _input(event:InputEvent) -> void:
	if game.automated or game.menu_active() or game.daily_life.busy:return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_ESCAPE and is_modal():
			close_modal();get_viewport().set_input_as_handled()
		elif event.physical_keycode==KEY_F and modal!="chat":
			if modal=="phone":close_modal()
			elif game.captured and not game.overview and not game.home_visits.busy and not game.shop_visits.busy:open_phone()
			get_viewport().set_input_as_handled()
	if is_modal() and event is InputEventMouseButton and event.pressed and not game.captured:game.set_capture(true)

func _show_modal(kind:String) -> void:
	modal=kind;overlay.show();phone.visible=kind=="phone";chat.visible=kind=="chat"
	game.player.velocity=Vector3.ZERO
	game.hud.get_parent().hide();info.hide()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;game.pause.hide()
	game.shop_visits.prompt.text="";game.home_visits.prompt.text=""
func close_modal() -> void:
	game.speech.stop()
	purchase_confirm.hide()
	_cancel_request()
	if actors.has(active_id) and is_instance_valid(actors[active_id]):actors[active_id].set_meta("in_dialogue",false)
	active_id="";modal="";overlay.hide();phone.hide();chat.hide();game.hud.get_parent().show();info.show()
	if is_instance_valid(portrait):portrait_holder.remove_child(portrait);portrait.queue_free();portrait=null
	game.set_capture(true);game.story.save()
func open_phone() -> void:
	_show_modal("phone");_phone_page(phone_page)

func _build_phone() -> void:
	phone=Control.new();phone.set_script(preload("res://phone_shell.gd"));overlay.add_child(phone)
	phone.theme=UI.make(true)
	phone.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	phone.offset_left=-410;phone.offset_right=-50;phone.offset_top=-350;phone.offset_bottom=350
	var screen:=VBoxContainer.new();phone.add_child(screen);screen.position=Vector2(29,87);screen.size=Vector2(302,520)
	screen.add_theme_constant_override("separation",10)
	phone_clock=_label(screen,"",14)
	var bar:=HBoxContainer.new();screen.add_child(bar);bar.add_theme_constant_override("separation",5)
	for entry in [["Басты","home"],["Карта","map"],["Шот","bank"]]:
		var button:=_button(bar,entry[0],_phone_page.bind(entry[1]));button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y=38;button.add_theme_font_size_override("font_size",15);tabs[entry[1]]=button
	phone_scroll=ScrollContainer.new();phone_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;phone_scroll.follow_focus=true
	phone_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;screen.add_child(phone_scroll)
	phone_content=VBoxContainer.new();phone_content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;phone_content.size_flags_vertical=Control.SIZE_EXPAND_FILL
	phone_content.add_theme_constant_override("separation",12);phone_scroll.add_child(phone_content)
	var home:=Button.new();phone.add_child(home);home.position=Vector2(157,638);home.size=Vector2(46,46);home.flat=true;home.tooltip_text="Басты бет · Touch ID";home.pressed.connect(_phone_page.bind("home"))
	var close:=_button(phone,"Телефонды жабу · F / Esc",close_modal);close.position=Vector2(0,712);close.size=Vector2(360,46);UI.primary(close)
func _phone_page(page:String) -> void:
	phone_page=page
	phone_scroll.scroll_vertical=0
	for key in tabs:
		tabs[key].remove_theme_stylebox_override("normal");tabs[key].remove_theme_color_override("font_color")
		if key==page:tabs[key].add_theme_stylebox_override("normal",UI.panel(UI.TEAL,12,10));tabs[key].add_theme_color_override("font_color",Color.WHITE)
	for child in phone_content.get_children():phone_content.remove_child(child);child.queue_free()
	phone_balance=null;phone_task=null;map_view=null;map_status=null
	if page=="map":
		map_view=Control.new();map_view.set_script(preload("res://phone_map.gd"));map_view.game=game;map_view.selected_shop=selected_shop;map_view.selected_home=selected_home
		map_view.size_flags_vertical=Control.SIZE_EXPAND_FILL;phone_content.add_child(map_view)
		map_view.destination_selected.connect(func(_label_text:String):selected_shop=map_view.selected_shop;selected_home=map_view.selected_home)
		map_status=_label(phone_content,"Бағыт есептелуде…",14);map_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		_label(phone_content,"● Сіз · ● Дүкен · ◆ Үй · ━ Бағыт",12)
		var controls:=HBoxContainer.new();phone_content.add_child(controls)
		_button(controls,"−",func():map_view.zoom=maxf(1,map_view.zoom/1.25))
		_button(controls,"Ортаға",func():map_view.center_map())
		_button(controls,"+",func():map_view.zoom=minf(2.7,map_view.zoom*1.25))
		_button(controls,"Үйім",func():map_view.choose_home())
	elif page=="bank":
		_label(phone_content,"МЕНІҢ ШОТЫМ",16);phone_balance=_label(phone_content,"%d ₸"%game.story.money,34)
		_label(phone_content,"Бонус: %d ұпай"%game.story.bonuses,15)
		_label(phone_content,"Азық-түлік қарызы: %d ₸"%game.story.food_credit,15)
		_label(phone_content,"Соңғы түсімдер",15)
		var log:=RichTextLabel.new();log.custom_minimum_size.y=240;log.size_flags_vertical=Control.SIZE_EXPAND_FILL;phone_content.add_child(log)
		for i in range(game.story.ledger.size()-1,maxi(-1,game.story.ledger.size()-7),-1):
			var item:Dictionary=game.story.ledger[i];log.add_text(str(item.text)+"\n%+d ₸\n\n"%int(item.amount))
	else:
		_label(phone_content,"СӘЛЕМ, ҚАЗАҚСТАН",18)
		var intro:=_label(phone_content,"Натан, қош келдің! Өз дүкеніңе апарар жол — жаңа таныстықтар мен алғашқы жұмыс.",16)
		intro.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		phone_balance=_label(phone_content,"%d ₸"%game.story.money,32);phone_balance.add_theme_color_override("font_color",UI.TEAL)
		_label(phone_content,"Кешкі ас: %d дана"%game.story.meals,15)
		_label(phone_content,"Қазіргі мақсат",15)
		phone_task=_label(phone_content,game.story.objective(),16);phone_task.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		UI.primary(_button(phone_content,"Бағытты ашу",_phone_page.bind("map")))
		_button(phone_content,"Менің пәтерім",_home_route)
		_button(phone_content,game.story.shop_name(3),func():selected_home=false;selected_shop=3;_phone_page("map"))
		var help:=_label(phone_content,"Сөйлесу — тінтуірдің сол жағы.\n09:00–18:00 = 10 минут.\nКелесі күн — ұйқыдан кейін.",14);help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	refresh=0

func _build_chat() -> void:
	chat=PanelContainer.new();overlay.add_child(chat);chat.theme=UI.make(true);chat.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	chat.offset_left=-500;chat.offset_right=500;chat.offset_top=-360;chat.offset_bottom=360
	chat.add_theme_stylebox_override("panel",UI.panel(UI.PAPER,26,20))
	var columns:=HBoxContainer.new();columns.add_theme_constant_override("separation",26);chat.add_child(columns)
	var side:=VBoxContainer.new();side.custom_minimum_size.x=235;side.add_theme_constant_override("separation",10);columns.add_child(side)
	_label(side,"ТАНЫСЫҢЫЗ",13).add_theme_color_override("font_color",UI.MUTED)
	portrait_holder=SubViewportContainer.new();portrait_holder.custom_minimum_size=Vector2(160,145);portrait_holder.stretch=true;portrait_holder.mouse_filter=Control.MOUSE_FILTER_IGNORE;side.add_child(portrait_holder)
	chat_name=_label(side,"",29);chat_role=_label(side,"",16);chat_role.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_label(side,"Қазақша сөйлесейік",18).add_theme_color_override("font_color",UI.TEAL)
	var encouragement:=_label(side,"Қателесуден қорықпа.
Өз сөзіңмен жауап бер.",15);encouragement.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_label(side,"СӨЙЛЕМ ҮЛГІЛЕРІ",12).add_theme_color_override("font_color",UI.MUTED)
	phrase_button=_button(side,"Сәлемдесу",_context_phrase)
	_button(side,"Танысайық",_quick_message.bind("Атыңыз кім? Не істейсіз?"))
	_button(side,"Қайталаңызшы",_quick_message.bind("Түсінбедім. Қарапайым сөзбен қайталаңызшы."))
	var box:=VBoxContainer.new();box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_theme_constant_override("separation",12);columns.add_child(box)
	var header:=HBoxContainer.new();box.add_child(header)
	var heading:=_label(header,"Әңгіме",26);heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_button(header,"Жабу · Esc",close_modal)
	messages=RichTextLabel.new();messages.bbcode_enabled=false;messages.selection_enabled=true;messages.scroll_following=true
	messages.custom_minimum_size=Vector2(0,180);messages.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.add_child(messages)
	status=_label(box,"",15);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.add_theme_color_override("font_color",UI.TEAL)
	phrase_help=_label(box,"",14);phrase_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;phrase_help.add_theme_color_override("font_color",UI.MUTED)
	job_button=_button(box,"",_job_action);job_button.add_theme_font_size_override("font_size",16);UI.primary(job_button)
	var voice_row:=HBoxContainer.new();voice_row.add_theme_constant_override("separation",6);box.add_child(voice_row)
	mic_button=_button(voice_row,"Микрофон",func():game.speech.toggle_recording())
	listen_button=_button(voice_row,"Қайта тыңдау",func():game.speech.speak(game.speech.last_words,active_id))
	practice_button=_button(voice_row,"Қайталап айту",practice_phrase)
	voice_toggle=CheckButton.new();voice_toggle.text="Дауыс";voice_row.add_child(voice_toggle);voice_toggle.button_pressed=true
	for button in [mic_button,listen_button,practice_button]:button.add_theme_font_size_override("font_size",15)
	voice_status=_label(box,"Қазақша айт немесе мәтін жаз. Жауапты дауыстап тыңда.",14);voice_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",10);box.add_child(row)
	draft=LineEdit.new();draft.placeholder_text="Ойыңды қазақша жаз…";draft.max_length=500;draft.custom_minimum_size.y=52;draft.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(draft)
	draft.text_submitted.connect(func(_text:String):send_message())
	send_button=_button(row,"Жіберу  ↵",send_message);send_button.custom_minimum_size=Vector2(130,52);UI.primary(send_button)
	purchase_confirm=ConfirmationDialog.new();purchase_confirm.title="Дүкен сатып алу";purchase_confirm.dialog_text="Бос дүкенді 1 000 000 ₸-ге сатып аласыз ба?\nСөрелер мен тауарлар бағаға кірмейді."
	purchase_confirm.ok_button_text="Сатып алу";purchase_confirm.cancel_button_text="Бас тарту";purchase_confirm.theme=UI.make(true);add_child(purchase_confirm)
	purchase_confirm.confirmed.connect(func():
		if active_id=="cashier_3" and game.story.purchase_shop():status.text="Дүкен енді сенікі! Жабдықтау келесі кезеңде ашылады."
		else:status.text="Сатып алу мүмкін емес. Қаражатыңды тексер."
		_update_job_button())
	_label(box,"Enter — жіберу · Үлгіні өзгертіп жазуға болады",13).add_theme_color_override("font_color",UI.MUTED)
func _context_phrase() -> void:
	var words:="Сәлеметсіз бе! Менің атым Натан."
	if active_id.begins_with("cashier_"):words="Сәлеметсіз бе! Мен жұмыс іздеп жүрмін."
	elif active_id.begins_with("resident_"):words="Сәлеметсіз бе! Тапсырысыңызды алып келдім."
	elif active_id.begins_with("salon_"):words="Сәлеметсіз бе! Салонға тапсырыс алып келдім."
	_quick_message(words)
func open_chat(id:String) -> void:
	if not profiles.has(id) or not actors.has(id):return
	if id=="cashier_3":profiles[id].greeting="Құтты болсын, Натан! Дүкен енді сенікі. Жабдықтауды кейін бастаймыз." if game.story.owns_shop else "Сәлеметсіз бе! Мына бос дүкенді сатамын. Бағасы — бір миллион теңге. Ішін көріп шығыңыз."
	active_id=id;actors[id].set_meta("in_dialogue",true);actors[id].play_motion("idle")
	_show_modal("chat");chat_name.text=profiles[id].name;chat_role.text=profiles[id].role
	phrase_button.text="Жұмыс туралы" if id.begins_with("cashier_") else ("Тапсырысты әкелдім" if id.begins_with("resident_") else "Сәлемдесу")
	draft.clear();status.text="";phrase_help.text="Тірек сөздер: сәлеметсіз бе · менің атым · рақмет"
	if id.begins_with("cashier_"):phrase_help.text="Тірек сөздер: жұмыс іздеймін · курьер · тапсырыс · еңбекақы"
	elif id.begins_with("resident_"):phrase_help.text="Тірек сөздер: тапсырысыңыз · алып келдім · алыңыз · сау болыңыз"
	elif id.begins_with("salon_"):phrase_help.text="Тірек сөздер: тапсырыс · алып келдім · сақын · рақмет"
	_draw_messages();_update_job_button();_make_portrait(actors[id]);draft.grab_focus()
	game.speech.expected="";practice_button.text="Қайталап айту"
	voice_status.text="Қазақша айт немесе мәтін жаз. Жібермес бұрын мәтінді тексер."
	game.speech.startup_attempts=0
	if not game.automated:game.speech.speak(str(profiles[id].greeting),id)
func _make_portrait(actor:Node3D) -> void:
	if is_instance_valid(portrait):portrait_holder.remove_child(portrait);portrait.queue_free()
	portrait=SubViewport.new();portrait.size=Vector2i(200,220);portrait.own_world_3d=true;portrait.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	portrait_holder.add_child(portrait)
	var world:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("284650")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("f0e8da");env.ambient_light_energy=.65;world.environment=env;portrait.add_child(world)
	var model:=Node3D.new();model.set_script(preload("res://citizen_visual.gd"));model.character_id=actor.character_id;model.outfit_variant=actor.outfit_variant;model.initial_motion="idle";portrait.add_child(model)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-25,160,0);light.light_energy=.7;portrait.add_child(light)
	var camera:=Camera3D.new();portrait.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.76
	camera.position=Vector3(0,1.5,-2);camera.look_at(Vector3(0,1.5,0));camera.current=true
func _message(who:String,words:String,own:bool=false) -> void:
	messages.push_color(UI.MUTED if own else UI.TEAL)
	messages.push_font(load("res://assets/fonts/NotoSans-SemiBold.ttf"));messages.add_text(who+"\n");messages.pop();messages.pop()
	messages.push_color(UI.INK);messages.add_text(words+"\n\n");messages.pop()
func _draw_messages() -> void:
	messages.clear();_message(str(profiles[active_id].name),str(profiles[active_id].greeting))
	for message in game.story.histories.get(active_id,[]):
		_message("Натан" if message.role=="user" else str(profiles[active_id].name),str(message.content),message.role=="user")
	if waiting and not pending_text.is_empty():_message("Натан · жіберілуде",pending_text,true)
func _update_job_button() -> void:
	var shop:int=profiles[active_id].shop
	job_button.visible=shop>=0
	job_button.disabled=false
	if shop<0:return
	if shop==4:
		if game.story.salon_phase<0:
			job_button.text="Салон тапсырысы · 900–1400 ₸"
		elif game.story.salon_phase==1:
			job_button.text="Зат: %s — BEREKE кассасынан алыңыз (E)"%game.story.salon_item
			job_button.disabled=true
		else:
			job_button.text="Зат қолыңда · «ANA BEAUTY» салонына апар"
			job_button.disabled=true
		return
	if shop==3:
		job_button.text="Бұл дүкен сенікі · жабдықтау кейін" if game.story.owns_shop else "Дүкен сатып алу · 1 000 000 ₸"
		job_button.disabled=game.story.owns_shop or game.story.money<game.story.SHOP_PRICE
		return
	if game.story.employer<0:
		if shop!=0:job_button.text="Жұмыс: BEREKE дүкеніндегі Ерлан";job_button.disabled=true
		elif game.story.histories.get(active_id,[]).is_empty():job_button.text="Алдымен Ерланмен қазақша сөйлес";job_button.disabled=true
		else:job_button.text="Курьер болып жұмысқа тұру"
	elif game.story.employer!=shop:job_button.text="Жұмыс орның: "+game.story.shop_name(game.story.employer);job_button.disabled=true
	elif game.story.pending_payment>0:job_button.text="Еңбекақыны алу · %d ₸ + 10 бонус"%game.story.pending_payment
	elif not game.story.work_open() and game.story.delivery_id.is_empty():job_button.text="Ауысым аяқталды · ертең 09:00";job_button.disabled=true
	elif game.story.delivery_id.is_empty():job_button.text="Тапсырыс алу · 700–1500 ₸"
	else:job_button.text="Тапсырыс қолыңда · мекенжай телефонда";job_button.disabled=true
func _job_action() -> void:
	if waiting or job_button.disabled:return
	var shop:int=profiles[active_id].shop
	if shop==4:
		if game.story.take_salon_order(4):status.text="Берілді! BEREKE дүкенінен %s алып, «ANA BEAUTY» салонына жеткіз."%game.story.salon_item
		else:status.text="Қазір салон тапсырысын қабылдау мүмкін емес."
		_update_job_button();return
	if shop==3:purchase_confirm.popup_centered(Vector2i(520,220));return
	if game.story.employer<0:
		if game.story.hire(shop):status.text="Жұмысқа қабылдандың! Алғашқы тапсырысты ал."
	elif game.story.pending_payment>0:
		if game.story.claim_payment(shop):status.text="Еңбекақы мен 10 бонус алдың. Рақмет!"
	elif game.story.collect(shop):status.text="Тапсырысты алдың: %d ₸. Мекенжай мен бағыт телефонда: F."%game.story.delivery_reward
	else:status.text="Қазір тапсырыс алу мүмкін емес."
	_update_job_button()
func _story_changed() -> void:
	refresh=0;selected_home=false
	if is_instance_valid(map_view):map_view.selected_home=false
	if modal=="chat":_update_job_button()
	if is_instance_valid(map_view):map_view.refresh=0

func api_key() -> String:
	var value:=OS.get_environment("ALEM_API_KEY").strip_edges()
	if not value.is_empty():return value
	var config:=ConfigFile.new()
	if config.load("user://llm.cfg")==OK:return str(config.get_value("alem","api_key","")).strip_edges()
	if config.load(preload("res://runtime_paths.gd").root_dir().path_join("config/llm.cfg"))==OK:return str(config.get_value("alem","api_key","")).strip_edges()
	return ""
func _quick_message(words:String) -> void:
	if waiting:return
	draft.text=words;draft.grab_focus();draft.caret_column=draft.text.length()
func send_message() -> void:
	if waiting or active_id.is_empty() or game.speech.recording:return
	var words:=draft.text.strip_edges()
	if words.is_empty():return
	game.speech.stop()
	var key:=api_key()
	if key.is_empty():status.text="Әңгімелесу үшін байланыс қажет. Карта қолжетімді.";return
	var packet:Array=[{"role":"system","content":str(profiles[active_id].system)+"\n"+game.story.context_text()}]
	var history:Array=game.story.histories.get(active_id,[])
	for message in history.slice(maxi(0,history.size()-12)):
		if message is Dictionary and message.get("role","") in ["user","assistant"]:packet.append({"role":message.role,"content":str(message.get("content","")).left(2000)})
	packet.append({"role":"user","content":words})
	request_serial+=1;var serial:=request_serial
	request=HTTPRequest.new();request.timeout=60;request.body_size_limit=131072;add_child(request)
	request.request_completed.connect(_reply.bind(serial,active_id,words))
	waiting=true;pending_text=words;request_started=Time.get_ticks_msec();draft.editable=false;job_button.disabled=true
	_refresh_voice_controls();_draw_messages()
	status.text=str(profiles[active_id].name)+" жауап жазып жатыр…"
	var error:=request.request(API_URL,["Authorization: Bearer "+key,"Content-Type: application/json"],HTTPClient.METHOD_POST,JSON.stringify({"model":"gemma4","messages":packet,"max_tokens":400}))
	if error!=OK:_request_failed("Байланыс орнатылмады. Қайталау үшін «Жіберу» батырмасын бас.")
func _reply(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray,serial:int,id:String,words:String) -> void:
	if serial!=request_serial or id!=active_id:return
	if result!=HTTPRequest.RESULT_SUCCESS:
		_request_failed(connection_error(result));return
	if code!=200:
		_request_failed("Қызмет бос емес. Сәл кейін қайталап көр." if code==429 or code>=500 else ("Alem кілті қабылданбады. API кілтін тексеру қажет." if code in [401,403] else "Сұрау қабылданбады (%d). Мәтін сақталды."%code));return
	var data=JSON.parse_string(body.get_string_from_utf8())
	var reply:=""
	if data is Dictionary and data.get("choices") is Array and not data.choices.is_empty():
		var first=data.choices[0]
		if first is Dictionary and first.get("message") is Dictionary and first.message.get("content") is String:reply=first.message.content.strip_edges().left(2500)
	if reply.is_empty():_request_failed("Жауап бос келді. Қайта жіберіп көр.");return
	var history:Array=game.story.histories.get(id,[])
	history.append({"role":"user","content":words});history.append({"role":"assistant","content":reply})
	while history.size()>24:history.pop_front()
	game.story.histories[id]=history;game.story.save();_finish_request()
	phrase_button.text="Жұмыс туралы" if id.begins_with("cashier_") else ("Тапсырысты әкелдім" if id.begins_with("resident_") else "Сәлемдесу")
	draft.clear();status.text="";phrase_help.text="Тірек сөздер: сәлеметсіз бе · менің атым · рақмет"
	if id.begins_with("cashier_"):phrase_help.text="Тірек сөздер: жұмыс іздеймін · курьер · тапсырыс · еңбекақы"
	elif id.begins_with("resident_"):phrase_help.text="Тірек сөздер: тапсырысыңыз · алып келдім · алыңыз · сау болыңыз"
	elif id.begins_with("salon_"):phrase_help.text="Тірек сөздер: тапсырыс · алып келдім · сақын · рақмет"
	_draw_messages();draft.grab_focus()
	if not game.automated:game.speech.speak(reply,id)
func _finish_request() -> void:
	waiting=false;pending_text="";draft.editable=true;_refresh_voice_controls()
	if is_instance_valid(request):request.queue_free();request=null
	if not active_id.is_empty():_update_job_button()
func _request_failed(message:String) -> void:
	_finish_request();_draw_messages();status.text=message;draft.grab_focus()
func _cancel_request() -> void:
	request_serial+=1
	if is_instance_valid(request):request.cancel_request()
	_finish_request()

func _home_route() -> void:
	selected_home=true;_phone_page("map")

func resident_profile(id:String,door:int,slot:int) -> Dictionary:
	if profiles.has(id):return profiles[id]
	var names:=["Гүлнар","Серік","Айша","Мұрат","Зере","Омар","Назым","Бауыржан","Салтанат","Ермек"]
	var index:=posmod(door*3+slot,names.size())
	var profile:Dictionary=profiles["citizen_%02d"%posmod(door+slot,32)].duplicate(true)
	profile.name=names[index];profile.role="Тапсырыс алушы" if slot==0 else "Үй тұрғыны"
	profile.shop=-1;profile.character="asel" if index%2==0 else "erlan";profile.outfit=posmod(door+slot,8)
	profile.greeting="Сәлеметсіз бе! Тапсырысымды алып келдіңіз бе?" if slot==0 else "Сәлем! Кіріңіз, сізді күтіп отырмыз."
	# Reuse the shared language rules, but never the source citizen's biography.
	profile.system=str(profile.system).get_slice("\n",0)+"\nАтың — "+str(profile.name)+". Сен "+game.story.address_for(door)+" мекенжайында тұрасың. "
	profile.system+="Сен тапсырыс алушысың. Натан сәлемдескенде жылы жауап бер. Азық-түлікті күтіп отырсың. E батырмасымен береді. Дүкенге қайтып, еңбекақысын алатынын еске сал. " if slot==0 else "Сен алушының үйіндегі екінші тұрғынсың. Тапсырысты сен емес, жанындағы алушы қабылдайды. "
	profile.system+="Мінезің: "+["сабырлы, қысқа сөйлейсің","ақжарқын, сұрақ қойғанды ұнатасың","ұқыпты, жаңа көршіге көмектесесің"][posmod(door+slot,3)]+"."
	profiles[id]=profile;return profile

func connection_error(result:int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_RESOLVE:return "Alem мекенжайы табылмады. Интернетті тексер. Мәтінің сақталды."
		HTTPRequest.RESULT_CANT_CONNECT,HTTPRequest.RESULT_CONNECTION_ERROR:return "Alem-ге қосылу мүмкін болмады. Интернетті тексеріп, қайта жібер."
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:return "Қауіпсіз байланыс орнатылмады. Жүйе уақытын және интернетті тексер."
		HTTPRequest.RESULT_TIMEOUT:return "Жауап күту уақыты аяқталды. Мәтінің сақталды — қайта жіберуге болады."
	return "Байланыс үзілді. Мәтінің сақталды — қайта жіберуге болады."

func _refresh_voice_controls() -> void:
	mic_button.text="Тоқтату" if game.speech.recording else "Микрофон"
	mic_button.disabled=game.speech.working or waiting
	listen_button.disabled=game.speech.working or game.speech.recording or waiting
	practice_button.disabled=game.speech.working or game.speech.recording or waiting
	# Writing is independent of speech synthesis. Sending cancels obsolete audio.
	send_button.disabled=waiting or game.speech.recording

func connect_speech() -> void:
	voice_toggle.button_pressed=game.speech.enabled
	voice_toggle.toggled.connect(game.speech.set_enabled)
	game.speech.feedback.connect(func(words:String):voice_status.text=words)
	game.speech.changed.connect(_refresh_voice_controls)
	game.speech.transcript.connect(func(words:String,details:Dictionary):
		if modal!="chat":return
		draft.text=words.left(500);draft.grab_focus();draft.caret_column=draft.text.length()
		voice_status.text="Мәтінді тексеріп, «Жіберу» бас. Қажет болса түзет."
		if details.has("practice"):
			voice_status.text="Үлгі: %s\nСөз сәйкестігі: %d%% · бұл айтылым бағасы емес.\nМәтінді тексеріп жібер немесе қайта айтып көр."%[str(details.practice.expected),int(details.practice.word_match)]
	)

func practice_phrase() -> void:
	if game.speech.recording or game.speech.working:return
	if not game.speech.expected.is_empty():
		game.speech.expected="";practice_button.text="Қайталап айту";voice_status.text="Еркін әңгіме. Қазақша айт немесе мәтін жаз.";return
	var words:=draft.text.strip_edges()
	if words.is_empty():words="Сәлеметсіз бе! Мен қазақ тілін үйреніп жүрмін."
	game.speech.expected=words.left(200);practice_button.text="Еркін әңгіме"
	voice_status.text="Қайтала: %s\nТыңдап ал да, «Микрофон» бас."%game.speech.expected
	game.speech.speak(game.speech.expected,active_id)
