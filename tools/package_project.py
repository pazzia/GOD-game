"""Package durable source checkpoints, without engine/SDK/cache binaries."""
from pathlib import Path
import zipfile
R=Path(__file__).resolve().parents[1]
OUT=R.parents[1]/'deliverables/Almost-God-Project.zip'
EXCLUDE={'.godot','.git','__pycache__','node_modules'}
OUT.parent.mkdir(parents=True,exist_ok=True)
staged=OUT.with_suffix('.zip.tmp')
with zipfile.ZipFile(staged,'w',zipfile.ZIP_DEFLATED,compresslevel=6)as z:
 for p in sorted(R.rglob('*')):
  if not p.is_file()or any(s in EXCLUDE for s in p.relative_to(R).parts):continue
  if p.suffix in('.tmp','.pyc','.apk','.idsig'):continue
  rel=p.relative_to(R)
  if (rel.parts[0]=='docs' or rel.parts[:2]==('data','authoring')) and (p.suffix=='.translation' or p.name.endswith('.csv.import')):continue
  z.write(p,'almost-god/'+str(p.relative_to(R)))
staged.replace(OUT)
print(str(OUT),OUT.stat().st_size)
