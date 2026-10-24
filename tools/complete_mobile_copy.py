"""Apply authored placement labels and introductory guidance to both locales.

The source is extra_translations.json; this one-time helper is idempotent.
"""
from pathlib import Path
import json, subprocess, sys
R=Path(__file__).resolve().parents[1]
SLOTS='''tray_stone|Камень в реквизите|Stone in the tray
tray_float|Поплавок в реквизите|Float in the tray
tray_screen_a|Ширма в реквизите|Screen in the tray
stage_stone|Камень на сцене|Stone on stage
stage_float|Под камнем на сцене|Beneath the stage stone
screen_left|Левый край сцены|Left side of the stage
bridge|На переправе|At the crossing
hero_start|Ближний причал|Near dock
audience_a|Место зрителя слева|Left audience seat
audience_b|Среднее место зрителя|Middle audience seat
audience_c|Место зрителя справа|Right audience seat
audience_bad|За билетной будкой|Behind the ticket booth
booth_slot|Место билетной будки|Ticket booth position
cargo_start|Площадка посылки|Parcel platform
tray_screen_b|Вторая ширма в реквизите|Second screen in the tray
screen_right|Правый край сцены|Right side of the stage
audience_1|Место зрителя слева|Left audience seat
audience_2|Среднее место зрителя|Middle audience seat
audience_3|Место зрителя справа|Right audience seat
stone_start|Камень в реквизите|Stone in the tray
float_start|Поплавок в реквизите|Float in the tray
screen_a_start|Ширма в реквизите|Screen in the tray
screen_blown|Открытое ветру место|Wind-exposed position
clamp_1_start|Первый зажим в реквизите|First clamp in the tray
clamp_2_start|Второй зажим в реквизите|Second clamp in the tray
screen_left_alt|Ширма ближе к сцене|Screen closer to the stage
boat_start|Место лодки|Boat berth
anchor_start|Каменный якорь у лодки|Stone anchor by the boat
bollard_start|Деревянный кнехт|Wooden bollard
mooring_start|Причальная верёвка|Mooring rope
goat_start|Карамелька на берегу|Caramel on the bank
small_stone_start|Маленький камень в реквизите|Small stone in the tray
small_bridge|Малая переправа|Small crossing
tow_rope_start|Буксирная верёвка|Tow rope
crate_1_start|Первый ящик на берегу|First crate on the bank
crate_2_start|Второй ящик на берегу|Second crate on the bank
stone_a_start|Первый камень в реквизите|First stone in the tray
stone_b_start|Второй камень в реквизите|Second stone in the tray
near_support|Ближняя опора|Near support
middle_support|Опора у острова|Island support
far_support|Дальняя опора|Far support
thread_start|Крепление страховочной нити|Safety thread attachment
thread_screen_start|Ширма для нити в реквизите|Thread screen in the tray
thread_screen_slot|Закрыть крепление нити|Hide the thread attachment
screen_b_start|Вторая ширма в реквизите|Second screen in the tray
oven_start|Жаровня у сцены|Brazier by the stage
oven_far|Жаровня вдали от воды|Brazier away from water
bowl_start|Чаша для показа|Demonstration bowl
flame_start|Бутафорское пламя|Stage flame
cold_pack_start|Криопак в реквизите|Cold pack in the tray
stage_cold|Криопак под чашей|Cold pack beneath the bowl
bread_start|Хлеб на прилавке|Bread on the counter
dessert_start|Десерт на прилавке|Dessert on the counter
box_start|Термокороб в реквизите|Insulated box in the tray
bread_box|Хлеб в термокоробе|Bread in the insulated box
bread_delivery|Хлеб для доставки|Bread for delivery
dessert_delivery|Десерт для доставки|Dessert for delivery
box_delivery|Короб для доставки|Box for delivery
food_oven_start|Печь у блюд|Oven by the dishes
delivery_start|Ящик доставки|Delivery crate
boat_oven_start|Жаровня у протоки|Brazier by the channel
boat_oven_far|Жаровня вдали от протоки|Brazier away from the channel
thermal_screen_start|Тепловой экран в реквизите|Heat screen in the tray
thermal_block|Перекрыть путь теплу|Block the thermal path
heated_stone_start|Тёплый камень в реквизите|Heated stone in the tray
warm_bowl|Тёплый камень у чаши|Heated stone by the bowl
permanent_screen_start|Постоянная ширма в реквизите|Permanent screen in the tray
permanent_screen_slot|Место постоянной ширмы|Permanent screen position
warm_boat|Тёплый камень у протоки|Heated stone by the channel
feast_start|Праздничная доставка|Feast delivery
anchor_a_start|Левый узел крепления|Left anchoring point
anchor_b_start|Правый узел крепления|Right anchoring point
paper_start|Бумага в реквизите|Paper in the tray
stage_paper|Бумажный пролёт|Paper span position
weight_start|Груз у тали|Load by the hoist
stage_weight|Груз на испытательном стенде|Load on the test stand
hoist_start|Место тали|Hoist position
frame_start|Тайная рама в реквизите|Hidden frame in the tray
stage_frame|Рама под пролётом|Frame beneath the span
gate_start|Деревянная калитка|Wooden gate
cold_screen_start|Экран для криопака в реквизите|Cold-pack screen in the tray
cold_screen_slot|Скрыть криопак|Hide the cold pack
test_weight_start|Испытательный груз у тали|Test load by the hoist
test_weight_stage|Испытательный груз на бумаге|Test load on the paper
first_cargo_start|Посылка для первой доставки|Parcel for the first delivery
flags_start|Место бумажных флажков|Paper flag position
anchor_a_water|Левая опора в воде|Left support in water
warm_sample|Тёплый камень у образца|Heated stone by the sample
stone_away|Убрать тёплый камень от образца|Move the heated stone away
screen_cold_start|Холодный экран в реквизите|Cold screen in the tray
screen_cold_slot|Скрыть холодный механизм|Hide the cold mechanism
screen_paper_start|Ширма для бумаги в реквизите|Paper screen in the tray
screen_paper_slot|Скрыть раму под бумагой|Hide the frame beneath paper'''
EXTRA={
'entity.screen_a.name':['Первая ширма','First screen'],
'entity.screen_b.name':['Вторая ширма','Second screen'],
'entity.thread_screen.name':['Ширма крепления','Attachment screen'],
'entity.screen_cold.name':['Ширма для холода','Cooling screen'],
'entity.screen_paper.name':['Ширма для бумаги','Paper screen'],
'entity.thermal_screen.name':['Тепловой экран','Heat screen'],
'entity.cold_screen.name':['Экран криопака','Cold-pack screen'],
'entity.clamp_1.name':['Первый зажим','First clamp'],
'entity.clamp_2.name':['Второй зажим','Second clamp'],
'entity.crate_1.name':['Первый ящик','First crate'],
'entity.crate_2.name':['Второй ящик','Second crate'],
'entity.stone_a.name':['Первый камень M','First stone M'],
'entity.stone_b.name':['Второй камень M','Second stone M'],
'entity.oven.name':['Сценическая жаровня','Stage brazier'],
'entity.boat_oven.name':['Жаровня у протоки','Channel brazier'],
'entity.food_oven.name':['Жаровня у блюд','Food brazier'],
'entity.anchor_a.name':['Левая опора','Left anchor'],
'entity.anchor_b.name':['Правая опора','Right anchor'],
'entity.weight.name':['Груз у тали','Hoist load'],
'entity.test_weight.name':['Пробный груз','Test load'],
'subtitle.curious':['заинтересованно мычит','hums curiously'],
'subtitle.accept':['одобрительно хмыкает','hums in approval'],
'subtitle.surprise':['удивлённо ахает','gasps in surprise'],
'subtitle.joy':['радостно восклицает','cheers happily'],
'subtitle.exposed':['недовольно ахает','gasps disapprovingly'],
'ui.level_load_error':['Эта сцена пока не открылась. Прогресс сохранён. Выберите другую сцену в альбоме.','This stage could not be opened. Your progress is safe. Choose another stage in the album.'],
'level.L01.plan_tip':['Камень — на поплавок. Секрет скройте ширмой.','Place the stone on a float. Screen the secret.'],
'level.L02.plan_tip':['Дайте каждому зрителю увидеть весь фокус.','Give every spectator a clear view of the trick.'],
'level.L03.plan_tip':['Скройте секрет спереди и со второй стороны.','Hide the secret from both inspection sides.'],
'level.L11.plan_tip':['Спрячьте криопак. Покажите замерзание воды.','Hide the cold pack. Let them see water freeze.'],
'level.L21.plan_tip':['Поставьте лист, раму и груз. Скройте раму.','Set up paper, frame and load. Hide the frame.'],
'level.L01.hint3':['Поставьте камень на поплавок, а ширму — на левый край сцены. Начните показ. Убирайте поплавок после печати.','Set the stone on the float and the screen on the left. Perform, seal, then remove the float.'],
'level.L02.hint3':['Пересадите зрителя из-за будки на свободное место справа. Затем повторите показ.','Move the spectator from behind the booth to the empty seat on the right, then perform again.'],
'level.L03.hint3':['Поставьте вторую ширму на правый край сцены: она должна скрыть поплавок со второго ракурса.','Place the second screen on the right side of the stage to hide the float from the second view.'],
'level.L21.hint3':['Поставьте бумагу на два узла, скройте раму и талью опустите испытательный груз на бумагу.','Mount the paper at both anchors, screen the frame and use the hoist to lower the test load onto the paper.'],
'ui.all_sound':['Весь звук','All audio'],
'ui.choose_on_stage':['Выбрать место на сцене','Choose a position on stage'],
'ui.hint_short':['Совет','Hint'],
'ui.method':['Механизм','Method'],
'ui.no_audience':['Закон уже действует. Соберите план и проверьте последствия.','The law is already active. Plan and test its consequences.'],
'ui.place':['Место','Position']}
def main():
 p=R/'data/authoring/extra_translations.json';d=json.loads(p.read_text())
 for line in SLOTS.splitlines():
  key,ru,en=line.split('|');d['slot.'+key+'.name']=[ru,en]
 d.update(EXTRA)
 for k,v in EXTRA.items():
  if k.endswith('.plan_tip'):assert all(len(x)<=50 for x in v),k
 p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
 subprocess.run([sys.executable,str(R/'tools/author_localization.py')],check=True)
if __name__=='__main__':main()
