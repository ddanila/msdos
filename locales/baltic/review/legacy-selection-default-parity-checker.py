from pathlib import Path
from types import SimpleNamespace
import sys,tempfile,subprocess
root=Path.cwd();sys.path.insert(0,str(root/'tests'))
import test_ru_legacy_keyboard_86box as legacy
from test_baltic_legacy_lifecycle_86box import plans,prepare,compile_probes
class Prepared(Exception):pass
class Boundary:
 def __enter__(self):return self
 def __exit__(self,*args):pass
 def setsockopt(self,*args):pass
 def bind(self,*args):raise Prepared()
legacy.socket.socket=lambda *args,**kwargs:Boundary()
work=Path(tempfile.mkdtemp(prefix='baltic-legacy-page-compat-',dir=root/'out'))
args=SimpleNamespace(machine='at84',suite='lifecycle',emulator=root/'out/ru-86box-vnc-bs283qnk/build/src/86Box',roms=Path('/unused'),qt_platform='offscreen')
for family,prior in [('ru',root/'out/ru-legacy-keyboard-gkdfyi0o/bios/test.img'),('baltic',root/'out/baltic-legacy-lifecycle-kg5bkb81/resources-et/bios/test.img')]:
 folder=work/family;folder.mkdir();locale=None
 if family=='baltic':
  args.machine='xt83';name,initial,plan,files=next(plans(['resources'],['ET'],None))
  locale={'page':775,'country':372,'country_probe':'P372775.COM','selection':'ET,775,KEYBRD2.SYS','compile_probes':compile_probes,'steps':lambda kind:[{'name':'unused','keys':[],'bios_ax':0}],'extra_pages':[],'compact_batch':True,'lifecycle':prepare(plan,files)}
 try:legacy.run_case(folder,args,legacy.selected_core(),'bios',locale)
 except Prepared:pass
 else:raise AssertionError('launch boundary not reached')
 image=folder/'bios/test.img';names=subprocess.check_output(['mdir','-b','-i',str(prior),'::'],text=True).splitlines()
 for path in names:
  name=path.rsplit('/',1)[-1]
  before=subprocess.check_output(['mtype','-i',str(prior),'::'+name]);after=subprocess.check_output(['mtype','-i',str(image),'::'+name])
  assert before==after,(family,name)
 print('PASS:',family,'all',len(names),'guest payloads including CONFIG/AUTOEXEC match the prior passed image byte for byte')
print('Private artifacts:',work)
