#include "LivingTownCafeCharacter.h"
#include "Components/CapsuleComponent.h"
#include "Components/InputComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Camera/CameraComponent.h"
#include "GameFramework/SpringArmComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Animation/BlendSpace.h"
#include "Animation/AnimSequence.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Engine/SkeletalMesh.h"

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
    USkeletalMesh* Visual=LoadObject<USkeletalMesh>(nullptr,*B.VisualAssetPath);UBlendSpace* Motion=LoadObject<UBlendSpace>(nullptr,*B.IdleWalkBlendSpacePath);
    if(!Visual||!Visual->GetSkeleton()||!Motion||Motion->GetSkeleton()!=Visual->GetSkeleton()||Motion->GetBlendParameter(0).Min>0||Motion->GetBlendParameter(0).Max<B.WalkSpeedCmPerSecond){Error=TEXT("qualified_Ben_mesh_and_matching_idle_walk_motion_required");return false;}
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
    GetCapsuleComponent()->SetCapsuleSize(B.CapsuleRadiusCm,B.CapsuleHalfHeightCm,true);GetCharacterMovement()->MaxWalkSpeed=B.WalkSpeedCmPerSecond;CameraArm->TargetArmLength=B.CameraArmCm;
    IdleWalk=Motion;GetMesh()->SetAnimationMode(EAnimationMode::AnimationSingleNode);GetMesh()->PlayAnimation(IdleWalk,true);
    if(!GetMesh()->GetSingleNodeInstance()){Error=TEXT("native_idle_walk_player_missing");return false;}
    GetMesh()->SetCollisionEnabled(ECollisionEnabled::NoCollision);GetMesh()->SetVisibility(true);bVisualQualified=true;SetActorTickEnabled(true);return true;
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
