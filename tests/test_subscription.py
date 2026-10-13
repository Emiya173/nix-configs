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
from email.utils import formatdate
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

    def bootstrap(self):
        self.args.config_file = self.directory / 'config.dae'
        self.args.node_name = 'ruruka'
        self.args.config_file.write_text("node {\n  ruruka: '" + NODE.decode().strip() + "'\n}\n")
        subscription.bootstrap(self.args)

    def test_first_boot_uses_static_proxy_and_keeps_retrying(self):
        self.bootstrap()
        cached = subscription.cache_read(self.directory)
        self.assertTrue(cached['fallback'])
        self.assertEqual(cached['content'], NODE.decode())
        self.assertEqual((self.directory / 'current.json').stat().st_mode & 0o777, 0o600)
        with patch.object(subscription, 'fetch', side_effect=OSError('offline')) as fetch:
            subscription.synchronize(self.args)
            fetch.assert_called_once()
        self.assertEqual(subscription.cache_read(self.directory)['content'], NODE.decode())
        with patch.object(subscription.time, 'time', return_value=subscription.fetch_state_read(self.directory)['next_retry_at']):
            self.sync(OTHER)
        self.assertEqual(subscription.cache_read(self.directory, 'candidate.json')['content'], OTHER.decode())
        self.assertEqual(subscription.cache_read(self.directory)['content'], NODE.decode())
        self.args.dae = '/bin/fake-dae'
        self.args.systemctl = '/bin/fake-systemctl'
        state = argparse.Namespace(stdout='ActiveState=active\nMainPID=123\nInvocationID=first\n', returncode=0)
        with patch.object(subscription.subprocess, 'run', side_effect=[state, argparse.Namespace(returncode=0, stdout=b'OK\n')]):
            subscription.apply(self.args)
        cached = subscription.cache_read(self.directory)
        self.assertEqual(cached['content'], OTHER.decode())
        self.assertFalse(cached.get('fallback', False))

    def test_bootstrap_preserves_good_and_recoverable_subscription(self):
        self.sync(OTHER)
        self.bootstrap()
        self.assertEqual(subscription.cache_read(self.directory)['content'], OTHER.decode())
        (self.directory / 'current.json').unlink()
        self.bootstrap()
        self.assertEqual(subscription.cache_read(self.directory)['content'], OTHER.decode())

    def test_bootstrap_rejects_missing_or_invalid_static_proxy(self):
        self.args.config_file = self.directory / 'config.dae'
        self.args.node_name = 'ruruka'
        for text in ["node {\n}\n", "node {\n ruruka: '<html>error</html>'\n}\n"]:
            self.args.config_file.write_text(text)
            with self.assertRaises(subscription.InvalidSubscription):
                subscription.bootstrap(self.args)
            self.assertFalse((self.directory / 'current.json').exists())

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
            subscription.synchronize(self.args)
        self.assertEqual((self.directory / 'current.json').read_bytes(), before)
        self.assertEqual(subscription.cache_read(self.directory)['content'], NODE.decode())

    def http_error(self, status=429, retry_after=None):
        headers = {'Retry-After': retry_after} if retry_after is not None else {}
        return subscription.urllib.error.HTTPError(self.url_file.read_text(), status, 'private-token', headers, None)

    def test_rate_limit_survives_restarts_and_backoff_grows(self):
        self.bootstrap()
        with patch.object(subscription.time, 'time', return_value=1000):
            with patch.object(subscription, 'fetch', side_effect=self.http_error()) as fetch:
                subscription.synchronize(self.args)
                fetch.assert_called_once()
        state = subscription.fetch_state_read(self.directory)
        self.assertEqual(state['next_retry_at'], 1900)
        self.assertEqual(state['failures'], 1)
        # New invocation reads the persisted deadline instead of hitting upstream.
        with patch.object(subscription.time, 'time', return_value=1899):
            with patch.object(subscription, 'fetch') as fetch:
                subscription.synchronize(self.args)
                fetch.assert_not_called()
        for now, delay, failures in [(1900, 1800, 2), (3700, 3600, 3), (7300, 3600, 4)]:
            with patch.object(subscription.time, 'time', return_value=now):
                with patch.object(subscription, 'fetch', side_effect=self.http_error()) as fetch:
                    subscription.synchronize(self.args)
                    fetch.assert_called_once()
            state = subscription.fetch_state_read(self.directory)
            self.assertEqual(state['next_retry_at'], now + delay)
            self.assertEqual(state['failures'], failures)

    def test_retry_after_seconds_and_http_date_are_honored(self):
        self.bootstrap()
        now = 1800000000
        for header, deadline in [('7200', now + 7200), (formatdate(now + 10800, usegmt=True), now + 10800), ('invalid', now + 900), ('0', now + 900), (formatdate(now - 60, usegmt=True), now + 900)]:
            with self.subTest(header=header):
                (self.directory / subscription.FETCH_STATE).unlink(missing_ok=True)
                with patch.object(subscription.time, 'time', return_value=now):
                    with patch.object(subscription, 'fetch', side_effect=self.http_error(retry_after=header)):
                        subscription.synchronize(self.args)
                self.assertEqual(subscription.fetch_state_read(self.directory)['next_retry_at'], deadline)

    def test_rate_limit_without_cache_still_fails_during_backoff(self):
        with patch.object(subscription.time, 'time', return_value=1000):
            with patch.object(subscription, 'fetch', side_effect=self.http_error()):
                with self.assertRaises(subscription.urllib.error.HTTPError):
                    subscription.synchronize(self.args)
            with patch.object(subscription, 'fetch') as fetch:
                with self.assertRaises(subscription.InvalidSubscription):
                    subscription.synchronize(self.args)
                fetch.assert_not_called()
        self.assertIsNone(subscription.cache_read(self.directory))

    def test_source_change_bypasses_backoff_and_success_clears_failure(self):
        self.bootstrap()
        with patch.object(subscription.time, 'time', return_value=1000):
            with patch.object(subscription, 'fetch', side_effect=self.http_error()):
                subscription.synchronize(self.args)
            self.url_file.write_text('https://other.invalid/new-private-token')
            with patch.object(subscription, 'fetch', return_value=OTHER) as fetch:
                subscription.synchronize(self.args)
                fetch.assert_called_once()
        self.assertFalse((self.directory / subscription.FETCH_STATE).exists())
        self.assertEqual(subscription.sync_health(self.directory), {'degraded': False})
        self.assertEqual(subscription.cache_read(self.directory, 'candidate.json')['content'], OTHER.decode())

    def test_transient_failures_succeed_with_cache_and_keep_safe_diagnostics(self):
        self.bootstrap()
        for error in [self.http_error(), self.http_error(503), OSError('https://example.invalid/private-token'), subscription.http.client.BadStatusLine('private-token')]:
            with self.subTest(error=type(error).__name__):
                (self.directory / subscription.FETCH_STATE).unlink(missing_ok=True)
                with patch('sys.argv', ['subscription', '--state-dir', str(self.directory), 'sync', '--url-file', str(self.url_file)]):
                    with patch.object(subscription, 'fetch', side_effect=error):
                        errors = io.StringIO()
                        with redirect_stderr(errors):
                            self.assertEqual(subscription.main(), 0)
                status = subscription.sync_health(self.directory)
                self.assertTrue(status['degraded'])
                self.assertIn(status['error'], {'http', 'network'})
                state_file = self.directory / subscription.FETCH_STATE
                self.assertEqual(state_file.stat().st_mode & 0o777, 0o600)
                for output in (errors.getvalue(), json.dumps(status), state_file.read_text()):
                    self.assertNotIn('private-token', output)
                    self.assertNotIn('https://', output)

    def test_auth_and_invalid_responses_remain_errors_with_cache(self):
        self.bootstrap()
        for error in [self.http_error(401), self.http_error(403), self.http_error(404), subscription.InvalidSubscription('invalid-node')]:
            with self.subTest(error=type(error).__name__):
                (self.directory / subscription.FETCH_STATE).unlink(missing_ok=True)
                with patch.object(subscription, 'fetch', side_effect=error):
                    with self.assertRaises((subscription.urllib.error.HTTPError, subscription.InvalidSubscription)):
                        subscription.synchronize(self.args)
                self.assertFalse(subscription.fetch_state_read(self.directory)['retryable'])
                self.assertEqual(subscription.cache_read(self.directory)['content'], NODE.decode())

    def test_missing_credentials_and_state_write_errors_are_not_hidden(self):
        self.bootstrap()
        self.url_file.unlink()
        with self.assertRaises(OSError):
            subscription.synchronize(self.args)
        self.url_file.write_text('https://example.invalid/private-token')
        with patch.object(subscription, 'fetch', side_effect=self.http_error()):
            with patch.object(subscription, 'atomic_json', side_effect=PermissionError('private-token')):
                with self.assertRaises(PermissionError):
                    subscription.synchronize(self.args)

    def test_invalid_retry_metadata_is_ignored_without_leaking_values(self):
        self.bootstrap()
        with patch.object(subscription, 'fetch', side_effect=self.http_error()):
            subscription.synchronize(self.args)
        state = subscription.fetch_state_read(self.directory)
        for update in [{'error': 'private-token'}, {'failures': -1}, {'failures': 1000000}, {'source_digest': {}}, {'next_retry_at': float('nan')}, {'next_retry_at': 'private-token'}, {'retryable': 'private-token'}, {'http_status': 'private-token'}]:
            with self.subTest(fields=tuple(update)):
                subscription.atomic_json(self.directory / subscription.FETCH_STATE, {**state, **update})
                self.assertIsNone(subscription.fetch_state_read(self.directory))
                self.assertNotIn('private-token', json.dumps(subscription.sync_health(self.directory)))
        subscription.atomic_json(self.directory / subscription.FETCH_STATE, {**state, 'extra': 'private-token'})
        self.assertNotIn('private-token', json.dumps(subscription.sync_health(self.directory)))
        (self.directory / subscription.FETCH_STATE).write_text('{')
        with patch.object(subscription, 'fetch', return_value=OTHER) as fetch:
            subscription.synchronize(self.args)
            fetch.assert_called_once()

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
                (self.directory / subscription.FETCH_STATE).unlink(missing_ok=True)
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
