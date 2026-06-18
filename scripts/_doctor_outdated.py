#!/usr/bin/env python3
"""Summarize `flutter pub outdated --json` for the skill's key packages.

Advisory only: resolution success is the real compatibility gate, so this just
shows what's behind. Usage: _doctor_outdated.py <outdated.json>
"""
import json
import sys

TRACKED = [
    'flutter_bloc', 'bloc', 'bloc_test', 'bloc_concurrency', 'hydrated_bloc',
    'dio', 'retrofit', 'retrofit_generator', 'json_annotation',
    'json_serializable', 'build_runner', 'envied', 'envied_generator',
    'get_it', 'go_router', 'easy_localization', 'freezed', 'freezed_annotation',
    'flutter_secure_storage', 'very_good_analysis', 'flutter_gen_runner',
    'flutter_svg', 'alchemist', 'cached_network_image', 'path_provider',
    'flutter_screenutil_plus',
]


def ver(node):
    if isinstance(node, dict):
        return node.get('version')
    return None


def major(v):
    try:
        return int(v.split('.')[0].split('+')[0])
    except (ValueError, AttributeError, IndexError):
        return None


def main():
    with open(sys.argv[1]) as f:
        data = json.load(f)
    by_name = {p.get('package'): p for p in data.get('packages', [])}

    behind, major_behind, ok = [], [], 0
    for name in TRACKED:
        p = by_name.get(name)
        if not p:
            continue
        cur, latest = ver(p.get('current')), ver(p.get('latest'))
        if not cur or not latest:
            continue
        if cur == latest:
            ok += 1
        elif major(cur) is not None and major(latest) is not None \
                and major(cur) < major(latest):
            major_behind.append('  ⬆ %-26s %s → %s  (major)' % (name, cur, latest))
        else:
            behind.append('  · %-26s %s → %s' % (name, cur, latest))

    for line in major_behind:
        print(line)
    for line in behind:
        print(line)
    if not major_behind and not behind:
        print('  ✓ all tracked packages at latest (%d checked)' % ok)
    else:
        print('  (%d others at latest. "major" gaps may need code changes; '
              'verify before bumping.)' % ok)


if __name__ == '__main__':
    main()
