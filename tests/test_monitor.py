import os
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / 'wg-monitor.sh'


class MonitorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.script = self.root / 'wg-monitor.sh'
        self.script.write_text(SCRIPT.read_text().replace('/run/wg_monitor_state_', str(self.root / 'state_')))
        self.script.chmod(0o755)
        for name, body in {
            'wg': 'if [ "$2" = interfaces ]; then echo "wgtest"; else printf "header\\n"; cat "$TEST_ROOT/peers"; fi',
            'logger': 'printf "%s\\n" "$*" >> "$TEST_ROOT/log"',
            'curl': 'printf "%s\\n" "$*" >> "$TEST_ROOT/calls"',
            'jq': 'printf "%s" "$4"',
            'date': 'echo 1000',
        }.items():
            path = self.bin / name
            path.write_text('#!/bin/bash\n' + body + '\n')
            path.chmod(0o755)
        (self.root / 'peers').write_text('')
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'], TEST_ROOT=str(self.root))
        self.env.pop('WG_MONITOR_CONFIG', None)
        self.env.pop('DISCORD_WEBHOOK_URL', None)

    def run_monitor(self, *args):
        return subprocess.run([str(self.script), *args], cwd='/', env=self.env, text=True, capture_output=True)

    def test_adjacent_config_is_loaded_during_discovery_and_state_transitions(self):
        (self.root / 'wg-monitor.conf').write_text(
            'DISCORD_WEBHOOK_URL="https://example.invalid/webhook"\n'
            'declare -A PEER_NAMES=([testkey]="Example device")\n'
        )
        self.assertEqual(self.run_monitor().returncode, 0)
        (self.root / 'peers').write_text('testkey none 192.0.2.1:1234 10.0.0.2/32 999 0 0 0\n')
        result = self.run_monitor()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('[CONNECTED]', (self.root / 'log').read_text())
        self.assertIn('Name: Example device', (self.root / 'calls').read_text())
        self.assertIn('testkey|10.0.0.2/32|192.0.2.1:1234', (self.root / 'state_wgtest.txt').read_text())
        (self.root / 'peers').write_text('testkey none 192.0.2.2:4567 10.0.0.2/32 999 0 0 0\n')
        self.assertEqual(self.run_monitor().returncode, 0)
        self.assertEqual((self.root / 'calls').read_text().count('https://example.invalid/webhook'), 1)
        (self.root / 'peers').write_text('')
        self.assertEqual(self.run_monitor().returncode, 0)
        self.assertIn('[DISCONNECTED]', (self.root / 'log').read_text())
        self.assertEqual((self.root / 'calls').read_text().count('https://example.invalid/webhook'), 2)
        self.assertEqual((self.root / 'state_wgtest.txt').read_text(), '')

    def test_missing_config_fails_before_writing_state(self):
        result = self.run_monitor('wgtest')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'state_wgtest.txt').exists())
        self.assertIn('Cannot read WireGuard monitor config', (self.root / 'log').read_text())

    def test_override_config_is_used(self):
        config = self.root / 'alternate.conf'
        config.write_text('DISCORD_WEBHOOK_URL="https://example.invalid/alternate"\n'
                          'declare -A PEER_NAMES=([testkey]="Alternate name")\n')
        self.env['WG_MONITOR_CONFIG'] = str(config)
        self.assertEqual(self.run_monitor('wgtest').returncode, 0)
        (self.root / 'peers').write_text('testkey none 192.0.2.1:1234 10.0.0.2/32 999 0 0 0\n')
        self.assertEqual(self.run_monitor('wgtest').returncode, 0)
        self.assertIn('Name: Alternate name', (self.root / 'log').read_text())
        self.assertIn('https://example.invalid/alternate', (self.root / 'calls').read_text())

    def test_webhook_without_peer_names_uses_unknown_name(self):
        (self.root / 'wg-monitor.conf').write_text('DISCORD_WEBHOOK_URL="https://example.invalid/webhook"\n')
        self.assertEqual(self.run_monitor('wgtest').returncode, 0)
        (self.root / 'peers').write_text('testkey none 192.0.2.1:1234 10.0.0.2/32 999 0 0 0\n')
        result = self.run_monitor('wgtest')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Name: Unknown peer', (self.root / 'log').read_text())
        self.assertTrue((self.root / 'calls').exists())


if __name__ == '__main__':
    unittest.main()
