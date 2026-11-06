"""Compile the project's restricted two-voice ABC dialect to deduplicated bars.

Unsupported syntax fails explicitly. Accidental state resets at every bar.
Usage: python3 tools/convert_music_abc.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'godot/music/generated_dm.abc'
TARGET = SOURCE.with_suffix('.json')
TOKEN = re.compile(r'([_=^]?)([A-Ga-gzZ])([,\x27]*)(\d*)')
PITCHES = dict(zip('CDEFGAB', (0, 2, 4, 5, 7, 9, 11)))


def parse_bar(text):
    text = re.sub(r'\s+', '', text)
    if re.fullmatch(r'Z\d*', text):
        return [[{'slot': 0, 'length': 32, 'midi': -1}]] * int(text[1:] or 1)
    events, accidentals, slot, position = [], {}, 0, 0
    while position < len(text):
        match = TOKEN.match(text, position)
        if not match or match[2] == 'Z':
            raise ValueError(f'Unsupported ABC at {text[position:]}')
        accidental, letter, octave, length = match.groups()
        length = int(length or 1)
        midi = -1
        if letter != 'z':
            natural = 60 + PITCHES[letter.upper()] + (12 if letter.islower() else 0)
            natural += 12 * (octave.count("'") - octave.count(','))
            if accidental:
                accidentals[natural] = {'_': -1, '=': 0, '^': 1}[accidental]
            key_offset = -1 if letter.upper() == 'B' else 0
            midi = natural + accidentals.get(natural, key_offset)
        if length <= 0:
            raise ValueError('Non-positive duration')
        events.append({'slot': slot, 'length': length, 'midi': midi})
        slot += length
        position = match.end()
    if slot != 32:
        raise ValueError(f'Expected 32 units per bar, got {slot}: {text}')
    return [events]


def compile_abc(source):
    sections, patterns, lookup = [], [], {}
    section, voice = None, None
    for line in source.splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith('% '):
            section = {'name': line[2:], 'Vocal': [], 'Ins': []}
            sections.append(section)
            continue
        if line.startswith('V:'):
            voice = line[2:].strip().split()[0]
            if voice not in ('Vocal', 'Ins'):
                raise ValueError(f'Unknown voice: {voice}')
            continue
        if re.match(r'^[A-Za-z]:', line):
            if line.startswith(('M:', 'L:', 'K:', 'Q:')) and line not in (
                'M:4/4', 'L:1/32', 'K:Dm', 'Q:1/4=145'
            ):
                raise ValueError(f'Unsupported header: {line}')
            continue
        if section is None or voice is None:
            raise ValueError('Notes require a section and voice')
        for bar in filter(str.strip, line.split('|')):
            for events in parse_bar(bar):
                signature = json.dumps(events, sort_keys=True)
                if signature not in lookup:
                    lookup[signature] = len(patterns)
                    patterns.append(events)
                section[voice].append(lookup[signature])
    for section in sections:
        if not section['Vocal'] or len(section['Vocal']) != len(section['Ins']):
            raise ValueError(f'Unaligned voices in {section["name"]}')
    if not sections:
        raise ValueError('No sections')
    return {'bpm': 145, 'units_per_bar': 32, 'patterns': patterns, 'sections': sections}


if __name__ == '__main__':
    data = compile_abc(SOURCE.read_text())
    TARGET.write_text(json.dumps(data, indent=2) + '\n')
    print(f'{sum(len(s["Vocal"]) for s in data["sections"])} bars, '
          f'{len(data["patterns"])} unique patterns → {TARGET}')
