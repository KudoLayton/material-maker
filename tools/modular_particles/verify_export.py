"""Copy only manifest-owned runtime files into a fresh project, then import,
run, export Windows x86_64 release, and execute the exported EXE. Never modifies
the input bundle, installed templates, original project, or existing builds.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def run(command, directory, name, marker=None):
    log = directory / (name + '.log')
    with log.open('w', encoding='utf-8') as output:
        with subprocess.Popen(command, cwd=directory, stdout=output, stderr=subprocess.STDOUT,
                              creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0)) as process:
            started = time.monotonic()
            while process.poll() is None:
                time.sleep(0.2)
                text = log.read_text(encoding='utf-8', errors='replace')
                if 'SCRIPT ERROR:' in text or time.monotonic()-started > 240:
                    process.kill()
                    process.wait()
                    break
    text = log.read_text(encoding='utf-8', errors='replace')
    print(name + ': ' + str(log), flush=True)
    print('\n'.join(line for line in text.splitlines() if 'MODULAR_' in line), flush=True)
    if process.returncode or 'ERROR:' in text or 'leaked' in text or (marker and marker not in text):
        print(text[-10000:])
        raise SystemExit('Verification failed: ' + str(log))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--bundle', required=True, type=Path)
    parser.add_argument('--templates', type=Path, help='Optional installed 4.7.2.stable template directory (read-only)')
    parser.add_argument('--enable-plugin', action='store_true', help='Also exercise the optional Godot EditorPlugin during import')
    args = parser.parse_args()
    engine = args.godot.resolve()
    version = subprocess.check_output([str(engine), '--version'], text=True).strip()
    if not version.startswith('4.7.2.stable.'): raise SystemExit('Godot 4.7.2 stable required')
    manifest = json.loads((args.bundle / 'mm_particles_manifest.json').read_text(encoding='utf-8'))
    project = Path(tempfile.mkdtemp(prefix='mm-modular-export-'))
    print('PROJECT:', project, flush=True)
    for relative, expected in manifest['files'].items():
        path = Path(relative)
        if path.is_absolute() or '..' in path.parts: raise SystemExit('Unsafe manifest path')
        data = (args.bundle / path).read_bytes()
        if hashlib.sha256(data).hexdigest() != expected: raise SystemExit('Bundle checksum mismatch: ' + relative)
        target = project / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    config = (args.bundle / 'project.godot').read_text(encoding='utf-8')
    config = re.sub(r'run/main_scene="[^"]+"', 'run/main_scene="res://verify.tscn"', config)
    config = config.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="mm-modular-tests/' + project.name + '"')
    if args.enable_plugin:
        config += '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/mm_gpu_particles/plugin.cfg")\n'
    (project / 'project.godot').write_text(config, encoding='utf-8')
    smoke = 'standalone_user_smoke.gd' if 'effects/modular_particles/user_demo.gd' in manifest['files'] else 'standalone_smoke.gd'
    shutil.copy2(ROOT / 'test/modular_particles' / smoke, project / 'verify.gd')
    (project / 'verify.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://verify.gd" id="1"]\n[node name="Verify" type="Node"]\nscript=ExtResource("1")\n', encoding='utf-8')
    (project / 'export_presets.cfg').write_text('''[preset.0]
name="Windows Desktop"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="windows/ModularParticles.exe"
[preset.0.options]
binary_format/architecture="x86_64"
binary_format/embed_pck=true
application/modify_resources=false
''', encoding='utf-8')
    if args.templates:
        if (args.templates / 'version.txt').read_text(encoding='utf-8').strip() != '4.7.2.stable':
            raise SystemExit('Template version mismatch')
        with (project / 'export_presets.cfg').open('a', encoding='utf-8') as preset:
            for kind in ['debug', 'release']:
                template = (args.templates / f'windows_{kind}_x86_64.exe').resolve()
                if not template.is_file(): raise SystemExit('Missing template: ' + str(template))
                preset.write(f'custom_template/{kind}="{template.as_posix()}"\n')
    base = [str(engine), '--path', str(project)]
    graphics = ['--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan', '--position', '-32000,-32000', '--max-fps', '60']
    run(base + ['--headless', '--editor', '--import'], project, 'import')
    run(base + graphics, project, 'editor-runtime', 'MODULAR_STANDALONE PASS')
    (project / 'windows').mkdir()
    run(base + ['--headless', '--export-release', 'Windows Desktop'], project, 'export')
    executable = project / 'windows/ModularParticles.exe'
    # --log-file captures output even for the GUI Windows release template.
    run([str(executable), '--log-file', str(project / 'release-engine.log'), *graphics], project, 'windows-runtime')
    release_log = (project / 'release-engine.log').read_text(encoding='utf-8', errors='replace')
    print(release_log, flush=True)
    if 'MODULAR_STANDALONE PASS' not in release_log or 'editor=false' not in release_log or 'ERROR:' in release_log or 'leaked' in release_log:
        raise SystemExit('Exported runtime did not pass')
    print('MODULAR_WINDOWS_EXPORT PASS plugin_enabled=' + str(args.enable_plugin), flush=True)


if __name__ == '__main__': main()
