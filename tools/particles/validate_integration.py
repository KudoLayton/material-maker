"""Run particle integration checks in an isolated copy of Material Maker."""
import argparse
from pathlib import Path
from build_windows import ROOT, prepare, run


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', type=Path, required=True)
    args = parser.parse_args()
    project = ROOT / 'build/particle-integration/app'
    prepare(project)
    config = project / 'project.godot'
    text = config.read_text(encoding='utf-8')
    import re
    text = re.sub(r'config/custom_user_dir_name="[^"]+"',
                  'config/custom_user_dir_name="material_maker_integration_validation"', text)
    config.write_text(text, encoding='utf-8')
    engine = args.godot.resolve()
    run(engine, project, 'import.log', ['--headless', '--editor', '--import'])
    text = run(engine, project, 'integration.log',
               ['test/particles/test_integration.tscn', '--position', '-32000,-32000', '--max-fps', '60'], 180)
    print(text)
    for name in ['gpu', 'runtime', 'app', 'constant_ui', 'port_ui', 'random']:
        output = run(engine, project, name + '.log', ['test/particles/test_' + name + '.tscn', '--position', '-32000,-32000', '--max-fps', '60'], 180)
        print('\n'.join(line for line in output.splitlines() if 'PARTICLE_' in line))
    if 'PARTICLE_INTEGRATION: passed' not in text:
        raise RuntimeError('Integration test did not complete')


if __name__ == '__main__':
    main()
