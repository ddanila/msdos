from pathlib import Path
import subprocess,hashlib,json,tempfile
root=Path.cwd();work=Path(tempfile.mkdtemp(prefix='font-probe-parity-',dir=root/'out'))
old=work/'before.asm';old.write_bytes(subprocess.check_output(['git','show','d51fd53:tests/ru_font_probe.asm']))
checks=[]
for page in (775,866):
 for height in (8,14,16):
  for flags in ([],['-DHIDE_CURSOR'],['-DSETUP_ONLY'],['-DBOX86'],['-DBOX86','-DHIDE_CURSOR']):
   outputs=[]
   for i,src in enumerate((old,root/'tests/ru_font_probe.asm')):
    out=work/f'{i}.com'
    subprocess.run(['nasm','-f','bin','-I'+str(root/'tests')+'/',f'-DPAGE={page}',f'-DHEIGHT={height}',*flags,str(src),'-o',str(out)],check=True)
    outputs.append(out.read_bytes())
   assert outputs[0]==outputs[1]
   checks.append({'page':page,'height':height,'flags':flags,'sha256':hashlib.sha256(outputs[0]).hexdigest()})
Path('out/baltic-font-resources-probe-parity.json').write_text(json.dumps({'status':'passed','before_commit':'d51fd53','checks':checks},indent=2)+'\n')
print('Default QEMU/86Box probe binary parity passed.')
