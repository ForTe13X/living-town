#include "LivingTownCafeProjectionSubsystem.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownCafeVenue.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "HAL/PlatformTime.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Components/BoxComponent.h"
#include "Components/CapsuleComponent.h"
#include "LivingTownCafeGameMode.h"
#include "Components/SkeletalMeshComponent.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Animation/BlendSpace.h"
#include "Engine/SkeletalMesh.h"
#include "ReferenceSkeleton.h"
#include "UObject/Package.h"
#include "Camera/CameraComponent.h"
#include "Camera/PlayerCameraManager.h"
#include "GameFramework/SpringArmComponent.h"
#include "HAL/FileManager.h"
#include "Tests/AutomationCommon.h"
#include "Misc/FileHelper.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

namespace
{

// Evidence is read from the naturally ticking game component. This test never
// calls TickAnimation/RefreshBoneTransforms, sets animation time/pose, changes
// visibility tick policy, or teleports the character to manufacture a pass.
static const FName PoseBones[]={TEXT("Skin_Foot_L"),TEXT("Skin_Foot_R"),TEXT("Skin_Shin_L"),TEXT("Skin_Shin_R"),TEXT("Skin_UpperArm_L"),TEXT("Skin_UpperArm_R"),TEXT("Skin_PelvisRoot")};
static TArray<TSharedPtr<FJsonValue>> VectorJson(const FVector& V)
{
    return {MakeShared<FJsonValueNumber>(V.X),MakeShared<FJsonValueNumber>(V.Y),MakeShared<FJsonValueNumber>(V.Z)};
}
static TSharedPtr<FJsonObject> TransformJson(const FTransform& T)
{
    auto J=MakeShared<FJsonObject>();J->SetArrayField(TEXT("translation_cm"),VectorJson(T.GetTranslation()));J->SetArrayField(TEXT("scale"),VectorJson(T.GetScale3D()));
    const FQuat Q=T.GetRotation();J->SetArrayField(TEXT("rotation_quat_xyzw"),{MakeShared<FJsonValueNumber>(Q.X),MakeShared<FJsonValueNumber>(Q.Y),MakeShared<FJsonValueNumber>(Q.Z),MakeShared<FJsonValueNumber>(Q.W)});return J;
}
struct FCafeMotionSummary
{
    int32 MovingSamples=0,TimeChanges=0;double FirstMovingWorld=0,LastMovingWorld=0,TimeTravel=0,DistanceCm=0;float LastAnimationTime=0;
    FVector FirstActor=FVector::ZeroVector;FTransform FirstBones[7];double FootSpanCm[2]={0,0},ShinLocalDegrees[2]={0,0},ArmLocalDegrees[2]={0,0};
    bool Qualifies()const
    {
        return MovingSamples>=12&&LastMovingWorld-FirstMovingWorld>=.6&&DistanceCm>=80&&TimeChanges>=3&&TimeTravel>=.05&&
            FootSpanCm[0]>=2&&FootSpanCm[1]>=2&&ShinLocalDegrees[0]>=2&&ShinLocalDegrees[1]>=2&&ArmLocalDegrees[0]>=2&&ArmLocalDegrees[1]>=2;
    }
    TSharedPtr<FJsonObject> Json()const
    {
        auto J=MakeShared<FJsonObject>();J->SetNumberField(TEXT("moving_samples"),MovingSamples);J->SetNumberField(TEXT("moving_world_span_seconds"),LastMovingWorld-FirstMovingWorld);J->SetNumberField(TEXT("actor_displacement_cm"),DistanceCm);J->SetNumberField(TEXT("normalized_blend_time_changes"),TimeChanges);J->SetNumberField(TEXT("normalized_blend_time_absolute_travel"),TimeTravel);
        for(int32 I=0;I<2;++I){const FString Side=I==0?TEXT("left"):TEXT("right");J->SetNumberField(Side+TEXT("_foot_minus_pelvis_component_span_from_first_cm"),FootSpanCm[I]);J->SetNumberField(Side+TEXT("_shin_parent_relative_rotation_degrees"),ShinLocalDegrees[I]);J->SetNumberField(Side+TEXT("_upper_arm_parent_relative_rotation_degrees"),ArmLocalDegrees[I]);}
        J->SetBoolField(TEXT("qualifies"),Qualifies());return J;
    }
};
static bool CheckMotionRefusalFixtures(FAutomationTestBase* Test)
{
    FCafeMotionSummary Good;Good.MovingSamples=15;Good.FirstMovingWorld=1;Good.LastMovingWorld=2;Good.DistanceCm=100;Good.TimeChanges=10;Good.TimeTravel=.8;
    for(int I=0;I<2;++I){Good.FootSpanCm[I]=10;Good.ShinLocalDegrees[I]=10;Good.ArmLocalDegrees[I]=10;}
    bool Ok=Test->TestTrue(TEXT("Motion evidence arithmetic accepts articulated moving fixture"),Good.Qualifies());
    auto Bad=Good;for(int I=0;I<2;++I){Bad.FootSpanCm[I]=0;Bad.ShinLocalDegrees[I]=0;Bad.ArmLocalDegrees[I]=0;}Ok&=Test->TestFalse(TEXT("Actor translation with frozen T-pose rejects even if clock advances"),Bad.Qualifies());
    Bad=Good;Bad.TimeTravel=0;Bad.TimeChanges=0;Ok&=Test->TestFalse(TEXT("Pose deltas without playback time reject"),Bad.Qualifies());
    Bad=Good;Bad.DistanceCm=0;Ok&=Test->TestFalse(TEXT("Animated stationary fixture is not walked journey"),Bad.Qualifies());
    Bad=Good;Bad.ShinLocalDegrees[1]=0;Ok&=Test->TestFalse(TEXT("One frozen leg rejects"),Bad.Qualifies());return Ok;
}

class FCafeActualJourney final:public IAutomationLatentCommand
{
    FAutomationTestBase* Test;double Deadline=0;int32 Stage=0,Waypoint=0;double SettleUntil=0;TWeakObjectPtr<AActor> Occluder;
    // Root-supplied engine-qualified route: never infer walkability from a
    // logical cell or silently keep an obsolete capsule/visual calibration.
    TArray<FVector> Route;
    const FLivingTownCafeBinding ExpectedBinding;const FString ExpectedRouteSha256;
    TWeakObjectPtr<UWorld> QualifiedWorld;TWeakObjectPtr<ALivingTownCafeCharacter> QualifiedBen;TWeakObjectPtr<APlayerController> QualifiedController;
    TSharedPtr<FJsonObject> Evidence=MakeShared<FJsonObject>();TArray<TSharedPtr<FJsonValue>> Samples;FCafeMotionSummary Motion;
    FTransform FirstLocal[7];double LastSampleWorld=-1,ReadySince=-1;FVector LastActor=FVector::ZeroVector;bool bHaveActorSample=false,bJourneyCompleted=false;
    bool Capture(UWorld* W,APlayerController* PC,ALivingTownCafeCharacter* Ben,const TCHAR* Label,bool Force=false)
    {
        const double WorldTime=W->GetTimeSeconds();if(!Force&&WorldTime-LastSampleWorld<.05)return true;
        if(Samples.Num()>=256){Test->AddError(TEXT("Motion evidence exceeded bounded256samples before journey completed"));return false;}
        auto* Mesh=Ben->GetMesh();auto* Anim=Mesh?Mesh->GetSingleNodeInstance():nullptr;auto* Camera=Ben->FindComponentByClass<UCameraComponent>();auto* Arm=Ben->FindComponentByClass<USpringArmComponent>();
        if(!Mesh||!Anim||!Camera||!Arm||!PC->PlayerCameraManager||!Mesh->GetSkeletalMeshAsset()){Test->AddError(TEXT("Actual runtime mesh/player/camera missing"));return false;}
        if(QualifiedWorld.IsValid()&&(QualifiedWorld.Get()!=W||QualifiedBen.Get()!=Ben||QualifiedController.Get()!=PC)){Test->AddError(TEXT("Journey world/player identity changed"));return false;}
        const bool Identity=UWorld::RemovePIEPrefix(W->GetOutermost()->GetName())==TEXT("/Engine/Maps/Entry")&&W->HasBegunPlay()&&Ben->HasQualifiedVisual()&&W->GetNetMode()==NM_Standalone&&Cast<ALivingTownCafeGameMode>(W->GetAuthGameMode())&&PC->GetPawn()==Ben&&Ben->GetController()==PC&&PC->GetViewTarget()==Ben&&Mesh->GetSkeletalMeshAsset()->GetPathName()==ExpectedBinding.VisualAssetPath&&Anim->GetCurrentAsset()&&Anim->GetCurrentAsset()->GetPathName()==ExpectedBinding.IdleWalkBlendSpacePath&&Mesh->GetRelativeTransform().Equals(ExpectedBinding.MeshRelativeTransform,.001);
        
        const FVector CameraPosition=PC->PlayerCameraManager->GetCameraLocation();const FRotator CameraRotation=PC->PlayerCameraManager->GetCameraRotation();const float Fov=PC->PlayerCameraManager->GetFOVAngle();
        const FVector ToBen=Ben->GetActorLocation()-CameraPosition;
        const bool CameraValid=Camera->IsActive()&&Camera->GetAttachParent()==Arm&&FMath::IsNearlyEqual(Arm->TargetArmLength,ExpectedBinding.CameraArmCm,.01f)&&!CameraPosition.ContainsNaN()&&!CameraRotation.ContainsNaN()&&FMath::IsFinite(Fov)&&Fov>=5&&Fov<=170&&FVector::Dist(CameraPosition,Camera->GetComponentLocation())<5&&ToBen.Size()>5&&ToBen.Size()<ExpectedBinding.CameraArmCm+300&&FVector::DotProduct(ToBen.GetSafeNormal(),CameraRotation.Vector())>.1;
        
        
        if(bHaveActorSample&&WorldTime>LastSampleWorld)
        {
            const double MaxStep=ExpectedBinding.WalkSpeedCmPerSecond*(WorldTime-LastSampleWorld)+2.;
            if(!Test->TestTrue(TEXT("Observed walking displacement respects actual speed/world delta; no teleport"),FVector::Dist2D(Ben->GetActorLocation(),LastActor)<=MaxStep))return false;
        }
        auto J=MakeShared<FJsonObject>();J->SetStringField(TEXT("label"),Label);J->SetNumberField(TEXT("world_seconds"),WorldTime);J->SetNumberField(TEXT("world_delta_seconds"),W->GetDeltaSeconds());J->SetStringField(TEXT("engine_frame"),FString::Printf(TEXT("%llu"),static_cast<unsigned long long>(GFrameCounter)));J->SetNumberField(TEXT("animation_normalized_time"),Anim->GetCurrentTime());J->SetBoolField(TEXT("animation_playing"),Anim->IsPlaying());J->SetNumberField(TEXT("animation_play_rate"),Anim->GetPlayRate());J->SetStringField(TEXT("animation_asset"),Anim->GetCurrentAsset()?Anim->GetCurrentAsset()->GetPathName():TEXT("missing"));J->SetStringField(TEXT("mesh_asset"),Mesh->GetSkeletalMeshAsset()->GetPathName());J->SetObjectField(TEXT("actor_transform"),TransformJson(Ben->GetActorTransform()));J->SetObjectField(TEXT("mesh_component_transform"),TransformJson(Mesh->GetComponentTransform()));J->SetArrayField(TEXT("velocity_cm_per_second"),VectorJson(Ben->GetVelocity()));J->SetBoolField(TEXT("moving_on_actual_floor"),Ben->GetCharacterMovement()->IsMovingOnGround());J->SetArrayField(TEXT("camera_location_cm"),VectorJson(CameraPosition));J->SetArrayField(TEXT("camera_rotation_pitch_yaw_roll"),VectorJson(FVector(CameraRotation.Pitch,CameraRotation.Yaw,CameraRotation.Roll)));J->SetNumberField(TEXT("camera_fov"),Fov);J->SetObjectField(TEXT("camera_component_transform"),TransformJson(Camera->GetComponentTransform()));J->SetObjectField(TEXT("mesh_relative_transform"),TransformJson(Mesh->GetRelativeTransform()));J->SetNumberField(TEXT("camera_target_arm_length_cm"),Arm->TargetArmLength);J->SetBoolField(TEXT("camera_component_active"),Camera->IsActive());J->SetBoolField(TEXT("camera_attached_to_source_arm"),Camera->GetAttachParent()==Arm);J->SetStringField(TEXT("camera_view_target"),PC->GetViewTarget()?PC->GetViewTarget()->GetPathName():TEXT("missing"));J->SetNumberField(TEXT("visibility_based_anim_tick_option"),int32(Mesh->VisibilityBasedAnimTickOption));J->SetBoolField(TEXT("update_rate_optimization_enabled"),Mesh->bEnableUpdateRateOptimizations);
        FVector BlendInput,Filtered;Anim->GetBlendSpaceState(BlendInput,Filtered);J->SetArrayField(TEXT("blend_input_cm_per_second"),VectorJson(BlendInput));J->SetArrayField(TEXT("blend_filtered_input"),VectorJson(Filtered));
        const auto& Poses=Mesh->GetComponentSpaceTransforms();const auto& Ref=Mesh->GetSkeletalMeshAsset()->GetRefSkeleton();auto Bones=MakeShared<FJsonObject>();FTransform CS[7],Local[7];
        for(int32 I=0;I<7;++I)
        {
            const int32 Index=Mesh->GetBoneIndex(PoseBones[I]);if(!Poses.IsValidIndex(Index)){Test->AddError(TEXT("Source bound evaluated limb bone missing: ")+PoseBones[I].ToString());return false;}
            CS[I]=Poses[Index];const int32 Parent=Ref.GetParentIndex(Index);if(Parent!=INDEX_NONE&&!Poses.IsValidIndex(Parent)){Test->AddError(TEXT("Source bound evaluated parent bone missing"));return false;}Local[I]=Parent==INDEX_NONE?CS[I]:CS[I].GetRelativeTransform(Poses[Parent]);
            if(CS[I].ContainsNaN()||Local[I].ContainsNaN()){Test->AddError(TEXT("Nonfinite evaluated component/parent-relative pose"));return false;}
            auto Bone=MakeShared<FJsonObject>();Bone->SetStringField(TEXT("parent_name"),Parent==INDEX_NONE?TEXT("none"):Ref.GetBoneName(Parent).ToString());Bone->SetObjectField(TEXT("parent_component"),TransformJson(Parent==INDEX_NONE?FTransform::Identity:Poses[Parent]));Bone->SetObjectField(TEXT("component"),TransformJson(CS[I]));Bone->SetObjectField(TEXT("parent_relative"),TransformJson(Local[I]));Bones->SetObjectField(PoseBones[I].ToString(),Bone);
        }
        J->SetObjectField(TEXT("evaluated_bones"),Bones);J->SetBoolField(TEXT("identity_valid"),Identity);J->SetBoolField(TEXT("camera_valid"),CameraValid);J->SetBoolField(TEXT("mesh_visible"),Mesh->IsVisible());J->SetBoolField(TEXT("mesh_component_tick_enabled"),Mesh->IsComponentTickEnabled());J->SetBoolField(TEXT("world_paused"),W->IsPaused());Evidence->SetObjectField(TEXT("last_observation_including_failure"),J);
        if(!Test->TestTrue(TEXT("Actual game/possessedBen/mesh/motion/camera binding stays exact"),Identity))return false;
        if(!Test->TestTrue(TEXT("Actual active third-person camera is finite and views Ben"),CameraValid))return false;
        if(!Test->TestTrue(TEXT("Game world time advances naturally and mesh ticks without test overrides"),!W->IsPaused()&&FMath::IsFinite(WorldTime)&&Mesh->IsVisible()&&Mesh->IsComponentTickEnabled()&&Anim->IsPlaying()&&Anim->GetPlayRate()>0))return false;
        const bool Moving=Stage==1&&Ben->GetCharacterMovement()->IsMovingOnGround()&&Ben->GetVelocity().Size2D()>=ExpectedBinding.WalkSpeedCmPerSecond*.3;
        J->SetBoolField(TEXT("qualifying_moving_sample"),Moving);
        if(Moving)
        {
            if(Motion.MovingSamples==0){Motion.FirstMovingWorld=WorldTime;Motion.FirstActor=Ben->GetActorLocation();for(int I=0;I<7;++I){Motion.FirstBones[I]=CS[I];FirstLocal[I]=Local[I];}}
            else{const double D=FMath::Abs(double(Anim->GetCurrentTime())-Motion.LastAnimationTime);if(D>1e-4){++Motion.TimeChanges;Motion.TimeTravel+=D;}}
            Motion.LastAnimationTime=Anim->GetCurrentTime();Motion.LastMovingWorld=WorldTime;Motion.DistanceCm=FMath::Max(Motion.DistanceCm,FVector::Dist2D(Motion.FirstActor,Ben->GetActorLocation()));++Motion.MovingSamples;
            for(int I=0;I<2;++I){Motion.FootSpanCm[I]=FMath::Max(Motion.FootSpanCm[I],FVector::Dist(CS[I].GetTranslation()-CS[6].GetTranslation(),Motion.FirstBones[I].GetTranslation()-Motion.FirstBones[6].GetTranslation()));Motion.ShinLocalDegrees[I]=FMath::Max(Motion.ShinLocalDegrees[I],FMath::RadiansToDegrees(Local[I+2].GetRotation().AngularDistance(FirstLocal[I+2].GetRotation())));Motion.ArmLocalDegrees[I]=FMath::Max(Motion.ArmLocalDegrees[I],FMath::RadiansToDegrees(Local[I+4].GetRotation().AngularDistance(FirstLocal[I+4].GetRotation())));}
        }
        Samples.Add(MakeShared<FJsonValueObject>(J));LastSampleWorld=WorldTime;LastActor=Ben->GetActorLocation();bHaveActorSample=true;return true;
    }
    void Persist()
    {
        TArray<uint8> BindingBytes,RouteBytes;FString BindingEnd,RouteEnd;
        const bool InputsStable=FFileHelper::LoadFileToArray(BindingBytes,*FPaths::Combine(FPaths::ProjectContentDir(),TEXT("LivingTown/CafeProjectionBinding.json")))&&LivingTownCafeJournal::Sha256(BindingBytes,BindingEnd)&&BindingEnd==ExpectedBinding.BindingFileSha256&&FFileHelper::LoadFileToArray(RouteBytes,*FPaths::Combine(FPaths::ProjectContentDir(),TEXT("LivingTown/CafeJourneyRoute.json")))&&LivingTownCafeJournal::Sha256(RouteBytes,RouteEnd)&&RouteEnd==ExpectedRouteSha256;
        Test->TestTrue(TEXT("Exact physical binding and route bytes remain unchanged through journey"),InputsStable);Evidence->SetBoolField(TEXT("binding_and_route_bytes_unchanged"),InputsStable);Evidence->SetStringField(TEXT("binding_file_sha256_end"),BindingEnd);Evidence->SetStringField(TEXT("route_sha256_end"),RouteEnd);
        Evidence->SetStringField(TEXT("format"),TEXT("LivingTown.CafeActualJourneyEvidence"));Evidence->SetNumberField(TEXT("version"),1);Evidence->SetStringField(TEXT("status"),bJourneyCompleted&&!Test->HasAnyErrors()?TEXT("PASS_ACTUAL_WALK_POSE_LEASE_LEDGER_ONLY"):TEXT("FAIL_PRESERVED_ACTUAL_JOURNEY"));Evidence->SetNumberField(TEXT("terminal_stage"),Stage);Evidence->SetStringField(TEXT("physical_scene_sha256"),ExpectedBinding.PhysicalSceneSha256);Evidence->SetStringField(TEXT("source_projection_sha256"),ExpectedBinding.SourceProjectionSha256);Evidence->SetStringField(TEXT("map_package_without_pie_prefix"),QualifiedWorld.IsValid()?UWorld::RemovePIEPrefix(QualifiedWorld->GetOutermost()->GetName()):TEXT("unavailable"));Evidence->SetStringField(TEXT("physical_binding_sha256"),ExpectedBinding.BindingFileSha256);Evidence->SetStringField(TEXT("physical_qualification_sha256"),ExpectedBinding.PhysicalQualificationSha256);Evidence->SetStringField(TEXT("visual_sha256"),ExpectedBinding.VisualSha256);Evidence->SetStringField(TEXT("route_sha256"),ExpectedRouteSha256);Evidence->SetStringField(TEXT("world"),QualifiedWorld.IsValid()?QualifiedWorld->GetPathName():TEXT("unavailable"));Evidence->SetStringField(TEXT("world_type"),!QualifiedWorld.IsValid()?TEXT("unavailable"):QualifiedWorld->WorldType==EWorldType::PIE?TEXT("PIE"):TEXT("Game"));Evidence->SetStringField(TEXT("actual_ben"),QualifiedBen.IsValid()?QualifiedBen->GetPathName():TEXT("unavailable"));Evidence->SetStringField(TEXT("source_to_ue"),TEXT("source(x,-y,z)*100 centimetres; evaluated bones component-space centimetres"));Evidence->SetObjectField(TEXT("motion_summary"),Motion.Json());Evidence->SetArrayField(TEXT("samples"),Samples);Evidence->SetBoolField(TEXT("manual_pose_animation_tick_or_position_mutation"),false);Evidence->SetBoolField(TEXT("art_contact_animation_or_frame_performance_qualified"),false);
        FString Output;const auto Writer=TJsonWriterFactory<>::Create(&Output);FJsonSerializer::Serialize(Evidence.ToSharedRef(),Writer);const FString Folder=FPaths::Combine(FPaths::ProjectSavedDir(),TEXT("CafePilotTests"));IFileManager::Get().MakeDirectory(*Folder,true);if(!FFileHelper::SaveStringToFile(Output,*FPaths::Combine(Folder,TEXT("ACTUAL_WALK_POSE_EVIDENCE.json")),FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM))Test->AddError(TEXT("Actual journey evidence could not be persisted"));
    }
public:
    FCafeActualJourney(FAutomationTestBase* T,const TArray<FVector>& Points,const FLivingTownCafeBinding& B,const FString& RouteSha):Test(T),Deadline(FPlatformTime::Seconds()+90),Route(Points),ExpectedBinding(B),ExpectedRouteSha256(RouteSha){}
    virtual bool Update()override{const bool Done=UpdateJourney();if(Done){if(Occluder.IsValid())Occluder->Destroy();Persist();}return Done;}
    bool UpdateJourney()
    {
        if(FPlatformTime::Seconds()>Deadline){Test->AddError(TEXT("Actual cafe journey timed out: source assets/calibration, possession, collision or reach did not qualify."));if(Occluder.IsValid())Occluder->Destroy();return true;}
        UWorld* W=nullptr;int32 Worlds=0;for(const auto& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::PIE||C.WorldType==EWorldType::Game)){W=C.World();++Worlds;}if(!W)return false;if(Worlds!=1){Test->AddError(TEXT("Actual journey requires exactly one Game/PIEworld; no ambiguous first-world selection"));return true;}
        auto* Projection=W->GetSubsystem<ULivingTownCafeProjectionSubsystem>();auto* PC=W->GetFirstPlayerController();auto* Ben=PC?Cast<ALivingTownCafeCharacter>(PC->GetPawn()):nullptr;
        if(!Projection||!Projection->IsReady()||!Ben)return false;
        if(Stage==0){if(ReadySince<0){ReadySince=W->GetTimeSeconds();return false;}if(W->GetTimeSeconds()-ReadySince<.25)return false;QualifiedWorld=W;QualifiedBen=Ben;QualifiedController=PC;}
        if(!Capture(W,PC,Ben,Stage==0?TEXT("spawn"):Stage==1?TEXT("walking"):TEXT("counter")))return true;
        if(Stage==0)
        {
            Test->TestTrue(TEXT("Actual qualified Ben skeletal visual, not capsule substitute"),Ben->HasQualifiedVisual());Test->TestTrue(TEXT("Actual source radius matches calibration"),FMath::IsNearlyEqual(Ben->GetCapsuleComponent()->GetScaledCapsuleRadius(),Projection->GetBinding().CapsuleRadiusCm,.01f));Test->TestTrue(TEXT("Actual source height matches calibration"),FMath::IsNearlyEqual(Ben->GetCapsuleComponent()->GetScaledCapsuleHalfHeight(),Projection->GetBinding().CapsuleHalfHeightCm,.01f));
            const FVector Feet=Ben->GetActorLocation()-FVector(0,0,Ben->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());if(!Test->TestTrue(TEXT("Actual spawn matches source route start"),FVector::Dist(Feet,Route[0])<5.))return true;
            const auto Before=Projection->GetLeaseView();Test->TestFalse(TEXT("Real far-counter command refuses"),Projection->RequestAction(ELivingTownLeaseAction::Lease).bAccepted);const auto After=Projection->GetLeaseView();Test->TestEqual(TEXT("Far command cannot move coins"),After.BenCoins,Before.BenCoins);Waypoint=1;Stage=1;
        }
        if(Stage==1)
        {
            const FVector Feet=Ben->GetActorLocation()-FVector(0,0,Ben->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());FVector Delta=Route[Waypoint]-Feet;Delta.Z=0;
            if(Delta.Size2D()>2.){PC->SetControlRotation(Delta.Rotation());Ben->AddMovementInput(Delta.GetSafeNormal2D(),1.);return false;}
            Ben->GetCharacterMovement()->StopMovementImmediately();if(++Waypoint<Route.Num())return false;
            if(!Test->TestTrue(TEXT("Walk advances normalized animation time and both evaluated feet/shins/arms; frozen pose cannot pass"),Motion.Qualifies()))return true;
            // Rotation is a physical in-place orientation only. Position is
            // never teleported to turn a rejected location into a reachable one.
            const FVector Aim=Projection->GetBinding().CounterUsePointCm-Ben->GetActorLocation();Ben->SetActorRotation(FRotator(0,Aim.Rotation().Yaw,0));SettleUntil=FPlatformTime::Seconds()+.5;Stage=2;
        }
        if(Stage==2)
        {
            if(FPlatformTime::Seconds()<SettleUntil)return false;FLivingTownTrustedInteraction At;FString Why;
            if(!Test->TestTrue(TEXT("Actual floor/hand/eye collision resolver runs"),Projection->ObserveCounter(At,Why)))return true;
            if(!Test->TestTrue(FString(TEXT("Actual walked counter reachable: "))+Why,At.bWithinReach))return true;
            Test->TestEqual(TEXT("Real logical counter identity"),At.InteractionId,FString(TEXT("cafe1f_counter")));
            // Native negative fixture: real query-only occluder, not a venue or
            // avatar asset. It must block the original source counter rays.
            AActor* Block=W->SpawnActor<AActor>();UBoxComponent* Box=NewObject<UBoxComponent>(Block);Block->SetRootComponent(Box);Box->SetBoxExtent(FVector(6,35,35));Box->SetCollisionEnabled(ECollisionEnabled::QueryOnly);Box->SetCollisionResponseToAllChannels(ECR_Ignore);Box->SetCollisionResponseToChannel(ECC_Visibility,ECR_Block);Box->RegisterComponent();Block->SetActorLocation((Ben->InteractionHand()+Projection->GetBinding().CounterUsePointCm)*.5);Occluder=Block;SettleUntil=FPlatformTime::Seconds()+.15;Stage=3;return false;
        }
        if(Stage==3)
        {
            if(FPlatformTime::Seconds()<SettleUntil)return false;FLivingTownTrustedInteraction At;FString Why;Projection->ObserveCounter(At,Why);Test->TestFalse(TEXT("Actual collision blocks line of sight"),At.bWithinReach);const auto Before=Projection->GetLeaseView();Test->TestFalse(TEXT("Occluded native action refuses"),Projection->RequestAction(ELivingTownLeaseAction::Lease).bAccepted);Test->TestEqual(TEXT("Occluded action cannot move coins"),Projection->GetLeaseView().BenCoins,Before.BenCoins);Occluder->Destroy();Occluder.Reset();SettleUntil=FPlatformTime::Seconds()+.15;Stage=4;return false;
        }
        if(Stage==4)
        {
            if(FPlatformTime::Seconds()<SettleUntil)return false;FLivingTownTrustedInteraction At;FString Why;Projection->ObserveCounter(At,Why);if(!Test->TestTrue(TEXT("Removing real obstruction restores source reach"),At.bWithinReach))return true;
            if(!Test->TestTrue(TEXT("Walked real counter lease accepted"),Projection->RequestAction(ELivingTownLeaseAction::Lease).bAccepted))return true;const auto Granted=Projection->GetLeaseView();Test->TestEqual(TEXT("Ben pays conserved4"),Granted.BenCoins,int64(8));Test->TestEqual(TEXT("Aria receives conserved4"),Granted.AriaCoins,int64(16));Test->TestEqual(TEXT("Total conserved24"),Granted.BenCoins+Granted.AriaCoins,int64(24));
            FString Saved,Error;Test->TestTrue(TEXT("Actual physical wrapper save"),Projection->SaveProjection(Saved,Error));Test->TestTrue(TEXT("Actual counter End lease"),Projection->RequestAction(ELivingTownLeaseAction::EndLease).bAccepted);Test->TestEqual(TEXT("End no refund"),Projection->GetLeaseView().BenCoins,int64(8));
            const FVector Position=Ben->GetActorLocation();Test->TestTrue(TEXT("Actual native save replay"),Projection->LoadProjection(Saved,Error));Test->TestEqual(TEXT("Replay restores exact lease digest"),Projection->GetLeaseView().JournalDigest,Granted.JournalDigest);Test->TestTrue(TEXT("Save replay never invents physical position"),Ben->GetActorLocation().Equals(Position,0));
            const auto Before=Projection->GetLeaseView();const FString Bad=Saved.Replace(TEXT("\"version\":\"1\""),TEXT("\"version\":\"unsupported\""));Test->TestTrue(TEXT("Actual negative envelope fixture changed"),Bad!=Saved);Test->TestFalse(TEXT("Unsupported outer save rejects atomically"),Projection->LoadProjection(Bad,Error));Test->TestEqual(TEXT("Rejected replay retains digest"),Projection->GetLeaseView().JournalDigest,Before.JournalDigest);Test->TestEqual(TEXT("Rejected replay retains clock"),Projection->GetLeaseView().Clock,Before.Clock);Test->TestTrue(TEXT("Rejected replay retains actual pose"),Ben->GetActorLocation().Equals(Position,0));
            Test->TestTrue(TEXT("Actual file slot atomic save"),Projection->SaveSlot(Error));Test->TestTrue(TEXT("Actual file slot replay"),Projection->LoadSlot(Error));bJourneyCompleted=true;Test->AddInfo(TEXT("Actual cafe walk/evaluated bilateral limb pose/collision/lease/end/conservation/ledger save completed. This does not qualify art, contact animation, FPS or the whole town roadmap."));return true;
        }
        return false;
    }
};
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafeActualWorldTest,"LivingTown.Native.CafeActualWalkLeaseJourney",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafeActualWorldTest::RunTest(const FString&)
{
    FLivingTownCafeBinding B;FString Error;
    if(!FLivingTownCafeBinding::ReadQualifiedFile(FPaths::Combine(FPaths::ProjectContentDir(),TEXT("LivingTown/CafeProjectionBinding.json")),B,Error)){AddError(TEXT("Actual world test requires real imported source/Ben/engine calibration; refusal is not a pass: ")+Error);return false;}
    FString RouteJson;TSharedPtr<FJsonObject> RouteObject;TArray<FVector> Points;
    if(!FFileHelper::LoadFileToString(RouteJson,*FPaths::Combine(FPaths::ProjectContentDir(),TEXT("LivingTown/CafeJourneyRoute.json")))||RouteJson.Len()>65536||!LivingTownCafeJournal::HasUniqueObjectKeys(RouteJson)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(RouteJson),RouteObject)||!RouteObject){AddError(TEXT("Actual journey needs a source-bound engine-qualified route fixture."));return false;}
    const TSet<FString> Fields={TEXT("format"),TEXT("version"),TEXT("status"),TEXT("physical_scene_sha256"),TEXT("physical_binding_sha256"),TEXT("capsule_radius_cm"),TEXT("capsule_half_height_cm"),TEXT("route_feet_cm")};
    if(RouteObject->Values.Num()!=Fields.Num()){AddError(TEXT("Unsupported route fixture fields"));return false;}for(const auto& Pair:RouteObject->Values)if(!Fields.Contains(FString(*Pair.Key))){AddError(TEXT("Unknown route fixture field"));return false;}
    auto Exact=[&](const TCHAR* K,const FString& Value){return RouteObject->HasTypedField<EJson::String>(K)&&RouteObject->GetStringField(K)==Value;};
    if(!Exact(TEXT("format"),TEXT("LivingTown.CafeJourneyRoute"))||!Exact(TEXT("version"),TEXT("1"))||!Exact(TEXT("status"),TEXT("UE_ROUTE_QUALIFIED"))||!Exact(TEXT("physical_scene_sha256"),B.PhysicalSceneSha256)||!Exact(TEXT("physical_binding_sha256"),B.BindingFileSha256)||!RouteObject->HasTypedField<EJson::Number>(TEXT("capsule_radius_cm"))||!RouteObject->HasTypedField<EJson::Number>(TEXT("capsule_half_height_cm"))||!FMath::IsNearlyEqual(RouteObject->GetNumberField(TEXT("capsule_radius_cm")),double(B.CapsuleRadiusCm),.01)||!FMath::IsNearlyEqual(RouteObject->GetNumberField(TEXT("capsule_half_height_cm")),double(B.CapsuleHalfHeightCm),.01)){AddError(TEXT("Route fixture physical provenance/capsule mismatch"));return false;}
    const TArray<TSharedPtr<FJsonValue>>* Values=nullptr;if(!RouteObject->TryGetArrayField(TEXT("route_feet_cm"),Values)||Values->Num()<2||Values->Num()>64){AddError(TEXT("Route needs2–64actualwaypoints"));return false;}
    for(const auto& V:*Values){if(V->Type!=EJson::Array||V->AsArray().Num()!=3){AddError(TEXT("Invalid route point"));return false;}double C[3];for(int I=0;I<3;++I){if(V->AsArray()[I]->Type!=EJson::Number){AddError(TEXT("Non-numeric route coordinate"));return false;}C[I]=V->AsArray()[I]->AsNumber();if(!FMath::IsFinite(C[I])||FMath::Abs(C[I])>10000000){AddError(TEXT("Nonfinite/unbounded route coordinate"));return false;}}Points.Add(FVector(C[0],C[1],C[2]));}
    if(!Points[0].Equals(B.SpawnFeetCm,.1)){AddError(TEXT("Route start differs from actual calibrated spawn"));return false;}
    if(!CheckMotionRefusalFixtures(this))return false;
    TArray<uint8> RouteBytes;FString RouteSha;
    if(!FFileHelper::LoadFileToArray(RouteBytes,*FPaths::Combine(FPaths::ProjectContentDir(),TEXT("LivingTown/CafeJourneyRoute.json")))||!LivingTownCafeJournal::Sha256(RouteBytes,RouteSha)){AddError(TEXT("Actual source route bytes cannot be hash-bound"));return false;}
    if(!AutomationOpenMap(TEXT("/Engine/Maps/Entry"),true)){AddError(TEXT("Actual PIE/game map did not open"));return false;}
    ADD_LATENT_AUTOMATION_COMMAND(FCafeActualJourney(this,Points,B,RouteSha));return true;
}
#endif
