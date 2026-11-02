#include "LivingTownCafeCharacter.h"
#include "LivingTownRootCorrectedSingleNodeInstance.h"
#include "Engine/SkeletalMeshSocket.h"
#include "ReferenceSkeleton.h"
#include "Materials/Material.h"
#include "Rendering/SkeletalMeshRenderData.h"
#include "Rendering/SkeletalMeshLODRenderData.h"
#include "Components/CapsuleComponent.h"
#include "Components/InputComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Camera/CameraComponent.h"
#include "GameFramework/SpringArmComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/Controller.h"
#include "Animation/BlendSpace.h"
#include "Animation/BlendSpace1D.h"
#include "Animation/AnimSequence.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Engine/SkeletalMesh.h"

bool LivingTownCafeWorker110::HasUnfilteredUnscaled1DMotionPolicy(const UBlendSpace* Motion)
{
    if(!Motion||Motion->GetClass()!=UBlendSpace1D::StaticClass())return false;
    const auto* OneD=Cast<UBlendSpace1D>(Motion);
    const auto& Axis=OneD->GetBlendParameter(0);
    return !Axis.bSnapToGrid&&!Axis.bWrapInput&&!OneD->bScaleAnimation&&
        OneD->TargetWeightInterpolationSpeedPerSec==0.f&&OneD->InterpolationParam[0].InterpolationTime==0.f;
}

const TArray<FString>& LivingTownCafeCurrent61Baked::MaterialAssets()
{
    static const TArray<FString> Paths={
        TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_body_1.M_Baked_body_1"),
        TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_body_2.M_Baked_body_2"),
        TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_brows_0.M_Baked_brows_0"),
        TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_eyes_0.M_Baked_eyes_0"),
        TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_garment_0.M_Baked_garment_0"),
        TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_pants_0.M_Baked_pants_0"),
        TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_shoes_0.M_Baked_shoes_0"),
        TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_apron_0.M_Baked_apron_0")
    };return Paths;
}
bool LivingTownCafeCurrent61Baked::HasUnfilteredUnscaled1DMotionPolicy(const UBlendSpace* Motion)
{
    if(!Motion||Motion->GetClass()!=UBlendSpace1D::StaticClass())return false;
    const auto* OneD=Cast<UBlendSpace1D>(Motion);const auto& Axis=OneD->GetBlendParameter(0);
    return !Axis.bSnapToGrid&&!Axis.bWrapInput&&!OneD->bScaleAnimation&&
        OneD->TargetWeightInterpolationSpeedPerSec==0.f&&OneD->InterpolationParam[0].InterpolationTime==0.f;
}

ALivingTownCafeCharacter::ALivingTownCafeCharacter()
{
    PrimaryActorTick.bCanEverTick=true; bUseControllerRotationYaw=false;
    GetCapsuleComponent()->InitCapsuleSize(20,88); // physical component only; never a ready avatar
    GetCharacterMovement()->bOrientRotationToMovement=true;GetCharacterMovement()->RotationRate=FRotator(0,480,0);
    CameraArm=CreateDefaultSubobject<USpringArmComponent>(TEXT("ThirdPersonArm"));CameraArm->SetupAttachment(GetRootComponent());CameraArm->bUsePawnControlRotation=true;CameraArm->bDoCollisionTest=true;CameraArm->TargetOffset=FVector(0,0,45);
    Camera=CreateDefaultSubobject<UCameraComponent>(TEXT("ThirdPersonCamera"));Camera->SetupAttachment(CameraArm);Camera->bUsePawnControlRotation=false;
    GetMesh()->SetVisibility(false);SetActorTickEnabled(false);
}
bool ALivingTownCafeCharacter::ConfigureQualifiedBen(const FLivingTownCafeBinding& B,FString& Error)
{
    Error.Reset(); if(bVisualQualified||B.ResidentId!=TEXT("ben")){Error=TEXT("exact_Ben_roster_binding_required");return false;}
    const bool bWorker110=B.MotionStrategy==ELivingTownCafeMotionStrategy::CafeWorker110RootAligned;
    const bool bCurrent61Baked=B.MotionStrategy==ELivingTownCafeMotionStrategy::Current61BakedSingleNode;
    if(B.MotionStrategy!=ELivingTownCafeMotionStrategy::LegacySingleNode&&!bWorker110&&!bCurrent61Baked){Error=TEXT("unsupported_cafe_motion_strategy");return false;}
    UMaterial* WorkerMaterial=nullptr;
    UAnimSequence* WorkerIdle=nullptr;UAnimSequence* WorkerWalk=nullptr;
    if(bWorker110)
    {
        // Read the actual saved UMaterial usage before loading any worker mesh.
        // Never repair usage in Game or accept a material-instance base flag.
        WorkerMaterial=LoadObject<UMaterial>(nullptr,LivingTownCafeWorker110::MaterialAsset);
        if(!WorkerMaterial||WorkerMaterial->GetClass()!=UMaterial::StaticClass()||!WorkerMaterial->GetUsageByFlag(MATUSAGE_SkeletalMesh)||
            B.VisualAssetPath!=LivingTownCafeWorker110::MeshAsset||B.IdleWalkBlendSpacePath!=LivingTownCafeWorker110::MotionAsset||
            B.IdleAnimationPath!=LivingTownCafeWorker110::IdleAsset||B.WalkAnimationPath!=LivingTownCafeWorker110::WalkAsset||
            B.UseSocket!=LivingTownCafeWorker110::PalmSocket||B.IdleRootDeltaCm!=LivingTownCafeWorker110::RootDeltaCm()||B.WalkSpeedCmPerSecond!=110.f)
        {Error=TEXT("cold_qualified_worker110_material_and_binding_required");return false;}
        WorkerIdle=LoadObject<UAnimSequence>(nullptr,*B.IdleAnimationPath);WorkerWalk=LoadObject<UAnimSequence>(nullptr,*B.WalkAnimationPath);
        if(!WorkerIdle||!WorkerWalk||WorkerIdle==WorkerWalk||WorkerIdle->RateScale!=1.f||WorkerWalk->RateScale!=1.f||
            WorkerIdle->IsValidAdditive()||WorkerWalk->IsValidAdditive()||WorkerIdle->bEnableRootMotion||WorkerWalk->bEnableRootMotion||
            WorkerIdle->GetNumberOfSampledKeys()!=462||WorkerWalk->GetNumberOfSampledKeys()!=72||
            WorkerIdle->GetPlayLength()!=15.366666793823242||WorkerWalk->GetPlayLength()!=2.366666555404663)
        {Error=TEXT("unchanged_full_worker110_source_clips_required");return false;}
    }
    TArray<UMaterial*> BakedMaterials;UAnimSequence* BakedIdle=nullptr;UAnimSequence* BakedWalk=nullptr;
    if(bCurrent61Baked)
    {
        // Read all8 saved UMaterial skeletal flags before loading the new duplicate mesh.
        // No material usage repair, source PBR006 mutation or engine default fallback.
        if(!B.HasValidatedCurrent61BakedAvatarBinding()||
            B.VisualAssetPath!=LivingTownCafeCurrent61Baked::MeshAsset||B.IdleWalkBlendSpacePath!=LivingTownCafeCurrent61Baked::MotionAsset||
            B.IdleAnimationPath!=LivingTownCafeCurrent61Baked::IdleAsset||B.WalkAnimationPath!=LivingTownCafeCurrent61Baked::WalkAsset||B.UseSocket!=LivingTownCafeCurrent61Baked::PalmSocket||
            B.MeshRelativeTransform.GetScale3D()!=FVector::OneVector||B.IdleRootDeltaCm!=FVector::ZeroVector||
            B.WalkSpeedCmPerSecond!=float(B.Current61BakedCalibration.WalkSpeedCmPerSecond))
        {Error=TEXT("qualified_current61_baked_avatar_descriptor_required");return false;}
        for(const FString& Path:LivingTownCafeCurrent61Baked::MaterialAssets())
        {
            UMaterial* Material=LoadObject<UMaterial>(nullptr,*Path);
            if(!Material||Material->GetClass()!=UMaterial::StaticClass()||!Material->GetUsageByFlag(MATUSAGE_SkeletalMesh))
            {Error=TEXT("cold_qualified_all8_current61_baked_materials_required");return false;}
            BakedMaterials.Add(Material);
        }
        BakedIdle=LoadObject<UAnimSequence>(nullptr,*B.IdleAnimationPath);BakedWalk=LoadObject<UAnimSequence>(nullptr,*B.WalkAnimationPath);
        if(!BakedIdle||!BakedWalk||BakedIdle==BakedWalk||BakedIdle->RateScale!=1.f||BakedWalk->RateScale!=1.f||
            BakedIdle->IsValidAdditive()||BakedWalk->IsValidAdditive()||BakedIdle->bEnableRootMotion||BakedWalk->bEnableRootMotion||
            BakedIdle->GetNumberOfSampledKeys()!=461||BakedWalk->GetNumberOfSampledKeys()!=71||
            double(BakedIdle->GetPlayLength())!=B.Current61BakedCalibration.IdleDurationSeconds||double(BakedWalk->GetPlayLength())!=B.Current61BakedCalibration.WalkDurationSeconds||
            BakedIdle->GetSamplingFrameRate()!=FFrameRate(30,1)||BakedWalk->GetSamplingFrameRate()!=FFrameRate(30,1))
        {Error=TEXT("qualified_complete_current61_baked30hz_idle_walk_required");return false;}
    }
    USkeletalMesh* Visual=LoadObject<USkeletalMesh>(nullptr,*B.VisualAssetPath);UBlendSpace* Motion=LoadObject<UBlendSpace>(nullptr,*B.IdleWalkBlendSpacePath);
    if(!Visual||!Visual->GetSkeleton()||!Motion||Motion->GetSkeleton()!=Visual->GetSkeleton()||Motion->GetBlendParameter(0).Min>0||Motion->GetBlendParameter(0).Max<B.WalkSpeedCmPerSecond){Error=TEXT("qualified_Ben_mesh_and_matching_idle_walk_motion_required");return false;}
    if(bWorker110)
    {
        const auto& Ref=Visual->GetRefSkeleton();const auto* Render=Visual->GetResourceForRendering();const auto* Palm=Visual->FindSocket(FName(LivingTownCafeWorker110::PalmSocket));
        const FTransform ReviewedPalm(FQuat::Identity,LivingTownCafeWorker110::PalmLocalCm(),FVector::OneVector);
        if(Ref.GetNum()!=61||Ref.GetBoneName(0)!=FName(TEXT("root"))||Ref.GetParentIndex(0)!=INDEX_NONE||
            !Render||Render->LODRenderData.Num()!=1||Render->LODRenderData[0].GetNumVertices()!=10707||Render->LODRenderData[0].GetTotalFaces()!=18425||Render->LODRenderData[0].GetNumTexCoords()!=1||Render->LODRenderData[0].RenderSections.Num()!=1||
            Visual->GetMaterials().Num()!=1||Visual->GetMaterials()[0].MaterialInterface.Get()!=WorkerMaterial||
            !Palm||Palm->GetOuter()!=Visual||Palm->BoneName!=FName(TEXT("hand_r"))||!Palm->GetSocketLocalTransform().Equals(ReviewedPalm,1e-9)||
            !LivingTownCafeWorker110::HasUnfilteredUnscaled1DMotionPolicy(Motion)||
            Motion->GetBlendSamples().Num()!=2||Motion->IsValidAdditive()||Motion->GetBlendParameter(0).Min!=0.f||Motion->GetBlendParameter(0).Max!=110.f||
            WorkerIdle->GetSkeleton()!=Visual->GetSkeleton()||WorkerWalk->GetSkeleton()!=Visual->GetSkeleton())
        {Error=TEXT("actual_worker110_mesh_material_socket_and_motion_required");return false;}
        for(const auto& Sample:Motion->GetBlendSamples())
        {
            const bool IdleRole=Sample.Animation==WorkerIdle&&Sample.SampleValue==FVector::ZeroVector;
            const bool WalkRole=Sample.Animation==WorkerWalk&&Sample.SampleValue==FVector(110,0,0);
            if((!IdleRole&&!WalkRole)||Sample.RateScale!=1.f||Sample.bUseSingleFrameForBlending||Sample.bMirror)
            {Error=TEXT("worker110_unmodified_two_full_rate1_samples_required");return false;}
        }
    }
    if(bCurrent61Baked)
    {
        const auto& Ref=Visual->GetRefSkeleton();const auto* Render=Visual->GetResourceForRendering();const auto* Palm=Visual->FindSocket(FName(LivingTownCafeCurrent61Baked::PalmSocket));
        if(Ref.GetNum()!=62||Ref.GetBoneName(0)!=FName(LivingTownCafeCurrent61Baked::WrapperBone)||Ref.GetParentIndex(0)!=INDEX_NONE||Ref.GetBoneName(1)!=FName(TEXT("root"))||Ref.GetParentIndex(1)!=0||
            !Render||Render->LODRenderData.Num()!=1||Render->LODRenderData[0].GetNumVertices()!=43432||Render->LODRenderData[0].GetTotalFaces()!=72848||Render->LODRenderData[0].GetNumTexCoords()!=3||Render->LODRenderData[0].RenderSections.Num()!=8||
            Visual->GetMaterials().Num()!=8||BakedMaterials.Num()!=8||!Palm||Palm->GetOuter()!=Visual||Palm->BoneName!=FName(TEXT("hand_r"))||
            !Palm->GetSocketLocalTransform().Equals(B.Current61BakedCalibration.PalmSocketLocalTransform,1e-9)||
            !LivingTownCafeCurrent61Baked::HasUnfilteredUnscaled1DMotionPolicy(Motion)||Motion->GetBlendSamples().Num()!=2||Motion->IsValidAdditive()||
            Motion->GetBlendParameter(0).Min!=0.f||Motion->GetBlendParameter(0).Max!=B.WalkSpeedCmPerSecond||
            BakedIdle->GetSkeleton()!=Visual->GetSkeleton()||BakedWalk->GetSkeleton()!=Visual->GetSkeleton())
        {Error=TEXT("actual_current61_baked_body_socket_and_measured_gait_motion_required");return false;}
        TSet<int32> SectionMaterialSlots;
        for(int32 I=0;I<8;++I)
        {
            if(Visual->GetMaterials()[I].MaterialInterface.Get()!=BakedMaterials[I]){Error=TEXT("exact8_current61_baked_material_order_required");return false;}
            const int32 Slot=Render->LODRenderData[0].RenderSections[I].MaterialIndex;
            if(Slot<0||Slot>=8||SectionMaterialSlots.Contains(Slot)){Error=TEXT("exact8_current61_baked_section_slots_required");return false;}SectionMaterialSlots.Add(Slot);
        }
        for(const auto& Sample:Motion->GetBlendSamples())
        {
            const bool IdleRole=Sample.Animation==BakedIdle&&Sample.SampleValue==FVector::ZeroVector;
            const bool WalkRole=Sample.Animation==BakedWalk&&Sample.SampleValue==FVector(B.WalkSpeedCmPerSecond,0,0);
            if((!IdleRole&&!WalkRole)||Sample.RateScale!=1.f||Sample.bUseSingleFrameForBlending||Sample.bMirror)
            {Error=TEXT("current61_baked_two_full_rate1_measured_speed_samples_required");return false;}
        }
    }
    const UAnimSequence* IdleSample=nullptr;const UAnimSequence* WalkSample=nullptr;
    for(const FBlendSample& Sample:Motion->GetBlendSamples())
    {
        const UAnimSequence* A=Sample.Animation;if(!A||A->GetSkeleton()!=Visual->GetSkeleton()||A->GetPlayLength()<=0||A->GetNumberOfSampledKeys()<2||Sample.bUseSingleFrameForBlending||Sample.RateScale<=0){Error=TEXT("actual_idle_walk_animation_samples_required");return false;}
        if(Sample.SampleValue.X<=.01)IdleSample=A;if(Sample.SampleValue.X>=B.WalkSpeedCmPerSecond-.01)WalkSample=A;
    }
    if(!IdleSample||!WalkSample||IdleSample==WalkSample){Error=TEXT("distinct_source_idle_and_walk_clips_required");return false;}
    // Raw editor SampleData alone is insufficient: a saved BlendSpace can have
    // two valid clips but no built runtime segments/grid, yielding no samples
    // and a fixed reference pose. Qualify the same public sampler used by its
    // runtime player. Never rebuild asset interpolation or force poses here.
    for(const double Fraction : {0.0,0.5,1.0})
    {
        TArray<FBlendSampleData> Weighted;int32 CachedSegment=INDEX_NONE;
        if(!Motion->GetSamplesFromBlendInput(FVector(B.WalkSpeedCmPerSecond*Fraction,0,0),Weighted,CachedSegment,true)||Weighted.Num()<1||Weighted.Num()>2)
        {Error=TEXT("qualified_Ben_motion_runtime_interpolation_missing");return false;}
        double IdleWeight=0,WalkWeight=0;
        for(const FBlendSampleData& Sample:Weighted)
        {
            if(!FMath::IsFinite(Sample.TotalWeight)||Sample.TotalWeight<=0||(Sample.Animation!=IdleSample&&Sample.Animation!=WalkSample))
            {Error=TEXT("qualified_Ben_motion_runtime_weights_invalid");return false;}
            if(Sample.Animation==IdleSample)IdleWeight+=Sample.TotalWeight;if(Sample.Animation==WalkSample)WalkWeight+=Sample.TotalWeight;
        }
        if(!FMath::IsNearlyEqual(IdleWeight,1.-Fraction,.001)||!FMath::IsNearlyEqual(WalkWeight,Fraction,.001))
        {Error=TEXT("qualified_Ben_motion_idle_walk_interpolation_inconsistent");return false;}
    }

    GetMesh()->SetSkeletalMeshAsset(Visual);GetMesh()->SetRelativeTransform(B.MeshRelativeTransform);UseSocket=B.UseSocket;
    if(!GetMesh()->DoesSocketExist(FName(*UseSocket))){Error=TEXT("calibrated_Ben_hand_socket_missing");GetMesh()->SetSkeletalMeshAsset(nullptr);return false;}
    GetCapsuleComponent()->SetCapsuleSize(B.CapsuleRadiusCm,B.CapsuleHalfHeightCm,true);GetCharacterMovement()->MaxWalkSpeed=B.WalkSpeedCmPerSecond;CameraArm->TargetArmLength=B.CameraArmCm;if(bWorker110||bCurrent61Baked)CameraArm->TargetOffset.Z=0.f; // Origin is capsule centre; keep full body framed during short boom collisions.
    IdleWalk=Motion;
    if(bWorker110)
    {
        GetMesh()->SetAnimInstanceClass(ULivingTownRootCorrectedSingleNodeInstance::StaticClass());
        auto* Instance=Cast<ULivingTownRootCorrectedSingleNodeInstance>(GetMesh()->GetAnimInstance());
        if(!Instance||GetMesh()->GetSingleNodeInstance()!=Instance||
            !Instance->ConfigureRootCorrection(Motion,WorkerIdle,WorkerWalk,B.IdleRootDeltaCm,true,false,Error))
        {if(Error.IsEmpty())Error=TEXT("configured_native_worker110_player_required");return false;}
        // Configure sets and retains the original source asset. PlayAnimation would reset the class.
        Instance->SetLooping(true);Instance->SetPlayRate(1.f);Instance->SetPlaying(true);
    }
    else
    {
        GetMesh()->SetAnimationMode(EAnimationMode::AnimationSingleNode);GetMesh()->PlayAnimation(IdleWalk,true);
    }
    if(bCurrent61Baked&&(!GetMesh()->GetSingleNodeInstance()||GetMesh()->GetSingleNodeInstance()->GetClass()!=UAnimSingleNodeInstance::StaticClass()||GetMesh()->GetAnimationMode()!=EAnimationMode::AnimationSingleNode))
    {Error=TEXT("plain_current61_baked_single_node_player_required");return false;}
    if(!GetMesh()->GetSingleNodeInstance()){Error=TEXT("native_idle_walk_player_missing");return false;}
    GetMesh()->SetCollisionEnabled(ECollisionEnabled::NoCollision);GetMesh()->SetVisibility(true);bVisualQualified=true;bWorker110VisualQualified=bWorker110;bCurrent61BakedVisualQualified=bCurrent61Baked;SetActorTickEnabled(true);UpdatePossessedBonePolicy();return true;
}
void ALivingTownCafeCharacter::RestorePossessedBonePolicy()
{
    if(bPossessedBonePolicyApplied&&GetMesh())GetMesh()->VisibilityBasedAnimTickOption=static_cast<EVisibilityBasedAnimTickOption>(PreviousPossessedBonePolicy);
    bPossessedBonePolicyApplied=false;
}
void ALivingTownCafeCharacter::UpdatePossessedBonePolicy()
{
    // Gameplay uses this active player's palm/socket and body bones even when occluded.
    // Do not expand full bone evaluation to legacy visuals, AI or unpossessed workers.
    RestorePossessedBonePolicy();
    const bool bQualifiedRootPlayer=bWorker110VisualQualified&&GetMesh()&&Cast<ULivingTownRootCorrectedSingleNodeInstance>(GetMesh()->GetAnimInstance());
    const bool bQualifiedBakedPlayer=bCurrent61BakedVisualQualified&&GetMesh()&&GetMesh()->GetAnimationMode()==EAnimationMode::AnimationSingleNode&&GetMesh()->GetSingleNodeInstance()&&GetMesh()->GetSingleNodeInstance()->GetClass()==UAnimSingleNodeInstance::StaticClass();
    if(bVisualQualified&&Controller&&Controller->IsPlayerController()&&(bQualifiedRootPlayer||bQualifiedBakedPlayer))
    {
        PreviousPossessedBonePolicy=static_cast<uint8>(GetMesh()->VisibilityBasedAnimTickOption);
        GetMesh()->VisibilityBasedAnimTickOption=EVisibilityBasedAnimTickOption::AlwaysTickPoseAndRefreshBones;
        bPossessedBonePolicyApplied=true;
    }
}
void ALivingTownCafeCharacter::PossessedBy(AController* NewController)
{
    Super::PossessedBy(NewController);UpdatePossessedBonePolicy();
}
void ALivingTownCafeCharacter::UnPossessed()
{
    Super::UnPossessed();RestorePossessedBonePolicy();
}
void ALivingTownCafeCharacter::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
    RestorePossessedBonePolicy();Super::EndPlay(EndPlayReason);
}
FVector ALivingTownCafeCharacter::InteractionHand()const{return bVisualQualified?GetMesh()->GetSocketLocation(FName(*UseSocket)):FVector::ZeroVector;}
void ALivingTownCafeCharacter::Tick(float Delta)
{
    Super::Tick(Delta);if(bVisualQualified&&GetMesh()->GetSingleNodeInstance())GetMesh()->GetSingleNodeInstance()->SetBlendSpacePosition(FVector(GetVelocity().Size2D(),0,0));
}
void ALivingTownCafeCharacter::Forward(float V){if(bVisualQualified&&Controller&&V!=0)AddMovementInput(FRotationMatrix(FRotator(0,Controller->GetControlRotation().Yaw,0)).GetUnitAxis(EAxis::X),V);}
void ALivingTownCafeCharacter::Right(float V){if(bVisualQualified&&Controller&&V!=0)AddMovementInput(FRotationMatrix(FRotator(0,Controller->GetControlRotation().Yaw,0)).GetUnitAxis(EAxis::Y),V);}
void ALivingTownCafeCharacter::Yaw(float V){if(bVisualQualified)AddControllerYawInput(V);}
void ALivingTownCafeCharacter::Pitch(float V){if(bVisualQualified)AddControllerPitchInput(V);}
void ALivingTownCafeCharacter::SetupPlayerInputComponent(UInputComponent* Input)
{
    Super::SetupPlayerInputComponent(Input);check(Input);Input->BindAxis(TEXT("CafeForward"),this,&ALivingTownCafeCharacter::Forward);Input->BindAxis(TEXT("CafeRight"),this,&ALivingTownCafeCharacter::Right);Input->BindAxis(TEXT("CafeYaw"),this,&ALivingTownCafeCharacter::Yaw);Input->BindAxis(TEXT("CafePitch"),this,&ALivingTownCafeCharacter::Pitch);
}
