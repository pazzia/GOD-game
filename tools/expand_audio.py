"""Original editable chamber score and procedural material/character audio.
No songs, recordings or voice imitations are sampled. Requires numpy/ffmpeg.
Output is authored audio awaiting listening/mix and device-interruption review.
"""
from pathlib import Path
import numpy as np
import json,math,subprocess,wave,hashlib,struct
from collections import Counter
R=Path(__file__).resolve().parents[1];OUT=R/'assets/audio/production';SOURCE=R/'assets/source/audio'
SR=48000;RNG=np.random.default_rng(94027);FILES=[]
PLAN=json.loads((R/'data/authoring/audio_plan.json').read_text())
BASE=[[74,78,81,78],[76,78,79,76],[74,78,81,83],[81,81,78,76],[79,83,81,79],[78,76,74,69],[76,78,79,73],[74,74,74,None]]
def tone(note,duration,kind='pluck',v=1):
 t=np.arange(max(1,round(duration*SR)))/SR;f=440*2**((note-69)/12);end=np.minimum((duration-t)/.12,1)
 if kind=='clarinet':
  p=2*np.pi*f*t+.025*np.sin(2*np.pi*4.7*t);s=np.sin(p)+.27*np.sin(3*p)+.09*np.sin(5*p);e=np.minimum(t/.065,1)*end*(.92+.08*np.sin(2*np.pi*2*t))
 elif kind=='strings':
  s=sum(np.sin(2*np.pi*f*(1+d)*t+p)/(i+1)**1.8 for i,(d,p)in enumerate(((0,0),(.0015,.5),(-.0017,1.3),(.0008,2))));e=np.minimum(t/.12,1)*end*.55
 elif kind=='celesta':s=np.sin(2*np.pi*f*t)+.3*np.sin(2*np.pi*f*2.01*t)+.09*np.sin(2*np.pi*f*4.02*t);e=np.minimum(t/.012,1)*np.exp(-t*4.5)*end
 elif kind=='bass':s=np.sin(2*np.pi*f*t)+.16*np.sin(4*np.pi*f*t);e=np.minimum(t/.012,1)*np.exp(-t*2.3)*end
 else:s=np.sin(2*np.pi*f*t)+.32*np.sin(4*np.pi*f*t)+.16*np.sin(6*np.pi*f*t);e=np.minimum(t/.003,1)*np.exp(-t*6)*end
 return(s*e*v*.11).astype(np.float32)
def add(buf,sound,start,pan=0):
 off=round(start*SR)%len(buf);s=sound[:,None]*np.array([math.sqrt((1-pan)/2),math.sqrt((1+pan)/2)],np.float32);n=min(len(s),len(buf)-off);buf[off:off+n]+=s[:n]
 if len(s)>n:buf[:len(s)-n]+=s[n:]
def save(aid,a,bus,loop=False,bpm=None,meter=None,stem=None):
 a=np.asarray(a,np.float32)
 if a.ndim==1:a=a[:,None]
 target=.08 if bus=='Music' else(.012 if bus=='Ambience' else(.065 if bus=='Voice' else .05))
 if stem=='bed':target=.065
 elif stem=='curiosity':target=.045
 elif stem=='tension':target=.018
 rms=float(np.sqrt(np.mean(a*a)))
 if rms>1e-7:a*=target/rms
 peak=float(np.max(np.abs(a)))
 if peak>.82:a*=.82/peak
 if not loop:
  n=min(len(a)//4,384);a[:n]*=np.linspace(0,1,n)[:,None];a[-n:]*=np.linspace(1,0,n)[:,None]
 p=OUT/(aid.lower()+('.ogg'if loop else'.wav'));temp=SOURCE/(aid.lower()+'.pending'+p.suffix);pcm=(np.clip(a,-1,1)*32767).astype('<i2')
 if p.suffix=='.ogg':subprocess.run(['ffmpeg','-v','error','-y','-f','s16le','-ar',str(SR),'-ac',str(a.shape[1]),'-i','pipe:0','-c:a','libvorbis','-q:a','5',str(temp)],input=pcm.tobytes(),check=True)
 else:
  with wave.open(str(temp),'wb')as f:f.setnchannels(a.shape[1]);f.setsampwidth(2);f.setframerate(SR);f.writeframes(pcm.tobytes())
 temp.replace(p)
 d=dict(id=aid,path='res://'+str(p.relative_to(R)),bus=bus,loop=loop,duration_seconds=round(len(a)/SR,6),sample_count=len(a),sample_rate=SR,channels=a.shape[1],peak_linear=round(float(np.max(np.abs(a))),6),rms_linear=round(float(np.sqrt(np.mean(a*a))),6),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),status='produced_mix_review_pending',source='tools/expand_audio.py',rights='Original synthesis, no external samples')
 if bpm:d.update(tempo_bpm=bpm,meter=meter,stem=stem)
 FILES.append(d)
def vl(n):
 a=[n&127];n>>=7
 while n:a.insert(0,(n&127)|128);n>>=7
 return bytes(a)
def midi(name,notes,bpm,meter):
 ev=[(0,b'\xff\x51\x03'+int(60000000/bpm).to_bytes(3,'big')),(0,b'\xff\x58\x04'+bytes([meter,2,24,8]))]
 for start,length,note,volume,ch in notes:ev.extend([(round(start*480),bytes([0x90+ch,note,volume])),(round((start+length)*480),bytes([0x80+ch,note,0]))])
 ev.sort(key=lambda x:(x[0],x[1][0]>>4));track=bytearray();prev=0
 for t,e in ev:track+=vl(t-prev)+e;prev=t
 track+=b'\x00\xff\x2f\x00';(SOURCE/(name.lower()+'.mid')).write_bytes(b'MThd'+struct.pack('>IHHH',6,0,1,480)+b'MTrk'+struct.pack('>I',len(track))+track)
def score():
 forms=[('MAIN',104,4,40,0),('RIVER',96,4,40,0),('KITCHEN',104,4,40,0),('ARCHIVE',100,3,60,-7),('ALBUM',90,4,30,0),('FINALE',104,4,40,0),('CREDITS',96,4,48,0)];source=[]
 for name,bpm,meter,bars,shift in forms:
  beat=60/bpm;n=round(bars*meter*beat*SR);stems={k:np.zeros((n,2),np.float32)for k in('bed','curiosity','tension')};notes=[];arr=[]
  for bar in range(bars):
   phrase=(bar//8)%5;part=bar%8;root=[50,45,47,42,43,50,45,50][part]+shift;chord=[root+12,root+12+(3 if name=='ARCHIVE'or part in(2,3)else 4),root+19]
   if name=='KITCHEN'and part==6:chord=[57,61,67]
   density=(.65 if phrase==0 else(1 if phrase in(1,3)else .8))*(.55 if bar>=bars-4 else 1)
   add(stems['bed'],tone(root,beat*1.7,'bass',.72*density),bar*meter*beat,-.12);notes.append((bar*meter,1.5,root,56,1))
   for p in range(meter):
    note=chord[(p+phrase)%3];add(stems['bed'],tone(note,beat*1.25,v=.52*density),(bar*meter+p+.08)*beat,-.35);notes.append((bar*meter+p+.08,1.1,note,48,2))
   if phrase in(2,3)and bar%2==0:
    for note in chord:add(stems['bed'],tone(note,beat*meter*1.1,'strings',.24),bar*meter*beat,.2)
   motif=list(BASE[(part+(2 if name=='KITCHEN'else 0))%8])
   if name=='ARCHIVE':motif=[v-7-(1 if v%12 in(1,6,11)else 0)if v else None for v in motif]
   if name=='KITCHEN':motif=[v-1 if v and v%12==1 else v for v in motif]
   if phrase==2:motif=list(reversed(motif))
   if phrase==3:motif=[v+12 if v and i%2 else v for i,v in enumerate(motif)]
   if phrase==4:motif=[motif[0],None,motif[2],None]
   if name=='ALBUM'and bar%2:motif=[motif[0],None,None,None]
   for p,note in enumerate(motif[:meter]):
    if note is None:continue
    kind='celesta'if phrase==2 or name=='ALBUM'else'clarinet';length=beat*(1.55 if p==meter-1 else .78);add(stems['curiosity'],tone(note,length,kind,.62*density),(bar*meter+p)*beat,.18);notes.append((bar*meter+p,length/beat,note,68,0))
   if bar%8 in(3,7)and bar<bars-4:
    for j,note in enumerate([83,81,78,76]):add(stems['curiosity'],tone(note,.18,'celesta',.38),(bar*meter+meter-1+j*.22)*beat,.45)
   for p in range(meter):
    t=np.arange(round(.09*SR))/SR;s=RNG.normal(0,.015,len(t))*np.exp(-t*65)+np.sin(2*np.pi*180*t)*np.exp(-t*48)*.035;add(stems['tension'],s.astype(np.float32),(bar*meter+p+.48)*beat,-.45)
    if name in('KITCHEN','FINALE')and p%2==0:add(stems['tension'],tone(chord[p%3]+12,beat*.35,v=.22),(bar*meter+p+.75)*beat,.4)
   arr.append(dict(bar=bar+1,phrase=phrase,root=root,chord=chord,melody=motif[:meter]))
  for k,a in stems.items():stems[k]=a+np.roll(a,round(.087*SR),axis=0)*.12+np.roll(a,round(.173*SR),axis=0)*.055
  if name in('MAIN','ALBUM','CREDITS'):save(f'MUS_{name}_FULL',stems['bed']+stems['curiosity']*.75+stems['tension']*(.08 if name=='ALBUM'else .3),'Music',True,bpm,[meter,4],'full')
  else:
   for stem,a in stems.items():save(f'MUS_{name}_{stem.upper()}',a,'Music',True,bpm,[meter,4],stem)
  midi(name,notes,bpm,meter);source.append(dict(id=name,bpm=bpm,meter=[meter,4],bars=bars,arrangement=arr));print('score '+name,flush=True)
 (SOURCE/'SCORE.json').write_text(json.dumps(dict(sample_rate=SR,tuning_hz=440,instruments=['pizzicato strings','odd-harmonic clarinet','celesta','warm bowed pad','wood percussion'],forms=source),ensure_ascii=False,indent=2)+'\n')
 for name,duration,notes in[('PROOF',1.5,[74,78,81]),('LAW',2.2,[74,78,81,86]),('REVEAL',.85,[76,75,73]),('CHAPTER',3.6,[74,78,81,83,81,86]),('FINAL',6.2,[74,78,81,83,86,85,86])]:
  a=np.zeros((round(duration*SR),2),np.float32)
  for i,note in enumerate(notes):
   start=i*(duration-.8)/max(1,len(notes)-1);add(a,tone(note,min(.9,duration/(len(notes)+1)*2),'celesta',.85),start,.1)
   if name in('LAW','CHAPTER','FINAL'):add(a,tone(note-12,min(1.3,duration/2),'strings',.5),start,-.2)
  save('MUS_STINGER_'+name,a,'Music')
def material(aid):
 n=round(SR*(.18 if 'UI_'in aid else .65));t=np.arange(n)/SR;noise=RNG.normal(0,1,n);decay=np.exp(-t*9);s=np.zeros(n)
 if any(k in aid for k in('PAPER','PAGE','CLOTH','SCREEN','RIBBON')):s=np.convolve(noise,np.ones(9)/9,'same')*np.sin(np.pi*np.minimum(t/.6,1))**2*.11+np.convolve(noise,np.ones(28)/28,'same')*.08*np.exp(-((t-.12)/.07)**2)
 elif any(k in aid for k in('WATER','BUOY','FLOAT','THAW','BOAT_MOVE','ANCHOR_UP')):
  s=np.convolve(noise,np.ones(32)/32,'same')*.15*decay
  for delay in(.04,.16,.29):x=np.maximum(0,t-delay);s+=np.sin(2*np.pi*(600*x-300*x*x))*np.exp(-x*24)*(t>=delay)*.045
 elif any(k in aid for k in('STONE','WEIGHT','FRAME','DOCK','STAMP')):
  for f,v,d in((131,.15,28),(353,.08,18),(713,.03,14),(1123,.015,12)):s+=np.sin(2*np.pi*f*t)*np.exp(-t*d)*v
  s+=noise*np.exp(-t*75)*.045
 elif any(k in aid for k in('FROST','ICE','FREEZE','BELL','CRYO','PLUM')):
  for f in(1174.66,1761.99,2349.32):s+=np.sin(2*np.pi*f*t)*np.exp(-t*7)*.035
  s+=np.convolve(noise,np.ones(5)/5,'same')*.025*decay
 elif any(k in aid for k in('FIRE','KETTLE')):s=np.convolve(noise,np.ones(20)/20,'same')*.12*np.sin(np.pi*np.minimum(t/.65,1))**2+noise*(np.sin(t*91)>.94)*.018
 elif 'ROPE'in aid:s=np.convolve(noise,np.ones(8)/8,'same')*.08*np.exp(-((t-.18)/.16)**2)+np.sin(2*np.pi*(140*t+16*t*t))*.035*decay
 else:s=(np.sin(2*np.pi*410*t)+.18*np.sin(2*np.pi*930*t))*decay*.05+noise*np.exp(-t*85)*.015
 return s.astype(np.float32)
def voice(aid):
 _,ch,emotion,take=aid.split('_');i=int(ch[2:])-1;f0=[168,510,218,142,365,198,192,242,155][i]*(1.045 if take=='B'else 1);dur=dict(CURIOUS=.62,DOUBT=.75,ACCEPT=.5,SURPRISE=.42,JOY=.86)[emotion];n=round(dur*SR);t=np.arange(n)/SR;u=t/dur
 contour=dict(CURIOUS=1+.18*u,DOUBT=1-.13*u,ACCEPT=1+.06*np.sin(np.pi*u),SURPRISE=1.3-.22*u,JOY=1+.12*np.sin(3*np.pi*u))[emotion];p=2*np.pi*np.cumsum(f0*contour*(1+.008*np.sin(2*np.pi*(9 if i==8 else 5)*t)))/SR;f1,f2,f3=[(550,1150,2450),(850,1900,3300),(650,1350,2550),(450,1050,2350),(800,1700,3100),(600,1450,2600),(530,1600,2750),(700,1250,2500),(520,1850,2900)][i];s=np.zeros(n)
 for h in range(1,24):a=sum(math.exp(-((f0*h-center)/width)**2)for center,width in((f1,180),(f2,260),(f3,400)))/h**.35;s+=np.sin(p*h)*a
 syllables=2 if emotion in('JOY','DOUBT')else 1;env=np.sin(np.pi*u)**.7*(.3+.7*np.maximum(0,np.sin(np.pi*u*syllables))**.6)
 return(s*env*.055+RNG.normal(0,.002,n)*env).astype(np.float32)
def effects():
 for row in PLAN:
  cat=row['category'];aid=row['asset_id']
  if cat=='sfx':save(aid,material(aid),row['bus']or'SFX')
  elif cat=='voice':save(aid,voice(aid),'Voice')
  elif cat=='ambience':
   n=SR*24;t=np.arange(n)/SR;noise=RNG.normal(0,1,n);width=120 if'WIND'in aid else(24 if'PAPER'in aid else 70);s=np.zeros(n)
   for off in range(width):s+=np.roll(noise,off)
   s=s/width*.07*(.8+.2*np.sin(2*np.pi*t/24))
   if'WATER'in aid:
    for delay in(2.1,7.4,11.8,18.9):a=tone(84,.15,'celesta',.12);p=round(delay*SR);s[p:p+len(a)]+=a
   save(aid,s.astype(np.float32),'Ambience',True)
def main():
 OUT.mkdir(parents=True,exist_ok=True);SOURCE.mkdir(parents=True,exist_ok=True);(R/'assets/source/.gdignore').touch();score();effects()
 events={}
 for row in PLAN:
  if row['event_id']:events.setdefault(row['event_id'],[]).append(row['asset_id'])
 themes={'main':['MUS_MAIN_FULL'],'ENV01':['MUS_RIVER_BED','MUS_RIVER_CURIOSITY','MUS_RIVER_TENSION'],'ENV02':['MUS_KITCHEN_BED','MUS_KITCHEN_CURIOSITY','MUS_KITCHEN_TENSION'],'ENV03':['MUS_ARCHIVE_BED','MUS_ARCHIVE_CURIOSITY','MUS_ARCHIVE_TENSION'],'finale':['MUS_FINALE_BED','MUS_FINALE_CURIOSITY','MUS_FINALE_TENSION'],'album':['MUS_ALBUM_FULL'],'credits':['MUS_CREDITS_FULL']}
 catalog=dict(schema_version=1,status='produced_mix_review_pending',files=FILES,events=events,themes=themes);(R/'data/audio_catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
 byid={r['id']:r for r in FILES};alias={'music_menu':'MUS_MAIN_FULL','music_river':'MUS_RIVER_BED','music_show':'MUS_RIVER_TENSION','music_kitchen':'MUS_KITCHEN_BED','music_archive':'MUS_ARCHIVE_BED','music_album':'MUS_ALBUM_FULL','music_finale':'MUS_FINALE_BED','music_credits':'MUS_CREDITS_FULL','river_ambience':'AMB_RIVER_WATER','tap':'SFX_UI_SELECT_A','place':'SFX_PROP_STONE_DRY_A','remove':'SFX_PROP_FLOAT_REMOVE_A','hint':'SFX_UI_HINT_A','undo':'SFX_UI_UNDO_A','reveal':'SFX_WITNESS_REVEAL_A','stamp':'SFX_LAW_STAMP_A','convinced':'SFX_WITNESS_ACCEPT_A','splash':'SFX_PROP_STONE_WATER_A','success':'MUS_STINGER_PROOF','stinger_proof':'MUS_STINGER_PROOF','stinger_law':'MUS_STINGER_LAW','stinger_reveal':'MUS_STINGER_REVEAL','stinger_chapter':'MUS_STINGER_CHAPTER','stinger_final':'MUS_STINGER_FINAL'}
 for i,name in enumerate(['felix','plum','marfa','semyon','nika','lada','roza','hugo','goat'],1):alias['voice_'+name]=f'VO_CH{i:02d}_ACCEPT_A'
 runtime={k:dict(path=byid[v]['path'],bus=byid[v]['bus'],loop=byid[v]['loop'])for k,v in alias.items()}
 for row in FILES:runtime[row['id']]=dict(path=row['path'],bus=row['bus'],loop=row['loop'])
 (OUT/'runtime_catalog.json').write_text(json.dumps(runtime,ensure_ascii=False,indent=2)+'\n')
 report=dict(files=len(FILES),buses=dict(Counter(r['bus']for r in FILES)),max_peak=max(r['peak_linear']for r in FILES),source='tools/expand_audio.py + SCORE.json + 7 MIDI files',review='Produced files/peak checks; listening, mastering and mobile interruptions remain separate acceptance.')
 (SOURCE/'PRODUCTION_REPORT.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report),flush=True)
if __name__=='__main__':main()
