"""Check the literal description contract of a closed Python toolset.

This catches copied class docstrings that disagree with the descriptor written
by the registration adapter. It parses source without importing Unreal or
executing the module. Native registry/schema checks are still required.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
from pathlib import Path


def inspect_description(source: str, class_name: str, variable: str = "DESC") -> dict:
    tree = ast.parse(source)
    declarations = []
    for node in tree.body:
        if isinstance(node, ast.Assign):
            if any(isinstance(target, ast.Name) and target.id == variable
                   for target in node.targets):
                declarations.append((node.value, node.lineno))
        elif isinstance(node, ast.AnnAssign):
            if isinstance(node.target, ast.Name) and node.target.id == variable:
                declarations.append((node.value, node.lineno))
        elif isinstance(node, ast.AugAssign):
            if isinstance(node.target, ast.Name) and node.target.id == variable:
                raise ValueError(f"{variable} must not be augmented")
    if len(declarations) != 1:
        raise ValueError(f"Expected one module-level {variable} declaration")
    value, declaration_line = declarations[0]
    if not isinstance(value, ast.Constant) or not isinstance(value.value, str):
        raise ValueError(f"{variable} must be a literal string for this check")
    expected = value.value
    if not expected.strip():
        raise ValueError("The declared description is empty")
    classes = [node for node in tree.body
               if isinstance(node, ast.ClassDef) and node.name == class_name]
    if len(classes) != 1:
        raise ValueError(f"Expected one top-level class {class_name}")
    cls = classes[0]
    actual = ast.get_docstring(cls, clean=True)
    # Explicit __doc__ replacement makes the initial docstring insufficient.
    for node in cls.body:
        targets = node.targets if isinstance(node, ast.Assign) else (
            [node.target] if isinstance(node, (ast.AnnAssign, ast.AugAssign)) else [])
        if any(isinstance(target, ast.Name) and target.id == "__doc__"
               for target in targets):
            raise ValueError("Explicit class __doc__ assignment is unsupported")
    if actual != expected:
        raise ValueError(f"Toolset description mismatch: {class_name} at line "
                         f"{cls.lineno} has {actual!r}; {variable} at line "
                         f"{declaration_line} is {expected!r}")
    return {
        "status": "PASS_SOURCE_TOOLSET_DESCRIPTION_CONTRACT",
        "class": class_name,
        "class_line": cls.lineno,
        "description_variable": variable,
        "description_line": declaration_line,
        "description": expected,
        "module_executed": False,
        "native_registry_schema_verified": False,
    }


def inspect_file(path: Path, class_name: str, variable: str = "DESC") -> dict:
    data = path.read_bytes()
    result = inspect_description(data.decode("utf-8-sig"), class_name, variable)
    result["source"] = {"path": str(path.resolve()), "bytes": len(data),
                        "sha256": hashlib.sha256(data).hexdigest()}
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--class-name", required=True)
    parser.add_argument("--description-variable", default="DESC")
    args = parser.parse_args()
    try:
        result = inspect_file(args.source, args.class_name, args.description_variable)
    except (ValueError, SyntaxError, UnicodeError, OSError) as error:
        print(json.dumps({"status": "FAIL_SOURCE_TOOLSET_DESCRIPTION_CONTRACT",
                          "error": str(error), "module_executed": False}))
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
