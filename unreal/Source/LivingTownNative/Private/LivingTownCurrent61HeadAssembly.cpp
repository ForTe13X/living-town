#include "LivingTownCurrent61HeadAssembly.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "Materials/Material.h"
#include "Rendering/SkeletalMeshRenderData.h"

namespace
{
bool AllowedShadingProfile(const FLivingTownCurrent61HeadPart& P)
{
    if(P.Role==ELivingTownHeadPartRole::HairCards)
        return P.ShadingModel==ELivingTownHeadShadingModel::Hair||P.ShadingModel==ELivingTownHeadShadingModel::DefaultLit;
    if(P.Role==ELivingTownHeadPartRole::Underlayer)
        return P.ShadingModel==ELivingTownHeadShadingModel::DefaultLit;
    return false;
}
bool HeadPath(const FString& P)
{
    return P.StartsWith(TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/"))&&P.Len()<=512&&
        !P.Contains(TEXT(".."))&&!P.Contains(TEXT("\\"))&&P.Contains(TEXT("."));
}
FName ParentName(const FReferenceSkeleton& Ref,int32 Index)
{
    const int32 Parent=Ref.GetParentIndex(Index);
    return Parent==INDEX_NONE?NAME_None:Ref.GetBoneName(Parent);
}
bool SharesHierarchy(const FReferenceSkeleton& Body,const FReferenceSkeleton& Part,const TArray<FName>& Source)
{
    if(Part.GetNum()<Source.Num()||Part.GetNum()>64)return false;
    for(FName Name:Source)if(Body.FindBoneIndex(Name)==INDEX_NONE||Part.FindBoneIndex(Name)==INDEX_NONE)return false;
    for(int32 I=0;I<Part.GetNum();++I)
    {
        const int32 Leader=Body.FindBoneIndex(Part.GetBoneName(I));
        if(Leader==INDEX_NONE||ParentName(Part,I)!=ParentName(Body,Leader))return false;
    }
    return true;
}
bool ActualLeaderMap(const USkeletalMeshComponent* Body,const USkeletalMeshComponent* Part)
{
    if(Part->LeaderPoseComponent.Get()!=Body||Part->GetRefPoseOverride().IsValid()||Part->IsSimulatingPhysics())return false;
    const auto& Leader=Body->GetSkeletalMeshAsset()->GetRefSkeleton();
    const auto& Follower=Part->GetSkeletalMeshAsset()->GetRefSkeleton();
    const auto& Map=Part->GetLeaderBoneMap();
    if(Map.Num()!=Follower.GetNum())return false;
    for(int32 I=0;I<Map.Num();++I)
        if((Map[I]<0||Map[I]>=Leader.GetNum())||Leader.GetBoneName(Map[I])!=Follower.GetBoneName(I))return false;
    return true;
}
}

bool FLivingTownCurrent61HeadBinding::IsValidated() const
{
    if(!bReadQualifiedDescriptor||QualificationSha256.Len()!=64||QualificationSha256==FString::ChrN(64,TCHAR('0'))||SourceJointNames.Num()!=61||Parts.Num()!=2)return false;
    for(TCHAR C:QualificationSha256)if(!((C>='0'&&C<='9')||(C>='a'&&C<='f')))return false;
    TSet<FName> Names;
    for(FName Name:SourceJointNames){if(Name.IsNone()||Names.Contains(Name))return false;Names.Add(Name);}
    if(!Names.Contains(FName(TEXT("root")))||!Names.Contains(FName(TEXT("neck_01")))||!Names.Contains(FName(TEXT("head"))))return false;
    bool Hair=false,Cap=false;
    TSet<FString> Meshes;
    for(const auto& P:Parts)
    {
        if(!AllowedShadingProfile(P)||!HeadPath(P.MeshPath)||!HeadPath(P.MaterialPath)||Meshes.Contains(P.MeshPath)||P.RenderTriangles<1||P.RenderTriangles>100000||P.UVChannels<1||P.UVChannels>8)return false;
        Meshes.Add(P.MeshPath);
        if(P.Role==ELivingTownHeadPartRole::HairCards){if(Hair)return false;Hair=true;}
        else if(P.Role==ELivingTownHeadPartRole::Underlayer){if(Cap)return false;Cap=true;}
        else return false;
    }
    return Hair&&Cap;
}

void LivingTownCurrent61HeadAssembly::Reset(USkeletalMeshComponent* Hair,USkeletalMeshComponent* Cap)
{
    // These setters change component/render/physics/leader state. A refused
    // off-thread call must not touch any component, including a valid follower.
    if(!IsInGameThread())return;
    for(auto* C:{Hair,Cap})if(C)
    {
        C->SetVisibility(false);C->SetLeaderPoseComponent(nullptr,true,false);
        C->EmptyOverrideMaterials();C->SetSkeletalMeshAsset(nullptr);
    }
}

bool LivingTownCurrent61HeadAssembly::Configure(USkeletalMeshComponent* Body,USkeletalMeshComponent* Hair,
    USkeletalMeshComponent* Cap,const FLivingTownCurrent61HeadBinding& Binding,FString& Error)
{
    Error.Reset();
    // Reject unsafe arguments before the cleanup transaction exists. In
    // particular, a follower alias must never let Reset clear the body.
    if(!IsInGameThread())
    {
        Error=TEXT("head_assembly_game_thread_required");return false;
    }
    if(!Body||!Hair||!Cap||Body==Hair||Body==Cap||Hair==Cap)
    {
        Error=TEXT("distinct_nonnull_body_and_head_followers_required");return false;
    }
    auto Fail=[&](const TCHAR* Why){Reset(Hair,Cap);Error=Why;return false;};
    if(!Binding.IsValidated()||
        !Body->GetSkeletalMeshAsset()||Body->GetRefPoseOverride().IsValid()||Body->IsSimulatingPhysics())
        return Fail(TEXT("explicit_current61_body_and_closed_head_descriptor_required"));
    USkeletalMesh* Leader=Body->GetSkeletalMeshAsset();
    TArray<USkeletalMesh*> Meshes;TArray<UMaterial*> Materials;
    for(const auto& Part:Binding.Parts)
    {
        UMaterial* M=LoadObject<UMaterial>(nullptr,*Part.MaterialPath);
        const EMaterialShadingModel Model=Part.ShadingModel==ELivingTownHeadShadingModel::Hair?MSM_Hair:MSM_DefaultLit;
        const bool TwoSided=Part.Role==ELivingTownHeadPartRole::HairCards;
        const float Cutoff=TwoSided?.3f:.5f;
        if(!M||M->GetClass()!=UMaterial::StaticClass()||!M->GetUsageByFlag(MATUSAGE_SkeletalMesh)||
            M->GetBlendMode()!=BLEND_Masked||M->IsTwoSided()!=TwoSided||M->GetOpacityMaskClipValue()!=Cutoff||
            M->GetShadingModels().GetShadingModelField()!=uint16(1u<<Model))
            return Fail(TEXT("saved_owned_skeletal_head_mask_material_required"));
        USkeletalMesh* Mesh=LoadObject<USkeletalMesh>(nullptr,*Part.MeshPath);
        const auto* Render=Mesh?Mesh->GetResourceForRendering():nullptr;
        if(!Mesh||Mesh->GetSkeleton()!=Leader->GetSkeleton()||Mesh->GetPhysicsAsset()!=nullptr||Mesh->GetMaterials().Num()!=1||
            !Render||Render->LODRenderData.Num()!=1||Render->LODRenderData[0].GetTotalFaces()!=uint32(Part.RenderTriangles)||
            Render->LODRenderData[0].GetNumTexCoords()!=uint32(Part.UVChannels)||
            !SharesHierarchy(Leader->GetRefSkeleton(),Mesh->GetRefSkeleton(),Binding.SourceJointNames))
            return Fail(TEXT("saved_head_mesh_ref_hierarchy_render_and_shared_skeleton_required"));
        const auto* Slot=Mesh->GetMaterials()[0].MaterialInterface.Get();
        if(Slot&&Slot!=M)return Fail(TEXT("unassigned_or_exact_saved_head_material_slot_required"));
        Meshes.Add(Mesh);Materials.Add(M);
    }
    for(int32 I=0;I<Binding.Parts.Num();++I)
    {
        USkeletalMeshComponent* C=Binding.Parts[I].Role==ELivingTownHeadPartRole::HairCards?Hair:Cap;
        C->AttachToComponent(Body,FAttachmentTransformRules::SnapToTargetNotIncludingScale);
        C->SetRelativeTransform(FTransform::Identity);C->SetCollisionEnabled(ECollisionEnabled::NoCollision);
        C->SetGenerateOverlapEvents(false);C->SetCanEverAffectNavigation(false);
        C->SetSkeletalMeshAsset(Meshes[I]);C->SetMaterial(0,Materials[I]);
        C->SetLeaderPoseComponent(Body,true,false); // sole body player; no follower pose evaluation
        if(!ActualLeaderMap(Body,C))return Fail(TEXT("complete_actual_name_resolved_leader_bone_map_required"));
    }
    Hair->SetVisibility(true);Cap->SetVisibility(true);
    return true;
}
