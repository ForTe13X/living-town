#include "LivingTownAvatarPreparation.h"
#include "LivingTownCafeMotionPreparation.h"
#include "Animation/AnimSequence.h"
#include "Animation/Skeleton.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Animation/BlendSpace1D.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/SkeletalMeshSocket.h"
#include "Engine/World.h"
#include "GameFramework/Actor.h"
#include "Materials/MaterialInterface.h"
#include "Materials/Material.h"
#include "Rendering/SkeletalMeshRenderData.h"
#include "Rendering/SkeletalMeshLODRenderData.h"
#include "SkinnedAssetCompiler.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/MemoryWriter.h"
#include "Misc/SecureHash.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "HAL/FileManager.h"
#include "UObject/Package.h"
#include "UObject/SavePackage.h"
#include "UObject/UnrealType.h"
#include "UObject/UObjectGlobals.h"

namespace
{
const TCHAR* SourceMeshPath=TEXT("/Game/LivingTown_UEPilot/CafeWorkerMultiviewV002_WalkTrial_v001/tripo_node_183abe00-c177-48f4-b834-6c25e.tripo_node_183abe00-c177-48f4-b834-6c25e");
const TCHAR* IdlePath=TEXT("/Game/LivingTown_UEPilot/CafeWorkerMultiviewV002_IdleOnlyTrial_v002/idle.idle");
const TCHAR* WalkPath=TEXT("/Game/LivingTown_UEPilot/CafeWorkerMultiviewV002_WalkTrial_v001/walk.walk");
const TCHAR* MaterialPath=TEXT("/Game/LivingTown_UEPilot/CafeWorkerNeckConfidence_v001/M_FaceNeck_Confidence_v001.M_FaceNeck_Confidence_v001");
const TCHAR* OwnedMaterialPath=TEXT("/Game/LivingTown_UEPilot/CafeWorkerBen_v001/M_CafeWorkerBen_Skeletal_v001.M_CafeWorkerBen_Skeletal_v001");
const TCHAR* MeshPackage=TEXT("/Game/LivingTown_UEPilot/CafeWorkerBen_v001/SK_CafeWorkerBen_v001");
const TCHAR* MotionPackage=TEXT("/Game/LivingTown_UEPilot/CafeWorkerBen_v001/BS_CafeWorkerIdleWalk_v001");
const FName PalmName(TEXT("UsePalm_R"));
FString Json(const TSharedRef<FJsonObject>& O){FString S;auto W=TJsonWriterFactory<>::Create(&S);FJsonSerializer::Serialize(O,W);return S;}
TArray<TSharedPtr<FJsonValue>> V(const FVector& P){return {MakeShared<FJsonValueNumber>(P.X),MakeShared<FJsonValueNumber>(P.Y),MakeShared<FJsonValueNumber>(P.Z)};}
TSharedRef<FJsonObject> Transform(const FTransform& T)
{
    auto O=MakeShared<FJsonObject>();O->SetArrayField(TEXT("translation"),V(T.GetTranslation()));O->SetArrayField(TEXT("scale"),V(T.GetScale3D()));const auto Q=T.GetRotation();
    O->SetArrayField(TEXT("rotation_xyzw"),{MakeShared<FJsonValueNumber>(Q.X),MakeShared<FJsonValueNumber>(Q.Y),MakeShared<FJsonValueNumber>(Q.Z),MakeShared<FJsonValueNumber>(Q.W)});return O;
}
void Finish(USkeletalMesh* Mesh){USkinnedAsset* Assets[]={Mesh};FSkinnedAssetCompilingManager::Get().FinishCompilation(MakeArrayView(Assets));}
bool AllowedContext(){return IsInGameThread()&&GIsEditor&&!IsRunningCommandlet();}
bool Shape(USkeletalMesh* Mesh)
{
    if(!Mesh||!Mesh->GetSkeleton()||Mesh->GetRefSkeleton().GetNum()!=61||Mesh->GetMaterials().Num()!=1||Mesh->GetOutermost()->HasAnyPackageFlags(PKG_PlayInEditor))return false;
    Finish(Mesh);const auto* R=Mesh->GetResourceForRendering();return R&&R->LODRenderData.Num()==1&&R->LODRenderData[0].GetNumVertices()==10707&&R->LODRenderData[0].RenderSections.Num()==1;
}
TSharedRef<FJsonObject> Snapshot(USkeletalMesh* Mesh)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("REFUSED_NEW61_MESH_SHAPE"));if(!Shape(Mesh))return O;
    const auto& L=Mesh->GetResourceForRendering()->LODRenderData[0];const auto& B=L.StaticVertexBuffers;const auto& Skin=L.SkinWeightVertexBuffer;const auto* Indices=L.MultiSizeIndexContainer.GetIndexBuffer();if(!Indices)return O;
    TArray<uint8> Bytes;FMemoryWriter W(Bytes);int32 Num=Mesh->GetRefSkeleton().GetNum();W<<Num;
    TArray<TSharedPtr<FJsonValue>> Bones,Weights;
    for(int32 I=0;I<Num;++I)
    {
        const auto& Ref=Mesh->GetRefSkeleton();FString Name=Ref.GetBoneName(I).ToString();int32 Parent=Ref.GetParentIndex(I);FTransform Pose=Ref.GetRefBonePose()[I];W<<Name;W<<Parent;W<<Pose;
        auto Row=Transform(Pose);Row->SetStringField(TEXT("name"),Name);Row->SetNumberField(TEXT("parent"),Parent);Bones.Add(MakeShared<FJsonValueObject>(Row));
    }
    uint32 N=L.GetNumVertices(),UVs=B.StaticMeshVertexBuffer.GetNumTexCoords(),Influences=Skin.GetMaxBoneInfluences();W<<N;W<<UVs;W<<Influences;
    for(uint32 I=0;I<N;++I)
    {
        auto P=B.PositionVertexBuffer.VertexPosition(I);auto X=B.StaticMeshVertexBuffer.VertexTangentX(I);auto Z=B.StaticMeshVertexBuffer.VertexTangentZ(I);W<<P;W<<X;W<<Z;
        for(uint32 U=0;U<UVs;++U){auto UV=B.StaticMeshVertexBuffer.GetVertexUV(I,U);W<<UV;}
        if(B.ColorVertexBuffer.GetNumVertices()){auto C=B.ColorVertexBuffer.VertexColor(I);W<<C;}
        TArray<TSharedPtr<FJsonValue>> VertexWeights;
        const FSkelMeshRenderSection* Section=nullptr;for(const auto& S:L.RenderSections)if(I>=S.BaseVertexIndex&&I<S.BaseVertexIndex+S.NumVertices){Section=&S;break;}
        if(!Section){O->SetStringField(TEXT("status"),TEXT("REFUSED_VERTEX_SECTION"));return O;}
        for(uint32 J=0;J<Influences;++J)
        {
            uint32 Local=Skin.GetBoneIndex(I,J);uint16 Weight=Skin.GetBoneWeight(I,J);W<<Local;W<<Weight;
            if(Weight){if(!Section->BoneMap.IsValidIndex(Local)){O->SetStringField(TEXT("status"),TEXT("REFUSED_BONE_MAP"));return O;}VertexWeights.Add(MakeShared<FJsonValueArray>(TArray<TSharedPtr<FJsonValue>>{MakeShared<FJsonValueNumber>(Section->BoneMap[Local]),MakeShared<FJsonValueNumber>(Weight)}));}
        }
        Weights.Add(MakeShared<FJsonValueArray>(VertexWeights));
    }
    uint32 IndexCount=Indices->Num();W<<IndexCount;for(uint32 I=0;I<IndexCount;++I){uint32 Index=Indices->Get(I);W<<Index;}
    for(const auto& S:L.RenderSections){uint16 M=S.MaterialIndex;uint32 Start=S.BaseIndex,Count=S.NumTriangles,Vertex=S.BaseVertexIndex;W<<M;W<<Start;W<<Count;W<<Vertex;for(auto Bone:S.BoneMap){W<<Bone;}}
    W.Close();uint8 Digest[20];FSHA1::HashBuffer(Bytes.GetData(),Bytes.Num(),Digest);
    O->SetStringField(TEXT("status"),TEXT("READ_NEW61_REFERENCE_RENDER_SKIN_GEOMETRY"));O->SetStringField(TEXT("mesh"),Mesh->GetPathName());O->SetStringField(TEXT("skeleton"),Mesh->GetSkeleton()->GetPathName());
    O->SetStringField(TEXT("geometry_reference_skin_SHA1"),BytesToHex(Digest,20).ToLower());O->SetNumberField(TEXT("vertices"),N);O->SetNumberField(TEXT("triangles"),IndexCount/3);O->SetNumberField(TEXT("UV_channels"),UVs);O->SetArrayField(TEXT("reference_bones"),Bones);O->SetArrayField(TEXT("native_vertex_global_bone_weights_uint16"),Weights);
    O->SetArrayField(TEXT("materials"),{MakeShared<FJsonValueString>(Mesh->GetMaterials()[0].MaterialInterface?Mesh->GetMaterials()[0].MaterialInterface->GetPathName():TEXT("missing"))});O->SetBoolField(TEXT("package_dirty"),Mesh->GetOutermost()->IsDirty());O->SetBoolField(TEXT("skeleton_package_dirty"),Mesh->GetSkeleton()->GetOutermost()->IsDirty());
    const auto Bounds=Mesh->GetBounds();O->SetArrayField(TEXT("reference_bounds_origin_cm"),V(Bounds.Origin));O->SetArrayField(TEXT("reference_bounds_extent_cm"),V(Bounds.BoxExtent));
    if(const auto* Socket=Mesh->FindSocket(PalmName)){auto S=Transform(Socket->GetSocketLocalTransform());S->SetStringField(TEXT("bone"),Socket->BoneName.ToString());S->SetStringField(TEXT("name"),Socket->SocketName.ToString());S->SetBoolField(TEXT("mesh_owned"),Socket->GetOuter()==Mesh);O->SetObjectField(TEXT("use_socket"),S);}
    return O;
}
bool Fresh(const TCHAR* Package)
{
    FString Filename=FPaths::ConvertRelativePathToFull(FPackageName::LongPackageNameToFilename(Package,FPackageName::GetAssetPackageExtension()));return FPaths::IsUnderDirectory(Filename,FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()))&&!FindPackage(nullptr,Package)&&!IFileManager::Get().FileExists(*Filename);
}
bool Save(UObject* Asset)
{
    FString File=FPackageName::LongPackageNameToFilename(Asset->GetOutermost()->GetName(),FPackageName::GetAssetPackageExtension());IFileManager::Get().MakeDirectory(*FPaths::GetPath(File),true);Asset->MarkPackageDirty();FSavePackageArgs Args;Args.TopLevelFlags=RF_Public|RF_Standalone;Args.bSlowTask=false;return UPackage::SavePackage(Asset->GetOutermost(),Asset,*File,Args);
}
}

FString ULivingTownAvatarPreparation::AuthorCafeWorkerAvatar(USkeletalMesh* SourceMesh,UAnimSequence* Idle,UAnimSequence* Walk,UMaterialInterface* ReviewedMaterial,FVector PalmLocalCm)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("REFUSED_SOURCE_OR_FRESH_OWNED_DESTINATION"));
    if(!AllowedContext()||!Shape(SourceMesh)||SourceMesh->GetPathName()!=SourceMeshPath||!Idle||Idle->GetPathName()!=IdlePath||!Walk||Walk->GetPathName()!=WalkPath||!ReviewedMaterial||(ReviewedMaterial->GetPathName()!=MaterialPath&&ReviewedMaterial->GetPathName()!=OwnedMaterialPath)||!ReviewedMaterial->GetMaterial()||!ReviewedMaterial->GetMaterial()->GetUsageByFlag(MATUSAGE_SkeletalMesh)||Idle->GetSkeleton()!=SourceMesh->GetSkeleton()||Walk->GetSkeleton()!=SourceMesh->GetSkeleton()||Idle->GetPlayLength()<=0||Walk->GetPlayLength()<=0||PalmLocalCm.ContainsNaN()||PalmLocalCm.Size()>20||!Fresh(MeshPackage)||!Fresh(MotionPackage)||SourceMesh->FindSocket(PalmName))return Json(O);
    const auto Before=Snapshot(SourceMesh);O->SetObjectField(TEXT("source_before"),Before);
    auto* Candidate=DuplicateObject<USkeletalMesh>(SourceMesh,CreatePackage(MeshPackage),TEXT("SK_CafeWorkerBen_v001"));if(!Candidate)return Json(O);Candidate->ClearFlags(RF_Transient);Candidate->SetFlags(RF_Public|RF_Standalone);
    auto Slots=Candidate->GetMaterials();Slots[0].MaterialInterface=ReviewedMaterial;Candidate->SetMaterials(Slots);
    auto* Socket=NewObject<USkeletalMeshSocket>(Candidate);Socket->SocketName=PalmName;Socket->BoneName=TEXT("hand_r");Socket->RelativeLocation=PalmLocalCm;Socket->bForceAlwaysAnimated=true;Candidate->AddSocket(Socket,false);
    Candidate->PostEditChange();Finish(Candidate);auto After=Snapshot(Candidate);O->SetObjectField(TEXT("candidate"),After);
    if(After->GetStringField(TEXT("status"))!=TEXT("READ_NEW61_REFERENCE_RENDER_SKIN_GEOMETRY")||After->GetStringField(TEXT("geometry_reference_skin_SHA1"))!=Before->GetStringField(TEXT("geometry_reference_skin_SHA1"))){O->SetStringField(TEXT("status"),TEXT("REFUSED_DUPLICATE_GEOMETRY_CHANGE_NOT_SAVED"));return Json(O);}
    auto* Motion=NewObject<UBlendSpace1D>(CreatePackage(MotionPackage),TEXT("BS_CafeWorkerIdleWalk_v001"),RF_Public|RF_Standalone);Motion->SetSkeleton(SourceMesh->GetSkeleton());
    auto* Property=FindFProperty<FStructProperty>(UBlendSpace::StaticClass(),TEXT("BlendParameters"));if(!Property||Property->ArrayDim!=3||Property->Struct!=FBlendParameter::StaticStruct()){O->SetStringField(TEXT("status"),TEXT("REFUSED_EXACT_BLEND_PARAMETER_PROPERTY"));return Json(O);}
    auto* Axis=Property->ContainerPtrToValuePtr<FBlendParameter>(Motion,0);Axis->DisplayName=TEXT("Speed cm/s");Axis->Min=0;Axis->Max=180;Axis->GridNum=4;Axis->bSnapToGrid=false;Axis->bWrapInput=false;
    Motion->AddSample(Idle,FVector::ZeroVector);Motion->AddSample(Walk,FVector(180,0,0));Motion->ValidateSampleData();Motion->ResampleData();
    const FString Read=ULivingTownCafeMotionPreparation::ReadCafeMotionInterpolation(Motion);O->SetStringField(TEXT("motion_public_sampler_json"),Read);TSharedPtr<FJsonObject> Check;auto Reader=TJsonReaderFactory<>::Create(Read);if(!FJsonSerializer::Deserialize(Reader,Check)||!Check||!Check->GetBoolField(TEXT("runtime_interpolation_qualified"))){O->SetStringField(TEXT("status"),TEXT("REFUSED_BUILT_RUNTIME_SAMPLER_NOT_SAVED"));return Json(O);}
    if(!Save(Candidate)||!Save(Motion)){O->SetStringField(TEXT("status"),TEXT("FAIL_NEW_ASSET_SAVE_PARTIALS_PRESERVED"));return Json(O);}
    O->SetStringField(TEXT("mesh"),Candidate->GetPathName());O->SetStringField(TEXT("motion"),Motion->GetPathName());O->SetObjectField(TEXT("source_after"),Snapshot(SourceMesh));O->SetStringField(TEXT("status"),TEXT("SAVED_NEW61_AVATAR_AND_BUILT_IDLE_WALK_COLD_REOPEN_PENDING"));O->SetBoolField(TEXT("original_assets_saved"),false);O->SetBoolField(TEXT("runtime_adoption_or_contact_qualified"),false);return Json(O);
}

FString ULivingTownAvatarPreparation::ReadAvatarSnapshot(USkeletalMesh* Mesh,UBlendSpace* Motion)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("REFUSED_EDITOR_CONTEXT"));if(!AllowedContext())return Json(O);O=Snapshot(Mesh);if(Motion)O->SetStringField(TEXT("motion_public_sampler_json"),ULivingTownCafeMotionPreparation::ReadCafeMotionInterpolation(Motion));return Json(O);
}

FString ULivingTownAvatarPreparation::ReadAvatarPose(USkeletalMeshComponent* Component)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("REFUSED_OWNED_TEMPORARY_COMPONENT"));
    if(!AllowedContext()||!Component||!Component->GetWorld()||!Component->GetWorld()->IsEditorWorld()||!Component->IsRegistered()||!Component->GetOwner()||!Component->GetOwner()->HasAnyFlags(RF_Transient)||!Shape(Component->GetSkeletalMeshAsset())||!Component->GetSingleNodeInstance())return Json(O);
    Component->TickAnimation(0,false);Component->RefreshBoneTransforms();const auto& L=Component->GetSkeletalMeshAsset()->GetResourceForRendering()->LODRenderData[0];auto* Skin=Component->GetSkinWeightBuffer(0);if(!Skin)return Json(O);
    TArray<FMatrix44f> Matrices;Component->GetCurrentRefToLocalMatrices(Matrices,0);TArray<FVector3f> Positions;USkinnedMeshComponent::ComputeSkinnedPositions(Component,Positions,Matrices,L,*Skin);if(Positions.Num()!=10707)return Json(O);
    TArray<TSharedPtr<FJsonValue>> Values,Bones;for(const auto& P:Positions){if(P.ContainsNaN())return Json(O);Values.Add(MakeShared<FJsonValueArray>(V(FVector(P))));}
    for(int32 I=0;I<Component->GetNumBones();++I){auto Row=Transform(Component->GetSocketTransform(Component->GetBoneName(I),RTS_Component));Row->SetStringField(TEXT("name"),Component->GetBoneName(I).ToString());Bones.Add(MakeShared<FJsonValueObject>(Row));}
    O->SetStringField(TEXT("status"),TEXT("READ_ACTUAL_CPU_SKINNED_POSE_EXPLICIT_EVALUATION"));O->SetStringField(TEXT("mesh"),Component->GetSkeletalMeshAsset()->GetPathName());O->SetStringField(TEXT("animation"),Component->GetSingleNodeInstance()->GetCurrentAsset()->GetPathName());O->SetNumberField(TEXT("time_seconds"),Component->GetPosition());O->SetArrayField(TEXT("component_space_positions_cm"),Values);O->SetArrayField(TEXT("bones_component"),Bones);O->SetObjectField(TEXT("component_to_world"),Transform(Component->GetComponentTransform()));O->SetObjectField(TEXT("palm_component"),Transform(Component->GetSocketTransform(PalmName,RTS_Component)));O->SetBoolField(TEXT("TickAnimation_zero_and_RefreshBoneTransforms_called"),true);O->SetBoolField(TEXT("natural_runtime_motion_claimed"),false);return Json(O);
}
