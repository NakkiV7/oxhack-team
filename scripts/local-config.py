#!/usr/bin/env python3
"""Create local gateway configuration; prompt for secrets without echoing them."""
import argparse
import getpass
import json
from pathlib import Path
import re
import secrets

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('key', nargs='?', help='Variable from .env.example to set privately')
args = parser.parse_args()
example = (root / '.env.example').read_text()
allowed = set(re.findall(r'^([A-Z][A-Z0-9_]*)=', example, re.M))
path = root / '.env'
text = path.read_text() if path.exists() else example

def replace(key, value):
    global text
    line = key + '=' + json.dumps(value)
    pattern = r'^' + re.escape(key) + r'=.*$'
    text = re.sub(pattern, lambda _: line, text, flags=re.M) if re.search(pattern, text, re.M) else text + '\n' + line + '\n'

if not re.search(r'^SPOTTR_GATEWAY_TOKEN=.+$', text, re.M):
    replace('SPOTTR_GATEWAY_TOKEN', secrets.token_urlsafe(32))
if args.key:
    if args.key not in allowed:
        parser.error('Choose a variable listed in .env.example')
    value = getpass.getpass(args.key + ' (hidden): ').strip()
    if not value:
        parser.error('Value must not be empty')
    replace(args.key, value)
path.touch(mode=0o600, exist_ok=True)
path.chmod(0o600)
path.write_text(text)
print('Saved ignored .env. Values are not printed. Restart the gateway after changes.')
