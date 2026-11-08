// Current-world property journey and MetaHuman meal-provider lifecycle checks.
#include "LivingTownCafeWorldV3Scenario.h"
#include "LivingTownCafeWorldV3Subsystem.h"
#include "LivingTownCafePropertyV2Scenario.h"
#include "LivingTownCafePropertyV2Subsystem.h"
#include "LivingTownCafeProjectionSubsystem.h"
#include "LivingTownLeaseSubsystem.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownCafeVenue.h"
#include "LivingTownFullTownDriver.h"
#include "LivingTownFullTownStreamingSubsystem.h"
#include "LivingTownMetaHumanVisualAssembly.h"
#include "LivingTownMetaHumanMealProducer.h"
#include "../../ThirdParty/CafeWorldV3Envelope.hpp"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Tests/AutomationCommon.h"
#include "Engine/Engine.h"
#include "Engine/GameInstance.h"
#include "Engine/World.h"
#include "Engine/EngineBaseTypes.h"
#include "Dom/JsonValue.h"
#include "Engine/StaticMesh.h"
#include "EngineUtils.h"
#include "Components/CapsuleComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformTime.h"
#include "InputCoreTypes.h"
#include "InputKeyEventArgs.h"
#include "Misc/Base64.h"
#include "Misc/CommandLine.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "UObject/Package.h"

// Test-only friendship reads actual state without owning a shared load handle,
// injecting readiness, changing epochs, or adding a public production API.
struct FWorldV3MealProviderLifecycleTestAccess {
    struct Snapshot {uint64 Epoch;const void* Handle;bool RolesReady,ExplicitlyNull,Stale;const ACharacter* Pawn;};
    static Snapshot Read(const ULivingTownCafeWorldV3Subsystem* A){return {A->MealPreloadEpoch,A->MealPreload.Get(),A->bMealRolesReady,A->SessionPawn.IsExplicitlyNull(),A->SessionPawn.IsStale(),A->SessionPawn.Get()};}
};
namespace {
namespace W3=living_town::cafe_world_v3;
constexpr TCHAR PropertyRoot[]=TEXT("/Game/LivingTown_UEPilot/FullTownWorldV3_289_v001/L_FullTownWorldV3_289_v001");
constexpr TCHAR BindingSha[]=TEXT("38171606986ba5086102aeba31927fac698558eebed861dd0f4d8eaf713fad6e");
constexpr TCHAR RouteSha[]=TEXT("38d98ee0c968647be6a1a89eac2abfe7c4b8a65b8732248f62fd3e7f54113846");

bool ReadRoute(TArray<FVector>& Route) {
    const FString Path=FPaths::ProjectContentDir()/TEXT("LivingTown/CafeJourneyRoute.json");
    TArray<uint8> Bytes;FString Sha,Text,Binding;TSharedPtr<FJsonObject> O;const TArray<TSharedPtr<FJsonValue>>* Points=nullptr;
    if(!FFileHelper::LoadFileToArray(Bytes,*Path)||!LivingTownCafeJournal::Sha256(Bytes,Sha)||Sha!=RouteSha||
        !FFileHelper::LoadFileToString(Text,*Path)||!LivingTownCafeJournal::HasUniqueObjectKeys(Text)||
        !FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),O)||!O||
        !O->TryGetStringField(TEXT("physical_binding_sha256"),Binding)||Binding!=BindingSha||
        !O->TryGetArrayField(TEXT("route_feet_cm"),Points)||Points->Num()!=3)return false;
    for(const auto& Point:*Points){
        if(!Point||Point->Type!=EJson::Array||Point->AsArray().Num()!=3)return false;
        double XYZ[3];for(int32 I=0;I<3;++I)if(!Point->AsArray()[I]||Point->AsArray()[I]->Type!=EJson::Number||!FMath::IsFinite(XYZ[I]=Point->AsArray()[I]->AsNumber()))return false;
        Route.Add(FVector(XYZ[0],XYZ[1],XYZ[2]));
    }
    return true;
}
bool ReadDocument(const FString& Text,W3::Kernel& K,W3::CareEnvelope* Out=nullptr,FString* Diagnostic=nullptr) {
    auto Fail=[&](const TCHAR* Why){if(Diagnostic)*Diagnostic=Why;return false;};if(Diagnostic)Diagnostic->Reset();
    FString Encoded,ExpectedHash,ActualHash;TArray<uint8> Bytes;TSharedPtr<FJsonObject> O;
    if(!LivingTownCafeJournal::HasUniqueObjectKeys(Text))return Fail(TEXT("native_json_duplicate_keys"));
    if(!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),O)||!O)return Fail(TEXT("native_json_parse"));
    if(!O->TryGetStringField(TEXT("payload_base64"),Encoded)||!O->TryGetStringField(TEXT("payload_sha256"),ExpectedHash))return Fail(TEXT("native_payload_fields"));
    if(!FBase64::Decode(Encoded,Bytes)||Bytes.IsEmpty()||FBase64::Encode(Bytes)!=Encoded)return Fail(TEXT("native_payload_base64"));
    if(!LivingTownCafeJournal::Sha256(Bytes,ActualHash)||ActualHash!=ExpectedHash)return Fail(TEXT("native_payload_sha256"));
    const auto Envelope=W3::decode_care_envelope_document(std::string(reinterpret_cast<const char*>(Bytes.GetData()),size_t(Bytes.Num())));
    if(!Envelope)return Fail(TEXT("portable_care_envelope_decode"));
    if(!K.restore_bytes(Envelope->world_payload))return Fail(TEXT("portable_world_strict_replay"));
    if(Out)*Out=*Envelope;return true;
}
bool ReadWorld(ULivingTownCafeWorldV3Subsystem* A,W3::Kernel& K,W3::CareEnvelope* Out=nullptr,FString* Diagnostic=nullptr) {
    FString Text,Error;if(!A||!A->EncodeJournal(Text,Error)){if(Diagnostic)*Diagnostic=TEXT("EncodeJournal: ")+Error;return false;}return ReadDocument(Text,K,Out,Diagnostic);
}
int32 Count(const W3::Kernel& K,const char* Type){int32 N=0;for(const auto& E:K.events())if(E.type==Type)++N;return N;}

// An ordinary engine-scheduled read callback, never a manually executed tick.
struct FPropertyInputReadTick final:public FTickFunction {
    TFunction<void()> ReadOnly;
    FPropertyInputReadTick(){bCanEverTick=true;bStartWithTickEnabled=true;bRunOnAnyThread=false;TickGroup=TG_PostUpdateWork;EndTickGroup=TG_PostUpdateWork;}
    void ExecuteTick(float,ELevelTick,ENamedThreads::Type,const FGraphEventRef&)override{if(ReadOnly)ReadOnly();}
    FString DiagnosticMessage()override{return TEXT("LivingTown property test post-input read");}
    FName DiagnosticContext(bool)override{return FName(TEXT("LivingTownPropertyInputRead"));}
};
class FCurrentTownPropertyJourney final:public IAutomationLatentCommand {
    FAutomationTestBase* Test;TArray<FVector> Route;
    const double Deadline=FPlatformTime::Seconds()+420.;
    int32 Stage=0,Waypoint=1,RouteSamples=0,CompletedApproaches=0,CensusSamples=0;
    uint32 WorldId=0,ControllerId=0;double Epoch=-1,LastWalkTime=-1,WalkCm=0,LegStart=-1,StageTime=0;
    FVector LastFeet=FVector::ZeroVector;bool Held=false,Settling=false,Done=false;
    TWeakObjectPtr<ALivingTownCafeWorldV3Controller> Controller;
    std::string SavedWorld;FString SlotSha;int64 OpeningStock=-1,ExpectedStock=-1;
    W3::ClockMetadata SavedClock;double ProbeStarted=0;bool EntryWindow=false;
    FString ExpectedRecipeSha,ProbeFailure;bool FreshEntrySeen=false,FailedCandidateRetained=false;
    uint64 ProbeInputFrame=0,FreshEntryFrame=0;double FreshEntryWorldSeconds=-1;
    bool InitialBindObserved=false,InitialBindHadHandle=false,InitialBindRolesReady=false,PendingRebindObserved=false;
    uint64 InitialBindEpoch=0;
    uint32 FirstProviderId=0,ReacquiredProviderId=0,FinalProviderId=0;
    TWeakObjectPtr<ULivingTownMetaHumanMealProducer> FirstProvider,ReacquiredProvider;
    TWeakObjectPtr<AActor> TemporaryBlocker;
    FDelegateHandle ProviderObserver;
    TSharedPtr<FJsonObject> LatestTownStatus;
    FPropertyInputReadTick InputReadTick;FDelegateHandle WorldCleanup;
    TWeakObjectPtr<UWorld> ObservedWorld;
    // Test observations only: no gameplay readiness or movement state is injected.
    TWeakObjectPtr<ACharacter> GroundPawn;
    TWeakObjectPtr<UCharacterMovementComponent> GroundMovement;
    TSharedPtr<FJsonObject> GroundApproach;
    TArray<TSharedPtr<FJsonValue>> GroundSamples,GroundApproaches;
    uint64 GroundStartFrame=0,GroundObservedFrame=MAX_uint64;
    double GroundStartWorld=-1,GroundStartWall=0,GroundObservedWorld=-1;
    FVector GroundObservedFeet=FVector::ZeroVector;
    double GroundObservedSpeedXY=0;
    bool GroundAcquired=false,GroundObservedIdentity=false,GroundObservedSupport=false,GroundHistoryOverflow=false,GroundPrerequisiteBound=false,GroundObservedTickReady=false;
    uint64 GroundPrerequisiteFrame=MAX_uint64;
    static constexpr int32 MaxGroundSamples=1024;
    struct FQueuedTap {
        FKey Key;FString Label,ReadError,Notice;bool Active=false,Observed=false,ReadOK=false,PressReturn=false,ReleaseReturn=false,Physical=false;
        uint64 SentFrame=0,ObservedFrame=0;double SentWorld=-1,ObservedWorld=-1,SentWall=0;
        TWeakObjectPtr<APawn> PawnBefore,PawnAfter;FTransform BeforeTransform,AfterTransform;FRotator BeforeControl,AfterControl;
        FLivingTownCafeWorldView View;W3::Kernel Kernel{};W3::CareEnvelope Envelope;int64 BeforeEvents=0;
    } Queued;
    TArray<TSharedPtr<FJsonValue>> InputObservations;
    FString SlotPath()const{return FPaths::ProjectSavedDir()/TEXT("CafeWorldV3/CafeWorldResidentialCareV6.slot.json");}
    TSharedRef<FJsonObject> TapDiagnostic()const {
        auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("scope"),TEXT("Actual simulated key submission and ordinary post-controller/pre-source-clock read; no manual tick or action bypass"));
        O->SetStringField(TEXT("action"),Queued.Label);O->SetStringField(TEXT("key"),Queued.Key.ToString());O->SetBoolField(TEXT("active"),Queued.Active);O->SetBoolField(TEXT("observed"),Queued.Observed);
        O->SetBoolField(TEXT("submission_recorded"),!Queued.Label.IsEmpty());if(!Queued.Label.IsEmpty()){O->SetStringField(TEXT("submitted_frame"),LexToString(Queued.SentFrame));O->SetNumberField(TEXT("submitted_world_seconds"),Queued.SentWorld);}
        O->SetBoolField(TEXT("press_return_is_not_dispatch_ack"),Queued.PressReturn);O->SetBoolField(TEXT("release_return_is_not_dispatch_ack"),Queued.ReleaseReturn);
        if(Queued.Observed){O->SetStringField(TEXT("observed_frame"),LexToString(Queued.ObservedFrame));O->SetNumberField(TEXT("observed_world_seconds"),Queued.ObservedWorld);O->SetBoolField(TEXT("both_actual_key_events_observed"),true);O->SetBoolField(TEXT("journal_read_ok"),Queued.ReadOK);O->SetStringField(TEXT("journal_error"),Queued.ReadError);O->SetStringField(TEXT("operation_notice"),Queued.Notice);}
        if(Queued.Observed&&Queued.ReadOK){O->SetStringField(TEXT("captured_persona"),Queued.View.Persona);O->SetStringField(TEXT("captured_clock_tick"),LexToString(Queued.Envelope.clock.tick));O->SetStringField(TEXT("captured_fraction_bits"),LexToString(Queued.Envelope.clock.fraction_bits));O->SetStringField(TEXT("captured_aria_coins"),LexToString(Queued.View.AriaCoins));O->SetStringField(TEXT("captured_ben_coins"),LexToString(Queued.View.BenCoins));O->SetStringField(TEXT("captured_owner"),Queued.View.Owner);O->SetStringField(TEXT("captured_operator"),Queued.View.Operator);O->SetStringField(TEXT("captured_stock"),LexToString(Queued.View.Stock));O->SetNumberField(TEXT("captured_event_count"),double(Queued.Kernel.events().size()));O->SetNumberField(TEXT("captured_pay_count"),Count(Queued.Kernel,"pay"));if(!Queued.Kernel.events().empty()){O->SetStringField(TEXT("captured_last_event_type"),UTF8_TO_TCHAR(Queued.Kernel.events().back().type.c_str()));O->SetStringField(TEXT("captured_last_event_note"),UTF8_TO_TCHAR(Queued.Kernel.events().back().note.c_str()));}}
        return O;
    }
    FString FailureDiagnostic(const TCHAR* Why){
        ReadApproachGround(true);
        auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("FAIL_RETAINED_CURRENT_PROPERTY_ASSERTION"));O->SetNumberField(TEXT("stage"),Stage);O->SetStringField(TEXT("predicate"),Why);O->SetStringField(TEXT("current_frame"),LexToString(GFrameCounter));O->SetObjectField(TEXT("queued_input"),TapDiagnostic());O->SetArrayField(TEXT("completed_input_observations"),InputObservations);O->SetArrayField(TEXT("ground_acquisition_observations"),GroundApproaches);
        if(LatestTownStatus)O->SetObjectField(TEXT("native_status"),LatestTownStatus);
        if(auto* W=ObservedWorld.Get()){
            O->SetNumberField(TEXT("current_world_seconds"),W->GetTimeSeconds());auto* A=W->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();W3::Kernel K;FString Error;
            if(A){const auto V=A->GetPresentation();O->SetBoolField(TEXT("reachable"),V.bReachable);O->SetStringField(TEXT("counter_diagnostic"),V.Diagnostic);O->SetStringField(TEXT("notice"),V.Notice);O->SetStringField(TEXT("owner"),V.Owner);O->SetStringField(TEXT("operator"),V.Operator);O->SetStringField(TEXT("aria_coins"),LexToString(V.AriaCoins));O->SetStringField(TEXT("ben_coins"),LexToString(V.BenCoins));O->SetStringField(TEXT("stock"),LexToString(V.Stock));
                const bool OK=ReadWorld(A,K,nullptr,&Error);O->SetBoolField(TEXT("live_journal_read_ok"),OK);O->SetStringField(TEXT("live_journal_error"),Error);
                if(OK){O->SetNumberField(TEXT("event_count"),double(K.events().size()));O->SetNumberField(TEXT("pay_count"),Count(K,"pay"));O->SetNumberField(TEXT("deed_count"),Count(K,"property_deed_transferred"));O->SetNumberField(TEXT("lease_grant_count"),Count(K,"property_lease_granted"));O->SetNumberField(TEXT("lease_end_count"),Count(K,"property_lease_ended"));O->SetStringField(TEXT("offer_kind"),UTF8_TO_TCHAR(K.offer().kind.c_str()));O->SetBoolField(TEXT("offer_present"),K.offer().present);if(!K.events().empty()){O->SetStringField(TEXT("last_event_type"),UTF8_TO_TCHAR(K.events().back().type.c_str()));O->SetStringField(TEXT("last_event_note"),UTF8_TO_TCHAR(K.events().back().note.c_str()));}}}
            if(Controller.IsValid()){O->SetStringField(TEXT("controller_notice"),Controller->GetOperationNotice());if(auto* P=Cast<ACharacter>(Controller->GetPawn().Get())){O->SetStringField(TEXT("pawn_position"),P->GetActorLocation().ToString());O->SetStringField(TEXT("control_rotation"),Controller->GetControlRotation().ToString());O->SetBoolField(TEXT("on_walkable_floor"),P->GetCharacterMovement()->IsMovingOnGround()&&P->GetCharacterMovement()->CurrentFloor.IsWalkableFloor());TArray<ULivingTownMetaHumanMealProducer*> Providers;P->GetComponents(Providers);O->SetNumberField(TEXT("provider_component_count"),Providers.Num());if(auto* Source=P->FindComponentByClass<ULivingTownMetaHumanMealProducer>()){O->SetStringField(TEXT("provider_id"),LexToString(Source->GetUniqueID()));O->SetBoolField(TEXT("provider_registered"),Source->IsRegistered());O->SetBoolField(TEXT("provider_active"),Source->IsPhysicalUseActive());O->SetStringField(TEXT("provider_failure"),Source->GetFailure());FLivingTownMealPhysicalObservation Physical;FString PhysicalError;const bool Fresh=Source->ReadLatest(Physical,PhysicalError);O->SetBoolField(TEXT("provider_fresh_read"),Fresh);O->SetStringField(TEXT("provider_read_error"),PhysicalError);if(Fresh){O->SetStringField(TEXT("provider_observed_frame"),LexToString(Physical.Frame));O->SetNumberField(TEXT("provider_observed_world_seconds"),Physical.WorldSeconds);O->SetBoolField(TEXT("provider_bite_observed"),Physical.bBiteObserved);O->SetBoolField(TEXT("provider_progress_eligible"),Physical.bFirstProgressEligible);}}if(auto* Assembly=P->FindComponentByClass<ULivingTownMetaHumanVisualAssembly>())O->SetBoolField(TEXT("action_clip_active"),Assembly->IsActionClipActive());}}
        }
        const FString Directory=FPaths::ProjectSavedDir()/TEXT("WorldV3PropertyJourney");IFileManager::Get().MakeDirectory(*Directory,true);FString Text;const FString Path=Directory/TEXT("NATIVE_PROPERTY_FAILURE.json");
        if(FJsonSerializer::Serialize(O,TJsonWriterFactory<>::Create(&Text)))FFileHelper::SaveStringToFile(Text,*Path);return Path;
    }
    void RemoveReaders(){RemoveGroundPrerequisite();InputReadTick.ReadOnly=nullptr;if(InputReadTick.IsTickFunctionRegistered())InputReadTick.UnRegisterTickFunction();RemoveProviderObserver();if(WorldCleanup.IsValid())FWorldDelegates::OnWorldCleanup.Remove(WorldCleanup);WorldCleanup.Reset();}
    void WorldEnding(UWorld* W,bool,bool){if(W&&W->GetUniqueID()==WorldId){Release();RemoveReaders();}}
    void ReadAfterInput(){
        auto* W=ObservedWorld.Get();auto* C=Controller.Get();if(!W||!C||!Queued.Active||Queued.Observed||GFrameCounter<=Queued.SentFrame||W->GetTimeSeconds()<=Queued.SentWorld||C->GetWorld()!=W)return;
        if(!C->WasInputKeyJustPressed(Queued.Key)||!C->WasInputKeyJustReleased(Queued.Key))return;
        auto* A=W->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();if(!A)return;
        Queued.Observed=true;Queued.ObservedFrame=GFrameCounter;Queued.ObservedWorld=W->GetTimeSeconds();Queued.View=A->GetPresentation();Queued.Notice=C->GetOperationNotice();
        Queued.ReadOK=ReadWorld(A,Queued.Kernel,&Queued.Envelope,&Queued.ReadError);Queued.PawnAfter=C->GetPawn().Get();Queued.AfterControl=C->GetControlRotation();
        if(auto* P=C->GetPawn().Get()){Queued.AfterTransform=P->GetActorTransform();if(auto* Source=P->FindComponentByClass<ULivingTownMetaHumanMealProducer>())Queued.Physical=Source->IsPhysicalUseActive();}
    }
    bool InstallReader(UWorld* W,ALivingTownCafeWorldV3Controller* C){
        if(InputReadTick.IsTickFunctionRegistered())return true;
        if(!Need(W->PersistentLevel&&C->PrimaryActorTick.IsTickFunctionRegistered()&&C->PrimaryActorTick.TickGroup==TG_PrePhysics,TEXT("input_reader.requires_actual_controller_PrePhysics_tick")))return false;
        InputReadTick.ReadOnly=[this](){ReadAfterInput();ReadApproachGround();};InputReadTick.AddPrerequisite(C,C->PrimaryActorTick);InputReadTick.RegisterTickFunction(W->PersistentLevel);InputReadTick.SetTickFunctionEnable(true);
        WorldCleanup=FWorldDelegates::OnWorldCleanup.AddRaw(this,&FCurrentTownPropertyJourney::WorldEnding);return true;
    }
    bool QueueTap(UWorld* W,FKey Key,const TCHAR* Label){
        if(!Need(!Queued.Active&&Controller.IsValid()&&InputReadTick.IsTickFunctionRegistered(),TEXT("queued_input.single_pending_action")))return false;
        W3::Kernel Before;FString Error;const bool BaselineOK=ReadWorld(W->GetSubsystem<ULivingTownCafeWorldV3Subsystem>(),Before,nullptr,&Error);if(!Need(BaselineOK,*(TEXT("queued_input.baseline_journal: ")+Error)))return false;
        Release();Queued=FQueuedTap{};Queued.Active=true;Queued.Key=Key;Queued.Label=Label;Queued.SentFrame=GFrameCounter;Queued.SentWorld=W->GetTimeSeconds();Queued.SentWall=FPlatformTime::Seconds();Queued.BeforeEvents=int64(Before.events().size());
        Queued.PawnBefore=Controller->GetPawn().Get();if(Queued.PawnBefore.IsValid())Queued.BeforeTransform=Queued.PawnBefore->GetActorTransform();Queued.BeforeControl=Controller->GetControlRotation();
        Queued.PressReturn=Controller->InputKey(FInputKeyEventArgs::CreateSimulated(Key,IE_Pressed,1.f));Queued.ReleaseReturn=Controller->InputKey(FInputKeyEventArgs::CreateSimulated(Key,IE_Released,0.f));return true;
    }
    bool AwaitTap(UWorld* W){
        if(!Need(Queued.Active,TEXT("queued_input.await_has_pending_action")))return false;
        if(!Queued.Observed){Need(W->GetTimeSeconds()-Queued.SentWorld<5&&FPlatformTime::Seconds()-Queued.SentWall<15,TEXT("queued_input.timeout_no_actual_pressed_and_released_batch"));return false;}
        return Need(Queued.ObservedFrame>Queued.SentFrame&&Queued.ObservedWorld>Queued.SentWorld,TEXT("queued_input.later_natural_frame_and_world_time"))&&Need(Queued.ReadOK,*(TEXT("queued_input.observed_journal: ")+Queued.ReadError));
    }
    bool AwaitPersona(UWorld* W,ALivingTownCafeWorldV3Controller* C,ULivingTownCafeWorldV3Subsystem* A,ELivingTownCafeWorldPersona Expected){
        if(Persona(C,A,Expected))return true;if(Done)return false;Need(W->GetTimeSeconds()-Queued.SentWorld<60&&FPlatformTime::Seconds()-Queued.SentWall<90,TEXT("queued_persona.timeout_current_pawn_not_ready"));return false;
    }
    void FinishTap(){InputObservations.Add(MakeShared<FJsonValueObject>(TapDiagnostic()));Queued.Active=false;}
    bool OneEvent(const char* Type,const char* Note=nullptr){
        const auto& K=Queued.Kernel;return Need(int64(K.events().size())==Queued.BeforeEvents+1,TEXT("property.exactly_one_new_event"))&&Need(!K.events().empty(),TEXT("property.event_present"))&&Need(K.events().back().type==Type,*(FString(TEXT("property.event_type_actual="))+UTF8_TO_TCHAR(K.events().empty()?"empty":K.events().back().type.c_str())))&&(!Note||Need(K.events().back().note==Note,*(FString(TEXT("property.event_note_actual="))+UTF8_TO_TCHAR(K.events().back().note.c_str()))));
    }
    void Release(){if(Held&&Controller.IsValid())Controller->InputKey(FInputKeyEventArgs::CreateSimulated(EKeys::W,IE_Released,0.f));Held=false;}
    bool Need(bool Ok,const TCHAR* Why){if(!Ok&&!Done){const FString Diagnostic=FailureDiagnostic(Why);Release();RemoveReaders();Test->AddError(FString::Printf(TEXT("Current town property stage=%d action=%s: %s; diagnostic=%s"),Stage,*Queued.Label,Why,*Diagnostic));Done=true;}return Ok;}
    bool Persona(ALivingTownCafeWorldV3Controller* C,ULivingTownCafeWorldV3Subsystem* A,ELivingTownCafeWorldPersona Expected) {
        auto* P=C->GetPawn().Get();if(!P||!C->HasNativePersona()||C->GetNativePersona()!=Expected||!A->GetPresentation().bSessionReady)return false;
        if(!Need(P->GetController()==C&&C->GetViewTarget()==P&&!C->IsMoveInputIgnored(),TEXT("Actual possession/view target/movement owners retained")))return false;
        if(Expected==ELivingTownCafeWorldPersona::Aria){auto* Owner=Cast<ALivingTownCafePropertyOwnerProxy>(P);return Need(Owner&&Owner->IsFunctionalOwnerConfigured(),TEXT("Production Aria proxy remains functional"));}
        auto* Ben=Cast<ALivingTownCafeCharacter>(P);auto* Assembly=Ben?Ben->FindComponentByClass<ULivingTownMetaHumanVisualAssembly>():nullptr;
        return Need(Ben&&Ben->HasQualifiedVisual()&&Ben->HasMetaHumanVisual()&&Assembly&&Assembly->IsConfigured()&&Assembly->GetBody()&&Assembly->GetFace()&&
            Assembly->GetBody()->GetPostProcessInstance()&&Assembly->GetFace()->GetAnimInstance()&&Assembly->GetFace()->GetPostProcessInstance(),TEXT("Current complete MetaHuman and its pose owners qualify each Ben tenure"));
    }
    ULivingTownMetaHumanMealProducer* Provider(ACharacter* P,ULivingTownCafeWorldV3Subsystem* A) {
        if(!A->GetPresentation().bMealAvailable)return nullptr;
        TArray<ULivingTownMetaHumanMealProducer*> All;P->GetComponents(All);ULivingTownMetaHumanMealProducer* Found=nullptr;int32 Live=0;
        for(auto* Item:All)if(IsValid(Item)&&Item->IsRegistered()){Found=Item;++Live;}
        if(!Need(Live==1&&Found&&Found->GetOwner()==P&&Found->GetRecipe().RecipeSha256==ExpectedRecipeSha&&Found->GetFailure().IsEmpty(),TEXT("Exactly one source-qualified provider owned by the current Ben")))return nullptr;
        return Found;
    }
    bool ObserveInitialBind(ULivingTownCafeWorldV3Subsystem* A,ALivingTownCafeWorldV3Controller* C){
        if(InitialBindObserved||!C||!C->HasNativePersona()||C->GetNativePersona()!=ELivingTownCafeWorldPersona::Ben||!A->IsPrepared()||!A->GetPresentation().bSessionReady)return true;
        auto* P=Cast<ACharacter>(C->GetPawn().Get());if(!P)return true;
        const auto Actual=FWorldV3MealProviderLifecycleTestAccess::Read(A);
        if(!Need(Actual.Epoch==1&&!Actual.ExplicitlyNull&&!Actual.Stale&&Actual.Pawn==P&&(Actual.Handle||Actual.RolesReady),TEXT("First actual Ben bind preserved PrepareScenario's one preload epoch and pending-or-ready work")))return false;
        InitialBindObserved=true;InitialBindEpoch=Actual.Epoch;InitialBindHadHandle=Actual.Handle!=nullptr;InitialBindRolesReady=Actual.RolesReady;return true;
    }
    bool SameBindPreservesState(ULivingTownCafeWorldV3Subsystem* A,ALivingTownCafeWorldV3Controller* C,ACharacter* P){
        const auto Before=FWorldV3MealProviderLifecycleTestAccess::Read(A);FString Error;
        if(!Need(A->BindNativeSession(C,P,Error)&&A->BindNativeSession(C,P,Error),TEXT("Two valid same-pawn binds")))return false;
        const auto After=FWorldV3MealProviderLifecycleTestAccess::Read(A);
        return Need(Before.Epoch==After.Epoch&&Before.Handle==After.Handle&&Before.RolesReady==After.RolesReady&&Before.Pawn==After.Pawn&&!After.ExplicitlyNull&&!After.Stale,TEXT("Same-pawn rebind preserves actual handle identity, readiness and epoch"));
    }
    bool ObservePendingSameBind(ULivingTownCafeWorldV3Subsystem* A,ALivingTownCafeWorldV3Controller* C,ACharacter* P){
        const auto Actual=FWorldV3MealProviderLifecycleTestAccess::Read(A);
        if(Actual.Handle&&!Actual.RolesReady){if(!SameBindPreservesState(A,C,P))return false;PendingRebindObserved=true;}
        return true; // No fabricated pending state and no pending-timing claim if absent.
    }
    bool Retired(const TWeakObjectPtr<ULivingTownMetaHumanMealProducer>& Old) {
        return !Old.IsValid()||!Old->IsRegistered(); // No GC or artificial destruction from the test.
    }
    bool Inactive(ACharacter* P,ULivingTownCafeWorldV3Subsystem* A,ULivingTownMetaHumanMealProducer* Source) {
        auto* Assembly=P->FindComponentByClass<ULivingTownMetaHumanVisualAssembly>();FLivingTownMealPhysicalObservation O;FString Error;
        if(!Need(Source&&Source->GetOwner()==P&&Source->IsRegistered()&&!Source->IsPhysicalUseActive()&&!A->GetPresentation().bMealActive&&Assembly&&!Assembly->IsActionClipActive()&&!Source->ReadLatest(O,Error)&&Error==TEXT("meal_v2_no_fresh_observation"),TEXT("No inherited physical action, fresh observation or resumed clip")))return false;
        int32 Bread=0;TArray<UStaticMeshComponent*> Parts;P->GetComponents(Parts);
        const auto* Whole=Source->GetRecipe().FindRole(TEXT("bread"));const auto* Bitten=Source->GetRecipe().FindRole(TEXT("bread_bitten"));
        if(!Need(Whole&&Bitten,TEXT("Qualified provider retains both original food roles")))return false;
        for(auto* Part:Parts)if(Part->IsRegistered()&&Part->GetStaticMesh()&&(Part->GetStaticMesh()->GetPathName()==Whole->Asset||Part->GetStaticMesh()->GetPathName()==Bitten->Asset))++Bread;
        return Need(Bread==0,TEXT("No owned food component leaked or resumed"));
    }
    bool BlockedCandidate(UWorld* W,ACharacter* P,ULivingTownCafeWorldV3Subsystem* A,ULivingTownMetaHumanMealProducer* Source) {
        auto* Mode=W->GetAuthGameMode<ALivingTownCafeWorldV3GameMode>();W3::Kernel Before,After;FString Error;
        if(!Need(Mode&&ReadWorld(A,Before)&&Inactive(P,A,Source),TEXT("Live old Ben/provider before deliberate failed candidate")))return false;
        const FTransform Original=P->GetActorTransform();const auto OldPawn=Controller->GetPawn();const auto OldView=Controller->GetViewTarget();const FRotator OldControl=Controller->GetControlRotation();
        const auto& B=A->GetBinding();const FTransform Spawn(B.SpawnRotation,B.SpawnFeetCm+FVector(0,0,B.CapsuleHalfHeightCm));
        FActorSpawnParameters Params;Params.SpawnCollisionHandlingOverride=ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
        auto* Blocker=W->SpawnActor<AActor>(AActor::StaticClass(),Spawn,Params);if(!Need(Blocker!=nullptr,TEXT("Temporary actual spawn blocker")))return false;TemporaryBlocker=Blocker;
        auto* Capsule=NewObject<UCapsuleComponent>(Blocker);Blocker->AddInstanceComponent(Capsule);Blocker->SetRootComponent(Capsule);Capsule->InitCapsuleSize(B.CapsuleRadiusCm*1.5f,B.CapsuleHalfHeightCm*1.5f);
        Capsule->SetCollisionEnabled(ECollisionEnabled::QueryOnly);Capsule->SetCollisionObjectType(ECC_WorldStatic);Capsule->SetCollisionResponseToAllChannels(ECR_Block);Capsule->RegisterComponent();Blocker->SetActorTransform(Spawn);
        // Public immediate Aria request returns its exact refusal; unlike the async
        // Ben completion this source path emits no expected Warning to suppress.
        const auto Result=Mode->RequestPersona(Controller.Get(),ELivingTownCafeWorldPersona::Aria,Error);
        const bool Kept=Result==ELivingTownCafePersonaRequestResult::Refused&&Error==TEXT("actual_persona_spawn_capsule_overlap")&&Controller->GetPawn()==OldPawn&&Controller->GetViewTarget()==OldView&&Controller->GetControlRotation().Equals(OldControl,0)&&P->GetActorTransform().Equals(Original,0)&&Provider(P,A)==Source&&ReadWorld(A,After)&&After.save_bytes()==Before.save_bytes();
        Blocker->Destroy();TemporaryBlocker.Reset();
        if(!Need(Kept&&Inactive(P,A,Source),TEXT("Failed persona spawn retains exact old pawn/provider/ledger and no action")))return false;
        // Rebinding this same current pawn is intentionally idempotent.
        if(!SameBindPreservesState(A,Controller.Get(),P)||!Need(Provider(P,A)==Source&&Inactive(P,A,Source),TEXT("Same-pawn rebind twice preserves the live provider identity")))return false;
        FailedCandidateRetained=true;return true;
    }
    void RemoveProviderObserver(){if(ProviderObserver.IsValid())FWorldDelegates::OnWorldPostActorTick.Remove(ProviderObserver);ProviderObserver.Reset();}
    void ObserveProvider(UWorld* W,ELevelTick,float) {
        if(!W||W->GetUniqueID()!=WorldId||!Controller.IsValid()||!ReacquiredProvider.IsValid())return;
        auto* A=W->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();auto* Source=ReacquiredProvider.Get();auto* P=Controller->GetPawn().Get();FLivingTownMealPhysicalObservation O;FString Error;
        if(!A||Source->GetOwner()!=P){ProbeFailure=TEXT("provider owner changed during actual entry");return;}
        if(A->GetPresentation().ProgressTicks>0){ProbeFailure=TEXT("entry-cancel probe crossed a benefit tick");return;}
        if(Source->ReadLatest(O,Error)){
            if(O.bBiteObserved||O.bFirstProgressEligible){ProbeFailure=TEXT("entry-cancel probe crossed its no-benefit scope");return;}
            if(O.bFresh&&O.Frame==GFrameCounter&&O.Frame>ProbeInputFrame&&O.WorldSeconds>ProbeStarted&&O.bHolding&&O.Phase==ELivingTownMealPhysicalPhase::Entry){FreshEntrySeen=true;FreshEntryFrame=O.Frame;FreshEntryWorldSeconds=O.WorldSeconds;}
        }
    }
    bool Census(UWorld* W) {
        int32 Venues=0,Drivers=0;TSet<FString> Roles;
        for(TActorIterator<AActor> It(W);It;++It){
            if(auto* V=Cast<ALivingTownCafeVenue>(*It)){++Venues;TArray<UStaticMeshComponent*> Parts;V->GetComponents(Parts);if(!Need(V->IsQualified()&&Parts.Num()==289,TEXT("Original289 qualified cafe retained")))return false;}
            if(auto* D=Cast<ALivingTownFullTownDriver>(*It)){++Drivers;if(!Need(D->bEnableIntegrationSubset,TEXT("Sole integration driver retained")))return false;}
            TArray<UStaticMeshComponent*> Parts;It->GetComponents(Parts);
            for(auto* Part:Parts)for(FName Tag:Part->ComponentTags)if(Tag.ToString().StartsWith(TEXT("LT_FTW_ROLE="))){const FString Id=Tag.ToString().Mid(12);if(!Need(Part->IsRegistered()&&!Roles.Contains(Id),TEXT("Unique registered streamed source roles")))return false;Roles.Add(Id);}
        }
        ++CensusSamples;return Need(Venues==1&&Drivers==1&&Roles.Num()==971,TEXT("Actual289 external plus971 streamed roles, no duplicated old cafe"));
    }
    void RemoveGroundPrerequisite(){
        if(auto* Move=GroundMovement.Get())InputReadTick.RemovePrerequisite(Move,Move->PrimaryComponentTick);
        // Same stale-weak pruning as the engine scheduler; only this test reader owns this list.
        InputReadTick.GetPrerequisites().RemoveAll([this](const FTickPrerequisite& Item){return Item.PrerequisiteObject.HasSameIndexAndSerialNumber(GroundMovement)||Item.Get()==nullptr;});
        GroundPrerequisiteBound=false;GroundPrerequisiteFrame=MAX_uint64;GroundObservedTickReady=false;GroundMovement.Reset();GroundPawn.Reset();
    }
    static TSharedRef<FJsonObject> GroundVector(const FVector& V){
        auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("x"),V.X);O->SetNumberField(TEXT("y"),V.Y);O->SetNumberField(TEXT("z"),V.Z);return O;
    }
    void ReadApproachGround(bool FailureSnapshot=false){
        if(!GroundApproach||(!FailureSnapshot&&(Done||GroundAcquired||GroundObservedFrame==GFrameCounter)))return;
        auto* W=ObservedWorld.Get();auto* C=Controller.Get();auto* P=GroundPawn.Get();auto* Move=GroundMovement.Get();
        if(!GroundMovement.IsValid()&&P)GroundMovement=P->GetCharacterMovement();Move=GroundMovement.Get();
        const bool TickReady=Move&&Move->IsRegistered()&&Move->IsActive()&&Move->PrimaryComponentTick.IsTickFunctionRegistered()&&Move->IsComponentTickEnabled();
        if(!FailureSnapshot){
            if(!TickReady){if(GroundPrerequisiteBound&&Move)InputReadTick.RemovePrerequisite(Move,Move->PrimaryComponentTick);GroundPrerequisiteBound=false;GroundPrerequisiteFrame=MAX_uint64;}
            else if(!GroundPrerequisiteBound){InputReadTick.AddPrerequisite(Move,Move->PrimaryComponentTick);GroundPrerequisiteBound=true;GroundPrerequisiteFrame=GFrameCounter;}
        }
        GroundObservedFrame=GFrameCounter;GroundObservedWorld=W?W->GetTimeSeconds():-1;GroundObservedTickReady=TickReady&&GroundPrerequisiteBound&&GroundObservedFrame>GroundPrerequisiteFrame;
        GroundObservedIdentity=W&&C&&P&&Move&&P->GetWorld()==W&&C->GetWorld()==W&&C->GetPawn().Get()==P&&P->GetController()==C&&C->GetViewTarget()==P&&P->GetCharacterMovement()==Move&&!C->IsMoveInputIgnored()&&!Held&&!C->IsInputKeyDown(EKeys::W);
        GroundObservedSupport=Move&&Move->IsMovingOnGround()&&Move->CurrentFloor.IsWalkableFloor();
        auto Row=MakeShared<FJsonObject>();Row->SetStringField(TEXT("scope"),FailureSnapshot?TEXT("Immediate read-only failure snapshot, not a scheduled movement receipt"):TEXT("Ordinary engine TG_PostUpdateWork read; prerequisite qualification recorded separately; no movement setter or manual tick"));Row->SetBoolField(TEXT("engine_scheduled_reader"),!FailureSnapshot);Row->SetBoolField(TEXT("pawn_observed"),P&&P->GetCapsuleComponent());Row->SetBoolField(TEXT("movement_observed"),Move!=nullptr);
        Row->SetStringField(TEXT("frame"),LexToString(GroundObservedFrame));Row->SetNumberField(TEXT("world_seconds"),GroundObservedWorld);Row->SetNumberField(TEXT("wall_seconds_from_start"),FPlatformTime::Seconds()-GroundStartWall);Row->SetBoolField(TEXT("current_pawn_identity"),GroundObservedIdentity);Row->SetBoolField(TEXT("grounded_and_walkable"),GroundObservedSupport);Row->SetNumberField(TEXT("reader_actual_tick_group"),int32(InputReadTick.GetActualTickGroup().GetValue()));
        Row->SetBoolField(TEXT("movement_prerequisite_bound"),GroundPrerequisiteBound);Row->SetStringField(TEXT("movement_prerequisite_bound_frame"),LexToString(GroundPrerequisiteFrame));Row->SetBoolField(TEXT("after_bound_enabled_movement_prerequisite"),GroundObservedTickReady&&!FailureSnapshot);
        Row->SetStringField(TEXT("expected_pawn_id"),P?LexToString(P->GetUniqueID()):TEXT("invalid"));Row->SetStringField(TEXT("controller_current_pawn_id"),C&&C->GetPawn()?LexToString(C->GetPawn()->GetUniqueID()):TEXT("invalid"));
        if(P&&P->GetCapsuleComponent()){
            const auto* Capsule=P->GetCapsuleComponent();GroundObservedFeet=P->GetActorLocation()-FVector(0,0,Capsule->GetScaledCapsuleHalfHeight());GroundObservedSpeedXY=P->GetVelocity().Size2D();
            Row->SetObjectField(TEXT("actor_cm"),GroundVector(P->GetActorLocation()));Row->SetObjectField(TEXT("feet_cm"),GroundVector(GroundObservedFeet));Row->SetObjectField(TEXT("velocity_cm_s"),GroundVector(P->GetVelocity()));Row->SetNumberField(TEXT("speed_xy_cm_s"),GroundObservedSpeedXY);Row->SetNumberField(TEXT("capsule_radius_cm"),Capsule->GetScaledCapsuleRadius());Row->SetNumberField(TEXT("capsule_half_height_cm"),Capsule->GetScaledCapsuleHalfHeight());Row->SetNumberField(TEXT("spawn_xy_error_cm"),FVector::Dist2D(GroundObservedFeet,Route[0]));Row->SetNumberField(TEXT("spawn_height_error_cm"),GroundObservedFeet.Z-Route[0].Z);Row->SetStringField(TEXT("movement_base"),GetPathNameSafe(P->GetMovementBase()));
        }
        if(Move){
            const auto& Floor=Move->CurrentFloor;Row->SetNumberField(TEXT("movement_mode"),int32(Move->MovementMode.GetValue()));Row->SetNumberField(TEXT("custom_movement_mode"),Move->CustomMovementMode);Row->SetBoolField(TEXT("moving_on_ground"),Move->IsMovingOnGround());Row->SetBoolField(TEXT("floor_blocking_hit"),bool(Floor.bBlockingHit));Row->SetBoolField(TEXT("floor_walkable"),Floor.IsWalkableFloor());Row->SetBoolField(TEXT("floor_line_trace"),bool(Floor.bLineTrace));Row->SetNumberField(TEXT("floor_dist_cm"),Floor.FloorDist);Row->SetNumberField(TEXT("line_dist_cm"),Floor.LineDist);Row->SetStringField(TEXT("floor_hit_component"),GetPathNameSafe(Floor.HitResult.GetComponent()));Row->SetStringField(TEXT("floor_hit_actor"),GetPathNameSafe(Floor.HitResult.GetActor()));Row->SetObjectField(TEXT("floor_impact_cm"),GroundVector(Floor.HitResult.ImpactPoint));Row->SetObjectField(TEXT("floor_impact_normal"),GroundVector(Floor.HitResult.ImpactNormal));Row->SetBoolField(TEXT("floor_hit_start_penetrating"),Floor.HitResult.bStartPenetrating);Row->SetBoolField(TEXT("movement_registered"),Move->IsRegistered());Row->SetBoolField(TEXT("movement_active"),Move->IsActive());Row->SetBoolField(TEXT("movement_tick_registered"),Move->PrimaryComponentTick.IsTickFunctionRegistered());Row->SetBoolField(TEXT("movement_tick_enabled"),Move->IsComponentTickEnabled());Row->SetNumberField(TEXT("movement_actual_tick_group"),int32(Move->PrimaryComponentTick.GetActualTickGroup().GetValue()));Row->SetStringField(TEXT("floor_observation_source"),TEXT("CharacterMovement.CurrentFloor cached result; no new trace"));Row->SetNumberField(TEXT("movement_tick_interval_seconds"),Move->GetComponentTickInterval());Row->SetObjectField(TEXT("movement_last_update_location_cm"),GroundVector(Move->GetLastUpdateLocation()));Row->SetObjectField(TEXT("movement_last_update_velocity_cm_s"),GroundVector(Move->GetLastUpdateVelocity()));
        }
        GroundApproach->SetObjectField(TEXT("latest_observation"),Row);if(FailureSnapshot)GroundApproach->SetObjectField(TEXT("failure_live_observation"),Row);
        if(GroundSamples.Num()>=MaxGroundSamples){GroundHistoryOverflow=true;GroundApproach->SetBoolField(TEXT("history_overflow"),true);return;}
        GroundSamples.Add(MakeShared<FJsonValueObject>(Row));GroundApproach->SetArrayField(TEXT("samples"),GroundSamples);
    }
    bool AwaitApproachGround(UWorld* W,ACharacter* P){
        if(GroundAcquired)return true;
        const double Now=W->GetTimeSeconds(),Wall=FPlatformTime::Seconds();
        if(!Need(P&&P==GroundPawn.Get()&&(!GroundMovement.IsValid()||P->GetCharacterMovement()==GroundMovement.Get())&&Controller.IsValid()&&!Held&&!Controller->IsInputKeyDown(EKeys::W),TEXT("ground_acquisition.current_pawn_and_no_walk_input"))||
            !Need(Now-GroundStartWorld<5&&Wall-GroundStartWall<15&&Now-LegStart<30&&Wall<Deadline,TEXT("ground_acquisition.finite5world15wall_within_original_leg_and_test"))||
            !Need(!GroundHistoryOverflow,TEXT("ground_acquisition.bounded1024_actual_frame_history")))return false;
        if(GroundObservedFrame==MAX_uint64||GroundObservedFrame<=GroundStartFrame||GroundObservedWorld<=GroundStartWorld)return false;
        if(!Need(GroundObservedFrame<=GFrameCounter&&GFrameCounter-GroundObservedFrame<=1,TEXT("ground_acquisition.fresh_engine_reader_observation")))return false;
        if(!GroundObservedTickReady)return false;
        if(!Need(GroundObservedIdentity,TEXT("ground_acquisition.actual_current_pawn_observation"))||
            !Need(FVector::Dist2D(GroundObservedFeet,Route[0])<=5.5&&GroundObservedSpeedXY<=2,TEXT("ground_acquisition.stationary_xy_at_authored_spawn")))return false;
        if(!GroundObservedSupport)return false;
        if(!Need(FMath::Abs(GroundObservedFeet.Z-Route[0].Z)<=4,TEXT("ground_acquisition.original_source_spawn_height")))return false;
        GroundAcquired=true;GroundApproach->SetStringField(TEXT("status"),TEXT("ACQUIRED_ACTUAL_LATER_NATURAL_FRAME_SUPPORT"));GroundApproach->SetStringField(TEXT("acquired_frame"),LexToString(GroundObservedFrame));GroundApproach->SetNumberField(TEXT("acquired_world_seconds"),GroundObservedWorld);GroundApproach->SetNumberField(TEXT("acquired_wall_seconds_from_start"),Wall-GroundStartWall);return true;
    }
    void StartApproach(UWorld* W,ACharacter* P){Release();Waypoint=1;Settling=false;LegStart=W->GetTimeSeconds();LastWalkTime=-1;
        RemoveGroundPrerequisite();
        GroundPawn=P;GroundMovement=P->GetCharacterMovement();GroundStartFrame=GFrameCounter;GroundStartWorld=LegStart;GroundStartWall=FPlatformTime::Seconds();GroundObservedFrame=MAX_uint64;GroundObservedWorld=-1;GroundObservedIdentity=false;GroundObservedSupport=false;GroundHistoryOverflow=false;GroundAcquired=false;GroundSamples.Empty();
        GroundApproach=MakeShared<FJsonObject>();GroundApproach->SetStringField(TEXT("status"),TEXT("WAITING_FOR_ACTUAL_NATURAL_GROUND"));GroundApproach->SetNumberField(TEXT("approach"),CompletedApproaches+1);GroundApproach->SetStringField(TEXT("pawn_id"),LexToString(P->GetUniqueID()));GroundApproach->SetStringField(TEXT("start_frame"),LexToString(GroundStartFrame));GroundApproach->SetNumberField(TEXT("start_world_seconds"),GroundStartWorld);GroundApproach->SetNumberField(TEXT("original_first_leg_deadline_world_seconds"),LegStart+30);GroundApproach->SetNumberField(TEXT("maximum_acquisition_world_seconds"),5);GroundApproach->SetNumberField(TEXT("maximum_acquisition_wall_seconds"),15);GroundApproach->SetNumberField(TEXT("maximum_history_samples"),MaxGroundSamples);GroundApproaches.Add(MakeShared<FJsonValueObject>(GroundApproach.ToSharedRef()));
        const FVector Feet=P->GetActorLocation()-FVector(0,0,P->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());Need(FVector::Dist2D(Feet,Route[0])<=5.5,TEXT("Production persona switch started at its authored spawn; test never places it"));
    }
    bool Walk(UWorld* W,ACharacter* P) {
        if(!AwaitApproachGround(W,P))return false;
        auto* Move=P->GetCharacterMovement();const FVector Feet=P->GetActorLocation()-FVector(0,0,P->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());const double Now=W->GetTimeSeconds();
        if(!Need(Move->IsMovingOnGround()&&Move->CurrentFloor.IsWalkableFloor()&&Now-LegStart<30,TEXT("Natural grounded indoor route and finite leg deadline")))return false;
        if(LastWalkTime>=0&&Now>LastWalkTime){const double Distance=FVector::Dist2D(Feet,LastFeet);if(!Need(Distance<=Move->GetMaxSpeed()*(Now-LastWalkTime)+3,TEXT("No position/time substitution in observed movement")))return false;WalkCm+=Distance;++RouteSamples;}
        LastFeet=Feet;LastWalkTime=Now;const FVector To=Route[Waypoint]-Feet;
        if(!Settling){if(To.Size2D()>5.5){Controller->SetControlRotation(FRotator(0,To.Rotation().Yaw,0));if(!Held){Controller->InputKey(FInputKeyEventArgs::CreateSimulated(EKeys::W,IE_Pressed,1.f));Held=true;}return false;}
            if(!Need(FMath::Abs(To.Z)<=4,TEXT("Actual source waypoint height")))return false;Release();Settling=true;}
        if(P->GetVelocity().Size2D()>2)return false;
        if(!Need((Route[Waypoint]-Feet).Size2D()<=5.5&&FMath::Abs((Route[Waypoint]-Feet).Z)<=4,TEXT("Settled feet retain the original waypoint XY/height tolerances")))return false;
        ++Waypoint;Settling=false;LegStart=Now;
        if(Waypoint<Route.Num())return false;++CompletedApproaches;return true;
    }
    bool ReadSavedDocument(const FString& Text,W3::Kernel& K,W3::CareEnvelope& Envelope){FString Error;const bool OK=ReadDocument(Text,K,&Envelope,&Error);return Need(OK,*(FString(TEXT("save.slot_decode: "))+Error));}
    bool Money(ULivingTownCafeWorldV3Subsystem* A,int64 Aria,int64 Ben,const TCHAR* Owner,const TCHAR* Operator) {
        const auto V=A->GetPresentation();W3::Kernel K;FString Error;const bool ReadOK=ReadWorld(A,K,nullptr,&Error);
        return Need(ReadOK,*(TEXT("money.journal: ")+Error))&&Need(Aria+Ben==24,TEXT("money.expected_sum24"))&&
            Need(V.AriaCoins==Aria,*FString::Printf(TEXT("money.presentation_aria actual=%lld expected=%lld"),(long long)V.AriaCoins,(long long)Aria))&&Need(V.BenCoins==Ben,*FString::Printf(TEXT("money.presentation_ben actual=%lld expected=%lld"),(long long)V.BenCoins,(long long)Ben))&&
            Need(V.Owner==Owner,*(TEXT("money.owner_actual=")+V.Owner))&&Need(V.Operator==Operator,*(TEXT("money.operator_actual=")+V.Operator))&&Need(K.accounts()[0].coin==Aria,TEXT("money.kernel_aria"))&&Need(K.accounts()[1].coin==Ben,TEXT("money.kernel_ben"))&&Need(K.title().owner==TCHAR_TO_UTF8(Owner),TEXT("money.kernel_title"));
    }
public:
    FCurrentTownPropertyJourney(FAutomationTestBase* T,const TArray<FVector>& InRoute,const FString& RecipeSha):Test(T),Route(InRoute),ExpectedRecipeSha(RecipeSha){}
    ~FCurrentTownPropertyJourney(){Release();RemoveReaders();
        if(TemporaryBlocker.IsValid()&&GEngine)for(const auto& Context:GEngine->GetWorldContexts())if(Context.World()&&Context.World()->GetUniqueID()==WorldId){TemporaryBlocker->Destroy();break;}
    }
    bool Update()override {
        if(Done)return true;if(!Need(FPlatformTime::Seconds()<Deadline,TEXT("Finite420s actual current-town journey")))return true;
        UWorld* W=nullptr;int32 Worlds=0;if(GEngine)for(const auto& Context:GEngine->GetWorldContexts())if(Context.World()&&(Context.WorldType==EWorldType::Game||Context.WorldType==EWorldType::PIE)){W=Context.World();++Worlds;}
        if(!Need(Worlds<=1,TEXT("One native fixture world")))return true;if(!W||!W->HasBegunPlay())return false;ObservedWorld=W;
        if(!WorldId)WorldId=W->GetUniqueID();if(!Need(W->GetUniqueID()==WorldId&&UWorld::RemovePIEPrefix(W->GetOutermost()->GetName())==PropertyRoot,TEXT("Exact same saved current root")))return true;
        auto* Town=W->GetSubsystem<ULivingTownFullTownStreamingSubsystem>();auto* A=W->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();
        if(!Need(Town&&A&&W->GetAuthGameMode()&&W->GetAuthGameMode()->GetClass()==ALivingTownCafeWorldV3GameMode::StaticClass(),TEXT("Actual WorldV3/full-town owners")))return true;
        TSharedPtr<FJsonObject> S;FString Status;double CurrentEpoch=0,Relocks=0;bool Locked=true;
        if(!Need(FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Town->GetStatusJson()),S)&&S&&S->TryGetStringField(TEXT("status"),Status)&&S->TryGetNumberField(TEXT("epoch"),CurrentEpoch)&&S->TryGetNumberField(TEXT("post_possession_owned_relocks"),Relocks)&&S->TryGetBoolField(TEXT("owned_movement_lock"),Locked),TEXT("Actual typed town status")))return true;
        LatestTownStatus=S;if(!Need(Status!=TEXT("FAILED_SUPPORT_RETAINED")&&Status!=TEXT("STOPPED_SUPPORT_RETAINED"),TEXT("No startup/source/ownership refusal")))return true;
        auto* C=Cast<ALivingTownCafeWorldV3Controller>(W->GetFirstPlayerController());if(Stage==0&&!ObserveInitialBind(A,C))return true;
        if(Status!=TEXT("SUBSET_CONTROLLABLE_NOT_FULL_TOWN")){if(!Need(Stage==0&&Epoch<0,TEXT("Ready town stays ready")))return true;return false;}
        if(!C||!C->HasNativePersona()||!C->GetPawn())return false;
        if(!ControllerId){Controller=C;ControllerId=C->GetUniqueID();Epoch=CurrentEpoch;}
        if(!Need(C==Controller.Get()&&C->GetUniqueID()==ControllerId&&CurrentEpoch==Epoch&&!Locked&&Relocks==1&&!W->IsPaused()&&W->GetNetMode()==NM_Standalone,TEXT("One controller/epoch and balanced movement ownership"))||!InstallReader(W,C))return true;
        auto* Legacy=W->GetSubsystem<ULivingTownCafeProjectionSubsystem>();
        if(!Need((!Legacy||(!Legacy->IsReady()&&!Legacy->IsScenePrepared()))&&!W->GetSubsystem<ULivingTownCafePropertyV2Subsystem>()&&W->GetGameInstance()&&!W->GetGameInstance()->GetSubsystem<ULivingTownLeaseSubsystem>(),TEXT("No parallel legacy authority or wallet")))return true;
        auto* P=Cast<ACharacter>(C->GetPawn().Get());if(!Need(P!=nullptr,TEXT("Actual current native character")))return true;
        const auto V=A->GetPresentation();const auto& Binding=A->GetBinding();
        if(!Need(Binding.Parts.Num()==289&&Binding.BindingFileSha256==BindingSha&&Binding.MetaHumanActor.IsSet()&&Binding.MetaHumanActor->UsesWorkwear()&&(!V.bMealActive||EntryWindow),TEXT("Current289/workwear; active action only in explicit entry/cancel window")))return true;
        if(OpeningStock<0){OpeningStock=V.Stock;ExpectedStock=OpeningStock;}
        if(Stage!=9&&!Need(V.Stock==ExpectedStock,TEXT("Only the explicitly observed owner entry consumes stock")))return true;
        if(Stage>=6&&Stage<=12){if(!Need(V.bMealAvailable,TEXT("owner_tenure.provider_available")))return true;auto* Source=Provider(P,A);if(!Source)return Done;if(!Need(Source==ReacquiredProvider.Get(),TEXT("Same reacquired provider remains owned throughout the counter tenure")))return true;}
        if(Stage==0){
            if(!Persona(C,A,ELivingTownCafeWorldPersona::Ben))return Done;if(!V.bMealAvailable){if(!ObservePendingSameBind(A,C,P))return true;return false;}auto* Source=Provider(P,A);if(!Source)return Done;
            const auto Boot=FWorldV3MealProviderLifecycleTestAccess::Read(A);if(!Need(InitialBindObserved&&Boot.Epoch==1&&Boot.RolesReady&&!Boot.Handle&&Boot.Pawn==P,TEXT("Positive first-bind preload completed without cancellation/re-request"))||!Inactive(P,A,Source)||!SameBindPreservesState(A,C,P))return true;
            FirstProvider=Source;FirstProviderId=Source->GetUniqueID();if(!Money(A,12,12,TEXT("aria"),TEXT("aria"))||!Census(W)||!QueueTap(W,EKeys::F1,TEXT("select_aria_off_counter")))return true;Stage=1;return false;
        }
        if(Stage==1){if(!AwaitTap(W)||!AwaitPersona(W,C,A,ELivingTownCafeWorldPersona::Aria))return Done;if(!Need(Retired(FirstProvider),TEXT("Committed Aria switch retired original provider"))||!Need(!V.bReachable,TEXT("Off-counter condition physically observed")))return true;FinishTap();if(!QueueTap(W,EKeys::O,TEXT("off_counter_sale_refusal")))return true;Stage=2;return false;}
        if(Stage==2){if(!AwaitTap(W))return Done;if(!OneEvent("property_refused","not_at_commercial_counter")||!Need(Count(Queued.Kernel,"pay")==0,TEXT("off_counter.no_payment"))||!Money(A,12,12,TEXT("aria"),TEXT("aria")))return true;FinishTap();StartApproach(W,P);Stage=3;return false;}
        if(Stage==3){if(!Persona(C,A,ELivingTownCafeWorldPersona::Aria)||!Walk(W,P))return Done;if(!Need(A->GetPresentation().bReachable,TEXT("Actual Aria counter rays/facing"))||!QueueTap(W,EKeys::O,TEXT("sale_offer")))return true;Stage=4;return false;}
        if(Stage==4){if(!AwaitTap(W))return Done;const auto& Q=Queued.Kernel;if(!OneEvent("property_offer_opened","offer_sale")||!Need(Q.offer().present,TEXT("sale_offer.present"))||!Need(Q.offer().kind=="sale",TEXT("sale_offer.kind"))||!Need(Q.offer().owner=="aria",TEXT("sale_offer.owner"))||!Need(Count(Q,"pay")==0,TEXT("sale_offer.no_payment")))return true;FinishTap();if(!QueueTap(W,EKeys::F2,TEXT("select_ben_purchase")))return true;Stage=5;return false;}
        if(Stage==5){if(!AwaitTap(W)||!AwaitPersona(W,C,A,ELivingTownCafeWorldPersona::Ben))return Done;if(!V.bMealAvailable){if(!Need(W->GetTimeSeconds()-Queued.SentWorld<60&&FPlatformTime::Seconds()-Queued.SentWall<90,TEXT("ben_purchase.provider_timeout"))||!ObservePendingSameBind(A,C,P))return true;return false;}auto* Source=Provider(P,A);if(!Source)return Done;if(!Need(Source->GetUniqueID()!=FirstProviderId&&Retired(FirstProvider),TEXT("Returning Ben reacquired fresh current-owner provider"))||!Inactive(P,A,Source))return true;ReacquiredProvider=Source;ReacquiredProviderId=Source->GetUniqueID();FinishTap();StartApproach(W,P);Stage=6;return false;}
        if(Stage==6){if(!Persona(C,A,ELivingTownCafeWorldPersona::Ben)||!Walk(W,P))return Done;if(!Need(A->GetPresentation().bReachable,TEXT("Actual Ben counter rays/facing"))||!QueueTap(W,EKeys::B,TEXT("purchase")))return true;Stage=7;return false;}
        if(Stage==7){if(!AwaitTap(W))return Done;const auto& Q=Queued.Kernel;if(!Money(A,24,0,TEXT("ben"),TEXT("ben"))||!Need(Count(Q,"pay")==1,TEXT("purchase.one_payment"))||!Need(Count(Q,"property_deed_transferred")==1,TEXT("purchase.one_deed"))||!Need(Q.title().revision==1,TEXT("purchase.title_revision")))return true;FinishTap();if(!QueueTap(W,EKeys::L,TEXT("fixed_lease_offer")))return true;Stage=8;return false;}
        if(Stage==8){if(!AwaitTap(W))return Done;const auto& Q=Queued.Kernel;if(!OneEvent("property_offer_opened","offer_lease")||!Need(Q.offer().present,TEXT("fixed_offer.present"))||!Need(Q.offer().kind=="lease",TEXT("fixed_offer.kind"))||!Need(Q.offer().owner=="ben",TEXT("fixed_offer.owner")))return true;auto* Source=Provider(P,A);if(!Source)return Done;if(!Need(Source==ReacquiredProvider.Get(),TEXT("Same provider through owner tenure")))return true;FinishTap();if(!BlockedCandidate(W,P,A,Source))return true;
            ProviderObserver=FWorldDelegates::OnWorldPostActorTick.AddRaw(this,&FCurrentTownPropertyJourney::ObserveProvider);FreshEntrySeen=false;ProbeStarted=W->GetTimeSeconds();ProbeInputFrame=GFrameCounter;EntryWindow=true;if(!QueueTap(W,EKeys::E,TEXT("owner_physical_entry")))return true;Stage=9;return false;}
        if(Stage==9){if(!Need(W->GetTimeSeconds()-ProbeStarted<1,TEXT("entry.dispatch_within_finite_no_benefit_window")))return true;if(!AwaitTap(W))return Done;if(!Need(Queued.View.bMealActive,TEXT("entry.active_authority"))||!Need(Queued.Physical,TEXT("entry.actual_provider_active"))||!Need(Queued.View.Stock==OpeningStock-1,TEXT("entry.exactly_one_stock"))||!Need(Count(Queued.Kernel,"pay")==1,TEXT("entry.no_additional_owner_payment")))return true;ExpectedStock=OpeningStock-1;if(!Need(V.Stock==ExpectedStock,TEXT("entry.current_stock_matches_observed")))return true;FinishTap();Stage=10;return false;}
        if(Stage==10){auto* Source=Provider(P,A);if(!Source)return Done;if(!Need(ProbeFailure.IsEmpty(),*(TEXT("entry.observer: ")+ProbeFailure))||!Need(Source->GetFailure().IsEmpty(),*(TEXT("entry.provider: ")+Source->GetFailure()))||!Need(W->GetTimeSeconds()-ProbeStarted<1,TEXT("Finite natural provider entry observation without benefit")))return true;if(!FreshEntrySeen)return false;if(!QueueTap(W,EKeys::X,TEXT("cancel_physical_entry")))return true;Stage=11;return false;}
        if(Stage==11){if(!Need(W->GetTimeSeconds()-ProbeStarted<1,TEXT("cancel.dispatch_within_finite_no_benefit_window")))return true;if(!AwaitTap(W))return Done;if(!Need(!Queued.View.bMealActive&&!Queued.Physical,TEXT("cancel.observed_authority_and_physical_stopped")))return true;FinishTap();RemoveProviderObserver();EntryWindow=false;auto* Source=Provider(P,A);if(!Source)return Done;if(!Need(ProbeFailure.IsEmpty(),*(TEXT("cancel.observer: ")+ProbeFailure))||!Inactive(P,A,Source)||!Money(A,24,0,TEXT("ben"),TEXT("ben")))return true;StageTime=W->GetTimeSeconds();Stage=12;return false;}
        if(Stage==12){auto* Source=Provider(P,A);if(!Source)return Done;if(!Inactive(P,A,Source))return true;if(W->GetTimeSeconds()-StageTime<.5)return false;if(!QueueTap(W,EKeys::F1,TEXT("select_aria_lease")))return true;Stage=13;return false;}
        if(Stage==13){if(!AwaitTap(W)||!AwaitPersona(W,C,A,ELivingTownCafeWorldPersona::Aria))return Done;if(!Need(Retired(ReacquiredProvider),TEXT("Cancelled old provider retired on Aria commit")))return true;FinishTap();StartApproach(W,P);Stage=14;return false;}
        if(Stage==14){if(!Persona(C,A,ELivingTownCafeWorldPersona::Aria)||!Walk(W,P))return Done;if(!Need(A->GetPresentation().bReachable,TEXT("Former owner physically reaches lease counter"))||!QueueTap(W,EKeys::K,TEXT("accept_fixed_lease")))return true;Stage=15;return false;}
        if(Stage==15){if(!AwaitTap(W))return Done;const auto& Q=Queued.Kernel;if(!Money(A,20,4,TEXT("ben"),TEXT("aria"))||!Need(Q.lease().active,TEXT("lease.active"))||!Need(!Q.recurring_lease(),TEXT("lease.fixed_not_recurring"))||!Need(Q.lease().end-Q.lease().start==720,TEXT("lease.exact720_ticks"))||!Need(Count(Q,"pay")==2,TEXT("lease.second_payment"))||!Need(Count(Q,"property_lease_granted")==1,TEXT("lease.one_grant"))||!Need(Q.can_operate("aria","cafe","1f",Queued.View.Clock),TEXT("lease.commercial_permission"))||!Need(!Q.can_operate("aria","cafe","2f",Queued.View.Clock),TEXT("lease.private_upstairs_excluded")))return true;SavedWorld=Q.save_bytes();FinishTap();if(!Need(!IFileManager::Get().FileExists(*SlotPath()),TEXT("save.no_stale_slot_in_fresh_project"))||!QueueTap(W,EKeys::F5,TEXT("save_paid_fixed_lease")))return true;Stage=16;return false;}
        if(Stage==16){if(!AwaitTap(W))return Done;TArray<uint8> Bytes;FString SavedText;W3::CareEnvelope SavedEnvelope;W3::Kernel SavedKernel;
            if(!Need(Queued.Notice==TEXT("Cafe saved."),TEXT("save.observed_operation_notice"))||!Need(FFileHelper::LoadFileToArray(Bytes,*SlotPath()),TEXT("save.actual_slot_bytes"))||!Need(LivingTownCafeJournal::Sha256(Bytes,SlotSha),TEXT("save.slot_sha"))||!Need(FFileHelper::LoadFileToString(SavedText,*SlotPath()),TEXT("save.actual_slot_text"))||!ReadSavedDocument(SavedText,SavedKernel,SavedEnvelope)||!Need(SavedKernel.save_bytes()==SavedWorld&&Queued.Kernel.save_bytes()==SavedWorld,TEXT("save.exact_paid_world_bytes"))||!Need(SavedEnvelope.clock.tick==Queued.Envelope.clock.tick&&SavedEnvelope.clock.fraction_bits==Queued.Envelope.clock.fraction_bits,TEXT("save.exact_actual_post_input_clock")))return true;
            SavedClock=SavedEnvelope.clock;FinishTap();StageTime=W->GetTimeSeconds();Stage=17;return false;}
        if(Stage==17){if(!Need(W->GetTimeSeconds()-StageTime<3,TEXT("Finite natural clock-advance observation before F9")))return true;if(V.Clock<=SavedClock.tick)return false;if(!QueueTap(W,EKeys::F9,TEXT("restore_paid_fixed_lease")))return true;Stage=18;return false;}
        if(Stage==18){if(!AwaitTap(W))return Done;if(!Need(Queued.Notice.StartsWith(TEXT("Cafe restored.")),TEXT("restore.observed_operation_notice"))||!Need(Queued.PawnAfter==Queued.PawnBefore&&C->GetPawn().Get()==Queued.PawnBefore.Get(),TEXT("restore.same_pawn"))||!Need(Queued.AfterTransform.Equals(Queued.BeforeTransform,0)&&P->GetActorTransform().Equals(Queued.BeforeTransform,0),TEXT("restore.no_pawn_move"))||!Need(Queued.AfterControl.Equals(Queued.BeforeControl,0)&&C->GetControlRotation().Equals(Queued.BeforeControl,0),TEXT("restore.no_control_change"))||!Need(Queued.Envelope.clock.tick==SavedClock.tick,TEXT("restore.exact_tick_at_post_input_boundary"))||!Need(Queued.Envelope.clock.fraction_bits==SavedClock.fraction_bits,TEXT("restore.exact_fraction_bits_at_post_input_boundary"))||!Need(Queued.View.Clock==SavedClock.tick,TEXT("restore.presentation_tick_at_boundary"))||!Need(Queued.Kernel.save_bytes()==SavedWorld,TEXT("restore.exact_saved_world_bytes"))||!Need(Count(Queued.Kernel,"pay")==2,TEXT("restore.no_duplicate_payment"))||!Need(!Queued.View.bMealActive&&!A->GetPresentation().bMealActive,TEXT("restore.no_physical_resume"))||!Money(A,20,4,TEXT("ben"),TEXT("aria")))return true;FinishTap();if(!QueueTap(W,EKeys::R,TEXT("surrender_fixed_lease")))return true;Stage=19;return false;}
        if(Stage==19){if(!AwaitTap(W))return Done;const auto& Q=Queued.Kernel;if(!Money(A,20,4,TEXT("ben"),TEXT("ben"))||!Need(!Q.lease().active,TEXT("surrender.lease_inactive"))||!Need(Count(Q,"pay")==2,TEXT("surrender.no_additional_payment"))||!Need(Count(Q,"property_lease_ended")==1,TEXT("surrender.one_end_event")))return true;FinishTap();if(!QueueTap(W,EKeys::F2,TEXT("select_final_ben")))return true;Stage=20;return false;}
        if(Stage==20){if(!AwaitTap(W)||!AwaitPersona(W,C,A,ELivingTownCafeWorldPersona::Ben))return Done;if(!V.bMealAvailable){if(!Need(W->GetTimeSeconds()-Queued.SentWorld<60&&FPlatformTime::Seconds()-Queued.SentWall<90,TEXT("final_ben.provider_timeout"))||!ObservePendingSameBind(A,C,P))return true;return false;}auto* Source=Provider(P,A);if(!Source)return Done;if(!Need(Source->GetUniqueID()!=ReacquiredProviderId&&Retired(ReacquiredProvider),TEXT("Final Ben has another current-owner provider"))||!Inactive(P,A,Source))return true;FinalProviderId=Source->GetUniqueID();FinishTap();StartApproach(W,P);Stage=21;return false;}
        if(!Persona(C,A,ELivingTownCafeWorldPersona::Ben)||!Walk(W,P))return Done;
        if(!Need(A->GetPresentation().bReachable,TEXT("final_counter.reachable"))||!Need(A->GetPresentation().bMealAvailable,TEXT("final_counter.provider_available"))||!Need(CompletedApproaches==4,TEXT("route.four_actual_approaches"))||!Need(GroundApproaches.Num()==4,TEXT("ground_acquisition.four_bound_approaches"))||!Need(RouteSamples>=48,TEXT("route.minimum48_natural_samples"))||!Need(WalkCm>=1920,TEXT("route.minimum1920_observed_cm"))||!Money(A,20,4,TEXT("ben"),TEXT("ben"))||!Census(W))return true;
        auto Proof=MakeShared<FJsonObject>();Proof->SetStringField(TEXT("status"),TEXT("PASS_CURRENT_TOWN_PROPERTY_INPUT_STATE_ONLY"));Proof->SetStringField(TEXT("scope"),TEXT("Sale/fixed lease/F5-F9/surrender plus provider reacquisition, failed candidate retention and actual physical entry/cancel; no completed meal, cold process, recurring due, art or FPS qualification"));
        Proof->SetNumberField(TEXT("initial_bind_preload_epoch"),double(InitialBindEpoch));Proof->SetBoolField(TEXT("initial_bind_had_pending_handle"),InitialBindHadHandle);Proof->SetBoolField(TEXT("initial_bind_roles_ready"),InitialBindRolesReady);Proof->SetBoolField(TEXT("pending_same_pawn_rebind_observed"),PendingRebindObserved);Proof->SetNumberField(TEXT("initial_provider_id"),FirstProviderId);Proof->SetNumberField(TEXT("reacquired_provider_id"),ReacquiredProviderId);Proof->SetNumberField(TEXT("final_provider_id"),FinalProviderId);Proof->SetBoolField(TEXT("failed_candidate_retained_live_provider"),FailedCandidateRetained);Proof->SetBoolField(TEXT("actual_fresh_entry_seen"),FreshEntrySeen);Proof->SetStringField(TEXT("entry_input_frame"),FString::Printf(TEXT("%llu"),static_cast<unsigned long long>(ProbeInputFrame)));Proof->SetStringField(TEXT("entry_observed_frame"),FString::Printf(TEXT("%llu"),static_cast<unsigned long long>(FreshEntryFrame)));Proof->SetNumberField(TEXT("entry_observed_world_seconds"),FreshEntryWorldSeconds);Proof->SetNumberField(TEXT("explicit_owner_entry_stock_used"),OpeningStock-ExpectedStock);Proof->SetNumberField(TEXT("restored_clock_tick"),SavedClock.tick);Proof->SetStringField(TEXT("restored_fraction_bits"),FString::Printf(TEXT("%llu"),static_cast<unsigned long long>(SavedClock.fraction_bits)));Proof->SetNumberField(TEXT("walk_cm"),WalkCm);Proof->SetNumberField(TEXT("natural_walk_samples"),RouteSamples);Proof->SetNumberField(TEXT("completed_counter_approaches"),CompletedApproaches);Proof->SetNumberField(TEXT("census_samples"),CensusSamples);Proof->SetStringField(TEXT("paid_lease_slot_sha256"),SlotSha);Proof->SetObjectField(TEXT("final_native_status"),LatestTownStatus);
        const FString Directory=FPaths::ProjectSavedDir()/TEXT("WorldV3PropertyJourney");IFileManager::Get().MakeDirectory(*Directory,true);FString Text;
        auto AcquisitionRecord=MakeShared<FJsonObject>();AcquisitionRecord->SetStringField(TEXT("format"),TEXT("LivingTown.NativeGroundAcquisition"));AcquisitionRecord->SetStringField(TEXT("version"),TEXT("1"));AcquisitionRecord->SetStringField(TEXT("status"),TEXT("PASS_FOUR_NATURAL_GROUND_ACQUISITIONS"));AcquisitionRecord->SetStringField(TEXT("scope"),TEXT("Test-only natural-frame cached-ground acquisition for four authored approaches; scheduling is not a movement execution receipt; no physics/art/FPS qualification"));AcquisitionRecord->SetNumberField(TEXT("approach_count"),GroundApproaches.Num());AcquisitionRecord->SetNumberField(TEXT("history_sample_limit_per_approach"),MaxGroundSamples);AcquisitionRecord->SetBoolField(TEXT("movement_setters_or_manual_ticks_used"),false);AcquisitionRecord->SetArrayField(TEXT("observations"),GroundApproaches);FString GroundText;
        if(!Need(FJsonSerializer::Serialize(AcquisitionRecord,TJsonWriterFactory<>::Create(&GroundText))&&FFileHelper::SaveStringToFile(GroundText,*(Directory/TEXT("NATIVE_GROUND_ACQUISITION.json"))),TEXT("Four actual bounded acquisition histories published separately from unchanged property proof")))return true;
        if(!Need(FJsonSerializer::Serialize(Proof,TJsonWriterFactory<>::Create(&Text))&&FFileHelper::SaveStringToFile(Text,*(Directory/TEXT("NATIVE_PROPERTY_PROOF.json"))),TEXT("Actual source-bound property proof published")))return true;
        auto Inputs=MakeShared<FJsonObject>();Inputs->SetStringField(TEXT("scope"),TEXT("Actual one-shot queued key events and ordinary post-controller/pre-source-clock observations only"));Inputs->SetArrayField(TEXT("observations"),InputObservations);FString InputText;
        if(!Need(FJsonSerializer::Serialize(Inputs,TJsonWriterFactory<>::Create(&InputText))&&FFileHelper::SaveStringToFile(InputText,*(Directory/TEXT("NATIVE_INPUT_OBSERVATIONS.json"))),TEXT("Actual input observation evidence published")))return true;
        Release();RemoveReaders();Done=true;return true;
    }
};
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCurrentTownPropertyJourney,"LivingTown.FullTown.WorldV3PropertyJourney",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCurrentTownPropertyJourney::RunTest(const FString&) {
    FString Descriptor,Persona;TArray<FVector> Route;FLivingTownMetaHumanVisualBinding Visual;FLivingTownMetaHumanMealRecipeV2 Meal;FString Error;
    if(!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeWorldV3"))||!FParse::Param(FCommandLine::Get(),TEXT("LivingTownWorldV3TownJourney"))||!FParse::Param(FCommandLine::Get(),TEXT("LivingTownWorldV3PropertyJourney"))||
        !FParse::Value(FCommandLine::Get(),TEXT("LivingTownMetaHumanBen="),Descriptor)||!FParse::Value(FCommandLine::Get(),TEXT("CafeWorldPersona="),Persona)||Persona!=TEXT("ben"))
    {AddError(TEXT("Explicit current town/property/Ben fixture and original descriptor required"));return false;}
    if(!FLivingTownMetaHumanVisualBinding::Read(Descriptor,Visual,Error)||!Visual.UsesWorkwear()||!FLivingTownMetaHumanMealRecipeV2::ReadQualified(TEXT("LivingTown/MetaHumanMealContactV2.json"),Meal,Error)||!ReadRoute(Route)||
        !IFileManager::Get().FileExists(*FPackageName::LongPackageNameToFilename(PropertyRoot,FPackageName::GetMapPackageExtension())))
    {AddError(TEXT("Full unchanged current character/root/route/meal union required: ")+Error);return false;}
    if(GEngine)for(const auto& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::Game||C.WorldType==EWorldType::PIE)){AddError(TEXT("Fresh isolated current property fixture required"));return false;}
    if(!AutomationOpenMap(PropertyRoot,true))return false;ADD_LATENT_AUTOMATION_COMMAND(FCurrentTownPropertyJourney(this,Route,Meal.RecipeSha256));return true;
}
#endif
