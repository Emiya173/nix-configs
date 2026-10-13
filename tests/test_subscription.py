import argparse
import base64
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from contextlib import redirect_stderr
from unittest.mock import patch

MODULE = Path(os.environ.get('SUBSCRIPTION_MODULE', Path(__file__).parents[1] / 'packages/dae-subscription/subscription.py'))
spec = importlib.util.spec_from_file_location('subscription', MODULE)
subscription = importlib.util.module_from_spec(spec)
spec.loader.exec_module(subscription)
NODE = b'trojan://example-password@example.org:443#test\n'
OTHER = b'vless://00000000-0000-0000-0000-000000000001@example.net:443#test\n'


class SubscriptionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.url_file = self.directory / 'url'
        self.url_file.write_text('https://example.invalid/private-token')
        self.args = argparse.Namespace(state_dir=self.directory, url_file=self.url_file, max_age=3600, timeout=1)
        self.args.progress_file = self.directory / 'dae.progress'
        self.args.progress_file.write_bytes(b'2\nOK')

    def sync(self, content=NODE):
        with patch.object(subscription, 'fetch', return_value=content):
            subscription.synchronize(self.args)

    def test_plain_and_base64(self):
        self.assertEqual(subscription.validate_nodes(NODE), NODE)
        self.assertEqual(subscription.validate_nodes(base64.b64encode(NODE)), NODE)
        titled = 'trojan://example-password@example.org:443#香港 节点\n'.encode()
        self.assertEqual(subscription.validate_nodes(titled), titled)
        vmess = base64.b64encode(json.dumps({'add': 'example.org', 'port': 443, 'id': '00000000-0000-0000-0000-000000000001'}).encode())
        self.assertEqual(subscription.validate_nodes(b'vmess://' + vmess), b'vmess://' + vmess + b'\n')

    def test_invalid_and_empty_response(self):
        for invalid in [b'', b'<html>login</html>', b'not a node', b'trojan://example.org:443', b'vless://user@example.org:invalid', b'vmess://W10=']:
            with self.subTest(invalid=invalid), self.assertRaises(subscription.InvalidSubscription):
                subscription.validate_nodes(invalid)

    def test_offline_keeps_persistent_cache(self):
        self.sync()
        before = (self.directory / 'current.json').read_bytes()
        self.args.max_age = 0
        with patch.object(subscription, 'fetch', side_effect=OSError('private-token')):
            with self.assertRaises(OSError):
                subscription.synchronize(self.args)
        self.assertEqual((self.directory / 'current.json').read_bytes(), before)
        self.assertEqual(subscription.cache_read(self.directory)['content'], NODE.decode())

    def test_source_change_bypasses_refresh_interval(self):
        self.sync()
        self.url_file.write_text('https://other.invalid/new-private-token')
        with patch.object(subscription, 'fetch', return_value=OTHER) as fetch:
            subscription.synchronize(self.args)
        fetch.assert_called_once()
        self.assertEqual(subscription.cache_read(self.directory, 'candidate.json')['content'], OTHER.decode())
        self.assertEqual(subscription.cache_read(self.directory)['content'], NODE.decode())

    def test_cache_is_private_and_does_not_store_source_url(self):
        self.sync()
        cache = self.directory / 'current.json'
        self.assertEqual(cache.stat().st_mode & 0o777, 0o600)
        self.assertNotIn('private-token', cache.read_text())

    def test_corrupt_cache_is_not_ready(self):
        self.sync()
        value = json.loads((self.directory / 'current.json').read_text())
        value['content'] = '<html>error</html>'
        (self.directory / 'current.json').write_text(json.dumps(value))
        self.assertIsNone(subscription.cache_read(self.directory))

    def test_missing_current_recovers_from_pending_without_network(self):
        self.sync()
        (self.directory / 'current.json').unlink()
        with patch.object(subscription, 'fetch', side_effect=OSError('offline')) as fetch:
            subscription.synchronize(self.args)
        fetch.assert_not_called()
        self.assertEqual(subscription.cache_read(self.directory)['content'], NODE.decode())

    def test_reload_failure_is_retried_and_new_process_is_applied(self):
        self.sync()
        self.args.dae = '/bin/fake-dae'
        self.args.systemctl = '/bin/fake-systemctl'
        state = argparse.Namespace(stdout='ActiveState=active\nMainPID=123\nInvocationID=first\n', returncode=0)
        failed = argparse.Namespace(returncode=1)
        ok = argparse.Namespace(returncode=0, stdout=b'OK\n')
        with patch.object(subscription.subprocess, 'run', side_effect=[state, failed]):
            with self.assertRaises(subscription.InvalidSubscription):
                subscription.apply(self.args)
        self.assertFalse((self.directory / 'applied.json').exists())
        with patch.object(subscription.subprocess, 'run', side_effect=[state, ok]):
            subscription.apply(self.args)
        with patch.object(subscription.subprocess, 'run', return_value=state) as run:
            subscription.apply(self.args)
            self.assertEqual(run.call_count, 1)
        state.stdout = 'ActiveState=active\nMainPID=456\nInvocationID=second\n'
        with patch.object(subscription.subprocess, 'run', side_effect=[state, ok]) as run:
            subscription.apply(self.args)
            self.assertEqual(run.call_count, 2)

    def test_errors_do_not_print_the_private_source(self):
        for error in [OSError('https://example.invalid/private-token'), subscription.http.client.BadStatusLine('https://example.invalid/private-token')]:
            with self.subTest(error=type(error).__name__):
                with patch('sys.argv', ['subscription', '--state-dir', str(self.directory), 'sync', '--url-file', str(self.url_file)]):
                    with patch.object(subscription, 'fetch', side_effect=error):
                        errors = io.StringIO()
                        with redirect_stderr(errors):
                            self.assertEqual(subscription.main(), 1)
                self.assertNotIn('private-token', errors.getvalue())
                self.assertNotIn('https://', errors.getvalue())

    def test_failed_reload_restores_last_good_and_retries_candidate(self):
        self.sync()
        self.url_file.write_text('https://other.invalid/new-private-token')
        self.sync(OTHER)
        self.args.dae = '/bin/fake-dae'
        self.args.systemctl = '/bin/fake-systemctl'
        state = argparse.Namespace(stdout='ActiveState=active\nMainPID=123\nInvocationID=first\n', returncode=0)
        with patch.object(subscription.subprocess, 'run', side_effect=[state, argparse.Namespace(returncode=1)]):
            with self.assertRaises(subscription.InvalidSubscription):
                subscription.apply(self.args)
        self.assertEqual(subscription.cache_read(self.directory)['content'], NODE.decode())
        self.assertEqual(subscription.cache_read(self.directory, 'candidate.json')['content'], OTHER.decode())
        with patch.object(subscription.subprocess, 'run', side_effect=[state, argparse.Namespace(returncode=0, stdout=b'OK\n')]):
            subscription.apply(self.args)
        self.assertEqual(subscription.cache_read(self.directory)['content'], OTHER.decode())
        self.assertFalse((self.directory / 'candidate.json').exists())

    def test_dae_zero_exit_status_does_not_hide_reload_error(self):
        self.sync()
        self.args.dae = '/bin/fake-dae'
        self.args.systemctl = '/bin/fake-systemctl'
        self.args.progress_file.write_bytes(b'3\nredacted error')
        state = argparse.Namespace(stdout='ActiveState=active\nMainPID=123\nInvocationID=first\n', returncode=0)
        with patch.object(subscription.subprocess, 'run', side_effect=[state, argparse.Namespace(returncode=0, stdout=b'OK\n')]):
            with self.assertRaises(subscription.InvalidSubscription):
                subscription.apply(self.args)
        self.assertFalse((self.directory / 'applied.json').exists())


if __name__ == '__main__':
    unittest.main()
