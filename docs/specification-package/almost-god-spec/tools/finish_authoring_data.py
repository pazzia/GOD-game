"""Prepare specification fixtures and tables; this does not implement the game."""
from pathlib import Path
import csv
import json

ROOT = Path(__file__).resolve().parents[1]

def read_json(path):
    return json.loads((ROOT/path).read_text())

def write_json(path, data):
    target = ROOT/path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')

def read_csv(path):
    with (ROOT/path).open(newline='') as f:
        return list(csv.DictReader(f))

def write_csv(path, rows):
    with (ROOT/path).open('w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

def main():
    schema = read_json('schemas/level.schema.json')
    if 'zones' not in schema['required']:
        schema['required'].append('zones')
    schema['properties']['zones'] = {
        'type':'array','minItems':1,'items':{
            'type':'object','required':['id','kind'],'additionalProperties':False,
            'properties':{
                'id':{'type':'string'},'kind':{'enum':['REACH','WATER']},
                'polygon':{'type':'array','minItems':3,'items':{'type':'array','items':{'type':'integer'},'minItems':2,'maxItems':2}},
                'initial_phase':{'enum':['liquid','frozen']},
                'initial_thermal_charge':{'type':'integer','minimum':-30,'maximum':30}
            }
        }
    }
    routes = schema['properties']['navigation']['properties']['routes']['items']
    if 'required_support_slot' not in routes['required']:
        routes['required'].append('required_support_slot')
    routes['properties']['required_support_slot']={'type':'string'}
    write_json('schemas/level.schema.json',schema)

    for idx in range(1,4):
        name=f'L{idx:02d}'
        level=read_json(f'examples/{name}.json')
        level['zones']=[
            {'id':'near','kind':'REACH'},
            {'id':'demo_pool','kind':'WATER','polygon':[[10,8],[18,8],[18,16],[10,16]],'initial_phase':'liquid','initial_thermal_charge':0},
            {'id':'crossing_water','kind':'WATER','polygon':[[10,17],[14,17],[14,23],[10,23]],'initial_phase':'liquid','initial_thermal_charge':0}
        ]
        level['navigation']['routes'][0]['required_support_slot']='bridge'
        if idx in (2,3):
            for entity in level['entities']:
                if entity['id']=='stone':
                    entity['type_id']='stone_l'
                    entity['asset_id']='PROP_STONE_L'
                    entity['properties'].update({'size':'L','carry_capacity':5})
            for slot in level['slots']:
                slot['allowed_entity_types']=['stone_l' if value=='stone_m' else value for value in slot['allowed_entity_types']]
        if idx==3 and not any(x['id']=='cargo' for x in level['entities']):
            level['slots'].append({'id':'cargo_start','position':[7,21],'zone_id':'near','mount_layer':'ground','allowed_entity_types':['cargo_crate']})
            level['entities'].append({'id':'cargo','type_id':'cargo_crate','asset_id':'PROP_CARGO_CRATE','material':'WOOD','apparent_class':'CARGO','initial_slot':'cargo_start','movable':True,'mass_units':2,'properties':{}})
            level['goals'][0]={'id':'delivered','kind':'latched','predicate_id':'cargo_delivered','parameters':{'entity_id':'cargo','route_id':'cross'},'required':True}
            trace=read_json(f'examples/{name}_solution.json')
            for step in trace['steps']:
                if step.get('type')=='AssignRoute':
                    step['payload']['actor_id']='cargo'
            trace['expected_final_predicates']=['law_active:M01','entity_removed:float','cargo_delivered:cargo','level_success']
            write_json(f'examples/{name}_solution.json',trace)
        for entity in level['entities']:
            if entity['id']=='cargo':
                entity['properties'].update({'transport_mode':'carried','carrier_entity_id':'hero'})
        write_json(f'examples/{name}.json',level)

    laws=read_json('catalogs/laws.json')
    laws['observation_defaults'].update({'range_units':40,'field_of_view_degrees':100,'minimum_visible_result_samples':2,'result_sample_count':3})
    write_json('catalogs/laws.json',laws)
    bars=[
        [['D5',1],['F#5',1],['A5',1],['F#5',1]],
        [['E5',.5],['F#5',.5],['G5',1],['E5',1],['A4',1]],
        [['D5',1],['F#5',1],['A5',1],['B5',1]],
        [['A5',2],['F#5',1],['E5',1]],
        [['G5',1],['B5',1],['A5',1],['G5',1]],
        [['F#5',1],['E5',1],['D5',1],['A4',1]],
        [['E5',.5],['F#5',.5],['G5',1],['E5',1],['C#5',1]],
        [['D5',3],['REST',1]]]
    write_json('catalogs/music_composition_seed.json',{'status':'notation_seed_not_final_audio','key':'D major','meter':[4,4],'tempo_bpm':104,'bars':bars})

    assets=read_csv('ASSET_MANIFEST.csv')
    existing={a['asset_id'] for a in assets}
    def add(aid,category,stage,description,runtime,source,event=''):
        if aid in existing:
            return
        existing.add(aid)
        assets.append({'asset_id':aid,'category':category,'stage':stage,'description':description,'runtime_path':runtime,'source_path':source,'bus':'','loop':'False','duration_seconds':'','event_id':event,'status':'planned','rights':'to_document'})
    names=['садовник','почтальонка','рыбак','библиотекарь','торговец','музыкант']
    for idx,name in enumerate(names,1):
        aid=f'CROWD{idx:02d}'
        stage='S1' if idx<=2 else 'S2'
        add(aid+'_MODEL','crowd_model',stage,name+': отдельные голова, одежда, силуэт',f'assets/reference/{aid}.png',f'assets/source/crowd/{aid}.kra')
        add(aid+'_RIG','crowd_rig',stage,name+': согласованный общий риг',f'assets/runtime/crowd/{aid}/actor.tscn',f'assets/source/crowd/{aid}_rig.tscn')
        for clip in ['idle','move','observe','suspect','accept','clap']:
            add(aid+'_ANIM_'+clip.upper(),'crowd_animation',stage,name+': '+clip,f'assets/runtime/crowd/{aid}/{clip}.tres',f'assets/source/crowd/{aid}_rig.tscn',aid+'.'+clip)
    for aid,stage,desc in [
        ('LAW_WAVE','S1','Волна печати'),('BUOYANCY','S1','Рябь и всплытие'),('REVEAL','S1','Указание раскрытого механизма'),
        ('WITNESS_VOTE','S1','Понятный визуальный голос'),('SAFE_RECOVERY','S1','Безопасный возврат'),
        ('FREEZE','S2','Фронт замерзания'),('THAW','S2','Граница оттаивания'),('COLD_FIRE','S2','Холодное пламя'),
        ('PAPER_STRONG','S2','Прочная бумага'),('STEAM','S2','Пар с совпадающей логической маской'),('FINAL','S2','Финальный общий акцент')]:
        add('VFX_'+aid,'vfx',stage,desc,f'assets/runtime/vfx/{aid.lower()}.tscn',f'assets/source/vfx/{aid.lower()}.kra')
    add('KEYART_MAIN','key_art','S1','Законченная иллюстрация главного экрана','assets/runtime/ui/keyart.webp','assets/source/ui/keyart.kra')
    write_csv('ASSET_MANIFEST.csv',assets)

    req=read_csv('REQUIREMENTS.csv')
    tests=read_csv('ACCEPTANCE_TESTS.csv')
    backlog=read_csv('BACKLOG.csv')
    additions=[
        ('ART-05','S1','P0','WP12','Три законченные речные композиции','Сборка S1, L01–L03.','Сверить три композиции, все слои и маски.','Каждая задача имеет законченный вид, отдельный реквизит и правильное совпадение логики с рисунком.'),
        ('TOOL-01','S2','P1','WP33','Редактор авторских уровней','Данные уровня и финальная сцена.','Перенести слот/точку доказательства, проверить обзор, экспортировать и загрузить JSON.','Редактор воспроизводит изменения и эталонный trace, валидатор находит ошибочные ссылки.')]
    for rid,stage,priority,wp,text,pre,act,expected in additions:
        if any(r['requirement_id']==rid for r in req):
            continue
        tid=f'AT-{len(tests)+1:03d}'
        req.append({'requirement_id':rid,'stage':stage,'priority':priority,'work_package':wp,'requirement':text,'acceptance_id':tid,'source':'user_and_spec' if rid.startswith('ART') else 'spec_design_decision','status':'planned'})
        tests.append({'test_id':tid,'requirement_id':rid,'stage':stage,'preconditions':pre,'actions':act,'expected':expected,'status':'not_run','evidence':''})
    if not any(t['task_id']=='WP33' for t in backlog):
        backlog.append({'task_id':'WP33','stage':'S2','priority':'P1','task':'Редактор слотов, доказательств и повторов','dependencies':'WP02;WP04;WP16','requirements':'TOOL-01','status':'planned','acceptance':'Визуальный редактор, экспорт/импорт JSON, проверка обзора и проигрывание решений.','blocker':''})
    for task in backlog:
        task['requirements']=';'.join(r['requirement_id'] for r in req if r['work_package']==task['task_id'])
        if task['task_id']=='WP18' and 'WP33' not in task['dependencies'].split(';'):
            task['dependencies']+=';WP33'
    write_csv('REQUIREMENTS.csv',req)
    write_csv('ACCEPTANCE_TESTS.csv',tests)
    write_csv('BACKLOG.csv',backlog)

    md='# Сценарии приёмки\n\nНа дату ТЗ все игровые проверки имеют статус not_run. Это задания на испытания будущей игры. Структурная проверка документации отражается отдельно.\n'
    rmap={r['requirement_id']:r for r in req}
    for test in tests:
        r=rmap[test['requirement_id']]
        md+=f"\n### {test['test_id']} / {test['requirement_id']} — {r['requirement']}\n\nЭтап {test['stage']}. Предусловие: {test['preconditions']} Действия: {test['actions']} Ожидается: {test['expected']}\n"
    (ROOT/'07_ACCEPTANCE_SCENARIOS.md').write_text(md)

    first_three=[
        ['Spectators need to see the stone, not its support.','Hide the lower mechanism point, not the whole result.','Place the screen in the side slot, invite the audience and remove the float after sealing.'],
        ['One spectator can only see the ticket booth.','Compare the result visibility from the two side seats.','Move the obscured spectator to the right-side slot, or move the demonstration left.'],
        ['Semyon will not stay at his first position.','Check his second stop and the ray to the float.','Block the rear ray with the second screen, or move the demonstration behind the crate.']]
    loc=[]
    titles=['A Stone With Ambition','Front Row, Wrong View','How About the Back?','Wind Has Opinions','The Anchor Gets Promoted','Almost an Ark','A River Too Wide','Exactly Two Secrets','After the Applause','A Ferry on Good Faith','The Flame Takes a Break','Pastries With Personality','Two Stoves, One Boat','Cold Under Scrutiny','Not All Heat Is Fire','A Steamy Secret','A Second Seal','Boats Prefer Liquid','Give Fire Its Job Back','The Backwards Feast','A Sheet With Backbone','Not for Goats','The Fiery Archive','A Lightweight Solution','The Other Side of Approval','Two Slots, Three Miracles','Still Paper','A Certificate of Impossibility',"The Rival's Miracle",'The Square of Possibilities']
    levels=read_json('level_blueprints.json')['levels']
    for i,lvl in enumerate(levels):
        loc.append({'key':f"level.{lvl['id']}.title",'ru':lvl['title_ru'],'en':titles[i],'status':'editorial_review_required'})
        for hi,ru in enumerate(lvl['hints_ru']):
            loc.append({'key':f"level.{lvl['id']}.hint{hi+1}",'ru':ru,'en':first_three[i][hi] if i<3 else '', 'status':'editorial_review_required' if i<3 else 'en_translation_required'})
    for key,ru,en in [('play','Начать','Start'),('continue','Продолжить','Continue'),('settings','Настройки','Settings'),('music','Музыка','Music'),('sound','Звук','Sound'),('master','Общая громкость','Master volume'),('effects','Эффекты','Effects'),('ambience','Окружение','Ambience'),('voices','Голоса','Voices'),('interface','Интерфейс','Interface'),('mute_all','Выключить всё','Mute all'),('subtitles','Субтитры','Subtitles'),('motion','Уменьшить движение','Reduce motion'),('rehearse','Проверить','Rehearse'),('perform','Показать чудо','Perform'),('seal','Закрепить чудо','Seal the miracle'),('run_plan','Разыграть план','Run the plan'),('undo','Отменить ход','Undo'),('hint','Подсказка','Hint'),('restart','Начать заново','Restart'),('restore','Восстановить покупки','Restore purchases'),('cancel','Отмена','Cancel'),('apply','Применить','Apply'),('back','Назад','Back'),('proof_float_visible','Виден поплавок','The float is visible'),('proof_result_hidden','Не видно результат','The result is hidden'),('law_m01','Каменные вещи плавают','Stone objects float'),('law_m02','Огонь замораживает','Fire freezes'),('law_m03','Бумага прочнее стали','Paper is stronger than steel')]:
        loc.append({'key':'ui.'+key,'ru':ru,'en':en,'status':'editorial_review_required'})
    write_csv('LOCALIZATION_SEED.csv',loc)
    print(json.dumps({'levels':len(levels),'requirements':len(req),'tests':len(tests),'work_packages':len(backlog),'planned_assets':len(assets),'localization_rows':len(loc)},ensure_ascii=False))

if __name__=='__main__':
    main()
