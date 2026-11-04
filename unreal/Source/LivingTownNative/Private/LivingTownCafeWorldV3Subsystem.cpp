#include "LivingTownCafeWorldV3Subsystem.h"
#include "LivingTownCafeWorldV3Scenario.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownCafeVenue.h"
#include "LivingTownCafeProjectionSubsystem.h"
#include "LivingTownLeaseSubsystem.h"
#include "LivingTownCafeSlot.h"
#include "../ThirdParty/CafeWorldV3Envelope.hpp"
#include "LivingTownCafePropertyV2Scenario.h"
#include "LivingTownCafePropertyV2Subsystem.h"
#include "../ThirdParty/CafeBackendV3.hpp"
#include "Engine/GameInstance.h"
#include "Engine/World.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Animation/AnimSequence.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/Base64.h"
#include "HAL/FileManager.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Policies/CondensedJsonPrintPolicy.h"

namespace {
namespace P=living_town::cafe_world_v3;
namespace Care=living_town::daily_life_use_v1;
namespace Backend=living_town::cafe_backend_v3;
constexpr const TCHAR* CoreHash=TEXT("9c31b82a263b389457a8d3ea00344f90e24b81f646f66a6b8377ccb4b85be46d");
constexpr const TCHAR* RosterHash=TEXT("fda4596387cffd0eec0cab7fb021e7950afc4c6e878467712949924a630f0d8b");
constexpr const TCHAR* ConfigHash=TEXT("d45f1b001e0177088757be4e45ee3a4910c5cd6b09b18128693058886f40637f");
constexpr int64 MaxEnvelopeBytes=64*1024*1024;
constexpr const TCHAR* CareHash=TEXT("3968a82beab862fdd56054d1fe6cfe08aca3c7be41003a1fdc82abae56841d06");
constexpr const TCHAR* EnvelopeHashSource=TEXT("f003c16885a0fb8213f492114d1b9aa108791385f45a6c23f4e12e67d17b7616");

FString Text(const std::string& S){return FString(UTF8_TO_TCHAR(S.c_str()));}
std::string Utf8(const FString& S){return std::string(TCHAR_TO_UTF8(*S));}
FString PersonaId(ELivingTownCafeWorldPersona Pn){return Pn==ELivingTownCafeWorldPersona::Aria?TEXT("aria"):TEXT("ben");}
bool ValidPersona(ELivingTownCafeWorldPersona Pn){return Pn==ELivingTownCafeWorldPersona::Aria||Pn==ELivingTownCafeWorldPersona::Ben;}
bool Keys(const FJsonObject& O,std::initializer_list<const TCHAR*> K){if(O.Values.Num()!=static_cast<int32>(K.size()))return false;for(const auto* S:K)if(!O.HasField(FStringView(S)))return false;return true;}
bool String(const FJsonObject& O,const TCHAR* Key,FString& Value){return O.HasTypedField<EJson::String>(Key)&&O.TryGetStringField(Key,Value);}
TArray<uint8> Bytes(const std::string& S){TArray<uint8> Out;Out.Append(reinterpret_cast<const uint8*>(S.data()),static_cast<int32>(S.size()));return Out;}
bool SourceFile(const FString& Path,const TCHAR* Expected,TArray<uint8>& Data){FString H;const int64 Size=IFileManager::Get().FileSize(*Path);return Size>0&&Size<=2*1024*1024&&FFileHelper::LoadFileToArray(Data,*Path)&&LivingTownCafeJournal::Sha256(Data,H)&&H==Expected;}
bool AuthoredSources(FString& Error){
    const FString Folder=FPaths::ProjectContentDir()/TEXT("LivingTown");TArray<uint8> Data;
    if(!SourceFile(Folder/TEXT("PropertyV2PropertyRegistry.json"),ConfigHash,Data)){Error=TEXT("property_v2_exact_authored_property_source_required");return false;}
    if(!SourceFile(Folder/TEXT("PropertyV2AuthoredAgents.json"),RosterHash,Data)){Error=TEXT("property_v2_exact_authored_roster_source_required");return false;}
    FString Json;FFileHelper::BufferToString(Json,Data.GetData(),Data.Num());TSharedPtr<FJsonObject> O;const TArray<TSharedPtr<FJsonValue>>* Agents=nullptr;
    if(!LivingTownCafeJournal::HasUniqueObjectKeys(Json)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),O)||!O||!O->TryGetArrayField(TEXT("agents"),Agents)){Error=TEXT("authored_roster_invalid");return false;}
    int32 Aria=0,Ben=0;for(const auto& V:*Agents){if(!V||V->Type!=EJson::Object||!V->AsObject())continue;FString Id,Persona;const auto A=V->AsObject();if(!A->TryGetStringField(TEXT("id"),Id))continue;if(Id==TEXT("aria")||Id==TEXT("ben")){if(!A->TryGetStringField(TEXT("persona"),Persona)||Persona!=Id){Error=TEXT("authored_persona_identity_mismatch");return false;}if(Id==TEXT("aria"))++Aria;else ++Ben;}}
    if(Aria!=1||Ben!=1){Error=TEXT("two_unique_authored_personas_required");return false;}return true;
}
FLivingTownCafeWorldReceipt Refused(const FString& Why){FLivingTownCafeWorldReceipt R;R.Reason=Why;R.Message=Why==TEXT("meal_pilot_requires_ben")?TEXT("Select Ben to eat at the cafe."):TEXT("That action is unavailable. Please try again at the cafe counter.");return R;}
P::Action Action(ELivingTownCafePropertyAction A){switch(A){case ELivingTownCafePropertyAction::OfferLease:return P::Action::offer_lease;case ELivingTownCafePropertyAction::OfferSale:return P::Action::offer_sale;case ELivingTownCafePropertyAction::Buy:return P::Action::buy;case ELivingTownCafePropertyAction::Lease:return P::Action::lease;case ELivingTownCafePropertyAction::EndLease:return P::Action::end_lease;}throw std::invalid_argument("unsupported_action");}
}

namespace {
P::CareBindings CareSources(const FLivingTownCafeBinding& B);
bool ReadMealSource(const FLivingTownCafeBinding& B,P::CareBindings& Sources,FString& Error);
}
struct ULivingTownCafeWorldV3Subsystem::FState {P::Kernel Kernel;Care::ResidentUse Use{"ben"};P::CareBindings Sources;int64 Clock=0;};
void ULivingTownCafeWorldV3Subsystem::FStateDeleter::operator()(FState* Pn)const{delete Pn;}
ULivingTownCafeWorldV3Subsystem::ULivingTownCafeWorldV3Subsystem()=default;
ULivingTownCafeWorldV3Subsystem::~ULivingTownCafeWorldV3Subsystem()=default;
bool ULivingTownCafeWorldV3Subsystem::ShouldCreateSubsystem(UObject* Outer)const{return Super::ShouldCreateSubsystem(Outer)&&LivingTownCafeNativeBackend::Selected()==Backend::Backend::WorldV3;}
bool ULivingTownCafeWorldV3Subsystem::DoesSupportWorldType(EWorldType::Type T)const{return T==EWorldType::Game||T==EWorldType::PIE;}
TStatId ULivingTownCafeWorldV3Subsystem::GetStatId()const{RETURN_QUICK_DECLARE_CYCLE_STAT(ULivingTownCafeWorldV3Subsystem,STATGROUP_Tickables);}
void ULivingTownCafeWorldV3Subsystem::Deinitialize(){DetachNativeSession();State.Reset();if(IsValid(Venue))Venue->Destroy();Venue=nullptr;bPrepared=false;Super::Deinitialize();}
bool ULivingTownCafeWorldV3Subsystem::PrepareScenario(FString& Error){
    Error.Reset();auto Fail=[&](const TCHAR* Why){Error=Why;Notice=Error;RefreshPresentation();return false;};
    UWorld* W=GetWorld();if(!IsInGameThread()||bPrepared||!W)return Fail(TEXT("single_game_thread_property_scenario_required"));
    if(!Backend::can_activate(LivingTownCafeNativeBackend::Selected(),W->GetAuthGameMode()&&W->GetAuthGameMode()->GetClass()==ALivingTownCafeWorldV3GameMode::StaticClass()?Backend::ExactMode::WorldV3:Backend::ExactMode::Other,W->GetNetMode()==NM_Standalone,LivingTownCafeNativeBackend::Flags().worker_preview))return Fail(TEXT("explicit_exclusive_world_v3_standalone_scenario_required"));
    if(W->GetSubsystem<ULivingTownCafePropertyV2Subsystem>())return Fail(TEXT("property_v2_authority_must_not_exist_in_world_v3"));
    if(!W->GetGameInstance()||W->GetGameInstance()->GetSubsystem<ULivingTownLeaseSubsystem>())return Fail(TEXT("legacy_v1_authority_must_not_exist_in_world_v3"));
    if(const auto* Old=W->GetSubsystem<ULivingTownCafeProjectionSubsystem>())if(Old->IsReady()||Old->IsScenePrepared())return Fail(TEXT("legacy_v1_projection_must_remain_unprepared"));
    if(!AuthoredSources(Error)){Notice=Error;RefreshPresentation();return false;}
    FLivingTownCafeBinding B;if(!FLivingTownCafeBinding::ReadQualifiedFile(FPaths::ProjectContentDir()/TEXT("LivingTown/CafeProjectionBinding.json"),B,Error)){Notice=Error;RefreshPresentation();return false;}
    auto* V=W->SpawnActor<ALivingTownCafeVenue>();if(!V||!V->BuildQualified(B,Error)){if(V)V->Destroy();Notice=Error;RefreshPresentation();return false;}
    FHitResult Floor;FCollisionQueryParams Q(SCENE_QUERY_STAT(WorldV3ScenarioSpawn),true);const FVector Center=B.SpawnFeetCm+FVector(0,0,B.CapsuleHalfHeightCm);
    if(!B.FloorBoundsCm.IsInsideXY(B.SpawnFeetCm)||!V->FloorAt(B.SpawnFeetCm,Floor)||W->OverlapBlockingTestByChannel(Center,FQuat::Identity,ECC_Pawn,FCollisionShape::MakeCapsule(B.CapsuleRadiusCm,B.CapsuleHalfHeightCm),Q)){V->Destroy();return Fail(TEXT("qualified_property_scenario_spawn_refused"));}
    // Construct the sole book only after source, scenario, geometry and v1 absence checks.
    State.Reset(new FState());if(!ReadMealSource(B,State->Sources,Error)){State.Reset();V->Destroy();return false;}if(!State->Kernel.activate_care({0,true}).ok){State.Reset();V->Destroy();return Fail(TEXT("world_care_activation_failed"));}Binding=MoveTemp(B);Venue=V;bPrepared=true;ClockRemainder=0;Notice=TEXT("Choose Ben or Aria, then walk to the cafe counter.");RefreshPresentation();return true;
}
void ULivingTownCafeWorldV3Subsystem::DetachNativeSession(){if(State)P::cancel_meal_use(State->Kernel,State->Use,P::ReleaseReason::Interrupted);StopPhysicalMeal();SessionController.Reset();SessionPawn.Reset();RefreshPresentation();}
bool ULivingTownCafeWorldV3Subsystem::BindNativeSession(ALivingTownCafeWorldV3Controller* PC,ACharacter* Pawn,FString& Error){
    Error.Reset();if(!IsInGameThread()||!bPrepared||!State||!PC||!Pawn||PC!=GetWorld()->GetFirstPlayerController()||PC->GetWorld()!=GetWorld()||Pawn->GetWorld()!=GetWorld()||PC->GetPawn()!=Pawn||Pawn->GetController()!=PC||!PC->HasNativePersona()||!ValidPersona(PC->GetNativePersona())){Error=TEXT("native_persona_possession_required");return false;}
    const auto* Ben=Cast<ALivingTownCafeCharacter>(Pawn);const auto* Owner=Cast<ALivingTownCafePropertyOwnerProxy>(Pawn);
    if((PC->GetNativePersona()==ELivingTownCafeWorldPersona::Ben&&(!Ben||!Ben->HasQualifiedVisual()))||(PC->GetNativePersona()==ELivingTownCafeWorldPersona::Aria&&(!Owner||!Owner->IsFunctionalOwnerConfigured()))){Error=TEXT("persona_and_native_pawn_class_must_match");return false;}
    if(!FMath::IsNearlyEqual(Pawn->GetCapsuleComponent()->GetScaledCapsuleRadius(),Binding.CapsuleRadiusCm,.01f)||!FMath::IsNearlyEqual(Pawn->GetCapsuleComponent()->GetScaledCapsuleHalfHeight(),Binding.CapsuleHalfHeightCm,.01f)){Error=TEXT("persona_capsule_binding_mismatch");return false;}
    SessionController=PC;SessionPawn=Pawn;Notice=PC->GetNativePersona()==ELivingTownCafeWorldPersona::Aria?TEXT("Playing Aria. Walk to the cafe counter."):TEXT("Playing Ben. Walk to the cafe counter.");RefreshPresentation();return true;
}
bool ULivingTownCafeWorldV3Subsystem::ObserveCounter(bool& Reach,FString& Why)const{
    Reach=false;Why.Reset();const auto* PC=SessionController.Get();const auto* Pawn=SessionPawn.Get();UWorld* W=GetWorld();
    if(!bPrepared||!State||!W||!PC||!Pawn||!PC->HasNativePersona()||PC!=W->GetFirstPlayerController()||PC->GetPawn()!=Pawn||Pawn->GetController()!=PC||PC->GetViewTarget()!=Pawn||!IsValid(Venue)||!Venue->IsQualified()){Why=TEXT("native_persona_scene_binding_lost");return false;}
    const FVector Feet=Pawn->GetActorLocation()-FVector(0,0,Pawn->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());FHitResult Floor;
    if(!Pawn->GetCharacterMovement()->IsMovingOnGround()||!Binding.FloorBoundsCm.IsInsideXY(Feet)||!Venue->FloorAt(Feet,Floor,Pawn)){Why=TEXT("stand_on_the_actual_cafe_floor");return true;}
    const FVector Target=Binding.CounterUsePointCm;FVector Origin;const auto* Ben=Cast<ALivingTownCafeCharacter>(Pawn);
    if(PC->GetNativePersona()==ELivingTownCafeWorldPersona::Ben){if(!Ben||!Ben->HasQualifiedVisual()){Why=TEXT("qualified_Ben_visual_lost");return false;}Origin=Ben->InteractionHand();}
    else {const auto* Owner=Cast<ALivingTownCafePropertyOwnerProxy>(Pawn);if(!Owner||!Owner->IsFunctionalOwnerConfigured()){Why=TEXT("functional_owner_proxy_lost");return false;}const float Distance=Owner->GetCapsuleComponent()->GetClosestPointOnCollision(Target,Origin);if(!FMath::IsFinite(Distance)||Distance<0){Why=TEXT("actual_owner_capsule_query_unavailable");return true;}}
    if(Origin.ContainsNaN()||FVector::Dist(Origin,Target)>Binding.ReachCm){Why=TEXT("walk_closer_to_the_counter");return true;}
    if(FVector::DotProduct(Pawn->GetActorForwardVector().GetSafeNormal2D(),(Target-Pawn->GetActorLocation()).GetSafeNormal2D())<.15){Why=TEXT("face_the_counter");return true;}
    FCollisionQueryParams Q(SCENE_QUERY_STAT(WorldV3ActualCounter),true);Q.AddIgnoredActor(Pawn);FVector Eyes;FRotator Rotation;Pawn->GetActorEyesViewPoint(Eyes,Rotation);FHitResult NearHit,EyeHit;
    if(!W->LineTraceSingleByChannel(NearHit,Origin,Target,ECC_Visibility,Q)||!Venue->IsCounterComponent(NearHit.GetComponent())||!W->LineTraceSingleByChannel(EyeHit,Eyes,Target,ECC_Visibility,Q)||!Venue->IsCounterComponent(EyeHit.GetComponent())){Why=TEXT("counter_line_of_sight_blocked");return true;}
    Reach=true;Why=TEXT("counter_reachable");return true;
}
ULivingTownCafeMealContactComponent* ULivingTownCafeWorldV3Subsystem::MealProvider()const{
    const auto* Pawn=SessionPawn.Get();return Pawn?Pawn->FindComponentByClass<ULivingTownCafeMealContactComponent>():nullptr;
}
bool ULivingTownCafeWorldV3Subsystem::StartPhysicalMeal(FString& Error){
    auto* Pawn=SessionPawn.Get();auto* Provider=MealProvider();
    if(!Pawn||!Provider||!Provider->ValidateRecipe(Pawn,Binding.BindingFileSha256,Error)){if(Error.IsEmpty())Error=TEXT("reviewed_eat_clip_contact_recipe_required");return false;}
    auto* Mesh=Pawn->GetMesh();auto* Player=Mesh?Mesh->GetSingleNodeInstance():nullptr;FLivingTownCafeMealClipRecipe R;
    if(!Player||!Provider->ReviewedRecipe(R)||!R.Clip||Utf8(R.RecipeFileSha256)!=State->Sources.world.clip_sha256||MealAnimationPlayer.IsValid()||!Mesh->bEnableAnimation||Mesh->bPauseAnims||!FMath::IsNearlyEqual(Mesh->GlobalAnimRateScale,1.f,.001f)){
        Error=TEXT("enabled_single_native_animation_owner_required");return false;
    }
    PreviousAnimation=Player->GetCurrentAsset();PreviousAnimationTime=Player->GetCurrentTime();PreviousAnimationPlayRate=Player->GetPlayRate();
    bPreviousLooping=Player->IsLooping();bPreviousPlaying=Player->IsPlaying();MealAnimationPlayer=Player;PlayingMealClip=R.Clip;
    // Keep the exact configured player and its custom proxy/configuration alive.
    // PlayAnimation/SetAnimationMode would replace the worker's root-corrected
    // player; switching its existing asset does not initialize another owner.
    Player->SetAnimationAsset(R.Clip,true,1.f);Player->SetPlaying(true);
    if(Mesh->GetSingleNodeInstance()!=Player||Player->GetCurrentAsset()!=R.Clip||!Player->IsPlaying()||!Player->IsLooping()||!FMath::IsNearlyEqual(Player->GetPlayRate(),1.f,.001f)||!Mesh->bEnableAnimation||Mesh->bPauseAnims||!FMath::IsNearlyEqual(Mesh->GlobalAnimRateScale,1.f,.001f)){
        Error=TEXT("actual_eat_playback_start_refused");StopPhysicalMeal();return false;
    }
    LastObservedClipTime=Player->GetCurrentTime();LastObservedWorldTime=GetWorld()->GetTimeSeconds();LastObservedBoneRevision=Mesh->GetBoneTransformRevisionNumber();bClipAdvancedThisFrame=false;
    if(!FMath::IsFinite(LastObservedClipTime)){Error=TEXT("actual_eat_playback_time_invalid");StopPhysicalMeal();return false;}return true;
}
void ULivingTownCafeWorldV3Subsystem::StopPhysicalMeal(){
    auto* Pawn=SessionPawn.Get();auto* Mesh=Pawn?Pawn->GetMesh():nullptr;auto* Player=MealAnimationPlayer.Get();
    // Restore our still-installed instance, including partial start failures.
    // A foreign replacement player is never overwritten. The original custom
    // instance's class, proxy and root-correction configuration were never reset.
    if(Mesh&&Player&&Mesh->GetSingleNodeInstance()==Player){
        Player->SetAnimationAsset(PreviousAnimation.Get(),bPreviousLooping,PreviousAnimationPlayRate);
        Player->SetPosition(PreviousAnimationTime,false);Player->SetPlaying(bPreviousPlaying);
    }
    PreviousAnimation=nullptr;PlayingMealClip.Reset();MealAnimationPlayer.Reset();bClipAdvancedThisFrame=false;
}
bool ULivingTownCafeWorldV3Subsystem::ObservePhysicalMeal(FString& Error){
    bClipAdvancedThisFrame=false;auto* Pawn=SessionPawn.Get();auto* Mesh=Pawn?Pawn->GetMesh():nullptr;auto* Player=MealAnimationPlayer.Get();auto* Clip=PlayingMealClip.Get();auto* Provider=MealProvider();
    if(!Mesh||!Player||!Clip||Mesh->GetSingleNodeInstance()!=Player||Player->GetCurrentAsset()!=Clip||!Provider||!Provider->ObserveContact(Pawn,Binding.BindingFileSha256,Error))return false;
    const double Now=GetWorld()->GetTimeSeconds(),Elapsed=Now-LastObservedWorldTime;const float Time=Player->GetCurrentTime(),Length=Clip->GetPlayLength();
    if(!FMath::IsFinite(Elapsed)||Elapsed<0||!FMath::IsFinite(Time)||!FMath::IsFinite(Length)||Length<=0||Time<0||Time>Length){Error=TEXT("actual_eat_playback_time_invalid");return false;}
    // Start and a second observer may share one natural frame. This supplies no
    // elapsed evidence and can never earn an authority contact tick.
    if(Elapsed==0)return true;
    const uint32 Revision=Mesh->GetBoneTransformRevisionNumber();
    if(Elapsed>.25||Elapsed>=Length||Revision==LastObservedBoneRevision){Error=TEXT("fresh_eat_playback_frame_required");return false;}
    double Advanced=double(Time)-LastObservedClipTime;
    if(Advanced<0&&Player->IsLooping())Advanced+=Length;
    // An observed tail-to-head wrap is valid only within this actual bounded
    // frame's time budget. Repeated, frozen, reversed, reset or multi-loop times
    // cannot masquerade as progression by retaining playing/rate/revision flags.
    if(Advanced<=0||FMath::Abs(Advanced-Elapsed)>.01){Error=TEXT("actual_eat_clip_time_did_not_advance");return false;}
    LastObservedClipTime=Time;LastObservedWorldTime=Now;LastObservedBoneRevision=Revision;bClipAdvancedThisFrame=true;return true;
}
FLivingTownCafeWorldReceipt ULivingTownCafeWorldV3Subsystem::SubmitMeal(const FLivingTownCafeMealCommand& C){
    if(!IsInGameThread()||!bPrepared||!State||!GetWorld()||GetWorld()->IsPaused())return Refused(TEXT("world_v3_live_unpaused_session_required"));
    bool Reach=false;FString Why;if(!ObserveCounter(Reach,Why))return Refused(Why);
    if(SessionController->GetNativePersona()!=ELivingTownCafeWorldPersona::Ben)return Refused(TEXT("meal_pilot_requires_ben"));
    if(C.Kind!=ELivingTownCafeMealKind::PurchaseMeal&&C.Kind!=ELivingTownCafeMealKind::PublicMeal)return Refused(TEXT("unknown_meal_kind"));
    const P::MealCommand Command{Utf8(C.RequestId),Utf8(C.SiteId),C.Kind==ELivingTownCafeMealKind::PurchaseMeal?P::MealKind::PurchaseMeal:P::MealKind::PublicMeal,C.ExpectedRevision};
    // Let the core return original receipts before attempting a new animation.
    bool Known=false;for(const auto& E:State->Kernel.events())if(E.meal_command&&E.meal_command->request_id==Command.request_id){Known=true;break;}
    bool ClipReady=false,Started=false;
    if(!Known&&Reach&&!State->Use.active()&&Command.expected_revision==State->Kernel.revision()&&Command.site_id==P::meal_site&&P::token(Command.request_id)){
        ClipReady=StartPhysicalMeal(Why);Started=ClipReady;
    }
    const P::MealContext At{"ben","ben",State->Clock,true,Reach,Reach,true,ClipReady};
    const auto R=P::begin_meal_use(State->Kernel,State->Use,Command,At);
    if(Started&&(!R.ok||R.already_applied))StopPhysicalMeal();
    FLivingTownCafeWorldReceipt Out;Out.bAccepted=R.ok;Out.bAlreadyApplied=R.already_applied;Out.Reason=Text(R.reason);Out.EventId=R.event_id;
    Out.Message=R.ok?(R.already_applied?TEXT("This meal request was already recorded."):TEXT("Meal started. Stay at the counter while Ben eats. X cancels.")):
        (R.reason=="qualified_meal_clip_required"?TEXT("Eating is not available yet. You have not been charged."):R.reason=="stale_world_revision"?TEXT("The cafe changed. Please try again."):R.reason=="meal_stock_unavailable"?TEXT("Today's meals have sold out."):!Reach?TEXT("Walk closer and face the cafe counter."):TEXT("The meal could not start. You have not been charged."));
    Notice=Out.Message;RefreshPresentation();return Out;
}
FLivingTownCafeWorldReceipt ULivingTownCafeWorldV3Subsystem::CancelMeal(){
    if(!IsInGameThread()||!bPrepared||!State||!SessionController.IsValid()||!SessionPawn.IsValid()||SessionController->GetNativePersona()!=ELivingTownCafeWorldPersona::Ben||SessionController->GetPawn()!=SessionPawn.Get())return Refused(TEXT("live_ben_session_required"));
    const auto R=P::cancel_meal_use(State->Kernel,State->Use);if(R.ok)StopPhysicalMeal();
    FLivingTownCafeWorldReceipt Out;Out.bAccepted=R.ok;Out.bAlreadyApplied=R.already_applied;Out.Reason=Text(R.reason);Out.EventId=R.event_id;
    Out.Message=R.ok?(R.already_applied?TEXT("There is no meal in progress."):TEXT("Meal cancelled. Progress earned so far is kept.")):TEXT("Unable to cancel this meal.");Notice=Out.Message;RefreshPresentation();return Out;
}
FLivingTownCafeWorldReceipt ULivingTownCafeWorldV3Subsystem::SubmitProperty(const FLivingTownCafePropertyCommand& C){
    return SubmitPropertyInternal(C,false,false,-1,-1);
}
FLivingTownCafeWorldReceipt ULivingTownCafeWorldV3Subsystem::SubmitRecurringLeaseOffer(const FString& RequestId){
    FLivingTownCafePropertyCommand C;C.RequestId=RequestId;C.Action=ELivingTownCafePropertyAction::OfferLease;
    return SubmitPropertyInternal(C,true,false,-1,-1);
}
FLivingTownCafeWorldReceipt ULivingTownCafeWorldV3Subsystem::SubmitLeaseAgreement(const FString& RequestId,bool bRecurring,int64 ObservedOfferRevision,int64 ObservedTitleRevision){
    FLivingTownCafePropertyCommand C;C.RequestId=RequestId;C.Action=ELivingTownCafePropertyAction::Lease;
    return SubmitPropertyInternal(C,false,bRecurring,ObservedOfferRevision,ObservedTitleRevision);
}
FLivingTownCafeWorldReceipt ULivingTownCafeWorldV3Subsystem::SubmitPropertyInternal(const FLivingTownCafePropertyCommand& C,bool bRecurringOffer,bool bRecurringAgreement,int64 ObservedOfferRevision,int64 ObservedTitleRevision){
    if(!IsInGameThread()||!bPrepared||!State||!GetWorld()||GetWorld()->IsPaused())return Refused(TEXT("world_v3_live_unpaused_session_required"));
    bool Reach=false;FString Why;if(!ObserveCounter(Reach,Why))return Refused(Why);
    try{
        const std::string Actor=Utf8(PersonaId(SessionController->GetNativePersona()));P::Kernel Candidate=State->Kernel;
        if(!bRecurringAgreement&&(ObservedOfferRevision!=-1||ObservedTitleRevision!=-1))return Refused(TEXT("invalid_lease_agreement"));
        P::Intent Intent{Utf8(C.RequestId),Utf8(C.PropertyId),bRecurringOffer?P::Action::offer_recurring_lease:Action(C.Action)};
        if(bRecurringAgreement){Intent.agreed_lease_kind="recurring_lease";Intent.expected_offer_revision=ObservedOfferRevision;Intent.expected_title_revision=ObservedTitleRevision;}
        const auto R=Candidate.execute(Intent,{Actor,Actor,"cafe","1f","cafe1f_counter",State->Clock,Reach});
        if(!P::care_matches_world(Candidate,State->Use)||!P::valid_clock_for(Candidate,{State->Clock,0}))return Refused(TEXT("paired_capacity_or_reconciliation_required"));
        State->Kernel=std::move(Candidate);FLivingTownCafeWorldReceipt Out;Out.bAccepted=R.ok;Out.bAlreadyApplied=R.already_applied;Out.Reason=Text(R.reason);Out.EventId=R.event_id;
        Out.Message=R.ok?(bRecurringOffer?TEXT("Recurring lease offered: 4 coins every 12 minutes. The tenant can end future payments."):bRecurringAgreement?TEXT("Recurring lease agreed. 4 coins paid; next rent in 12 minutes."):TEXT("Property action recorded.")):!Reach?TEXT("Walk closer and face the cafe counter."):R.reason=="recurring_agreement_required"||R.reason=="agreement_changed"?TEXT("The lease offer changed. Check its terms and try again."):TEXT("That property action is unavailable for this resident or listing.");Notice=Out.Message;RefreshPresentation();return Out;
    }catch(const std::exception&){return Refused(TEXT("world_property_authority_exception"));}
}
bool ULivingTownCafeWorldV3Subsystem::AdvanceNaturalClock(int64 Whole,bool bContinuous,FString& Error){
    Error.Reset();if(!State||Whole<=0||State->Clock>P::max_tick-Whole){Error=TEXT("invalid_natural_clock");return false;}
    auto Candidate=State->Kernel;auto Use=State->Use;const int64 Next=State->Clock+Whole;
    if(Use.active()&&!bContinuous){const auto R=P::cancel_meal_use(Candidate,Use,P::ReleaseReason::Interrupted);if(!R.ok){Error=Text(R.reason);return false;}}
    const auto Due=Candidate.reconcile_property_until(Next);if(!Due.ok){Error=TEXT("natural_property_reconciliation_refused");return false;}
    if(Use.active()){
        // At most one contact sample from this actual frame. No loop reuses it.
        bool Reach=false;FString Why;const bool Scene=ObserveCounter(Reach,Why);auto* Provider=MealProvider();
        const bool Contact=Scene&&Reach&&bClipAdvancedThisFrame&&Provider&&Provider->ObserveContact(SessionPawn.Get(),Binding.BindingFileSha256,Why);
        const auto& A=Use.active()->grant;bool Reservation=false,Permission=false;
        for(const auto& G:Candidate.care_grants())if(G.active&&G.event_id==A.grant_event_id&&G.resident==A.resident_id&&G.site_id==A.site_id){Reservation=true;Permission=G.provider==Candidate.operator_at(Next);}
        const Care::Contact Observed{A.resident_id,A.site_id,A.grant_id,Scene,Scene&&Reach,Contact,Permission,Reservation};
        const auto R=P::advance_meal_use(Candidate,Use,Next,Observed);if(!R.ok){Error=Text(R.reason);return false;}
        if(R.outcome==Care::Outcome::Completed)Notice=TEXT("Meal finished. Ben feels better and had a little fun.");
        else if(R.outcome==Care::Outcome::Interrupted)Notice=TEXT("Meal interrupted. Progress earned so far is kept.");
    }else if(!Use.advance_idle_to(Next)){Error=TEXT("idle_care_clock_refused");return false;}
    if(!P::care_matches_world(Candidate,Use)||!P::valid_clock_for(Candidate,{Next,0})){Error=TEXT("natural_care_reconciliation_failed");return false;}
    State->Kernel=std::move(Candidate);State->Use=std::move(Use);State->Clock=Next;
    if(Due.reason=="rent_paid")Notice=TEXT("Rent paid: 4 coins. The cafe lease continues.");
    else if(Due.reason=="rent_unpaid")Notice=TEXT("The next rent could not be paid. No payment was taken for that period; the cafe lease ended.");
    else if(Due.reason=="term_limit_reached")Notice=TEXT("The cafe lease reached its final term and ended.");
    if(!State->Use.active())StopPhysicalMeal();return true;
}
void ULivingTownCafeWorldV3Subsystem::Tick(float Delta){
    Super::Tick(Delta);if(!bPrepared||!State||!GetWorld())return;
    if(GetWorld()->IsPaused()){
        if(State->Use.active()){P::cancel_meal_use(State->Kernel,State->Use,P::ReleaseReason::Interrupted);StopPhysicalMeal();Notice=TEXT("Meal interrupted while paused. Progress is kept.");RefreshPresentation();}return;
    }
    if(!FMath::IsFinite(Delta)||Delta<0||Delta>3600){P::cancel_meal_use(State->Kernel,State->Use,P::ReleaseReason::Interrupted);StopPhysicalMeal();Notice=TEXT("The cafe clock stopped. Reload the scenario to continue.");bPrepared=false;RefreshPresentation();return;}
    const double Accumulated=ClockRemainder+double(Delta);const int64 Whole=int64(FMath::FloorToDouble(Accumulated));
    // Check contact on every live frame, including frames without an authority
    // tick. A lost session/reach/pose cannot disappear between sampled seconds.
    bool Continuous=Delta<=.25f&&Whole<=1;FString Why;
    if(State->Use.active()){
        bool Reach=false;
        Continuous=Continuous&&ObserveCounter(Reach,Why)&&Reach&&ObservePhysicalMeal(Why);
        if(!Continuous){const auto R=P::cancel_meal_use(State->Kernel,State->Use,P::ReleaseReason::Interrupted);if(!R.ok){Notice=TEXT("Meal interruption could not be recorded.");bPrepared=false;RefreshPresentation();return;}StopPhysicalMeal();Notice=TEXT("Meal interrupted. Progress earned so far is kept.");}
    }
    if(Whole>0&&!AdvanceNaturalClock(Whole,Continuous,Why)){Notice=TEXT("The cafe clock stopped. Reload the scenario to continue.");bPrepared=false;StopPhysicalMeal();RefreshPresentation();return;}
    ClockRemainder=Accumulated-double(Whole);RefreshPresentation();
}
void ULivingTownCafeWorldV3Subsystem::RefreshPresentation(){
    Presentation={};auto& V=Presentation;V.bPrepared=bPrepared;V.Notice=Notice;V.Prompt=TEXT("Cafe interaction is unavailable.");if(!bPrepared||!State)return;
    V.bSessionReady=SessionController.IsValid()&&SessionController->HasNativePersona()&&SessionPawn.IsValid();V.Persona=V.bSessionReady?PersonaId(SessionController->GetNativePersona()):TEXT("choose resident");
    V.Owner=Text(State->Kernel.title().owner);V.Operator=Text(State->Kernel.operator_at(State->Clock));V.AriaCoins=State->Kernel.coin("aria");V.BenCoins=State->Kernel.coin("ben");V.Clock=State->Clock;V.Revision=State->Kernel.revision();V.Stock=State->Kernel.rations();V.Hunger=State->Use.needs().hunger;V.Fun=State->Use.needs().fun;
    V.bMealActive=bool(State->Use.active());if(V.bMealActive)V.ProgressTicks=State->Use.active()->elapsed;
    FString Why;ObserveCounter(V.bReachable,Why);V.Diagnostic=Why;
    // Recipe presence is an availability hint only. Submission independently
    // validates source bytes and the natural ticks observe actual animation.
    FLivingTownCafeMealClipRecipe Recipe;auto* Provider=MealProvider();V.bMealAvailable=V.Persona==TEXT("ben")&&Provider&&Provider->ReviewedRecipe(Recipe)&&Recipe.Clip;
    const auto Name=[](const FString& S){return S==TEXT("aria")?FString(TEXT("Aria")):S==TEXT("ben")?FString(TEXT("Ben")):FString(TEXT("Choose a resident"));};
    V.ResidentLabel=Name(V.Persona);if(V.bSessionReady)V.ResidentLabel+=FString::Printf(TEXT("  |  %lld coins"),(long long)(V.Persona==TEXT("aria")?V.AriaCoins:V.BenCoins));
    V.PropertyLabel=TEXT("Owned by ")+Name(V.Owner)+TEXT("  |  Run by ")+Name(V.Operator);
    const auto& Offer=State->Kernel.offer();const auto& Terms=State->Kernel.terms();
    V.bRecurringOffer=Offer.present&&!State->Kernel.lease().active&&Offer.kind=="recurring_lease";V.OfferRevision=Offer.revision;V.OfferTitleRevision=Offer.title_revision;
    V.bRecurringLease=State->Kernel.recurring_lease();V.RentAmount=V.bRecurringLease||V.bRecurringOffer?Terms.lease_fee:0;
    V.RentDueTick=V.bRecurringLease?State->Kernel.lease().end:-1;
    if(V.bRecurringLease){const int64 Left=FMath::Max<int64>(0,V.RentDueTick-State->Clock);V.ListingLabel=FString::Printf(TEXT("Rent: 4 coins / 12 min | Next in %lld:%02lld"),(long long)(Left/60),(long long)(Left%60));}
    else V.ListingLabel=State->Kernel.lease().active?TEXT("Fixed lease active"):!Offer.present?TEXT("No property listing"):Offer.kind=="sale"?FString::Printf(TEXT("For sale: %lld coins"),(long long)Terms.sale_price):V.bRecurringOffer?TEXT("Recurring lease: 4 coins / 12 min | K Agree"):FString::Printf(TEXT("Fixed lease: %lld coins / 12 min"),(long long)Terms.lease_fee);
    const FString Price=V.Persona==V.Operator?TEXT("Own meal stock"):TEXT("Meal: 2 coins");
    V.MealLabel=Price+FString::Printf(TEXT("  |  %lld left  |  Ben hunger %.2f  fun %.2f"),(long long)V.Stock,V.Hunger/100.f,V.Fun/100.f);
    V.Prompt=V.bMealActive?FString::Printf(TEXT("Eating %d / 18  |  X Cancel"),V.ProgressTicks):!V.bSessionReady?TEXT("Choose Ben or Aria."):!V.bReachable?TEXT("Walk closer and face the cafe counter."):V.Persona==TEXT("aria")?TEXT("O Sale | L Fixed lease | N Recurring lease | R End lease"):!V.bMealAvailable?TEXT("Eating is not available yet. E checks availability."):TEXT("E Eat a meal  |  B Buy property  |  K Lease  |  R End lease");
}
namespace {
// Native outer envelope adds SHA256 and atomic disk custody to the portable V4
// replay. Every binding includes the exact source-bound native appearance/scene.
FString Fingerprint(std::initializer_list<FString> Fields){P::detail::Writer W;for(const auto& F:Fields)W.s(Utf8(F));FString H;LivingTownCafeJournal::Sha256(Bytes(W.bytes),H);return H;}
P::CareBindings CareSources(const FLivingTownCafeBinding& B){
    P::CareBindings Out;Out.world.core_sha256=Utf8(CoreHash);Out.care_core_sha256=Utf8(CareHash);
    Out.world.fixture_sha256=Utf8(Fingerprint({RosterHash,ConfigHash,EnvelopeHashSource,TEXT("native_cafe_world_rent_v5_adapter_v1")}));
    Out.world.physical_sha256=Utf8(Fingerprint({B.BindingFileSha256,B.PhysicalSceneSha256,B.PhysicalQualificationSha256,B.VisualSha256}));
    // This is the fingerprint of an UNAVAILABLE provider policy, not an eat
    // certificate. It never authorizes a clip. An eventual reviewed producer
    // must source-bind its authored recipe before meals can be accepted.
    Out.world.clip_sha256=Utf8(Fingerprint({TEXT("no_reviewed_native_eat_provider_v1")}));
    Out.world.roster_sha256=Utf8(RosterHash);return Out;
}
bool ReadMealSource(const FLivingTownCafeBinding& B,P::CareBindings& Sources,FString& Error){
    Sources=CareSources(B);const FString Path=FPaths::ProjectContentDir()/TEXT("LivingTown/CafeWorldV3MealContact.json");
    if(!IFileManager::Get().FileExists(*Path))return true;
    const int64 Size=IFileManager::Get().FileSize(*Path);TArray<uint8> Data;FString Json,H;
    if(Size<=0||Size>64*1024||!FFileHelper::LoadFileToArray(Data,*Path)||!LivingTownCafeJournal::Sha256(Data,H)){Error=TEXT("meal_recipe_source_unreadable");return false;}
    FFileHelper::BufferToString(Json,Data.GetData(),Data.Num());TSharedPtr<FJsonObject> O;
    if(!LivingTownCafeJournal::HasUniqueObjectKeys(Json)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),O)||!O||!Keys(*O,{TEXT("format"),TEXT("version"),TEXT("binding_sha256"),TEXT("clip_asset"),TEXT("mesh_asset"),TEXT("clip_sha256"),TEXT("contact_certificate_sha256"),TEXT("hand_socket"),TEXT("mouth_socket"),TEXT("max_contact_distance_cm")})){Error=TEXT("meal_recipe_source_schema_required");return false;}
    FString F,V,BindingSha,Clip,Mesh,ClipSha,Certificate,Hand,Mouth;double Distance=0;
    if(!String(*O,TEXT("format"),F)||F!=TEXT("LivingTown.CafeWorldV3.MealContact")||!String(*O,TEXT("version"),V)||V!=TEXT("1")||!String(*O,TEXT("binding_sha256"),BindingSha)||BindingSha!=B.BindingFileSha256||!String(*O,TEXT("clip_asset"),Clip)||!Clip.StartsWith(TEXT("/Game/"))||!String(*O,TEXT("mesh_asset"),Mesh)||Mesh!=B.VisualAssetPath||!String(*O,TEXT("clip_sha256"),ClipSha)||!P::sha_token(Utf8(ClipSha))||!String(*O,TEXT("contact_certificate_sha256"),Certificate)||!P::sha_token(Utf8(Certificate))||!String(*O,TEXT("hand_socket"),Hand)||Hand.IsEmpty()||!String(*O,TEXT("mouth_socket"),Mouth)||Mouth.IsEmpty()||Hand==Mouth||!O->TryGetNumberField(TEXT("max_contact_distance_cm"),Distance)||!FMath::IsFinite(Distance)||Distance<=0||Distance>15){Error=TEXT("meal_recipe_source_binding_required");return false;}
    Sources.world.clip_sha256=Utf8(H);return true;
}
bool NativeEnvelopeHash(const FJsonObject& O,FString& Out){
    P::detail::Writer W;for(const TCHAR* K:{TEXT("format"),TEXT("version"),TEXT("capability"),TEXT("source_sha256"),TEXT("payload_sha256"),TEXT("payload_base64")}){
        FString V;if(!String(O,K,V))return false;W.s(Utf8(FString(K)));W.s(Utf8(V));
    }return LivingTownCafeJournal::Sha256(Bytes(W.bytes),Out);
}
FString NativeSourceHash(const P::CareBindings& Sources){P::detail::Writer W;P::write_bindings(W,Sources.world);W.s(Sources.care_core_sha256);FString H;LivingTownCafeJournal::Sha256(Bytes(W.bytes),H);return H;}
P::CareBindings LegacyV4Sources(const P::CareBindings& Current){
    auto Legacy=Current;
    Legacy.world.core_sha256="4856df21feca1d51d357454cee2047e4de19e4ffa7c16aa57d459f6f0793e903";
    Legacy.world.fixture_sha256=Utf8(Fingerprint({RosterHash,ConfigHash,TEXT("0cf5fca9a0f91fbaedfa83ab8e786f5022733aa33a56ea8f954d244bb9bd2690"),TEXT("native_cafe_world_v3_adapter_v1")}));
    // Exact current physical/visual/roster/recipe bindings remain required.
    return Legacy;
}
}
FString ULivingTownCafeWorldV3Subsystem::SlotPath()const{return FPaths::ProjectSavedDir()/TEXT("CafeWorldV3/CafeWorldRentCareV5.slot.json");}
bool ULivingTownCafeWorldV3Subsystem::EncodeJournal(FString& Json,FString& Error)const{
    Json.Reset();Error.Reset();bool Reach=false;FString Why;
    if(!IsInGameThread()||!bPrepared||!State||!ObserveCounter(Reach,Why)){Error=Why.IsEmpty()?TEXT("source_bound_native_world_session_required"):Why;return false;}
    uint64 Bits=0;FMemory::Memcpy(&Bits,&ClockRemainder,sizeof(Bits));
    const auto Encoded=P::save_care_envelope(State->Kernel,State->Use,State->Sources,{State->Clock,Bits},Utf8(PersonaId(SessionController->GetNativePersona())));
    if(!Encoded){Error=TEXT("paired_v5_source_or_replay_refused_save");return false;}
    const auto Payload=Bytes(*Encoded);FString Hash;if(!LivingTownCafeJournal::Sha256(Payload,Hash)){Error=TEXT("world_payload_hash_failed");return false;}
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("format"),TEXT("LivingTown.CafeWorldMealCare.NativeJournal"));O->SetStringField(TEXT("version"),TEXT("5"));O->SetStringField(TEXT("capability"),TEXT("cafe.world_rent_care.v5"));O->SetStringField(TEXT("source_sha256"),NativeSourceHash(State->Sources));O->SetStringField(TEXT("payload_sha256"),Hash);O->SetStringField(TEXT("payload_base64"),FBase64::Encode(Payload));
    FString EnvelopeHash;if(!NativeEnvelopeHash(*O,EnvelopeHash)){Error=TEXT("world_envelope_hash_failed");return false;}O->SetStringField(TEXT("envelope_sha256"),EnvelopeHash);
    if(!FJsonSerializer::Serialize(O,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Json))||Json.Len()>MaxEnvelopeBytes){Error=TEXT("world_envelope_encoding_failed");return false;}return true;
}
bool ULivingTownCafeWorldV3Subsystem::LoadJournal(const FString& Json,FString& Error){
    return DecodeJournal(Json,false,Error);
}
bool ULivingTownCafeWorldV3Subsystem::ImportLegacyV4Journal(const FString& Json,FString& Error){
    return DecodeJournal(Json,true,Error);
}
bool ULivingTownCafeWorldV3Subsystem::DecodeJournal(const FString& Json,bool bLegacyImport,FString& Error){
    Error.Reset();auto Fail=[&](const TCHAR* Why){Error=Why;return false;};bool Reach=false;FString Why;
    if(!IsInGameThread()||!bPrepared||!State||!ObserveCounter(Reach,Why))return Fail(TEXT("source_bound_native_world_session_required"));
    if(Json.Len()>MaxEnvelopeBytes||!LivingTownCafeJournal::HasUniqueObjectKeys(Json))return Fail(TEXT("world_envelope_size_or_duplicate_fields"));
    TSharedPtr<FJsonObject> O;if(!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),O)||!O||!Keys(*O,{TEXT("format"),TEXT("version"),TEXT("capability"),TEXT("source_sha256"),TEXT("payload_sha256"),TEXT("payload_base64"),TEXT("envelope_sha256")}))return Fail(TEXT("world_envelope_schema_required"));
    const auto Equal=[&](const TCHAR* K,const FString& Expected){FString V;return String(*O,K,V)&&V==Expected;};
    const auto Expected=bLegacyImport?LegacyV4Sources(State->Sources):State->Sources;
    FString H;if(!NativeEnvelopeHash(*O,H)||!Equal(TEXT("envelope_sha256"),H)||!Equal(TEXT("format"),TEXT("LivingTown.CafeWorldMealCare.NativeJournal"))||!Equal(TEXT("version"),bLegacyImport?TEXT("4"):TEXT("5"))||!Equal(TEXT("capability"),bLegacyImport?TEXT("cafe.world_meal_care.v4"):TEXT("cafe.world_rent_care.v5"))||!Equal(TEXT("source_sha256"),NativeSourceHash(Expected)))return Fail(TEXT("world_envelope_sha_version_or_source_mismatch"));
    FString Encoded,PayloadHash;TArray<uint8> Payload;
    if(!String(*O,TEXT("payload_base64"),Encoded)||!String(*O,TEXT("payload_sha256"),PayloadHash)||!FBase64::Decode(Encoded,Payload)||Payload.IsEmpty()||Payload.Num()>int32(P::max_paired_bytes)||FBase64::Encode(Payload)!=Encoded||!LivingTownCafeJournal::Sha256(Payload,H)||PayloadHash!=H)return Fail(TEXT("world_payload_bytes_or_sha_mismatch"));
    auto Candidate=State->Kernel;auto Use=State->Use;P::ClockMetadata Clock;
    const std::string Raw(reinterpret_cast<const char*>(Payload.GetData()),size_t(Payload.Num()));
    const bool Loaded=bLegacyImport?P::import_legacy_care_envelope(Candidate,Use,Raw,Expected,Clock):P::load_care_envelope(Candidate,Use,Raw,Expected,Clock);
    if(!Loaded)return Fail(TEXT("paired_strict_replay_or_binding_mismatch"));
    double Fraction=0;FMemory::Memcpy(&Fraction,&Clock.fraction_bits,sizeof(Fraction));
    // Publication occurs only after both independent replays, source/clock and
    // reservations reconcile; saved persona/position/observations grant nothing.
    StopPhysicalMeal();State->Kernel=std::move(Candidate);State->Use=std::move(Use);State->Clock=Clock.tick;ClockRemainder=Fraction;
    Notice=bLegacyImport?TEXT("Older cafe save imported. Fixed leases stay fixed. Previous meals stay stopped; earned progress is kept."):TEXT("Cafe restored. Previous meals stay stopped; earned progress is kept. Your resident and position are unchanged.");RefreshPresentation();return true;
}
bool ULivingTownCafeWorldV3Subsystem::SaveSlot(FString& Error,FString* SavedSha)const{
    FString Json;if(!EncodeJournal(Json,Error)||!LivingTownCafeSlot::WriteAtomic(SlotPath(),Json,Error))return false;
    TArray<uint8> Written;FString Hash,Readback;if(!FFileHelper::LoadFileToArray(Written,*SlotPath())||!FFileHelper::LoadFileToString(Readback,*SlotPath())||Readback!=Json||!LivingTownCafeJournal::Sha256(Written,Hash)){Error=TEXT("atomic_world_slot_final_readback_or_sha_failed");return false;}if(SavedSha)*SavedSha=Hash;return true;
}
bool ULivingTownCafeWorldV3Subsystem::LoadSlot(FString& Error){
    if(!IsInGameThread()){Error=TEXT("wrong_thread");return false;}const FString Path=SlotPath();const int64 Size=IFileManager::Get().FileSize(*Path);
    if(Size<=0||Size>MaxEnvelopeBytes){Error=TEXT("world_slot_missing_or_oversize");return false;}FString Json;if(!FFileHelper::LoadFileToString(Json,*Path)){Error=TEXT("world_slot_read_failed");return false;}return LoadJournal(Json,Error);
}
bool ULivingTownCafeWorldV3Subsystem::ImportLegacyV4Slot(FString& Error){
    if(!IsInGameThread()){Error=TEXT("wrong_thread");return false;}
    const FString Path=FPaths::ProjectSavedDir()/TEXT("CafeWorldV3/CafeWorldMealCareV4.slot.json");const int64 Size=IFileManager::Get().FileSize(*Path);
    if(Size<=0||Size>MaxEnvelopeBytes){Error=TEXT("older_world_slot_missing_or_oversize");return false;}
    FString Json;if(!FFileHelper::LoadFileToString(Json,*Path)){Error=TEXT("older_world_slot_read_failed");return false;}
    return ImportLegacyV4Journal(Json,Error);
}
