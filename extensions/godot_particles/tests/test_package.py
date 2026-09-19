import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ParticlePackageTests(unittest.TestCase):
    def test_library_resolves_all_nodes(self):
        library = json.loads((ROOT / 'particles.json').read_text())
        self.assertGreater(len(library['lib']), 15)
        for entry in library['lib']:
            node = json.loads((ROOT / 'nodes' / (entry['type'] + '.mmg')).read_text())
            self.assertIn('shader_model', node)

    def test_export_has_one_generation_scope_and_both_stages(self):
        node = json.loads((ROOT / 'nodes/mm_particle_output.mmg').read_text())
        profile = node['shader_model']['exports']['Godot 4/Particles 3D']
        shader = '\n'.join(profile['files'][0]['template'])
        self.assertEqual(shader.count('$begin_generate'), 1)
        for required in ['shader_type particles;', 'void start()', 'void process()',
                         'CUSTOM.x = 0.0;', 'CUSTOM.x += DELTA;',
                         'VELOCITY += acceleration * DELTA;']:
            self.assertIn(required, shader)
        self.assertNotIn('TRANSFORM[3].xyz +=', shader)
        self.assertIn('vec4(mm_scale, 0.0, 0.0, 0.0)', shader)

    def test_examples_have_valid_connections_and_shared_stage_input(self):
        graph = json.loads((ROOT / 'examples/gravity.ptex').read_text())
        nodes = {node['name']: node for node in graph['nodes']}
        for edge in graph['connections']:
            source = nodes[edge['from']]['shader_model']
            target = nodes[edge['to']]['shader_model']
            self.assertLess(edge['from_port'], len(source['outputs']))
            self.assertLess(edge['to_port'], len(target['inputs']))
        regression = json.loads((ROOT / 'tests/shared_stages.ptex').read_text())
        self.assertEqual(regression['connections'][0]['from'], regression['connections'][1]['from'])
        self.assertEqual({e['to_port'] for e in regression['connections']}, {1, 2})


if __name__ == '__main__':
    unittest.main()
