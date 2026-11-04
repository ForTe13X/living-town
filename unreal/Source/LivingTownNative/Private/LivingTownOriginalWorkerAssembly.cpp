#include "LivingTownOriginalWorkerAssembly.h"
#include "LivingTownCafeBinding.h"
#include "Animation/AnimSequence.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Animation/BlendSpace1D.h"
#include "ChaosClothAsset/ClothAsset.h"
#include "ChaosClothAsset/ClothComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/SkeletalMeshSocket.h"
#include "GameFramework/Actor.h"
#include "Materials/Material.h"
#include "PhysicsEngine/PhysicsAsset.h"
#include "PhysicsEngine/SkeletalBodySetup.h"
#include "Rendering/SkeletalMeshRenderData.h"
#include "Rendering/SkeletalMeshLODRenderData.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/FileHelper.h"
#include "HAL/FileManager.h"

namespace
{
bool Hash(const FString& S)
{
    if(S.Len()!=64||S==FString::ChrN(64,TCHAR('0')))return false;
    for(TCHAR C:S)if(!((C>='0'&&C<='9')||(C>='a'&&C<='f')))return false;
    return true;
}
bool Vector(const TSharedPtr<FJsonValue>& V,FVector& Out)
{
    if(!V||V->Type!=EJson::Array||V->AsArray().Num()!=3)return false;
    double N[3];for(int32 I=0;I<3;++I){const auto& X=V->AsArray()[I];if(!X||X->Type!=EJson::Number||!FMath::IsFinite(N[I]=X->AsNumber())||FMath::Abs(N[I])>10000.)return false;}
    Out=FVector(N[0],N[1],N[2]);return true;
}
bool Transform(const TSharedPtr<FJsonValue>& V,FTransform& Out)
{
    if(!V||V->Type!=EJson::Object)return false;const auto O=V->AsObject();
    if(!O||O->Values.Num()!=3)return false;FVector T,S;
    const auto Q=O->TryGetField(TEXT("rotation_xyzw"));
    if(!Vector(O->TryGetField(TEXT("translation_cm")),T)||!Vector(O->TryGetField(TEXT("scale")),S)||S.GetMin()<=0.00001||S.GetMax()>1000.||!Q||Q->Type!=EJson::Array||Q->AsArray().Num()!=4)return false;
    double A[4];for(int32 I=0;I<4;++I){const auto& X=Q->AsArray()[I];if(!X||X->Type!=EJson::Number||!FMath::IsFinite(A[I]=X->AsNumber()))return false;}
    const FQuat R(A[0],A[1],A[2],A[3]);if(!FMath::IsNearlyEqual(R.SizeSquared(),1.,1.e-6))return false;
    Out=FTransform(R,T,S);return Out.IsValid();
}
bool Number(const FJsonObject& O,const TCHAR* Key,double& Out,double Min,double Max)
{
    const auto V=O.TryGetField(Key);return V&&V->Type==EJson::Number&&FMath::IsFinite(Out=V->AsNumber())&&Out>=Min&&Out<=Max;
}
bool SameHierarchy(const FReferenceSkeleton& A,const FReferenceSkeleton& B)
{
    if(A.GetNum()!=62||B.GetNum()!=62)return false;
    for(int32 I=0;I<62;++I)
    {
        if(A.GetBoneName(I)!=B.GetBoneName(I)||A.GetParentIndex(I)!=B.GetParentIndex(I))return false;
        const auto& X=A.GetRefBonePose()[I];const auto& Y=B.GetRefBonePose()[I];
        // Independent FBX exports have measured sub-micrometre translation and
        // max3.2901764e-5 scale roundoff in actual001. Typed local tolerances.
        if((X.GetTranslation()-Y.GetTranslation()).GetAbsMax()>1.e-4||
           (X.GetScale3D()-Y.GetScale3D()).GetAbsMax()>4.e-5||
           1.-FMath::Abs(X.GetRotation()|Y.GetRotation())>1.e-10)return false;
    }
    return true;
}
bool Mesh(const USkeletalMesh* M,uint32 Vertices,uint32 Triangles)
{
    const auto* R=M?M->GetResourceForRendering():nullptr;
    return M&&M->GetSkeleton()&&R&&R->LODRenderData.Num()==1&&R->LODRenderData[0].GetNumVertices()==Vertices&&
        R->LODRenderData[0].GetTotalFaces()==Triangles&&R->LODRenderData[0].RenderSections.Num()==1&&M->GetMaterials().Num()==1;
}
bool LeaderMap(const USkinnedMeshComponent* Body,const USkinnedMeshComponent* Part)
{
    if(Part->LeaderPoseComponent.Get()!=Body)return false;const auto& M=Part->GetLeaderBoneMap();
    if(M.Num()!=62)return false;for(int32 I=0;I<62;++I)if(M[I]!=I)return false;return true;
}
bool MotionPolicy(UBlendSpace1D* BS,UAnimSequence* Idle,UAnimSequence* Walk)
{
    if(!BS||BS->GetClass()!=UBlendSpace1D::StaticClass()||!Idle||!Walk||Idle==Walk||BS->GetBlendSamples().Num()!=2||
       BS->IsValidAdditive()||BS->bScaleAnimation||BS->TargetWeightInterpolationSpeedPerSec!=0.f||BS->InterpolationParam[0].InterpolationTime!=0.f)return false;
    const auto& Axis=BS->GetBlendParameter(0);
    if(Axis.Min!=0.f||Axis.Max!=float(LivingTownOriginalWorker::WalkSpeedCmS)||Axis.bSnapToGrid||Axis.bWrapInput)return false;
    for(const auto& S:BS->GetBlendSamples())if(S.RateScale!=1.f||S.bUseSingleFrameForBlending||S.bMirror||
        !((S.Animation==Idle&&S.SampleValue==FVector::ZeroVector)||(S.Animation==Walk&&S.SampleValue==FVector(float(LivingTownOriginalWorker::WalkSpeedCmS),0,0))))return false;
    for(double F:{0.,.5,1.})
    {
        TArray<FBlendSampleData> W;int32 Segment=INDEX_NONE;double I=0.,K=0.;
        if(!BS->GetSamplesFromBlendInput(FVector(LivingTownOriginalWorker::WalkSpeedCmS*F,0,0),W,Segment,true)||W.IsEmpty()||W.Num()>2)return false;
        for(const auto& X:W){if(!FMath::IsFinite(X.TotalWeight)||X.TotalWeight<=0.f)return false;if(X.Animation==Idle)I+=X.TotalWeight;else if(X.Animation==Walk)K+=X.TotalWeight;else return false;}
        if(!FMath::IsNearlyEqual(I,1.-F,.001)||!FMath::IsNearlyEqual(K,F,.001))return false;
    }
    return true;
}
}

const TArray<FString>& LivingTownOriginalWorker::Materials()
{
    static const TArray<FString> P={TEXT("/Game/Worker110Prototype/Materials/M_VisibleOriginal_Body.M_VisibleOriginal_Body"),
        TEXT("/Game/Worker110Prototype/Materials/M_VisibleOriginal_Apron.M_VisibleOriginal_Apron"),
        TEXT("/Game/Worker110Prototype/Materials/M_VisibleOriginal_Underlay.M_VisibleOriginal_Underlay")};return P;
}
bool FLivingTownOriginalWorkerBinding::IsValidated() const
{
    if(!bReadPreparedDescriptor||!Hash(DescriptorSha256)||!Hash(SourceClosureSha256)||BoneNames.Num()!=62||Parents.Num()!=62||ReferenceLocal.Num()!=62||
       BoneNames[0]!=FName(LivingTownOriginalWorker::Wrapper)||Parents[0]!=INDEX_NONE||BoneNames[1]!=FName(TEXT("root"))||Parents[1]!=0||
       !MeshRelative.IsValid()||MeshRelative.GetRotation()!=FQuat::Identity||MeshRelative.GetScale3D()!=FVector::OneVector||
       !PalmLocal.IsValid()||PalmLocal.GetScale3D().GetMin()<=0.00001||PalmLocal.GetScale3D().GetMax()>1.||
       IdleOffsetCm.ContainsNaN()||WalkOffsetCm.ContainsNaN()||IdleOffsetCm.GetAbsMax()>100.||WalkOffsetCm.GetAbsMax()>100.||
       IdleOffsetCm.Z!=0.||WalkOffsetCm.Z!=0.||!FMath::IsFinite(CapsuleRadiusCm)||!FMath::IsFinite(CapsuleHalfHeightCm)||
       CapsuleRadiusCm<10.||CapsuleRadiusCm>40.||CapsuleHalfHeightCm<70.||CapsuleHalfHeightCm>110.)return false;
    TSet<FName> Names;for(int32 I=0;I<62;++I){if(BoneNames[I].IsNone()||Names.Contains(BoneNames[I])||!ReferenceLocal[I].IsValid()||
        (I>0&&(Parents[I]<0||Parents[I]>=I)))return false;Names.Add(BoneNames[I]);}
    return Names.Contains(FName(TEXT("hand_r")))&&Names.Contains(FName(TEXT("pelvis")))&&Names.Contains(FName(TEXT("foot_l")))&&Names.Contains(FName(TEXT("foot_r")));
}
bool FLivingTownOriginalWorkerBinding::Read(const FString& Path,FLivingTownOriginalWorkerBinding& Out,FString& Error)
{
    Error.Reset();auto Fail=[&](const TCHAR* E){Error=E;return false;};const int64 Size=IFileManager::Get().FileSize(*Path);
    TArray<uint8> Bytes;if(Size<=0||Size>128*1024||!FFileHelper::LoadFileToArray(Bytes,*Path))return Fail(TEXT("original_worker_descriptor_missing_or_oversize"));
    FString Text;FFileHelper::BufferToString(Text,Bytes.GetData(),Bytes.Num());TSharedPtr<FJsonObject> O;
    if(!LivingTownCafeJournal::HasUniqueObjectKeys(Text)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),O)||!O||O->Values.Num()!=13)return Fail(TEXT("original_worker_descriptor_schema_required"));
    FLivingTownOriginalWorkerBinding B;FString Format,Status;double Version=0.;
    if(!O->TryGetStringField(TEXT("format"),Format)||Format!=TEXT("LivingTown.OriginalWorkerBenPrepared")||!Number(*O,TEXT("version"),Version,1,1)||
       !O->TryGetStringField(TEXT("status"),Status)||Status!=TEXT("CONTROLLED_GAME_TRIAL_PREPARED")||
       !O->TryGetStringField(TEXT("source_closure_sha256"),B.SourceClosureSha256)||!LivingTownCafeJournal::Sha256(Bytes,B.DescriptorSha256)||
       !Transform(O->TryGetField(TEXT("mesh_relative")),B.MeshRelative)||!Transform(O->TryGetField(TEXT("palm_local")),B.PalmLocal)||
       !Vector(O->TryGetField(TEXT("idle_offset_cm")),B.IdleOffsetCm)||!Vector(O->TryGetField(TEXT("walk_offset_cm")),B.WalkOffsetCm)||
       !Number(*O,TEXT("capsule_radius_cm"),B.CapsuleRadiusCm,10,40)||!Number(*O,TEXT("capsule_half_height_cm"),B.CapsuleHalfHeightCm,70,110))return Fail(TEXT("original_worker_measured_trial_descriptor_required"));
    const TArray<TSharedPtr<FJsonValue>> *N=nullptr,*P=nullptr,*R=nullptr;
    if(!O->TryGetArrayField(TEXT("bone_names"),N)||!O->TryGetArrayField(TEXT("parents"),P)||!O->TryGetArrayField(TEXT("reference_local"),R)||N->Num()!=62||P->Num()!=62||R->Num()!=62)return Fail(TEXT("original_worker_exact62_reference_required"));
    for(int32 I=0;I<62;++I)
    {
        if((*N)[I]->Type!=EJson::String||(*N)[I]->AsString().Len()>128||(*P)[I]->Type!=EJson::Number)return Fail(TEXT("original_worker_reference_value_invalid"));
        const double Parent=(*P)[I]->AsNumber();FTransform T;if(!FMath::IsFinite(Parent)||Parent<-1||Parent>=I||Parent!=FMath::FloorToDouble(Parent)||!Transform((*R)[I],T))return Fail(TEXT("original_worker_reference_value_invalid"));
        B.BoneNames.Add(FName((*N)[I]->AsString()));B.Parents.Add(int32(Parent));B.ReferenceLocal.Add(T);
    }
    B.bReadPreparedDescriptor=true;if(!B.IsValidated())return Fail(TEXT("original_worker_prepared_calibration_invalid"));Out=MoveTemp(B);return true;
}
bool LivingTownOriginalWorker::ApplyCommandLineOptIn(FLivingTownCafeBinding& B,FString& Error)
{
    const TCHAR* Cursor=FCommandLine::Get();FString Token;int32 Count=0;
    while(FParse::Token(Cursor,Token,false))if(Token.Equals(TEXT("-LivingTownOriginalWorkerBen"),ESearchCase::IgnoreCase)||Token.StartsWith(TEXT("-LivingTownOriginalWorkerBen="),ESearchCase::IgnoreCase))++Count;
    if(!Count)return true;FString Path;
    if(Count!=1||!FParse::Value(FCommandLine::Get(),TEXT("LivingTownOriginalWorkerBen="),Path)||Path.IsEmpty()){Error=TEXT("one_original_worker_prepared_descriptor_path_required");return false;}
    FLivingTownOriginalWorkerBinding D;if(!FLivingTownOriginalWorkerBinding::Read(Path,D,Error))return false;
    return ApplyPreparedBinding(B,D,Error);
}
bool LivingTownOriginalWorker::ApplyPreparedBinding(FLivingTownCafeBinding& B,const FLivingTownOriginalWorkerBinding& D,FString& Error)
{
    Error.Reset();if(!D.IsValidated()||B.ResidentId!=TEXT("ben")||B.Current61Head.IsSet()||B.OriginalWorker.IsSet()){Error=TEXT("original_worker_exclusive_Ben_visual_and_prepared_descriptor_required");return false;}
    B.OriginalWorker=D;B.MotionStrategy=ELivingTownCafeMotionStrategy::OriginalWorkerSingleNode;
    B.VisualAssetPath=Body;B.IdleWalkBlendSpacePath=Motion;B.IdleAnimationPath=Idle;B.WalkAnimationPath=Walk;B.UseSocket=Palm;
    B.MeshRelativeTransform=D.MeshRelative;B.IdleRootDeltaCm=FVector::ZeroVector;B.CapsuleRadiusCm=float(D.CapsuleRadiusCm);B.CapsuleHalfHeightCm=float(D.CapsuleHalfHeightCm);B.WalkSpeedCmPerSecond=float(WalkSpeedCmS);
    // Existing paired-save envelopes already bind VisualSha256. Every prepared
    // descriptor therefore gets a distinct source identity without a new ledger.
    B.VisualSha256=D.DescriptorSha256;return true;
}

ULivingTownOriginalWorkerAssembly::ULivingTownOriginalWorkerAssembly(){PrimaryComponentTick.bCanEverTick=false;}
bool ULivingTownOriginalWorkerAssembly::Configure(USkeletalMeshComponent* Body,const FLivingTownOriginalWorkerBinding& B,FString& Error)
{
    Error.Reset();auto Fail=[&](const TCHAR* E){Error=E;return false;};
    if(!IsInGameThread())return Fail(TEXT("original_worker_game_thread_required"));
    if(bConfigured||Leader||!Body||!GetOwner()||Body->GetOwner()!=GetOwner()||Body->GetSkeletalMeshAsset()||Body->GetAnimInstance()||Body->GetAnimClass()||Body->GetNumOverrideMaterials()!=0||!Body->bEnableAnimation||!B.IsValidated())return Fail(TEXT("original_worker_empty_owned_body_and_prepared_binding_required"));
    TArray<UMaterial*> Materials;for(const auto& Path:LivingTownOriginalWorker::Materials())
    {
        auto* M=LoadObject<UMaterial>(nullptr,*Path);if(!M||M->GetClass()!=UMaterial::StaticClass()||!M->GetUsageByFlag(MATUSAGE_SkeletalMesh))return Fail(TEXT("original_worker_saved_skeletal_material_usage_required"));Materials.Add(M);
    }
    if(!Materials[1]->GetUsageByFlag(MATUSAGE_Clothing))return Fail(TEXT("original_worker_saved_clothing_material_usage_required"));
    auto* M=LoadObject<USkeletalMesh>(nullptr,LivingTownOriginalWorker::Body);auto* U=LoadObject<USkeletalMesh>(nullptr,LivingTownOriginalWorker::Underlay);
    auto* C=LoadObject<UChaosClothAsset>(nullptr,LivingTownOriginalWorker::Cloth);auto* P=LoadObject<UPhysicsAsset>(nullptr,LivingTownOriginalWorker::Collision);
    auto* I=LoadObject<UAnimSequence>(nullptr,LivingTownOriginalWorker::Idle);auto* W=LoadObject<UAnimSequence>(nullptr,LivingTownOriginalWorker::Walk);auto* BS=LoadObject<UBlendSpace1D>(nullptr,LivingTownOriginalWorker::Motion);
    const auto* CR=C?C->GetResourceForRendering():nullptr;
    if(!Mesh(M,51214,68085)||!Mesh(U,681,1206)||!C||!P||!CR||CR->LODRenderData.Num()!=1||CR->LODRenderData[0].GetNumVertices()!=1353||CR->LODRenderData[0].GetTotalFaces()!=2560||
       U->GetSkeleton()!=M->GetSkeleton()||C->GetSkeleton()!=M->GetSkeleton()||!SameHierarchy(M->GetRefSkeleton(),U->GetRefSkeleton())||!SameHierarchy(M->GetRefSkeleton(),C->GetRefSkeleton())||
       M->GetMaterials()[0].MaterialInterface!=Materials[0]||U->GetMaterials()[0].MaterialInterface!=Materials[2]||C->GetMaterials().Num()!=1||C->GetMaterials()[0].MaterialInterface!=Materials[1]||!MotionPolicy(BS,I,W))return Fail(TEXT("original_worker_saved_exact_body_support_cloth_motion_required"));
    const auto& Ref=M->GetRefSkeleton();if(Ref.GetNum()!=62)return Fail(TEXT("original_worker_exact62_reference_required"));
    for(int32 K=0;K<62;++K)if(Ref.GetBoneName(K)!=B.BoneNames[K]||Ref.GetParentIndex(K)!=B.Parents[K]||!Ref.GetRefBonePose()[K].Equals(B.ReferenceLocal[K],1.e-8))return Fail(TEXT("original_worker_descriptor_reference_changed"));
    for(auto* Clip:{I,W})if(Clip->GetSkeleton()!=M->GetSkeleton()||Clip->RateScale!=1.f||Clip->IsValidAdditive()||Clip->bEnableRootMotion||Clip->bForceRootLock||Clip->GetSamplingFrameRate()!=FFrameRate(30,1))return Fail(TEXT("original_worker_unchanged30hz_motion_policy_required"));
    if(I->GetNumberOfSampledKeys()!=461||W->GetNumberOfSampledKeys()!=71||BS->GetSkeleton()!=M->GetSkeleton())return Fail(TEXT("original_worker_complete_idle_walk_required"));
    const auto* Socket=M->FindSocket(FName(LivingTownOriginalWorker::Palm));if(!Socket||Socket->GetOuter()!=M||Socket->BoneName!=FName(TEXT("hand_r"))||!Socket->GetSocketLocalTransform().Equals(B.PalmLocal,1.e-8))return Fail(TEXT("original_worker_measured_mesh_owned_palm_required"));
    TSet<FName> Bodies;int32 Shapes=0;for(const auto& Ptr:P->SkeletalBodySetups)
    {
        const auto* S=Ptr.Get();if(!S||Bodies.Contains(S->BoneName)||Ref.FindBoneIndex(S->BoneName)==INDEX_NONE||S->AggGeom.SphereElems.Num()||S->AggGeom.BoxElems.Num()||S->AggGeom.ConvexElems.Num())return Fail(TEXT("original_worker_six_measured_sphyls_required"));
        const int32 Count=S->BoneName==FName(TEXT("pelvis"))?2:1;if(S->AggGeom.SphylElems.Num()!=Count)return Fail(TEXT("original_worker_six_measured_sphyls_required"));
        Bodies.Add(S->BoneName);Shapes+=Count;
    }
    if(Bodies.Num()!=5||Shapes!=6||!Bodies.Contains(FName(TEXT("pelvis")))||!Bodies.Contains(FName(TEXT("thigh_l")))||!Bodies.Contains(FName(TEXT("thigh_r")))||!Bodies.Contains(FName(TEXT("calf_l")))||!Bodies.Contains(FName(TEXT("calf_r"))))return Fail(TEXT("original_worker_six_measured_sphyls_required"));
    Leader=Body;OwnedBody=M;Motion=BS;PreviousRelative=Body->GetRelativeTransform();PreviousVisible=Body->IsVisible();PreviousAnimationMode=uint8(Body->GetAnimationMode());PreviousBonePolicy=uint8(Body->VisibilityBasedAnimTickOption);PreviousUpdateRateOptimization=Body->bEnableUpdateRateOptimizations;PreviousCollisionMode=uint8(Body->GetCollisionEnabled());
    auto Rollback=[&](const TCHAR* E){Reset();return Fail(E);};
    Body->SetVisibility(false);Body->SetSkeletalMeshAsset(M);Body->SetRelativeTransform(B.MeshRelative);Body->SetAnimationMode(EAnimationMode::AnimationSingleNode);
    auto* Player=Body->GetSingleNodeInstance();if(!Player||Player->GetClass()!=UAnimSingleNodeInstance::StaticClass())return Rollback(TEXT("original_worker_plain_single_node_required"));
    Player->SetAnimationAsset(BS,true,1.f);Player->SetPlaying(true); // possession owns the active player's bone/URO policy
    Support=NewObject<USkeletalMeshComponent>(GetOwner(),TEXT("OriginalWorkerInnerSupport"));Apron=NewObject<UChaosClothComponent>(GetOwner(),TEXT("OriginalWorkerChaosApron"));
    if(!Support||!Apron)return Rollback(TEXT("original_worker_owned_followers_required"));
    for(USkinnedMeshComponent* Part:{static_cast<USkinnedMeshComponent*>(Support.Get()),static_cast<USkinnedMeshComponent*>(Apron.Get())})
    {
        GetOwner()->AddInstanceComponent(Part);Part->SetupAttachment(Body);Part->SetRelativeTransform(FTransform::Identity);Part->SetVisibility(false);Part->SetCollisionEnabled(ECollisionEnabled::NoCollision);Part->SetGenerateOverlapEvents(false);Part->SetCanEverAffectNavigation(false);
    }
    Support->SetSkeletalMeshAsset(U);Support->RegisterComponent();Support->SetLeaderPoseComponent(Body,true,false);
    Apron->SetAsset(C);Apron->SetEnableSimulation(false);Apron->RegisterComponent();Apron->SetLeaderPoseComponent(Body,true,false);Apron->AddCollisionSource(Body,P,true);
    if(!LeaderMap(Body,Support)||!LeaderMap(Body,Apron)||Player->GetCurrentAsset()!=BS)return Rollback(TEXT("original_worker_actual62_leader_maps_and_player_required"));
    if(Body->GetMaterial(0)!=Materials[0]||Support->GetMaterial(0)!=Materials[2]||Apron->GetMaterial(0)!=Materials[1])return Rollback(TEXT("original_worker_actual_three_component_material_bindings_required"));
    Body->SetCollisionEnabled(ECollisionEnabled::NoCollision);Support->SetVisibility(true);Apron->SetVisibility(true);Apron->ForceNextUpdateTeleportAndReset();Apron->SetEnableSimulation(true);Body->SetVisibility(true);bConfigured=true;return true;
}
void ULivingTownOriginalWorkerAssembly::ResetAfterTeleport(){if(IsInGameThread()&&bConfigured&&Apron)Apron->ForceNextUpdateTeleportAndReset();}
void ULivingTownOriginalWorkerAssembly::Reset()
{
    if(!IsInGameThread())return;
    if(Apron){Apron->SetEnableSimulation(false);Apron->ResetCollisionSources();Apron->SetLeaderPoseComponent(nullptr,true,false);Apron->SetVisibility(false);Apron->SetAsset(nullptr);Apron->DestroyComponent();Apron=nullptr;}
    if(Support){Support->SetLeaderPoseComponent(nullptr,true,false);Support->SetVisibility(false);Support->SetSkeletalMeshAsset(nullptr);Support->DestroyComponent();Support=nullptr;}
    if(Leader&&Leader->GetSkeletalMeshAsset()==OwnedBody)
    {
        Leader->SetVisibility(false);Leader->SetSkeletalMeshAsset(nullptr);Leader->SetAnimationMode(EAnimationMode::Type(PreviousAnimationMode));Leader->SetRelativeTransform(PreviousRelative);Leader->VisibilityBasedAnimTickOption=EVisibilityBasedAnimTickOption(PreviousBonePolicy);Leader->bEnableUpdateRateOptimizations=PreviousUpdateRateOptimization;Leader->SetCollisionEnabled(ECollisionEnabled::Type(PreviousCollisionMode));Leader->SetVisibility(PreviousVisible);
    }
    Leader=nullptr;OwnedBody=nullptr;Motion=nullptr;bConfigured=false;
}
void ULivingTownOriginalWorkerAssembly::EndPlay(const EEndPlayReason::Type Reason){Reset();Super::EndPlay(Reason);}
