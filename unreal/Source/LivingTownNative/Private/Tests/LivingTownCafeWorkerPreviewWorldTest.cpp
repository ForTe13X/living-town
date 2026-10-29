#include "LivingTownCafeCharacter.h"
#include "LivingTownCafeVenue.h"
#include "LivingTownCafeProjectionSubsystem.h"
#include "LivingTownRootCorrectedSingleNodeInstance.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformTime.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameViewportClient.h"
#include "UnrealClient.h"
#include "CoreGlobals.h"
#include "EngineUtils.h"
#include "Engine/DirectionalLight.h"
#include "Engine/SkyLight.h"
#include "Engine/PointLight.h"
#include "Engine/TextureCube.h"
#include "Engine/Scene.h"
#include "Components/LightComponent.h"
#include "Components/SkyLightComponent.h"
#include "Components/PointLightComponent.h"
#include "UObject/UnrealType.h"
#include "UObject/Package.h"
#include "Engine/SkeletalMesh.h"
#include "GameFramework/PlayerController.h"
#include "Camera/PlayerCameraManager.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Rendering/SkeletalMeshRenderData.h"
#include "Rendering/SkeletalMeshLODRenderData.h"
#include "Animation/AnimSequence.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Camera/CameraComponent.h"
#include "ReferenceSkeleton.h"
#include "Tests/AutomationCommon.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

namespace
{
const FName PreviewBones[]={TEXT("foot_l"),TEXT("foot_r"),TEXT("ball_l"),TEXT("ball_r"),TEXT("calf_l"),TEXT("calf_r"),TEXT("upperarm_l"),TEXT("upperarm_r"),TEXT("pelvis"),TEXT("head")};
TArray<TSharedPtr<FJsonValue>> PV(const FVector& V){return {MakeShared<FJsonValueNumber>(V.X),MakeShared<FJsonValueNumber>(V.Y),MakeShared<FJsonValueNumber>(V.Z)};}
TSharedRef<FJsonObject> PT(const FTransform& T){auto J=MakeShared<FJsonObject>();J->SetArrayField(TEXT("translation_cm"),PV(T.GetTranslation()));J->SetArrayField(TEXT("scale"),PV(T.GetScale3D()));const auto Q=T.GetRotation();J->SetArrayField(TEXT("rotation_xyzw"),{MakeShared<FJsonValueNumber>(Q.X),MakeShared<FJsonValueNumber>(Q.Y),MakeShared<FJsonValueNumber>(Q.Z),MakeShared<FJsonValueNumber>(Q.W)});return J;}
bool FileHash(const FString& P,FString& H){TArray<uint8> B;return FFileHelper::LoadFileToArray(B,*P)&&LivingTownCafeJournal::Sha256(B,H);}
TSharedRef<FJsonObject> HitJson(const FHitResult& H,bool Hit,const ALivingTownCafeVenue* Venue)
{
    auto J=MakeShared<FJsonObject>();J->SetBoolField(TEXT("hit"),Hit);J->SetBoolField(TEXT("blocking_hit"),H.bBlockingHit);J->SetArrayField(TEXT("impact_cm"),PV(H.ImpactPoint));J->SetArrayField(TEXT("normal"),PV(H.ImpactNormal));J->SetStringField(TEXT("actor"),H.GetActor()?H.GetActor()->GetPathName():TEXT("none"));J->SetStringField(TEXT("component"),H.GetComponent()?H.GetComponent()->GetPathName():TEXT("none"));J->SetBoolField(TEXT("bound_source_floor"),Venue&&Venue->IsFloorComponent(H.GetComponent()));J->SetBoolField(TEXT("bound_source_counter"),Venue&&Venue->IsCounterComponent(H.GetComponent()));return J;
}

class FWorker110DevelopmentPreview final:public IAutomationLatentCommand
{
    FAutomationTestBase* Test;FLivingTownCafeBinding Scene,Candidate;TArray<FVector> Route;FString SceneFileHash,RouteFileHash,DeliveryFileHash;
    TWeakObjectPtr<UWorld> World;TWeakObjectPtr<ALivingTownCafeVenue> Venue;TWeakObjectPtr<ALivingTownCafeCharacter> Worker;TWeakObjectPtr<APlayerController> Controller;
    TSharedRef<FJsonObject> Evidence=MakeShared<FJsonObject>();TArray<TSharedPtr<FJsonValue>> Samples;TArray<uint32> SoleIds[2];
    TWeakObjectPtr<ADirectionalLight> PreviewSun;TWeakObjectPtr<ASkyLight> PreviewSky;TWeakObjectPtr<APointLight> PreviewInterior;
    TArray<TSharedPtr<FJsonValue>> StartupObservations, FrameObservations;bool bNaturalPoseReady=false;uint8 PriorPossessedPolicy=0;
    FDelegateHandle RenderedHandle,ProcessedHandle;int32 WantedShot=-1,CapturedFrames=0;bool ShotScheduled[3]={false,false,false};FString PendingShotFile;TSharedPtr<FJsonObject> PendingShot;uint64 PendingDrawFrame=0;int32 PendingWidth=0,PendingHeight=0;bool SavedScreenMessages=true;
    double Deadline=FPlatformTime::Seconds()+120,StageStart=0,LastWorld=-1;int32 Stage=0,Waypoint=1,MovingSamples=0,SerialChanges=0;uint64 LastSerial=0;FVector FirstMoving=FVector::ZeroVector,LastActor=FVector::ZeroVector;double MaxDisplacement=0;bool Completed=false;int32 AnimationTimeChanges=0;double AnimationTimeTravel=0;float LastMovingTime=0;FTransform FirstMovingCS[10],FirstMovingLocal[10];double FootSpan[2]={0,0},CalfDegrees[2]={0,0},ArmDegrees[2]={0,0};
    bool Fail(const FString& Why){Test->AddError(Why);Evidence->SetStringField(TEXT("failure"),Why);return true;}
    void LightCensus(UWorld* W,const FString& Label)
    {
        auto J=MakeShared<FJsonObject>();TArray<TSharedPtr<FJsonValue>> Actors,Lights;
        for(TActorIterator<AActor> It(W);It;++It)
        {
            auto A=MakeShared<FJsonObject>();A->SetStringField(TEXT("actor"),It->GetPathName());A->SetStringField(TEXT("class"),It->GetClass()->GetPathName());Actors.Add(MakeShared<FJsonValueObject>(A));
            TArray<ULightComponentBase*> Components;It->GetComponents<ULightComponentBase>(Components);
            for(auto* C:Components)
            {
                auto L=MakeShared<FJsonObject>();L->SetStringField(TEXT("component"),C->GetPathName());L->SetStringField(TEXT("class"),C->GetClass()->GetPathName());L->SetBoolField(TEXT("registered"),C->IsRegistered());L->SetBoolField(TEXT("visible"),C->IsVisible());L->SetBoolField(TEXT("affects_world"),C->bAffectsWorld);L->SetNumberField(TEXT("intensity"),C->Intensity);L->SetNumberField(TEXT("mobility"),int32(C->Mobility));L->SetObjectField(TEXT("world_transform"),PT(C->GetComponentTransform()));auto Properties=MakeShared<FJsonObject>();
                for(TFieldIterator<FProperty> P(C->GetClass());P;++P)for(int32 I=0;I<P->ArrayDim;++I){FString Value;P->ExportText_InContainer(I,Value,C,nullptr,C,PPF_None);Properties->SetStringField(P->GetName()+FString::Printf(TEXT("[%d]"),I),Value);}
                L->SetObjectField(TEXT("all_reflected_component_properties"),Properties);Lights.Add(MakeShared<FJsonValueObject>(L));
            }
        }
        J->SetArrayField(TEXT("actors"),Actors);J->SetArrayField(TEXT("lights"),Lights);if(auto* GV=W->GetGameViewport()){auto F=MakeShared<FJsonObject>();F->SetBoolField(TEXT("world_rendering_disabled"),GV->bDisableWorldRendering);F->SetBoolField(TEXT("game_rendering_enabled"),FViewport::IsGameRenderingEnabled());F->SetBoolField(TEXT("Rendering"),GV->EngineShowFlags.Rendering!=0);F->SetBoolField(TEXT("Lighting"),GV->EngineShowFlags.Lighting!=0);F->SetBoolField(TEXT("Materials"),GV->EngineShowFlags.Materials!=0);F->SetBoolField(TEXT("SkyLighting"),GV->EngineShowFlags.SkyLighting!=0);F->SetBoolField(TEXT("Tonemapper"),GV->EngineShowFlags.Tonemapper!=0);F->SetBoolField(TEXT("PostProcessing"),GV->EngineShowFlags.PostProcessing!=0);J->SetObjectField(TEXT("actual_game_viewport_flags"),F);}Evidence->SetObjectField(Label,J);
    }
    bool SetupControlledPreviewLighting(UWorld* W,ALivingTownCafeCharacter* Ben)
    {
        LightCensus(W,TEXT("world_before_controlled_preview_lighting"));
        auto* Sun=W->SpawnActor<ADirectionalLight>(FVector(0,0,1000),FRotator(-45,-35,0));PreviewSun=Sun;
        auto* Sky=W->SpawnActor<ASkyLight>();PreviewSky=Sky;FVector Center=FVector::ZeroVector;for(const FVector& P:Route)Center+=P;Center/=Route.Num();Center.Z=Route[0].Z+220;
        auto* Interior=W->SpawnActor<APointLight>(Center,FRotator::ZeroRotator);PreviewInterior=Interior;
        auto* Cube=LoadObject<UTextureCube>(nullptr,TEXT("/Engine/EngineResources/GrayTextureCube.GrayTextureCube"));auto* Cam=Ben->FindComponentByClass<UCameraComponent>();
        if(!Sun||!Sky||!Interior||!Cube||!Cam)return !Fail(TEXT("Owned controlled-preview light/camera resources unavailable"));
        auto* Key=Sun->GetLightComponent();Key->SetMobility(EComponentMobility::Movable);Key->SetIntensity(3.1415927f);Key->SetLightColor(FLinearColor(1.f,.96f,.90f),false);Key->SetCastShadows(true);
        auto* Fill=Sky->GetLightComponent();Fill->SetMobility(EComponentMobility::Movable);Fill->SourceType=SLS_SpecifiedCubemap;Fill->SetRealTimeCapture(false);Fill->SetCubemap(Cube);Fill->SetIntensity(1.f);
        auto* Point=Interior->PointLightComponent.Get();Point->SetMobility(EComponentMobility::Movable);Point->SetIntensityUnits(ELightUnits::Lumens);Point->SetIntensity(1200.f);Point->SetAttenuationRadius(800.f);Point->SetSourceRadius(25.f);Point->SetLightColor(FLinearColor(1.f,.96f,.90f),false);Point->SetCastShadows(true);
        float Compensation=-2.f;FParse::Value(FCommandLine::Get(),TEXT("LivingTownPreviewExposureCompensation="),Compensation);if(!FMath::IsFinite(Compensation)||Compensation< -8.f||Compensation>4.f)return !Fail(TEXT("Preview exposure compensation must be finite and between -8 and 4 stops"));
        Cam->PostProcessBlendWeight=1.f;auto& Exposure=Cam->PostProcessSettings;Exposure.bOverride_AutoExposureMethod=true;Exposure.AutoExposureMethod=EAutoExposureMethod::AEM_Manual;Exposure.bOverride_AutoExposureApplyPhysicalCameraExposure=true;Exposure.AutoExposureApplyPhysicalCameraExposure=false;Exposure.bOverride_AutoExposureBias=true;Exposure.AutoExposureBias=Compensation;
        auto Policy=MakeShared<FJsonObject>();Policy->SetStringField(TEXT("status"),TEXT("CONTROLLED_PREVIEW_LIGHTING_NOT_FINAL_GAME_LIGHTING"));Policy->SetStringField(TEXT("sky_cubemap"),Cube->GetPathName());Policy->SetArrayField(TEXT("interior_point_location_cm"),PV(Center));Policy->SetNumberField(TEXT("interior_lumens"),Point->Intensity);Policy->SetNumberField(TEXT("interior_attenuation_radius_cm"),Point->AttenuationRadius);Policy->SetNumberField(TEXT("manual_exposure_compensation_stops"),Exposure.AutoExposureBias);Policy->SetNumberField(TEXT("manual_exposure_method"),int32(Exposure.AutoExposureMethod));Policy->SetNumberField(TEXT("camera_post_process_blend_weight"),Cam->PostProcessBlendWeight);Policy->SetNumberField(TEXT("physical_camera_EV100_used_when_disabled"),0);Policy->SetBoolField(TEXT("physical_camera_exposure"),Exposure.AutoExposureApplyPhysicalCameraExposure);Policy->SetBoolField(TEXT("camera_location_rotation_FOV_or_motion_changed"),false);Evidence->SetObjectField(TEXT("controlled_preview_lighting"),Policy);LightCensus(W,TEXT("world_after_controlled_preview_lighting"));return true;
    }
    void CleanupControlledPreviewLighting()
    {
        if(PreviewInterior.IsValid())PreviewInterior->Destroy();if(PreviewSky.IsValid())PreviewSky->Destroy();if(PreviewSun.IsValid())PreviewSun->Destroy();
    }
    void CleanupFrameObservers()
    {
        UGameViewportClient::OnViewportRendered().Remove(RenderedHandle);FScreenshotRequest::OnScreenshotRequestProcessed().Remove(ProcessedHandle);
        if(!PendingShotFile.IsEmpty()&&FScreenshotRequest::IsScreenshotRequested()&&FScreenshotRequest::GetFilename()==PendingShotFile){FScreenshotRequest::Reset();GAreScreenMessagesEnabled=SavedScreenMessages;}
        if(PendingShot){PendingShot->SetStringField(TEXT("status"),TEXT("OWNED_NATIVE_FRAME_REQUEST_CANCELLED_ON_TEST_END"));PendingShot->SetStringField(TEXT("file"),PendingShotFile);FrameObservations.Add(MakeShared<FJsonValueObject>(PendingShot.ToSharedRef()));}
        PendingShotFile.Reset();PendingShot.Reset();
    }
    void FrameProcessed()
    {
        if(PendingShotFile.IsEmpty()||!PendingShot)return;
        PendingShot->SetStringField(TEXT("processed_engine_frame"),FString::Printf(TEXT("%llu"),(unsigned long long)GFrameCounter));
        TArray<uint8> Bytes;FString Hash;bool Valid=FFileHelper::LoadFileToArray(Bytes,*PendingShotFile)&&Bytes.Num()>=24&&Bytes.Num()<=64*1024*1024;
        uint32 Width=0,Height=0;if(Valid){Valid=FMemory::Memcmp(Bytes.GetData(),"\x89PNG\r\n\x1a\n",8)==0&&FMemory::Memcmp(Bytes.GetData()+12,"IHDR",4)==0;for(int32 I=0;I<4;++I){Width=(Width<<8)|Bytes[16+I];Height=(Height<<8)|Bytes[20+I];}}
        Valid=Valid&&Width==uint32(PendingWidth)&&Height==uint32(PendingHeight)&&GFrameCounter==PendingDrawFrame&&LivingTownCafeJournal::Sha256(Bytes,Hash);
        PendingShot->SetStringField(TEXT("status"),Valid?TEXT("NATIVE_GAME_VIEWPORT_GPU_PNG_REVIEW_REQUIRED"):TEXT("NATIVE_FRAME_UNAVAILABLE_OR_IDENTITY_MISMATCH_RETAINED"));PendingShot->SetStringField(TEXT("file"),PendingShotFile);PendingShot->SetNumberField(TEXT("bytes"),Bytes.Num());PendingShot->SetStringField(TEXT("sha256"),Hash);PendingShot->SetNumberField(TEXT("PNG_width"),Width);PendingShot->SetNumberField(TEXT("PNG_height"),Height);PendingShot->SetBoolField(TEXT("camera_contact_art_or_FPS_accepted"),false);FrameObservations.Add(MakeShared<FJsonValueObject>(PendingShot.ToSharedRef()));if(Valid)++CapturedFrames;PendingShot.Reset();PendingShotFile.Reset();
    }
    void ViewportRendered(FViewport* V)
    {
        if(WantedShot<0||!PendingShotFile.IsEmpty()||!World.IsValid()||!Controller.IsValid()||!Worker.IsValid()||!V)return;
        UWorld* W=World.Get();auto* PC=Controller.Get();auto* GV=W->GetGameViewport();if(!GV||GV->GetWorld()!=W||V->GetClient()!=GV)return;
        const int32 Label=WantedShot;WantedShot=-1;auto J=MakeShared<FJsonObject>();const TCHAR* Labels[]={TEXT("idle"),TEXT("walk"),TEXT("stopped")};J->SetStringField(TEXT("label"),Labels[Label]);J->SetNumberField(TEXT("stage_at_draw"),Stage);J->SetNumberField(TEXT("world_seconds_at_draw"),W->GetTimeSeconds());J->SetStringField(TEXT("draw_engine_frame"),FString::Printf(TEXT("%llu"),(unsigned long long)GFrameCounter));J->SetStringField(TEXT("world"),W->GetPathName());J->SetStringField(TEXT("viewport_client"),GV->GetPathName());J->SetStringField(TEXT("viewport_identity"),FString::Printf(TEXT("%p"),static_cast<void*>(V)));J->SetArrayField(TEXT("actor_velocity_at_draw_cm_s"),PV(Worker->GetVelocity()));J->SetNumberField(TEXT("nearest_natural_sample_index"),Samples.Num()-1);
        const FIntPoint Size=V->GetRenderTargetTextureSizeXY();J->SetNumberField(TEXT("render_target_width"),Size.X);J->SetNumberField(TEXT("render_target_height"),Size.Y);if(PC->PlayerCameraManager){J->SetArrayField(TEXT("camera_cm_at_draw"),PV(PC->PlayerCameraManager->GetCameraLocation()));const FRotator R=PC->PlayerCameraManager->GetCameraRotation();J->SetArrayField(TEXT("camera_pitch_yaw_roll_at_draw"),PV(FVector(R.Pitch,R.Yaw,R.Roll)));J->SetNumberField(TEXT("camera_fov_at_draw"),PC->PlayerCameraManager->GetFOVAngle());}
        const bool Phase=Stage==Label&&PC->GetPawn()==Worker.Get()&&PC->GetViewTarget()==Worker.Get()&&(Label==1?Worker->GetVelocity().Size2D()>33:Worker->GetVelocity().Size2D()<1);
        if(!Phase||Size.X<=0||Size.Y<=0||Size.X>4096||Size.Y>2160||FScreenshotRequest::IsScreenshotRequested()||GIsHighResScreenshot||GIsDumpingMovie||UGameViewportClient::OnScreenshotCaptured().IsBound()||UGameViewportClient::OnHDRScreenshotCaptured().IsBound())
        {J->SetStringField(TEXT("status"),TEXT("NATIVE_FRAME_PHASE_VIEWPORT_OR_REQUEST_OWNERSHIP_UNAVAILABLE"));FrameObservations.Add(MakeShared<FJsonValueObject>(J));return;}
        const FString Folder=FPaths::ProjectSavedDir()/TEXT("CafeWorker110Preview/Frames");IFileManager::Get().MakeDirectory(*Folder,true);const FString Path=Folder/(FString(Labels[Label])+TEXT(".png"));if(IFileManager::Get().FileExists(*Path)){J->SetStringField(TEXT("status"),TEXT("NATIVE_FRAME_REFUSED_EXISTING_FILE"));FrameObservations.Add(MakeShared<FJsonValueObject>(J));return;}
        PendingShot=J;PendingShotFile=Path;PendingDrawFrame=GFrameCounter;PendingWidth=Size.X;PendingHeight=Size.Y;SavedScreenMessages=GAreScreenMessagesEnabled;
        // This callback runs immediately before this exact viewport's ProcessScreenShots.
        // Engine ReadPixels/SaveImage writes the real GPU target, without a desktop window.
        FScreenshotRequest::RequestScreenshot(Path,false,false,false,FIntRect(),true);
    }
    bool Start(UWorld* W,APlayerController* PC)
    {
        if(UWorld::RemovePIEPrefix(W->GetOutermost()->GetName())!=TEXT("/Engine/Maps/Entry"))return !Fail(TEXT("Exact owned Entry PIE map required"));
        if(!W->GetAuthGameMode()||W->GetAuthGameMode()->GetClass()!=AGameModeBase::StaticClass()||W->GetNetMode()!=NM_Standalone)return !Fail(TEXT("Development preview requires exact GameModeBase, not the production cafe mode"));
        if(auto* P=W->GetSubsystem<ULivingTownCafeProjectionSubsystem>())if(P->IsReady()||P->IsScenePrepared())return !Fail(TEXT("Production projection must remain unprepared in this separate preview"));
        if(PC->GetPawn()){APawn* Old=PC->GetPawn();PC->UnPossess();Old->Destroy();}
        auto* V=W->SpawnActor<ALivingTownCafeVenue>();Venue=V;FString Why;if(!V||!V->BuildQualified(Scene,Why))return !Fail(TEXT("Existing exact source geometry/collision refused: ")+Why);Venue=V;
        FCollisionQueryParams Q(SCENE_QUERY_STAT(Worker110PreviewSafety),true);
        const auto Shape=FCollisionShape::MakeCapsule(28,95);TArray<TSharedPtr<FJsonValue>> Checks;
        for(int32 I=0;I<Route.Num();++I)
        {
            FHitResult Floor;const bool FloorOK=V->FloorAt(Route[I],Floor);const FVector Center=Route[I]+FVector(0,0,95);const bool Overlap=W->OverlapBlockingTestByChannel(Center,FQuat::Identity,ECC_Pawn,Shape,Q);auto J=HitJson(Floor,FloorOK,V);J->SetArrayField(TEXT("route_feet_cm"),PV(Route[I]));J->SetBoolField(TEXT("initial_capsule_overlap"),Overlap);
            if(I){FHitResult Sweep;const bool Block=W->SweepSingleByChannel(Sweep,Route[I-1]+FVector(0,0,95),Center,FQuat::Identity,ECC_Pawn,Shape,Q);J->SetObjectField(TEXT("from_previous_sweep"),HitJson(Sweep,Block,V));Checks.Add(MakeShared<FJsonValueObject>(J));Evidence->SetArrayField(TEXT("actual_pre_possession_safety"),Checks);if(Block)return !Fail(TEXT("Actual candidate capsule route sweep blocked; no possession"));}
            else Checks.Add(MakeShared<FJsonValueObject>(J));Evidence->SetArrayField(TEXT("actual_pre_possession_safety"),Checks);if(!FloorOK||Overlap)return !Fail(TEXT("Actual source floor or candidate capsule placement refused before possession"));
        }
        const FTransform Spawn(Candidate.SpawnRotation,Candidate.SpawnFeetCm+FVector(0,0,95));auto* Ben=W->SpawnActorDeferred<ALivingTownCafeCharacter>(ALivingTownCafeCharacter::StaticClass(),Spawn,nullptr,nullptr,ESpawnActorCollisionHandlingMethod::AlwaysSpawn);
        if(!Ben||!Ben->ConfigureQualifiedBen(Candidate,Why)){if(Ben)Ben->Destroy();return !Fail(TEXT("Development visual/player configuration refused; no lifecycle workaround: ")+Why);}
        Ben->FinishSpawning(Spawn);Q.AddIgnoredActor(Ben);if(W->OverlapBlockingTestByChannel(Ben->GetActorLocation(),FQuat::Identity,ECC_Pawn,Shape,Q)){Ben->Destroy();return !Fail(TEXT("Configured source character capsule overlaps actual cafe"));}
        Worker=Ben;Controller=PC;World=W;if(!SetupControlledPreviewLighting(W,Ben))return false;PriorPossessedPolicy=static_cast<uint8>(Ben->GetMesh()->VisibilityBasedAnimTickOption);Test->TestTrue(TEXT("Unpossessed new-worker retains inherited animation update policy"),Ben->GetMesh()->VisibilityBasedAnimTickOption==EVisibilityBasedAnimTickOption::AlwaysTickPose);Evidence->SetNumberField(TEXT("before_possession_animation_tick_policy"),PriorPossessedPolicy);PC->Possess(Ben);if(Ben->GetMesh()->VisibilityBasedAnimTickOption!=EVisibilityBasedAnimTickOption::AlwaysTickPoseAndRefreshBones)return !Fail(TEXT("Active new-worker production bone-refresh policy missing"));PC->SetViewTarget(Ben);PC->SetControlRotation(Candidate.SpawnRotation);Worker=Ben;Controller=PC;World=W;StageStart=W->GetTimeSeconds();RenderedHandle=UGameViewportClient::OnViewportRendered().AddRaw(this,&FWorker110DevelopmentPreview::ViewportRendered);ProcessedHandle=FScreenshotRequest::OnScreenshotRequestProcessed().AddRaw(this,&FWorker110DevelopmentPreview::FrameProcessed);return true;
    }
    bool Capture(UWorld* W,APlayerController* PC,ALivingTownCafeCharacter* Ben)
    {
        const double Time=W->GetTimeSeconds();if(Time-LastWorld<.05)return true;if(Samples.Num()>=256)return !Fail(TEXT("Finite development preview sample budget exceeded"));
        auto* Mesh=Ben->GetMesh();auto* Anim=Mesh?Cast<ULivingTownRootCorrectedSingleNodeInstance>(Mesh->GetAnimInstance()):nullptr;FLivingTownRootCorrectionDiagnostic D;
        if(!Mesh||!Mesh->IsVisible()||!Mesh->IsComponentTickEnabled()||W->IsPaused()||PC->GetViewTarget()!=Ben||Ben->GetController()!=PC||!Mesh->GetRelativeTransform().Equals(Candidate.MeshRelativeTransform,.001)||!Anim||Mesh->GetSingleNodeInstance()!=Anim||!Anim->CopyRootCorrectionDiagnostic(D))return !Fail(TEXT("Actual custom player/finished worker diagnostic unavailable"));
        auto J=MakeShared<FJsonObject>();J->SetNumberField(TEXT("stage"),Stage);J->SetNumberField(TEXT("world_seconds"),Time);J->SetNumberField(TEXT("world_delta_seconds"),W->GetDeltaSeconds());J->SetStringField(TEXT("engine_frame"),FString::Printf(TEXT("%llu"),(unsigned long long)GFrameCounter));J->SetStringField(TEXT("evaluation_serial"),FString::Printf(TEXT("%llu"),(unsigned long long)D.EvaluationSerial));J->SetStringField(TEXT("root_state"),Anim->StateName(D.State));J->SetNumberField(TEXT("actual_idle_weight"),D.IdleWeight);J->SetArrayField(TEXT("applied_root_delta_cm"),PV(D.AppliedDelta));J->SetBoolField(TEXT("pose_capture_disabled"),!D.bPoseCaptured);J->SetNumberField(TEXT("natural_normalized_animation_time"),Anim->GetCurrentTime());J->SetNumberField(TEXT("play_rate"),Anim->GetPlayRate());J->SetObjectField(TEXT("actor"),PT(Ben->GetActorTransform()));J->SetObjectField(TEXT("mesh_relative"),PT(Mesh->GetRelativeTransform()));J->SetArrayField(TEXT("actor_velocity_cm_s"),PV(Ben->GetVelocity()));J->SetBoolField(TEXT("moving_on_actual_floor"),Ben->GetCharacterMovement()->IsMovingOnGround());J->SetNumberField(TEXT("bone_transform_revision"),Mesh->GetBoneTransformRevisionNumber());J->SetBoolField(TEXT("existing_worker_completion_waited_without_animation_tick"),true);J->SetStringField(TEXT("world"),W->GetPathName());J->SetStringField(TEXT("player"),Ben->GetPathName());J->SetNumberField(TEXT("visibility_based_animation_tick_option"),int32(Mesh->VisibilityBasedAnimTickOption));J->SetBoolField(TEXT("update_rate_optimization_enabled"),Mesh->bEnableUpdateRateOptimizations);Evidence->SetObjectField(TEXT("last_observation_including_failure"),J);if(LastWorld>=0&&Time>LastWorld&&FVector::Dist2D(Ben->GetActorLocation(),LastActor)>110*(Time-LastWorld)+2)return !Fail(TEXT("Natural actor displacement exceeds source speed/world delta; teleport cannot pass"));
        if(Mesh->VisibilityBasedAnimTickOption!=EVisibilityBasedAnimTickOption::AlwaysTickPoseAndRefreshBones)return !Fail(TEXT("Possessed worker lost production bone-refresh policy"));
        if(!bNaturalPoseReady&&((D.State==ELivingTownRootCorrectionState::NotEvaluated&&D.EvaluationSerial==0)||(D.State==ELivingTownRootCorrectionState::Applied&&D.EvaluationSerial>0&&Mesh->GetBoneTransformRevisionNumber()<=1)))
        {StartupObservations.Add(MakeShared<FJsonValueObject>(J));Evidence->SetArrayField(TEXT("initial_natural_readiness_observations"),StartupObservations);if(Time-StageStart>5||StartupObservations.Num()>=120)return !Fail(TEXT("Natural initial evaluation readiness timed out; observations retained"));return true;}
        if(D.State!=ELivingTownRootCorrectionState::Applied||!D.bCorrectionEnabled||!D.bWeightObserved||D.bPoseCaptured||D.bMirrorTablePresent||D.Asset!=Anim->GetCurrentAsset()||D.Samples<1||D.Samples>2||!D.RequestedDelta.Equals(Candidate.IdleRootDeltaCm,1e-9)||!D.AppliedDelta.Equals(D.RequestedDelta*D.IdleWeight,1e-9)||!Anim->IsPlaying()||Anim->GetPlayRate()!=1.f)return !Fail(TEXT("Actual production player/cache/root policy is not the declared candidate"));
        if(!bNaturalPoseReady){bNaturalPoseReady=true;Evidence->SetNumberField(TEXT("natural_pose_ready_world_seconds"),Time);Evidence->SetNumberField(TEXT("natural_pose_ready_engine_frame"),double(GFrameCounter));StageStart=Time;}
        TArray<TSharedPtr<FJsonValue>> Cache;double Weight=0,Idle=0;
        for(int32 I=0;I<D.Samples;++I){const auto& S=D.SampleRows[I];if(!S.Animation||!FMath::IsFinite(S.Weight)||!FMath::IsFinite(S.Time)||S.Weight<=0||(S.Animation->GetPathName()!=Candidate.IdleAnimationPath&&S.Animation->GetPathName()!=Candidate.WalkAnimationPath))return !Fail(TEXT("Actual cache row refused"));auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("animation"),S.Animation->GetPathName());R->SetNumberField(TEXT("index"),S.SampleIndex);R->SetNumberField(TEXT("weight"),S.Weight);R->SetNumberField(TEXT("raw_weight"),S.RawWeight);R->SetNumberField(TEXT("time_seconds"),S.Time);R->SetNumberField(TEXT("previous_time_seconds"),S.PreviousTime);Cache.Add(MakeShared<FJsonValueObject>(R));Weight+=S.Weight;if(S.Animation->GetPathName()==Candidate.IdleAnimationPath)Idle+=S.Weight;}
        J->SetArrayField(TEXT("actual_cache"),Cache);if(!FMath::IsNearlyEqual(Weight,1.,1e-5)||!FMath::IsNearlyEqual(Idle,D.IdleWeight,1e-9))return !Fail(TEXT("Actual weighted cache operands disagree"));
        const bool MovingNow=Stage==1&&Ben->GetCharacterMovement()->IsMovingOnGround()&&Ben->GetVelocity().Size2D()>33;int32 BoneNumber=0;FTransform ObservedCS[10],ObservedLocal[10];const auto& Pose=Mesh->GetComponentSpaceTransforms();const auto& Ref=Mesh->GetSkeletalMeshAsset()->GetRefSkeleton();auto Bones=MakeShared<FJsonObject>();
        for(const FName Name:PreviewBones){const int32 I=Mesh->GetBoneIndex(Name);if(!Pose.IsValidIndex(I))return !Fail(TEXT("New-family natural bone absent: ")+Name.ToString());const int32 Parent=Ref.GetParentIndex(I);if(Parent!=INDEX_NONE&&!Pose.IsValidIndex(Parent))return !Fail(TEXT("Natural bone parent absent"));if(Pose[I].ContainsNaN())return !Fail(TEXT("Nonfinite natural pose"));auto R=MakeShared<FJsonObject>();R->SetObjectField(TEXT("component"),PT(Pose[I]));R->SetObjectField(TEXT("world"),PT(Pose[I]*Mesh->GetComponentTransform()));R->SetObjectField(TEXT("parent_relative"),PT(Parent==INDEX_NONE?Pose[I]:Pose[I].GetRelativeTransform(Pose[Parent])));Bones->SetObjectField(Name.ToString(),R);ObservedCS[BoneNumber]=Pose[I];ObservedLocal[BoneNumber]=Parent==INDEX_NONE?Pose[I]:Pose[I].GetRelativeTransform(Pose[Parent]);if(MovingNow&&!MovingSamples){FirstMovingCS[BoneNumber]=ObservedCS[BoneNumber];FirstMovingLocal[BoneNumber]=ObservedLocal[BoneNumber];}++BoneNumber;}J->SetObjectField(TEXT("naturally_evaluated_bones"),Bones);if(MovingNow)for(int32 I=0;I<2;++I){FootSpan[I]=FMath::Max(FootSpan[I],FVector::Dist(ObservedCS[I].GetTranslation()-ObservedCS[8].GetTranslation(),FirstMovingCS[I].GetTranslation()-FirstMovingCS[8].GetTranslation()));CalfDegrees[I]=FMath::Max(CalfDegrees[I],FMath::RadiansToDegrees(ObservedLocal[I+4].GetRotation().AngularDistance(FirstMovingLocal[I+4].GetRotation())));ArmDegrees[I]=FMath::Max(ArmDegrees[I],FMath::RadiansToDegrees(ObservedLocal[I+6].GetRotation().AngularDistance(FirstMovingLocal[I+6].GetRotation())));}
        const auto Palm=Mesh->GetSocketTransform(TEXT("UsePalm_R"),RTS_World);J->SetObjectField(TEXT("palm_world"),PT(Palm));J->SetArrayField(TEXT("counter_point_cm"),PV(Scene.CounterUsePointCm));J->SetNumberField(TEXT("palm_to_counter_cm"),FVector::Dist(Palm.GetTranslation(),Scene.CounterUsePointCm));FCollisionQueryParams Q(SCENE_QUERY_STAT(Worker110PreviewObservations),true,Ben);FHitResult Hand;const bool HandHit=W->LineTraceSingleByChannel(Hand,Palm.GetTranslation(),Scene.CounterUsePointCm,ECC_Visibility,Q);J->SetObjectField(TEXT("palm_counter_first_hit"),HitJson(Hand,HandHit,Venue.Get()));J->SetObjectField(TEXT("capsule_current_floor"),HitJson(Ben->GetCharacterMovement()->CurrentFloor.HitResult,Ben->GetCharacterMovement()->CurrentFloor.IsWalkableFloor(),Venue.Get()));
        const auto* Render=Mesh->GetSkeletalMeshAsset()->GetResourceForRendering();const auto* Skin=Mesh->GetSkinWeightBuffer(0);if(!Render||Render->LODRenderData.Num()!=1||!Skin||!Skin->GetDataVertexBuffer()||!Skin->GetDataVertexBuffer()->GetWeightData())return !Fail(TEXT("Natural source render/skin data unavailable"));const auto& L=Render->LODRenderData[0];if(L.GetNumVertices()!=10707||L.RenderSections.Num()!=1||!L.StaticVertexBuffers.PositionVertexBuffer.GetVertexData())return !Fail(TEXT("Exact source mesh LOD required"));
        if(SoleIds[0].IsEmpty())for(uint32 V=0;V<10707;++V){uint32 Sum=0,Side[2]={0,0};for(uint32 K=0;K<Skin->GetMaxBoneInfluences();++K){const uint32 Local=Skin->GetBoneIndex(V,K),WeightValue=Skin->GetBoneWeight(V,K);if(WeightValue==0)continue;if(!L.RenderSections[0].BoneMap.IsValidIndex(Local))return !Fail(TEXT("Actual source influence map invalid"));const FName N=Ref.GetBoneName(L.RenderSections[0].BoneMap[Local]);Sum+=WeightValue;if(N==TEXT("foot_l")||N==TEXT("ball_l"))Side[0]+=WeightValue;if(N==TEXT("foot_r")||N==TEXT("ball_r"))Side[1]+=WeightValue;}for(int32 SideIndex=0;SideIndex<2;++SideIndex)if(Sum&&Side[SideIndex]*2>Sum)SoleIds[SideIndex].Add(V);}
        if(SoleIds[0].Num()!=532||SoleIds[1].Num()!=571)return !Fail(TEXT("Original majority-foot influence groups changed"));
        TArray<FMatrix44f> Matrices;TArray<FVector3f> Positions;Mesh->GetCurrentRefToLocalMatrices(Matrices,0);USkinnedMeshComponent::ComputeSkinnedPositions(Mesh,Positions,Matrices,L,*Skin);if(Positions.Num()!=10707)return !Fail(TEXT("Natural-pose read-only skin result incomplete"));FBox Body(ForceInit);for(const auto& P:Positions){if(P.ContainsNaN())return !Fail(TEXT("Nonfinite naturally evaluated render position"));Body+=Mesh->GetComponentTransform().TransformPosition(FVector(P));}
        for(int32 Side=0;Side<2;++Side){TArray<TSharedPtr<FJsonValue>> Ids,Points;FVector Lowest=FVector::ZeroVector;uint32 LowestId=0;bool First=true;for(uint32 I:SoleIds[Side]){const FVector P=Mesh->GetComponentTransform().TransformPosition(FVector(Positions[I]));if(P.ContainsNaN())return !Fail(TEXT("Nonfinite natural skin point"));Ids.Add(MakeShared<FJsonValueNumber>(I));Points.Add(MakeShared<FJsonValueArray>(PV(P)));if(First||P.Z<Lowest.Z){Lowest=P;LowestId=I;First=false;}}const FString Label=Side==0?TEXT("left"):TEXT("right");Evidence->SetArrayField(Label+TEXT("_majority_foot_vertex_ids"),Ids);J->SetArrayField(Label+TEXT("_foot_surface_world_cm"),Points);FHitResult Hit;const bool DidHit=W->LineTraceSingleByChannel(Hit,Lowest+FVector(0,0,40),Lowest-FVector(0,0,40),ECC_Visibility,Q);auto Floor=HitJson(Hit,DidHit,Venue.Get());Floor->SetArrayField(TEXT("minimum_world_z_vertex_cm"),PV(Lowest));Floor->SetNumberField(TEXT("minimum_world_z_vertex_id"),LowestId);if(DidHit)Floor->SetNumberField(TEXT("signed_clearance_to_first_hit_plane_cm"),FVector::DotProduct(Lowest-Hit.ImpactPoint,Hit.ImpactNormal));Floor->SetBoolField(TEXT("foot_locking_or_complete_contact_qualified"),false);J->SetObjectField(Label+TEXT("_minimum_surface_floor_ray"),Floor);}
        int32 Width=0,Height=0;PC->GetViewportSize(Width,Height);TArray<TSharedPtr<FJsonValue>> Corners;bool Coverage=Width>0&&Height>0;for(int32 Mask=0;Mask<8;++Mask){const FVector Point((Mask&1)?Body.Max.X:Body.Min.X,(Mask&2)?Body.Max.Y:Body.Min.Y,(Mask&4)?Body.Max.Z:Body.Min.Z);FVector2D Pixel=FVector2D::ZeroVector;const bool Projected=PC->ProjectWorldLocationToScreen(Point,Pixel,false);auto P=MakeShared<FJsonObject>();P->SetArrayField(TEXT("world_cm"),PV(Point));P->SetBoolField(TEXT("projected"),Projected);P->SetArrayField(TEXT("pixel"),{MakeShared<FJsonValueNumber>(Pixel.X),MakeShared<FJsonValueNumber>(Pixel.Y)});Corners.Add(MakeShared<FJsonValueObject>(P));Coverage&=Projected&&Pixel.X>=Width*.03&&Pixel.X<=Width*.97&&Pixel.Y>=Height*.03&&Pixel.Y<=Height*.97;}J->SetNumberField(TEXT("viewport_width"),Width);J->SetNumberField(TEXT("viewport_height"),Height);J->SetArrayField(TEXT("render_body_AABB_projected_corners"),Corners);J->SetBoolField(TEXT("conservative_full_body_camera_coverage"),Coverage);
        if(PC->PlayerCameraManager){J->SetArrayField(TEXT("camera_cm"),PV(PC->PlayerCameraManager->GetCameraLocation()));J->SetNumberField(TEXT("camera_fov"),PC->PlayerCameraManager->GetFOVAngle());const FRotator Rot=PC->PlayerCameraManager->GetCameraRotation();J->SetArrayField(TEXT("camera_pitch_yaw_roll"),PV(FVector(Rot.Pitch,Rot.Yaw,Rot.Roll)));}
        if(D.EvaluationSerial!=LastSerial&&LastSerial)++SerialChanges;LastSerial=D.EvaluationSerial;if(MovingNow){if(!MovingSamples)FirstMoving=Ben->GetActorLocation();else{const double Change=FMath::Abs(double(Anim->GetCurrentTime())-LastMovingTime);if(Change>1e-4){++AnimationTimeChanges;AnimationTimeTravel+=Change;}}LastMovingTime=Anim->GetCurrentTime();++MovingSamples;MaxDisplacement=FMath::Max(MaxDisplacement,FVector::Dist2D(FirstMoving,Ben->GetActorLocation()));}Samples.Add(MakeShared<FJsonValueObject>(J));LastWorld=Time;LastActor=Ben->GetActorLocation();if(WantedShot<0&&PendingShotFile.IsEmpty()&&!ShotScheduled[Stage]&&((Stage==0&&Time-StageStart>=.5)||(Stage==1&&MovingSamples>=3&&MovingNow)||(Stage==2&&Time-StageStart>=.5))){WantedShot=Stage;ShotScheduled[Stage]=true;}return true;
    }
    void Persist()
    {
        Evidence->SetArrayField(TEXT("initial_natural_readiness_observations"),StartupObservations);Evidence->SetArrayField(TEXT("native_GPU_frames"),FrameObservations);Evidence->SetNumberField(TEXT("complete_native_GPU_frames"),CapturedFrames);
        FString EndScene,EndRoute,EndDelivery;const FString Inputs=FPaths::ProjectContentDir()/TEXT("LivingTown");const bool Stable=FileHash(Inputs/TEXT("CafePreviewSceneBinding.json"),EndScene)&&FileHash(Inputs/TEXT("CafePreviewSceneRoute.json"),EndRoute)&&FileHash(Inputs/TEXT("CafeWorker110DeliveryReceipt.json"),EndDelivery)&&EndScene==SceneFileHash&&EndRoute==RouteFileHash&&EndDelivery==DeliveryFileHash;Test->TestTrue(TEXT("Development scene/route/asset delivery inputs remain byte-exact"),Stable);Evidence->SetBoolField(TEXT("input_bytes_stable"),Stable);
        Evidence->SetStringField(TEXT("format"),TEXT("LivingTown.CafeWorker110DevelopmentPreviewEvidence"));Evidence->SetStringField(TEXT("status"),Completed&&!Test->HasAnyErrors()?TEXT("DEVELOPMENT_PREVIEW_OBSERVED_CONTACT_AND_CAMERA_REVIEW_REQUIRED"):TEXT("FAIL_DEVELOPMENT_PREVIEW_RAW_OBSERVATIONS_RETAINED"));Evidence->SetStringField(TEXT("scene_binding_sha256"),SceneFileHash);Evidence->SetStringField(TEXT("scene_route_sha256"),RouteFileHash);Evidence->SetStringField(TEXT("worker_delivery_receipt_sha256"),DeliveryFileHash);Evidence->SetNumberField(TEXT("moving_samples"),MovingSamples);Evidence->SetNumberField(TEXT("evaluation_serial_changes"),SerialChanges);Evidence->SetNumberField(TEXT("moving_displacement_cm"),MaxDisplacement);Evidence->SetNumberField(TEXT("moving_animation_time_changes"),AnimationTimeChanges);Evidence->SetNumberField(TEXT("moving_animation_absolute_time_travel"),AnimationTimeTravel);for(int32 I=0;I<2;++I){const FString Side=I?TEXT("right"):TEXT("left");Evidence->SetNumberField(Side+TEXT("_foot_minus_pelvis_span_cm"),FootSpan[I]);Evidence->SetNumberField(Side+TEXT("_calf_local_rotation_degrees"),CalfDegrees[I]);Evidence->SetNumberField(Side+TEXT("_upper_arm_local_rotation_degrees"),ArmDegrees[I]);}Evidence->SetArrayField(TEXT("samples"),Samples);Evidence->SetBoolField(TEXT("production_binding_created_or_modified"),false);Evidence->SetBoolField(TEXT("ledger_actions_executed"),false);Evidence->SetBoolField(TEXT("manual_animation_tick_pose_time_or_actor_teleport"),false);Evidence->SetBoolField(TEXT("read_only_CPU_skinning_of_natural_pose_performed"),true);Evidence->SetBoolField(TEXT("physical_qualification_contacts_art_or_FPS_accepted"),false);
        if(World.IsValid())if(auto* P=World->GetSubsystem<ULivingTownCafeProjectionSubsystem>()){const bool Unprepared=!P->IsReady()&&!P->IsScenePrepared();Evidence->SetBoolField(TEXT("production_projection_stayed_unprepared"),Unprepared);Test->TestTrue(TEXT("Development preview never activates production projection"),Unprepared);if(!Unprepared)Evidence->SetStringField(TEXT("status"),TEXT("FAIL_DEVELOPMENT_PREVIEW_RAW_OBSERVATIONS_RETAINED"));}
        FString S;FJsonSerializer::Serialize(Evidence,TJsonWriterFactory<>::Create(&S));const FString Folder=FPaths::ProjectSavedDir()/TEXT("CafeWorker110Preview");IFileManager::Get().MakeDirectory(*Folder,true);if(!FFileHelper::SaveStringToFile(S,*(Folder/TEXT("NATURAL_PREVIEW_EVIDENCE.json")),FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM))Test->AddError(TEXT("Development preview evidence write failed"));
    }
public:
    FWorker110DevelopmentPreview(FAutomationTestBase* T,const FLivingTownCafeBinding& S,const TArray<FVector>& Points,const FString& SH,const FString& RH,const FString& DH):Test(T),Scene(S),Candidate(S),Route(Points),SceneFileHash(SH),RouteFileHash(RH),DeliveryFileHash(DH)
    {
        Candidate.MotionStrategy=ELivingTownCafeMotionStrategy::CafeWorker110RootAligned;Candidate.VisualAssetPath=LivingTownCafeWorker110::MeshAsset;Candidate.IdleWalkBlendSpacePath=LivingTownCafeWorker110::MotionAsset;Candidate.IdleAnimationPath=LivingTownCafeWorker110::IdleAsset;Candidate.WalkAnimationPath=LivingTownCafeWorker110::WalkAsset;Candidate.IdleRootDeltaCm=LivingTownCafeWorker110::RootDeltaCm();Candidate.UseSocket=LivingTownCafeWorker110::PalmSocket;Candidate.WalkSpeedCmPerSecond=110;Candidate.CapsuleRadiusCm=28;Candidate.CapsuleHalfHeightCm=95;
        Candidate.MeshRelativeTransform=FTransform(FQuat::Identity,FVector(-0.37614760646798817,2.2014072933912665,-95.0+0.000022156637096881492),FVector(1.7900001881321583));Candidate.CameraArmCm=300;Candidate.ReachCm=0;Candidate.Parts.Reset();Candidate.PhysicalQualificationSha256.Reset();Candidate.VisualSha256.Reset();Candidate.BindingFileSha256.Reset();
    }
    virtual ~FWorker110DevelopmentPreview(){CleanupFrameObservers();CleanupControlledPreviewLighting();}
    virtual bool Update()override
    {
        bool Done=false;if(FPlatformTime::Seconds()>Deadline)Done=Fail(TEXT("Owned development preview timed out"));else
        {
            UWorld* W=nullptr;int32 Count=0;for(const auto& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::Game||C.WorldType==EWorldType::PIE)){W=C.World();++Count;}if(Count>1)Done=Fail(TEXT("Ambiguous development preview world"));else if(W&&W->HasBegunPlay()&&W->GetFirstPlayerController())
            {
                auto* PC=W->GetFirstPlayerController();if(!Worker.IsValid()){if(!Start(W,PC))Done=true;}else if(World.Get()!=W||Controller.Get()!=PC||PC->GetPawn()!=Worker.Get())Done=Fail(TEXT("Owned development player/world identity changed"));else if(!Capture(W,PC,Worker.Get()))Done=true;else if(!bNaturalPoseReady)return false;else
                {
                    auto* Ben=Worker.Get();const double Time=W->GetTimeSeconds();if(Stage==0&&Time-StageStart>=2){Stage=1;StageStart=Time;}
                    if(Stage==1){const FVector Feet=Ben->GetActorLocation()-FVector(0,0,95);FVector Delta=Route[Waypoint]-Feet;Delta.Z=0;if(Delta.Size2D()>2){PC->SetControlRotation(Delta.Rotation());Ben->AddMovementInput(Delta.GetSafeNormal2D(),1);}else{Ben->GetCharacterMovement()->StopMovementImmediately();if(++Waypoint>=Route.Num()){Stage=2;StageStart=Time;}}}
                    if(Stage==2&&Time-StageStart>=2){Completed=MovingSamples>=12&&MaxDisplacement>=80&&SerialChanges>=3&&AnimationTimeChanges>=3&&AnimationTimeTravel>=.05&&FootSpan[0]>=2&&FootSpan[1]>=2&&CalfDegrees[0]>=2&&CalfDegrees[1]>=2&&ArmDegrees[0]>=2&&ArmDegrees[1]>=2;if(!Completed)Fail(TEXT("Development preview did not demonstrate natural moving player/evaluation progression"));Done=true;}
                }
            }
        }
        if(Done){CleanupFrameObservers();if(World.IsValid())LightCensus(World.Get(),TEXT("world_at_preview_end"));CleanupControlledPreviewLighting();if(Worker.IsValid()&&Controller.IsValid()&&Controller->GetPawn()==Worker.Get()){Controller->UnPossess();const bool Restored=static_cast<uint8>(Worker->GetMesh()->VisibilityBasedAnimTickOption)==PriorPossessedPolicy;Evidence->SetBoolField(TEXT("unpossessed_bone_tick_policy_restored"),Restored);Test->TestTrue(TEXT("Unpossessed worker restores its previous bone tick policy"),Restored);}if(Completed&&CapturedFrames!=3)Fail(TEXT("Three native idle/walk/stopped GPU frames unavailable; natural motion observations retained"));Persist();if(Worker.IsValid())Worker->Destroy();if(Venue.IsValid())Venue->Destroy();}return Done;
    }
};
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafeWorkerPreviewWorldTest,"LivingTown.Development.CafeWorker110NaturalPreview",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafeWorkerPreviewWorldTest::RunTest(const FString&)
{
    if(!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeWorker110DevelopmentPreview"))){AddError(TEXT("Explicit owned development-preview process flag required"));return false;}
    const FString Folder=FPaths::ProjectContentDir()/TEXT("LivingTown");if(IFileManager::Get().FileExists(*(Folder/TEXT("CafeProjectionBinding.json")))){AddError(TEXT("Production physical binding must be absent from the separate development preview"));return false;}
    const FString ScenePath=Folder/TEXT("CafePreviewSceneBinding.json"),RoutePath=Folder/TEXT("CafePreviewSceneRoute.json"),DeliveryPath=Folder/TEXT("CafeWorker110DeliveryReceipt.json");FString SceneHash,RouteHash,DeliveryHash,Why;
    FLivingTownCafeBinding Scene;if(!FLivingTownCafeBinding::ReadQualifiedFile(ScenePath,Scene,Why)||Scene.MotionStrategy!=ELivingTownCafeMotionStrategy::LegacySingleNode||!FileHash(ScenePath,SceneHash)||!FileHash(RoutePath,RouteHash)||!FileHash(DeliveryPath,DeliveryHash)){AddError(TEXT("Actual source-scene binding/route/new-worker delivery inputs required: ")+Why);return false;}
    FString Json;TSharedPtr<FJsonObject> O;FString RouteScene,RouteBinding;if(!FFileHelper::LoadFileToString(Json,*RoutePath)||!LivingTownCafeJournal::HasUniqueObjectKeys(Json)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),O)||!O||!O->TryGetStringField(TEXT("physical_scene_sha256"),RouteScene)||RouteScene!=Scene.PhysicalSceneSha256||!O->TryGetStringField(TEXT("physical_binding_sha256"),RouteBinding)||RouteBinding!=Scene.BindingFileSha256){AddError(TEXT("Original scene route provenance mismatch"));return false;}
    const TSet<FString> Fields={TEXT("format"),TEXT("version"),TEXT("status"),TEXT("physical_scene_sha256"),TEXT("physical_binding_sha256"),TEXT("capsule_radius_cm"),TEXT("capsule_half_height_cm"),TEXT("route_feet_cm")};FString Format,Version,Status;double Radius=0,Half=0;if(O->Values.Num()!=Fields.Num()||!O->TryGetStringField(TEXT("format"),Format)||Format!=TEXT("LivingTown.CafeJourneyRoute")||!O->TryGetStringField(TEXT("version"),Version)||Version!=TEXT("1")||!O->TryGetStringField(TEXT("status"),Status)||Status!=TEXT("UE_ROUTE_QUALIFIED")||!O->TryGetNumberField(TEXT("capsule_radius_cm"),Radius)||!O->TryGetNumberField(TEXT("capsule_half_height_cm"),Half)||Radius!=28||Half!=95||Scene.CapsuleRadiusCm!=28||Scene.CapsuleHalfHeightCm!=95){AddError(TEXT("Exact existing scene route schema/capsule contract required"));return false;}for(const FString& Field:Fields)if(!O->HasField(FStringView(Field))){AddError(TEXT("Unknown scene route field"));return false;}
    const TArray<TSharedPtr<FJsonValue>>* Raw=nullptr;TArray<FVector> Route;if(!O->TryGetArrayField(TEXT("route_feet_cm"),Raw)||Raw->Num()<2||Raw->Num()>64){AddError(TEXT("Bounded source route required"));return false;}for(const auto& Value:*Raw){if(!Value||Value->Type!=EJson::Array||Value->AsArray().Num()!=3){AddError(TEXT("Invalid source route point"));return false;}double XYZ[3];for(int32 I=0;I<3;++I){if(!Value->AsArray()[I]||Value->AsArray()[I]->Type!=EJson::Number||!FMath::IsFinite(XYZ[I]=Value->AsArray()[I]->AsNumber())){AddError(TEXT("Nonfinite source route point"));return false;}}Route.Add(FVector(XYZ[0],XYZ[1],XYZ[2]));}if(!Route[0].Equals(Scene.SpawnFeetCm,.1)){AddError(TEXT("Source route start mismatch"));return false;}
    if(!AutomationOpenMap(TEXT("/Engine/Maps/Entry"),true)){AddError(TEXT("Owned real PIE preview world did not open"));return false;}ADD_LATENT_AUTOMATION_COMMAND(FWorker110DevelopmentPreview(this,Scene,Route,SceneHash,RouteHash,DeliveryHash));return true;
}
#endif
