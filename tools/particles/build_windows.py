"""Build the particle editor without importing assets into the source checkout."""
import argparse
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def run(engine, project, log_name, arguments, timeout=300):
    log_path = project.parent / log_name
    with log_path.open('w', encoding='utf-8') as log:
        result = subprocess.run([str(engine), '--path', str(project), *arguments],
                                stdout=log, stderr=subprocess.STDOUT,
                                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0), timeout=timeout)
    text = log_path.read_text(encoding='utf-8', errors='replace')
    if result.returncode or 'SCRIPT ERROR:' in text:
        raise RuntimeError(f'{log_name} failed ({result.returncode}); see {log_path}')
    return text


def copy_source(source, destination):
    source, destination = Path(source), Path(destination)
    if destination.exists() and (source.suffix == '.import' or
       (source.stat().st_size == destination.stat().st_size and source.stat().st_mtime_ns == destination.stat().st_mtime_ns)):
        return str(destination)
    return shutil.copy2(source, destination)


def prepare(project):
    project.mkdir(parents=True, exist_ok=True)
    for name in ['addons', 'demo', 'material_maker', 'splash_screen', 'test']:
        shutil.copytree(ROOT / name, project / name, dirs_exist_ok=True, copy_function=copy_source)
    for path in ROOT.iterdir():
        if path.is_file() and path.suffix in ['.godot', '.cfg', '.gd', '.uid', '.tscn', '.tres', '.png', '.ico', '.import']:
            copy_source(path, project / path.name)
    steam = project / 'addons/godotsteam/godotsteam.gdextension'
    if steam.exists():
        disabled = steam.with_suffix('.disabled')
        steam.replace(disabled)
    extensions = project / '.godot/extension_list.cfg'
    if extensions.exists():
        extensions.write_text('\n'.join(line for line in extensions.read_text().splitlines() if 'godotsteam' not in line))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--template', required=True, type=Path)
    parser.add_argument('--stock', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    engine, template = args.godot.resolve(), args.template.resolve()
    output, stock = args.output.resolve(), args.stock.resolve()
    if output == stock:
        raise ValueError('The particle build must use a separate directory')
    project = ROOT / 'build/particle-native/app'
    prepare(project)
    config_path = project / 'project.godot'
    release_config = config_path.read_text(encoding='utf-8')
    config_path.write_text(release_config.replace('custom_user_dir_name="material_maker_particles"',
                                                'custom_user_dir_name="material_maker_particles_validation"'), encoding='utf-8')
    run(engine, project, 'app-import.log', ['--headless', '--editor', '--import'])
    text = run(engine, project, 'app-test.log', ['test/particles/test_app.tscn', '--position', '-32000,-32000', '--max-fps', '60'], 120)
    if 'PARTICLE_APP_TESTS: passed' not in text:
        raise RuntimeError('App test did not complete')
    print('PARTICLE_APP_TESTS: passed', flush=True)
    config_path.write_text(release_config, encoding='utf-8')
    presets = project / 'export_presets.cfg'
    text = presets.read_text(encoding='utf-8')
    text = text.replace('custom_template/release=""', f'custom_template/release="{template.as_posix()}"')
    text = text.replace('application/modify_resources=true', 'application/modify_resources=false')
    text = text.replace('exclude_filter="*.ptex,*.mmn,*.mmg"', 'exclude_filter="*.ptex,*.mmn,*.mmg,test/*,extensions/*,tools/*,validation_outputs/*"')
    presets.write_text(text, encoding='utf-8')
    output.mkdir(parents=True, exist_ok=True)
    run(engine, project, 'windows-export.log', ['--headless', '--export-release', 'Windows', str(output / 'material_maker.exe')])
    for name in ['doc', 'environments', 'examples', 'export', 'library', 'meshes', 'nodes']:
        shutil.copytree(stock / name, output / name, dirs_exist_ok=True)
    shutil.copytree(ROOT / 'material_maker/examples/particles', output / 'examples/native_particles', dirs_exist_ok=True)
    for name in ['gravity', 'collision', 'subparticle']:
        for suffix in ['.gdshader', '.tres']:
            shutil.copy2(ROOT / 'build/particle-native/unit/exported' / (name + suffix), output / 'examples/native_particles/godot' / (name + suffix))
    shutil.copy2(ROOT / 'addons/material_maker/particles/README.md', output / 'PARTICLE_EDITOR_README.md')
    print(f'BUILT: {output / "material_maker.exe"}')


if __name__ == '__main__':
    main()
