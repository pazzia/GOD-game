"use strict";

const ART = {
  scene: "../assets/scene/canal.png",
  felix: "../assets/characters/felix-cutout.png",
  marfa: "../assets/characters/marfa-cutout.png",
  plum: "../assets/characters/plum-cutout.png",
  props: "../assets/props/prop-sheet.png"
};
const SCREENS = [
  {id:"menu",label:"01 · Меню",description:"Главное меню: тот же город, Феликс и Плюм. Одна главная команда начинает историю."},
  {id:"intro",label:"02 · Завязка",description:"Зачем помогать: мост сломан, Марфа не может попасть в свою пекарню. Атлас заранее назван источником чуда."},
  {id:"setup",label:"03 · Постановка",description:"Нажмите на ширму. Переставьте её и сложите верхнюю часть. Можно проверить взгляд Марфы и попробовать неверную постановку."},
  {id:"proof",label:"04 · Фокус",description:"Марфа видит камень и не видит поплавок. Это ещё постановка: закон изменится только отдельным действием Атласа."},
  {id:"law",label:"05 · Чудо",description:"Атлас закрепил наблюдаемый образ: каменные вещи не тонут. Плюм убрал поплавок, камень остался на воде."},
  {id:"crossing",label:"06 · Переход",description:"Настоящая проверка нового правила: Марфа и корзина проходят по камню к пекарне. Скрытого назначения маршрута нет."},
  {id:"success",label:"07 · Победа",description:"Победа наступает после перехода Марфы. Следующая задача прямо связана с последствием того же закона."},
  {id:"next",label:"08 · Дальше",description:"Каменный якорь тоже всплыл. Следующая задача продолжает действующее правило; первая глава не обрывается без объяснения."}
];
const frame = document.getElementById("game-frame");
const model = {screen:"menu",position:"side",folded:false,selected:false,placing:false,error:null,overlay:null,history:[],reducedMotion:window.matchMedia("(prefers-reduced-motion: reduce)").matches};
const icons = {
  settings:'<circle cx="12" cy="12" r="3"/><path d="m10 2-.7 3-2 .9L4.6 5 2 9l2.2 2v2L2 15l2.6 4 2.7-.9 2 .9.7 3h4l.7-3 2-.9 2.7.9 2.6-4-2.2-2v-2L22 9l-2.6-4-2.7.9-2-.9L14 2Z"/>',
  arrow:'<path d="M5 12h14m-5-5 5 5-5 5"/>',
  back:'<path d="M19 12H5m5-5-5 5 5 5"/>',
  pause:'<path d="M9 5v14M15 5v14"/>',
  play:'<path d="m8 5 11 7-11 7Z"/>',
  eye:'<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>',
  undo:'<path d="M7 7H3V3m0 4a9 9 0 1 1-1 10"/>',
  fold:'<path d="M5 18V7l7-3 7 3v11l-7-3Z M12 4v11 M5 9l7 4 7-4"/>',
  move:'<path d="M3 12h18M7 8l-4 4 4 4m10-8 4 4-4 4"/>',
  book:'<path d="M12 6C8 3 3 4 3 4v15s5-1 9 2c4-3 9-2 9-2V4s-5-1-9 2Zm0 0v15"/>',
  spark:'<path d="m12 2 2.5 7.5L22 12l-7.5 2.5L12 22l-2.5-7.5L2 12l7.5-2.5Z"/>',
  check:'<path d="m5 12 4 4L19 6"/>',
  close:'<path d="m6 6 12 12M18 6 6 18"/>',
  sound:'<path d="m10 4-5 4H2v8h3l5 4Zm5 4a6 6 0 0 1 0 8m4-12a12 12 0 0 1 0 16"/>',
  anchor:'<circle cx="12" cy="4" r="2"/><path d="M12 6v15M8 10h8M3 15v3c3 0 4 3 9 3s6-3 9-3v-3M1 17l2-2 2 2m14 0 2-2 2 2"/>'
};
function icon(name,extra=""){return `<svg viewBox="0 0 24 24" class="icon ${extra}" aria-hidden="true">${icons[name]||icons.spark}</svg>`;}
function button(label,action,{kind="",symbol="arrow",extra=""}={}){return `<button class="game-button ${kind}" data-action="${action}" ${extra}><span>${label}</span>${symbol?icon(symbol):""}</button>`;}
function round(label,action,symbol){return `<button class="round-control" aria-label="${label}" title="${label}" data-action="${action}">${icon(symbol)}</button>`;}
function image(src,className,style="",alt=""){return `<img class="${className}" style="${style}" src="${src}" alt="${alt}" draggable="false">`;}

function actor(name,x,feet,height,extra=""){
  const width = name === "plum" ? height*1.15 : name === "marfa" ? height*.88 : height*.83;
  return image(ART[name],`character actor-${name} ${extra}`,`left:${x-width/2}px;top:${feet-height}px;width:${width}px;height:${height}px`,name === "felix"?"Феликс":name === "marfa"?"Марфа":"Плюм");
}
function prop(name,x,y,width,height,extra=""){
  return `<div class="prop prop-${name} ${extra}" style="left:${x}px;top:${y}px;width:${width}px;height:${height}px" role="img" aria-label="${{stone:"Каменная ступень",float:"Оранжевый поплавок",screen:"Складная ширма",atlas:"Атлас"}[name]||name}">${propSvg(name)}</div>`;
}
// The original generated atlas is rendered through SVG viewports, without altering its pixels.
function propSvg(name){
  const folded=name==="screen-folded" || (name==="screen" && (model.folded || model.screen==="proof"));
  const rect={stone:[10,170,540,300],float:[550,180,550,310],screen:folded?[25,610,465,355]:[1108,0,428,535],atlas:[530,530,570,445],stamp:[1110,570,426,400]}[name] || [25,610,465,355];
  const clipId="clip-"+rect.join("-");
  return `<svg viewBox="${rect.join(" ")}" preserveAspectRatio="xMidYMid meet" aria-hidden="true"><defs><clipPath id="${clipId}"><rect x="${rect[0]}" y="${rect[1]}" width="${rect[2]}" height="${rect[3]}"/></clipPath></defs><image href="${ART.props}" width="1536" height="1024" clip-path="url(#${clipId})"/></svg>`;
}
function nextBoat(){return `<svg class="next-boat" viewBox="0 0 580 320" role="img" aria-label="Лодка дрейфует, каменный якорь плавает рядом"><defs><linearGradient id="boat-hull" x2="0" y2="1"><stop stop-color="#FFF2D8"/><stop offset="1" stop-color="#D9B68C"/></linearGradient></defs><ellipse cx="272" cy="246" rx="223" ry="35" fill="#0B7B8566"/><path d="M38 169Q171 151 401 174l47 24Q357 297 136 252Z" fill="url(#boat-hull)" stroke="#353753" stroke-width="6"/><path d="M44 169Q220 131 442 192l-42 30Q224 196 78 193Z" fill="#9D514B" stroke="#353753" stroke-width="5"/><path d="M82 170Q239 153 390 191" fill="none" stroke="#F28F77" stroke-width="14"/><path d="M132 166 160 111l168 9 34 56" fill="#252647" stroke="#353753" stroke-width="6"/><path d="m152 107 22-48 137 7 39 59Z" fill="#40B8B3" stroke="#353753" stroke-width="5"/><path d="m177 64-6 45m56-43-4 47m57-45 8 48" stroke="#FFF2D8" stroke-width="21"/><path d="M425 200Q481 161 509 213" fill="none" stroke="#88684B" stroke-width="6"/><g transform="translate(479 191) rotate(14)"><path d="M22 4v69M1 33h42M-12 62Q22 101 56 62M-12 62v18M56 62v18" fill="none" stroke="#6B7C8A" stroke-width="17" stroke-linecap="round"/><path d="M22 4v69M1 33h42" fill="none" stroke="#B6C2C7" stroke-width="6" stroke-linecap="round"/></g><path d="M25 269q40 9 81 0m350 12q48 9 80-4" fill="none" stroke="#FFF2D8" stroke-width="6" stroke-linecap="round" opacity=".7"/></svg>`;}

function scene(stage){
  const magical = ["law","crossing","success","next"].includes(stage);
  let marfaX=190,marfaFeet=440;
  if(stage === "crossing"){marfaX=790;marfaFeet=405;}
  if(stage === "success" || stage === "next"){marfaX=1240;marfaFeet=376;}
  const showScreen = ["setup","proof"].includes(stage);
  const screenFront = model.position === "front" || stage === "proof";
  const screenX = screenFront ? 610 : 480;
  const screenHeight = (model.folded || stage === "proof") ? 90 : 185;
  const screenY = screenFront ? 434-screenHeight : 495-screenHeight;
  return `${image(ART.scene,"scene-plate", "", "Город мастерских у канала, два причала и пекарня")}
    <div class="scene-light"></div><div class="scene-vignette"></div>
    ${magical?'<div class="miracle-aura" style="left:610px;top:300px;width:420px;height:250px"></div>':""}
    <svg class="scene-ropes" viewBox="0 0 1560 720" aria-hidden="true"><path d="M690 383Q794 423 898 383M690 426Q794 458 898 426" fill="none" stroke="#655B50" stroke-width="2.4" stroke-linecap="round"/></svg>
    ${!magical?prop("float",726,410,135,57):""}
    ${prop("stone",699,350,190,95,magical?"stone-magical":"")}
    ${prop("atlas",470,330,115,96,magical?"atlas-magical":"")}
    ${actor("felix",385,425,295)}
    ${actor("marfa",marfaX,marfaFeet,275)}
    ${actor("plum",stage==="law"?1220:magical?1015:495,stage==="law"?400:magical?338:228,100,"float")}
    ${magical?prop("float",976,345,153,60):""}
    ${showScreen?prop("screen",screenX,screenY,194,screenHeight):""}
    ${magical?'<div class="miracle-spark" style="left:738px;top:351px">✦</div><div class="miracle-spark" style="left:894px;top:398px;font-size:25px">✧</div>':""}
    ${stage === "next"?nextBoat():""}`;
}

function header({eyebrow="Первый переход",goal="Помогите Марфе перейти канал",eye=false}={}){
  return `<div class="scene-topline"><div class="location-medallion">01</div><div class="objective-ribbon"><span class="eyebrow">${eyebrow}</span><strong>${goal}</strong></div></div><div class="top-right">${eye?round("Взгляд Марфы","view","eye"):""}${round("Пауза","pause","pause")}</div>`;
}
function screenMenu(){return `${image(ART.scene,"scene-plate","","Солнечный город у канала")}<div class="menu-shade"></div><div class="hero-halo"></div>${actor("felix",1080,728,690)}${actor("plum",1390,309,205,"float")}<div class="scene-hud"><div class="menu-copy"><span class="eyebrow">СОЛНЕЧНЫЙ ТЕАТР НЕВОЗМОЖНОГО</span><h1 class="wordmark">ПОЧТИ<span class="second">Б<em>О</em>Г</span></h1><p class="menu-description">Сначала — маленький фокус.<br>Потом — совсем другой мир.</p>${button("Начать историю","start")}<div class="menu-footnote"><span>Феликс и Плюм</span><i></i><span>Первое приключение</span></div></div><div class="top-right">${round("Настройки","settings","settings")}</div><div class="menu-emblem">${icon("spark")} НЕВОЗМОЖНОЕ ВОЗМОЖНО</div></div>`;}
function screenIntro(){return `${scene("intro")}<div class="story-shade"></div><div class="scene-hud"><div class="story-copy"><span class="eyebrow">ГЛАВА I · ПЕРВЫЙ ПЕРЕХОД</span><h2>Утро начинается<br>с маленького чуда.</h2><p>Мост сломан. Марфа не может попасть в пекарню. Поплавок держит камень, но не выдержит человека.</p><p><strong>«Покажем невозможное — Атлас сделает его настоящим».</strong></p></div><div class="chapter-marker"></div><div class="chapter-sign"><span class="eyebrow">ТАМ ЖДУТ СВЕЖИЙ ХЛЕБ</span>Пекарня Марфы</div><div class="bottom-left">${round("Назад в меню","menu","back")}</div><div class="bottom-right">${button("Помочь Марфе","help-marfa")}</div></div>`;}
function screenSetup(){
  const screenFront=model.position === "front", screenX=screenFront?615:456;
  const screenHeight=model.folded?90:185, screenY=(screenFront?434:495)-screenHeight;
  let controls = model.selected ? `<div class="bottom-left">${button("Переставить","place",{kind:"secondary",symbol:"move"})}${button(model.folded?"Развернуть":"Сложить","fold",{kind:"secondary",symbol:"fold"})}</div>` : '<div class="bottom-left"><div class="caption-ribbon"><span class="eyebrow">ВАША ПОСТАНОВКА</span>Нажмите на ширму</div></div>';
  let target = `<button class="interaction screen-target" style="left:${screenX-9}px;top:${screenY-7}px;width:212px;height:${Math.max(screenHeight+18,110)}px" aria-label="Выбрать ширму" data-action="select-screen"><span class="interaction-label">Ширма</span></button>`;
  if(model.placing){
    target += `<button class="placement-target side" data-action="place-side"><span>Сбоку</span></button><button class="placement-target front" data-action="place-front"><span>Перед поплавком</span></button>`;
    controls = '<div class="bottom-left"><div class="caption-ribbon">Выберите место для ширмы</div></div>';
  }
  controls += `<button class="undo-control" data-action="undo" aria-label="Отменить последнее действие" ${model.history.length?"":"disabled"}>${icon("undo")}</button><button class="help-control" data-action="hint" aria-label="Подсказка">?</button>`;
  const error = model.error ? `<div class="speech setup-error" role="status"><span class="eyebrow">МАРФА</span>${model.error === "float" ? '«Я вижу поплавок.<br>Он и держит камень».' : '«Ширма закрыла всё.<br>Самого камня не видно».'}</div>` : "";
  return `${scene("setup")}<div class="scene-hud">${header({eye:true})}${target}${error}${controls}<div class="bottom-right">${button("Показать фокус","perform",{symbol:"play"})}</div></div>`;
}
function screenProof(){return `${scene("proof")}<div class="scene-hud">${header({eyebrow:"Фокус получился"})}<div class="speech" style="left:875px;top:170px;width:570px"><span class="eyebrow">МАРФА</span>«Камень вижу.<br>Что его держит — не вижу».</div><div class="bottom-left"><div class="caption-ribbon"><span class="eyebrow">ПОКА ЭТО ТОЛЬКО ФОКУС</span>Теперь слово за Атласом</div></div><div class="bottom-right">${button("Сделать законом","make-law",{symbol:"book"})}</div></div>`;}
function screenLaw(){return `${scene("law")}<svg class="law-trail" viewBox="0 0 1560 720" aria-hidden="true"><path d="M527 369C567 213 748 217 794 385" fill="none" stroke="#F7D760" stroke-width="8" stroke-linecap="round" stroke-dasharray="3 20"/><path d="M527 369C567 213 748 217 794 385" fill="none" stroke="#FFF2D8" stroke-width="2" opacity=".8"/></svg><div class="scene-hud">${header({eyebrow:"Новый закон",goal:"Каменные вещи не тонут"})}<div class="water-rule" style="left:849px;top:177px">${icon("spark")}Вода держит камень<br>вместе с грузом</div><div class="speech small" style="left:1010px;top:435px;width:470px"><span class="eyebrow">ПЛЮМ</span>«Поплавок убрал.<br>Камень держится!»</div><div class="bottom-left"><div class="caption-ribbon"><span class="eyebrow">ПРОВЕРИМ В ДЕЛЕ</span>Путь к пекарне открыт</div></div><div class="bottom-right">${button("Переправить Марфу","cross",{symbol:"arrow"})}</div></div>`;}
function screenCrossing(){return `${scene("crossing")}<div class="scene-hud">${header({eyebrow:"Настоящее чудо",goal:"Марфа идёт к пекарне"})}<div class="speech" style="left:1005px;top:160px;width:485px"><span class="eyebrow">МАРФА</span>«И меня держит.<br>И целую корзину!»</div><div class="bottom-left"><div class="caption-ribbon"><span class="eyebrow">ОДНО ПРАВИЛО ДЛЯ ВСЕХ КАМНЕЙ</span>Теперь это часть мира</div></div><div class="bottom-right"><div class="crossing-status">${icon("arrow")}Марфа переходит…</div></div></div>`;}
function screenSuccess(){return `${scene("success")}<div class="win-shade"></div><div class="win-copy"><span class="eyebrow">ПЕРВОЕ НАСТОЯЩЕЕ ЧУДО</span><h2>Марфа<br>у пекарни!</h2><p>Марфа добралась до своей двери.<br>Теперь можно открывать.</p><div class="win-lesson">${icon("book")}<span>В Атласе: каменные вещи<br>не тонут</span></div><span class="win-next">НО У ЧУДА ЕСТЬ ПРОДОЛЖЕНИЕ…</span>${button("К якорю","next-chapter",{symbol:"anchor"})}<br><button class="win-replay" data-action="replay">Вернуться к первому фокусу</button></div><div class="character-credit" style="left:1092px;top:435px;width:320px">Марфа у пекарни<small>Цель выполнена</small></div>`;}
function screenNext(){return `${scene("next")}<div class="story-shade"></div><div class="scene-hud"><div class="story-copy"><span class="eyebrow">СЛЕДУЮЩИЙ ФОКУС · ОБРАТНАЯ СТОРОНА ЧУДА</span><h2>Всплыл<br>даже якорь.</h2><p>Камень больше не тонет.<br>Теперь лодку уносит течением.</p><p><strong>Как удержать её у причала?</strong><br>Рядом верёвка и деревянный кнехт.</p></div><div class="bottom-left">${round("К победе первого уровня","success","back")}</div><div class="bottom-right">${button("Осмотреть причал","next-detail",{symbol:"eye"})}</div></div>`;}

function overlay(){
  if(!model.overlay)return "";
  if(model.overlay === "view"){
    const hideStone = model.position === "front" && !model.folded;
    const hideFloat = model.position === "front";
    return `<div class="overlay"><div class="view-panel"><div class="view-heading"><span><span class="eyebrow">ВИД СО СТОРОНЫ</span>Взгляд Марфы</span>${round("Вернуться к постановке","close-overlay","close")}</div><div class="marfa-view"><div class="view-water"></div>${!hideFloat?prop("float",310,200,270,110):""}${!hideStone?prop("stone",300,126,290,145):""}${model.position === "front"?prop("screen",260,model.folded?220:77,360,model.folded?125:290):prop("screen",45,model.folded?220:77,210,model.folded?125:290)}<div class="view-caption">${hideStone?"«За ширмой не видно камень».":hideFloat?"«Камень вижу. Что его держит — не вижу».":"«Камень стоит на поплавке»."}</div></div></div></div>`;
  }
  if(model.overlay === "hint")return `<div class="overlay"><div class="overlay-panel"><span class="eyebrow">ПЛЮМ ПОДСКАЗЫВАЕТ</span><h2>Проверьте вид со стороны.</h2><p>Атлас запишет то, что видно Марфе. Она должна видеть камень — но не его поддержку. У ширмы можно менять место и высоту.</p><div class="overlay-row">${button("Попробую","close-overlay",{symbol:"play"})}</div></div></div>`;
  if(model.overlay === "next-detail")return `<div class="overlay"><div class="overlay-panel"><span class="eyebrow">СЛЕДУЮЩИЙ ВОПРОС</span><h2>Поможет то,<br>что не изменилось.</h2><p>Каменные вещи не тонут. Верёвка и деревянный кнехт по-прежнему могут удержать лодку.</p><p>Здесь заканчивается показ первого уровня и его продолжения.</p><div class="overlay-row">${button("К началу истории","restart",{symbol:"back"})}</div></div></div>`;
  return `<div class="overlay"><div class="overlay-panel"><span class="eyebrow">МОЖНО НЕ СПЕШИТЬ</span><h2>${model.overlay === "settings"?"Настройки":"Пауза"}</h2><p>Ваша постановка останется на месте.<br>Ошибки можно исправлять без штрафа.</p><div class="overlay-toggle"><span>Уменьшить движение</span><button class="switch-hit" data-action="reduce-motion" role="switch" aria-checked="${model.reducedMotion}" aria-label="Уменьшить движение"><span class="switch ${model.reducedMotion?"":"off"}"></span></button></div><div class="overlay-row">${button("Продолжить","close-overlay",{symbol:"play"})}${button("В меню","menu",{kind:"secondary",symbol:"back"})}</div></div></div>`;
}
const renderers={menu:screenMenu,intro:screenIntro,setup:screenSetup,proof:screenProof,law:screenLaw,crossing:screenCrossing,success:screenSuccess,next:screenNext};
let crossingTimer;
function render(){
  clearTimeout(crossingTimer);
  frame.classList.toggle("reduced-motion",model.reducedMotion);
  frame.innerHTML=renderers[model.screen]()+overlay();
  frame.dataset.screen=model.screen;
  frame.dataset.placement=model.position;
  frame.dataset.folded=String(model.folded);
  frame.dataset.overlay=model.overlay||"";
  const current=SCREENS.findIndex(s=>s.id===model.screen);
  document.getElementById("preview-nav").innerHTML=SCREENS.map(s=>`<button data-screen="${s.id}" aria-current="${s.id===model.screen}">${s.label}</button>`).join("");
  document.getElementById("screen-description").textContent=SCREENS[current].description;
  document.getElementById("screen-position").textContent=`${current+1} / ${SCREENS.length}`;
  document.getElementById("previous-screen").disabled=current===0;
  document.getElementById("next-screen").disabled=current===SCREENS.length-1;
  const params=new URLSearchParams(location.search);params.set("screen",model.screen);history.replaceState(null,"",`${location.pathname}?${params.toString()}`);
  window.__mockState={...model};
  if(model.screen==="crossing" && !model.overlay && !new URLSearchParams(location.search).has("capture"))crossingTimer=setTimeout(()=>showScreen("success",{preset:false}),2200);
}
function showScreen(id,{preset=true}={}){
  if(!renderers[id])id="menu";
  model.screen=id;model.overlay=null;model.error=null;model.placing=false;model.selected=false;
  if(preset){model.history=[];model.position=["proof","law","crossing","success","next"].includes(id)?"front":"side";model.folded=["proof","law","crossing","success","next"].includes(id);}
  render();
}
function remember(){model.history.push({position:model.position,folded:model.folded});}
const actions={
  start:()=>showScreen("intro"),
  "help-marfa":()=>showScreen("setup"),
  menu:()=>showScreen("menu"),
  success:()=>showScreen("success"),
  replay:()=>showScreen("setup"),
  restart:()=>showScreen("menu"),
  "select-screen":()=>{model.selected=!model.selected;model.placing=false;render();},
  place:()=>{model.placing=!model.placing;model.error=null;render();},
  "place-side":()=>{if(model.position!=="side")remember();model.position="side";model.placing=false;model.error=null;render();},
  "place-front":()=>{if(model.position!=="front")remember();model.position="front";model.placing=false;model.error=null;render();},
  fold:()=>{remember();model.folded=!model.folded;model.error=null;render();},
  perform:()=>{model.placing=false;if(model.position!=="front"){model.error="float";model.selected=true;render();}else if(!model.folded){model.error="stone";model.selected=true;render();}else{showScreen("proof",{preset:false});}},
  "make-law":()=>showScreen("law",{preset:false}),
  cross:()=>showScreen("crossing",{preset:false}),
  arrive:()=>showScreen("success",{preset:false}),
  "next-chapter":()=>showScreen("next",{preset:false}),
  "next-detail":()=>{model.overlay="next-detail";render();},
  view:()=>{model.overlay="view";render();},
  hint:()=>{model.overlay="hint";render();},
  undo:()=>{const last=model.history.pop();if(last){model.position=last.position;model.folded=last.folded;}model.error=null;model.placing=false;model.selected=true;render();},
  pause:()=>{model.overlay="pause";render();},
  settings:()=>{model.overlay="settings";render();},
  "reduce-motion":()=>{model.reducedMotion=!model.reducedMotion;render();},
  "close-overlay":()=>{model.overlay=null;render();}
};
document.addEventListener("click",event=>{
  const target=event.target.closest("[data-action],[data-screen]");if(!target)return;
  if(target.dataset.screen)showScreen(target.dataset.screen);
  else if(actions[target.dataset.action])actions[target.dataset.action]();
});
document.getElementById("previous-screen").addEventListener("click",()=>showScreen(SCREENS[Math.max(0,SCREENS.findIndex(s=>s.id===model.screen)-1)].id));
document.getElementById("next-screen").addEventListener("click",()=>showScreen(SCREENS[Math.min(SCREENS.length-1,SCREENS.findIndex(s=>s.id===model.screen)+1)].id));
document.getElementById("restart-flow").addEventListener("click",()=>showScreen("menu"));
document.addEventListener("keydown",event=>{if(event.key==="Escape"){model.overlay=null;model.placing=false;render();}});
function resize(){const space=document.getElementById("frame-space");frame.style.transform=`scale(${space.clientWidth/1560})`;}
window.addEventListener("resize",resize);
new ResizeObserver(resize).observe(document.getElementById("frame-space"));
const params=new URLSearchParams(location.search);
if(params.has("capture"))document.body.classList.add("capture");
window.mockup={show:showScreen,state:model,render,screens:SCREENS};
showScreen(params.get("screen")||"menu");
if(params.get("position")==="front")model.position="front";
if(params.get("folded")==="true")model.folded=true;
if(params.has("overlay"))model.overlay=params.get("overlay");
render();
resize();
