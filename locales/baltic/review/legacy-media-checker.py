from pathlib import Path
from types import SimpleNamespace
import sys,tempfile,subprocess,os,json,hashlib
root=Path.cwd();sys.path.insert(0,str(root/'tests'));os.environ['MEMORY_CORE_DIR']='out/baltic-country-boot-core2/files'
import test_baltic_legacy_lifecycle_86box as main
import test_ru_legacy_keyboard_86box as helper
class StopBeforeLaunch(Exception):pass
original=subprocess.Popen
class PortCheck:
 def __enter__(self):return self
 def __exit__(self,*args):pass
 def setsockopt(self,*args):pass
 def bind(self,*args):pass
def popen(command,*args,**kwargs):
 if str(command[0]).endswith('/86Box'):raise StopBeforeLaunch()
 return original(command,*args,**kwargs)
helper.socket=SimpleNamespace(socket=PortCheck,SOL_SOCKET=1,SO_REUSEADDR=1)
subprocess.Popen=popen
work=Path(tempfile.mkdtemp(prefix='baltic-xt-capacity-',dir=root/'out'))
args=SimpleNamespace(machine='xt83',suite='lifecycle',emulator=root/'out/ru-86box-vnc-bs283qnk/build/src/86Box',roms=Path('/Users/ddanila/Library/Application Support/net.86box.86Box/roms'),qt_platform='offscreen')
records=[]
for name,initial,plan,files in main.plans(['resources'],['LV','LT'],None):
 for kind in ['bios','dos']:
  folder=work/(name+'-'+kind);folder.mkdir();country={'LV':371,'LT':370}[initial]
  locale={'page':775,'country':country,'country_probe':f'P{country}775.COM','selection':initial+',775,KEYBRD2.SYS','compile_probes':main.compile_probes,'steps':lambda kind:[{'keys':[],'bios_ax':0}],'extra_pages':[],'compact_batch':True,'lifecycle':main.prepare(plan,files)}
  try:helper.run_case(folder,args,helper.selected_core(),kind,locale)
  except StopBeforeLaunch:pass
  else:raise AssertionError('unexpected emulator launch')
  image=folder/kind/'test.img';data=image.read_bytes();assert len(data)==360*1024 and data[13]==1
  for filename,payload in files.items():assert subprocess.check_output(['mtype','-i',str(image),'::'+filename])==payload
  batch=subprocess.check_output(['mtype','-i',str(image),'::AUTOEXEC.BAT']);assert b'RU_LEGACY_KEY_DONE' in batch
  inventory=subprocess.check_output(['mdir','-i',str(image),'::'],text=True)
  records.append({'case':name,'input':kind,'private_image':str(image.relative_to(root)),'image_sha256':hashlib.sha256(data).hexdigest(),'all_mutations_present':len(files),'batch_bytes':len(batch),'allocation':inventory.splitlines()[-2:]})
r={'status':'capacity-passed-no-emulator-launched','cases':records};(root/'out/baltic-xt-compact-capacity.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))
