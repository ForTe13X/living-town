"""Art direction and the stable presentation contract; no simulation state.

The anatomical mesh, macro targets, tailored outfit and strand hair are adapted
from checksum-verified MakeHuman CC0 graphical assets. Fitting, relaxed-pose
retargeting, aprons, role details, palette texture derivatives and animation are
this package's original adaptation; upstream authorship remains in provenance.
The concept image is a visual reference, never projected onto a character mesh.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

VERSION = 1
BASE_HEIGHT = 1.665
DIRECTIONS = ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
CLIPS = ["Idle", "Walk", "Sit", "Lie", "Work", "Talk", "Soak"]
REQUIRED_JOINTS = ["PelvisRoot", "BodyPivot", "HeadPivot", "UpperArm_L", "Forearm_L", "Hand_L", "UpperArm_R", "Forearm_R", "Hand_R", "Thigh_L", "Shin_L", "Foot_L", "Thigh_R", "Shin_R", "Foot_R"]
OPTIONAL_JOINTS = ["ApronDrape", "ApronHem"]
ANIMATED_JOINTS = REQUIRED_JOINTS + OPTIONAL_JOINTS

# key, stature, build, age, top, lower, hair, style, garment, occupational detail.
# The existing persona identities and muted identity palettes remain intact.
_LOOKS = [
    ("aria",1.66,"slim",32,"#ac7468","#384453","#493126","bun","blouse","apron"),
    ("ben",1.79,"broad",35,"#b39257","#303f52","#30291f","short","shirt","tools"),
    ("coco",1.67,"slim",28,"#476b82","#cec1a2","#473224","bun","overshirt","paint"),
    ("dan",1.72,"stocky",72,"#777e67","#c4baa3","#aaa394","receding","knit","captain"),
    ("evy",1.65,"slim",20,"#bc995a","#6f7661","#3e2b20","wavy","overshirt","backpack"),
    ("fei",1.67,"slim",38,"#ada3b9","#a4a0b1","#302921","ponytail","scrubs","doctor"),
    ("lin",1.73,"stocky",45,"#a36b52","#4b535c","#382b23","short","shirt","apron"),
    ("hai",1.75,"broad",59,"#748997","#5e665b","#8f8a7e","receding","knit","fisher"),
    ("shu",1.78,"slim",49,"#7e8774","#605c55","#342b25","sidepart","shirt","glasses"),
    ("mei",1.63,"slim",40,"#ba9988","#4c6070","#3d2b24","bun","blouse","sewing"),
    ("qin",1.70,"slim",26,"#b2825b","#496d7f","#663e29","wavy","blouse","guitar"),
    ("tie",1.84,"broad",44,"#ab8e56","#555d5b","#352a23","short","shirt","leather_apron"),
    ("hua",1.61,"stocky",54,"#789b9b","#7e8270","#645345","bun","blouse","flowers"),
    ("shi",1.80,"broad",42,"#7f8973","#686a61","#42372b","short","shirt","tools"),
    ("mian",1.60,"slim",25,"#9b9f80","#7c7770","#392a25","ponytail","blouse","sewing"),
    ("huai",1.68,"slim",74,"#9b8669","#74786a","#b5aea0","receding","knit","garden"),
    ("dou",1.43,"child",13,"#b87662","#657f82","#423027","wavy","shirt","satchel"),
    ("gui",1.62,"stocky",57,"#8896a6","#737967","#635446","bun","blouse","herbs"),
    ("liu",1.59,"stocky",60,"#a08f9c","#6a7380","#91816f","bun","blouse","apron"),
    ("tao",1.83,"broad",32,"#a88f67","#697360","#32291f","short","shirt","satchel"),
    ("mo",1.75,"slim",56,"#9f9381","#4e5d68","#6f675b","sidepart","shirt","glasses"),
    ("yin",1.71,"stocky",52,"#a89669","#5d625d","#514236","sidepart","shirt","waistcoat"),
    ("yun",1.73,"slim",29,"#779da3","#b0a38a","#503a2c","wavy","overshirt","satchel"),
    ("yong",1.83,"broad",27,"#a58269","#5e7280","#392d22","short","shirt","fisher"),
    ("player",1.72,"slim",29,"#b4a074","#4c6872","#49372c","wavy","overshirt","none"),
]


def outfit_asset(key):
    if key in {'coco','evy','fei','mei','qin','hua','mian','gui','liu','dou'}:
        return 'female_casualsuit01'
    if key in {'tie','shi','yong'}:return 'male_worksuit01'
    return 'male_casualsuit01'


def shoe_asset(key):return 'shoes05' if key in {'dou','evy','qin','yun','player'} else 'shoes01'


def build_manifest(personas: dict | None = None) -> dict:
    entries = {}
    for key,height,build,age,top,lower,hair,style,garment,detail in _LOOKS:
        skin = ["#c58e70", "#d7a580", "#bd8668", "#e0af8c"][sum(map(ord,key)) % 4]
        entries[key] = {
            "id":key, "name":(personas or {}).get(key,{}).get("name",key),
            "model":f"res://assets/characters3d/{key}.glb", "body_height_m":height,
            "build":build,"age":age,"top":top,"lower":lower,"hair":hair,
            "outfit_asset":outfit_asset(key),
            "shoe_asset":shoe_asset(key),
            "skin":skin,"hair_style":style,"garment":garment,"detail":detail,
            "apron":"#dfd5bb" if detail != "leather_apron" else "#79533c",
            "shoe":"#63503d", "eye":"#342d24", "clips":list(CLIPS),
            "origin":"ground_between_feet", "forward":"-Z", "up":"+Y",
            "animation":"named_joint_continuous_skin_v2",
        }
    return {
        "schema":"living_town.characters.v1", "version":VERSION,
        "source":"CC0 MakeHuman anatomy, age/gender targets, authored wardrobe/footwear, registered skin/garment/eye maps and strand hair/brows/lashes; original fitting, apron, palette derivatives and rig adaptation",
        "concept_reference":"concepts/character_style_v1.png",
        "license":"CC0-1.0", "directions":list(DIRECTIONS),
        "required_joints":list(REQUIRED_JOINTS), "optional_joints":list(OPTIONAL_JOINTS), "characters":entries,
    }


def validate_manifest(data: dict, persona_keys: set[str] | None = None) -> list[str]:
    errors = []
    entries = data.get("characters",{})
    expected = (persona_keys | {"player"}) if persona_keys is not None else {row[0] for row in _LOOKS}
    if set(entries) != expected:
        errors.append(f"character coverage mismatch: missing={sorted(expected-set(entries))}, extra={sorted(set(entries)-expected)}")
    for key, entry in entries.items():
        if not 1.2 <= entry.get("body_height_m",0) <= 2.1:
            errors.append(f"{key}: stature outside authored range")
        if set(entry.get("clips",[])) != set(CLIPS):
            errors.append(f"{key}: incomplete animation contract")
        if entry.get("model") != f"res://assets/characters3d/{key}.glb":
            errors.append(f"{key}: unstable model path")
        if entry.get("forward") != "-Z" or entry.get("origin") != "ground_between_feet":
            errors.append(f"{key}: invalid spatial convention")
    return errors


def source_digest() -> str:
    h = hashlib.sha256()
    for p in sorted(Path(__file__).parent.glob("*.py")):
        h.update(p.name.encode()); h.update(p.read_bytes())
    return h.hexdigest()


def write_manifest(path: Path, personas: dict | None = None) -> dict:
    data = build_manifest(personas)
    errors = validate_manifest(data, set(personas) if personas else None)
    if errors:
        raise ValueError("; ".join(errors))
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    return data
