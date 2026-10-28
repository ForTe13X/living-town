#pragma once

#include "CoreMinimal.h"
#include "Materials/Material.h"
#include "Materials/MaterialInterface.h"
#include "UObject/UObjectGlobals.h"

namespace LivingTownMaterials
{
// Read-only pre-creation gate. GetUsageByFlag is virtual: UE 5.8 material
// instances can override effective usage independently of their base material.
// Never use CheckMaterialUsage here: in the editor it can set flags/compile.
inline bool ValidateInstancedUsage(const UMaterialInterface* Material,const FString& EntryId,
    const FString& MeshPath,int32 SlotIndex,FString& Error)
{
    check(IsInGameThread());
    const UMaterial* Base=Material?Material->GetMaterial():nullptr;
    // Preserve UE's existing special-engine-material exemption; this does not
    // select a default material or enable the expensive special usage flag.
    if(Material&&Base&&(Material->GetUsageByFlag(MATUSAGE_InstancedStaticMeshes)||Base->bUsedAsSpecialEngineMaterial))return true;
    Error=FString::Printf(TEXT("tile_native_instanced_material_usage_missing: entry=%s mesh=%s slot=%d material=%s base=%s required=MATUSAGE_InstancedStaticMeshes; author/compile/save the effective material usage, then cold-reopen and requalify the content; runtime will not repair it"),
        *EntryId,*MeshPath,SlotIndex,*GetPathNameSafe(Material),*GetPathNameSafe(Base));
    return false;
}
}
