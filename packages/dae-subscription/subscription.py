#!/usr/bin/env python3
"""Private, persistent DAE subscription relay and serialized synchronization."""
import argparse
import base64
import binascii
from email.utils import parsedate_to_datetime
import hashlib
import http.client
import http.server
import json
import math
import os
import re
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

MAX_BYTES = 4 * 1024 * 1024
SCHEMES = {'ss', 'ssr', 'vmess', 'vless', 'trojan', 'hysteria', 'hysteria2', 'hy2', 'tuic', 'socks', 'socks5', 'http', 'https'}
FETCH_STATE = 'fetch-state.json'
MAX_TIMESTAMP = 253402300799  # Last second representable by an HTTP date.


class InvalidSubscription(ValueError):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def validate_nodes(raw):
    """Accept URI lists or their Base64 envelope, reject login/error pages."""
    if not raw or len(raw) > MAX_BYTES:
        raise InvalidSubscription('empty-or-oversize')
    try:
        text = raw.decode('utf-8-sig').strip()
    except UnicodeError:
        raise InvalidSubscription('invalid-encoding') from None
    if '://' not in text:
        try:
            encoded = ''.join(text.split()).encode('ascii')
            text = base64.b64decode(encoded + b'=' * (-len(encoded) % 4), validate=True).decode('utf-8').strip()
        except (ValueError, UnicodeError, binascii.Error):
            raise InvalidSubscription('invalid-base64') from None
    nodes = [line.strip() for line in text.splitlines() if line.strip() and not line.lstrip().startswith('#')]
    if not nodes:
        raise InvalidSubscription('no-nodes')
    for node in nodes:
        try:
            scheme, payload = node.split('://', 1)
            if scheme not in SCHEMES or not payload or any(c.isspace() for c in node.split('#', 1)[0]):
                raise ValueError()
            if scheme in {'vmess', 'ssr'}:
                decoded = base64.urlsafe_b64decode(payload.split('#', 1)[0] + '=' * (-len(payload.split('#', 1)[0]) % 4))
                if scheme == 'vmess':
                    info = json.loads(decoded)
                    if not isinstance(info, dict) or not all(info.get(k) for k in ('add', 'port', 'id')):
                        raise ValueError()
                elif b':' not in decoded:
                    raise ValueError()
            elif scheme == 'ss' and '@' not in payload:
                decoded = base64.urlsafe_b64decode(payload.split('#', 1)[0] + '=' * (-len(payload.split('#', 1)[0]) % 4))
                if b'@' not in decoded or b':' not in decoded:
                    raise ValueError()
            else:
                parsed = urllib.parse.urlsplit(node)
                if not parsed.hostname or parsed.port is None or not 0 < parsed.port < 65536:
                    raise ValueError()
                if scheme in {'vless', 'trojan', 'hysteria', 'hysteria2', 'hy2', 'tuic', 'ss'} and not parsed.username:
                    raise ValueError()
        except (ValueError, UnicodeError, binascii.Error, KeyError, TypeError):
            raise InvalidSubscription('invalid-node') from None
    return ('\n'.join(nodes) + '\n').encode()


def atomic_json(path, data):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as handle:
            os.fchmod(handle.fileno(), 0o600)
            if os.geteuid() == 0:
                owner = path.parent.stat()
                os.fchown(handle.fileno(), owner.st_uid, owner.st_gid)
            json.dump(data, handle, separators=(',', ':'))
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def cache_read(directory, filename='current.json'):
    try:
        value = json.loads((directory / filename).read_text())
        if not isinstance(value, dict) or not isinstance(value.get('content'), str) or not isinstance(value.get('fetched_at'), (int, float)):
            raise ValueError()
        content = validate_nodes(value['content'].encode())
        if digest(content) != value['sha256']:
            raise ValueError()
        return value
    except (OSError, ValueError, KeyError, TypeError):
        return None


def bootstrap(args):
    """Keep DAE usable on first boot without weakening subscription validation."""
    if cache_read(args.state_dir):
        return
    recovery = cache_read(args.state_dir, 'previous.json') or cache_read(args.state_dir, 'candidate.json')
    if recovery:
        atomic_json(args.state_dir / 'current.json', recovery)
        return
    text = Path(args.config_file).read_text()
    section = re.search(r'(?ms)^node\s*\{\s*\n(.*?)^\s*\}', text)
    if section is None:
        raise InvalidSubscription('missing-node-section')
    pattern = r"""(?m)^\s*""" + re.escape(args.node_name) + r""":\s*(['"])(.*?)\1\s*(?:#.*)?$"""
    matches = list(re.finditer(pattern, section.group(1)))
    if len(matches) != 1:
        raise InvalidSubscription('missing-or-ambiguous-fallback-node')
    content = validate_nodes(matches[0].group(2).encode())
    atomic_json(args.state_dir / 'current.json', {
        'content': content.decode(), 'sha256': digest(content),
        'source_digest': '', 'fetched_at': 0, 'fallback': True,
    })
    print('subscription-fallback-ready')


def fetch(url, timeout):
    # Preserve the existing relay's no-User-Agent behavior; avoid inherited proxies
    # so first boot cannot depend on DAE's not-yet-loaded subscription.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    opener.addheaders = []
    with opener.open(url, timeout=timeout) as response:
        data = response.read(MAX_BYTES + 1)
    return validate_nodes(data)


def fetch_state_read(directory):
    """Only accept safe fields; never echo arbitrary state into health or logs."""
    try:
        value = json.loads((directory / FETCH_STATE).read_text())
        if not isinstance(value, dict) or not re.fullmatch('[0-9a-f]{64}', value.get('source_digest', '')):
            return None
        if type(value.get('failures')) is not int or not 1 <= value['failures'] <= 31:
            return None
        if value.get('error') not in {'http', 'network', 'invalid-response'} or type(value.get('retryable')) is not bool:
            return None
        status = value.get('http_status')
        if status is not None and (type(status) is not int or not 400 <= status <= 599):
            return None
        for key in ('attempted_at', 'next_retry_at'):
            number = value.get(key)
            if type(number) not in (int, float) or not math.isfinite(number) or not 0 <= number <= MAX_TIMESTAMP:
                return None
        return {key: value[key] for key in ('source_digest', 'failures', 'error', 'retryable', 'http_status', 'attempted_at', 'next_retry_at')}
    except (OSError, ValueError, TypeError, KeyError, OverflowError):
        return None


def retry_after_at(header, now):
    if not header:
        return now
    try:
        if re.fullmatch(r'[0-9]+', header.strip()):
            return min(MAX_TIMESTAMP, now + int(header.strip()))
        date = parsedate_to_datetime(header)
        if date.tzinfo is not None:
            return min(MAX_TIMESTAMP, max(now, date.timestamp()))
    except (ValueError, TypeError, OverflowError):
        pass
    return now


def report_fetch_failure(state, cached, deferred=False):
    # Exception text, response bodies and headers may contain credentials.
    print(json.dumps({
        'event': 'subscription-fetch-deferred' if deferred else 'subscription-fetch-failed',
        'error': state['error'], 'http_status': state['http_status'],
        'next_retry_at': state['next_retry_at'], 'using_cache': cached,
    }, separators=(',', ':')), file=sys.stderr)


def sync_health(directory):
    state = fetch_state_read(directory)
    if state is None:
        return {'degraded': False}
    return {'degraded': True, **{key: state[key] for key in ('failures', 'error', 'http_status', 'attempted_at', 'next_retry_at')}}


def synchronize(args):
    url = Path(args.url_file).read_text().strip()
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme not in {'http', 'https'} or not parsed.hostname or any(c.isspace() for c in url):
        raise InvalidSubscription('invalid-source')
    old = cache_read(args.state_dir)
    pending = cache_read(args.state_dir, 'candidate.json')
    if old is None:
        recovery = cache_read(args.state_dir, 'previous.json') or pending
        if recovery:
            atomic_json(args.state_dir / 'current.json', recovery)
            old = recovery
    source = digest(url.encode())
    latest = pending if pending and pending.get('source_digest') == source else old
    if latest and latest.get('source_digest') == source and time.time() - latest.get('fetched_at', 0) < args.max_age:
        return
    failure = fetch_state_read(args.state_dir)
    if failure and failure['source_digest'] != source:
        failure = None
    if failure and time.time() < failure['next_retry_at']:
        usable = cache_read(args.state_dir) is not None
        report_fetch_failure(failure, usable, deferred=True)
        if usable and failure['retryable']:
            return
        raise InvalidSubscription('upstream-backoff')
    try:
        content = fetch(url, args.timeout)
    except (OSError, http.client.HTTPException, InvalidSubscription) as error:
        now = time.time()
        status = None
        retry_after = now
        category, retryable = 'network', True
        if isinstance(error, urllib.error.HTTPError):
            status = error.code
            category = 'http'
            retryable = status in {408, 425, 429} or 500 <= status <= 599
            retry_after = retry_after_at(error.headers.get('Retry-After') if error.headers else None, now)
        elif isinstance(error, InvalidSubscription):
            category, retryable = 'invalid-response', False
        failures = min(31, failure['failures'] + 1) if failure else 1
        delay = min(3600, (900 if status == 429 else 60) * 2 ** (failures - 1))
        state = {
            'source_digest': source, 'failures': failures,
            'error': category, 'http_status': status, 'retryable': retryable,
            'attempted_at': now, 'next_retry_at': max(now + delay, retry_after),
        }
        atomic_json(args.state_dir / FETCH_STATE, state)
        # Bootstrap can create the fallback while the network request is running.
        usable = cache_read(args.state_dir) is not None
        report_fetch_failure(state, usable)
        if usable and retryable:
            return
        raise
    current = {'content': content.decode(), 'sha256': digest(content), 'source_digest': source, 'fetched_at': time.time()}
    atomic_json(args.state_dir / 'candidate.json', current)
    if old is None:
        # First boot needs a validated subscription before DAE can start.
        atomic_json(args.state_dir / 'current.json', current)
    (args.state_dir / FETCH_STATE).unlink(missing_ok=True)
    print('subscription-fetch-ok')


def serve(args):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            cached = cache_read(args.state_dir)
            path = urllib.parse.urlsplit(self.path).path
            if path not in {'/', '/sub', '/subscribe', '/health'}:
                self.send_error(404)
                return
            if cached is None:
                self.send_response(503)
                self.end_headers()
                return
            if path == '/health':
                body = json.dumps({'ready': True, 'sha256': cached['sha256'], 'fetched_at': cached['fetched_at'], 'fallback': cached.get('fallback', False), 'sync': sync_health(args.state_dir)}).encode()
                content_type = 'application/json'
            else:
                body = cached['content'].encode()
                content_type = 'text/plain; charset=utf-8'
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(body)

    server = http.server.ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    server.serve_forever()


def ready(args):
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(f'http://127.0.0.1:{args.port}/sub', timeout=2) as response:
                validate_nodes(response.read(MAX_BYTES + 1))
                return
        except (OSError, ValueError):
            time.sleep(1)
    raise InvalidSubscription('readiness-timeout')


def apply(args):
    """Root-only ExecStartPost; a failed reload remains pending for the next run."""
    cached = cache_read(args.state_dir)
    candidate = cache_read(args.state_dir, 'candidate.json') or cached
    if cached is None:
        raise InvalidSubscription('no-cache')
    state = subprocess.run([args.systemctl, 'show', 'dae.service', '-p', 'ActiveState', '-p', 'MainPID', '-p', 'InvocationID'], capture_output=True, text=True, check=True)
    properties = dict(line.split('=', 1) for line in state.stdout.splitlines() if '=' in line)
    if properties.get('ActiveState') != 'active' or properties.get('MainPID') in {None, '0'}:
        return
    desired = {'sha256': candidate['sha256'], 'invocation': properties.get('InvocationID')}
    try:
        if json.loads((args.state_dir / 'applied.json').read_text()) == desired:
            atomic_json(args.state_dir / 'current.json', candidate)
            (args.state_dir / 'candidate.json').unlink(missing_ok=True)
            return
    except (OSError, ValueError):
        pass
    # Suppress tool output: parser errors can include full credential-bearing URIs.
    if cached['sha256'] != candidate['sha256']:
        atomic_json(args.state_dir / 'previous.json', cached)
    atomic_json(args.state_dir / 'current.json', candidate)
    try:
        result = subprocess.run([args.dae, 'reload', properties['MainPID']], capture_output=True, timeout=90)
        # DAE 2.0 can return zero for ReloadError/ReloadBusy. Check the actual
        # completion marker as well as the command's explicit OK response.
        progress = Path(args.progress_file).read_bytes().split(b'\n', 1)[0]
        if result.returncode or result.stdout.strip() != b'OK' or progress != b'2':
            raise InvalidSubscription('dae-reload-failed')
    except (OSError, ValueError, subprocess.SubprocessError):
        atomic_json(args.state_dir / 'current.json', cached)
        raise
    atomic_json(args.state_dir / 'applied.json', desired)
    (args.state_dir / 'candidate.json').unlink(missing_ok=True)
    print('subscription-applied-ok')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--state-dir', type=Path, default=Path('/var/lib/dae-subscription'))
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ('serve', 'ready'):
        command = commands.add_parser(name)
        command.add_argument('--port', type=int, default=8080)
        if name == 'ready': command.add_argument('--timeout', type=int, default=90)
    bootstrap_command = commands.add_parser('bootstrap')
    bootstrap_command.add_argument('--config-file', required=True)
    bootstrap_command.add_argument('--node-name', required=True)
    sync = commands.add_parser('sync')
    sync.add_argument('--url-file', required=True)
    sync.add_argument('--max-age', type=int, default=3600)
    sync.add_argument('--timeout', type=int, default=20)
    reload = commands.add_parser('apply')
    reload.add_argument('--dae', required=True)
    reload.add_argument('--systemctl', required=True)
    reload.add_argument('--progress-file', type=Path, default=Path('/run/dae.progress'))
    args = parser.parse_args()
    os.umask(0o077)
    try:
        {'serve': serve, 'sync': synchronize, 'ready': ready, 'apply': apply, 'bootstrap': bootstrap}[args.command](args)
    except (OSError, ValueError, http.client.HTTPException, subprocess.SubprocessError):
        # Deliberately never format an upstream/library exception containing secrets.
        print('subscription-operation-failed command=' + args.command, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
