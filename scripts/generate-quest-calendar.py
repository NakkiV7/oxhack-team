#!/usr/bin/env python3
"""Deterministic offline quest calendar. --check validates the committed bundle."""
import json
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parents[1]
path = root / 'Shared/Core/Resources/quest-calendar.json'
daily = [
    ['practice', 'camera', 'recovery'],
    ['control', 'practice', 'reflection'],
    ['balance', 'camera', 'recovery'],
    ['rhythm', 'practice', 'reflection'],
    ['comfortable', 'camera', 'recovery'],
    ['steady', 'practice', 'reflection'],
]
weekly = [['weekPractice', 'weekRecovery'], ['weekRhythm', 'weekReflection']]
value = {'version': 1,
         'daily': [{'slot': day, 'options': daily[(day - 1) % len(daily)]} for day in range(1, 367)],
         'weekly': [{'slot': week, 'options': weekly[(week - 1) % len(weekly)]} for week in range(1, 54)]}
encoded = json.dumps(value, indent=2) + '\n'
if '--check' in sys.argv:
    assert path.read_text() == encoded, 'Quest calendar differs from deterministic source'
    print('366 daily x 3 and 53 weekly x 2 options validated')
else:
    path.write_text(encoded)
