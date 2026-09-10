from pathlib import Path
import hashlib,json,os,shutil,subprocess,tempfile
root=Path.cwd();work=Path(tempfile.mkdtemp(prefix='baltic-repro-',dir=root/'out'))
commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
report={'status':'running','commit':commit,'runs':[],'tool_sha256':{name:sha(root/name) for name in ['jwasm/macos-arm64/jwasm','watcom/bin/macos-arm64/wcc','watcom/bin/macos-arm64/wlib','watcom/bin/macos-arm64/wlink']}}
print('Baltic pristine artifacts:',work,flush=True)
def save():(work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
save()
try:
    for jobs in [1,4,8]:
        checkout=work/f'j{jobs}'
        with (work/f'j{jobs}-setup.log').open('wb') as output:
            subprocess.run(['git','worktree','add','--detach',str(checkout),commit],stdout=output,stderr=subprocess.STDOUT,check=True)
            # Use the exact already pinned native assembler, never generated DOS objects.
            destination=checkout/'jwasm/macos-arm64/jwasm';destination.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(root/'jwasm/macos-arm64/jwasm',destination)
            for name,want in report['tool_sha256'].items():assert sha(checkout/name)==want,name
            kvikdos_commit=subprocess.check_output(['git','rev-parse','HEAD:kvikdos'],cwd=checkout,text=True).strip()
            subprocess.run(['git','clone','--no-hardlinks',str(root/'kvikdos'),str(checkout/'kvikdos')],stdout=output,stderr=subprocess.STDOUT,check=True)
            subprocess.run(['git','checkout','--detach',kvikdos_commit],cwd=checkout/'kvikdos',stdout=output,stderr=subprocess.STDOUT,check=True)
        # No source-generated files should be inherited from the primary checkout.
        assert not (checkout/'src/DOS/MSDOS.SYS').exists()
        with (work/f'j{jobs}-build.log').open('wb') as output:
            result=subprocess.run(['make',f'-j{jobs}','all'],cwd=checkout,stdout=output,stderr=subprocess.STDOUT)
        assert result.returncode==0, (jobs,'build failed')
        database=subprocess.check_output(['make','-pn','all'],cwd=checkout,text=True)
        line=next(line for line in database.splitlines() if line.startswith('ARTIFACTS :='))
        names=line.split(':=',1)[1].split()
        artifacts={name:sha(checkout/'src'/name) for name in names}
        core=json.loads((checkout/'out/memory-production/build.json').read_text())
        run={'jobs':jobs,'checkout':str(checkout),'artifacts':artifacts,'core_sha256':core['sha256']}
        if report['runs']:
            assert artifacts==report['runs'][0]['artifacts'],(jobs,'ordinary artifacts differ')
            assert core['sha256']==report['runs'][0]['core_sha256'],(jobs,'production cores differ')
        report['runs'].append(run);save();print('PASS: pristine',jobs,flush=True)
except Exception as error:
    report.update(status='failed',failure=str(error));save();raise
report['status']='passed';save()
