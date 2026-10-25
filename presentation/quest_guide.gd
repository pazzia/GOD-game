extends RefCounted
## Read-only presentation of the authoritative puzzle state. No commands or solutions.

static func _t(locale: String,ru: String,en: String) -> String:
	return en if locale=="en" else ru

static func _entity_name(kernel,id: String,catalog: Dictionary,locale: String) -> String:
	var entity: Dictionary=kernel._entities.get(id,{})
	var fallback: String=_t(locale,"Предмет","Object")
	return str(catalog.get("entity."+id+".name",catalog.get("prop."+str(entity.get("type_id",""))+".name",fallback)))

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
			return (_t(locale,"Заморозить: ","Freeze: ") if p.phase=="frozen" else _t(locale,"Сохранить жидкой: ","Keep liquid: "))+str(zones.get(p.zone_id,_t(locale,"вода","water")))
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
			label=_t(locale,"Путь: ","Route: ")+actor
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
			if "замораживает" in full or "Fire freezes" in full:label=_t(locale,"Огонь морозит","Freezing fire")
			elif "Бумага" in full or "Paper" in full:label=_t(locale,"Прочная бумага","Strong paper")
			else:label=_t(locale,"Камни плавают","Floating stones")
		return {"id":row.id,"label":label,"done":false}
	return {"id":"","label":_t(locale,"Цели выполнены","Goals complete") if phase=="SUCCESS" else _t(locale,"Цели готовы","Goals ready"),"done":true}

static func witness_status(kernel,id: String,locale: String) -> String:
	var w: Dictionary=kernel.state.witnesses[id]
	if w.get("exposed",false):return _t(locale,"Разгадал фокус","Secret exposed")
	if w.get("eligible_vote",false):return _t(locale,"Верит","Convinced")
	if str(w.get("status",""))=="MOVING_TO_VIEW":return _t(locale,"Меняет ракурс","Moving to view")
	var sight: Dictionary=kernel.visibility_for(id)
	if sight.method_visible:return _t(locale,"Видит секрет","Sees secret")
	if int(sight.visible_results)<2:return _t(locale,"Не видит результат","Cannot see result")
	if str(w.get("status",""))=="NO_MIRACLE":return _t(locale,"Ждёт чуда","No miracle yet")
	if kernel.state.phase in ["PERFORMANCE","REHEARSAL"]:return _t(locale,"Наблюдает","Watching")
	return _t(locale,"Обзор свободен","Clear view")

static func witness_short(kernel,id: String,locale: String) -> String:
	var full: String=witness_status(kernel,id,"en")
	var labels: Dictionary={"Secret exposed":_t(locale,"Разгадал","Exposed"),"Convinced":_t(locale,"Верит","Believes"),"Moving to view":_t(locale,"Идёт","Moving"),"Sees secret":_t(locale,"Секрет!","Secret!"),"Cannot see result":_t(locale,"Не видит","Blocked"),"No miracle yet":_t(locale,"Нет чуда","No magic"),"Watching":_t(locale,"Смотрит","Watching"),"Clear view":_t(locale,"Обзор ✓","View OK")}
	return str(labels.get(full,_t(locale,"Проверить","Inspect")))

static func describe(kernel,locale: String,level_number: int,total: int,selected: String="",catalog: Dictionary={}) -> Dictionary:
	var state: Dictionary=kernel.state
	var phase: String=str(state.get("phase","PLAN_SHOW"))
	var rows: Array=goal_rows(kernel,catalog,locale)
	var current_key: String="level."+str(state.get("level_id",""))+"."
	var objective: String=str(catalog.get(current_key+"objective",_t(locale,"Помогите жителям этой сцены.","Help the people in this scene.")))
	var data: Dictionary={"stage_number":1,"stage_title":_t(locale,"1 · Подготовка","1 · Prepare"),"body":"","objective":objective,"primary":_t(locale,"Показать фокус","Perform the trick"),"primary_disabled":false,"goals":rows,"witness_status":{},"witness_short":{},"law":""}
	data.goal_headline=goal_headline(rows,phase,locale)
	var laws: Array[String]=[]
	for law in state.get("active_laws",[]):laws.append(_law_name(law,catalog,locale))
	data.law=(_t(locale,"Законы сцены: ","Scene laws: ")+" · ".join(laws)) if not laws.is_empty() else _t(locale,"Мир пока обыкновенный","An ordinary world, for now")
	for id in state.get("witnesses",{}):
		data.witness_status[id]=witness_status(kernel,id,locale)
		data.witness_short[id]=witness_short(kernel,id,locale)
	data.body=_t(locale,"Поставьте реквизит. Нажмите на зрителя, чтобы проверить обзор.","Place your props. Tap a witness to check their view.")
	match phase:
		"PERFORMANCE","REHEARSAL":
			data.stage_number=2;data.stage_title=_t(locale,"2 · Показ","2 · Perform")
			data.primary=_t(locale,"К подготовке","Adjust trick")
			data.body=_t(locale,"Результат должен быть виден, секрет — скрыт. Нажмите на зрителя для проверки.","Keep the result visible and the secret hidden. Tap a witness to inspect.")
		"PROOF_ACCEPTED":
			data.stage_number=2;data.stage_title=_t(locale,"2 · Печать","2 · Seal")
			data.primary=_t(locale,"Закрепить чудо","Seal the miracle")
			data.body=_t(locale,"Фокус удался — это ещё не победа. Закрепите закон, затем выполните цели.","The trick worked — the quest is not finished. Seal the law, then complete the goals.")
		"LAW_SELECTION":
			data.stage_number=2;data.stage_title=_t(locale,"2 · Выбор","2 · Choose")
			data.primary=_t(locale,"Выбрать замену","Choose a replacement")
			data.body=_t(locale,"Можно сохранить два закона. Выберите замену и проверьте опоры.","Keep up to two laws. Choose a replacement and check the supports.")
		"PLAN_RESOLUTION":
			data.stage_number=3;data.stage_title=_t(locale,"3 · Решение","3 · Solve")
			data.primary=_t(locale,"Проверить решение","Run the plan")
			data.body=_resolution_help(kernel,rows,catalog,locale)
		"RUN_RESOLUTION":
			data.stage_number=3;data.stage_title=_t(locale,"3 · Проверка","3 · Check")
			var pending: bool=false
			var waiting: bool=false
			for task in state.get("routes",{}).values():
				pending=pending or not bool(task.get("completed",false))
				waiting=waiting or not str(task.get("waiting_for","")).is_empty()
			data.primary=_t(locale,"Выполняется…","In progress…") if pending else _t(locale,"Вернуться к плану","Back to the plan")
			data.primary_disabled=pending
			data.body=_t(locale,"Ждём изменения воды; все в безопасности. «Откат» отменит запуск бесплатно.","Waiting for the water; everyone is safe. Undo cancels the run for free.") if waiting else _t(locale,"План выполняется. Выполните все цели, чтобы открыть следующий уровень.","The plan is running. Complete every goal to unlock the next level.")
		"RECOVERABLE_FAILURE":
			data.stage_number=3;data.stage_title=_t(locale,"Новый план","Retry")
			data.primary=_t(locale,"Откатить","Undo")
			data.body=str(catalog.get("reason."+str(state.get("failure_reason","")),_t(locale,"План пока не сработал. Бесплатный откат вернёт состояние до запуска; подсказка объяснит, что проверить.","The plan did not work yet. Undo restores the state before the run for free; a hint explains what to check.")))
		"SUCCESS":
			data.stage_number=4;data.stage_title=_t(locale,"Готово!","Complete!")
			data.primary=_t(locale,"Начать уровень %d","Start level %d") % (level_number+1) if level_number<total else _t(locale,"Итоги путешествия","Journey complete")
			data.body=_t(locale,"Все обязательные цели выполнены. Следующая сцена — новое задание с собственными законами.","Every required goal is complete. The next scene brings a new quest and its own laws.") if level_number<total else _t(locale,"Вы помогли всем трём главам. Любой уровень можно повторить в альбоме.","You helped all three chapters. Replay any level from the album.")
	if not selected.is_empty() and (phase in ["PLAN_SHOW","PLAN_RESOLUTION"] or selected.begins_with("w:")):
		if selected.begins_with("w:"):
			var id: String=selected.trim_prefix("w:")
			var witness: Dictionary=kernel._find(kernel.definition.witnesses,id)
			var name: String=str(catalog.get("character."+str(witness.get("character_id",""))+".name",_t(locale,"Зритель","Witness")))
			var state_text: String=str(data.witness_status.get(id,""))
			var position_tip: String=_t(locale,"Свободное место меняет обзор.","A free seat changes the view.")
			if witness.get("views",[]).size()>1:position_tip=_t(locale,"Проверяет сцену с нескольких сторон.","Checks the stage from several sides.")
			if phase in ["PERFORMANCE","REHEARSAL"]:position_tip=_t(locale,"Для изменений вернитесь к подготовке.","Return to preparation to make changes.")
			data.body=name+" · "+state_text+". "+position_tip
		else:
			data.primary=_t(locale,"Действия предмета","Object actions")
			data.body=_entity_name(kernel,selected,catalog,locale)+_t(locale,": выберите место или откройте действия. Маршруты — в «Плане».",": choose a position or open actions. Routes are in Plan.")
	return data

static func _resolution_help(kernel,rows: Array,catalog: Dictionary,locale: String) -> String:
	var complete: bool=true
	for row in rows:
		if row.required and not row.done:complete=false
	if complete:return _t(locale,"Всё готово. Нажмите «Проверить решение», чтобы подтвердить результат.","Everything is ready. Run the plan to confirm the result.")
	var pending_routes: bool=false
	for task in kernel.state.get("routes",{}).values():pending_routes=pending_routes or not bool(task.get("completed",false))
	if pending_routes:return _t(locale,"Маршрут назначен. Проверьте опоры и груз, затем запустите решение.","Route assigned. Check supports and cargo, then run the plan.")
	for goal in kernel.definition.goals:
		if not goal.required or goal.predicate_id not in ["route_completed","cargo_delivered"]:continue
		var done: bool=bool(kernel.state.goals.get(goal.id,false)) or kernel.evaluate(goal.predicate_id,goal.parameters)
		if done:continue
		var id: String=str(goal.parameters.get("actor_id",goal.parameters.get("entity_id","")))
		return _t(locale,"Назначьте маршрут: «План» → «Маршруты» → ","Assign a route: Plan → Routes → ")+_entity_name(kernel,id,catalog,locale)+_t(locale,". Подготовьте путь.",". Prepare the path.")
	return _t(locale,"Подготовьте цели ниже. «Проверить решение» запустит время, тепло и движение.","Prepare the goals below. Run the plan starts time, heat and movement.")

static func briefing(kernel,locale: String,level_number: int,total: int,catalog: Dictionary) -> String:
	var key: String="level."+str(kernel.state.level_id)+"."
	var parts: Array[String]=[]
	parts.append(str(catalog.get(key+"intro","")))
	parts.append(_t(locale,"Ваша цель: ","Your goal: ")+str(catalog.get(key+"objective","")))
	if level_number<=3 and kernel.state.phase=="PLAN_SHOW":
		parts.append(_t(locale,"1. Подготовьте фокус: результат виден, секрет скрыт.\n2. Покажите его зрителям и закрепите печатью.\n3. Примените настоящий закон, чтобы выполнить цель уровня.","1. Prepare the trick: show the result, hide the secret.\n2. Perform for the audience and seal the miracle.\n3. Use the real law to complete the level's goal."))
		if level_number==1:parts.append(_t(locale,"Зрители поверили — это ещё не победа. После печати нужна настоящая переправа. Для движения: «План» → «Маршруты» → Феликс.","Convincing the audience is not the finish. After sealing the law, you still need a real crossing. To move: Plan → Routes → Felix."))
	else:
		var info: Dictionary=describe(kernel,locale,level_number,total,"",catalog)
		parts.append(_t(locale,"Сейчас: ","Current step: ")+str(info.stage_title)+"\n"+str(info.body))
	return "\n\n".join(parts)

static func victory(kernel,locale: String,level_number: int,total: int,catalog: Dictionary,next_title: String="") -> Dictionary:
	var key: String="level."+str(kernel.state.level_id)+"."
	var lines: Array[String]=[str(catalog.get(key+"success",_t(locale,"Вы помогли жителям этой сцены.","You helped the people in this scene.")))]
	for row in goal_rows(kernel,catalog,locale):
		if row.required:lines.append("✓ "+str(row.label))
	if level_number<total:
		lines.append(_t(locale,"Дальше — уровень %d: ","Next — level %d: ") % (level_number+1)+next_title)
		lines.append(_t(locale,"Новая сцена начнётся с новой задачи. Пройденное чудо сохранено в альбоме.","The new scene starts with a new quest. This completed miracle is saved in your album."))
	else:lines.append(_t(locale,"Все 30 уровней пройдены. В альбоме доступны повторные прохождения и другие решения.","All 30 levels are complete. Replay levels and explore other solutions from the album."))
	return {"title":_t(locale,"Уровень %d из %d пройден!","Level %d of %d complete!") % [level_number,total],"body":"\n\n".join(lines),"primary":_t(locale,"Начать уровень %d","Start level %d") % (level_number+1) if level_number<total else _t(locale,"Итоги путешествия","Journey complete")}
