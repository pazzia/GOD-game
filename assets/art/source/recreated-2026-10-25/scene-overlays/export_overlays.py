"""Mechanical atlas slicing and placement of imagegen corner illustrations."""
from pathlib import Path
import json,hashlib,subprocess,shutil,csv
from PIL import Image
import numpy as np
R=Path(__file__).resolve().parents[5];W=R/'build/scene-overlay-export';S=Path(__file__).resolve().parent;W.mkdir(parents=True,exist_ok=True)
BATCHES=[
 ('ENV01','exec-7ccb141f-be78-4dc9-ab6f-9ce39e5126c4.png',[[24,84,339,457],[386,171,668,442],[734,167,1026,452],[1075,150,1419,457],[1442,257,1749,452],[22,564,342,846],[368,486,720,848],[736,561,1069,837],[1089,577,1411,848],[1442,476,1748,864]],['Камыши и три ромашки у первого причала','Билетные ленты с бархатцами','Папоротник и ракушка обходной тропы','Гнущиеся травы и декоративный ветроуказатель','Морской узел на кусочке плавника','Клевер, сено и колокольчик Карамельки','Плавник, листья кувшинок и стрекозы','Пара театральных кисточек','Записная книжка проверяющего с листом и пером','Праздничные речные ленты и цветы']),
 ('ENV02','exec-0e132223-b73b-4bf0-b31a-f9a635fa5b50.png',[[21,124,325,466],[345,177,692,476],[717,144,1069,454],[1088,150,1414,456],[1443,162,1763,467],[18,527,337,856],[354,523,705,848],[710,576,1044,838],[1053,567,1400,854],[1414,565,1762,856]],['Тимьян в горшке и медный половник','Ягоды на вышитом кухонном льне','Парные керамические дымники без огня','Сушилка шалфея с кремовым бантом','Прихватки, щипцы и розмарин','Медная трубка с каплями и папоротником','Две праздничные розетки','Морские салфетки, ракушка и мята','Пустая хлебная корзина с полотенцем','Праздничный поднос с цитрусами и ягодами']),
 ('ENV03','exec-cec4e943-a693-4220-bb88-ab35255c00f5.png',[[69,133,340,391],[431,135,665,384],[762,142,1016,385],[1114,114,1338,390],[1406,147,1691,388],[79,519,317,780],[398,539,665,770],[759,518,1023,782],[1122,520,1354,791],[1440,517,1704,795]],['Бумажные листья и писчие перья','Клевер и надкушенный декоративный лист','Книги и закрытый незажжённый фонарь','Лёгкие бумажные перья на золотом шнуре','Чистые свитки сертификатов с печатями','Три бумажных цветка в двух вазах','Гирлянда из складчатой бумаги','Печать, лента и дубовые листья','Театральная кисть Гуго со звездой','Финальный букет бумажных цветов трёх цветов'])]
localization=json.loads((R/'data/localization/ru.json').read_text());titles={f'L{n:02d}':localization[f'level.L{n:02d}.title'] for n in range(1,31)}
manifest={'schema_version':1,'kind':'decorative_level_overlays','canvas_size':[1536,1024],'authoring':'Original imagegen vignette atlases mechanically cropped and placed in peripheral corners. No gameplay geometry or occlusion changes.','acceptance_limits':'Distinct painted peripheral decoration delivered. Native before/after gameplay frames and phone readability remain separate acceptance.','entries':[]}
for b,(env,filename,boxes,descriptions) in enumerate(BATCHES):
 source=S/f'{env}-corner-vignettes.png';assert source.is_file(),source
 for c,(box,description) in enumerate(zip(boxes,descriptions)):
  num=b*10+c+1;level=f'L{num:02d}';target=R/f'assets/art/scenes/{level}/overlay.png';target.parent.mkdir(parents=True,exist_ok=True)
  l,t,r,bot=box;l=max(0,l-2);t=max(0,t-2);r+=2;bot+=2
  cut=W/f'{level}-cutout.png';subprocess.run(['magick',str(source),'-crop',f'{r-l}x{bot-t}+{l}+{t}','+repage','-filter','Lanczos','-resize','222x176','PNG32:'+str(cut)],check=True)
  corner='bottom_left' if num%2 else 'bottom_right';gravity='SouthWest' if num%2 else 'SouthEast'
  subprocess.run(['magick','-size','1536x1024','xc:none',str(cut),'-gravity',gravity,'-geometry','+8+8','-composite','PNG32:'+str(target)],check=True)
  with Image.open(target) as im:
   assert im.size==(1536,1024);alpha=np.array(im.getchannel('A'));bbox=im.getchannel('A').getbbox()
   assert not alpha[:,231:1305].any(),level+' central70percent must be transparent'
   assert not alpha[:840,:].any(),level+' must stay in bottom18percent'
   assert alpha.max()>100
  entry={'level_id':level,'level_title':titles.get(level),'environment_id':env,'file':f'res://assets/art/scenes/{level}/overlay.png','canvas_size':[1536,1024],'decoration':description,'placement':{'corner':corner,'max_size':[222,176],'margin':8,'alpha_bbox':list(bbox)},'source_atlas':str(source.relative_to(R)),'source_cell':c,'source_crop':[l,t,r,bot],'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'status':'new_generated_peripheral_decoration'}
  with Image.open(target) as im:entry['rgba_sha256']=hashlib.sha256(im.convert('RGBA').tobytes()).hexdigest()
  manifest['entries'].append(entry)
manifest['export_byte_stability']='PNG metadata contains ImageMagick creation timestamps. Reproduction checks RGBA pixels; shipped-byte SHA256 remains recorded separately.'
assert len(manifest['entries'])==30 and len({x['sha256'] for x in manifest['entries']})==30
(R/'assets/art/scenes/manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');(S/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'overlays':30,'unique_sha256':30,'canvas':'1536x1024','central70percent':'all transparent','peripheral_bounds':'all contained within bottom18percent and side15percent','manifest':str(R/'assets/art/scenes/manifest.json')},indent=2))
