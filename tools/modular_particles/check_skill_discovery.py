"""Probe real Codex/Pi skill discovery without model requests or global config writes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]


class JsonLines:
    def __init__(self, command, cwd, env, log):
        self.output = []
        self.queue = queue.Queue()
        self.log = log
        self.errors = log.with_suffix('.stderr.log').open('wb')
        self.process = subprocess.Popen(command,cwd=cwd,env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=self.errors)
        self.reader = threading.Thread(target=self.read,daemon=True)
        self.reader.start()

    def read(self):
        for line in iter(self.process.stdout.readline,b''):
            try: value = json.loads(line)
            except ValueError: continue
            self.output.append(value)
            self.queue.put(value)

    def send(self, value):
        self.process.stdin.write(json.dumps(value).encode('utf-8')+b'\n')
        self.process.stdin.flush()

    def response(self, id):
        while True:
            item = self.queue.get(timeout=60)
            if item.get('id') == id: return item

    def close(self):
        self.process.stdin.close()
        try: self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.reader.join(timeout=5)
        self.errors.close()
        self.log.write_text(json.dumps(self.output,indent=2),encoding='utf-8')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--project',type=Path,required=True)
    parser.add_argument('--codex-cli',type=Path,required=True)
    parser.add_argument('--pi-cli',type=Path,required=True)
    parser.add_argument('--node',default='node')
    args = parser.parse_args()
    project = args.project.resolve()
    work = Path(tempfile.mkdtemp(prefix='mm-vfx-discovery-'))
    print('EVIDENCE:',work,flush=True)
    canonical = project / '.agents/skills/godot-modular-vfx'
    pi_copy = project / '.pi/skills/godot-modular-vfx'
    # Git autocrlf on Windows may alter bytes; compare tracked blob content with
    # normalized LF and also require both installed copies to be byte-identical.
    installed_files = {}
    for source in (ROOT / 'skills/godot-modular-vfx').rglob('*'):
        if not source.is_file(): continue
        relative = source.relative_to(ROOT / 'skills/godot-modular-vfx')
        a, b = canonical / relative, pi_copy / relative
        assert a.is_file() and b.is_file() and a.read_bytes() == b.read_bytes(), relative
        blob = subprocess.check_output(['git','-C',str(ROOT),'show','HEAD:skills/godot-modular-vfx/'+relative.as_posix()])
        assert blob.replace(b'\r\n',b'\n') == a.read_bytes().replace(b'\r\n',b'\n'), relative
        installed_files[relative.as_posix()] = hashlib.sha256(a.read_bytes()).hexdigest()
    env = os.environ.copy()
    codex_home = work / 'codex-home'
    codex_home.mkdir()
    env['CODEX_HOME'] = str(codex_home)
    codex = JsonLines([args.node,str(args.codex_cli.resolve()),'app-server'],project,env,work / 'codex.json')
    try:
        codex.send({'id':1,'method':'initialize','params':{'clientInfo':{'name':'vfx_skill_verification','title':'VFX skill verification','version':'1.0'},'capabilities':{'experimentalApi':True}}})
        assert 'result' in codex.response(1)
        codex.send({'method':'initialized','params':{}})
        codex.send({'id':2,'method':'skills/list','params':{'cwds':[str(project)],'forceReload':True}})
        response = codex.response(2)
        assert 'result' in response, response
        matches = [skill for entry in response['result']['data'] for skill in entry['skills'] if skill['name']=='godot-modular-vfx']
        assert len(matches) == 1 and matches[0].get('enabled',True), response
        codex_skill = matches[0]
    finally: codex.close()
    env = os.environ.copy()
    env.update(PI_CODING_AGENT_DIR=str(work / 'pi-home'),PI_OFFLINE='1',PI_SKIP_VERSION_CHECK='1',PI_TELEMETRY='0')
    pi = JsonLines([args.node,str(args.pi_cli.resolve()),'--mode','rpc','--no-session','--approve','--offline','--no-extensions','--no-prompt-templates','--no-themes','--no-context-files','--no-tools'],project,env,work / 'pi.json')
    try:
        pi.send({'id':'commands','type':'get_commands'})
        response = pi.response('commands')
        assert response.get('success'), response
        matches = [c for c in response['data']['commands'] if c['name']=='skill:godot-modular-vfx']
        assert len(matches) == 1, response
        pi_skill = matches[0]
    finally: pi.close()
    summary = {'passed':True,'project':str(project),'codex':codex_skill,'pi':pi_skill,
               'installed_file_checksums':installed_files,'published_content_matches_normalized_lf':True,
               'global_config_untouched':True,'model_requests':0,
               'scope':'real agent discovery/metadata parsing; no LLM forward-test'}
    (work / 'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print('MODULAR_SKILL_DISCOVERY PASS',work,flush=True)


if __name__ == '__main__': main()
