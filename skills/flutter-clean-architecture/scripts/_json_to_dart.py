#!/usr/bin/env python3
"""Generate Dart entity + model files (incl. nested types) from a sample JSON.

Called by new_feature.sh when `--json <file>` is passed for an `api` feature.
Infers the shape by MERGING all records in the sample (so a field null/absent in
any record is treated as nullable). Models default every field nullable (APIs
lie even when the sample is fully populated); entities are non-null with
fallbacks. The Retrofit client is NOT generated — verb/path/envelope aren't in a
data sample.

Usage: _json_to_dart.py <pkg> <feature_snake> <item_snake> <json_path> <feature_dir>
"""
import json
import os
import re
import sys


def pascal(s):
    return ''.join(p[:1].upper() + p[1:] for p in s.split('_') if p)


def to_snake(camel):
    return re.sub(r'(?<!^)(?=[A-Z])', '_', camel).lower()


def singular(key):
    if key.endswith('ies'):
        return key[:-3] + 'y'
    if len(key) > 1 and key.endswith('s') and not key.endswith('ss'):
        return key[:-1]
    return key


def dart_field(key):
    if '_' in key:
        parts = [p for p in key.split('_') if p]
        return parts[0] + ''.join(p[:1].upper() + p[1:] for p in parts[1:])
    return key


_DATE_RE = re.compile(r'^\d{4}-\d{2}-\d{2}([T ].*)?$')


def looks_like_date(values):
    strs = [v for v in values if isinstance(v, str)]
    return bool(strs) and all(_DATE_RE.match(v) for v in strs)


def scalar_type(values):
    vals = [v for v in values if v is not None]
    if not vals:
        return ('Object', None)
    if all(isinstance(v, bool) for v in vals):
        return ('bool', 'false')
    if all(isinstance(v, int) and not isinstance(v, bool) for v in vals):
        return ('int', '0')
    if all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in vals):
        return ('double', '0')
    return ('String', "''")


def main():
    pkg, feature, item, json_path, feature_dir = sys.argv[1:6]
    with open(json_path) as f:
        data = json.load(f)
    recs = data if isinstance(data, list) else [data]
    recs = [r for r in recs if isinstance(r, dict)]
    if not recs:
        sys.stderr.write('json_to_dart: expected an object or array of objects\n')
        sys.exit(1)

    built = set()
    created = []

    def write_file(path, content):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w') as fh:
            fh.write(content)
        created.append(path)

    def build(type_pascal, type_snake, records):
        if type_pascal in built:
            return
        built.add(type_pascal)

        keys = []
        for r in records:
            for k in r.keys():
                if k not in keys:
                    keys.append(k)

        model_fields, model_ctor, entity_fields, entity_ctor = [], [], [], []
        to_entity, names = [], []
        model_imports, entity_imports = set(), set()

        for k in keys:
            field = dart_field(k)
            names.append(field if k != 'id' else 'id')
            values = [r.get(k) for r in records]
            non_null = [v for v in values if v is not None]
            keyann = '' if field == k else "  @JsonKey(name: '%s')\n" % k

            is_list = any(isinstance(v, list) for v in non_null)
            is_obj = any(isinstance(v, dict) for v in non_null)

            if is_list:
                elems = []
                for v in non_null:
                    if isinstance(v, list):
                        elems.extend(v)
                elems = [e for e in elems if e is not None]
                if elems and all(isinstance(e, dict) for e in elems):
                    np = pascal(item) + pascal(singular(k))
                    ns = item + '_' + to_snake(singular(k))
                    build(np, ns, elems)
                    model_imports.add(
                        'package:%s/features/%s/data/models/%s_model.dart'
                        % (pkg, feature, ns))
                    entity_imports.add(
                        'package:%s/features/%s/domain/entities/%s.dart'
                        % (pkg, feature, ns))
                    model_fields.append('%s  final List<%sModel> %s;'
                                        % (keyann, np, field))
                    model_ctor.append('    this.%s = const [],' % field)
                    entity_fields.append('  final List<%s> %s;' % (np, field))
                    entity_ctor.append('    required this.%s,' % field)
                    to_entity.append(
                        '        %s: %s.map((e) => e.toEntity()).toList(),'
                        % (field, field))
                else:
                    et, _ = scalar_type(elems)
                    model_fields.append('%s  final List<%s> %s;'
                                        % (keyann, et, field))
                    model_ctor.append('    this.%s = const [],' % field)
                    entity_fields.append('  final List<%s> %s;' % (et, field))
                    entity_ctor.append('    required this.%s,' % field)
                    to_entity.append('        %s: %s,' % (field, field))
            elif is_obj:
                np = pascal(item) + pascal(k)
                ns = item + '_' + to_snake(k)
                build(np, ns, [v for v in non_null if isinstance(v, dict)])
                model_imports.add(
                    'package:%s/features/%s/data/models/%s_model.dart'
                    % (pkg, feature, ns))
                entity_imports.add(
                    'package:%s/features/%s/domain/entities/%s.dart'
                    % (pkg, feature, ns))
                model_fields.append('%s  final %sModel? %s;' % (keyann, np, field))
                model_ctor.append('    this.%s,' % field)
                entity_fields.append('  final %s? %s;' % (np, field))
                entity_ctor.append('    this.%s,' % field)
                to_entity.append('        %s: %s?.toEntity(),' % (field, field))
            elif k == 'id':
                dt, _ = scalar_type(non_null)
                idt = dt if dt in ('int', 'String') else 'String'
                model_fields.append('  final %s id;' % idt)
                model_ctor.append('    required this.id,')
                entity_fields.append('  final %s id;' % idt)
                entity_ctor.append('    required this.id,')
                to_entity.append('        id: id,')
            else:
                dt, fb = scalar_type(non_null)
                if dt == 'Object':
                    model_fields.append(
                        '%s  // TODO(you): type unknown from sample (null/empty).\n'
                        '  final Object? %s;' % (keyann, field))
                    model_ctor.append('    this.%s,' % field)
                    entity_fields.append('  final Object? %s;' % field)
                    entity_ctor.append('    this.%s,' % field)
                    to_entity.append('        %s: %s,' % (field, field))
                else:
                    hint = ''
                    if dt == 'String' and looks_like_date(non_null):
                        hint = ('  // TODO(you): looks like a date'
                                ' — type as DateTime?\n')
                    model_fields.append(
                        '%s%s  final %s? %s;' % (keyann, hint, dt, field))
                    model_ctor.append('    this.%s,' % field)
                    entity_fields.append('  final %s %s;' % (dt, field))
                    entity_ctor.append('    required this.%s,' % field)
                    to_entity.append('        %s: %s ?? %s,' % (field, field, fb))

        # very_good: required named params must precede optional ones.
        def req_first(ctor):
            req = [c for c in ctor if c.lstrip().startswith('required ')]
            opt = [c for c in ctor if not c.lstrip().startswith('required ')]
            return req + opt
        entity_ctor = req_first(entity_ctor)
        model_ctor = req_first(model_ctor)

        # entity file
        ent_imports = sorted(
            ["import 'package:equatable/equatable.dart';"]
            + ["import '%s';" % i for i in entity_imports])
        entity_code = (
            '\n'.join(ent_imports) + '\n\n'
            + 'final class %s extends Equatable {\n' % type_pascal
            + '  const %s({\n' % type_pascal
            + '\n'.join(entity_ctor) + '\n  });\n\n'
            + '\n'.join(entity_fields) + '\n\n'
            + '  @override\n'
            + '  List<Object?> get props => [%s];\n' % ', '.join(names)
            + '}\n')
        write_file(
            os.path.join(feature_dir, 'domain', 'entities', type_snake + '.dart'),
            entity_code)

        # model file
        mod_imports = sorted(
            ["import '%s';"
             % ('package:%s/features/%s/domain/entities/%s.dart'
                % (pkg, feature, type_snake))]
            + ["import '%s';" % i for i in model_imports]
            + ["import 'package:json_annotation/json_annotation.dart';"])
        model_code = (
            '\n'.join(mod_imports) + '\n\n'
            + "part '%s_model.g.dart';\n\n" % type_snake
            + '@JsonSerializable(createToJson: false)\n'
            + 'class %sModel {\n' % type_pascal
            + '  const %sModel({\n' % type_pascal
            + '\n'.join(model_ctor) + '\n  });\n\n'
            + '  factory %sModel.fromJson(Map<String, dynamic> json) =>\n' % type_pascal
            + '      _$%sModelFromJson(json);\n\n' % type_pascal
            + '\n'.join(model_fields) + '\n\n'
            + '  %s toEntity() => %s(\n' % (type_pascal, type_pascal)
            + '\n'.join(to_entity) + '\n      );\n'
            + '}\n')
        write_file(
            os.path.join(feature_dir, 'data', 'models', type_snake + '_model.dart'),
            model_code)

    build(pascal(item), item, recs)
    for p in created:
        print('  + %s' % p)


if __name__ == '__main__':
    main()
