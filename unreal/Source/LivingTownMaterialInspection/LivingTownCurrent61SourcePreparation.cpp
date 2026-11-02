#include "LivingTownCurrent61SourcePreparation.h"
#include "LivingTownTileData.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/SkeletalMeshSourceModel.h"
#include "Animation/AnimSequence.h"
#include "AssetCompilingManager.h"
#include "Animation/Skeleton.h"
#include "Factories/FbxAnimSequenceImportData.h"
#include "EditorFramework/AssetImportData.h"
#include "Materials/MaterialInterface.h"
#include "MeshDescription.h"
#include "MeshDescriptionBase.h"
#include "SkeletalMeshAttributes.h"
#include "Rendering/SkeletalMeshModel.h"
#include "Rendering/SkeletalMeshRenderData.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "HAL/FileManager.h"
#include "UObject/Package.h"
#include "UObject/UnrealType.h"
#if PLATFORM_WINDOWS
#include "Windows/WindowsHWrapper.h"
#endif

namespace Current61SourcePreparation
{
constexpr uint64 PackageCap=256ull<<20, BulkCap=96ull<<20;
constexpr int32 MaxV=250000,MaxT=100000,MaxUV=8,MaxBones=64,MaxSections=32,MaxMorph=16;
constexpr const TCHAR* BodyPath=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedDefault_v001/SK_Worker110Current61_BakedREST_v001.SK_Worker110Current61_BakedREST_v001");
constexpr const TCHAR* SkeletonPath=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedDefault_v001/SK_Worker110Current61_BakedREST_v001_Skeleton.SK_Worker110Current61_BakedREST_v001_Skeleton");
constexpr const TCHAR* PbrPath=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/SK_Worker110BakedPBR_v006.SK_Worker110BakedPBR_v006");
constexpr const TCHAR* IdlePath=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMotion_v001/A_Worker110_BakedIdle_v001.A_Worker110_BakedIdle_v001");
constexpr const TCHAR* WalkPath=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMotion_v001/A_Worker110_BakedWalk_v001.A_Worker110_BakedWalk_v001");

FString Json(const TSharedRef<FJsonObject>& O)
{
    FString Text;
    FJsonSerializer::Serialize(O,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Text));
    return Text.Len()<=131072?Text:TEXT("{\"status\":\"REFUSED\",\"reason\":\"JSON_bound\"}");
}
FString Refuse(const TCHAR* Why)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("REFUSED"));O->SetStringField(TEXT("reason"),Why);return Json(O);
}
bool Loaded(const UObject* O)
{
    return O&&!O->IsTemplate()&&!O->HasAnyFlags(RF_NeedLoad|RF_NeedPostLoad|RF_BeginDestroyed|RF_FinishDestroyed);
}
bool NoReparse(const FString& Absolute)
{
#if PLATFORM_WINDOWS
    FString N=Absolute.Replace(TEXT("/"),TEXT("\\"));
    if(N.Len()<3||N[1]!=':'||N[2]!='\\')return false;
    FString P=N.Left(3);TArray<FString> Parts;N.Mid(3).ParseIntoArray(Parts,TEXT("\\"),true);
    auto Check=[](const FString& X){DWORD A=GetFileAttributesW(*X);return A!=INVALID_FILE_ATTRIBUTES&&!(A&FILE_ATTRIBUTE_REPARSE_POINT);};
    if(!Check(P))return false;
    for(const FString& X:Parts){if(X==TEXT(".")||X==TEXT(".."))return false;P=FPaths::Combine(P,X);if(!Check(P))return false;}
    return true;
#else
    return false;
#endif
}
struct FPackageState
{
    UPackage* Package=nullptr;FString File,Hash;FDateTime Timestamp;int64 Bytes=-1;bool Dirty=false;bool Exists=false;
};
bool PackageState(UObject* O,FPackageState& S,bool RequireSaved)
{
    S.Package=O?O->GetOutermost():nullptr;
    if(!S.Package||S.Package==GetTransientPackage())return false;
    S.Dirty=S.Package->IsDirty();
    if(!FPackageName::TryConvertLongPackageNameToFilename(S.Package->GetName(),S.File,FPackageName::GetAssetPackageExtension()))return false;
    S.File=FPaths::ConvertRelativePathToFull(S.File);
    FString Content=FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir());FPaths::NormalizeDirectoryName(Content);
    if(!S.File.StartsWith(Content+TEXT("/")))return false;
    S.Exists=IFileManager::Get().FileExists(*S.File);
    if(!S.Exists)return !RequireSaved;
    S.Bytes=IFileManager::Get().FileSize(*S.File);S.Timestamp=IFileManager::Get().GetTimeStamp(*S.File);
    if(S.Bytes<=0||uint64(S.Bytes)>PackageCap||!NoReparse(S.File))return false;
    TArray<uint8> B;
    return FFileHelper::LoadFileToArray(B,*S.File)&&B.Num()==S.Bytes&&LivingTownTiles::HashBytes(B,S.Hash)&&IFileManager::Get().FileSize(*S.File)==S.Bytes;
}
bool SamePackage(const FPackageState& A,const FPackageState& B)
{
    return A.Package==B.Package&&A.File==B.File&&A.Hash==B.Hash&&A.Bytes==B.Bytes&&A.Timestamp==B.Timestamp&&A.Dirty==B.Dirty&&A.Exists==B.Exists;
}
TSharedRef<FJsonObject> PackageJson(const FPackageState& S)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("package"),S.Package?S.Package->GetName():TEXT(""));O->SetStringField(TEXT("file"),S.File);O->SetBoolField(TEXT("exists"),S.Exists);O->SetNumberField(TEXT("bytes"),double(S.Bytes));O->SetStringField(TEXT("timestamp_ticks"),LexToString(S.Timestamp.GetTicks()));O->SetStringField(TEXT("sha256"),S.Hash);O->SetBoolField(TEXT("dirty"),S.Dirty);return O;
}
struct FReferenceState
{
    TArray<FName> Names;TArray<int32> Parents;TArray<FTransform> Poses;
};
FReferenceState Reference(const FReferenceSkeleton& Ref)
{
    FReferenceState S;S.Poses=Ref.GetRefBonePose();
    for(int32 I=0;I<Ref.GetNum();++I){S.Names.Add(Ref.GetBoneName(I));S.Parents.Add(Ref.GetParentIndex(I));}
    return S;
}
bool SameReference(const FReferenceState& A,const FReferenceState& B)
{
    if(A.Names!=B.Names||A.Parents!=B.Parents||A.Poses.Num()!=B.Poses.Num())return false;
    for(int32 I=0;I<A.Poses.Num();++I)
    {
        if(A.Poses[I].GetTranslation()!=B.Poses[I].GetTranslation()||A.Poses[I].GetRotation()!=B.Poses[I].GetRotation()||A.Poses[I].GetScale3D()!=B.Poses[I].GetScale3D())return false;
    }
    return true;
}
struct FMaterialState
{
    UMaterialInterface* Material=nullptr;FName Slot,Imported;FMeshUVChannelInfo UV;
};
TArray<FMaterialState> Materials(const USkeletalMesh* Mesh)
{
    TArray<FMaterialState> S;
    for(const auto& M:Mesh->GetMaterials()){FMaterialState V;V.Material=M.MaterialInterface;V.Slot=M.MaterialSlotName;V.Imported=M.ImportedMaterialSlotName;V.UV=M.UVChannelData;S.Add(V);}
    return S;
}
bool SameMaterials(const TArray<FMaterialState>& A,const TArray<FMaterialState>& B)
{
    if(A.Num()!=B.Num())return false;
    for(int32 I=0;I<A.Num();++I)
    {
        if(A[I].Material!=B[I].Material||A[I].Slot!=B[I].Slot||A[I].Imported!=B[I].Imported||A[I].UV.bInitialized!=B[I].UV.bInitialized||A[I].UV.bOverrideDensities!=B[I].UV.bOverrideDensities)return false;
        for(int32 C=0;C<UE_ARRAY_COUNT(A[I].UV.LocalUVDensities);++C)if(A[I].UV.LocalUVDensities[C]!=B[I].UV.LocalUVDensities[C])return false;
    }
    return true;
}
bool Base(USkeletalMesh*& Body,USkeleton*& Skeleton,FPackageState& BodyPackage,FPackageState& SkeletonPackage)
{
    Body=FindObject<USkeletalMesh>(nullptr,BodyPath);Skeleton=FindObject<USkeleton>(nullptr,SkeletonPath);
    if(!Loaded(Body)||!Loaded(Skeleton)||Body->GetClass()!=USkeletalMesh::StaticClass()||Skeleton->GetClass()!=USkeleton::StaticClass()||Body->IsCompiling()||Body->GetSkeleton()!=Skeleton||Body->GetRefSkeleton().GetNum()!=62||Skeleton->GetReferenceSkeleton().GetNum()!=62)return false;
    return PackageState(Body,BodyPackage,true)&&PackageState(Skeleton,SkeletonPackage,true)&&!BodyPackage.Dirty&&!SkeletonPackage.Dirty&&BodyPackage.Bytes==12043447&&BodyPackage.Hash==TEXT("b3f22cd9736b8b3b148fe36d08f5bb00fd23c79cad8fc3e3553efd428cffbf0a")&&SkeletonPackage.Bytes==23914&&SkeletonPackage.Hash==TEXT("6769c3700866e27dc129f2e4bfcd701a1621e74ed1810d64f46c04fd2a7b89e6");
}
bool CachedBounds(const FMeshDescription& D)
{
    if(!D.Vertices().Num()||D.Vertices().GetArraySize()>MaxV||D.VertexInstances().GetArraySize()>MaxV||D.Triangles().GetArraySize()>MaxT||D.Polygons().GetArraySize()>MaxT||D.Edges().GetArraySize()>MaxT*3||D.PolygonGroups().GetArraySize()>MaxSections)return false;
    const FSkeletalMeshConstAttributes A(D);
    return A.HasSourceGeometryParts()&&A.GetNumSourceGeometryParts()==7&&A.HasBoneNameAttribute()&&A.HasBoneParentIndexAttribute()&&A.HasBonePoseAttribute()&&A.GetNumBones()>=61&&A.GetNumBones()<=MaxBones&&A.GetVertexSkinWeights().IsValid()&&A.GetVertexInstanceUVs().GetNumChannels()<=MaxUV&&A.GetMorphTargetNames().Num()<=MaxMorph&&A.GetSkinWeightProfileNames().Num()==1;
}
} // namespace Current61SourcePreparation

FString ULivingTownCurrent61SourcePreparation::CacheCurrent61PbrMeshDescription(USkeletalMesh* Mesh)
{
    using namespace Current61SourcePreparation;
    if(!IsInGameThread()||!GIsEditor)return Refuse(TEXT("Editor_GameThread_only"));
    if(!Loaded(Mesh)||Mesh->GetClass()!=USkeletalMesh::StaticClass()||Mesh->GetPathName()!=PbrPath||FindObject<USkeletalMesh>(nullptr,PbrPath)!=Mesh)return Refuse(TEXT("exact_already_loaded_PBR006_mesh_only_no_load"));
    if(Mesh->IsCompiling()||Mesh->GetLODNum()!=1||Mesh->GetNumSourceModels()!=1||Mesh->GetRefSkeleton().GetNum()!=62||Mesh->GetMaterials().Num()!=8)return Refuse(TEXT("finite_saved_PBR_mesh_bounds_or_compiling_no_wait"));
    const auto* Imported=Mesh->GetImportedModel();const auto* Render=Mesh->GetResourceForRendering();
    if(!Imported||Imported->LODModels.Num()!=1||!Render||Render->LODRenderData.Num()!=1)return Refuse(TEXT("imported_render_LOD0_required"));
    if(!Imported->LODModels[0].NumVertices||Imported->LODModels[0].NumVertices>uint32(MaxV)||Imported->LODModels[0].IndexBuffer.Num()>MaxT*3||Render->LODRenderData[0].GetNumVertices()>uint32(MaxV))return Refuse(TEXT("parent_Current61_allocation_bounds"));
    USkeletalMesh* Body=nullptr;USkeleton* Skeleton=nullptr;FPackageState BodyBefore,SkeletonBefore,MeshBefore;
    if(!Base(Body,Skeleton,BodyBefore,SkeletonBefore)||Mesh->GetSkeleton()!=Skeleton||!PackageState(Mesh,MeshBefore,true)||MeshBefore.Dirty||MeshBefore.Bytes!=12046294||MeshBefore.Hash!=TEXT("d184aedf07a2bf75261b356e86e2039e9c6a6f94e1a3338509db8591f32f9929"))return Refuse(TEXT("exact_clean_PBR006_and_two_original_saved_packages_required"));
    const FReferenceState MeshRef=Reference(Mesh->GetRefSkeleton()),BodyRef=Reference(Body->GetRefSkeleton()),SkelRef=Reference(Skeleton->GetReferenceSkeleton());
    const auto MaterialBefore=Materials(Mesh);const auto BodyMaterialBefore=Materials(Body);
    const FSkeletalMeshSourceModel& Source=Mesh->GetSourceModel(0);
    if(!Source.IsInitialized())return Refuse(TEXT("initialized_source_model_required"));
    const auto* Property=FindFProperty<FObjectPropertyBase>(FSkeletalMeshSourceModel::StaticStruct(),TEXT("MeshDescriptionBulkData"));
    auto* Bulk=Property?Cast<USkeletalMeshDescriptionBulkData>(Property->GetObjectPropertyValue_InContainer(&Source)):nullptr;
    if(!Bulk||!Bulk->IsBulkDataValid())return Refuse(TEXT("persisted_source_bulk_valid_before_cache_required"));
    const int64 BulkBytes=Bulk->GetBulkData().GetBulkDataSize();
    if(BulkBytes<=0||uint64(BulkBytes)>BulkCap)return Refuse(TEXT("source_bulk_96MiB_bound"));
    const FString BulkId=Bulk->GetBulkData().GetVersionedIdString();
    const bool CachedBefore=Bulk->HasCachedMeshDescription();bool Created=false,LoadedCache=false;FString Failure;
    if(!CachedBefore)
    {
        // CacheMeshDescription requires its transient wrapper. No source-model getter or bone repair.
        const auto* Preallocated=FindFProperty<FObjectPropertyBase>(UMeshDescriptionBaseBulkData::StaticClass(),TEXT("PreallocatedMeshDescription"));
        const bool HasTemplate=Preallocated&&Cast<UMeshDescriptionBase>(Preallocated->GetObjectPropertyValue_InContainer(Bulk));
        if(HasTemplate)Created=Bulk->CreateMeshDescription()!=nullptr;
        if(Created)LoadedCache=Bulk->CacheMeshDescription();
        if(!Created||!LoadedCache)Failure=TEXT("transient_wrapper_or_saved_bulk_cache_failed_stop");
    }
    const bool CachedAfter=Bulk->HasCachedMeshDescription();
    const UMeshDescriptionBase* Wrapper=Bulk->GetMeshDescription();
    const bool Bounds=CachedAfter&&Wrapper&&CachedBounds(Wrapper->GetMeshDescription());
    FPackageState MeshAfter,BodyAfter,SkeletonAfter;
    const bool PackageCustody=PackageState(Mesh,MeshAfter,true)&&PackageState(Body,BodyAfter,true)&&PackageState(Skeleton,SkeletonAfter,true)&&SamePackage(MeshBefore,MeshAfter)&&SamePackage(BodyBefore,BodyAfter)&&SamePackage(SkeletonBefore,SkeletonAfter);
    const bool ReferenceCustody=SameReference(MeshRef,Reference(Mesh->GetRefSkeleton()))&&SameReference(BodyRef,Reference(Body->GetRefSkeleton()))&&SameReference(SkelRef,Reference(Skeleton->GetReferenceSkeleton()))&&Mesh->GetSkeleton()==Skeleton&&Body->GetSkeleton()==Skeleton;
    const bool MaterialCustody=SameMaterials(MaterialBefore,Materials(Mesh))&&SameMaterials(BodyMaterialBefore,Materials(Body));
    const bool BulkCustody=Bulk->IsBulkDataValid()&&Bulk->GetBulkData().GetBulkDataSize()==BulkBytes&&Bulk->GetBulkData().GetVersionedIdString()==BulkId;
    auto O=MakeShared<FJsonObject>();const bool Good=Failure.IsEmpty()&&Bounds&&PackageCustody&&ReferenceCustody&&MaterialCustody&&BulkCustody;
    O->SetStringField(TEXT("status"),Good?TEXT("CACHED_SAVED_PBR006_SOURCE_DESCRIPTION_ONLY"):TEXT("HOLD_CACHE_STAGE_FAILED_STOP"));O->SetStringField(TEXT("reason"),Failure);O->SetStringField(TEXT("mesh"),Mesh->GetPathName());
    O->SetBoolField(TEXT("cached_before"),CachedBefore);O->SetBoolField(TEXT("transient_wrapper_created"),Created);O->SetBoolField(TEXT("saved_bulk_loaded_into_transient_cache"),LoadedCache);O->SetBoolField(TEXT("cached_after"),CachedAfter);O->SetNumberField(TEXT("saved_bulk_bytes"),double(BulkBytes));O->SetStringField(TEXT("saved_bulk_versioned_id"),BulkId);O->SetBoolField(TEXT("saved_bulk_unchanged"),BulkCustody);O->SetBoolField(TEXT("cached_parent_domain_bounds"),Bounds);
    O->SetBoolField(TEXT("three_saved_packages_bytes_and_dirty_unchanged"),PackageCustody);O->SetBoolField(TEXT("three_reference_skeletons_unchanged"),ReferenceCustody);O->SetBoolField(TEXT("all_material_slots_unchanged"),MaterialCustody);
    O->SetObjectField(TEXT("pbr_package_before"),PackageJson(MeshBefore));O->SetObjectField(TEXT("pbr_package_after"),PackageJson(MeshAfter));O->SetObjectField(TEXT("original_body_before"),PackageJson(BodyBefore));O->SetObjectField(TEXT("original_body_after"),PackageJson(BodyAfter));O->SetObjectField(TEXT("original_skeleton_before"),PackageJson(SkeletonBefore));O->SetObjectField(TEXT("original_skeleton_after"),PackageJson(SkeletonAfter));
    O->SetBoolField(TEXT("source_model_getter_bone_update_commit_build_save_or_reimport_called"),false);O->SetBoolField(TEXT("geometry_material_animation_or_runtime_qualified"),false);return Json(O);
}

FString ULivingTownCurrent61SourcePreparation::ReadCurrent61AnimationSourceName(UAnimSequence* Animation)
{
    using namespace Current61SourcePreparation;
    if(!IsInGameThread()||!GIsEditor)return Refuse(TEXT("Editor_GameThread_only"));
    if(!Loaded(Animation)||Animation->GetClass()!=UAnimSequence::StaticClass()||(Animation->GetPathName()!=IdlePath&&Animation->GetPathName()!=WalkPath)||FindObject<UAnimSequence>(nullptr,*Animation->GetPathName())!=Animation)return Refuse(TEXT("exact_already_loaded_two_baked_animations_only_no_load"));
    // Public aggregate includes the registered AnimSequence manager. Never waits or finishes compilation.
    const int32 RemainingBefore=FAssetCompilingManager::Get().GetNumRemainingAssets();
    if(RemainingBefore!=0)
    {
        auto Pending=MakeShared<FJsonObject>();Pending->SetStringField(TEXT("status"),TEXT("HOLD_ASSET_COMPILATION_PENDING_NO_WAIT"));Pending->SetNumberField(TEXT("registered_asset_compilations_before"),RemainingBefore);Pending->SetStringField(TEXT("compilation_guard_scope"),TEXT("all_registered_asset_managers_including_AnimSequence_not_per_asset"));return Json(Pending);
    }
    USkeletalMesh* Body=nullptr;USkeleton* Skeleton=nullptr;FPackageState BodyBefore,SkeletonBefore,AnimBefore;
    if(!Base(Body,Skeleton,BodyBefore,SkeletonBefore)||Animation->GetSkeleton()!=Skeleton||!PackageState(Animation,AnimBefore,false))return Refuse(TEXT("exact_base_skeleton_and_animation_package_custody_required"));
    const auto* ImportProperty=FindFProperty<FObjectPropertyBase>(UAnimSequence::StaticClass(),TEXT("AssetImportData"));
    auto* Data=ImportProperty?Cast<UFbxAnimSequenceImportData>(ImportProperty->GetObjectPropertyValue_InContainer(Animation)):nullptr;
    const auto* NameProperty=FindFProperty<FStrProperty>(UFbxAnimSequenceImportData::StaticClass(),TEXT("SourceAnimationName"));
    if(!Data||Data->GetClass()!=UFbxAnimSequenceImportData::StaticClass()||!NameProperty)return Refuse(TEXT("actual_exact_FbxAnimSequenceImportData_and_FStrProperty_required"));
    const FString Take=NameProperty->GetPropertyValue_InContainer(Data);const auto Filenames=Data->ExtractFilenames();
    if(Take.IsEmpty()||Take.Len()>256||Filenames.Num()!=1||Filenames[0].IsEmpty()||Filenames[0].Len()>4096)return Refuse(TEXT("one_bounded_source_filename_and_nonempty_take_required"));
    const FString Class=Data->GetClass()->GetPathName();const bool ImportDirtyBefore=Data->GetOutermost()->IsDirty();
    FPackageState AnimAfter,BodyAfter,SkeletonAfter;
    const int32 RemainingAfter=FAssetCompilingManager::Get().GetNumRemainingAssets();
    const bool Custody=RemainingAfter==0&&PackageState(Animation,AnimAfter,false)&&PackageState(Body,BodyAfter,true)&&PackageState(Skeleton,SkeletonAfter,true)&&SamePackage(AnimBefore,AnimAfter)&&SamePackage(BodyBefore,BodyAfter)&&SamePackage(SkeletonBefore,SkeletonAfter)&&ImportDirtyBefore==Data->GetOutermost()->IsDirty()&&Animation->GetSkeleton()==Skeleton&&NameProperty->GetPropertyValue_InContainer(Data)==Take&&Data->ExtractFilenames()==Filenames;
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),Custody?TEXT("READ_ONLY_CURRENT61_ANIMATION_IMPORT_PROVENANCE"):TEXT("HOLD_READ_ONLY_CUSTODY_FAILED"));O->SetStringField(TEXT("animation"),Animation->GetPathName());O->SetStringField(TEXT("import_data_class"),Class);O->SetStringField(TEXT("native_property_name"),NameProperty->GetName());O->SetStringField(TEXT("source_take"),Take);O->SetStringField(TEXT("source_filename"),Filenames[0]);O->SetStringField(TEXT("skeleton"),Skeleton->GetPathName());O->SetBoolField(TEXT("package_bytes_presence_and_dirty_unchanged"),Custody);O->SetObjectField(TEXT("animation_package_before"),PackageJson(AnimBefore));O->SetObjectField(TEXT("animation_package_after"),PackageJson(AnimAfter));O->SetObjectField(TEXT("original_body_before"),PackageJson(BodyBefore));O->SetObjectField(TEXT("original_body_after"),PackageJson(BodyAfter));O->SetObjectField(TEXT("original_skeleton_before"),PackageJson(SkeletonBefore));O->SetObjectField(TEXT("original_skeleton_after"),PackageJson(SkeletonAfter));O->SetNumberField(TEXT("registered_asset_compilations_before"),RemainingBefore);O->SetNumberField(TEXT("registered_asset_compilations_after"),RemainingAfter);O->SetStringField(TEXT("compilation_guard_scope"),TEXT("all_registered_asset_managers_including_AnimSequence_not_per_asset"));O->SetBoolField(TEXT("load_setter_save_build_reimport_or_pose_evaluation_called"),false);O->SetBoolField(TEXT("take_matches_caller_source_FBX_or_motion_qualified"),false);return Json(O);
}
