#!/usr/bin/env python3
"""Generate Dart from an OpenAPI / Swagger spec for an `api` feature.

Called by new_feature.sh with `--openapi <spec> --path <path> [--method get|post]`.
The spec is a contract (exact types, nullability, nested $refs, enums, the
endpoint), so we emit real models + the Retrofit client — not guesses.

Modes:
  GET  (collection): response is an array of objects -> entity/model (+nested)
       + Retrofit @GET -> List<Model>, a Dio-backed datasource (fetchAll).
  POST (command): requestBody -> request entity/model (toJson + fromEntity)
       + Retrofit @POST(@Body) , datasource/repo/usecase `submit`. A 2xx body
       maps to a response entity (Result<Entity>); no body -> Result<bool>.

Type rules: integer->int, number->double, boolean->bool, string->String,
string+date-time/date -> DateTime (nullable in the entity), enum -> String,
array of $ref -> List<Nested>, $ref object -> nested type (named after the
schema, …Dto/Model stripped). object+additionalProperties -> Map<String, V>
(V from the value schema, or a nested model for an object value); bare object ->
Map<String, dynamic>. allOf is flattened (composition) by merging member
properties, resolving $ref members. `nullable: true` keeps an entity field
nullable. Models default nullable (except id); entities are non-null with
fallbacks, except DateTime/nested-object/nullable which stay nullable.
oneOf/anyOf of object $refs -> a sealed entity + sealed model: one variant class
per member, fromJson dispatches on discriminator.propertyName, and fields common
to every variant are lifted to the base as getters (so callers read e.g. `id`
polymorphically). A discriminator is required; without one the generator errors.
Inline (non-$ref) oneOf members and discriminator-less unions are not modelled.

Usage:
  _openapi_to_dart.py <pkg> <feature> <item> <spec> <feature_dir> <path> <method> <stack>
"""
import json
import os
import re
import sys

# Shared core import paths, resolved from the real project layout by
# new_feature.sh and passed through the environment. Fall back to the
# documented convention when invoked standalone.
CORE_RESULT = os.environ.get('FCA_IMP_RESULT', 'core/error/result.dart')
CORE_FAILURES = os.environ.get('FCA_IMP_FAILURES', 'core/error/failures.dart')
CORE_ERRMAP = os.environ.get('FCA_IMP_ERRMAP', 'core/network/error_mapper.dart')
CORE_DI = os.environ.get('FCA_IMP_DI', 'core/di/injection.dart')


def _imp(pkg, rel):
    """A `package:` import directive for a lib-relative path."""
    return "import 'package:%s/%s';" % (pkg, rel)


# Riverpod Dio provider, resolved from the project by new_feature.sh. When set,
# the generated Riverpod datasource provider reads the project's configured Dio
# (`ref.watch(dioProvider)`) instead of newing up a bare, baseUrl-less `Dio()`.
DIO_PROVIDER = os.environ.get('FCA_DIO_PROVIDER', '')
DIO_PROVIDER_IMPORT = os.environ.get('FCA_DIO_PROVIDER_IMPORT', '')


def _dio_expr():
    return 'ref.watch(%s)' % DIO_PROVIDER if DIO_PROVIDER else 'Dio()'


def _dio_import(pkg):
    # With a provider the notifier never names the Dio type, so import the
    # provider (and not dio.dart, which would be an unused import); otherwise
    # import dio.dart for the bare Dio() fallback.
    if DIO_PROVIDER and DIO_PROVIDER_IMPORT:
        return "import 'package:%s/%s';" % (pkg, DIO_PROVIDER_IMPORT)
    return "import 'package:dio/dio.dart';"


def _sort_import_block(src):
    """Sort the contiguous leading `import` lines (dart: then package:,
    alphabetically) so a patched-in import keeps `directives_ordering` happy."""
    lines = src.split('\n')
    idx = [i for i, l in enumerate(lines) if l.startswith('import ')]
    if not idx:
        return src
    block = [lines[i] for i in idx]
    ordered = (sorted(l for l in block if l.startswith("import 'dart:"))
               + sorted(l for l in block if not l.startswith("import 'dart:")))
    for pos, i in enumerate(idx):
        lines[i] = ordered[pos]
    return '\n'.join(lines)


def pascal(s):
    return ''.join(p[:1].upper() + p[1:] for p in re.split(r'[_\s]+', s) if p)


def to_snake(camel):
    return re.sub(r'_+', '_', re.sub(r'(?<!^)(?=[A-Z])', '_', camel).lower())


def dart_field(key):
    if '_' in key:
        parts = [p for p in key.split('_') if p]
        return parts[0] + ''.join(p[:1].upper() + p[1:] for p in parts[1:])
    return (key[:1].lower() + key[1:]) if key else key


def strip_suffix(name):
    for suf in ('Dto', 'Model', 'Response', 'Resource', 'Command'):
        if name.endswith(suf) and len(name) > len(suf):
            return name[:-len(suf)]
    return name


def ref_name(ref):
    return ref.split('/')[-1]


def main():
    (pkg, feature, item, spec_path, feature_dir,
     path, method, stack) = sys.argv[1:9]
    with open(spec_path) as f:
        spec = json.load(f)

    schemas = spec.get('components', {}).get('schemas', {})
    enum_names = {n for n, s in schemas.items() if 'enum' in s}
    method = method.lower()

    paths = spec.get('paths', {})
    if path not in paths or method not in paths[path]:
        sys.stderr.write("openapi: %s %s not in spec.\n" % (method.upper(), path))
        sys.exit(1)
    op = paths[path][method]

    built = set()
    created = []

    def write_file(p, content):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'w') as fh:
            fh.write(content)
        created.append(p)

    def scalar(ps):
        # (dart_type, fallback). fallback None => nullable entity (no default).
        t, fmt = ps.get('type'), ps.get('format')
        if t == 'integer':
            return ('int', '0')
        if t == 'number':
            return ('double', '0')
        if t == 'boolean':
            return ('bool', 'false')
        if t == 'string' and fmt in ('date-time', 'date'):
            return ('DateTime', None)
        return ('String', "''")

    def resp_2xx_schema():
        responses = op.get('responses', {})
        rkey = '200' if '200' in responses else next(
            (k for k in responses if k.startswith('2')), None)
        if not rkey:
            return None
        content = responses[rkey].get('content', {})
        cs = content.get('application/json') or (
            next(iter(content.values())) if content else None)
        return cs.get('schema') if cs else None

    def merged_props(sch):
        # Flatten allOf composition into one properties dict, recursively
        # resolving $ref members. A plain object just returns its properties.
        # (oneOf/anyOf is handled separately by build -> build_sealed, which
        # generates a sealed hierarchy rather than a flat property set.)
        if not isinstance(sch, dict):
            return {}
        if 'allOf' in sch:
            out = {}
            for part in sch['allOf']:
                if isinstance(part, dict) and '$ref' in part:
                    out.update(merged_props(schemas.get(ref_name(part['$ref']), {})))
                else:
                    out.update(merged_props(part))
            out.update(sch.get('properties', {}))
            return out
        return sch.get('properties', {})

    def walk(props, direction):
        # Walk a properties dict into model/entity field + ctor + mapping lists
        # (no file writing). Shared by build (one object) and build_sealed (one
        # call per oneOf/anyOf variant).
        m_fields, m_ctor, e_fields, e_ctor = [], [], [], []
        to_entity, from_entity, names = [], [], []
        m_imports, e_imports = set(), set()

        def add_object(np, ns, sch):
            build(sch, np, ns, direction)
            m_imports.add('package:%s/features/%s/data/models/%s_model.dart'
                          % (pkg, feature, ns))
            e_imports.add('package:%s/features/%s/domain/entities/%s.dart'
                          % (pkg, feature, ns))

        for k, ps in props.items():
            field = dart_field(k)
            names.append('id' if k == 'id' else field)
            keyann = '' if field == k else "  @JsonKey(name: '%s')\n" % k

            if '$ref' in ps:
                rn = ref_name(ps['$ref'])
                if rn in enum_names:
                    ps = {'type': 'string'}
                else:
                    np, ns = strip_suffix(rn), to_snake(strip_suffix(rn))
                    add_object(np, ns, schemas[rn])
                    m_fields.append('%s  final %sModel? %s;' % (keyann, np, field))
                    m_ctor.append('    this.%s,' % field)
                    e_fields.append('  final %s? %s;' % (np, field))
                    e_ctor.append('    this.%s,' % field)
                    to_entity.append('        %s: %s?.toEntity(),' % (field, field))
                    from_entity.append(
                        '        %s: e.%s == null ? null : %sModel.fromEntity(e.%s),'
                        % (field, field, np, field))
                    continue

            if ps.get('type') == 'object':
                # additionalProperties -> a typed Map; bare object -> dynamic map.
                ap = ps.get('additionalProperties')
                if isinstance(ap, dict) and '$ref' in ap \
                        and ref_name(ap['$ref']) not in enum_names:
                    rn = ref_name(ap['$ref'])
                    np, ns = strip_suffix(rn), to_snake(strip_suffix(rn))
                    add_object(np, ns, schemas[rn])
                    m_fields.append('%s  final Map<String, %sModel> %s;'
                                    % (keyann, np, field))
                    m_ctor.append('    this.%s = const {},' % field)
                    e_fields.append('  final Map<String, %s> %s;' % (np, field))
                    e_ctor.append('    required this.%s,' % field)
                    to_entity.append(
                        '        %s: %s.map((k, v) => MapEntry(k, v.toEntity())),'
                        % (field, field))
                    from_entity.append(
                        '        %s: e.%s.map((k, v) => MapEntry(k, %sModel.fromEntity(v))),'
                        % (field, field, np))
                else:
                    vt = scalar(ap)[0] if isinstance(ap, dict) else 'dynamic'
                    m_fields.append('%s  final Map<String, %s> %s;'
                                    % (keyann, vt, field))
                    m_ctor.append('    this.%s = const {},' % field)
                    e_fields.append('  final Map<String, %s> %s;' % (vt, field))
                    e_ctor.append('    required this.%s,' % field)
                    to_entity.append('        %s: %s,' % (field, field))
                    from_entity.append('        %s: e.%s,' % (field, field))
                continue

            if ps.get('type') == 'array':
                items = ps.get('items', {})
                if '$ref' in items and ref_name(items['$ref']) not in enum_names:
                    rn = ref_name(items['$ref'])
                    np, ns = strip_suffix(rn), to_snake(strip_suffix(rn))
                    add_object(np, ns, schemas[rn])
                    m_fields.append('%s  final List<%sModel> %s;'
                                    % (keyann, np, field))
                    m_ctor.append('    this.%s = const [],' % field)
                    e_fields.append('  final List<%s> %s;' % (np, field))
                    e_ctor.append('    required this.%s,' % field)
                    to_entity.append(
                        '        %s: %s.map((e) => e.toEntity()).toList(),'
                        % (field, field))
                    from_entity.append(
                        '        %s: e.%s.map(%sModel.fromEntity).toList(),'
                        % (field, field, np))
                else:
                    et = 'String' if '$ref' in items else scalar(items)[0]
                    m_fields.append('%s  final List<%s> %s;' % (keyann, et, field))
                    m_ctor.append('    this.%s = const [],' % field)
                    e_fields.append('  final List<%s> %s;' % (et, field))
                    e_ctor.append('    required this.%s,' % field)
                    to_entity.append('        %s: %s,' % (field, field))
                    from_entity.append('        %s: e.%s,' % (field, field))
            elif k == 'id':
                idt = 'int' if ps.get('type') == 'integer' else 'String'
                m_fields.append('  final %s id;' % idt)
                m_ctor.append('    required this.id,')
                e_fields.append('  final %s id;' % idt)
                e_ctor.append('    required this.id,')
                to_entity.append('        id: id,')
                from_entity.append('        id: e.id,')
            else:
                dt, fb = scalar(ps)
                if ps.get('nullable'):
                    fb = None    # explicit nullable -> entity field stays nullable
                m_fields.append('%s  final %s? %s;' % (keyann, dt, field))
                m_ctor.append('    this.%s,' % field)
                if fb is None:
                    e_fields.append('  final %s? %s;' % (dt, field))
                    e_ctor.append('    this.%s,' % field)
                    to_entity.append('        %s: %s,' % (field, field))
                else:
                    e_fields.append('  final %s %s;' % (dt, field))
                    e_ctor.append('    required this.%s,' % field)
                    to_entity.append('        %s: %s ?? %s,' % (field, field, fb))
                from_entity.append('        %s: e.%s,' % (field, field))

        def req_first(ctor):
            req = [c for c in ctor if c.lstrip().startswith('required ')]
            opt = [c for c in ctor if not c.lstrip().startswith('required ')]
            return req + opt
        return (m_fields, req_first(m_ctor), e_fields, req_first(e_ctor),
                to_entity, from_entity, names, m_imports, e_imports)

    def _entity_class(tp, names, e_ctor, e_fields, extends='Equatable'):
        return (
            'final class %s extends %s {\n' % (tp, extends)
            + '  const %s({\n' % tp + '\n'.join(e_ctor) + '\n  });\n\n'
            + '\n'.join(e_fields) + '\n\n  @override\n'
            + '  List<Object?> get props => [%s];\n}\n' % ', '.join(names))

    def build(schema, type_pascal, type_snake, direction='response'):
        if type_pascal in built:
            return
        if isinstance(schema, dict) and ('oneOf' in schema or 'anyOf' in schema):
            build_sealed(schema, type_pascal, type_snake, direction)
            return
        built.add(type_pascal)
        (m_fields, m_ctor, e_fields, e_ctor, to_entity, from_entity, names,
         m_imports, e_imports) = walk(merged_props(schema), direction)

        ent_imports = sorted(
            ["import 'package:equatable/equatable.dart';"]
            + ["import '%s';" % i for i in e_imports])
        entity_code = ('\n'.join(ent_imports) + '\n\n'
                       + _entity_class(type_pascal, names, e_ctor, e_fields))
        write_file(os.path.join(feature_dir, 'domain', 'entities',
                                type_snake + '.dart'), entity_code)

        mod_imports = sorted(
            ["import 'package:%s/features/%s/domain/entities/%s.dart';"
             % (pkg, feature, type_snake)]
            + ["import '%s';" % i for i in m_imports]
            + ["import 'package:json_annotation/json_annotation.dart';"])
        head = ('\n'.join(mod_imports) + '\n\n'
                + "part '%s_model.g.dart';\n\n" % type_snake)
        if direction == 'request':
            # outbound: toJson + fromEntity (no fromJson/toEntity).
            model_code = (
                head + '@JsonSerializable()\n'
                + 'class %sModel {\n' % type_pascal
                + '  const %sModel({\n' % type_pascal + '\n'.join(m_ctor)
                + '\n  });\n\n'
                + '  factory %sModel.fromEntity(%s e) => %sModel(\n'
                % (type_pascal, type_pascal, type_pascal)
                + '\n'.join(from_entity) + '\n      );\n\n'
                + '\n'.join(m_fields) + '\n\n'
                + '  Map<String, dynamic> toJson() => _$%sModelToJson(this);\n}\n'
                % type_pascal)
        else:
            model_code = (
                head + '@JsonSerializable(createToJson: false)\n'
                + 'class %sModel {\n' % type_pascal
                + '  const %sModel({\n' % type_pascal + '\n'.join(m_ctor)
                + '\n  });\n\n'
                + '  factory %sModel.fromJson(Map<String, dynamic> json) =>\n'
                % type_pascal
                + '      _$%sModelFromJson(json);\n\n' % type_pascal
                + '\n'.join(m_fields) + '\n\n'
                + '  %s toEntity() => %s(\n' % (type_pascal, type_pascal)
                + '\n'.join(to_entity) + '\n      );\n}\n')
        write_file(os.path.join(feature_dir, 'data', 'models',
                                type_snake + '_model.dart'), model_code)

    def build_sealed(schema, type_pascal, type_snake, direction):
        # oneOf/anyOf of object $refs -> a sealed entity + sealed model with
        # discriminator dispatch. Dart requires sealed subtypes to be co-located,
        # so every variant lives in the one entity file and the one model file.
        # A discriminator (discriminator.propertyName) is required to deserialize.
        # Fields common to ALL variants (same name + type) are lifted to the
        # sealed base as abstract getters so callers read them polymorphically
        # (e.g. a list page's `item.id`); variant fields then override them.
        built.add(type_pascal)
        variants = schema.get('oneOf') or schema.get('anyOf') or []
        disc = schema.get('discriminator') or {}
        disc_prop = disc.get('propertyName')
        ref_to_val = {ref_name(v): key
                      for key, v in (disc.get('mapping') or {}).items()}
        if not disc_prop:
            sys.stderr.write(
                'openapi: %s is oneOf/anyOf without discriminator.propertyName; '
                'cannot dispatch fromJson reliably.\n' % type_pascal)
            sys.exit(1)

        def field_pairs(e_fields):
            out = []
            for ef in e_fields:
                m = re.match(r'\s*final (.+) (\w+);', ef)
                if m:
                    out.append((m.group(2), m.group(1)))  # (name, dart_type)
            return out

        # Gather each variant's walk output first (needed to compute common
        # fields before emitting, so variant fields can be marked @override).
        vdata = []
        for v in variants:
            if not isinstance(v, dict) or '$ref' not in v:
                continue
            rn = ref_name(v['$ref'])
            vp = strip_suffix(rn)
            built.add(vp)                       # emitted inline; don't rebuild
            dval = ref_to_val.get(rn, rn)       # default disc value = schema name
            vdata.append((vp, dval, walk(merged_props(schemas[rn]), direction)))

        common = []
        if vdata:
            maps = [dict(field_pairs(d[2][2])) for d in vdata]  # d[2][2] = e_fields
            for nm, ty in field_pairs(vdata[0][2][2]):
                if all(m.get(nm) == ty for m in maps):
                    common.append((nm, ty))
        common_names = {nm for nm, _ in common}

        ent_blocks, mod_blocks = [], []
        e_imports_all, m_imports_all = set(), set()
        from_json_cases, from_entity_cases = [], []
        for vp, dval, (m_fields, m_ctor, e_fields, e_ctor, to_entity,
                       from_entity, names, m_imports, e_imports) in vdata:
            e_imports_all |= e_imports
            m_imports_all |= m_imports
            ov_e_fields = [('  @override\n' + ef) if nm in common_names else ef
                           for nm, ef in zip(names, e_fields)]
            ent_blocks.append(_entity_class(vp, names, e_ctor, ov_e_fields,
                                            extends=type_pascal))
            if direction == 'request':
                mod_blocks.append(
                    '@JsonSerializable()\n'
                    + 'final class %sModel extends %sModel {\n' % (vp, type_pascal)
                    + '  const %sModel({\n' % vp + '\n'.join(m_ctor) + '\n  });\n\n'
                    + '  factory %sModel.fromEntity(%s e) => %sModel(\n'
                    % (vp, vp, vp)
                    + '\n'.join(from_entity) + '\n      );\n\n'
                    + '\n'.join(m_fields) + '\n\n'
                    + '  @override\n'
                    + '  Map<String, dynamic> toJson() => _$%sModelToJson(this);\n}\n'
                    % vp)
                from_entity_cases.append('      %s() => %sModel.fromEntity(e),'
                                         % (vp, vp))
            else:
                mod_blocks.append(
                    '@JsonSerializable(createToJson: false)\n'
                    + 'final class %sModel extends %sModel {\n' % (vp, type_pascal)
                    + '  const %sModel({\n' % vp + '\n'.join(m_ctor) + '\n  });\n\n'
                    + '  factory %sModel.fromJson(Map<String, dynamic> json) =>\n'
                    % vp
                    + '      _$%sModelFromJson(json);\n\n' % vp
                    + '\n'.join(m_fields) + '\n\n'
                    + '  @override\n'
                    + '  %s toEntity() => %s(\n' % (vp, vp)
                    + '\n'.join(to_entity) + '\n      );\n}\n')
                from_json_cases.append("      '%s' => %sModel.fromJson(json),"
                                       % (dval, vp))

        base_getters = ''.join('\n  %s get %s;' % (ty, nm) for nm, ty in common)
        ent_imports = sorted(
            ["import 'package:equatable/equatable.dart';"]
            + ["import '%s';" % i for i in e_imports_all])
        entity_code = (
            '\n'.join(ent_imports) + '\n\n'
            + 'sealed class %s extends Equatable {\n' % type_pascal
            + '  const %s();' % type_pascal
            + base_getters + '\n}\n\n'
            + '\n'.join(ent_blocks))
        write_file(os.path.join(feature_dir, 'domain', 'entities',
                                type_snake + '.dart'), entity_code)

        mod_imports = sorted(
            ["import 'package:%s/features/%s/domain/entities/%s.dart';"
             % (pkg, feature, type_snake)]
            + ["import '%s';" % i for i in m_imports_all]
            + ["import 'package:json_annotation/json_annotation.dart';"])
        head = ('\n'.join(mod_imports) + '\n\n'
                + "part '%s_model.g.dart';\n\n" % type_snake)
        if direction == 'request':
            base = (
                'sealed class %sModel {\n' % type_pascal
                + '  const %sModel();\n\n' % type_pascal
                + '  factory %sModel.fromEntity(%s e) => switch (e) {\n'
                % (type_pascal, type_pascal)
                + '\n'.join(from_entity_cases) + '\n      };\n\n'
                + '  Map<String, dynamic> toJson();\n}\n\n')
        else:
            base = (
                'sealed class %sModel {\n' % type_pascal
                + '  const %sModel();\n\n' % type_pascal
                + '  factory %sModel.fromJson(Map<String, dynamic> json) {\n'
                % type_pascal
                + "    final type = json['%s'] as String?;\n" % disc_prop
                + '    return switch (type) {\n'
                + '\n'.join(from_json_cases) + '\n'
                + "      _ => throw ArgumentError('Unknown %s discriminator: $type'),\n"
                % type_pascal
                + '    };\n  }\n\n'
                + '  %s toEntity();\n}\n\n' % type_pascal)
        model_code = head + base + '\n'.join(mod_blocks)
        write_file(os.path.join(feature_dir, 'data', 'models',
                                type_snake + '_model.dart'), model_code)

    fp, ip = pascal(feature), pascal(item)

    def sorted_imports(*lines):
        return '\n'.join(sorted(lines))

    # ---- GET (collection + optional query filters, or fetch-by-id) ----------
    if method == 'get':
        rsch = resp_2xx_schema()
        is_coll = bool(rsch and rsch.get('type') == 'array'
                       and '$ref' in rsch.get('items', {}))
        is_one = bool(rsch and '$ref' in rsch
                      and ref_name(rsch['$ref']) not in enum_names)
        if not (is_coll or is_one):
            sys.stderr.write('openapi: GET needs an array-of-objects or a single '
                             '$ref-object response on %s.\n' % path)
            sys.exit(1)
        ient = lambda sn: ("import 'package:%s/features/%s/domain/entities/%s.dart';"
                           % (pkg, feature, sn))
        imod = lambda sn: ("import 'package:%s/features/%s/data/models/%s_model.dart';"
                           % (pkg, feature, sn))
        ddir = os.path.join(feature_dir, 'data', 'datasources')
        path_params = []
        for prm in op.get('parameters', []):
            if prm.get('in') == 'path':
                pt = prm.get('schema', {}).get('type')
                path_params.append((dart_field(prm['name']),
                                    'int' if pt == 'integer' else 'String'))

        if is_coll:
            build(schemas[ref_name(rsch['items']['$ref'])], ip, item)
            # query parameters -> optional named filters threaded end-to-end
            qp = []
            for prm in op.get('parameters', []):
                if prm.get('in') == 'query':
                    sc = prm.get('schema', {})
                    qt = ('String' if '$ref' in sc else
                          {'integer': 'int', 'number': 'double',
                           'boolean': 'bool'}.get(sc.get('type'), 'String'))
                    qp.append((dart_field(prm['name']), qt, prm['name']))
            dom_p = ('{%s}' % ', '.join('%s? %s' % (t, f) for f, t, _ in qp)) if qp else ''
            named = ', '.join('%s: %s' % (f, f) for f, _, _ in qp)
            cli_p = ('{%s}' % ', '.join("@Query('%s') %s? %s" % (o, t, f)
                                        for f, t, o in qp)) if qp else ''

            client = ('\n'.join(sorted(["import 'package:dio/dio.dart';", imod(item),
                                        "import 'package:retrofit/retrofit.dart';"]))
                      + '\n\n' + "part '%s_api.g.dart';\n\n@RestApi()\n" % feature
                      + "abstract class %sApi {\n" % fp
                      + "  factory %sApi(Dio dio, {String baseUrl}) = _%sApi;\n\n" % (fp, fp)
                      + "  @GET('%s')\n" % path
                      + "  Future<List<%sModel>> getAll(%s);\n}\n" % (ip, cli_p))
            write_file(os.path.join(ddir, feature + '_api.dart'), client)

            ds = ('\n'.join(sorted([
                "import 'package:dio/dio.dart';",
                "import 'package:%s/features/%s/data/datasources/%s_api.dart';"
                % (pkg, feature, feature), imod(item)])) + '\n\n'
                + "abstract interface class %sRemoteDataSource {\n" % fp
                + "  Future<List<%sModel>> fetchAll(%s);\n}\n\n" % (ip, dom_p)
                + "final class %sRemoteDataSourceImpl implements %sRemoteDataSource {\n"
                % (fp, fp)
                + "  %sRemoteDataSourceImpl(Dio dio) : _api = %sApi(dio);\n\n" % (fp, fp)
                + "  final %sApi _api;\n\n  @override\n" % fp
                + "  Future<List<%sModel>> fetchAll(%s) => _api.getAll(%s);\n}\n"
                % (ip, dom_p, named))
            write_file(os.path.join(ddir, feature + '_remote_data_source.dart'), ds)

            repo = ('\n'.join(sorted([_imp(pkg, CORE_RESULT),
                                      ient(item)])) + '\n\n'
                    + "abstract interface class %sRepository {\n" % fp
                    + "  Future<Result<List<%s>>> getAll(%s);\n}\n" % (ip, dom_p))
            write_file(os.path.join(feature_dir, 'domain', 'repositories',
                                    feature + '_repository.dart'), repo)

            uc = ('\n'.join(sorted([
                _imp(pkg, CORE_RESULT), ient(item),
                "import 'package:%s/features/%s/domain/repositories/%s_repository.dart';"
                % (pkg, feature, feature)])) + '\n\n'
                + 'class Get%sUseCase {\n' % fp
                + '  const Get%sUseCase(this._repository);\n\n' % fp
                + '  final %sRepository _repository;\n\n' % fp
                + '  Future<Result<List<%s>>> call(%s) =>\n' % (ip, dom_p)
                + '      _repository.getAll(%s);\n}\n' % named)
            write_file(os.path.join(feature_dir, 'domain', 'usecases',
                                    'get_%s_use_case.dart' % feature), uc)

            ri = ('\n'.join(sorted([
                "import 'package:dio/dio.dart';",
                _imp(pkg, CORE_FAILURES),
                _imp(pkg, CORE_RESULT),
                _imp(pkg, CORE_ERRMAP),
                "import 'package:%s/features/%s/data/datasources/%s_remote_data_source.dart';"
                % (pkg, feature, feature), ient(item),
                "import 'package:%s/features/%s/domain/repositories/%s_repository.dart';"
                % (pkg, feature, feature)])) + '\n\n'
                + 'final class %sRepositoryImpl implements %sRepository {\n' % (fp, fp)
                + '  const %sRepositoryImpl(this._remoteDataSource);\n\n' % fp
                + '  final %sRemoteDataSource _remoteDataSource;\n\n  @override\n' % fp
                + '  Future<Result<List<%s>>> getAll(%s) async {\n' % (ip, dom_p)
                + '    try {\n'
                + '      final models = await _remoteDataSource.fetchAll(%s);\n' % named
                + '      return Success(models.map((model) => model.toEntity()).toList());\n'
                + '    } on DioException catch (error) {\n'
                + '      return FailureResult(mapDioException(error));\n'
                + '    } on Object {\n'
                + "      return const FailureResult(\n"
                + "        UnknownFailure(message: 'common.unknown_error'),\n"
                + '      );\n    }\n  }\n}\n')
            write_file(os.path.join(feature_dir, 'data', 'repositories',
                                    feature + '_repository_impl.dart'), ri)
            if stack == 'riverpod':
                _patch_riverpod(feature_dir, feature, fp, pkg)

        else:  # fetch-by-id (single resource)
            if rsch.get('type') == 'array':
                sys.stderr.write('openapi: GET with a path param is treated as '
                                 'fetch-by-id (single resource); %s returns an '
                                 'array.\n' % path)
                sys.exit(1)
            build(schemas[ref_name(rsch['$ref'])], ip, item)
            idf, idt = path_params[0] if path_params else ('id', 'String')
            _generate_get_by_id(write_file, feature_dir, pkg, feature, item, fp, ip,
                                 path, idf, idt, stack)

    # ---- Command (POST / PUT / PATCH / DELETE) ------------------------------
    elif method in ('post', 'put', 'patch', 'delete'):
        verbs = {'post': ('@POST', 'submit', 'Submit'),
                 'put': ('@PUT', 'update', 'Update'),
                 'patch': ('@PATCH', 'patch', 'Patch'),
                 'delete': ('@DELETE', 'delete', 'Delete')}
        http_ann, mname, uc_prefix = verbs[method]

        # path parameters, e.g. /Things/{id}
        path_params = []
        for prm in op.get('parameters', []):
            if prm.get('in') == 'path':
                pt = prm.get('schema', {}).get('type')
                path_params.append((dart_field(prm['name']),
                                    'int' if pt == 'integer' else 'String'))

        # request body -> request entity/model (toJson + fromEntity)
        req_pascal, req_snake, has_body = ip + 'Request', item + '_request', False
        if method in ('post', 'put', 'patch'):
            rb = op.get('requestBody', {}).get('content', {})
            rbs = (rb.get('application/json')
                   or (next(iter(rb.values())) if rb else None))
            if rbs and '$ref' in rbs.get('schema', {}):
                build(schemas[ref_name(rbs['schema']['$ref'])],
                      req_pascal, req_snake, 'request')
                has_body = True

        # response object -> entity; otherwise void -> Result<bool>
        rsch = resp_2xx_schema()
        resp_pascal = resp_snake = None
        if rsch and '$ref' in rsch and ref_name(rsch['$ref']) not in enum_names:
            rn = ref_name(rsch['$ref'])
            resp_pascal, resp_snake = strip_suffix(rn), to_snake(strip_suffix(rn))
            build(schemas[rn], resp_pascal, resp_snake)
        ret_model = '%sModel' % resp_pascal if resp_pascal else 'void'
        ret_entity = resp_pascal if resp_pascal else 'bool'

        # signatures shared across layers
        dom_decl = ['%s %s' % (dt, n) for n, dt in path_params]
        dom_args = [n for n, _ in path_params]
        if has_body:
            dom_decl.append('%s input' % req_pascal)
            dom_args.append('input')
        dom_decl_s, dom_args_s = ', '.join(dom_decl), ', '.join(dom_args)
        cli_decl = ["@Path('%s') %s %s" % (n, dt, n) for n, dt in path_params]
        if has_body:
            cli_decl.append('@Body() %sModel body' % req_pascal)
        ds_call = [n for n, _ in path_params] + (
            ['%sModel.fromEntity(input)' % req_pascal] if has_body else [])

        ent_imp = lambda sn: ("import 'package:%s/features/%s/domain/entities/%s.dart';"
                              % (pkg, feature, sn))
        mod_imp = lambda sn: ("import 'package:%s/features/%s/data/models/%s_model.dart';"
                              % (pkg, feature, sn))

        # Retrofit client
        cimports = ["import 'package:dio/dio.dart';",
                    "import 'package:retrofit/retrofit.dart';"]
        if has_body:
            cimports.append(mod_imp(req_snake))
        if resp_pascal:
            cimports.append(mod_imp(resp_snake))
        client = ('\n'.join(sorted(cimports)) + '\n\n'
                  + "part '%s_api.g.dart';\n\n@RestApi()\n" % feature
                  + "abstract class %sApi {\n" % fp
                  + "  factory %sApi(Dio dio, {String baseUrl}) = _%sApi;\n\n"
                  % (fp, fp)
                  + "  %s('%s')\n" % (http_ann, path)
                  + "  Future<%s> %s(%s);\n}\n" % (ret_model, mname, ', '.join(cli_decl)))
        write_file(os.path.join(feature_dir, 'data', 'datasources',
                                feature + '_api.dart'), client)

        # datasource
        dimports = ["import 'package:dio/dio.dart';",
                    "import 'package:%s/features/%s/data/datasources/%s_api.dart';"
                    % (pkg, feature, feature)]
        if has_body:
            dimports += [mod_imp(req_snake), ent_imp(req_snake)]
        if resp_pascal:  # datasource returns the response model
            dimports.append(mod_imp(resp_snake))
        ds = ('\n'.join(sorted(dimports)) + '\n\n'
              + "abstract interface class %sRemoteDataSource {\n" % fp
              + "  Future<%s> %s(%s);\n}\n\n" % (ret_model, mname, dom_decl_s)
              + "final class %sRemoteDataSourceImpl implements %sRemoteDataSource {\n"
              % (fp, fp)
              + "  %sRemoteDataSourceImpl(Dio dio) : _api = %sApi(dio);\n\n" % (fp, fp)
              + "  final %sApi _api;\n\n  @override\n" % fp
              + "  Future<%s> %s(%s) =>\n" % (ret_model, mname, dom_decl_s)
              + "      _api.%s(%s);\n}\n" % (mname, ', '.join(ds_call)))
        write_file(os.path.join(feature_dir, 'data', 'datasources',
                                feature + '_remote_data_source.dart'), ds)

        # repository contract
        rimports = [_imp(pkg, CORE_RESULT)]
        if has_body:
            rimports.append(ent_imp(req_snake))
        if resp_pascal:
            rimports.append(ent_imp(resp_snake))
        repo = ('\n'.join(sorted(rimports)) + '\n\n'
                + "abstract interface class %sRepository {\n" % fp
                + "  Future<Result<%s>> %s(%s);\n}\n" % (ret_entity, mname, dom_decl_s))
        write_file(os.path.join(feature_dir, 'domain', 'repositories',
                                feature + '_repository.dart'), repo)

        # use case
        ucimports = [_imp(pkg, CORE_RESULT),
                     "import 'package:%s/features/%s/domain/repositories/%s_repository.dart';"
                     % (pkg, feature, feature)]
        if has_body:
            ucimports.append(ent_imp(req_snake))
        if resp_pascal:
            ucimports.append(ent_imp(resp_snake))
        uc = ('\n'.join(sorted(ucimports)) + '\n\n'
              + 'class %s%sUseCase {\n' % (uc_prefix, fp)
              + '  const %s%sUseCase(this._repository);\n\n' % (uc_prefix, fp)
              + '  final %sRepository _repository;\n\n' % fp
              + '  Future<Result<%s>> call(%s) =>\n' % (ret_entity, dom_decl_s)
              + '      _repository.%s(%s);\n}\n' % (mname, dom_args_s))
        write_file(os.path.join(feature_dir, 'domain', 'usecases',
                                '%s_%s_use_case.dart' % (mname, feature)), uc)

        # repository impl
        if resp_pascal:
            success = ('      final model = await _remoteDataSource.%s(%s);\n'
                       '      return Success(model.toEntity());' % (mname, dom_args_s))
        else:
            success = ('      await _remoteDataSource.%s(%s);\n'
                       '      return const Success(true);' % (mname, dom_args_s))
        riimports = ["import 'package:dio/dio.dart';",
                     _imp(pkg, CORE_FAILURES),
                     _imp(pkg, CORE_RESULT),
                     _imp(pkg, CORE_ERRMAP),
                     "import 'package:%s/features/%s/data/datasources/%s_remote_data_source.dart';"
                     % (pkg, feature, feature),
                     "import 'package:%s/features/%s/domain/repositories/%s_repository.dart';"
                     % (pkg, feature, feature)]
        if has_body:
            riimports.append(ent_imp(req_snake))
        if resp_pascal:
            riimports.append(ent_imp(resp_snake))
        ri = ('\n'.join(sorted(riimports)) + '\n\n'
              + 'final class %sRepositoryImpl implements %sRepository {\n' % (fp, fp)
              + '  const %sRepositoryImpl(this._remoteDataSource);\n\n' % fp
              + '  final %sRemoteDataSource _remoteDataSource;\n\n' % fp
              + '  @override\n'
              + '  Future<Result<%s>> %s(%s) async {\n' % (ret_entity, mname, dom_decl_s)
              + '    try {\n' + success + '\n'
              + '    } on DioException catch (error) {\n'
              + '      return FailureResult(mapDioException(error));\n'
              + '    } on Object {\n'
              + "      return const FailureResult(\n"
              + "        UnknownFailure(message: 'common.unknown_error'),\n"
              + '      );\n    }\n  }\n}\n')
        write_file(os.path.join(feature_dir, 'data', 'repositories',
                                feature + '_repository_impl.dart'), ri)

        _gen_action_presentation(
            write_file, feature_dir, pkg, feature, fp, ip, stack,
            kind='command', uc_class='%s%sUseCase' % (uc_prefix, fp),
            uc_file='%s_%s' % (mname, feature), action='submit',
            p_decl=dom_decl_s, p_args=dom_args_s, item_type=None,
            param_snakes=[req_snake] if has_body else [])

    for p in created:
        print('  + %s' % p)


def _generate_get_by_id(write_file, feature_dir, pkg, feature, item, fp, ip,
                        path, idf, idt, stack):
    """Full fetch-by-id stack (client @GET/{id} + datasource/repo/usecase) plus
    a Bloc detail cubit. The entity/model were already built by the caller."""
    ient = lambda sn: ("import 'package:%s/features/%s/domain/entities/%s.dart';"
                       % (pkg, feature, sn))
    imod = lambda sn: ("import 'package:%s/features/%s/data/models/%s_model.dart';"
                       % (pkg, feature, sn))
    repo_imp = ("import 'package:%s/features/%s/domain/repositories/%s_repository.dart';"
                % (pkg, feature, feature))
    ddir = os.path.join(feature_dir, 'data', 'datasources')

    client = ('\n'.join(sorted(["import 'package:dio/dio.dart';", imod(item),
                                "import 'package:retrofit/retrofit.dart';"])) + '\n\n'
              + "part '%s_api.g.dart';\n\n@RestApi()\n" % feature
              + "abstract class %sApi {\n" % fp
              + "  factory %sApi(Dio dio, {String baseUrl}) = _%sApi;\n\n" % (fp, fp)
              + "  @GET('%s')\n" % path
              + "  Future<%sModel> getById(@Path('%s') %s %s);\n}\n" % (ip, idf, idt, idf))
    write_file(os.path.join(ddir, feature + '_api.dart'), client)

    ds = ('\n'.join(sorted([
        "import 'package:dio/dio.dart';",
        "import 'package:%s/features/%s/data/datasources/%s_api.dart';"
        % (pkg, feature, feature), imod(item)])) + '\n\n'
        + "abstract interface class %sRemoteDataSource {\n" % fp
        + "  Future<%sModel> fetchOne(%s %s);\n}\n\n" % (ip, idt, idf)
        + "final class %sRemoteDataSourceImpl implements %sRemoteDataSource {\n" % (fp, fp)
        + "  %sRemoteDataSourceImpl(Dio dio) : _api = %sApi(dio);\n\n" % (fp, fp)
        + "  final %sApi _api;\n\n  @override\n" % fp
        + "  Future<%sModel> fetchOne(%s %s) => _api.getById(%s);\n}\n" % (ip, idt, idf, idf))
    write_file(os.path.join(ddir, feature + '_remote_data_source.dart'), ds)

    repo = ('\n'.join(sorted([_imp(pkg, CORE_RESULT),
                              ient(item)])) + '\n\n'
            + "abstract interface class %sRepository {\n" % fp
            + "  Future<Result<%s>> getById(%s %s);\n}\n" % (ip, idt, idf))
    write_file(os.path.join(feature_dir, 'domain', 'repositories',
                            feature + '_repository.dart'), repo)

    uc = ('\n'.join(sorted([_imp(pkg, CORE_RESULT),
                            ient(item), repo_imp])) + '\n\n'
          + 'class Get%sByIdUseCase {\n' % fp
          + '  const Get%sByIdUseCase(this._repository);\n\n' % fp
          + '  final %sRepository _repository;\n\n' % fp
          + '  Future<Result<%s>> call(%s %s) =>\n' % (ip, idt, idf)
          + '      _repository.getById(%s);\n}\n' % idf)
    write_file(os.path.join(feature_dir, 'domain', 'usecases',
                            'get_%s_by_id_use_case.dart' % feature), uc)

    ri = ('\n'.join(sorted([
        "import 'package:dio/dio.dart';",
        _imp(pkg, CORE_FAILURES),
        _imp(pkg, CORE_RESULT),
        _imp(pkg, CORE_ERRMAP),
        "import 'package:%s/features/%s/data/datasources/%s_remote_data_source.dart';"
        % (pkg, feature, feature), ient(item), repo_imp])) + '\n\n'
        + 'final class %sRepositoryImpl implements %sRepository {\n' % (fp, fp)
        + '  const %sRepositoryImpl(this._remoteDataSource);\n\n' % fp
        + '  final %sRemoteDataSource _remoteDataSource;\n\n  @override\n' % fp
        + '  Future<Result<%s>> getById(%s %s) async {\n' % (ip, idt, idf)
        + '    try {\n'
        + '      final model = await _remoteDataSource.fetchOne(%s);\n' % idf
        + '      return Success(model.toEntity());\n'
        + '    } on DioException catch (error) {\n'
        + '      return FailureResult(mapDioException(error));\n'
        + '    } on Object {\n'
        + "      return const FailureResult(\n"
        + "        UnknownFailure(message: 'common.unknown_error'),\n"
        + '      );\n    }\n  }\n}\n')
    write_file(os.path.join(feature_dir, 'data', 'repositories',
                            feature + '_repository_impl.dart'), ri)

    _gen_action_presentation(
        write_file, feature_dir, pkg, feature, fp, ip, stack,
        kind='detail', uc_class='Get%sByIdUseCase' % fp,
        uc_file='get_%s_by_id' % feature, action='load',
        p_decl='%s %s' % (idt, idf), p_args=idf, item_type=ip,
        param_snakes=[], item_snake=item)


def _gen_action_presentation(write_file, fd, pkg, feature, fp, ip, stack, *,
                             kind, uc_class, uc_file, action, p_decl, p_args,
                             item_type, param_snakes, item_snake=None):
    """Single-action presentation (command `submit(...)` or detail `load(id)`)
    for any stack. State = status (+ item for detail) + errorMessage."""
    busy = 'submitting' if kind == 'command' else 'loading'
    detail = kind == 'detail'
    ient = lambda sn: ("import 'package:%s/features/%s/domain/entities/%s.dart';"
                       % (pkg, feature, sn))
    uc_imp = ("import 'package:%s/features/%s/domain/usecases/%s_use_case.dart';"
              % (pkg, feature, uc_file))
    di_imp = _imp(pkg, CORE_DI)
    res_imp = _imp(pkg, CORE_RESULT)
    cb = os.path.join(fd, 'presentation', 'cubit')
    nt = os.path.join(fd, 'presentation', 'notifier')
    ct = os.path.join(fd, 'presentation', 'controller')
    st = os.path.join(fd, 'presentation', 'store')
    pg = os.path.join(fd, 'presentation', 'pages')
    ent_imps = [ient(s) for s in param_snakes] + ([ient(item_snake)] if detail else [])
    statuses = 'initial, %s, success, failure' % busy
    # how the page invokes the action: detail loads on open; command via a button.
    if detail:
        result_ok = ' item: data'
        succ_bind = '(:final data)'
    else:
        result_ok = ''
        succ_bind = '()'

    if stack == 'bloc':
        imps = sorted([res_imp, uc_imp,
                       "import 'package:equatable/equatable.dart';",
                       "import 'package:flutter_bloc/flutter_bloc.dart';"] + ent_imps)
        cubit = ('\n'.join(imps) + '\n\n' + "part '%s_state.dart';\n\n" % feature
                 + 'final class %sCubit extends Cubit<%sState> {\n' % (fp, fp)
                 + '  %sCubit(this._useCase) : super(const %sState());\n\n' % (fp, fp)
                 + '  final %s _useCase;\n\n' % uc_class
                 + '  Future<void> %s(%s) async {\n' % (action, p_decl)
                 + '    emit(state.copyWith(status: %sStatus.%s));\n' % (fp, busy)
                 + '    final result = await _useCase(%s);\n' % p_args
                 + '    switch (result) {\n      case Success%s:\n' % succ_bind
                 + '        emit(state.copyWith(status: %sStatus.success,%s));\n'
                 % (fp, result_ok)
                 + '      case FailureResult(:final failure):\n'
                 + '        emit(\n          state.copyWith(\n'
                 + '            status: %sStatus.failure,\n' % fp
                 + '            errorMessage: failure.message,\n          ),\n        );\n    }\n  }\n}\n')
        write_file(os.path.join(cb, feature + '_cubit.dart'), cubit)
        itemf = '  final %s? item;\n' % item_type if detail else ''
        itemp = '%s? item, ' % item_type if detail else ''
        itemc = '      item: item ?? this.item,\n' if detail else ''
        props = '[status, item, errorMessage]' if detail else '[status, errorMessage]'
        state = ("part of '%s_cubit.dart';\n\n" % feature
                 + 'enum %sStatus { %s }\n\n' % (fp, statuses)
                 + 'final class %sState extends Equatable {\n' % fp
                 + '  const %sState({this.status = %sStatus.initial,%s this.errorMessage});\n\n'
                 % (fp, fp, ' this.item,' if detail else '')
                 + '  final %sStatus status;\n' % fp + itemf
                 + '  final String? errorMessage;\n\n'
                 + '  %sState copyWith({%sStatus? status, %sString? errorMessage}) {\n'
                 % (fp, fp, itemp)
                 + '    return %sState(\n      status: status ?? this.status,\n' % fp
                 + itemc + '      errorMessage: errorMessage,\n    );\n  }\n\n'
                 + '  @override\n  List<Object?> get props => %s;\n}\n' % props)
        write_file(os.path.join(cb, feature + '_state.dart'), state)
        _action_page(write_file, pg, pkg, feature, fp, ip, 'bloc', detail, busy)

    elif stack == 'provider':
        imps = sorted([res_imp, uc_imp,
                       "import 'package:flutter/foundation.dart';"] + ent_imps)
        itemf = '  %s? item;\n' % item_type if detail else ''
        body = ('\n'.join(imps) + '\n\n'
                + 'enum %sStatus { %s }\n\n' % (fp, statuses)
                + 'class %sNotifier extends ChangeNotifier {\n' % fp
                + '  %sNotifier(this._useCase);\n\n  final %s _useCase;\n\n' % (fp, uc_class)
                + '  %sStatus status = %sStatus.initial;\n' % (fp, fp) + itemf
                + '  String? errorMessage;\n\n'
                + '  Future<void> %s(%s) async {\n' % (action, p_decl)
                + '    status = %sStatus.%s;\n    errorMessage = null;\n    notifyListeners();\n' % (fp, busy)
                + '    final result = await _useCase(%s);\n' % p_args
                + '    switch (result) {\n      case Success%s:\n' % succ_bind
                + ('        item = data;\n' if detail else '')
                + '        status = %sStatus.success;\n' % fp
                + '      case FailureResult(:final failure):\n'
                + '        errorMessage = failure.message;\n        status = %sStatus.failure;\n' % fp
                + '    }\n    notifyListeners();\n  }\n}\n')
        write_file(os.path.join(nt, feature + '_notifier.dart'), body)
        _action_page(write_file, pg, pkg, feature, fp, ip, 'provider', detail, busy)

    elif stack == 'getx':
        imps = sorted([res_imp, uc_imp, "import 'package:get/get.dart';"] + ent_imps)
        itemf = '  final Rxn<%s> item = Rxn<%s>();\n' % (item_type, item_type) if detail else ''
        body = ('\n'.join(imps) + '\n\n'
                + 'enum %sStatus { %s }\n\n' % (fp, statuses)
                + 'class %sController extends GetxController {\n' % fp
                + '  %sController(this._useCase);\n\n  final %s _useCase;\n\n' % (fp, uc_class)
                + '  final Rx<%sStatus> status = %sStatus.initial.obs;\n' % (fp, fp) + itemf
                + '  final RxnString errorMessage = RxnString();\n\n'
                + '  Future<void> %s(%s) async {\n' % (action, p_decl)
                + '    status.value = %sStatus.%s;\n    errorMessage.value = null;\n' % (fp, busy)
                + '    final result = await _useCase(%s);\n' % p_args
                + '    switch (result) {\n      case Success%s:\n' % succ_bind
                + ('        item.value = data;\n' if detail else '')
                + '        status.value = %sStatus.success;\n' % fp
                + '      case FailureResult(:final failure):\n'
                + '        errorMessage.value = failure.message;\n        status.value = %sStatus.failure;\n' % fp
                + '    }\n  }\n}\n')
        write_file(os.path.join(ct, feature + '_controller.dart'), body)
        _action_page(write_file, pg, pkg, feature, fp, ip, 'getx', detail, busy)

    elif stack == 'mobx':
        imps = sorted([res_imp, uc_imp, "import 'package:mobx/mobx.dart';"] + ent_imps)
        itemf = '  @observable\n  %s? item;\n\n' % item_type if detail else ''
        body = ('\n'.join(imps) + '\n\n' + "part '%s_store.g.dart';\n\n" % feature
                + 'enum %sStatus { %s }\n\n' % (fp, statuses)
                + '// The MobX `Store = _StoreBase with _$Store` typedef references the\n'
                + '// private base intentionally.\n'
                + '// ignore: library_private_types_in_public_api\n'
                + 'class %sStore = ___%sStore with _$%sStore;\n\n'.replace('___', '_')
                % (fp, fp, fp)
                + 'abstract class _%sStore with Store {\n' % fp
                + '  _%sStore(this._useCase);\n\n  final %s _useCase;\n\n' % (fp, uc_class)
                + '  @observable\n  %sStatus status = %sStatus.initial;\n\n' % (fp, fp) + itemf
                + '  @observable\n  String? errorMessage;\n\n  @action\n'
                + '  Future<void> %s(%s) async {\n' % (action, p_decl)
                + '    status = %sStatus.%s;\n    errorMessage = null;\n' % (fp, busy)
                + '    final result = await _useCase(%s);\n' % p_args
                + '    switch (result) {\n      case Success%s:\n' % succ_bind
                + ('        item = data;\n' if detail else '')
                + '        status = %sStatus.success;\n' % fp
                + '      case FailureResult(:final failure):\n'
                + '        errorMessage = failure.message;\n        status = %sStatus.failure;\n' % fp
                + '    }\n  }\n}\n')
        write_file(os.path.join(st, feature + '_store.dart'), body)
        _action_page(write_file, pg, pkg, feature, fp, ip, 'mobx', detail, busy)

    elif stack == 'riverpod':
        fcamel = fp[0].lower() + fp[1:]
        uc_camel = uc_class[0].lower() + uc_class[1:]
        ds_imp = ("import 'package:%s/features/%s/data/datasources/%s_remote_data_source.dart';"
                  % (pkg, feature, feature))
        repo_imp = ("import 'package:%s/features/%s/domain/repositories/%s_repository.dart';"
                    % (pkg, feature, feature))
        repoimpl_imp = ("import 'package:%s/features/%s/data/repositories/%s_repository_impl.dart';"
                        % (pkg, feature, feature))
        imps = sorted([res_imp, uc_imp, ds_imp, repo_imp, repoimpl_imp,
                       _dio_import(pkg),
                       "import 'package:equatable/equatable.dart';",
                       "import 'package:riverpod_annotation/riverpod_annotation.dart';"]
                      + ent_imps)
        itemf = '  final %s? item;\n' % item_type if detail else ''
        itemp = '%s? item, ' % item_type if detail else ''
        itemc = '      item: item ?? this.item,\n' if detail else ''
        props = '[status, item, errorMessage]' if detail else '[status, errorMessage]'
        nb = ('\n'.join(imps) + '\n\n' + "part '%s_notifier.g.dart';\n\n" % feature
              + 'enum %sStatus { %s }\n\n' % (fp, statuses)
              + 'final class %sState extends Equatable {\n' % fp
              + '  const %sState({this.status = %sStatus.initial,%s this.errorMessage});\n\n'
              % (fp, fp, ' this.item,' if detail else '')
              + '  final %sStatus status;\n' % fp + itemf + '  final String? errorMessage;\n\n'
              + '  %sState copyWith({%sStatus? status, %sString? errorMessage}) {\n'
              % (fp, fp, itemp)
              + '    return %sState(\n      status: status ?? this.status,\n' % fp + itemc
              + '      errorMessage: errorMessage,\n    );\n  }\n\n'
              + '  @override\n  List<Object?> get props => %s;\n}\n\n' % props
              + '@riverpod\n%sRemoteDataSource %sRemoteDataSource(Ref ref) =>\n'
              % (fp, fcamel)
              + '    %sRemoteDataSourceImpl(%s);\n\n' % (fp, _dio_expr())
              + '@riverpod\n%sRepository %sRepository(Ref ref) =>\n' % (fp, fcamel)
              + '    %sRepositoryImpl(ref.watch(%sRemoteDataSourceProvider));\n\n' % (fp, fcamel)
              + '@riverpod\n%s %s(Ref ref) =>\n' % (uc_class, uc_camel)
              + '    %s(ref.watch(%sRepositoryProvider));\n\n' % (uc_class, fcamel)
              + '@riverpod\nclass %sNotifier extends _$%sNotifier {\n' % (fp, fp)
              + '  @override\n  %sState build() => const %sState();\n\n' % (fp, fp)
              + '  Future<void> %s(%s) async {\n' % (action, p_decl)
              + '    state = state.copyWith(status: %sStatus.%s);\n' % (fp, busy)
              + '    final result = await ref.read(%sProvider)(%s);\n' % (uc_camel, p_args)
              + '    switch (result) {\n      case Success%s:\n' % succ_bind
              + '        state = state.copyWith(status: %sStatus.success,%s);\n' % (fp, result_ok)
              + '      case FailureResult(:final failure):\n'
              + '        state = state.copyWith(\n          status: %sStatus.failure,\n' % fp
              + '          errorMessage: failure.message,\n        );\n    }\n  }\n}\n')
        write_file(os.path.join(nt, feature + '_notifier.dart'), nb)
        _action_page(write_file, pg, pkg, feature, fp, ip, 'riverpod', detail, busy)


def _action_page(write_file, pg, pkg, feature, fp, ip, stack, detail, busy):
    """Status-driven page (line-list build to avoid literal/%-concat pitfalls).
    Detail loads on open; command shows a submit-button stub."""
    el = "import 'package:easy_localization/easy_localization.dart';"
    di = _imp(pkg, CORE_DI)
    fm = "import 'package:flutter/material.dart';"

    def switch_lines(status, item, err):
        L = ['          switch (%s) {' % status,
             '            case %sStatus.initial:' % fp]
        if not detail:
            L += ['              return Center(',
                  '                child: ElevatedButton(',
                  '                  onPressed: () {',
                  '                    // TODO(you): collect inputs, then call the action.',
                  '                  },',
                  "                  child: Text('" + feature + ".submit'.tr()),",
                  '                ),',
                  '              );']
        L += ['            case %sStatus.%s:' % (fp, busy),
              '              return const Center(child: CircularProgressIndicator());',
              '            case %sStatus.failure:' % fp,
              '              return Center(',
              "                child: Text((" + err + " ?? 'common.unknown_error').tr()),",
              '              );',
              '            case %sStatus.success:' % fp]
        if detail:
            L += ['              final item = ' + item + ';',
                  '              if (item == null) return const SizedBox.shrink();',
                  "              return Center(child: Text('#${item.id}'));"]
        else:
            L += ["              return Center(child: Text('" + feature + ".success'.tr()));"]
        return L + ['          }']

    out = []
    if stack in ('bloc', 'provider'):
        if stack == 'bloc':
            prov_imp = "import 'package:flutter_bloc/flutter_bloc.dart';"
            hub = ("import 'package:%s/features/%s/presentation/cubit/%s_cubit.dart';"
                   % (pkg, feature, feature))
            holder, provw = '%sCubit' % fp, 'BlocProvider'
            consumer, sig = 'BlocBuilder<%sCubit, %sState>' % (fp, fp), '(context, state)'
        else:
            prov_imp = "import 'package:provider/provider.dart';"
            hub = ("import 'package:%s/features/%s/presentation/notifier/%s_notifier.dart';"
                   % (pkg, feature, feature))
            holder, provw = '%sNotifier' % fp, 'ChangeNotifierProvider'
            consumer, sig = 'Consumer<%sNotifier>' % fp, '(context, state, _)'
        imps = [el, di, hub, fm, prov_imp] + (["import 'dart:async';"] if detail else [])
        out += sorted(imps) + ['']
        out.append('class %sPage extends StatelessWidget {' % fp)
        out += (['  const %sPage({required this.id, super.key});' % fp, '',
                 '  final String id;', ''] if detail
                else ['  const %sPage({super.key});' % fp, ''])
        out += ['  @override', '  Widget build(BuildContext context) {',
                '    return %s(' % provw]
        if detail:
            out += ['      create: (_) {',
                    '        final holder = getIt<%s>();' % holder,
                    '        unawaited(holder.load(id));',
                    '        return holder;', '      },']
        else:
            out.append('      create: (_) => getIt<%s>(),' % holder)
        out += ['      child: const %sView(),' % fp, '    );', '  }', '}', '',
                'class %sView extends StatelessWidget {' % fp,
                '  const %sView({super.key});' % fp, '',
                '  @override', '  Widget build(BuildContext context) {',
                '    return Scaffold(',
                "      appBar: AppBar(title: Text('" + feature + ".title'.tr())),",
                '      body: %s(' % consumer, '        builder: %s {' % sig]
        out += switch_lines('state.status', 'state.item', 'state.errorMessage')
        out += ['        },', '      ),', '    );', '  }', '}']

    elif stack in ('getx', 'mobx'):
        if stack == 'getx':
            hub = ("import 'package:%s/features/%s/presentation/controller/%s_controller.dart';"
                   % (pkg, feature, feature))
            react = "import 'package:get/get.dart' hide Trans;"
            holder = '%sController' % fp
            status, item, err = '_h.status.value', '_h.item.value', '_h.errorMessage.value'
        else:
            hub = ("import 'package:%s/features/%s/presentation/store/%s_store.dart';"
                   % (pkg, feature, feature))
            react = "import 'package:flutter_mobx/flutter_mobx.dart';"
            holder = '%sStore' % fp
            status, item, err = '_h.status', '_h.item', '_h.errorMessage'
        out += sorted([el, di, hub, fm, react]) + ['']
        out.append('class %sPage extends StatefulWidget {' % fp)
        out += (['  const %sPage({required this.id, super.key});' % fp, '',
                 '  final String id;', ''] if detail
                else ['  const %sPage({super.key});' % fp, ''])
        out += ['  @override',
                '  State<%sPage> createState() => _PageState();' % fp, '}', '',
                'class _PageState extends State<%sPage> {' % fp]
        out.append('  late final %s _h = getIt<%s>()%s;'
                   % (holder, holder, '..load(widget.id)' if detail else ''))
        out += ['', '  @override', '  Widget build(BuildContext context) {',
                '    return Scaffold(',
                "      appBar: AppBar(title: Text('" + feature + ".title'.tr())),"]
        if stack == 'getx':
            out.append('      body: Obx(() {')
            out += switch_lines(status, item, err)
            out += ['      }),', '    );', '  }', '}']
        else:
            out += ['      body: Observer(', '        builder: (context) {']
            out += switch_lines(status, item, err)
            out += ['        },', '      ),', '    );', '  }', '}']

    else:  # riverpod
        fcamel = fp[0].lower() + fp[1:]
        hub = ("import 'package:%s/features/%s/presentation/notifier/%s_notifier.dart';"
               % (pkg, feature, feature))
        fr = "import 'package:flutter_riverpod/flutter_riverpod.dart';"
        if detail:
            out += sorted(["import 'dart:async';", el, hub, fm, fr]) + ['']
            out += ['class %sPage extends ConsumerStatefulWidget {' % fp,
                    '  const %sPage({required this.id, super.key});' % fp, '',
                    '  final String id;', '', '  @override',
                    '  ConsumerState<%sPage> createState() => _PageState();' % fp,
                    '}', '',
                    'class _PageState extends ConsumerState<%sPage> {' % fp,
                    '  @override', '  void initState() {', '    super.initState();',
                    '    unawaited(ref.read(%sProvider.notifier).load(widget.id));' % fcamel,
                    '  }', '', '  @override',
                    '  Widget build(BuildContext context) {',
                    '    final state = ref.watch(%sProvider);' % fcamel]
        else:
            out += sorted([el, hub, fm, fr]) + ['']
            out += ['class %sPage extends ConsumerWidget {' % fp,
                    '  const %sPage({super.key});' % fp, '', '  @override',
                    '  Widget build(BuildContext context, WidgetRef ref) {',
                    '    final state = ref.watch(%sProvider);' % fcamel]
        out += ['    return Scaffold(',
                "      appBar: AppBar(title: Text('" + feature + ".title'.tr())),",
                '      body: Builder(', '        builder: (context) {']
        out += switch_lines('state.status', 'state.item', 'state.errorMessage')
        out += ['        },', '      ),', '    );', '  }', '}']

    write_file(os.path.join(pg, feature + '_page.dart'), '\n'.join(out) + '\n')


def _patch_riverpod(feature_dir, feature, fp, pkg):
    nf = os.path.join(feature_dir, 'presentation', 'notifier',
                      feature + '_notifier.dart')
    if not os.path.exists(nf):
        return
    src = open(nf).read()
    src = src.replace('const %sRemoteDataSourceImpl()' % fp,
                      '%sRemoteDataSourceImpl(%s)' % (fp, _dio_expr()))
    imp = _dio_import(pkg)
    if imp not in src:
        src = src.replace(
            "import 'package:riverpod_annotation/riverpod_annotation.dart';",
            imp + "\n"
            "import 'package:riverpod_annotation/riverpod_annotation.dart';", 1)
        src = _sort_import_block(src)
    open(nf, 'w').write(src)


if __name__ == '__main__':
    main()
