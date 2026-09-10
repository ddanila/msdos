"""Feed a valid CPI to the rejection gate; it must reject this false fixture."""
import sys,json
from pathlib import Path
sys.path.insert(0,str(Path.cwd()/'tests'))
import test_baltic_font_resources_qemu as gate
gate.mutations=lambda original: {'valid-control':original}
sys.argv=[__file__,'--language','et','--profile','low','--height','16']
original_run=gate.subprocess.run
exits=[]
def capture(*args,**kwargs):
 result=original_run(*args,**kwargs)
 if args and isinstance(args[0],list) and 'qemu' in Path(args[0][0]).name:
  exits.append(result.returncode)
 return result
gate.subprocess.run=capture
try:
 gate.main()
finally:
 Path('out/baltic-font-resources-control-exits.json').write_text(json.dumps({'qemu_exits':exits})+'\n')
