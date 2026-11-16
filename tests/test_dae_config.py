"""Check LAN merging and private config handling in disposable directories."""

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


MODULE = Path(os.environ.get(
    "DAE_CONFIG_MODULE", Path(__file__).parents[1] / "scripts/prepare-dae-config.py"))
spec = importlib.util.spec_from_file_location("dae_config", MODULE)
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


class DaeConfigTests(unittest.TestCase):
    def test_preserves_lan_wan_routing_and_private_nodes(self):
        source = '''global {
  wan_interface: auto
  lan_interface: enp1s0,wlp2s0 # existing LANs
  auto_config_kernel_parameter: true
}
node {
  example: 'anytls://private-password@example.invalid:443#global { fake }'
}
routing {
  dip(192.168.0.0/16) -> direct
  fallback: direct
}
'''
        result = config.merge_lan_interfaces(source, ["virbr0"])
        self.assertEqual(result, source.replace("enp1s0,wlp2s0", '"enp1s0,wlp2s0,virbr0"'))

    def test_inserts_missing_option_without_matching_comments_or_strings(self):
        source = '# global { lan_interface: fake }\nglobal {\n log_level: info\n}\n'
        result = config.merge_lan_interfaces(source, ["virbr0"])
        self.assertIn('lan_interface: "virbr0"', result)
        self.assertTrue(result.startswith('# global { lan_interface: fake }'))

    def test_handles_quoted_and_duplicate_lans_across_global_sections(self):
        source = '''global { lan_interface: 'enp1s0,virbr0' }
global {
  lan_interface: "wlp2s0", 'enp1s0'
  lan_interface: virbr0
}
'''
        result = config.merge_lan_interfaces(source, ["virbr0"])
        self.assertEqual(result.count("lan_interface:"), 1)
        self.assertIn('"enp1s0,virbr0,wlp2s0"', result)
        self.assertEqual(config.merge_lan_interfaces(result, ["virbr0"]), result)

    def test_supports_inline_global_options_and_quoted_hashes(self):
        source = 'global { lan_interface: "enp1s0" wan_interface: auto }\n'
        result = config.merge_lan_interfaces(source, ["virbr0"])
        self.assertIn('"enp1s0,virbr0" wan_interface: auto', result)

    def test_creates_global_section_when_absent(self):
        result = config.merge_lan_interfaces('routing { fallback: direct }\n', ["virbr0"])
        self.assertIn('global {\n  lan_interface: "virbr0"', result)

    def test_fills_empty_interface_list(self):
        source = 'global {\n lan_interface:   # no LANs yet\n}\n'
        result = config.merge_lan_interfaces(source, ["virbr0"])
        self.assertIn('lan_interface:"virbr0"   # no LANs yet', result)
        self.assertEqual(config.merge_lan_interfaces(result, ["virbr0"]), result)

    def test_atomic_private_output_does_not_modify_source(self):
        with tempfile.TemporaryDirectory(prefix="dae-config-", dir="/tmp") as temporary:
            root = Path(temporary)
            source, destination = root / "secret.dae", root / "config.dae"
            source.write_text('global { wan_interface: auto }\n')
            before = source.read_bytes()
            config.prepare(source, destination, ["virbr0"])
            self.assertEqual(destination.stat().st_mode & 0o777, 0o600)
            self.assertEqual(source.read_bytes(), before)
            self.assertEqual(sorted(item.name for item in root.iterdir()), ["config.dae", "secret.dae"])

    def test_failure_leaves_previous_output_and_does_not_leak_source(self):
        with tempfile.TemporaryDirectory(prefix="dae-config-", dir="/tmp") as temporary:
            root = Path(temporary)
            source, destination = root / "secret.dae", root / "config.dae"
            source.write_text('global {\nnode { secret: "private-password" }\n')
            destination.write_text("previous valid config")
            result = subprocess.run([sys.executable, str(MODULE), "--source", str(source),
                                     "--output", str(destination), "--lan-interface", "virbr0"],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("private-password", result.stdout + result.stderr)
            self.assertEqual(destination.read_text(), "previous valid config")

    @unittest.skipUnless(os.environ.get("DAE_BIN"), "DAE_BIN required for parser validation")
    def test_generated_config_is_accepted_by_dae(self):
        with tempfile.TemporaryDirectory(prefix="dae-config-", dir="/tmp") as temporary:
            root = Path(temporary)
            for source in (
                    'global {\n wan_interface: auto\n lan_interface: enp1s0,wlp2s0\n}\n',
                    "global { lan_interface: 'docker0' wan_interface: auto }\n",
                    '# global { lan_interface: fake }\nglobal { wan_interface: auto }\n'):
                secret, output = root / "secret.dae", root / "config.dae"
                secret.write_text(source + 'routing {\n fallback: direct\n}\n')
                config.prepare(secret, output, ["virbr0"])
                result = subprocess.run([os.environ["DAE_BIN"], "validate", "-c", str(output)],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
