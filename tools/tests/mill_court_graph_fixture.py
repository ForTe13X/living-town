"""Execute production material-graph builder with a socket/link recording CPU adapter.
This checks graph topology, not Blender RNA availability, pixels or shader quality.
"""

from types import SimpleNamespace as N
import copy


class Socket:
    def __init__(self, node, name):
        self.node = node
        self.name = name
        self.default_value = 0


class Sockets:
    def __init__(self, node, names):
        self.node = node
        self.names = names
        self.rows = {}

    def __getitem__(self, key):
        name = self.names[key] if isinstance(key, int) else key
        if name not in self.rows:
            self.rows[name] = Socket(self.node, name)
        return self.rows[name]


class Node:
    def __init__(self, kind):
        self.bl_idname = kind
        self.name = "Principled BSDF" if kind == "ShaderNodeBsdfPrincipled" else kind
        names = (
            ["Fac", "Color1", "Color2"]
            if kind == "ShaderNodeMixRGB"
            else ["Vector", "Vector_001", "Scale"]
        )
        self.inputs = Sockets(self, names)
        self.outputs = Sockets(self, ["Color"])
        self.color_ramp = N(elements=[N(color=None), N(color=None)])


class Nodes(list):
    def new(self, kind):
        n = Node(kind)
        self.append(n)
        return n

    def get(self, name):
        return next((n for n in self if n.name == name), None)


class Links(list):
    def new(self, a, b):
        # Match single-input Blender semantics; replacing a link must remove the old one.
        self[:] = [x for x in self if x.to_socket is not b]
        self.append(N(from_socket=a, to_socket=b, from_node=a.node, to_node=b.node))


class Material(dict):
    def __init__(self, name):
        self.name = name
        nodes = Nodes()
        nodes.new("ShaderNodeBsdfPrincipled")
        self.node_tree = N(nodes=nodes, links=Links())

    def copy(self):
        return copy.deepcopy(self)


def incoming(mat, node, pin):
    socket = node.inputs[pin]
    rows = [x for x in mat.node_tree.links if x.to_socket is socket]
    assert len(rows) == 1, (node.name, pin, len(rows))
    return rows[0].from_node


def validate_floor(mat):
    nodes = mat.node_tree.nodes
    bs = nodes.get("Principled BSDF")
    fine = nodes.get("SurfaceBump_Fine")
    noise = nodes.get("FineGrain_Noise")
    seam = nodes.get("PlankOrTileSeam_Bump")
    brick = nodes.get("MetricPlankOrTileSeams")
    multiply = nodes.get("PlankGrain_Multiply")
    ramp = nodes.get("WoodGrain_Grayscale")
    assert incoming(mat, bs, "Base Color") is multiply
    assert (
        incoming(mat, multiply, 1) is brick
        and incoming(mat, multiply, 2) is ramp
        and incoming(mat, ramp, "Fac").name == "LongWoodGrain_Noise"
    )
    assert (
        incoming(mat, bs, "Normal") is fine
        and incoming(mat, fine, "Height") is noise
        and incoming(mat, fine, "Normal") is seam
        and incoming(mat, seam, "Height") is brick
    )
    stretch = incoming(mat, noise, "Vector")
    assert incoming(mat, stretch, 0).name == "MetricPhysicalGrainUV"


def main():
    from tools.mill_court.materials import create

    fake = N(data=N(materials=N(new=lambda name: Material(name))))
    mats = create(fake)
    validate_floor(mats["oak_floor"])
    bad = copy.deepcopy(mats["oak_floor"])
    nodes = bad.node_tree.nodes
    bad.node_tree.links.new(
        nodes.get("MetricPlankOrTileSeams").outputs["Fac"],
        nodes.get("SurfaceBump_Fine").inputs["Height"],
    )
    rejected = False
    try:
        validate_floor(bad)
    except AssertionError:
        rejected = True
    assert rejected, "The original seam-overwrites-grain defect must be rejected"
    return dict(
        status="PASS_PRODUCTION_FLOOR_GRAPH_RETAINS_GRAIN_COLOR_AND_CHAINED_GRAIN_SEAM_NORMAL",
        old_defect_negative_control_rejected=True,
        physical_UV_input=True,
        scope="CPU graph-builder topology only; actual Blender/RNA/pixels remain root qualification",
    )
