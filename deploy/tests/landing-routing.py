"""Provider-free Caddy integration checks. Run on a Docker host with the gateway.

Usage: python3 deploy/tests/landing-routing.py /absolute/path/to/repository
Uses only an isolated loopback listener; never restarts the running gateway.
"""
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.request

root = pathlib.Path(sys.argv[1]).resolve()
image = 'caddy:2.11.7-alpine@sha256:eb4d35b7452d1ab6171fbdbe8d9275b2301dad6dad92115d91e19fb9b24d510f'
name = 'spottr-landing-routing-check'
origin = 'http://127.0.0.1:18149'


def request(path, method='GET', headers=None):
    req = urllib.request.Request(origin + path, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


for allowed in (True, False):
    subprocess.run([
        'docker', 'run', '--detach', '--name', name, '--network', 'spottr_default',
        '--publish', '127.0.0.1:18149:80', '--read-only', '--tmpfs', '/tmp',
        '--env', 'SPOTTR_HOSTNAME=http://:80', '--env', 'ACME_EMAIL=test@example.com',
        '--env', 'SPOTTR_ALLOWED_CIDRS=' + ('0.0.0.0/0' if allowed else '192.0.2.1/32'),
        '--mount', f'type=bind,src={root}/deploy/Caddyfile,dst=/etc/caddy/Caddyfile,readonly',
        '--mount', f'type=bind,src={root}/landing,dst=/srv/landing,readonly', image,
    ], check=True, stdout=subprocess.DEVNULL)
    try:
        for attempt in range(30):
            try:
                request('/')
                break
            except (OSError, urllib.error.URLError):
                time.sleep(0.1)
        status, body = request('/')
        assert status == 200 and body == (root / 'landing/index.html').read_bytes(), (status, 'landing')
        for asset in ('today-simulator.jpg', 'watch-simulator.jpg'):
            status, body = request('/assets/' + asset)
            assert status == 200 and body == (root / 'landing/assets' / asset).read_bytes(), (status, asset)
        status, _ = request('/health')
        assert status == (200 if allowed else 403), (status, 'health', allowed)
        for route in ('/v1/chat', '/v1/summary', '/v1/proposal', '/v1/week-proposal', '/v1/voice', '/v1/voices', '/v1/chat?preview=1', '/v1/workouts', '/unknown', '/.env', '/deploy/gateway.env'):
            status, body = request(route, 'POST' if route.startswith('/v1/') and route != '/v1/voices' else 'GET')
            expected = {401} if route.startswith('/v1/') and '?' not in route else {404}
            # Older deployed gateways predate optional voice routes. Both deny access.
            if route in ('/v1/voice', '/v1/voices'):
                expected = {401, 404}
            assert status in (expected if allowed else {403}), (status, route, allowed)
            assert b'<!DOCTYPE html>' not in body, route
        assert request('/assets/missing.jpg')[0] == 404
        if not allowed:
            status, _ = request('/v1/chat', 'POST', {'X-Forwarded-For': '192.0.2.1'})
            assert status == 403, ('spoofed client', status)
        print('PASS public landing/assets; gateway ' + ('requires bearer' if allowed else 'rejects outside IP, including forged forwarding header'))
    finally:
        subprocess.run(['docker', 'rm', '--force', name], check=True, stdout=subprocess.DEVNULL)
