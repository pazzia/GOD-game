extends RefCounted
## Read-only presentation of the authoritative puzzle state. No commands or solutions.

static func _t(locale: String,ru: String,en: String) -> String:
	return en if locale=="en" else ru

static func _entity_name(kernel,id: String,catalog: Dictionary,locale: String) -> String:
	var entity: Dictionary=kernel._entities.get(id,{})
	var fallback: String=_t(locale,"Предмет","Object")
	var level_key: String="level."+str(kernel.state.level_id)+".entity."+id+".name"
	return str(catalog.get(level_key,catalog.get("entity."+id+".name",catalog.get("prop."+str(entity.get("type_id",""))+".name",fallback))))

static func _slot_name(kernel,id: String,catalog: Dictionary,locale: String) -> String:
	var level_key: String="level."+str(kernel.state.level_id)+".slot."+id+".name"
	return str(catalog.get(level_key,catalog.get("slot."+id+".name",_t(locale,"нужное место","the required position"))))

static func _law_name(id: String,catalog: Dictionary,locale: String) -> String:
	var names: Dictionary={"M01":_t(locale,"Камни плавают","Stones float"),"M02":_t(locale,"Огонь замораживает","Fire freezes"),"M03":_t(locale,"Прочная бумага","Strong paper")}
	return str(catalog.get("law."+id+".name",names.get(id,_t(locale,"Новый закон","New law"))))

static func _route_name(id: String,catalog: Dictionary,locale: String) -> String:
	return str(catalog.get("route."+id+".name",_t(locale,"путь к цели","route to the goal")))

static func goal_label(kernel,goal: Dictionary,catalog: Dictionary,locale: String) -> String:
	var p: Dictionary=goal.parameters
	var entity: String=_entity_name(kernel,str(p.get("entity_id",p.get("actor_id",""))),catalog,locale)
	match str(goal.predicate_id):
		"route_completed":return _t(locale,"Провести: ","Guide: ")+entity+" → "+_route_name(p.route_id,catalog,locale)
		"cargo_delivered":return _t(locale,"Доставить: ","Deliver: ")+entity+" → "+_route_name(p.route_id,catalog,locale)
		"entity_removed":return _t(locale,"Убрать: ","Remove: ")+entity
		"entity_intact":return _t(locale,"Сохранить целым: ","Keep intact: ")+entity
		"support_valid":return _t(locale,"Устойчивая опора: ","Stable support: ")+entity
		"entity_state":
			if p.get("key","")=="moored":return _t(locale,"Закрепить у причала: ","Moor safely: ")+entity
			if p.get("key","")=="secured":return _t(locale,"Закрепить от ветра: ","Secure against wind: ")+entity
			return _t(locale,"Подготовить: ","Prepare: ")+entity
		"water_phase":
			var zones: Dictionary={"dessert_zone":_t(locale,"десерт","dessert"),"bowl_water":_t(locale,"вода в чаше","bowl water"),"crossing_water":_t(locale,"вода на переправе","crossing water"),"boat_water":_t(locale,"лодочная протока","boat channel"),"cold_passage":_t(locale,"холодный проход","cold passage")}
			var zone_key: String="level."+str(kernel.state.level_id)+".zone."+str(p.zone_id)
			var zone_name: String=str(catalog.get(zone_key,zones.get(p.zone_id,_t(locale,"вода","water"))))
			return (_t(locale,"Заморозить: ","Freeze: ") if p.phase=="frozen" else _t(locale,"Сохранить жидкой: ","Keep liquid: "))+zone_name
		"law_active":return _t(locale,"Действует закон: ","Law active: ")+_law_name(p.myth_id,catalog,locale)
		"law_inactive":return _t(locale,"Отменить закон: ","Revoke law: ")+_law_name(p.myth_id,catalog,locale)
	return _t(locale,"Выполнить условие задания","Complete the quest condition")

static func goal_rows(kernel,catalog: Dictionary,locale: String) -> Array:
	var rows: Array=[]
	for goal in kernel.definition.get("goals",[]):
		var done: bool=kernel.evaluate(goal.predicate_id,goal.parameters)
		if goal.kind=="latched":done=done or bool(kernel.state.get("goals",{}).get(goal.id,false))
		rows.append({"id":goal.id,"label":goal_label(kernel,goal,catalog,locale),"done":done,"required":bool(goal.required)})
	return rows

static func goal_headline(rows: Array,phase: String,locale: String) -> Dictionary:
	for row in rows:
		if not row.required or row.done:continue
		var full: String=str(row.label)
		var label: String=full
		if full.begins_with("Провести: ") or full.begins_with("Guide: "):
			var actor: String=full.trim_prefix("Провести: ").trim_prefix("Guide: ").split(" → ")[0]
			if actor in ["Марфа","Marfa"]:label=_t(locale,"Переправить Марфу","Help Marfa cross")
			elif actor in ["Профессор Феликс","Professor Felix","Феликс","Felix"]:label=_t(locale,"Провести профессора","Guide the professor")
			elif actor in ["Карамелька","Caramel"]:label=_t(locale,"Провести Карамельку","Guide Caramel")
			else:label=_t(locale,"Провести: ","Guide: ")+actor
		elif full.begins_with("Доставить: ") or full.begins_with("Deliver: "):
			label=_t(locale,"Доставить груз","Deliver cargo")
		elif full.begins_with("Убрать: ") or full.begins_with("Remove: "):
			label=_t(locale,"Убрать подпорку","Remove support")
		elif full.begins_with("Сохранить целым: ") or full.begins_with("Keep intact: "):
			label=_t(locale,"Сохранить целым","Keep intact")
		elif full.begins_with("Устойчивая опора: ") or full.begins_with("Stable support: "):
			label=_t(locale,"Надёжная опора","Stable support")
		elif full.begins_with("Закрепить от ветра: ") or full.begins_with("Secure against wind: "):
			label=_t(locale,"Закрепить ширму","Secure screen")
		elif full.begins_with("Закрепить у причала: ") or full.begins_with("Moor safely: "):
			label=_t(locale,"Закрепить лодку","Moor the boat")
		elif full.begins_with("Заморозить: ") or full.begins_with("Freeze: "):
			label=_t(locale,"Нужен лёд","Make ice")
		elif full.begins_with("Сохранить жидкой: ") or full.begins_with("Keep liquid: "):
			label=_t(locale,"Жидкая вода","Liquid water")
		elif full.begins_with("Отменить закон: ") or full.begins_with("Revoke law: "):
			label=_t(locale,"Отменить закон","Revoke the law")
		elif full.begins_with("Действует закон: ") or full.begins_with("Law active: "):
			if "Огонь" in full or "Fire" in full:label=_t(locale,"Огонь морозит","Freezing fire")
			elif "Бумага" in full or "Paper" in full:label=_t(locale,"Прочная бумага","Strong paper")
			else:label=_t(locale,"Камни плавают","Floating stones")
		return {"id":row.id,"label":label,"done":false}
	return {"id":"","label":_t(locale,"Цели выполнены","Goals complete") if phase=="SUCCESS" else _t(locale,"Цели готовы","Goals ready"),"done":true}

static func witness_status(kernel,id: String,locale: String) -> String:
	var w: Dictionary=kernel.state.witnesses[id]
	if w.get("exposed",false):return _t(locale,"Механизм был виден","Method was visible")
	if w.get("eligible_vote",false):return _t(locale,"Результат записан","Result recorded")
	if str(w.get("status",""))=="MOVING_TO_VIEW":return _t(locale,"Меняет ракурс","Moving to view")
	var sight: Dictionary=kernel.visibility_for(id)
	if sight.method_visible:return _t(locale,"Видит механизм","Sees method")
	if int(sight.visible_results)<2:return _t(locale,"Не видит результат","Cannot see result")
	if str(w.get("status",""))=="NO_MIRACLE":return _t(locale,"Нет изменения","No change yet")
	if kernel.state.phase in ["PERFORMANCE","REHEARSAL"]:return _t(locale,"Наблюдает","Watching")
	return _t(locale,"Обзор свободен","Clear view")

static func witness_short(kernel,id: String,locale: String) -> String:
	var w: Dictionary=kernel.state.witnesses[id]
	if w.get("exposed",false):return _t(locale,"Механизм виден","Method visible")
	if w.get("eligible_vote",false):return _t(locale,"Записано","Recorded")
	var sight: Dictionary=kernel.visibility_for(id)
	if sight.method_visible:return _t(locale,"Виден механизм","Method visible")
	if int(sight.visible_results)<2:return _t(locale,"Результат скрыт","Result hidden")
	if str(w.get("status",""))=="MOVING_TO_VIEW":return _t(locale,"Меняет ракурс","Changing view")
	return _t(locale,"Наблюдает","Observing") if kernel.state.phase in ["PERFORMANCE","REHEARSAL"] else _t(locale,"Обзор готов","View ready")

static func _required_experiment(kernel) -> String:
	# Guide decisions describe available phase actions; they never move equipment.
	var id: String=str(kernel.state.get("level_id",""))
	var required: Dictionary={"L17":"M02","L19":"M01","L20":"M02","L24":"M03","L28":"M03","L29":"M02"}
	if id=="L26" and kernel.evaluate("cargo_delivered",{"entity_id":"first_cargo","route_id":"dry_delivery"}):required[id]="M03"
	if id=="L29" and str(kernel.state.zones.get("demo_water",{}).get("phase","frozen"))!="liquid":return ""
	if id=="L30":
		if not kernel.evaluate("cargo_delivered",{"entity_id":"first_cargo","route_id":"cross"}):
			return "M01" if "M01" not in kernel.state.active_laws else ""
		if "M03" not in kernel.state.active_laws:
			if "M02" not in kernel.state.active_laws:return "M02"
			if str(kernel.state.zones.get("cold_passage",{}).get("phase","liquid"))!="frozen":return ""
			return "M03"
	var candidate: String=str(required.get(id,""))
	return candidate if not candidate.is_empty() and candidate not in kernel.state.active_laws else ""

static func hint_context(kernel) -> String:
	var phase: String=str(kernel.state.phase)
	if phase=="SUCCESS":return "success"
	if phase in ["PROOF_ACCEPTED","LAW_SELECTION"]:return "law"
	if phase=="RECOVERABLE_FAILURE":
		return "show" if str(kernel.state.get("failure_reason","")) in ["NO_CANDIDATE","NOT_ENOUGH_WITNESSES","METHOD_VISIBLE","RESULT_OBSCURED"] else "resolution"
	if phase in ["PLAN_RESOLUTION","RUN_RESOLUTION"]:
		return "resolution" if _required_experiment(kernel).is_empty() else "show"
	return "show"

static func hint(kernel,locale: String,index: int,catalog: Dictionary={}) -> Dictionary:
	var number: int=clampi(index,1,3)
	var context: String=hint_context(kernel)
	var key: String="level."+str(kernel.state.level_id)+"."
	var title_context: String=_t(locale,"опыт","demonstration")
	var body: String=""
	match context:
		"resolution":
			title_context=_t(locale,"применение закона","applying the law")
			var rows: Array=goal_rows(kernel,catalog,locale)
			var diagnostic: Dictionary=resolution_diagnostic(kernel,catalog,locale)
			if str(kernel.state.level_id)=="L03" and not bool(kernel.state.entities.get("float",{}).get("removed",false)):
				body=_t(locale,"Закон уже действует. Уберите поплавок через его действия, чтобы проверить новую опору.","The law is active. Remove the float through its actions to test the new support.")
			elif str(kernel.state.level_id)=="L03" and str(kernel.state.entities.get("stone",{}).get("slot",""))!="bridge":
				body=str(catalog.get(key+"resolution_hint%d"%number,_resolution_help(kernel,rows,catalog,locale)))
			elif number==1:
				body=_t(locale,"Закон уже действует. Текущая задача: ","The law is active. Current task: ")+str(goal_headline(rows,str(kernel.state.phase),locale).label)+"."
			elif not diagnostic.is_empty():body=str(diagnostic.body)
			else:body=_resolution_help(kernel,rows,catalog,locale)
		"law":
			title_context=_t(locale,"запись Атласа","Atlas record")
			body=_t(locale,"Опыт принят, но мир ещё не изменён. Нажмите «Сделать законом», затем выполните практическую задачу.","The demonstration is accepted, but the world has not changed. Choose ‘Make it a law’, then complete the practical task.")
			if str(kernel.state.phase)=="LAW_SELECTION":body=_t(locale,"Оба места Атласа заняты. Выберите закон для замены; сначала проверьте, от каких законов зависят ваши опоры.","Both Atlas slots are occupied. Choose a law to replace; first check which laws your supports depend on.")
		"success":
			title_context=_t(locale,"дальше","next step")
			body=_t(locale,"Задача завершена. Основная кнопка открывает следующий опыт; уже пройденные доступны в Атласе.","The task is complete. The main button opens the next experiment; completed stages remain in the Atlas.")
			if str(kernel.state.level_id)=="L30":body=_t(locale,"Путешествие завершено. В Атласе можно повторить опыты и найти другие решения.","The journey is complete. Replay experiments and discover other solutions in the Atlas.")
		_:
			body=str(catalog.get(key+"hint%d"%number,_t(locale,"Проверьте, виден ли результат и скрыт ли механизм из каждого ракурса.","Check that the result is visible and the method hidden from every view.")))
	var title: String=_t(locale,"Подсказка: %s · %d из 3","Hint: %s · %d of 3")%[title_context,number]
	return {"context":context,"title":title,"body":body,"index":number}

static func resolution_diagnostic(kernel,catalog: Dictionary,locale: String) -> Dictionary:
	# Inspect the same route requirements and cached support state as the kernel.
	# This function is read-only and never advances a route or selects a solution.
	var actors: Array=kernel.state.get("routes",{}).keys();actors.sort()
	var shared: Dictionary={}
	for actor_id in actors:
		var task: Dictionary=kernel.state.routes[actor_id]
		if bool(task.get("completed",false)):continue
		var route: Dictionary=kernel._find(kernel.definition.navigation.routes,str(task.route_id))
		for req in kernel._route_requirements(route):
			if str(req.type)=="support":
				var support_id: String=str(req.parameters.entity_id)
				shared[support_id]=int(shared.get(support_id,0))+int(kernel._task_mass(str(actor_id),task))
	var waiting: Dictionary={}
	for actor_id in actors:
		var task: Dictionary=kernel.state.routes[actor_id]
		if bool(task.get("completed",false)):continue
		var actor: String=_entity_name(kernel,str(actor_id),catalog,locale)
		var route: Dictionary=kernel._find(kernel.definition.navigation.routes,str(task.route_id))
		var text: String="";var detail: String="";var obstacle: String="";var reason: String=""
		for id in [str(actor_id),str(task.get("carrier_id",actor_id))]:
			if bool(kernel.state.entities[id].get("removed",false)):
				text=_t(locale,"%s убран; доставка не может начаться.","%s was removed; delivery cannot start.")%_entity_name(kernel,id,catalog,locale)
				obstacle=id;reason="ENTITY_REMOVED";break
		if text.is_empty():
			for req in kernel._route_requirements(route):
				var p: Dictionary=req.parameters
				if str(req.type)=="support":
					var support_id: String=str(p.entity_id)
					var support: Dictionary=kernel.state.entities[support_id]
					var support_name: String=_entity_name(kernel,support_id,catalog,locale)
					if bool(support.removed):
						text=_t(locale,"%s: опора «%s» убрана.","%s: the support ‘%s’ was removed.")%[actor,support_name]
					elif str(support.slot)!=str(p.slot_id):
						text=_t(locale,"%s: опора «%s» не на маршруте.","%s: support ‘%s’ is away from the route.")%[actor,support_name]
						detail=_t(locale,"Сейчас: %s. Нужное место: %s.","Current position: %s. Required position: %s.")%[_slot_name(kernel,str(support.slot),catalog,locale),_slot_name(kernel,str(p.slot_id),catalog,locale)]
					elif not bool(support.support):
						text=_t(locale,"%s: опора «%s» не удерживается.","%s: support ‘%s’ is not supported.")%[actor,support_name]
					if not text.is_empty():reason="MISSING_FLOATING_BRIDGE";obstacle=support_id;break
					var capacity: int=int(kernel._paper_capacity(support_id)) if str(p.kind)=="paper" else int(support.effective.get("carry_capacity",0))
					if int(shared.get(support_id,0))>capacity:
						text=_t(locale,"%s: опора перегружена (%d / %d).","%s: the support is overloaded (%d / %d).")%[actor,int(shared[support_id]),capacity]
						reason="OVER_CAPACITY";obstacle=support_id;break
				elif str(req.type)=="entity_state" and not kernel.evaluate("entity_state",p):
					var target: String=_entity_name(kernel,str(p.entity_id),catalog,locale)
					var state_text: String=_t(locale,"не подготовлен","is not ready")
					match str(p.get("key","")):
						"moored":state_text=_t(locale,"не закреплён у причала" if p.get("value",true) else "должен быть отвязан","is not securely moored" if p.get("value",true) else "must be unmoored")
						"open":state_text=_t(locale,"должен быть открыт" if p.get("value",true) else "должен быть закрыт","must be open" if p.get("value",true) else "must be closed")
						"closed":state_text=_t(locale,"должен быть закрыт" if p.get("value",true) else "должен быть открыт","must be closed" if p.get("value",true) else "must be open")
						"secured":state_text=_t(locale,"не закреплён от ветра" if p.get("value",true) else "должен быть освобождён от крепления","is not secured against the wind" if p.get("value",true) else "must be released from its attachment")
						"enabled":state_text=_t(locale,"должен быть включён" if p.get("value",true) else "должен быть выключен","must be enabled" if p.get("value",true) else "must be disabled")
					text=target+" "+state_text+".";reason="ROUTE_STATE_BLOCKED";obstacle=str(p.entity_id);break
				elif str(req.type)=="water_phase" and not kernel.evaluate("water_phase",p):
					var zone_key: String="level."+str(kernel.state.level_id)+".zone."+str(p.zone_id)
					var zone_name: String=str(catalog.get(zone_key,_t(locale,"вода на пути","the route water")))
					var phase_name: String=_t(locale,"замерзания","freezing") if str(p.phase)=="frozen" else _t(locale,"оттаивания","thawing")
					waiting={"short_body":_t(locale,"%s: ждём %s (%s).","%s: waiting for %s (%s).")%[actor,phase_name,zone_name],"body":_t(locale,"Движение ждёт изменения воды. Проверьте источник тепла и подготовленный план.","Movement is waiting for the water to change. Check the heat source and the prepared plan."),"entity_id":"","route_id":str(task.route_id),"reason":"WAITING_WATER_PHASE","waiting":true}
		if not text.is_empty():
			return {"short_body":text,"body":text+(" "+detail if not detail.is_empty() else ""),"entity_id":obstacle,"route_id":str(task.route_id),"reason":reason,"waiting":false}
	return waiting

static func _tutorial_step(kernel,selected: String,locale: String) -> String:
	var screen: Dictionary=kernel.state.entities.get("screen_a",{})
	if bool(screen.get("removed",false)):return _t(locale,"Отмените удаление, чтобы вернуть учебную ширму.","Undo the removal to recover the practice screen.")
	var slot: Dictionary=kernel._slots.get(str(screen.get("slot","")),{})
	if str(slot.get("mount_layer",""))=="tray":
		return _t(locale,"Коснитесь подсвеченного места, чтобы поставить ширму.","Tap a highlighted location to place the screen.") if selected=="screen_a" else _t(locale,"Откройте «Предметы» и возьмите учебную ширму.","Open ‘Objects’ and choose the practice screen.")
	if not bool(screen.get("folded",false)):return _t(locale,"Выберите ширму и сложите верх. Камень должен остаться виден.","Select the screen and fold its top. The stone must stay visible.")
	return _t(locale,"Проверьте обзор Марфы и проведите опыт.","Check Marfa’s view and demonstrate the effect.")

static func describe(kernel,locale: String,level_number: int,total: int,selected: String="",catalog: Dictionary={}) -> Dictionary:
	var state: Dictionary=kernel.state
	var phase: String=str(state.get("phase","PLAN_SHOW"))
	var rows: Array=goal_rows(kernel,catalog,locale)
	var current_key: String="level."+str(state.get("level_id",""))+"."
	var objective: String=str(catalog.get(current_key+"objective",_t(locale,"Помогите жителям этой площадки.","Help the people on this stage.")))
	var data: Dictionary={"stage_number":1,"stage_title":_t(locale,"1 · Подготовка","1 · Prepare"),"body":"","short_body":"","objective":objective,"primary":_t(locale,"Провести опыт","Demonstrate"),"primary_intent":"","primary_disabled":false,"goals":rows,"witness_status":{},"witness_short":{},"law":"","context_title":"","context_body":""}
	data.goal_headline=goal_headline(rows,phase,locale)
	var laws: Array[String]=[]
	for law in state.get("active_laws",[]):laws.append(_law_name(law,catalog,locale))
	data.law=(_t(locale,"Законы площадки: ","Stage laws: ")+" · ".join(laws)) if not laws.is_empty() else _t(locale,"Записей пока нет","No active records yet")
	for id in state.get("witnesses",{}):
		data.witness_status[id]=witness_status(kernel,id,locale)
		data.witness_short[id]=witness_short(kernel,id,locale)
	data.body=str(catalog.get(current_key+"plan_tip",_t(locale,"Результат должен быть виден, механизм — скрыт. Проверьте обзор из места наблюдателя.","The result must be visible and its method hidden. Check the observer’s view.")))
	data.short_body=str(catalog.get(current_key+"plan_tip",_t(locale,"Выберите предмет. Проверьте, что видно со стороны.","Select an object. Check the view from outside.")))
	if phase=="PLAN_SHOW" and str(state.level_id)=="L01":
		data.short_body=_tutorial_step(kernel,selected,locale)
		data.body=data.short_body+" "+_t(locale,"Марфа должна видеть камень, но не его опору.","Marfa must see the stone, but not its support.")
	match phase:
		"PERFORMANCE","REHEARSAL":
			data.stage_number=2;data.stage_title=_t(locale,"2 · Наблюдение","2 · Observe")
			data.primary=_t(locale,"Поправить опыт","Adjust the setup")
			data.body=_t(locale,"Атлас проверяет наблюдаемый результат и скрытый механизм. Личная вера и память наблюдателя не меняются.","The Atlas checks the observed result and hidden method. The observer’s belief and memory do not change.")
			data.short_body=_t(locale,"Результат виден, механизм скрыт. Дождитесь наблюдения.","Keep the result visible and method hidden. Wait for observation.")
		"PROOF_ACCEPTED":
			data.stage_number=2;data.stage_title=_t(locale,"2 · Запись Атласа","2 · Atlas record")
			data.primary=_t(locale,"Сделать законом","Make it a law")
			data.body=_t(locale,"Опыт получился — это ещё не победа. Сделайте результат законом, затем выполните практическую задачу.","The demonstration worked — the quest is not finished. Make the result a law, then complete the practical task.")
			data.short_body=_t(locale,"Пока это демонстрация. Атлас ещё не изменил мир.","This is a demonstration. The Atlas has not changed the world yet.")
		"LAW_SELECTION":
			data.stage_number=2;data.stage_title=_t(locale,"2 · Замена записи","2 · Replace a record")
			data.primary=_t(locale,"Выбрать замену","Choose a replacement")
			data.body=_t(locale,"В Атласе два активных места. Перед заменой проверьте, какие опоры и источники зависят от прежней записи.","The Atlas has two active slots. Before replacing a record, check which supports and sources depend on it.")
			data.short_body=_t(locale,"Два места заняты. Выберите, какой закон больше не нужен.","Both slots are full. Choose which law is no longer needed.")
		"PLAN_RESOLUTION":
			data.stage_number=3;data.stage_title=_t(locale,"3 · Применение","3 · Apply")
			data.primary=_t(locale,"Запустить план","Run the plan")
			data.body=str(catalog.get(current_key+"resolution_tip",""))+" "+_resolution_help(kernel,rows,catalog,locale)
			data.short_body=_resolution_short(kernel,rows,catalog,locale)
			var required: String=_required_experiment(kernel)
			if not required.is_empty():
				data.primary=_t(locale,"Провести опыт","Demonstrate")
				data.primary_intent="begin_required_experiment";data.required_experiment=required
				data.body=str(catalog.get(current_key+"plan_tip",data.body))+" "+_t(locale,"Подготовьте новый опыт. Закон запишется только после отдельного подтверждения Атласа.","Prepare the new demonstration. The law is recorded only after a separate Atlas confirmation.")
				data.short_body=_t(locale,"Подготовьте следующий опыт. Запись подтвердите отдельно.","Prepare the next demonstration. Confirm the record separately.")
			if str(state.get("level_id",""))=="L01":
				if not bool(state.entities.float.removed):
					data.primary=_t(locale,"Убрать поплавок","Remove the float");data.primary_intent="remove_l01_float"
					data.body=_t(locale,"Вода удерживает камень вместе с Марфой и корзиной. Уберите поплавок, чтобы проверить настоящий закон.","Water supports the stone with Marfa and her basket. Remove the float to test the real law.")
					data.short_body=_t(locale,"Закон записан. Теперь уберите поплавок.","The law is recorded. Remove the float now.")
				else:
					data.primary=_t(locale,"Переправить Марфу","Guide Marfa across");data.primary_intent="cross_l01_marfa"
					data.body=_t(locale,"Поплавок убран. Камень остаётся на воде и выдержит Марфу с корзиной. Пора пройти к пекарне.","The float is removed. The stone stays on the water and can carry Marfa with her basket. It is time to reach the bakery.")
					data.short_body=_t(locale,"Камень держится без подпорки. Переправьте Марфу.","The stone holds without support. Guide Marfa across.")
		"RUN_RESOLUTION":
			data.stage_number=3;data.stage_title=_t(locale,"3 · Проверка","3 · Check")
			var pending: bool=false
			var waiting: bool=false
			for task in state.get("routes",{}).values():
				pending=pending or not bool(task.get("completed",false))
				waiting=waiting or not str(task.get("waiting_for","")).is_empty()
			data.primary=_t(locale,"Выполняется…","In progress…") if pending else _t(locale,"Вернуться к плану","Back to the plan")
			data.primary_disabled=pending
			data.body=_t(locale,"Ждём изменения воды. Отмена бесплатно вернёт план перед запуском.","Waiting for the water to change. Undo restores the plan before this run for free.") if waiting else _t(locale,"План выполняется. Победа наступит после настоящей доставки и выполнения всех обязательных условий.","The plan is running. Victory follows the actual delivery and every required condition.")
			data.short_body=_t(locale,"Ждём изменения воды; путь пока не готов.","Waiting for the water; the route is not ready yet.") if waiting else _t(locale,"План выполняется. Дождитесь настоящего результата.","The plan is running. Wait for the actual result.")
			if waiting:
				var diagnostic: Dictionary=resolution_diagnostic(kernel,catalog,locale)
				if not diagnostic.is_empty() and bool(diagnostic.get("waiting",false)):
					data.short_body=str(diagnostic.short_body);data.body=str(diagnostic.body)
		"RECOVERABLE_FAILURE":
			data.stage_number=3;data.stage_title=_t(locale,"Поправим план","Adjust the plan")
			data.primary=_t(locale,"Отменить запуск","Undo the run")
			data.body=str(catalog.get("reason."+str(state.get("failure_reason","")),_t(locale,"План не сработал. Бесплатная отмена вернёт состояние перед запуском.","The plan did not work. Undo restores the state before the run for free.")))
			data.short_body=data.body
			if hint_context(kernel)=="show":
				data.stage_number=1;data.stage_title=_t(locale,"Поправим опыт","Adjust the demonstration")
				data.primary=_t(locale,"Вернуться к подготовке","Return to preparation")
			if hint_context(kernel)=="resolution":
				var diagnostic: Dictionary=resolution_diagnostic(kernel,catalog,locale)
				if not diagnostic.is_empty():
					data.body=str(diagnostic.body)
					data.short_body=str(diagnostic.short_body)
					data.blocking_entity_id=str(diagnostic.entity_id)
					data.blocking_route_id=str(diagnostic.route_id)
				if str(state.get("failure_reason",""))=="GOALS_INCOMPLETE":
					for row in rows:
						if row.required and not row.done:
							data.short_body=_t(locale,"Не выполнено: ","Not completed: ")+str(row.label)
							data.body=data.short_body+". "+_resolution_help(kernel,rows,catalog,locale);break
		"SUCCESS":
			data.stage_number=4;data.stage_title=_t(locale,"Задача решена!","Task complete!")
			data.primary=_t(locale,"Начать уровень %d","Start level %d") % (level_number+1) if level_number<total else _t(locale,"Итоги путешествия","Journey complete")
			data.body=str(catalog.get(current_key+"success",_t(locale,"Все обязательные условия выполнены.","Every required condition is complete.")))
			data.short_body=_t(locale,"Результат готов. В Атласе открыта следующая задача.","The result is complete. The next Atlas task is unlocked.") if level_number<total else _t(locale,"Все 30 задач решены. Атлас открыт для повторов.","All 30 tasks are complete. Replay them from the Atlas.")
	if not selected.is_empty():
		if selected.begins_with("w:"):
			var id: String=selected.trim_prefix("w:")
			var witness: Dictionary=kernel._find(kernel.definition.witnesses,id)
			data.context_title=str(catalog.get("character."+str(witness.get("character_id",""))+".name",_t(locale,"Наблюдатель","Observer")))
			data.context_body=str(data.witness_status.get(id,""))+". "+_t(locale,"Проверьте вид из этой точки.","Check the view from this position.")
		elif kernel._entities.has(selected):
			data.context_title=_entity_name(kernel,selected,catalog,locale)
			data.context_body=_t(locale,"Доступные действия показаны у предмета. Основная кнопка продолжает этап.","Available actions are beside the object. The main button continues the current stage.")
	return data

static func _resolution_short(kernel,rows: Array,catalog: Dictionary,locale: String) -> String:
	for goal in kernel.definition.goals:
		if not goal.required or kernel.evaluate(goal.predicate_id,goal.parameters):continue
		if goal.predicate_id=="entity_removed":
			return _t(locale,"Уберите лишнюю подпорку: ","Remove the spare support: ")+_entity_name(kernel,str(goal.parameters.entity_id),catalog,locale)+"."
		if goal.predicate_id=="entity_state":
			if goal.parameters.get("key","")=="moored":return _t(locale,"Закрепите лодку: выберите причальную верёвку.","Moor the boat: select the mooring rope.")
			if goal.parameters.get("key","")=="secured":return _t(locale,"Закрепите щит зажимами перед запуском.","Secure the screen with clamps before running the plan.")
	for task in kernel.state.get("routes",{}).values():
		if not bool(task.get("completed",false)):return _t(locale,"Путь назначен. Проверьте опоры и запустите план.","A route is assigned. Check the supports and run the plan.")
	for row in rows:
		if row.required and not row.done:
			for goal in kernel.definition.goals:
				if str(goal.id)!=str(row.id) or goal.predicate_id not in ["route_completed","cargo_delivered"]:continue
				var id: String=str(goal.parameters.get("actor_id",goal.parameters.get("entity_id","")))
				return _t(locale,"Выберите %s и назначьте маршрут.","Select %s and assign a route.")%_entity_name(kernel,id,catalog,locale)
			return _t(locale,"Текущая цель: ","Current goal: ")+str(row.label)
	return _t(locale,"Условия готовы. Запустите план для проверки.","The conditions are ready. Run the plan to check them.")

static func _resolution_help(kernel,rows: Array,catalog: Dictionary,locale: String) -> String:
	var complete: bool=true
	for row in rows:
		if row.required and not row.done:complete=false
	if complete:return _t(locale,"Всё готово. Запустите план, чтобы подтвердить результат.","Everything is ready. Run the plan to confirm the result.")
	for goal in kernel.definition.goals:
		if not goal.required or kernel.evaluate(goal.predicate_id,goal.parameters):continue
		if goal.predicate_id=="entity_removed":
			return _t(locale,"Сначала уберите лишнюю подпорку через её действия: ","First remove the spare support through its actions: ")+_entity_name(kernel,str(goal.parameters.entity_id),catalog,locale)+"."
		if goal.predicate_id=="entity_state":
			if goal.parameters.get("key","")=="moored":return _t(locale,"Сначала выберите швартовочный канат и закрепите лодку за деревянный кнехт.","First select the mooring rope and secure the boat to the wooden bollard.")
			if goal.parameters.get("key","")=="secured":return _t(locale,"Сначала закрепите ширму обоими зажимами.","First secure the screen with both clamps.")
	var pending_routes: bool=false
	for task in kernel.state.get("routes",{}).values():pending_routes=pending_routes or not bool(task.get("completed",false))
	if pending_routes:return _t(locale,"Маршрут назначен. Проверьте опоры и груз, затем запустите решение.","Route assigned. Check supports and cargo, then run the plan.")
	for goal in kernel.definition.goals:
		if not goal.required or goal.predicate_id not in ["route_completed","cargo_delivered"]:continue
		var done: bool=bool(kernel.state.goals.get(goal.id,false)) or kernel.evaluate(goal.predicate_id,goal.parameters)
		if done:continue
		var id: String=str(goal.parameters.get("actor_id",goal.parameters.get("entity_id","")))
		return _t(locale,"Выберите предмет и назначьте путь в его действиях: ","Select the object and assign a route through its actions: ")+_entity_name(kernel,id,catalog,locale)+_t(locale,". Подготовьте путь.",". Prepare the path.")
	return _t(locale,"Подготовьте условия задачи. Запуск плана включает время, тепло и движение.","Prepare the task conditions. Running the plan advances time, heat and movement.")

static func briefing(kernel,locale: String,level_number: int,total: int,catalog: Dictionary) -> String:
	var key: String="level."+str(kernel.state.level_id)+"."
	var parts: Array[String]=[str(catalog.get(key+"intro",""))]
	parts.append(_t(locale,"Ваша цель: ","Your goal: ")+str(catalog.get(key+"objective","")))
	if level_number==1:
		parts.append(_t(locale,"Камень и поплавок уже подготовлены. Меняйте только положение и форму ширмы. Марфа должна видеть камень и не видеть его опору.","The stone and float are ready. Change only the screen’s position and shape. Marfa must see the stone without seeing its support."))
		parts.append(_t(locale,"Удачный опыт ещё не меняет мир. Отдельная команда Атласа создаст закон; затем уберите поплавок и переправьте Марфу.","A successful demonstration does not change the world yet. A separate Atlas command creates the law; then remove the float and guide Marfa across."))
	else:
		parts.append(str(catalog.get("ui.atlas_scope",_t(locale,"Каждая площадка использует свою страницу Атласа.","Each stage uses its own Atlas page."))))
		var info: Dictionary=describe(kernel,locale,level_number,total,"",catalog)
		parts.append(_t(locale,"Сейчас: ","Current step: ")+str(info.stage_title)+"\n"+str(info.body))
	return "\n\n".join(parts)

static func victory(kernel,locale: String,level_number: int,total: int,catalog: Dictionary,next_title: String="") -> Dictionary:
	var key: String="level."+str(kernel.state.level_id)+"."
	var lines: Array[String]=[str(catalog.get(key+"success",_t(locale,"Вы помогли жителям этой площадки.","You helped the people on this stage.")))]
	for row in goal_rows(kernel,catalog,locale):
		if row.required:lines.append("✓ "+str(row.label))
	var next_story: String=str(catalog.get(key+"next_story",""))
	if level_number<total:
		if not next_story.is_empty():lines.append(next_story)
		lines.append(_t(locale,"Следующая задача %d: ","Next task %d: ") % (level_number+1)+next_title)
	else:lines.append(_t(locale,"Все 30 задач пройдены. В Атласе можно повторить опыты и найти другие решения.","All 30 tasks are complete. Replay experiments and find other solutions in the Atlas."))
	var title: String=str(catalog.get(key+"success_title",_t(locale,"Задача выполнена!","Task complete!")))
	var primary: String=_t(locale,"Начать уровень %d","Start level %d") % (level_number+1) if level_number<total else _t(locale,"Итоги путешествия","Journey complete")
	if level_number==1 and level_number<total:primary=_t(locale,"2 · К якорю","2 · To the anchor")
	return {"title":title,"body":"\n\n".join(lines),"primary":primary,"next_story":next_story}
