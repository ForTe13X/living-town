"""Unpromoted, unsaved two-material leaf-mask composition adapter.

Call check_payload, preflight_native, then apply from an owned compositor.
Only four authored values may change: each existing leaf material's one
GREATER_THAN input and matching alpha_cutoff metadata. No new datablocks,
binding changes, geometry edits, save, render, export or image decoding.
The consumer must retain its whole-native geometry/placement preservation
guard and perform final portable/Godot integration; this module does not
authorize adoption from the Material Preview evidence alone.
"""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
from types import FunctionType

LEAVES = ('Botanical_Broadleaf', 'Botanical_Pine_Needles')
SOURCE_THRESHOLD = 0.44999998807907104  # Actual float32 RNA .45 storage.
RNA_SHA = 'b1d99d0d4db0f7968646973b0fc3e3df5506f3fbfd51b3cecb0cf66c9dc40ab1'
GUI_SHA = 'fb8b9f5614690afaf2a859b8c9a7016ffa022b51028f7a4a43bfb702de0f7d38'
ENTRY_HELPER_SHA = '7cb64f0a0f25e92c59a693eb4271cb8b9c8e4a847603a9ce9d486a1975f6e0b5'
ALIAS_SOURCE_SHA = '70b5b9aeed6af2c29334fc5ffdec01e9f15a90aa2b1294ef65a7bbfe6f3785b7'
ALIAS_NATIVE_SHA = 'f5354b15ebae1980892cd228e52d54bc6d576aab33d21f68476dfc34e8b56279'
ALIAS_REPORT_SHA = '8662301b6220f85a274c955ab8d9531e72d97ad85b98dc3ca7a3e126fb290656'
PORTABLE_CHECK_SHA = '988b8ac422f55ad589bba563100fe63f22ca4b3a3119277eac4fc756f9925bf0'
PORTABLE_EXPORT_SHA = 'c7d9d33d9c9ff01f15cf2c90510ab5aaab8336eb74b39fc86768706b155a8681'
GUI_STATUS = 'ACTUAL_WHOLE_TOWN_CUTOFF_AB_SOURCE_PRESERVED_ART_PENDING'


def need(value, message):
    if not value:
        raise ValueError(message)


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'),
                                     ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def binding(path):
    path = Path(path).resolve(strict=True)
    return {'path': str(path), 'bytes': path.stat().st_size, 'sha256': sha(path)}


def verify(row):
    need(binding(row['path']) == row, 'Bound evidence/source changed: ' + row['path'])


def check_payload(rna_path, gui_report_path, alias_folder, portable_folder):
    """Pins completed evidence, never treats art/integration as already approved."""
    need(sha(rna_path) == RNA_SHA and sha(gui_report_path) == GUI_SHA, 'Pinned actual RNA/GUI receipt differs')
    rna = json.loads(Path(rna_path).read_text(encoding='utf-8'))
    gui = json.loads(Path(gui_report_path).read_text(encoding='utf-8'))
    need(gui['status'] == GUI_STATUS and not gui['failures'] and gui['saved'] is False
         and gui['exported'] is False and gui['installed'] is False, 'GUI diagnostic scope/status differs')
    expected_cases = ['A_mask045_core', 'B_mask025_core', 'A_mask045_overview', 'B_mask025_overview']
    need([row['name'] for row in gui['cases']] == expected_cases
         and [row['case'] for row in gui['screenshots']] == expected_cases, 'Four actual paired views required')
    need(gui['native_before'] == gui['native_after'] and gui['all_original_slots_restored'] is True
         and gui['geometry_before']['sha256'] == gui['geometry_after_sha256']
         and all(value == 'PASS' for value in gui['cleanup_stages'].values()), 'Actual source preservation failed')
    need(gui['leaf_user_counts'] == {'mesh_slots': 10, 'object_slots': 6711}, 'Actual GUI leaf-user inventory differs')
    artifacts = [gui['all_leaf_users']]
    for row in gui['screenshots']:
        need(row['kind'] == 'ACTUAL_EXISTING_VIEW_3D_EDITOR_SCREENSHOT', 'Synthetic/substituted GUI evidence')
        artifacts.append(row['file'])
    for row in artifacts:
        verify(row)
    need(rna['placement_count'] == 30176 and rna['unique_mesh_count'] == 36
         and len(rna['images']) == 30, 'Pinned botanical source inventory differs')
    aliases = check_alias_payload(alias_folder, ALIAS_REPORT_SHA)
    portable_folder = Path(portable_folder).resolve(strict=True)
    portable_check = portable_folder / 'core_mask_check.json'
    portable_export = portable_folder / 'portable_cutoff_export.json'
    need(sha(portable_check) == PORTABLE_CHECK_SHA and sha(portable_export) == PORTABLE_EXPORT_SHA,
         'Pinned actual tiny core MASK export/check differs')
    portable = json.loads(portable_check.read_text(encoding='utf-8'))
    need(portable['status'] == 'CORE_GLTF_MASK025_ORIGINAL_RGBA_PASS'
         and portable['export_report_sha256'] == PORTABLE_EXPORT_SHA
         and len(portable['leaf_materials']) == 2
         and all(row['alphaMode'] == 'MASK' and row['alphaCutoff'] == .25 for row in portable['leaf_materials']),
         'Actual tiny core MASK025 check did not pass')
    verify(portable['glb'])
    artifacts.extend([binding(portable_check), binding(portable_export), portable['glb']])
    return {'rna_binding': binding(rna_path), 'gui_binding': binding(gui_report_path), 'aliases': aliases,
            'artifacts': artifacts, 'rna': rna, 'gui': gui,
            'scope': 'Two-pose Material Preview improvement and tiny core MASK025 original RGBA pass; Godot/final native art adoption pending'}


def structured_materials(bpy, E):
    """Exact frozen whole-material RNA graph, with digest replaced by identity."""
    need(sha(E.__file__) == ENTRY_HELPER_SHA, 'Frozen entry material snapshot helper differs')
    fn = FunctionType(E._materials.__code__, {**E._materials.__globals__, '_digest': lambda value: value})
    return fn(bpy)


def source_leaf_record(material):
    """The exact material-record schema used by the pinned actual RNA receipt."""
    def plain(value):
        if isinstance(value, (str, int, float, bool)) or value is None:
            return value
        return [plain(item) for item in value]
    def fields(owner, names):
        return {name: plain(getattr(owner, name)) for name in names if hasattr(owner, name)}
    result = fields(material, ('diffuse_color', 'surface_render_method', 'use_backface_culling',
                               'use_backface_culling_shadow', 'use_backface_culling_lightprobe_volume',
                               'thickness_mode', 'use_thickness_from_shadow', 'max_vertex_displacement'))
    result['custom'] = {key: plain(value) for key, value in material.items()}
    result['nodes'] = []
    need(material.node_tree is not None, 'Leaf material has no authored graph')
    for node in material.node_tree.nodes:
        row = {'name': node.name, 'type': node.bl_idname,
               'parameters': fields(node, ('operation', 'blend_type', 'space', 'uv_map', 'from_instancer',
                   'projection', 'projection_blend', 'interpolation', 'extension', 'invert',
                   'attribute_name', 'attribute_type', 'mute')), 'inputs': []}
        if hasattr(node, 'image'):
            row['image'] = node.image.name if node.image else None
        for socket in node.inputs:
            item = {'name': socket.name, 'identifier': socket.identifier, 'is_linked': socket.is_linked}
            if hasattr(socket, 'default_value'):
                item['default_value'] = plain(socket.default_value)
            row['inputs'].append(item)
        result['nodes'].append(row)
    result['links'] = [[link.from_node.name, link.from_socket.name, link.to_node.name, link.to_socket.name]
                       for link in material.node_tree.links]
    return result


def declared_fields(source_records):
    fields = []
    for name in LEAVES:
        record = source_records[name]
        need(record['custom'].get('alpha_mode') == 'MASK' and record['custom'].get('alpha_cutoff') == .45,
             'Original leaf MASK metadata differs: ' + name)
        nodes = [node for node in record['nodes'] if node['type'] == 'ShaderNodeMath'
                 and node['parameters'].get('operation') == 'GREATER_THAN']
        need(len(nodes) == 1, 'Exactly one leaf GREATER_THAN is required: ' + name)
        node = nodes[0]
        need(node['inputs'][0]['is_linked'] and not node['inputs'][1]['is_linked']
             and node['inputs'][1]['identifier'] == 'Value_001'
             and node['inputs'][1]['default_value'] == SOURCE_THRESHOLD, 'Original binary mask differs: ' + name)
        fields.append({'material': name, 'node': node['name'], 'socket_index': 1,
                       'socket_identifier': 'Value_001', 'before': SOURCE_THRESHOLD, 'after': .25,
                       'metadata': 'alpha_cutoff', 'metadata_before': .45, 'metadata_after': .25})
    return fields


def difference_rows(before, after, path=()):
    need(type(before) is type(after), 'Alias fixture changed a structured schema type')
    if isinstance(before, dict):
        need(before.keys() == after.keys(), 'Alias fixture changed a structured key set')
        return [row for key in before for row in difference_rows(before[key], after[key], (*path, key))]
    if isinstance(before, (list, tuple)):
        need(len(before) == len(after), 'Alias fixture changed a structured array length')
        return [row for index in range(len(before)) for row in difference_rows(before[index], after[index], (*path, index))]
    return [] if before == after else [{'path': list(path), 'before': before, 'after': after}]


def project_aliases(before, rows):
    """Finite measured paths only: no recursive field-name/value exemption."""
    wanted = copy.deepcopy(before)
    seen = set()
    for row in rows:
        path = row['path']
        need(path and path[0] in LEAVES and all(type(key) in (str, int) for key in path)
             and tuple(path) not in seen and row['after'] == .25
             and row['before'] in (.45, SOURCE_THRESHOLD), 'Invalid/duplicate measured cutoff alias')
        seen.add(tuple(path))
        owner = wanted
        for key in path[:-1]:
            need((isinstance(owner, dict) and type(key) is str and key in owner)
                 or (isinstance(owner, (list, tuple)) and type(key) is int and 0 <= key < len(owner)),
                 'Measured cutoff alias path no longer exists')
            owner = owner[key]
        key = path[-1]
        need((isinstance(owner, dict) and type(key) is str and key in owner)
             or (isinstance(owner, list) and type(key) is int and 0 <= key < len(owner)), 'Measured cutoff alias target differs')
        need(type(owner[key]) is type(row['before']) and owner[key] == row['before'], 'Measured cutoff alias source value differs')
        owner[key] = row['after']
    return wanted


def alias_contract(before, after, rows, owners):
    """Measurement comes from four actual writes in one pinned tiny process."""
    need(set(before) == set(after) == set(LEAVES), 'Alias fixture material inventory differs')
    need(rows == difference_rows(before, after), 'Complete actual alias diff differs from before/after graphs')
    need(len(rows) == 18 and len(owners) == 2 and tuple(row['material'] for row in owners) == LEAVES,
         'Exact eighteen aliases/two authored owners required')
    for owner in owners:
        need(owner['node'] == 'Math' and owner['socket_identifier'] == 'Value_001'
             and owner['threshold_before'] == SOURCE_THRESHOLD and owner['threshold_after'] == .25
             and owner['metadata_before'] == .45 and owner['metadata_after'] == .25
             and type(owner['socket_identity']) is int and owner['socket_identity'] > 0
             and type(owner['material_identity']) is int and owner['material_identity'] > 0,
             'Actual source-owned cutoff mutation differs')
    need(len({row['socket_identity'] for row in owners}) == 2, 'Measured leaf sockets unexpectedly share identity')
    for name in LEAVES:
        need(sum(row['path'] == [name, 'properties', 'alpha_cutoff'] for row in rows) == 1,
             'Exactly one portable metadata change required per leaf')
        need(sum(row['path'][0] == name for row in rows) == 9, 'Exact eight scalar aliases plus one metadata value required per leaf')
    need(project_aliases(before, rows) == after, 'Measured aliases do not exactly reconstruct actual graphs')
    return rows


def check_alias_payload(folder, expected_receipt_sha256):
    folder = Path(folder).resolve(strict=True)
    receipt = folder / 'leaf_mask_alias_report.json'
    need(len(expected_receipt_sha256) == 64 and sha(receipt) == expected_receipt_sha256,
         'Actual completed alias receipt hash required')
    report = json.loads(receipt.read_text(encoding='utf-8'))
    need(report['schema'] == 'living_town.actual_leaf_mask_alias_measurement.v1'
         and report['status'] == 'ACTUAL_TWO_LEAF_ALIAS_MEASUREMENT_AND_RESTORATION_PASS'
         and report['native']['sha256'] == ALIAS_NATIVE_SHA and report['script']['sha256'] == ALIAS_SOURCE_SHA
         and report['original_graph_images_bindings_restored'] is True and report['immutable_bytes_preserved'] is True
         and report['saved'] is False and report['rendered'] is False and report['exported'] is False,
         'Actual source-bound alias measurement did not pass')
    artifacts = report['artifacts']
    need(set(artifacts) == {'before.json', 'after.json', 'recursive_diff.json'}, 'Exact alias artifact inventory differs')
    for row in [report['script'], *report['sources'], *artifacts.values()]:
        verify(row)
    for name, row in artifacts.items():
        need(Path(row['path']).resolve() == folder / name, 'Alias artifact leaves immutable measurement folder')
    need({row['sha256'] for row in report['sources']} == {ENTRY_HELPER_SHA, RNA_SHA,
          'eb2eb9de6ebc0349918e8a78e55715726efefe58e0d637a437cbb008c878e383'}, 'Alias measurement recipe/source differs')
    before, after, rows = (json.loads(Path(artifacts[name]['path']).read_text(encoding='utf-8'))
                           for name in ('before.json', 'after.json', 'recursive_diff.json'))
    alias_contract(before, after, rows, report['authored_owners'])
    return {'receipt': binding(receipt), 'artifacts': list(artifacts.values()),
            'sources': [report['script'], *report['sources']], 'rows': rows}


def predicted_materials(before, fields, measured_aliases):
    """Exact whole graph model, including the finite actual serializer aliases."""
    need(len(fields) == 2 and tuple(row['material'] for row in fields) == LEAVES, 'Exact two-leaf field declaration required')
    for row in fields:
        need(row == {'material': row['material'], 'node': row['node'], 'socket_index': 1,
                     'socket_identifier': 'Value_001', 'before': SOURCE_THRESHOLD, 'after': .25,
                     'metadata': 'alpha_cutoff', 'metadata_before': .45, 'metadata_after': .25},
             'Unexpected cutoff field declaration')
        material = before[row['material']]
        need(material['properties'].get('alpha_cutoff') == .45
             and material['properties'].get('alpha_mode') == 'MASK', 'Original structured metadata differs')
        nodes = [node for node in material['node_tree']['nodes'] if node['name'] == row['node']]
        need(len(nodes) == 1, 'Exact source mask node missing/duplicated')
        node = nodes[0]
        need(node['settings']['operation'] == 'GREATER_THAN'
             and node['inputs'][1]['default'] == SOURCE_THRESHOLD
             and node['settings']['inputs'][1]['default_value'] == SOURCE_THRESHOLD
             and node['settings']['inputs'][1]['identifier'] == 'Value_001', 'Structured original socket differs')
    wanted = project_aliases(before, measured_aliases)
    for row in fields:
        name = row['material']
        node = next(node for node in wanted[name]['node_tree']['nodes'] if node['name'] == row['node'])
        need(wanted[name]['properties']['alpha_cutoff'] == .25 and node['inputs'][1]['default'] == .25
             and node['settings']['inputs'][1]['default_value'] == .25,
             'Actual alias model omitted an authored cutoff representation')
    return wanted


def permitted_material_delta(before, after, fields, measured_aliases):
    wanted = predicted_materials(before, fields, measured_aliases)
    need(digest(wanted) == digest(after),
         'Material/node/socket/link state changed beyond four authored values and eighteen measured serialized paths')
    return {'status': 'EXACT_TWO_LEAF_MASK_FOUR_AUTHORED_VALUES_18_SERIALIZED_PATHS_ONLY',
            'authored_value_count': 4, 'serialized_changed_path_count': 18, 'fields': fields,
            'raw_before_sha256': digest(before), 'raw_after_sha256': digest(after),
            'ignored_or_normalized_state': []}


def all_bindings(bpy):
    """All actual Mesh DATA bindings and all object material-slot link modes."""
    return {'meshes': {mesh.name: {'identity': mesh.as_pointer(),
                 'materials': [(m.name, m.as_pointer()) if m else None for m in mesh.materials]}
                 for mesh in bpy.data.meshes},
            'objects': {ob.name: {'identity': ob.as_pointer(),
                 'data': ob.data.as_pointer() if ob.data else None,
                 'slots': [{'link': s.link, 'material': (s.material.name, s.material.as_pointer()) if s.material else None}
                           for s in ob.material_slots]}
                 for ob in bpy.data.objects if hasattr(ob, 'material_slots')}}


def all_images(bpy):
    """Every packed payload (including multi-file images), no RNA pixel decoding."""
    result = {}
    for image in bpy.data.images:
        packed = [{'filepath': entry.filepath, 'bytes': len(entry.packed_file.data),
                   'sha256': hashlib.sha256(entry.packed_file.data).hexdigest()} for entry in image.packed_files]
        if image.packed_file is not None and not packed:
            packed = [{'filepath': image.filepath, 'bytes': len(image.packed_file.data),
                       'sha256': hashlib.sha256(image.packed_file.data).hexdigest()}]
        result[image.name] = {'identity': image.as_pointer(), 'source': image.source,
            'filepath': image.filepath, 'alpha_mode': image.alpha_mode, 'size': list(image.size),
            'is_float': image.is_float, 'colorspace': image.colorspace_settings.name, 'packed': packed}
    return result


def preflight_native(bpy, E, payload):
    for row in [payload['rna_binding'], payload['gui_binding'], *payload['artifacts'],
                payload['aliases']['receipt'], *payload['aliases']['artifacts'], *payload['aliases']['sources']]:
        verify(row)
    records = {}
    for name in LEAVES:
        material = bpy.data.materials.get(name)
        need(material is not None, 'Source leaf material missing: ' + name)
        records[name] = source_leaf_record(material)
        need(digest(records[name]) == digest(payload['rna']['materials'][name]), 'Actual original leaf graph differs from pinned source RNA: ' + name)
    fields = declared_fields(records)
    materials = structured_materials(bpy, E)
    wanted = predicted_materials(materials, fields, payload['aliases']['rows'])
    images = all_images(bpy)
    for name, original in payload['rna']['images'].items():
        actual = images.get(name)
        need(actual is not None and actual['source'] == 'FILE' and len(actual['packed']) == 1
             and actual['packed'][0]['sha256'] == original['packed_sha256']
             and actual['packed'][0]['bytes'] == original['packed_bytes']
             and all(actual[key] == original[key] for key in ('alpha_mode', 'size', 'is_float', 'colorspace')),
             'Original botanical packed pixels/settings differ: ' + name)
    return {'materials': materials, 'wanted': wanted, 'fields': fields,
            'bindings': all_bindings(bpy), 'images': images,
            'material_identities': {m.name: m.as_pointer() for m in bpy.data.materials}}


def apply(bpy, E, payload, context):
    """Mutate existing two materials only after every preflight gate has passed."""
    need(digest(structured_materials(bpy, E)) == digest(context['materials'])
         and all_bindings(bpy) == context['bindings'] and all_images(bpy) == context['images'],
         'Native changed between cutoff preflight and apply')
    for row in context['fields']:
        material = bpy.data.materials[row['material']]
        material.node_tree.nodes[row['node']].inputs[1].default_value = .25
        material['alpha_cutoff'] = .25
    actual = structured_materials(bpy, E)
    material_proof = permitted_material_delta(context['materials'], actual, context['fields'], payload['aliases']['rows'])
    need({m.name: m.as_pointer() for m in bpy.data.materials} == context['material_identities']
         and all_bindings(bpy) == context['bindings'], 'Material identities or mesh/object bindings changed')
    need(all_images(bpy) == context['images'], 'An image/payload/settings/identity changed')
    for row in [payload['rna_binding'], payload['gui_binding'], *payload['artifacts'],
                payload['aliases']['receipt'], *payload['aliases']['artifacts'], *payload['aliases']['sources']]:
        verify(row)
    return {'schema': 'living_town.composed_leaf_cutoff_delta.v1',
            'status': 'EXACT_TWO_LEAF_MASK_FOUR_VALUE_DELTA_PASS_INTEGRATION_PENDING',
            'source_RNA': payload['rna_binding'], 'source_GUI': payload['gui_binding'],
            'source_exact_aliases': payload['aliases']['receipt'], 'serialized_alias_count': len(payload['aliases']['rows']),
            'fields': context['fields'], 'raw_material_before_sha256': digest(context['materials']),
            'raw_material_after_sha256': digest(actual), 'all_mesh_object_bindings_sha256': digest(context['bindings']),
            'material_changes': material_proof,
            'packed_image_count': sum(bool(row['packed']) for row in context['images'].values()),
            'all_images_sha256': digest(context['images']), 'material_identities_and_bindings_unchanged': True,
            'saved_or_exported_by_stage': False, 'geometry_or_UV_edit_by_stage': False,
            'tiny_core_glTF_MASK025_original_RGBA': 'ACTUAL_PASS', 'whole_town_portable_and_Godot_integration': 'PENDING',
            'whole_town_concept_acceptance': False}
