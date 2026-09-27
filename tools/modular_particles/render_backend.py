"""Fail closed on renderer fallback: inspect Godot's actual RD startup header.
A requested command-line driver alone is NOT proof of the backend in use.
"""
import re


def add_driver_argument(parser):
    parser.add_argument('--rendering-driver', choices=['vulkan', 'd3d12'], default='vulkan',
                        help='Actual Forward+ backend required; fallback fails verification')


def graphics(driver):
    return ['--rendering-method', 'forward_plus', '--rendering-driver', driver,
            '--position', '-32000,-32000', '--max-fps', '60']


def require_backend(text, driver):
    # RenderingDevice prints get_device_api_name() AFTER selecting the device.
    # Match only full RD headers, not command echoes, warnings or PASS markers.
    headers = re.findall(r'^(Vulkan|D3D12|Metal) [^\r\n]+ - (Forward\+|Forward Mobile) - Using Device #[0-9]+: [^\r\n]+$', text, re.MULTILINE)
    if not headers or any(api.lower() != driver or method != 'Forward+' for api, method in headers):
        raise SystemExit(f'Expected actual Forward+/{driver}, found {headers or "no RD header (headless/GL/startup failure)"}')
    return {'driver': driver, 'method': 'forward_plus', 'headers': len(headers)}
