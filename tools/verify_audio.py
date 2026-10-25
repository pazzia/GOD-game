"""Decode and measure authored audio. This is not a listening/device test."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import json,subprocess,hashlib,wave,math,sys
import numpy as np
R=Path(__file__).resolve().parents[1]
def parse_loudnorm_output(stderr):
 """Read a loudnorm JSON object without consuming FFmpeg's trailing log lines."""
 decoder=json.JSONDecoder()
 for index in reversed([i for i,char in enumerate(stderr) if char=='{']):
  try:stats,_=decoder.raw_decode(stderr[index:])
  except json.JSONDecodeError:continue
  if isinstance(stats,dict) and {'input_i','input_tp'}<=stats.keys():return stats
 raise ValueError('FFmpeg did not emit a complete loudnorm measurement')

def main():
 catalog=json.loads((R/'data/audio_catalog.json').read_text());rows=catalog['files'];errors=[]
 plan=json.loads((R/'data/authoring/audio_plan.json').read_text());byid={r['id']:r for r in rows}
 if set(byid)!={r['asset_id']for r in plan}:errors.append('Production catalog does not cover the exact planned audio IDs')
 for row in rows:
  p=R/row['path'].removeprefix('res://')
  if not p.exists():errors.append('Missing '+row['id']);continue
  if hashlib.sha256(p.read_bytes()).hexdigest()!=row['sha256']:errors.append('Digest mismatch '+row['id'])
  if p.suffix=='.wav':
   with wave.open(str(p),'rb')as f:
    if f.getnframes()!=row['sample_count']or f.getframerate()!=48000:errors.append('PCM length/rate '+row['id'])
 for name,theme in catalog['themes'].items():
  if len(theme)==3 and len({byid[k]['sample_count']for k in theme})!=1:errors.append('Unequal stem samples '+name)
 for name in ['main','river','kitchen','archive','album','finale','credits']:
  p=R/'assets/source/audio'/(name+'.mid')
  if not p.exists()or p.read_bytes()[:4]!=b'MThd':errors.append('MIDI source '+name)
 long=[row for row in rows if row['bus']in('Music','Ambience')]
 def measure(row):
  p=R/row['path'].removeprefix('res://')
  decoded=subprocess.run(['ffmpeg','-v','error','-i',str(p),'-ar','48000','-f','f32le','pipe:1'],capture_output=True,check=True)
  a=np.frombuffer(decoded.stdout,dtype='<f4').reshape(-1,row['channels'])
  seam=float(np.max(np.abs(a[0]-a[-1])))if row['loop']else None
  result=dict(id=row['id'],decoded_samples=len(a),expected_samples=row['sample_count'],peak_linear=float(np.max(np.abs(a))),loop_seam_sample_step=seam)
  if row['bus']=='Music':
   proc=subprocess.run(['ffmpeg','-hide_banner','-nostats','-i',str(p),'-af','loudnorm=I=-20:TP=-1.5:LRA=9:print_format=json','-f','null','-'],capture_output=True,text=True,check=True)
   stats=parse_loudnorm_output(proc.stderr);result.update(lufs_i=float(stats['input_i']),true_peak_db=float(stats['input_tp']))
  return result
 def measure_checked(row):
  try:return measure(row)
  except (OSError,ValueError,subprocess.CalledProcessError) as exc:
   return {'id':row['id'],'error':str(exc)}
 with ThreadPoolExecutor(max_workers=3)as pool:results=list(pool.map(measure_checked,long))
 measurements=[row for row in results if 'error' not in row]
 errors.extend('Measurement '+row['id']+': '+row['error'] for row in results if 'error' in row)
 for row in measurements:
  if abs(row['decoded_samples']-row['expected_samples'])>1:errors.append('Decoded length '+row['id'])
  if row.get('true_peak_db',-99)>-1:errors.append('True peak above -1dBTP '+row['id'])
  if row.get('loop_seam_sample_step')is not None and row['loop_seam_sample_step']>.04:errors.append('Loop sample discontinuity '+row['id'])
 full=[r for r in measurements if r['id'].endswith('_FULL')]
 advisories=[r['id']+' integrated loudness '+str(r['lufs_i'])+' LUFS (target -18..-22)'for r in full if not -22<=r['lufs_i']<=-18]
 report=dict(kind='audio_file_measurements',status='passed'if not errors else'failed',files=len(rows),music_runtime_files=15,stingers=5,voices=90,sfx_variants=106,ambiences=6,errors=errors,advisories=advisories,measurements=measurements,limits='No subjective listening, speaker/headphone, mobile interruption or 20-minute scene-mix acceptance.')
 out=R/'tests/reports';out.mkdir(parents=True,exist_ok=True);(out/'audio-files.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({k:v for k,v in report.items()if k!='measurements'},ensure_ascii=False,indent=2));return int(bool(errors))
if __name__=='__main__':sys.exit(main())
