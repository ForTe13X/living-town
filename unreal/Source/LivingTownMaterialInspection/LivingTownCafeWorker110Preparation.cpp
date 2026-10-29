#include "LivingTownCafeWorker110Preparation.h"
#include "LivingTownAvatarPreparation.h"
#include "Animation/AnimSequence.h"
#include "Animation/BlendSpace1D.h"
#include "Animation/Skeleton.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/SkeletalMeshSocket.h"
#include "Engine/SkinnedAssetCommon.h"
#include "Materials/Material.h"
#include "Rendering/SkeletalMeshRenderData.h"
#include "Rendering/SkeletalMeshLODRenderData.h"
#include "Rendering/SkinWeightVertexBuffer.h"
#include "SkinnedAssetCompiler.h"
#include "Exporters/Exporter.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/MemoryWriter.h"
#include "Misc/FileHelper.h"
#include "Misc/SecureHash.h"
#include "Misc/Paths.h"
#include "Misc/PackageName.h"
#include "HAL/PlatformMisc.h"
#include "HAL/FileManager.h"
#include "UObject/Package.h"
#include "UObject/SavePackage.h"
#include "UObject/UObjectIterator.h"
#include "UObject/UnrealType.h"
#include "UObject/UObjectGlobals.h"

namespace
{
const TCHAR* SourceMeshPath=TEXT("/Game/LivingTown_UEPilot/CafeWorkerBen_v001/SK_CafeWorkerBen_v001.SK_CafeWorkerBen_v001");
const TCHAR* SkeletonPath=TEXT("/Game/LivingTown_UEPilot/CafeWorkerMultiviewV002_WalkTrial_v001/tripo_node_183abe00-c177-48f4-b834-6c25e_Skeleton.tripo_node_183abe00-c177-48f4-b834-6c25e_Skeleton");
const TCHAR* IdlePath=TEXT("/Game/LivingTown_UEPilot/CafeWorkerMultiviewV002_IdleOnlyTrial_v002/idle.idle");
const TCHAR* WalkPath=TEXT("/Game/LivingTown_UEPilot/CafeWorkerMultiviewV002_WalkTrial_v001/walk.walk");
const TCHAR* SelectedMaterialPath=TEXT("/Game/LivingTown_UEPilot/CharacterNormalStrength_v001/M_Normal035.M_Normal035");
const TCHAR* MeshPackage=TEXT("/Game/LivingTown_UEPilot/CafeWorkerBen110_v001/SK_CafeWorkerBen110_v001");
const TCHAR* MotionPackage=TEXT("/Game/LivingTown_UEPilot/CafeWorkerBen110_v001/BS_CafeWorkerIdleWalk110_v001");
const TCHAR* ExpectedLegacyHash=TEXT("c26a6aba81b5e27656d455815670791054c5a68a");
const FName PalmName(TEXT("UsePalm_R"));
struct FSourceFile { const TCHAR* Relative; int64 Bytes; const TCHAR* SHA1; };
const FSourceFile OriginalFiles[]={
    {TEXT("LivingTown_UEPilot/CafeWorkerConfidenceNormal_v001/M_ConfidenceMaskedFace_v001.uasset"),72418,TEXT("f9e876b8a33140f84b8b5ac0522b8321bd66987d")},
    {TEXT("LivingTown_UEPilot/CafeWorkerConfidenceNormal_v001/M_EncodedOriginal_v001.uasset"),72560,TEXT("ded9403dfeb3ea612d5eab04e3f1d78156be66de")},
    {TEXT("LivingTown_UEPilot/CafeWorkerConfidenceNormal_v001/T_baked_Encoded_v001.uasset"),61327742,TEXT("05dd8bfaa4e412870d3794e16582db7652fc580e")},
    {TEXT("LivingTown_UEPilot/CafeWorkerConfidenceNormal_v001/T_confidence_Encoded_v001.uasset"),43001,TEXT("b6938b2038132a46b9d16b757d204d85c31b456f")},
    {TEXT("LivingTown_UEPilot/CafeWorkerConfidenceNormal_v001/T_OriginalNormal_Encoded_v001.uasset"),7287972,TEXT("3cdeb83c7f50fe979b51c96a923c72dc098e3980")},
    {TEXT("LivingTown_UEPilot/CafeWorkerMultiviewV002_WalkTrial_v001/tripo_node_183abe00-c177-48f4-b834-6c25e.uasset"),2656366,TEXT("b871fb30891a5401d6b730ece0e70114cdc96b61")},
    {TEXT("LivingTown_UEPilot/CafeWorkerMultiviewV002_WalkTrial_v001/tripo_node_183abe00-c177-48f4-b834-6c25e_BaseColor.uasset"),11612084,TEXT("901887aebca3884c7397d9bf3e92f75b293ad973")},
    {TEXT("LivingTown_UEPilot/CafeWorkerMultiviewV002_WalkTrial_v001/tripo_node_183abe00-c177-48f4-b834-6c25e_material.uasset"),61233,TEXT("6158fcaf916b7a58fa541b9803d20c11642be580")},
    {TEXT("LivingTown_UEPilot/CafeWorkerMultiviewV002_WalkTrial_v001/tripo_node_183abe00-c177-48f4-b834-6c25e_Metallic-tripo_node_18.uasset"),3418029,TEXT("9a75f80a56c918bb0beb545bd79960dad265e0e4")},
    {TEXT("LivingTown_UEPilot/CafeWorkerMultiviewV002_WalkTrial_v001/tripo_node_183abe00-c177-48f4-b834-6c25e_Normal_Bake.uasset"),7295182,TEXT("d89bc806302309c34443898404ce4a1b50c341b4")},
    {TEXT("LivingTown_UEPilot/CafeWorkerMultiviewV002_WalkTrial_v001/tripo_node_183abe00-c177-48f4-b834-6c25e_Skeleton.uasset"),14886,TEXT("10bc228dced61c6377f1ca3b71fc35405407d26a")},
    {TEXT("LivingTown_UEPilot/CafeWorkerMultiviewV002_WalkTrial_v001/walk.uasset"),597203,TEXT("7e3df89aa43cf54e6a4b265accca8b888edd94eb")},
    {TEXT("LivingTown_UEPilot/CafeWorkerNeckConfidence_v001/M_FaceNeck_Confidence_v001.uasset"),72206,TEXT("203f80b6980615172ebc174b635eb3b2bc68ea4e")},
    {TEXT("LivingTown_UEPilot/CafeWorkerNeckConfidence_v001/T_confidence_Encoded_v001.uasset"),57506,TEXT("c9e799aca482810e8b529efaa9494ffe7c5b49b2")},
    {TEXT("LivingTown_UEPilot/CafeWorkerMultiviewV002_IdleOnlyTrial_v002/idle.uasset"),2612257,TEXT("2c02ebb80d0fccae31900a649ea398f51ccd755d")},
    {TEXT("LivingTown_UEPilot/CafeWorkerBen_v001/BS_CafeWorkerIdleWalk_v001.uasset"),3725,TEXT("0b4062bd327ab7540c518d45d0a6a338947971d7")},
    {TEXT("LivingTown_UEPilot/CafeWorkerBen_v001/SK_CafeWorkerBen_v001.uasset"),2656387,TEXT("725e9c0e1cbac83f8f78a72b74dc2ce208f93360")},
    {TEXT("LivingTown_UEPilot/CharacterNormalStrength_v001/M_Normal035.uasset"),74211,TEXT("fa535086472e2ac6955b8f1bb8e2701774d3c7d3")},
    {TEXT("LivingTown_UEPilot/CharacterNormalStrength_v001/M_Normal060.uasset"),73873,TEXT("f7d2ab78dfb4a4e9671eabce242b7202cbc27875")},
};
FString Json(const TSharedRef<FJsonObject>& O){FString S;auto W=TJsonWriterFactory<>::Create(&S);FJsonSerializer::Serialize(O,W);return S;}
TArray<TSharedPtr<FJsonValue>> V(const FVector& P){return {MakeShared<FJsonValueNumber>(P.X),MakeShared<FJsonValueNumber>(P.Y),MakeShared<FJsonValueNumber>(P.Z)};}
FString ObjectPath(const UObject* O){return O?O->GetPathName():TEXT("");}
FString Hash(const TArray<uint8>& Bytes){uint8 D[20];FSHA1::HashBuffer(Bytes.GetData(),Bytes.Num(),D);return BytesToHex(D,20).ToLower();}
bool Write(const FString& Root,const FString& Name,const TSharedRef<FJsonObject>& O)
{return FFileHelper::SaveStringToFile(Json(O),*(Root/Name),FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);}
bool ArtifactContext(bool Build,FString& Root,FString& Why)
{
    if(!IsInGameThread()||!GIsEditor||IsRunningCommandlet()){Why=TEXT("editor_game_thread_non_commandlet_required");return false;}
    FString Out=FPlatformMisc::GetEnvironmentVariable(TEXT("LIVING_TOWN_BOOTSTRAP_OUTPUT"));
    if(Out.IsEmpty()){Why=TEXT("owned_bootstrap_output_required");return false;}
    Out=FPaths::ConvertRelativePathToFull(Out);FPaths::NormalizeDirectoryName(Out);
    FString Project=FPaths::ConvertRelativePathToFull(FPaths::ProjectDir());FPaths::NormalizeDirectoryName(Project);
    if(!Out.StartsWith(TEXT("F:/"))||Project!=Out/TEXT("Project")||FPaths::GetCleanFilename(Out)!=(Build?TEXT("Author"):TEXT("Reload")))
    {Why=TEXT("exact_F_owned_Author_or_Reload_Project_sibling_required");return false;}
    Root=Out/TEXT("CafeWorker110");if(IFileManager::Get().DirectoryExists(*Root)||!IFileManager::Get().MakeDirectory(*Root,true))
    {Why=TEXT("fresh_owned_artifact_subdirectory_required");return false;}return true;
}
bool GuardOriginalFiles(const TSharedRef<FJsonObject>& Report,const TCHAR* Field,FString& Why)
{
    TArray<TSharedPtr<FJsonValue>> Rows;bool Good=true;
    for(const auto& Source:OriginalFiles)
    {
        auto Row=MakeShared<FJsonObject>();Row->SetStringField(TEXT("content_relative"),Source.Relative);Row->SetNumberField(TEXT("expected_bytes"),Source.Bytes);Row->SetStringField(TEXT("expected_SHA1"),Source.SHA1);
        FString File=FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()/Source.Relative);const int64 Size=IFileManager::Get().FileSize(*File);Row->SetNumberField(TEXT("actual_bytes"),Size);TArray<uint8> Bytes;
        const bool Loaded=FPaths::IsUnderDirectory(File,FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()))&&Size==Source.Bytes&&Size<=64ll*1024*1024&&FFileHelper::LoadFileToArray(Bytes,*File);
        FString Actual=Loaded?Hash(Bytes):TEXT("");Row->SetStringField(TEXT("actual_SHA1"),Actual);
        FString Package=TEXT("/Game/")+FPaths::ChangeExtension(FString(Source.Relative),TEXT(""));const UPackage* P=FindPackage(nullptr,*Package);Row->SetBoolField(TEXT("package_loaded"),P!=nullptr);Row->SetBoolField(TEXT("package_dirty"),P&&P->IsDirty());Rows.Add(MakeShared<FJsonValueObject>(Row));
        if(!Loaded||Actual!=Source.SHA1||(P&&P->IsDirty())){Good=false;Why=TEXT("original_package_bytes_or_dirty_state_changed: ")+FString(Source.Relative);break;}
    }
    Report->SetArrayField(Field,Rows);return Good;
}
bool NoPilotMeshLoaded(FString& Why)
{
    for(TObjectIterator<USkeletalMesh> It;It;++It)if(It->GetPathName().StartsWith(TEXT("/Game/LivingTown_UEPilot/")))
    {Why=TEXT("pilot_mesh_already_loaded_before_cold_material_gate: ")+It->GetPathName();return false;}return true;
}
UMaterial* ColdMaterial(const FString& Root,const TSharedRef<FJsonObject>& Report,FString& Why)
{
    if(!NoPilotMeshLoaded(Why))return nullptr;
    auto M=LoadObject<UMaterial>(nullptr,SelectedMaterialPath);auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("path"),ObjectPath(M));O->SetStringField(TEXT("class"),M?M->GetClass()->GetPathName():TEXT(""));
    const bool Exact=M&&M->GetClass()==UMaterial::StaticClass()&&M->GetPathName()==SelectedMaterialPath;
    const bool Usage=Exact&&M->GetUsageByFlag(MATUSAGE_SkeletalMesh);O->SetBoolField(TEXT("actual_UMaterial_skeletal_usage_before_any_pilot_mesh_load"),Usage);O->SetBoolField(TEXT("automatically_set_usage_in_editor"),M&&M->bAutomaticallySetUsageInEditor);O->SetBoolField(TEXT("tangent_space_normal"),M&&M->bTangentSpaceNormal);Report->SetObjectField(TEXT("cold_selected_material"),O);
    if(!Write(Root,TEXT("COLD_MATERIAL.json"),O)||!Exact||!Usage||M->bAutomaticallySetUsageInEditor||!M->bTangentSpaceNormal)
    {Why=TEXT("exact_cold_M035_UMaterial_skeletal_usage_without_auto_enable_required");return nullptr;}
    const FString Graph=Root/TEXT("COLD_M035_GRAPH.t3d");
    UClass* ExporterClass=FindObject<UClass>(nullptr,TEXT("/Script/UnrealEd.ObjectExporterT3D"));
    UExporter* Exporter=ExporterClass&&ExporterClass->IsChildOf(UExporter::StaticClass())?NewObject<UExporter>(GetTransientPackage(),ExporterClass):nullptr;
    if(!Exporter||IFileManager::Get().FileExists(*Graph)||UExporter::ExportToFile(M,Exporter,*Graph,false,false,false)!=1||IFileManager::Get().FileSize(*Graph)<=0||!NoPilotMeshLoaded(Why))
    {Why=TEXT("cold_material_T3D_export_before_mesh_load_required: ")+Why;return nullptr;}
    O->SetStringField(TEXT("native_graph_file"),Graph);O->SetBoolField(TEXT("host_exact_graph_comparison_required"),true);if(!Write(Root,TEXT("COLD_MATERIAL.json"),O)){Why=TEXT("cold_material_metadata_write_failed");return nullptr;}return M;
}
bool Fresh(const TCHAR* Package)
{
    FString File=FPaths::ConvertRelativePathToFull(FPackageName::LongPackageNameToFilename(Package,FPackageName::GetAssetPackageExtension()));return FPaths::IsUnderDirectory(File,FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()))&&!FindPackage(nullptr,Package)&&!IFileManager::Get().FileExists(*File);
}
void Finish(USkeletalMesh* Mesh){USkinnedAsset* Assets[]={Mesh};FSkinnedAssetCompilingManager::Get().FinishCompilation(MakeArrayView(Assets));}
bool Shape(USkeletalMesh* Mesh,FString& Why)
{
    if(!Mesh||!Mesh->GetSkeleton()||Mesh->GetSkeleton()->GetPathName()!=SkeletonPath||Mesh->GetRefSkeleton().GetNum()!=61||Mesh->GetMaterials().Num()!=1){Why=TEXT("fixed_61_family_skeleton_and_one_slot_required");return false;}
    Finish(Mesh);const auto* R=Mesh->GetResourceForRendering();if(!R||R->LODRenderData.Num()!=1){Why=TEXT("one_native_LOD_required");return false;}
    const auto& L=R->LODRenderData[0];const auto& B=L.StaticVertexBuffers;const auto& S=L.SkinWeightVertexBuffer;
    if(L.GetNumVertices()!=10707||S.GetNumVertices()!=10707||L.RenderSections.Num()!=1||B.StaticMeshVertexBuffer.GetNumVertices()!=10707||!B.PositionVertexBuffer.GetVertexData()||!B.StaticMeshVertexBuffer.GetTangentData()||!B.StaticMeshVertexBuffer.GetTexCoordData()||!S.GetDataVertexBuffer()->GetWeightData())
    {Why=TEXT("qualified_10707_vertex_single_section_CPU_readback_required");return false;}return true;
}
TSharedRef<FJsonObject> Palm(USkeletalMesh* Mesh)
{
    auto O=MakeShared<FJsonObject>();const auto* P=Mesh?Mesh->FindSocket(PalmName):nullptr;O->SetBoolField(TEXT("present"),P!=nullptr);
    if(P){O->SetStringField(TEXT("name"),P->SocketName.ToString());O->SetStringField(TEXT("bone"),P->BoneName.ToString());O->SetBoolField(TEXT("mesh_owned"),P->GetOuter()==Mesh);O->SetBoolField(TEXT("force_always_animated"),P->bForceAlwaysAnimated);O->SetArrayField(TEXT("relative_location_cm"),V(P->RelativeLocation));O->SetArrayField(TEXT("relative_rotation_pitch_yaw_roll"),V(FVector(P->RelativeRotation.Pitch,P->RelativeRotation.Yaw,P->RelativeRotation.Roll)));O->SetArrayField(TEXT("relative_scale"),V(P->RelativeScale));}return O;
}
bool SamePalm(USkeletalMesh* A,USkeletalMesh* B)
{
    const auto* X=A->FindSocket(PalmName);const auto* Y=B->FindSocket(PalmName);return A->GetMeshOnlySocketList().Num()==1&&B->GetMeshOnlySocketList().Num()==1&&X&&Y&&X->GetOuter()==A&&Y->GetOuter()==B&&X->SocketName==PalmName&&Y->SocketName==PalmName&&X->BoneName==FName(TEXT("hand_r"))&&Y->BoneName==X->BoneName&&X->RelativeLocation==Y->RelativeLocation&&X->RelativeRotation==Y->RelativeRotation&&X->RelativeScale==Y->RelativeScale&&X->bForceAlwaysAnimated&&Y->bForceAlwaysAnimated;
}
TSharedRef<FJsonObject> SlotMetadata(const FSkeletalMaterial& S)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("slot_name"),S.MaterialSlotName.ToString());O->SetStringField(TEXT("imported_slot_name"),S.ImportedMaterialSlotName.ToString());O->SetStringField(TEXT("overlay"),ObjectPath(S.OverlayMaterialInterface));O->SetBoolField(TEXT("UV_density_initialized"),S.UVChannelData.bInitialized);O->SetBoolField(TEXT("UV_density_override"),S.UVChannelData.bOverrideDensities);TArray<TSharedPtr<FJsonValue>> D;for(int32 I=0;I<TEXSTREAM_MAX_NUM_UVCHANNELS;++I)D.Add(MakeShared<FJsonValueNumber>(S.UVChannelData.LocalUVDensities[I]));O->SetArrayField(TEXT("UV_density"),D);return O;
}
bool SameSlotMetadata(const FSkeletalMaterial& A,const FSkeletalMaterial& B)
{
    if(A.MaterialSlotName!=B.MaterialSlotName||A.ImportedMaterialSlotName!=B.ImportedMaterialSlotName||A.OverlayMaterialInterface!=B.OverlayMaterialInterface||A.UVChannelData.bInitialized!=B.UVChannelData.bInitialized||A.UVChannelData.bOverrideDensities!=B.UVChannelData.bOverrideDensities)return false;
    for(int32 I=0;I<TEXSTREAM_MAX_NUM_UVCHANNELS;++I)if(A.UVChannelData.LocalUVDensities[I]!=B.UVChannelData.LocalUVDensities[I])return false;return true;
}
bool ObserveMesh(USkeletalMesh* Mesh,const FString& Root,const FString& Label,TSharedPtr<FJsonObject>& Result,FString& Why)
{
    if(!Shape(Mesh,Why))return false;
    const FString LegacyText=ULivingTownAvatarPreparation::ReadAvatarSnapshot(Mesh,nullptr);const FString LegacyFile=Root/(Label+TEXT("_LEGACY.json"));if(!FFileHelper::SaveStringToFile(LegacyText,*LegacyFile,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM)){Why=TEXT("legacy_readback_artifact_write_failed");return false;}
    TSharedPtr<FJsonObject> Legacy;auto Reader=TJsonReaderFactory<>::Create(LegacyText);if(!FJsonSerializer::Deserialize(Reader,Legacy)||!Legacy){Why=TEXT("legacy_snapshot_JSON_required");return false;}
    Result=MakeShared<FJsonObject>();Result->SetStringField(TEXT("mesh"),Mesh->GetPathName());Result->SetStringField(TEXT("legacy_readback_file"),LegacyFile);FString LegacyStatus,LegacyHash;Legacy->TryGetStringField(TEXT("status"),LegacyStatus);Legacy->TryGetStringField(TEXT("geometry_reference_skin_SHA1"),LegacyHash);Result->SetStringField(TEXT("legacy_status"),LegacyStatus);Result->SetStringField(TEXT("legacy_reference_render_skin_SHA1"),LegacyHash);Result->SetObjectField(TEXT("palm"),Palm(Mesh));Result->SetObjectField(TEXT("material_slot_metadata"),SlotMetadata(Mesh->GetMaterials()[0]));Result->SetStringField(TEXT("material"),ObjectPath(Mesh->GetMaterials()[0].MaterialInterface));
    const auto& L=Mesh->GetResourceForRendering()->LODRenderData[0];const auto& B=L.StaticVertexBuffers;const auto& S=L.SkinWeightVertexBuffer;
    uint32 Magic=0x31564255,Version=1,N=L.GetNumVertices(),UVs=B.StaticMeshVertexBuffer.GetNumTexCoords(),FullUV=B.StaticMeshVertexBuffer.GetUseFullPrecisionUVs()?1:0,HighTangent=B.StaticMeshVertexBuffer.GetUseHighPrecisionTangentBasis()?1:0;
    if(UVs<1||UVs>8){Why=TEXT("bounded_existing_UV_channel_count_required");return false;}TArray<uint8> Bytes;FMemoryWriter W(Bytes);W<<Magic;W<<Version;W<<N;W<<UVs;W<<FullUV;W<<HighTangent;
    for(uint32 I=0;I<N;++I)
    {
        auto X=B.StaticMeshVertexBuffer.VertexTangentX(I);auto Y=B.StaticMeshVertexBuffer.VertexTangentY(I);auto Z=B.StaticMeshVertexBuffer.VertexTangentZ(I);
        if(X.ContainsNaN()||Y.ContainsNaN()||Z.ContainsNaN()){Why=TEXT("nonfinite_decoded_basis");return false;}W<<X;W<<Y;W<<Z;
        for(uint32 U=0;U<UVs;++U){auto UV=B.StaticMeshVertexBuffer.GetVertexUV(I,U);if(!FMath::IsFinite(UV.X)||!FMath::IsFinite(UV.Y)){Why=TEXT("nonfinite_decoded_UV");return false;}W<<UV;}
    }
    W.Close();const FString Binary=Root/(Label+TEXT("_UV_BASIS.bin"));if(IFileManager::Get().FileExists(*Binary)||!FFileHelper::SaveArrayToFile(Bytes,*Binary)){Why=TEXT("fresh_UV_basis_artifact_required");return false;}
    Result->SetStringField(TEXT("decoded_UV_full_basis_SHA1"),Hash(Bytes));Result->SetStringField(TEXT("decoded_UV_full_basis_file"),Binary);Result->SetNumberField(TEXT("decoded_UV_full_basis_bytes"),Bytes.Num());Result->SetNumberField(TEXT("vertices"),N);Result->SetNumberField(TEXT("UV_channels"),UVs);Result->SetBoolField(TEXT("full_precision_UV"),FullUV!=0);Result->SetBoolField(TEXT("high_precision_tangent_basis"),HighTangent!=0);Result->SetNumberField(TEXT("skin_index_bytes"),S.GetBoneIndexByteSize());Result->SetNumberField(TEXT("skin_weight_bytes"),S.GetBoneWeightByteSize());Result->SetBoolField(TEXT("variable_bone_influences"),S.GetVariableBonesPerVertex());Result->SetBoolField(TEXT("package_dirty"),Mesh->GetOutermost()->IsDirty());Result->SetBoolField(TEXT("skeleton_package_dirty"),Mesh->GetSkeleton()->GetOutermost()->IsDirty());if(!Write(Root,Label+TEXT("_MESH.json"),Result.ToSharedRef())){Why=TEXT("mesh_metadata_write_failed");return false;}
    if(LegacyStatus!=TEXT("READ_NEW61_REFERENCE_RENDER_SKIN_GEOMETRY")||LegacyHash!=ExpectedLegacyHash){Why=TEXT("original_qualified_reference_render_skin_digest_required");return false;}return true;
}
bool SameMeshData(const TSharedPtr<FJsonObject>& A,const TSharedPtr<FJsonObject>& B)
{
    return A&&B&&A->GetStringField(TEXT("legacy_reference_render_skin_SHA1"))==B->GetStringField(TEXT("legacy_reference_render_skin_SHA1"))&&A->GetStringField(TEXT("decoded_UV_full_basis_SHA1"))==B->GetStringField(TEXT("decoded_UV_full_basis_SHA1"))&&A->GetNumberField(TEXT("skin_index_bytes"))==B->GetNumberField(TEXT("skin_index_bytes"))&&A->GetNumberField(TEXT("skin_weight_bytes"))==B->GetNumberField(TEXT("skin_weight_bytes"))&&A->GetBoolField(TEXT("variable_bone_influences"))==B->GetBoolField(TEXT("variable_bone_influences"));
}
TSharedRef<FJsonObject> Clip(UAnimSequence* A)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("path"),ObjectPath(A));if(A){O->SetStringField(TEXT("skeleton"),ObjectPath(A->GetSkeleton()));O->SetNumberField(TEXT("length_seconds"),A->GetPlayLength());O->SetNumberField(TEXT("RateScale"),A->RateScale);O->SetBoolField(TEXT("root_motion_enabled"),A->bEnableRootMotion);O->SetNumberField(TEXT("additive_type"),int32(A->GetAdditiveAnimType()));O->SetNumberField(TEXT("sampled_keys"),A->GetNumberOfSampledKeys());O->SetBoolField(TEXT("package_dirty"),A->GetOutermost()->IsDirty());}return O;
}
bool Clips(UAnimSequence* Idle,UAnimSequence* Walk,USkeleton* Skeleton)
{
    return Idle&&Walk&&Idle!=Walk&&Idle->GetPathName()==IdlePath&&Walk->GetPathName()==WalkPath&&Idle->GetSkeleton()==Skeleton&&Walk->GetSkeleton()==Skeleton&&Idle->RateScale==1.f&&Walk->RateScale==1.f&&Idle->GetPlayLength()>0&&Walk->GetPlayLength()>0&&!Idle->bEnableRootMotion&&!Walk->bEnableRootMotion&&Idle->GetAdditiveAnimType()==AAT_None&&Walk->GetAdditiveAnimType()==AAT_None&&!Idle->GetOutermost()->IsDirty()&&!Walk->GetOutermost()->IsDirty();
}
bool Sampler(UBlendSpace1D* Motion,UAnimSequence* Idle,UAnimSequence* Walk,const FString& Root,const TSharedRef<FJsonObject>& Report,FString& Why)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("asset"),ObjectPath(Motion));O->SetObjectField(TEXT("idle"),Clip(Idle));O->SetObjectField(TEXT("walk"),Clip(Walk));Report->SetObjectField(TEXT("sampler"),O);
    if(!Motion||Motion->GetClass()!=UBlendSpace1D::StaticClass()||Motion->GetPathName()!=FString(MotionPackage)+TEXT(".BS_CafeWorkerIdleWalk110_v001")||!Clips(Idle,Walk,Motion->GetSkeleton())){Why=TEXT("fixed_full_rate1_clip_and_BlendSpace1D_identities_required");Write(Root,TEXT("SAMPLER.json"),O);return false;}
    const auto& Axis=Motion->GetBlendParameter(0);O->SetNumberField(TEXT("axis_min"),Axis.Min);O->SetNumberField(TEXT("axis_max"),Axis.Max);O->SetNumberField(TEXT("runtime_segments"),Motion->GetBlendSpaceData().Segments.Num());O->SetNumberField(TEXT("runtime_triangles"),Motion->GetBlendSpaceData().Triangles.Num());O->SetNumberField(TEXT("grid_samples"),Motion->GetGridSamples().Num());O->SetBoolField(TEXT("scale_animation_with_filtered_input"),Motion->bScaleAnimation);O->SetNumberField(TEXT("effective_1D_axis_to_scale_enum"),int32(Motion->bScaleAnimation?BSA_X:BSA_None));O->SetStringField(TEXT("effective_1D_axis_source"),TEXT("public UBlendSpace1D::bScaleAnimation; exact native GetAxisToScale override, no protected getter called"));O->SetBoolField(TEXT("package_dirty"),Motion->GetOutermost()->IsDirty());O->SetNumberField(TEXT("sample_weight_smoothing_speed"),Motion->TargetWeightInterpolationSpeedPerSec);
    bool Good=Motion->GetBlendSamples().Num()==2&&Axis.Min==0.f&&Axis.Max==110.f&&!Axis.bSnapToGrid&&!Axis.bWrapInput&&Motion->GetBlendSpaceData().Segments.Num()>0&&!Motion->bScaleAnimation&&Motion->TargetWeightInterpolationSpeedPerSec==0.f&&Motion->InterpolationParam[0].InterpolationTime==0.f;
    TArray<TSharedPtr<FJsonValue>> Raw,Probes;bool HasIdle=false,HasWalk=false;
    for(const auto& S:Motion->GetBlendSamples()){auto Row=MakeShared<FJsonObject>();Row->SetStringField(TEXT("animation"),ObjectPath(S.Animation));Row->SetArrayField(TEXT("value"),V(S.SampleValue));Row->SetNumberField(TEXT("RateScale"),S.RateScale);Row->SetBoolField(TEXT("single_frame"),S.bUseSingleFrameForBlending);Row->SetBoolField(TEXT("mirror"),S.bMirror);Raw.Add(MakeShared<FJsonValueObject>(Row));Good&=S.Animation&&S.RateScale==1.f&&!S.bUseSingleFrameForBlending&&!S.bMirror;if(S.Animation==Idle&&S.SampleValue==FVector::ZeroVector)HasIdle=true;else if(S.Animation==Walk&&S.SampleValue==FVector(110,0,0))HasWalk=true;else Good=false;}
    Good&=HasIdle&&HasWalk;
    for(const double Fraction:{0.0,0.5,1.0})
    {
        TArray<FBlendSampleData> Weights;int32 Segment=INDEX_NONE;bool Got=Motion->GetSamplesFromBlendInput(FVector(110*Fraction,0,0),Weights,Segment,true);auto Probe=MakeShared<FJsonObject>();Probe->SetNumberField(TEXT("speed_cm_s"),110*Fraction);Probe->SetBoolField(TEXT("sampler_returned_data"),Got);TArray<TSharedPtr<FJsonValue>> Rows;double IW=0,WW=0;bool Valid=Got&&Weights.Num()>=1&&Weights.Num()<=2;
        for(const auto& W:Weights){auto Row=MakeShared<FJsonObject>();Row->SetStringField(TEXT("animation"),ObjectPath(W.Animation));Row->SetNumberField(TEXT("weight"),W.TotalWeight);Row->SetNumberField(TEXT("source_index"),W.SampleDataIndex);Rows.Add(MakeShared<FJsonValueObject>(Row));Valid&=FMath::IsFinite(W.TotalWeight)&&W.TotalWeight>0&&(W.Animation==Idle||W.Animation==Walk);if(W.Animation==Idle)IW+=W.TotalWeight;if(W.Animation==Walk)WW+=W.TotalWeight;}
        Valid&=FMath::IsNearlyEqual(IW,1-Fraction,.001)&&FMath::IsNearlyEqual(WW,Fraction,.001);Probe->SetBoolField(TEXT("correct_full_clip_weights"),Valid);Probe->SetArrayField(TEXT("weights"),Rows);Probes.Add(MakeShared<FJsonValueObject>(Probe));Good&=Valid;
    }
    O->SetArrayField(TEXT("raw_samples"),Raw);O->SetArrayField(TEXT("public_speed_probes"),Probes);O->SetBoolField(TEXT("built_public_sampler_qualified"),Good);O->SetBoolField(TEXT("playback_contact_or_body_fit_qualified"),false);if(!Write(Root,TEXT("SAMPLER.json"),O)){Why=TEXT("sampler_artifact_write_failed");return false;}if(!Good)Why=TEXT("actual_built_0_55_110_public_weights_or_rate1_shape_refused");return Good;
}
bool SaveOwned(UObject* Asset)
{
    FString File=FPackageName::LongPackageNameToFilename(Asset->GetOutermost()->GetName(),FPackageName::GetAssetPackageExtension());if(!FPaths::IsUnderDirectory(FPaths::ConvertRelativePathToFull(File),FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()))||IFileManager::Get().FileExists(*File))return false;IFileManager::Get().MakeDirectory(*FPaths::GetPath(File),true);Asset->MarkPackageDirty();FSavePackageArgs Args;Args.TopLevelFlags=RF_Public|RF_Standalone;Args.bSlowTask=false;return UPackage::SavePackage(Asset->GetOutermost(),Asset,*File,Args);
}
FString Run(bool Build)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("REFUSED_CAFE_WORKER110_PREPARATION"));FString Root,Why;
    auto Fail=[&](const TCHAR* Stage){O->SetStringField(TEXT("stage"),Stage);O->SetStringField(TEXT("reason"),Why);O->SetBoolField(TEXT("runtime_or_physical_enablement"),false);if(!Root.IsEmpty()&&IFileManager::Get().DirectoryExists(*Root))Write(Root,TEXT("REPORT.json"),O);return Json(O);};
    if(!ArtifactContext(Build,Root,Why))return Fail(TEXT("owned_context"));O->SetStringField(TEXT("artifact_root"),Root);
    if(!GuardOriginalFiles(O,TEXT("original_files_before"),Why))return Fail(TEXT("source_file_guard_before"));
    if(Build&&(!Fresh(MeshPackage)||!Fresh(MotionPackage))){Why=TEXT("both_fixed_110_asset_destinations_must_be_fresh");return Fail(TEXT("fresh_assets"));}
    UMaterial* Material=ColdMaterial(Root,O,Why);if(!Material)return Fail(TEXT("cold_M035_before_mesh"));
    auto Source=LoadObject<USkeletalMesh>(nullptr,SourceMeshPath);auto Idle=LoadObject<UAnimSequence>(nullptr,IdlePath);auto Walk=LoadObject<UAnimSequence>(nullptr,WalkPath);
    if(!Source||!Clips(Idle,Walk,Source->GetSkeleton())||!SamePalm(Source,Source)){Why=TEXT("qualified_source61_full_clips_and_existing_mesh_owned_palm_required");return Fail(TEXT("source_family"));}
    TSharedPtr<FJsonObject> Before,After,SourceAfter;if(!ObserveMesh(Source,Root,TEXT("SourceBefore"),Before,Why))return Fail(TEXT("source_snapshot"));O->SetObjectField(TEXT("source_before"),Before);
    USkeletalMesh* Candidate=nullptr;UBlendSpace1D* Motion=nullptr;
    if(Build)
    {
        Candidate=DuplicateObject<USkeletalMesh>(Source,CreatePackage(MeshPackage),TEXT("SK_CafeWorkerBen110_v001"));if(!Candidate){Why=TEXT("fresh_mesh_duplicate_failed");return Fail(TEXT("duplicate_mesh"));}Candidate->ClearFlags(RF_Transient);Candidate->SetFlags(RF_Public|RF_Standalone);auto Slots=Candidate->GetMaterials();Slots[0].MaterialInterface=Material;Candidate->SetMaterials(Slots);Candidate->PostEditChange();Finish(Candidate);
        Motion=NewObject<UBlendSpace1D>(CreatePackage(MotionPackage),TEXT("BS_CafeWorkerIdleWalk110_v001"),RF_Public|RF_Standalone);if(!Motion){Why=TEXT("fresh_BlendSpace1D_creation_failed");return Fail(TEXT("create_motion"));}Motion->SetSkeleton(Source->GetSkeleton());
        // Same fixed typed EditAnywhere-property authoring used by the qualified legacy builder;
        // no private engine function, memory offset, const_cast or fabricated runtime cache.
        auto Property=FindFProperty<FStructProperty>(UBlendSpace::StaticClass(),TEXT("BlendParameters"));if(!Property||Property->ArrayDim!=3||Property->Struct!=FBlendParameter::StaticStruct()||!Property->HasAnyPropertyFlags(CPF_Edit)){Why=TEXT("typed_editable_three_axis_FBlendParameter_property_required");return Fail(TEXT("axis_property"));}
        auto Axis=Property->ContainerPtrToValuePtr<FBlendParameter>(Motion,0);Axis->DisplayName=TEXT("Speed cm/s");Axis->Min=0;Axis->Max=110;Axis->GridNum=4;Axis->bSnapToGrid=false;Axis->bWrapInput=false;Motion->bScaleAnimation=false;Motion->TargetWeightInterpolationSpeedPerSec=0;Motion->InterpolationParam[0].InterpolationTime=0;
        if(Motion->AddSample(Idle,FVector::ZeroVector)==INDEX_NONE||Motion->AddSample(Walk,FVector(110,0,0))==INDEX_NONE){Why=TEXT("two_full_source_samples_not_accepted");return Fail(TEXT("add_samples"));}Motion->ValidateSampleData();Motion->ResampleData();
    }
    else
    {
        Candidate=LoadObject<USkeletalMesh>(nullptr,*(FString(MeshPackage)+TEXT(".SK_CafeWorkerBen110_v001")));Motion=LoadObject<UBlendSpace1D>(nullptr,*(FString(MotionPackage)+TEXT(".BS_CafeWorkerIdleWalk110_v001")));
    }
    if(!Candidate||Candidate->GetClass()!=USkeletalMesh::StaticClass()||Candidate->GetPathName()!=FString(MeshPackage)+TEXT(".SK_CafeWorkerBen110_v001")){Why=TEXT("exact_owned110_mesh_class_and_path_required");return Fail(TEXT("candidate_identity"));}
    if(!ObserveMesh(Candidate,Root,TEXT("Candidate"),After,Why))return Fail(TEXT("candidate_snapshot"));O->SetObjectField(TEXT("candidate"),After);
    if(!SameMeshData(Before,After)||Candidate->GetSkeleton()!=Source->GetSkeleton()||!SamePalm(Source,Candidate)||!SameSlotMetadata(Source->GetMaterials()[0],Candidate->GetMaterials()[0])||Candidate->GetMaterials()[0].MaterialInterface!=Material)
    {Why=TEXT("duplicate_geometry_UV_basis_skin_socket_or_slot_metadata_changed");return Fail(TEXT("preservation_compare"));}
    if(!Sampler(Motion,Idle,Walk,Root,O,Why))return Fail(TEXT("built_sampler"));
    if(!ObserveMesh(Source,Root,TEXT("SourceAfter"),SourceAfter,Why))return Fail(TEXT("source_after_snapshot"));O->SetObjectField(TEXT("source_after"),SourceAfter);
    if(!SameMeshData(Before,SourceAfter)||Before->GetStringField(TEXT("material"))!=SourceAfter->GetStringField(TEXT("material"))||Json(Before->GetObjectField(TEXT("palm")).ToSharedRef())!=Json(SourceAfter->GetObjectField(TEXT("palm")).ToSharedRef())||Json(Before->GetObjectField(TEXT("material_slot_metadata")).ToSharedRef())!=Json(SourceAfter->GetObjectField(TEXT("material_slot_metadata")).ToSharedRef()))
    {Why=TEXT("original_in_memory_mesh_geometry_basis_skin_material_palm_or_slot_metadata_changed");return Fail(TEXT("original_memory_preservation"));}
    if(!GuardOriginalFiles(O,TEXT("original_files_before_save"),Why))return Fail(TEXT("original_preservation_before_save"));
    if(!Build&&(Candidate->GetOutermost()->IsDirty()||Motion->GetOutermost()->IsDirty())){Why=TEXT("cold_derivative_packages_must_remain_clean");return Fail(TEXT("cold_package_cleanliness"));}
    O->SetBoolField(TEXT("new_mesh_saved"),false);O->SetBoolField(TEXT("new_motion_saved"),false);
    if(Build)
    {
        if(!SaveOwned(Candidate)){Why=TEXT("new_mesh_save_failed_partials_preserved");return Fail(TEXT("save_mesh"));}O->SetBoolField(TEXT("new_mesh_saved"),true);Write(Root,TEXT("REPORT.json"),O);
        if(!SaveOwned(Motion)){Why=TEXT("new_motion_save_failed_partial_mesh_preserved");return Fail(TEXT("save_motion"));}O->SetBoolField(TEXT("new_motion_saved"),true);
    }
    if(!GuardOriginalFiles(O,TEXT("original_files_final"),Why))return Fail(TEXT("original_preservation_final"));
    O->SetStringField(TEXT("status"),Build?TEXT("SAVED_TWO_CAFE_WORKER110_ASSETS_NATIVE_COLD_REOPEN_AND_HOST_GRAPH_BYTES_PENDING"):TEXT("READ_COLD_CAFE_WORKER110_SOURCE_MATCH_AND_BUILT_SAMPLER_HOST_GRAPH_BYTES_PENDING"));O->SetStringField(TEXT("mesh"),Candidate->GetPathName());O->SetStringField(TEXT("motion"),Motion->GetPathName());O->SetBoolField(TEXT("original_packages_saved"),false);O->SetBoolField(TEXT("runtime_or_body_fit_reach_contact_enabled"),false);Write(Root,TEXT("REPORT.json"),O);return Json(O);
}
}
FString ULivingTownCafeWorker110Preparation::BuildCafeWorker110Derivative(){return Run(true);}
FString ULivingTownCafeWorker110Preparation::ReadCafeWorker110Sampler(){return Run(false);}
