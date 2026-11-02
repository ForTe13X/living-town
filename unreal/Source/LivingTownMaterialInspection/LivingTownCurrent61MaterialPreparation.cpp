#include "LivingTownCurrent61MaterialPreparation.h"
#include "LivingTownTileData.h"
#include "Materials/Material.h"
#include "MaterialShared.h"
#include "ShaderCompiler.h"
#include "Shader.h"
#include "RHI.h"
#include "DynamicRHI.h"
#include "UnrealEngine.h"
#include "HAL/IConsoleManager.h"
#include "HAL/FileManager.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "UObject/Package.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#if PLATFORM_WINDOWS
#include "Windows/WindowsHWrapper.h"
#endif

namespace Current61MaterialPreparation
{
FString Json(const TSharedRef<FJsonObject>& Object)
{
    FString Text;
    FJsonSerializer::Serialize(Object,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Text));
    return Text.Len()<=32768?Text:TEXT("{\"status\":\"REFUSED\",\"reason\":\"JSON_bound\"}");
}
FString Refuse(const TCHAR* Reason)
{
    auto Object=MakeShared<FJsonObject>();Object->SetStringField(TEXT("status"),TEXT("REFUSED"));Object->SetStringField(TEXT("reason"),Reason);return Json(Object);
}
bool NoReparse(const FString& Absolute)
{
#if PLATFORM_WINDOWS
    FString Name=Absolute.Replace(TEXT("/"),TEXT("\\"));
    if(Name.Len()<3||Name[1]!=':'||Name[2]!='\\')return false;
    FString Part=Name.Left(3);TArray<FString> Parts;Name.Mid(3).ParseIntoArray(Parts,TEXT("\\"),true);
    auto Check=[](const FString& Path){DWORD Attr=GetFileAttributesW(*Path);return Attr!=INVALID_FILE_ATTRIBUTES&&!(Attr&FILE_ATTRIBUTE_REPARSE_POINT);};
    if(!Check(Part))return false;
    for(const FString& Next:Parts){if(Next==TEXT(".")||Next==TEXT(".."))return false;Part=FPaths::Combine(Part,Next);if(!Check(Part))return false;}
    return true;
#else
    return false;
#endif
}
bool Allowed(const FString& Path)
{
    static const TSet<FString> Paths={
        TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/HairCards_v001/M_Worker110NativeHair_v001.M_Worker110NativeHair_v001"),
        TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_body_1.M_Baked_body_1"),
        TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_body_2.M_Baked_body_2"),
        TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_brows_0.M_Baked_brows_0"),
        TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_eyes_0.M_Baked_eyes_0"),
        TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_garment_0.M_Baked_garment_0"),
        TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_pants_0.M_Baked_pants_0"),
        TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_shoes_0.M_Baked_shoes_0"),
        TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_apron_0.M_Baked_apron_0")};
    return Paths.Contains(Path);
}
bool Context()
{
    const IConsoleVariable* Forward=IConsoleManager::Get().FindConsoleVariable(TEXT("r.ForwardShading"));
    const IConsoleVariable* Substrate=IConsoleManager::Get().FindConsoleVariable(TEXT("r.Substrate"));
    return IsInGameThread()&&GIsEditor&&Forward&&Substrate&&Forward->GetInt()==0&&Substrate->GetInt()==0&&GDynamicRHI&&FString(GDynamicRHI->GetName())==TEXT("D3D12")&&GMaxRHIShaderPlatform==SP_PCD3D_SM6&&GMaxRHIFeatureLevel==ERHIFeatureLevel::SM6&&GShaderCompilingManager;
}
struct FState
{
    FString Path,File,Hash;int64 Bytes=0;FDateTime Timestamp;FGuid Id;bool Dirty=false;uint16 Models=0;
};
bool Snapshot(UMaterial* Material,const FString& Hash,FState& State)
{
    if(!Context()||!IsValid(Material)||Material->GetClass()!=UMaterial::StaticClass()||Material->IsTemplate()||Material->HasAnyFlags(RF_NeedLoad|RF_NeedPostLoad|RF_NeedPostLoadSubobjects|RF_BeginDestroyed|RF_FinishDestroyed)||!Allowed(Material->GetPathName())||FindObject<UMaterial>(nullptr,*Material->GetPathName())!=Material)return false;
    if(Hash.Len()!=64)return false;
    for(TCHAR Ch:Hash)if(!((Ch>='0'&&Ch<='9')||(Ch>='a'&&Ch<='f')))return false;
    UPackage* Package=Material->GetOutermost();
    if(!Package||Package==GetTransientPackage()||Package->HasAnyPackageFlags(PKG_PlayInEditor)||Package->IsDirty())return false;
    State.Path=Material->GetPathName();State.Id=Material->StateId;State.Dirty=Package->IsDirty();State.Models=Material->GetShadingModels().GetShadingModelField();
    if(!State.Id.IsValid()||!FPackageName::TryConvertLongPackageNameToFilename(Package->GetName(),State.File,FPackageName::GetAssetPackageExtension()))return false;
    State.File=FPaths::ConvertRelativePathToFull(State.File);
    if(!FPaths::IsUnderDirectory(State.File,FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()))||!NoReparse(State.File))return false;
    State.Bytes=IFileManager::Get().FileSize(*State.File);State.Timestamp=IFileManager::Get().GetTimeStamp(*State.File);
    if(State.Bytes<=0||State.Bytes>(16ll<<20))return false;
    TArray<uint8> Data;
    return FFileHelper::LoadFileToArray(Data,*State.File)&&Data.Num()==State.Bytes&&LivingTownTiles::HashBytes(Data,State.Hash)&&State.Hash==Hash&&IFileManager::Get().FileSize(*State.File)==State.Bytes&&IFileManager::Get().GetTimeStamp(*State.File)==State.Timestamp;
}
bool Same(const FState& A,const FState& B)
{
    return A.Path==B.Path&&A.File==B.File&&A.Hash==B.Hash&&A.Bytes==B.Bytes&&A.Timestamp==B.Timestamp&&A.Id==B.Id&&A.Dirty==B.Dirty&&A.Models==B.Models;
}
TSharedRef<FJsonObject> StateJson(const FState& State)
{
    auto Object=MakeShared<FJsonObject>();Object->SetStringField(TEXT("material"),State.Path);Object->SetStringField(TEXT("file"),State.File);Object->SetStringField(TEXT("sha256"),State.Hash);Object->SetNumberField(TEXT("bytes"),double(State.Bytes));Object->SetStringField(TEXT("mtime_ticks"),LexToString(State.Timestamp.GetTicks()));Object->SetStringField(TEXT("StateId"),State.Id.ToString());Object->SetBoolField(TEXT("dirty"),State.Dirty);Object->SetNumberField(TEXT("shading_model_field"),State.Models);return Object;
}
TSet<TWeakObjectPtr<UMaterial>> Begun;
}

FString ULivingTownCurrent61MaterialPreparation::PrepareCurrent61SavedMaterialResource(UMaterial* Material,const FString& ExpectedPackageSha256)
{
    using namespace Current61MaterialPreparation;
    FState Before,After;
    if(!Snapshot(Material,ExpectedPackageSha256,Before))return Refuse(TEXT("exact_clean_saved_owned_material_hash_and_Editor_D3D12_SM6_required"));
    const TWeakObjectPtr<UMaterial> Key(Material);
    if(Begun.Contains(Key))return Refuse(TEXT("once_only_explicit_resource_preparation_no_retry"));
    Begun.Add(Key);
    // CacheShaders is the public exported wrapper for private
    // CacheResourceShadersForRendering(false, CompileMode). It preserves StateId.
    // The scope syncs render state; shader jobs finish asynchronously. No asset
    // edit notifications, global full-map CVar change or package save is issued.
    {
        FMaterialUpdateContext Update;
        Update.AddMaterial(Material);
        Material->CacheShaders(EMaterialShaderPrecompileMode::Default);
    }
    const bool Custody=Snapshot(Material,ExpectedPackageSha256,After)&&Same(Before,After);
    auto Object=MakeShared<FJsonObject>();
    Object->SetStringField(TEXT("status"),Custody?TEXT("REQUESTED_OWNED_MATERIAL_RESOURCE_CACHE_NOT_READY_PROOF"):TEXT("REFUSED_RESOURCE_INITIALIZATION_CUSTODY_CHANGED"));
    Object->SetStringField(TEXT("schema"),TEXT("LivingTown.Current61OwnedMaterialResourcePreparation.v1"));
    Object->SetObjectField(TEXT("before"),StateJson(Before));Object->SetObjectField(TEXT("after"),StateJson(After));
    Object->SetBoolField(TEXT("saved_package_StateId_dirty_shading_models_unchanged"),Custody);
    Object->SetBoolField(TEXT("explicit_resource_cache_request_once"),true);
    Object->SetBoolField(TEXT("pure_observer"),false);
    Object->SetBoolField(TEXT("asset_property_edit_reimport_resave_or_global_shader_wait"),false);
    Object->SetBoolField(TEXT("readiness_or_GPU_art_qualified"),false);
    return Json(Object);
}

FString ULivingTownCurrent61MaterialPreparation::ReadCurrent61SavedMaterialResource(UMaterial* Material,const FString& ExpectedPackageSha256)
{
    using namespace Current61MaterialPreparation;
    FState Before,After;
    if(!Snapshot(Material,ExpectedPackageSha256,Before))return Refuse(TEXT("exact_clean_saved_owned_material_hash_and_Editor_D3D12_SM6_required"));
    const bool GlobalBefore=GShaderCompilingManager->IsCompiling();const int32 JobsBefore=GShaderCompilingManager->GetNumRemainingJobs();
    const FMaterialResource* Resource=static_cast<const UMaterial*>(Material)->GetMaterialResource(GMaxRHIShaderPlatform);
    const bool Own=Resource&&Resource->GetMaterial()==Material&&Resource->GetMaterialInstance()==nullptr&&Resource->GetShaderPlatform()==GMaxRHIShaderPlatform;
    const FMaterialShaderMap* Map=Own?Resource->GetGameThreadShaderMap():nullptr;
    const FShaderMapResource* Code=Map?Map->GetResource():nullptr;
    const bool Finalized=Map&&Map->IsCompilationFinalized();
    const bool Successful=Map&&Map->CompiledSuccessfully();
    const bool Complete=Own&&Resource->IsGameThreadShaderMapComplete();
    const bool Caching=Own&&Resource->IsCachingShaders();
    const auto Quality=GetCachedScalabilityCVars().MaterialQualityLevel;
    const auto ResourceQuality=Own?Resource->GetQualityLevel():EMaterialQualityLevel::Num;
    const bool Compatible=GetCachedScalabilityCVars().bInitialized&&int32(Quality)>=0&&Quality<EMaterialQualityLevel::Num&&Own&&Map&&(ResourceQuality==Quality||ResourceQuality==EMaterialQualityLevel::Num)&&Map->GetShaderMapId().QualityLevel==ResourceQuality&&Resource->GetFeatureLevel()==GMaxRHIFeatureLevel&&Map->GetShaderMapId().FeatureLevel==GMaxRHIFeatureLevel;
    const bool Current=Own&&Map&&Resource->GetMaterialId()==Before.Id&&Map->GetShaderMapId().BaseMaterialId==Before.Id;
    int32 Shaders=0,Pipelines=0;const uint32 FrozenBytes=Map?Map->GetFrozenContentSize():0;
    if(Map&&Map->GetContent()&&FrozenBytes)Map->CountNumShaders(Shaders,Pipelines);
    const bool Resolved=Code&&Code->IsResolved();const int32 CodeShaders=Code?Code->GetNumShaders():0;
    const bool Renderable=Map&&Map->IsValidForRendering(false)&&Map->GetShaderPlatform()==GMaxRHIShaderPlatform&&FrozenBytes>0&&Shaders>0&&Code&&Resolved&&CodeShaders>0&&Code->GetPlatform()==GMaxRHIShaderPlatform;
    TArray<TSharedPtr<FJsonValue>> Errors;
    if(Own){const auto& NativeErrors=Resource->GetCompileErrors();if(NativeErrors.Num()>16)return Refuse(TEXT("compile_error_count_bound"));for(const FString& Error:NativeErrors){if(Error.Len()>4096)return Refuse(TEXT("compile_error_length_bound"));Errors.Add(MakeShared<FJsonValueString>(Error));}}
    const bool DDC=IsMaterialMapDDCEnabled();
    const bool GlobalAfter=GShaderCompilingManager->IsCompiling();const int32 JobsAfter=GShaderCompilingManager->GetNumRemainingJobs();
    const bool Custody=Snapshot(Material,ExpectedPackageSha256,After)&&Same(Before,After);
    const bool Stable=static_cast<const UMaterial*>(Material)->GetMaterialResource(GMaxRHIShaderPlatform)==Resource&&(!Resource||(Resource->GetGameThreadShaderMap()==Map&&Resource->GetQualityLevel()==ResourceQuality))&&(!Map||(Map->GetResource()==Code&&Map->GetFrozenContentSize()==FrozenBytes&&Map->IsCompilationFinalized()==Finalized&&Map->CompiledSuccessfully()==Successful))&&(!Code||(Code->IsResolved()==Resolved&&Code->GetNumShaders()==CodeShaders))&&GetCachedScalabilityCVars().MaterialQualityLevel==Quality&&IsMaterialMapDDCEnabled()==DDC&&Context();
    const bool Ready=Custody&&Stable&&Own&&Complete&&!Caching&&Compatible&&Current&&Renderable&&Errors.IsEmpty()&&!GlobalBefore&&!GlobalAfter&&JobsBefore==0&&JobsAfter==0;
    auto Object=MakeShared<FJsonObject>();
    Object->SetStringField(TEXT("status"),Ready?TEXT("READ_ONLY_OWNED_SAVED_SM6_RESOURCE_READY_V1"):TEXT("HOLD_OWNED_SAVED_SHADER_RESOURCE_PENDING_OR_INVALID_V1"));
    Object->SetStringField(TEXT("schema"),TEXT("LivingTown.Current61OwnedMaterialResourceReadiness.v1"));Object->SetStringField(TEXT("material"),Before.Path);Object->SetObjectField(TEXT("before"),StateJson(Before));Object->SetObjectField(TEXT("after"),StateJson(After));
    Object->SetBoolField(TEXT("saved_package_StateId_dirty_shading_models_unchanged"),Custody);Object->SetBoolField(TEXT("resource_snapshot_unchanged"),Stable);Object->SetBoolField(TEXT("exact_own_resource_no_default_fallback"),Own);Object->SetBoolField(TEXT("complete"),Complete);Object->SetBoolField(TEXT("is_caching_shaders"),Caching);Object->SetBoolField(TEXT("feature_quality_compatible"),Compatible);Object->SetBoolField(TEXT("current_material_ids"),Current);Object->SetBoolField(TEXT("renderable_frozen_nonempty_resolved"),Renderable);
    Object->SetNumberField(TEXT("shader_count"),Shaders);Object->SetNumberField(TEXT("pipeline_count"),Pipelines);Object->SetNumberField(TEXT("resource_shader_count"),CodeShaders);Object->SetNumberField(TEXT("frozen_bytes"),FrozenBytes);Object->SetBoolField(TEXT("material_map_DDC_enabled_observed"),DDC);Object->SetBoolField(TEXT("map_compilation_finalized_observed"),Finalized);Object->SetBoolField(TEXT("map_compiled_successfully_observed"),Successful);Object->SetArrayField(TEXT("compile_errors"),Errors);
    Object->SetBoolField(TEXT("global_compiling_before"),GlobalBefore);Object->SetBoolField(TEXT("global_compiling_after"),GlobalAfter);Object->SetNumberField(TEXT("global_jobs_before"),JobsBefore);Object->SetNumberField(TEXT("global_jobs_after"),JobsAfter);Object->SetBoolField(TEXT("pure_observer_no_compile_finish_wait_setter_or_fallback"),true);Object->SetBoolField(TEXT("GPU_shader_use_art_or_Game_qualified"),false);
    return Json(Object);
}
