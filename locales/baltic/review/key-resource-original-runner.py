import hashlib,json,os,struct,sys,tempfile,shutil,subprocess
from pathlib import Path
root=Path.cwd();sys.path.insert(0,str(root/'tests'))
from test_baltic_country_qemu import run_case,command
from ru_profiles import verify_base,CONFIG,require_profile
work=Path(tempfile.mkdtemp(prefix='baltic-key-existing-',dir=root/'out'))
print(work,flush=True)
base=work/'base.img';shutil.copyfile(root/'out/baltic-pack-floppy.img',base)
command('mcopy','-o','-i',str(base),str(root/'src/CMD/KEYB/KEYB.COM'),'::KEYB.COM')
core=verify_base(base)
for name,source,flags in [('QEXIT','qemu_exit.asm',[]),('HIGH','ru_profile_probe.asm',['-DHIGH=1']),('LOW','ru_profile_probe.asm',['-DHIGH=0'])]:
 command('nasm','-f','bin',*flags,str(root/'tests'/source),'-o',str(work/(name+'.COM')))
data=(root/'src/DEV/KEYBOARD/KEYBOARD.SYS').read_bytes()
ids,langs=struct.unpack_from('<HH',data,24)
commands=[]
for index in range(ids+langs):
 entry=struct.unpack_from('<I',data,28+index*6+2)[0]
 code=data[28+index*6:30+index*6].decode() if index<langs else data[entry:entry+2].decode()
 if code=='XX':code='US'
 identifier=struct.unpack_from('<H',data,28+index*6)[0] if index>=langs else None
 for i in range(data[entry+9]):
  page,pointer=struct.unpack_from('<HI',data,entry+10+6*i)
  if pointer==0xffffffff:continue
  action=f'KEYB {code},{page},KEYBOARD.SYS'+(f' /ID:{identifier}' if identifier is not None else '')
  if action not in commands:commands.append(action)
report={'status':'running','core_sha256':core,'commands':commands,'cases':[]}
outputs={}
for version in ('before','after'):
 for profile in ('high','low'):
  folder=work/(version+'-'+profile);folder.mkdir();image=folder/'boot.img';shutil.copyfile(base,image)
  keyb=root/'out/baltic-key-resources-before.com' if version=='before' else root/'src/CMD/KEYB/KEYB.COM'
  command('mcopy','-o','-i',str(image),str(keyb),'::KEYB.COM')
  for probe in work.glob('*.COM'):
   command('mcopy','-o','-i',str(image),str(probe),'::'+probe.name)
  config='COUNTRY=372,775,COUNTRY.SYS\r\n'+CONFIG[profile]
  batch=['@ECHO OFF','CTTY AUX',profile.upper()+'.COM','IF ERRORLEVEL 1 GOTO FAIL','KEYB ET,775,KEYBRD2.SYS /ID:454','IF ERRORLEVEL 1 GOTO FAIL']
  for index,action in enumerate(commands):
   batch += [f'ECHO ORIGINAL_{index:03d}',action,'IF ERRORLEVEL 1 ECHO ORIGINAL_REJECTED','KEYB']
  batch += ['KEYB ET,775,KEYBRD2.SYS /ID:454','IF ERRORLEVEL 1 GOTO FAIL',profile.upper()+'.COM','IF ERRORLEVEL 1 GOTO FAIL','ECHO KEYB_ALL_DONE','QEXIT.COM',':FAIL','ECHO KEYB_ALL_FAIL','QEXIT.COM']
  for name,value in [('CONFIG.SYS',config),('AUTOEXEC.BAT','\r\n'.join(batch)+'\r\n')]:
   (folder/name).write_bytes(value.encode('ascii'))
   command('mcopy','-o','-i',str(image),str(folder/name),'::'+name)
  log=folder/'serial.log'
  with log.open('wb') as out:
   proc=subprocess.run(['qemu-system-i386','-display','none','-m','8','-drive',f'if=floppy,format=raw,file={image}','-boot','a','-serial','stdio','-monitor','none','-no-reboot','-device','isa-debug-exit,iobase=0xf4,iosize=0x04'],stdin=subprocess.DEVNULL,stdout=out,stderr=subprocess.STDOUT,timeout=60)
  output=log.read_bytes(); assert proc.returncode==33 and b'KEYB_ALL_DONE' in output and b'FAIL' not in output,(log,output)
  require_profile(output,profile)
  assert output.count(b'Current keyboard code:')==len(commands)
  if version=='after':assert output==outputs[profile],(log,'old/new output mismatch')
  else:outputs[profile]=output
  report['cases'].append({'version':version,'profile':profile,'emulator_exit':proc.returncode,'config':config,'actions':batch,'keyb_sha256':hashlib.sha256(keyb.read_bytes()).hexdigest(),'log':str(log),'log_sha256':hashlib.sha256(output).hexdigest()})
  (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
  print('PASS:',version,profile,flush=True)
report['status']='passed';(work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
