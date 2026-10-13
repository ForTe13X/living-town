"""Serial CLI entry point for the reserve edition. Requires Blender, six threads.

blender --background --threads 6 --python tools/build_reserve.py
The source kit also remains executable through Blender Lab MCP with
LT_STAGE='town', LT_INCLUDE_RESERVE=True in an empty disposable scene.
"""
import runpy
from pathlib import Path
import bpy

bpy.ops.wm.read_homefile(use_empty=True,use_factory_startup=True)
result=runpy.run_path(str(Path(__file__).with_name('build_living_town.py')),
                    init_globals={'LT_STAGE':'town','LT_INCLUDE_RESERVE':True})
print('RESERVE_BUILD_COMPLETE',result['result'],flush=True)
