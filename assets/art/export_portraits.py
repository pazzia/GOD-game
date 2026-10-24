from pathlib import Path
from PIL import Image
from atlas_export import export,ROOT
STATES=['idle','observe','suspect','accept','reveal_react','focused','embarrassed','celebrate','extra']
def run(actor):
 src=ROOT/'source'/'bibles'/f'{actor}_expressions.png'
 im=Image.open(src);im.load();w,h=im.size
 export(src,{f'characters/portraits/{actor}/{s}.png':(int(i%3*w/3),int(i//3*h/3),int((i%3+1)*w/3),int((i//3+1)*h/3)) for i,s in enumerate(STATES)})
if __name__=='__main__':
 import sys
 for actor in sys.argv[1:]:run(actor)
