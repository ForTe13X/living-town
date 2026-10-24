"""Packed image guard with explicit shader-unbound Blender result exclusion.

No exclusion by image name. Every Material/World image node is enumerated,
including nested groups and unused outputs. All shader-bound images and all
other images with actual users remain required packed FILE assets. Only RNA
types RENDER_RESULT/COMPOSITING proved unbound from all those shaders can be
classified as transient render builtins. Unused images are listed separately.
"""
import hashlib


def need(value, message):
    if not value: raise ValueError(message)


def shader_image_bindings(bpy):
    bindings = {}
    def visit(tree, owner, path, stack):
        identity = tree.as_pointer() if hasattr(tree, 'as_pointer') else id(tree)
        need(identity not in stack, 'Cyclic shader node group cannot be proven image-unbound')
        stack = stack | {identity}
        for node in tree.nodes:
            node_path = [*path, node.name]
            image = getattr(node, 'image', None)
            if image is not None:
                bindings.setdefault(image.name, []).append({**owner, 'node_path': node_path,
                    'node_type': getattr(node, 'bl_idname', getattr(node, 'type', None)), 'node_tree': tree.name})
            group = getattr(node, 'node_tree', None)
            if group is not None: visit(group, owner, node_path, stack)
    for kind, owners in (('MATERIAL', bpy.data.materials), ('WORLD', bpy.data.worlds)):
        for owner in owners:
            if getattr(owner, 'node_tree', None) is not None:
                visit(owner.node_tree, {'owner_kind': kind, 'owner': owner.name,
                    'owner_use_nodes': bool(getattr(owner, 'use_nodes', False))}, [], set())
    return bindings


def packed_row(image):
    return {'size': list(image.size), 'colorspace': image.colorspace_settings.name,
            'alpha_mode': image.alpha_mode, 'filepath': image.filepath,
            'bytes': len(image.packed_file.data), 'sha256': hashlib.sha256(image.packed_file.data).hexdigest()}


def capture(bpy):
    bindings = shader_image_bindings(bpy)
    assets, excluded, unused = {}, [], []
    actual_names = set()
    for image in bpy.data.images:
        actual_names.add(image.name)
        bound = image.name in bindings
        identity = {'name': image.name, 'type': image.type, 'source': image.source,
                    'users': int(image.users), 'shader_bindings': bindings.get(image.name, [])}
        if image.type in {'RENDER_RESULT', 'COMPOSITING'}:
            need(not bound, 'Builtin render/compositing image is shader-bound: ' + image.name)
            excluded.append({**identity, 'reason': 'RNA_BUILTIN_TYPE_AND_ACTUAL_ALL_MATERIAL_WORLD_SHADER_UNBOUND'})
            continue
        if not bound and image.users == 0:
            unused.append({**identity, 'reason': 'NO_SHADER_BINDING_AND_ACTUAL_ZERO_USERS; NOT_CERTIFIED_AS_ASSET'})
            continue
        need(image.source == 'FILE' and image.packed_file is not None,
             'Used or shader-bound image is not a packed FILE asset: ' + image.name)
        assets[image.name] = packed_row(image)
    need(set(bindings) <= actual_names, 'Shader-bound image missing from actual bpy.data.images inventory')
    return {'assets': assets, 'shader_image_bindings': bindings,
            'excluded_unbound_builtins': excluded, 'excluded_unused_images': unused,
            'scope': 'ALL_USED_NONBUILTIN_IMAGES_AND_ALL_MATERIAL_WORLD_SHADER_IMAGE_BINDINGS_RECURSIVE'}


def original_botanical_images(bpy, rna):
    result = {}
    for name, expected in rna['images'].items():
        image = bpy.data.images.get(name)
        need(image is not None and image.source == 'FILE' and image.packed_file is not None,
             'Original botanical packed FILE image missing: ' + name)
        actual = packed_row(image)
        wanted = {'size': expected['size'], 'colorspace': expected['colorspace'], 'alpha_mode': expected['alpha_mode'],
                  'filepath': expected['filepath'], 'bytes': expected['packed_bytes'], 'sha256': expected['packed_sha256']}
        need(actual == wanted, 'Original exact botanical packed image/settings differ: ' + name)
        result[name] = actual
    need(len(result) == 30, 'Exact original thirty botanical images required')
    return result
