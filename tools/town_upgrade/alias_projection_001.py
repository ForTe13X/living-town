"""Finite, measured RNA-reference alias projection; no state exclusions.

The table contains exact paths from root-run Blender5.2.2 measurements. Each
path is tied to its authored node and socket identities. Live before/after
snapshots are compared in full within the SAME process. Historical raw states
are evidence, never cross-session appearance baselines.
"""
from __future__ import annotations
import copy
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
TABLE_SHA = '2691ac9303fc377e273f76ef7a50bd91aff2e315c64cac6bf85f2bb86879314a'
SCHEMA = 'living_town.exact_material_rna_alias_paths.v1'


def need(value, message):
    if not value: raise ValueError(message)


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False).encode('utf-8')


def digest(value): return hashlib.sha256(encoded(value)).hexdigest()


def sha(path):
    with Path(path).open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def binding(path):
    path = Path(path).resolve(strict=True)
    return {'path': str(path), 'bytes': path.stat().st_size, 'sha256': sha(path)}


def verify(row):
    need(binding(row['path']) == row, 'Measured alias source bytes differ: ' + row['path'])


def tokens(path):
    need(path.startswith('/') and path != '/', 'Exact non-root JSON pointer required')
    return [part.replace('~1', '/').replace('~0', '~') for part in path.split('/')[1:]]


def at(value, path):
    for key in tokens(path):
        if isinstance(value, list):
            need(key.isdigit() and str(int(key)) == key and int(key) < len(value), 'Exact alias list index differs: ' + path)
            value = value[int(key)]
        else:
            need(isinstance(value, dict) and key in value, 'Exact alias object path differs: ' + path)
            value = value[key]
    return value


def assign(value, path, replacement):
    keys = tokens(path); parent = value
    for key in keys[:-1]: parent = parent[int(key)] if isinstance(parent, list) else parent[key]
    parent[int(keys[-1]) if isinstance(parent, list) else keys[-1]] = replacement


def model():
    path = HERE / 'alias_paths_001.json'
    need(sha(path) == TABLE_SHA, 'Exact measured alias table differs')
    result = json.loads(path.read_text(encoding='utf-8'))
    need(result['schema'] == SCHEMA and set(result['models']) == {'wood_uv', 'grass_specular'}, 'Alias model schema differs')
    for name, count, authors in [('wood_uv', 66, 15), ('grass_specular', 35, 1)]:
        part = result['models'][name]
        need(len(part['paths']) == count and len({row['path'] for row in part['paths']}) == count and len(part['authors']) == authors,
             'Exact finite alias/author count differs: ' + name)
    return result


def evidence_bindings(table=None):
    table = model() if table is None else table
    rows = table['sources']
    for row in rows.values(): verify(row)
    return {**rows, str(Path(__file__).resolve()): binding(__file__),
            str((HERE / 'alias_paths_001.json').resolve()): binding(HERE / 'alias_paths_001.json')}


def expected(before, name, table=None):
    """Project only measured finite aliases after proving owning identities."""
    table = model() if table is None else table
    need(name in table['models'], 'Unregistered material alias model')
    part = table['models'][name]; wanted = copy.deepcopy(before)
    for row in part['paths']:
        need(encoded(at(before, row['path'])) == encoded(row['old']), 'Actual original alias value differs: ' + row['path'])
        for guard in row['identity_guards']:
            obj = at(before, guard['path'])
            need(isinstance(obj, dict) and all(key in obj and encoded(obj[key]) == encoded(value) for key, value in guard['identity'].items()),
                 'Actual alias owner/socket identity differs: ' + guard['path'])
        assign(wanted, row['path'], row['new'])
    return wanted


def check(before, after, name, table=None):
    table = model() if table is None else table
    wanted = expected(before, name, table)
    need(encoded(wanted) == encoded(after), 'Material/node/socket/image/mapping/link state differs beyond exact measured aliases: ' + name)
    return {'status': 'EXACT_AUTHORED_FIELDS_AND_ALL_MEASURED_RNA_ALIASES_ONLY',
            'authored_field_count': len(table['models'][name]['authors']),
            'serialized_changed_path_count': len(table['models'][name]['paths']),
            'model_source': binding(__file__), 'path_table': binding(HERE / 'alias_paths_001.json'),
            'whole_live_before_sha256': digest(before), 'whole_live_after_sha256': digest(after),
            'expected_live_after_sha256': digest(wanted), 'ignored_or_normalized_state': [],
            'cross_session_raw_state_equality_claim': False}


def permitted_material_delta(before, after, fields):
    table = model(); registered = table['models']['wood_uv']['authors']
    need(encoded(sorted(fields, key=lambda x: (x['material'], x['node']))) == encoded(registered),
         'Exact original fifteen authored UV fields differ')
    result = check(before, after, 'wood_uv', table)
    result.update(materials=sorted({row['material'] for row in fields}), fields=fields,
                  KHR_mapping_or_pixels_changed=False,
                  status='EXACT_15_UV_NAME_FIELDS_AND_66_MEASURED_SERIALIZED_PATHS_ONLY')
    return result


def specular_delta(before, after, material, node, old, new):
    table = model(); author = table['models']['grass_specular']['authors'][0]
    need(encoded({'material': material, 'node': node, 'socket': 'Specular IOR Level', 'old': old, 'new': new}) == encoded(author),
         'Exact measured source scalar/node/socket differs')
    result = check(before, after, 'grass_specular', table)
    result.update(material=material, node=node, socket='Specular IOR Level', old=old, new=new,
                  status='EXACT_ONE_SCALAR_AND_35_MEASURED_SERIALIZED_PATHS_ONLY')
    return result
