#include "LivingTownMetaHumanMealProducer.h"
#include "LivingTownMetaHumanVisualAssembly.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownCafeWorldV3Subsystem.h"
#include "LivingTownCafeWorldV3Scenario.h"
#include "LivingTownCafeVenue.h"
#include "Animation/AnimInstance.h"
#include "Animation/AnimSequence.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Animation/Skeleton.h"
#include "Components/CapsuleComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/StaticMesh.h"
#include "Engine/Texture.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Materials/MaterialInterface.h"
#include "UObject/SoftObjectPath.h"

namespace {
bool Refuse(FString& Error,const TCHAR* Why){Error=Why;return false;}
}
ULivingTownMetaHumanMealProducer::ULivingTownMetaHumanMealProducer(){
    PrimaryComponentTick.bCanEverTick=true;PrimaryComponentTick.bStartWithTickEnabled=false;
    PrimaryComponentTick.bTickEvenWhenPaused=true;PrimaryComponentTick.TickGroup=TG_PostUpdateWork;
}
UObject* ULivingTownMetaHumanMealProducer::RoleObject(const FString& Role)const{
    const auto* Object=SourceObjects.Find(Role);return Object?Object->Get():nullptr;
}
bool ULivingTownMetaHumanMealProducer::BindTrustedSessionObserver(ULivingTownCafeWorldV3Subsystem* Owner,TFunction<bool(const ALivingTownCafeCharacter*)>&& Observer){
    if(!IsInGameThread()||!bConfigured||bActive||!Owner||Authority.Get()!=Owner||!Observer)return false;
    TrustedSessionObserver=MoveTemp(Observer);return true;
}
bool ULivingTownMetaHumanMealProducer::Configure(const FString& RelativeRecipe,FString& Error){
    Error.Reset();if(!IsInGameThread()||bConfigured||bActive||!IsRegistered()||!GetWorld()||!GetWorld()->IsGameWorld()||GetWorld()->GetNetMode()!=NM_Standalone)return Refuse(Error,TEXT("meal_v2_registered_standalone_owner_required"));
    auto* P=Cast<ALivingTownCafeCharacter>(GetOwner());auto* A=GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();
    if(!P||!A||!A->IsPrepared()||!P->HasMetaHumanVisual()||!A->GetBinding().MetaHumanActor.IsSet())return Refuse(Error,TEXT("meal_v2_actual_metahuman_session_required"));
    FLivingTownMetaHumanMealRecipeV2 Candidate;if(!FLivingTownMetaHumanMealRecipeV2::ReadQualified(RelativeRecipe,Candidate,Error))return false;
    const auto& B=A->GetBinding();const auto& D=B.MetaHumanActor.GetValue();
    if(Candidate.BindingSha256!=B.BindingFileSha256||Candidate.VisualDescriptorSha256!=D.DescriptorSha256||Candidate.SourceClosureSha256!=D.SourceClosureSha256||
       Candidate.FindRole(TEXT("actor_class"))->Asset!=D.ActorClassPath||Candidate.FindRole(TEXT("body"))->Asset!=LivingTownMetaHumanVisual::BodyMesh||Candidate.FindRole(TEXT("face"))->Asset!=LivingTownMetaHumanVisual::FaceMesh||Candidate.FindRole(TEXT("outfit"))->Asset!=D.ExpectedOutfitMesh()||
       !B.CounterUsePointCm.Equals(Candidate.CounterPointCm,Candidate.TransformTolerance)||!B.FloorBoundsCm.IsInsideXY(Candidate.StationFeetCm))return Refuse(Error,TEXT("meal_v2_recipe_does_not_match_current_binding"));
    TMap<FString,TObjectPtr<UObject>> Objects;for(const auto& Role:Candidate.Assets){auto* Object=FSoftObjectPath(Role.Asset).ResolveObject();if(!IsValid(Object)||Object->GetPathName()!=Role.Asset)return Refuse(Error,TEXT("meal_v2_exact_preloaded_roles_required_no_runtime_load"));Objects.Add(Role.Role,Object);}
    const auto ObjectFor=[&](const FString& Role)->UObject*{const auto* Object=Objects.Find(Role);return Object?Object->Get():nullptr;};
    auto* NewClip=Cast<UAnimSequence>(ObjectFor(TEXT("clip")));auto* NewBread=Cast<UStaticMesh>(ObjectFor(TEXT("bread")));
    const auto* BMesh=Cast<USkeletalMesh>(ObjectFor(TEXT("body")));const auto* FMesh=Cast<USkeletalMesh>(ObjectFor(TEXT("face")));const auto* OMesh=Cast<USkeletalMesh>(ObjectFor(TEXT("outfit")));
    if(!NewClip||!NewBread||!BMesh||!FMesh||!OMesh||BMesh->GetSkeleton()!=ObjectFor(TEXT("body_skeleton"))||FMesh->GetSkeleton()!=ObjectFor(TEXT("face_skeleton"))||NewClip->GetSkeleton()!=BMesh->GetSkeleton()||OMesh->GetSkeleton()!=BMesh->GetSkeleton()||
       NewClip->IsValidAdditive()||NewClip->bEnableRootMotion||NewClip->RateScale!=1.f||NewClip->GetNumberOfSampledKeys()<2||!FMath::IsNearlyEqual(double(NewClip->GetPlayLength()),Candidate.Duration,Candidate.TimeError)||NewBread->GetStaticMaterials().Num()!=Candidate.BreadMaterials.Num())return Refuse(Error,TEXT("meal_v2_preloaded_mesh_rig_clip_or_material_mismatch"));
    TSet<FString> Used;for(int32 I=0;I<Candidate.BreadMaterials.Num();++I){auto* M=NewBread->GetStaticMaterials()[I].MaterialInterface.Get();if(!M||M!=ObjectFor(FString::Printf(TEXT("bread_material/%d"),I)))return Refuse(Error,TEXT("meal_v2_ordered_bread_material_mismatch"));TArray<UTexture*> Textures;M->GetUsedTextures(Textures);for(auto* T:Textures)if(T)Used.Add(T->GetPathName());}
    TSet<FString> Expected;for(int32 I=0;I<Candidate.BreadTextures.Num();++I){if(!Cast<UTexture>(ObjectFor(FString::Printf(TEXT("bread_texture/%d"),I))))return Refuse(Error,TEXT("meal_v2_real_texture_role_required"));Expected.Add(Candidate.BreadTextures[I]);}
    if(Used.Num()!=Expected.Num())return Refuse(Error,TEXT("meal_v2_complete_bread_texture_closure_mismatch"));for(const auto& T:Used)if(!Expected.Contains(T))return Refuse(Error,TEXT("meal_v2_unbound_bread_texture"));
    Recipe=MoveTemp(Candidate);SourceObjects=MoveTemp(Objects);Clip=NewClip;BreadMesh=NewBread;Pawn=P;Authority=A;bConfigured=true;return true;
}
bool ULivingTownMetaHumanMealProducer::LiveIdentity(FString& Error)const{
    const auto* P=Pawn.Get();const auto* A=Authority.Get();const auto* W=GetWorld();const auto* PC=W?Cast<ALivingTownCafeWorldV3Controller>(W->GetFirstPlayerController()):nullptr;
    if(!bConfigured||!P||GetOwner()!=P||!IsRegistered()||!W||W->IsPaused()||W->bIsTearingDown||W->GetNetMode()!=NM_Standalone||!A||W->GetSubsystem<ULivingTownCafeWorldV3Subsystem>()!=A||!A->IsPrepared()||!PC||!PC->HasNativePersona()||PC->GetNativePersona()!=ELivingTownCafeWorldPersona::Ben||PC->GetPawn()!=P||PC->GetViewTarget()!=P||P->GetController()!=PC||!A->GetPresentation().bSessionReady||A->GetPresentation().Persona!=TEXT("ben")||A->GetBinding().BindingFileSha256!=Recipe.BindingSha256)return Refuse(Error,TEXT("meal_v2_owned_native_session_lost"));
    if(!TrustedSessionObserver||!TrustedSessionObserver(P))return Refuse(Error,TEXT("meal_v2_trusted_current_session_grant_observer_required"));
    auto* S=Assembly.Get();auto* B=Body.Get();auto* F=Face.Get();auto* O=Outfit.Get();auto* PlayerNow=B?B->GetSingleNodeInstance():nullptr;
    if(!S||!S->IsConfigured()||S->GetOwner()!=P||S->GetVisualActor()!=Visual.Get()||S->GetBody()!=B||S->GetFace()!=F||!Visual.IsValid()||Visual->GetClass()!=RoleObject(TEXT("actor_class"))||!B||!F||!O||PlayerNow!=Player.Get()||
       B->GetSkeletalMeshAsset()!=RoleObject(TEXT("body"))||F->GetSkeletalMeshAsset()!=RoleObject(TEXT("face"))||O->GetSkeletalMeshAsset()!=RoleObject(TEXT("outfit"))||
       B->GetPostProcessInstance()!=BodyPost.Get()||F->GetAnimInstance()!=FaceMain.Get()||F->GetPostProcessInstance()!=FacePost.Get()||F->GetAnimationMode()!=EAnimationMode::Type(FaceMode)||F->LeaderPoseComponent.Get()!=FaceLeader.Get()||F->GetDisablePostProcessBlueprint()!=bFacePostDisabled||
       O->GetAnimInstance()!=OutfitMain.Get()||O->GetPostProcessInstance()!=OutfitPost.Get()||O->GetAnimationMode()!=EAnimationMode::Type(OutfitMode)||O->LeaderPoseComponent.Get()!=OutfitLeader.Get()||O->LeaderPoseComponent.Get()!=B||O->GetDisablePostProcessBlueprint()!=bOutfitPostDisabled)return Refuse(Error,TEXT("meal_v2_player_or_face_outfit_owner_replaced"));
    if(bActive&&(!S->IsActionClipActive()||!PlayerNow||PlayerNow->GetCurrentAsset()!=Clip||B->GetAnimationMode()!=EAnimationMode::AnimationSingleNode||PlayerNow->GetClass()!=UAnimSingleNodeInstance::StaticClass()||PlayerNow->IsLooping()||PlayerNow->GetPlayRate()!=1.f||!B->bEnableAnimation||B->bPauseAnims||B->GlobalAnimRateScale!=1.f))return Refuse(Error,TEXT("meal_v2_owned_action_asset_replaced"));
    return true;
}
bool ULivingTownMetaHumanMealProducer::ObserveStation(FString& Error)const{
    const auto* P=Pawn.Get();const auto* V=Venue.Get();const auto* W=GetWorld();if(!P||!V||!V->IsQualified()||!W||!IsValid(P->GetCharacterMovement())||!IsValid(P->GetCapsuleComponent())||!P->GetCharacterMovement()->IsMovingOnGround())return Refuse(Error,TEXT("meal_v2_grounded_station_lost"));
    const FVector Feet=P->GetActorLocation()-FVector(0,0,P->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());FHitResult Floor;
    const FVector ToCounter=(Recipe.CounterPointCm-P->GetActorLocation()).GetSafeNormal2D();
    if(Feet.ContainsNaN()||ToCounter.ContainsNaN()||FVector::Dist2D(Feet,Recipe.StationFeetCm)>Recipe.StationRadiusCm||FMath::Abs(Feet.Z-Recipe.StationFeetCm.Z)>Recipe.StationHeightToleranceCm||ToCounter.IsNearlyZero()||FVector::DotProduct(P->GetActorForwardVector().GetSafeNormal2D(),ToCounter)<Recipe.StationFacingDot||!V->FloorAt(Feet,Floor,P))return Refuse(Error,TEXT("meal_v2_measured_service_station_lost"));
    FCollisionQueryParams Q(SCENE_QUERY_STAT(MetaHumanMealStation),true);Q.AddIgnoredActor(P);FVector Eyes;FRotator Rotation;P->GetActorEyesViewPoint(Eyes,Rotation);FHitResult Hit;
    if(!W->LineTraceSingleByChannel(Hit,Eyes,Recipe.CounterPointCm,ECC_Visibility,Q)||!V->IsCounterComponent(Hit.GetComponent()))return Refuse(Error,TEXT("meal_v2_counter_eye_line_lost"));return true;
}
bool ULivingTownMetaHumanMealProducer::BeginPhysicalUse(FString& Error){
    Error.Reset();if(!IsInGameThread()||!bConfigured||bActive||!Pawn.IsValid())return Refuse(Error,TEXT("meal_v2_inactive_qualified_producer_required"));
    auto* P=Pawn.Get();auto* S=P->FindComponentByClass<ULivingTownMetaHumanVisualAssembly>();auto* B=S?S->GetBody():nullptr;auto* F=S?S->GetFace():nullptr;auto* V=S?S->GetVisualActor():nullptr;USkeletalMeshComponent* O=nullptr;
    if(!S||!S->IsConfigured()||S->IsActionClipActive()||!B||!F||!V)return Refuse(Error,TEXT("meal_v2_original_live_assembly_required"));
    TArray<USkeletalMeshComponent*> Parts;V->GetComponents(Parts);for(auto* Part:Parts)if(Part!=B&&Part!=F)O=Part;
    if(Parts.Num()!=3||!O||O->LeaderPoseComponent.Get()!=B||!B->GetPostProcessInstance()||B->GetPostProcessInstance()->GetClass()!=RoleObject(TEXT("body_post"))||F->GetAnimationMode()!=EAnimationMode::AnimationBlueprint||!F->GetAnimInstance()||F->GetAnimInstance()->GetClass()!=RoleObject(TEXT("face_main"))||!F->GetPostProcessInstance()||F->GetPostProcessInstance()->GetClass()!=RoleObject(TEXT("face_post"))||F->GetDisablePostProcessBlueprint()||B->GetBoneIndex(Recipe.HandBone)==INDEX_NONE||F->GetBoneIndex(Recipe.MouthBone)==INDEX_NONE||F->GetBoneIndex(Recipe.JawBone)==INDEX_NONE||F->GetParentBone(Recipe.JawBone)!=Recipe.JawParentBone)return Refuse(Error,TEXT("meal_v2_actual_body_face_anchor_sources_required"));
    for(const auto& G:Recipe.GripProbes)if(B->GetBoneIndex(G.BodyBone)==INDEX_NONE)return Refuse(Error,TEXT("meal_v2_actual_holding_bone_missing"));
    Assembly=S;Visual=V;Body=B;Face=F;Outfit=O;Player=B->GetSingleNodeInstance();BodyPost=B->GetPostProcessInstance();FaceMain=F->GetAnimInstance();FacePost=F->GetPostProcessInstance();FaceLeader=F->LeaderPoseComponent;FaceMode=uint8(F->GetAnimationMode());bFacePostDisabled=F->GetDisablePostProcessBlueprint();OutfitMain=O->GetAnimInstance();OutfitPost=O->GetPostProcessInstance();OutfitLeader=O->LeaderPoseComponent;OutfitMode=uint8(O->GetAnimationMode());bOutfitPostDisabled=O->GetDisablePostProcessBlueprint();
    int32 Venues=0;for(TActorIterator<ALivingTownCafeVenue> It(GetWorld());It;++It)if(It->IsQualified()){Venue=*It;++Venues;}
    if(Venues!=1)return Refuse(Error,TEXT("meal_v2_one_qualified_venue_required"));
    if(!LiveIdentity(Error)||!ObserveStation(Error))return false;
    Failure.Reset();Latest={};BiteSamples=0;bBiteObserved=false;bChewObserved=false;BiteSpanStart=0;BiteObservedAt=0;MaxChewJawDegrees=0;BodyFinalizedFrame=FaceFinalizedFrame=MAX_uint64;
    OwnedBread=NewObject<UStaticMeshComponent>(P);P->AddInstanceComponent(OwnedBread);OwnedBread->SetMobility(EComponentMobility::Movable);OwnedBread->SetupAttachment(B,Recipe.HandBone);OwnedBread->SetRelativeTransform(Recipe.GripRelative);OwnedBread->SetStaticMesh(BreadMesh);OwnedBread->SetCollisionEnabled(ECollisionEnabled::NoCollision);OwnedBread->SetGenerateOverlapEvents(false);OwnedBread->SetCanEverAffectNavigation(false);OwnedBread->RegisterComponent();
    if(!OwnedBread->IsRegistered()||!S->BeginActionClip(Clip,false,Error)){StopPhysicalUse();return false;}
    bActive=true;bMayRestoreAction=true;bAwaitingFirstPose=true;StartedFrame=GFrameCounter;StartedWorld=LastWorld=GetWorld()->GetTimeSeconds();LastClip=Player->GetCurrentTime();LastBodyRevision=B->GetBoneTransformRevisionNumber();LastFaceRevision=F->GetBoneTransformRevisionNumber();
    BodyFinalizedHandle=B->RegisterOnBoneTransformsFinalizedDelegate(FOnBoneTransformsFinalizedMultiCast::FDelegate::CreateUObject(this,&ULivingTownMetaHumanMealProducer::BodyFinalized));
    FaceFinalizedHandle=F->RegisterOnBoneTransformsFinalizedDelegate(FOnBoneTransformsFinalizedMultiCast::FDelegate::CreateUObject(this,&ULivingTownMetaHumanMealProducer::FaceFinalized));
    if(!BodyFinalizedHandle.IsValid()||!FaceFinalizedHandle.IsValid()){StopPhysicalUse();return Refuse(Error,TEXT("meal_v2_finalized_pose_observers_required"));}
    AddTickPrerequisiteComponent(B);AddTickPrerequisiteComponent(F);SetComponentTickEnabled(true);return true;
}
void ULivingTownMetaHumanMealProducer::BodyFinalized(){if(IsInGameThread()&&bActive)BodyFinalizedFrame=GFrameCounter;}
void ULivingTownMetaHumanMealProducer::FaceFinalized(){if(IsInGameThread()&&bActive)FaceFinalizedFrame=GFrameCounter;}
bool ULivingTownMetaHumanMealProducer::LiveBread(FString& Error)const{
    const auto* Food=OwnedBread.Get();
    if(!Food||Food->GetOwner()!=Pawn.Get()||!Food->IsRegistered()||Food->GetAttachParent()!=Body.Get()||Food->GetAttachSocketName()!=Recipe.HandBone||Food->GetStaticMesh()!=BreadMesh||Food->GetCollisionEnabled()!=ECollisionEnabled::NoCollision||!Food->IsVisible()||Food->bHiddenInGame||Food->GetOverlayMaterial()||Food->GetNumMaterials()!=Recipe.BreadMaterials.Num()||!Food->GetRelativeTransform().Equals(Recipe.GripRelative,Recipe.TransformTolerance))return Refuse(Error,TEXT("meal_v2_owned_bread_replaced_or_detached"));
    for(int32 I=0;I<Recipe.BreadMaterials.Num();++I)if(Food->GetMaterial(I)!=RoleObject(FString::Printf(TEXT("bread_material/%d"),I))||Food->GetOverlayMaterial(true,I))return Refuse(Error,TEXT("meal_v2_live_bread_material_changed"));
    return true;
}
bool ULivingTownMetaHumanMealProducer::ObserveFrame(FString& Error){
    if(!LiveIdentity(Error)||!LiveBread(Error)||!ObserveStation(Error))return false;auto* B=Body.Get();auto* F=Face.Get();auto* P=Player.Get();auto* Food=OwnedBread.Get();
    const double Now=GetWorld()->GetTimeSeconds(),Elapsed=Now-LastWorld,Time=P->GetCurrentTime(),Advanced=Time-LastClip;
    if(!FMath::IsFinite(Elapsed)||Elapsed<=0||Elapsed>Recipe.MaxFrameGap||!FMath::IsFinite(Time)||Time<0||Time>Recipe.Duration+Recipe.TimeError||Advanced<=0||FMath::Abs(Advanced-Elapsed)>Recipe.TimeError)return Refuse(Error,TEXT("meal_v2_stale_frozen_or_reset_clip_time"));
    if(BodyFinalizedFrame!=GFrameCounter||FaceFinalizedFrame!=GFrameCounter||B->GetBoneTransformRevisionNumber()==LastBodyRevision||F->GetBoneTransformRevisionNumber()==LastFaceRevision)return Refuse(Error,TEXT("meal_v2_fresh_finalized_body_and_face_required"));
    const FTransform FoodWorld=Food->GetComponentTransform(),HandWorld=B->GetSocketTransform(Recipe.HandBone,RTS_World),MouthWorld=F->GetSocketTransform(Recipe.MouthBone,RTS_World);
    if(!FoodWorld.IsValid()||!HandWorld.IsValid()||!MouthWorld.IsValid()||!FoodWorld.Equals(Recipe.GripRelative*HandWorld,Recipe.TransformTolerance))return Refuse(Error,TEXT("meal_v2_actual_food_socket_transform_stale"));
    for(const auto& G:Recipe.GripProbes){const FVector Bone=B->GetSocketLocation(G.BodyBone),Point=FoodWorld.TransformPosition(G.FoodPointCm);if(Bone.ContainsNaN()||Point.ContainsNaN()||FVector::Dist(Bone,Point)>G.MaxDistanceCm)return Refuse(Error,TEXT("meal_v2_measured_physical_grip_lost"));}
    const FVector Bite=FoodWorld.TransformPosition(Recipe.FoodBitePointCm),Mouth=MouthWorld.TransformPosition(Recipe.MouthOffsetCm);
    if(Bite.ContainsNaN()||Mouth.ContainsNaN())return Refuse(Error,TEXT("meal_v2_finite_bite_and_mouth_points_required"));
    const float ExpectedCurve=Clip->EvaluateCurveData(Recipe.JawCurve,FAnimExtractContext(Time),false);
    float BC=0,FC=0;if(!P->GetCurveValue(Recipe.JawCurve,BC)||!FaceMain->GetCurveValue(Recipe.JawCurve,FC)||!FMath::IsFinite(ExpectedCurve)||!FMath::IsFinite(BC)||!FMath::IsFinite(FC)||FMath::Abs(double(BC)-ExpectedCurve)>Recipe.CurveTolerance||FMath::Abs(double(BC)-FC)>Recipe.CurveTolerance)return Refuse(Error,TEXT("meal_v2_actual_body_face_curve_chain_lost"));
    if(Time>=Recipe.BiteStart&&Time<=Recipe.BiteEnd){
        if(Bite.ContainsNaN()||Mouth.ContainsNaN()||FVector::Dist(Bite,Mouth)>Recipe.MaxBiteDistanceCm||BC<Recipe.MinBiteJawCurve||FC<Recipe.MinBiteJawCurve)return Refuse(Error,TEXT("meal_v2_actual_food_mouth_bite_lost"));
        if(BiteSamples==0)BiteSpanStart=Time;++BiteSamples;
        if(!bBiteObserved&&BiteSamples>=Recipe.MinBiteSamples&&Time-BiteSpanStart>=Recipe.MinBiteSpan){bBiteObserved=true;BiteObservedAt=Now;}
    }
    if(Time>Recipe.BiteEnd&&!bBiteObserved)return Refuse(Error,TEXT("meal_v2_measured_bite_interval_not_observed"));
    if(Time>=Recipe.ChewStart&&Time<=Recipe.ChewEnd){
        const FTransform RelativeJaw=F->GetSocketTransform(Recipe.JawBone,RTS_Component).GetRelativeTransform(F->GetSocketTransform(Recipe.JawParentBone,RTS_Component));if(!RelativeJaw.IsValid())return Refuse(Error,TEXT("meal_v2_finite_relative_jaw_pose_required"));
        if(!bChewObserved){bChewObserved=true;MinBodyCurve=MaxBodyCurve=MotionBodyCurve=BC;MinFaceCurve=MaxFaceCurve=MotionFaceCurve=FC;FirstChewJaw=MotionJaw=RelativeJaw.GetRotation();LastCurveMotionWorld=LastJawMotionWorld=Now;}
        MinBodyCurve=FMath::Min(MinBodyCurve,BC);MaxBodyCurve=FMath::Max(MaxBodyCurve,BC);MinFaceCurve=FMath::Min(MinFaceCurve,FC);MaxFaceCurve=FMath::Max(MaxFaceCurve,FC);
        MaxChewJawDegrees=FMath::Max(MaxChewJawDegrees,FMath::RadiansToDegrees(FirstChewJaw.AngularDistance(RelativeJaw.GetRotation())));
        if(FMath::Abs(BC-MotionBodyCurve)>=Recipe.MinChewCurveDelta&&FMath::Abs(FC-MotionFaceCurve)>=Recipe.MinChewCurveDelta){MotionBodyCurve=BC;MotionFaceCurve=FC;LastCurveMotionWorld=Now;}
        if(FMath::RadiansToDegrees(MotionJaw.AngularDistance(RelativeJaw.GetRotation()))>=Recipe.MinChewJawDegrees){MotionJaw=RelativeJaw.GetRotation();LastJawMotionWorld=Now;}
        if(Now-LastCurveMotionWorld>Recipe.MaxChewStaticSpan||Now-LastJawMotionWorld>Recipe.MaxChewStaticSpan)return Refuse(Error,TEXT("meal_v2_actual_chewing_curve_or_jaw_frozen"));
    }
    if(Time>Recipe.ChewEnd&&(!bChewObserved||double(MaxBodyCurve-MinBodyCurve)<Recipe.MinChewCurveDelta||double(MaxFaceCurve-MinFaceCurve)<Recipe.MinChewCurveDelta||MaxChewJawDegrees<Recipe.MinChewJawDegrees))return Refuse(Error,TEXT("meal_v2_actual_natural_chewing_not_observed"));
    Latest={};Latest.Frame=GFrameCounter;Latest.WorldSeconds=Now;Latest.ClipSeconds=Time;Latest.FoodBiteWorld=Bite;Latest.MouthWorld=Mouth;Latest.bFresh=true;Latest.bHolding=true;Latest.bBiteObserved=bBiteObserved;
    Latest.Phase=Time>=Recipe.Duration-Recipe.TimeError?ELivingTownMealPhysicalPhase::Finished:Time>=Recipe.TailStart?ELivingTownMealPhysicalPhase::Exit:Time>=Recipe.ChewStart?ELivingTownMealPhysicalPhase::Chew:Time>=Recipe.BiteStart?ELivingTownMealPhysicalPhase::Bite:ELivingTownMealPhysicalPhase::Entry;
    const bool ChewWitness=bChewObserved&&double(MaxBodyCurve-MinBodyCurve)>=Recipe.MinChewCurveDelta&&double(MaxFaceCurve-MinFaceCurve)>=Recipe.MinChewCurveDelta&&MaxChewJawDegrees>=Recipe.MinChewJawDegrees;
    Latest.bFirstProgressEligible=bBiteObserved&&ChewWitness&&Now-BiteObservedAt>=Recipe.FirstProgressDelay&&Time>=Recipe.ChewStart&&Time<=Recipe.ChewEnd;Latest.bConsumptionPhase=Latest.bFirstProgressEligible;
    LastWorld=Now;LastClip=Time;LastBodyRevision=B->GetBoneTransformRevisionNumber();LastFaceRevision=F->GetBoneTransformRevisionNumber();return true;
}
void ULivingTownMetaHumanMealProducer::TickComponent(float Delta,ELevelTick Type,FActorComponentTickFunction* Tick){
    Super::TickComponent(Delta,Type,Tick);if(!bActive)return;FString Error;
    if(bAwaitingFirstPose){
        const double Now=GetWorld()->GetTimeSeconds(),Age=Now-StartedWorld;
        if(!LiveIdentity(Error)||!LiveBread(Error)||!ObserveStation(Error)){Failure=Error;StopPhysicalUse();return;}
        if(!FMath::IsFinite(Age)||Age<0||Age>Recipe.MaxFrameGap){Failure=TEXT("meal_v2_initial_natural_pose_deadline");StopPhysicalUse();return;}
        // Begin may run before or after either animation tick. Never label the
        // start frame fresh, and never compare a partial first tick with a full dt.
        const double Time=Player->GetCurrentTime();
        if(GFrameCounter!=StartedFrame&&Age>0&&FMath::IsFinite(Time)&&Time>LastClip&&Time<=Recipe.Duration&&BodyFinalizedFrame==GFrameCounter&&FaceFinalizedFrame==GFrameCounter&&Body->GetBoneTransformRevisionNumber()!=LastBodyRevision&&Face->GetBoneTransformRevisionNumber()!=LastFaceRevision){
            LastWorld=Now;LastClip=Time;LastBodyRevision=Body->GetBoneTransformRevisionNumber();LastFaceRevision=Face->GetBoneTransformRevisionNumber();bAwaitingFirstPose=false;
        }
        return; // No holding/contact/benefit sample until the next natural frame.
    }
    if(!ObserveFrame(Error)){Failure=Error;Latest={};StopPhysicalUse();return;}
    if(Latest.Phase==ELivingTownMealPhysicalPhase::Finished)StopPhysicalUse();
}
bool ULivingTownMetaHumanMealProducer::ReadLatest(FLivingTownMealPhysicalObservation& Out,FString& Error)const{
    Out={};Error.Reset();if(!IsInGameThread())return Refuse(Error,TEXT("meal_v2_game_thread_observation_required"));
    const double Age=GetWorld()?GetWorld()->GetTimeSeconds()-Latest.WorldSeconds:-1;
    if(!bActive||!Failure.IsEmpty()||!Latest.bFresh||Latest.Frame!=GFrameCounter||Age<0||Age>Recipe.MaxFrameGap)return Refuse(Error,TEXT("meal_v2_no_fresh_observation"));
    if(!LiveIdentity(Error)||!LiveBread(Error))return false;
    if(Body->GetBoneTransformRevisionNumber()!=LastBodyRevision||Face->GetBoneTransformRevisionNumber()!=LastFaceRevision||Player->GetCurrentTime()!=LastClip)return Refuse(Error,TEXT("meal_v2_observed_pose_changed_after_production"));
    Out=Latest;return true;
}
void ULivingTownMetaHumanMealProducer::StopPhysicalUse(){
    if(!IsInGameThread())return;Latest={};bActive=false;SetComponentTickEnabled(false);
    if(Body.IsValid()){if(BodyFinalizedHandle.IsValid())Body->UnregisterOnBoneTransformsFinalizedDelegate(BodyFinalizedHandle);RemoveTickPrerequisiteComponent(Body.Get());}
    if(Face.IsValid()){if(FaceFinalizedHandle.IsValid())Face->UnregisterOnBoneTransformsFinalizedDelegate(FaceFinalizedHandle);RemoveTickPrerequisiteComponent(Face.Get());}
    BodyFinalizedHandle.Reset();FaceFinalizedHandle.Reset();
    if(OwnedBread){if(auto* P=Pawn.Get())P->RemoveInstanceComponent(OwnedBread);OwnedBread->DestroyComponent();OwnedBread=nullptr;}
    if(bMayRestoreAction&&Assembly.IsValid()&&Assembly->IsActionClipActive()&&Body.IsValid()&&Player.IsValid()&&Body->GetSingleNodeInstance()==Player.Get()&&Player->GetCurrentAsset()==Clip)Assembly->EndActionClip();
    Latest={};bActive=false;bMayRestoreAction=false;bAwaitingFirstPose=false;bBiteObserved=false;bChewObserved=false;BiteSamples=0;
}
void ULivingTownMetaHumanMealProducer::EndPlay(const EEndPlayReason::Type Reason){StopPhysicalUse();bConfigured=false;TrustedSessionObserver=nullptr;SourceObjects.Empty();Clip=nullptr;BreadMesh=nullptr;Super::EndPlay(Reason);}
