"""Unit regressions: a PASS marker or requested driver must never hide fallback."""
import unittest
from render_backend import require_backend

VULKAN = 'Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - Test GPU\n'
D3D12 = 'D3D12 12_0 - Forward+ - Using Device #0: NVIDIA - Test GPU\n'


class BackendGuardTests(unittest.TestCase):
    def test_actual_vulkan(self):
        self.assertEqual(require_backend(VULKAN, 'vulkan')['driver'], 'vulkan')

    def test_actual_d3d12(self):
        self.assertEqual(require_backend(D3D12, 'd3d12')['driver'], 'd3d12')

    def test_duplicated_stdout_and_engine_log(self):
        self.assertEqual(require_backend(D3D12 * 2, 'd3d12')['headers'], 2)

    def test_rejects_fallback_headless_mobile_and_claim_only(self):
        for driver, text in [
            ('d3d12', VULKAN), ('vulkan', D3D12), ('d3d12', VULKAN + D3D12),
            ('d3d12', ''), ('d3d12', 'MODULAR_TEST PASS driver=d3d12\n'),
            ('d3d12', '--rendering-driver d3d12\nMODULAR_TEST PASS\n'),
            ('d3d12', D3D12.replace('Forward+', 'Forward Mobile')),
            ('d3d12', 'OpenGL API 3.3 - Compatibility - Using Device: Test GPU\n'),
        ]:
            with self.subTest(driver=driver, text=text), self.assertRaises(SystemExit):
                require_backend(text, driver)


if __name__ == '__main__': unittest.main()
