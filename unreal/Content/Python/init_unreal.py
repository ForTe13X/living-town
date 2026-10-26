# Read-only path/capability telemetry; no assets/imports/feature changes.
import os,sys,json
sys.dont_write_bytecode=True
from pathlib import Path
import unreal
out=Path(os.environ['LIVING_TOWN_BOOTSTRAP_OUTPUT'])
names=['project_dir','project_user_dir','project_saved_dir','project_intermediate_dir','engine_user_dir','engine_saved_dir']
paths={name:getattr(unreal.Paths,name)() if hasattr(unreal.Paths,name) else 'API_NOT_EXPOSED' for name in names}
paths['environment']={k:os.environ.get(k)for k in ['TEMP','TMP','UE-LocalDataCachePath','PYTHONPYCACHEPREFIX']}
paths['python_cache_prefix']=sys.pycache_prefix
paths['python_write_bytecode_disabled']=sys.dont_write_bytecode
paths['feature_changes_executed']=False
paths['Lumen_Nanite_actual_RHI_and_import_checks_pending']=True

# Register the project-owned, path-restricted glTF Interchange import tool.
try:
    from toolset_registry.registration import Registration
    from livingtown_interchange import LivingTownInterchangeTools

    _living_town_interchange_registration=Registration([LivingTownInterchangeTools])
    _registered=_living_town_interchange_registration.register()
    paths['living_town_interchange_toolset_registration']={
        'registered':bool(_registered),
        'toolset':'LivingTownInterchangeTools',
    }
except Exception as error:
    paths['living_town_interchange_toolset_registration']={
        'registered':False,
        'error':str(error),
    }

(out/'BOOTSTRAP_PATH_DIAGNOSTICS.json').write_text(json.dumps(paths,indent=2),encoding='utf-8')
