"""Narrow project-owned Unreal MCP bridge to the native glTF Interchange importer."""

import re
from pathlib import Path

import unreal
import toolset_registry


@unreal.uclass()
class LivingTownInterchangeTools(unreal.ToolsetDefinition):
    """Imports engine-agnostic glTF assets through Unreal's Interchange pipeline."""

    @toolset_registry.tool_call
    @staticmethod
    def import_gltf_interchange(
            folder_path: str, asset_name: str, source_file: str) -> list[unreal.Object]:
        """Imports a glTF/GLB without pinning a factory, then returns all created assets.

        The destination is restricted to /Game/LivingTown_UEPilot and descendants.
        Existing assets are refused. Use AssetTools.save_assets on returned paths
        after checking them. Factory and options are deliberately omitted so the
        editor selects its native Interchange pipeline.
        """
        folder = folder_path.rstrip("/")
        folder_parts = folder.split("/")
        if (len(folder_parts) < 3 or folder_parts[0] != "" or
                folder_parts[1] != "Game" or folder_parts[2] != "LivingTown_UEPilot" or
                any(not re.fullmatch(r"[A-Za-z0-9_]+", part)
                    for part in folder_parts[1:])):
            raise ValueError("Import folder must be /Game/LivingTown_UEPilot or a safe child path")
        if not re.fullmatch(r"[A-Za-z0-9_]+", asset_name):
            raise ValueError("Asset name must contain only ASCII letters, digits, and underscores")

        source = Path(source_file).resolve(strict=True)
        if source.suffix.lower() not in {".gltf", ".glb"}:
            raise ValueError("Only .gltf and .glb sources are accepted by this tool")
        if not source.is_file() or source.stat().st_size <= 0 or source.stat().st_size > 2 * 1024**3:
            raise ValueError("Source must be a non-empty local file no larger than 2 GiB")

        object_path = f"{folder}/{asset_name}"
        if unreal.EditorAssetLibrary.does_asset_exist(object_path):
            raise FileExistsError(f"Refusing to replace existing asset {object_path}")

        task = unreal.AssetImportTask()
        task.filename = str(source)
        task.destination_path = folder
        task.destination_name = asset_name
        task.replace_existing = False
        task.automated = True
        task.save = False

        unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
        paths = list(task.get_editor_property("imported_object_paths"))
        if not paths:
            raise RuntimeError(f"Interchange imported no assets from {source.name}")

        created = []
        for path in paths:
            if not isinstance(path, str) or not path.startswith(folder + "/"):
                raise RuntimeError(f"Importer produced an unexpected asset path: {path!r}")
            asset = unreal.load_asset(path)
            if not asset:
                raise RuntimeError(f"Imported asset could not be loaded: {path}")
            created.append(asset)
        return created
