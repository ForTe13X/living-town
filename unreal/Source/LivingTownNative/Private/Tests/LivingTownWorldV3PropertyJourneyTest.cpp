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
bool ReadDocument(const FString& Text,W3::Kernel& K,W3::CareEnvelope* Out=nullptr) {
    FString Encoded;TArray<uint8> Bytes;TSharedPtr<FJsonObject> O;
    if(!LivingTownCafeJournal::HasUniqueObjectKeys(Text)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),O)||!O||!O->TryGetStringField(TEXT("payload_base64"),Encoded)||!FBase64::Decode(Encoded,Bytes)||Bytes.IsEmpty())return false;
    const auto Envelope=W3::decode_care_envelope_document(std::string(reinterpret_cast<const char*>(Bytes.GetData()),size_t(Bytes.Num())));
    if(!Envelope||!K.restore_bytes(Envelope->world_payload))return false;if(Out)*Out=*Envelope;return true;
}
bool ReadWorld(ULivingTownCafeWorldV3Subsystem* A,W3::Kernel& K,W3::CareEnvelope* Out=nullptr) {
    FString Text,Error;return A->EncodeJournal(Text,Error)&&ReadDocument(Text,K,Out);
}
int32 Count(const W3::Kernel& K,const char* Type){int32 N=0;for(const auto& E:K.events())if(E.type==Type)++N;return N;}

class FCurrentTownPropertyJourney final:public IAutomationLatentCommand {
    FAutomationTestBase* Test;TArray<FVector> Route;
    const double Deadline=FPlatformTime::Seconds()+420.;
    int32 Stage=0,Waypoint=1,RouteSamples=0,CompletedApproaches=0,CensusSamples=0;
    uint32 WorldId=0,ControllerId=0;double Epoch=-1,LastWalkTime=-1,WalkCm=0,LegStart=-1,StageTime=0;
    FVector LastFeet=FVector::ZeroVector;bool Held=false,Settling=false,Done=false;
    TWeakObjectPtr<ALivingTownCafeWorldV3Controller> Controller;
    std::string SavedWorld;FString SlotSha;int64 OpeningStock=-1,ExpectedStock=-1;
    W3::ClockMetadata SavedClock;int32 ProviderPhase=0;double ProbeStarted=0;
    FString ExpectedRecipeSha,ProbeFailure;bool FreshEntrySeen=false,FailedCandidateRetained=false;
    uint64 ProbeInputFrame=0,FreshEntryFrame=0;double FreshEntryWorldSeconds=-1;
    bool InitialBindObserved=false,InitialBindHadHandle=false,InitialBindRolesReady=false,PendingRebindObserved=false;
    uint64 InitialBindEpoch=0;
    uint32 FirstProviderId=0,ReacquiredProviderId=0,FinalProviderId=0;
    TWeakObjectPtr<ULivingTownMetaHumanMealProducer> FirstProvider,ReacquiredProvider;
    TWeakObjectPtr<AActor> TemporaryBlocker;
    FDelegateHandle ProviderObserver;
    TSharedPtr<FJsonObject> LatestTownStatus;
    void Release(){if(Held&&Controller.IsValid())Controller->InputKey(FInputKeyEventArgs::CreateSimulated(EKeys::W,IE_Released,0.f));Held=false;}
    void Tap(FKey Key){Release();Controller->InputKey(FInputKeyEventArgs::CreateSimulated(Key,IE_Pressed,1.f));Controller->InputKey(FInputKeyEventArgs::CreateSimulated(Key,IE_Released,0.f));}
    bool Need(bool Ok,const TCHAR* Why){if(!Ok){Release();Test->AddError(FString::Printf(TEXT("Current town property stage=%d: %s"),Stage,Why));Done=true;}return Ok;}
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
    void StartApproach(UWorld* W,ACharacter* P){Release();Waypoint=1;Settling=false;LegStart=W->GetTimeSeconds();LastWalkTime=-1;
        const FVector Feet=P->GetActorLocation()-FVector(0,0,P->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());Need(FVector::Dist2D(Feet,Route[0])<=5.5,TEXT("Production persona switch started at its authored spawn; test never places it"));}
    bool Walk(UWorld* W,ACharacter* P) {
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
    bool Money(ULivingTownCafeWorldV3Subsystem* A,int64 Aria,int64 Ben,const TCHAR* Owner,const TCHAR* Operator) {
        const auto& V=A->GetPresentation();W3::Kernel K;
        if(!Need(ReadWorld(A,K),TEXT("Actual paired journal decodes and strictly replays")))return false;
        return Need(V.AriaCoins==Aria&&V.BenCoins==Ben&&Aria+Ben==24&&V.Owner==Owner&&V.Operator==Operator&&
            K.accounts()[0].coin==Aria&&K.accounts()[1].coin==Ben&&K.title().owner==TCHAR_TO_UTF8(Owner),TEXT("HUD authority and real conserved kernel balances/title/operator agree"));
    }
public:
    FCurrentTownPropertyJourney(FAutomationTestBase* T,const TArray<FVector>& InRoute,const FString& RecipeSha):Test(T),Route(InRoute),ExpectedRecipeSha(RecipeSha){}
    ~FCurrentTownPropertyJourney(){Release();RemoveProviderObserver();
        if(TemporaryBlocker.IsValid()&&GEngine)for(const auto& Context:GEngine->GetWorldContexts())if(Context.World()&&Context.World()->GetUniqueID()==WorldId){TemporaryBlocker->Destroy();break;}
    }
    bool Update()override {
        if(Done)return true;if(!Need(FPlatformTime::Seconds()<Deadline,TEXT("Finite420s actual current-town journey")))return true;
        UWorld* W=nullptr;int32 Worlds=0;if(GEngine)for(const auto& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::Game||C.WorldType==EWorldType::PIE)){W=C.World();++Worlds;}
        if(!Need(Worlds<=1,TEXT("One native fixture world")))return true;if(!W||!W->HasBegunPlay())return false;
        if(!WorldId)WorldId=W->GetUniqueID();if(!Need(W->GetUniqueID()==WorldId&&UWorld::RemovePIEPrefix(W->GetOutermost()->GetName())==PropertyRoot,TEXT("Exact same saved current root")))return true;
        auto* Town=W->GetSubsystem<ULivingTownFullTownStreamingSubsystem>();auto* A=W->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();auto* C=Cast<ALivingTownCafeWorldV3Controller>(W->GetFirstPlayerController());
        if(!Need(Town&&A&&W->GetAuthGameMode()&&W->GetAuthGameMode()->GetClass()==ALivingTownCafeWorldV3GameMode::StaticClass(),TEXT("Actual WorldV3/full-town owners")))return true;
        TSharedPtr<FJsonObject> S;FString Status;double CurrentEpoch=0,Relocks=0;bool Locked=true;
        if(!Need(FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Town->GetStatusJson()),S)&&S&&S->TryGetStringField(TEXT("status"),Status)&&S->TryGetNumberField(TEXT("epoch"),CurrentEpoch)&&S->TryGetNumberField(TEXT("post_possession_owned_relocks"),Relocks)&&S->TryGetBoolField(TEXT("owned_movement_lock"),Locked),TEXT("Actual typed town status")))return true;
        if(!Need(Status!=TEXT("FAILED_SUPPORT_RETAINED")&&Status!=TEXT("STOPPED_SUPPORT_RETAINED"),TEXT("No native startup/source/ownership refusal")))return true;
        if(Stage==0&&!ObserveInitialBind(A,C))return true;
        if(Status!=TEXT("SUBSET_CONTROLLABLE_NOT_FULL_TOWN")){if(!Need(Stage==0&&Epoch<0,TEXT("Ready town stays ready")))return true;return false;}
        if(!C||!A->IsPrepared()||!A->GetPresentation().bSessionReady)return false;
        if(!ControllerId){Controller=C;ControllerId=C->GetUniqueID();Epoch=CurrentEpoch;}
        if(!Need(C==Controller.Get()&&C->GetUniqueID()==ControllerId&&CurrentEpoch==Epoch&&!Locked&&Relocks==1&&!W->IsPaused()&&W->GetNetMode()==NM_Standalone,TEXT("One controller/epoch with original balanced movement ownership")))return true;
        const auto* Legacy=W->GetSubsystem<ULivingTownCafeProjectionSubsystem>();
        if(!Need((!Legacy||(!Legacy->IsReady()&&!Legacy->IsScenePrepared()))&&!W->GetSubsystem<ULivingTownCafePropertyV2Subsystem>()&&W->GetGameInstance()&&!W->GetGameInstance()->GetSubsystem<ULivingTownLeaseSubsystem>(),TEXT("No parallel legacy authority or wallet")))return true;
        const auto& V=A->GetPresentation();const auto& Binding=A->GetBinding();LatestTownStatus=S;
        if(!Need(Binding.Parts.Num()==289&&Binding.BindingFileSha256==BindingSha&&Binding.MetaHumanActor.IsSet()&&Binding.MetaHumanActor->UsesWorkwear()&&(!V.bMealActive||(Stage==4&&ProviderPhase==1)),TEXT("Current289/workwear authority; active action exists only during the explicit entry/cancel probe")))return true;
        if(OpeningStock<0){OpeningStock=V.Stock;ExpectedStock=OpeningStock;}if(!Need(V.Stock==ExpectedStock,TEXT("Only the one explicitly observed owner-meal probe consumes one stock item")))return true;
        auto* P=Cast<ACharacter>(C->GetPawn().Get());if(!P)return false;
        W3::Kernel K;
        if(Stage==0){if(!Persona(C,A,ELivingTownCafeWorldPersona::Ben))return Done;if(!V.bMealAvailable){if(!ObservePendingSameBind(A,C,P))return true;return false;}auto* Source=Provider(P,A);if(!Source)return Done;const auto Boot=FWorldV3MealProviderLifecycleTestAccess::Read(A);if(!Need(InitialBindObserved&&Boot.Epoch==1&&Boot.RolesReady&&!Boot.Handle&&Boot.Pawn==P,TEXT("Positive first-bind preload completed without cancellation or re-request"))||!Inactive(P,A,Source)||!SameBindPreservesState(A,C,P))return true;FirstProvider=Source;FirstProviderId=Source->GetUniqueID();if(!Money(A,12,12,TEXT("aria"),TEXT("aria"))||!Census(W))return true;Tap(EKeys::F1);Stage=1;return false;}
        if(Stage==1){if(!Persona(C,A,ELivingTownCafeWorldPersona::Aria))return Done;if(!Need(Retired(FirstProvider),TEXT("Committed Aria switch retired original Ben provider")))return true;if(!Need(!V.bReachable,TEXT("Off-counter refusal is physically observed, not injected")))return true;
            Tap(EKeys::O);if(!Need(ReadWorld(A,K)&&!K.events().empty()&&K.events().back().type=="property_refused"&&K.events().back().note=="not_at_commercial_counter"&&Count(K,"pay")==0,TEXT("Off-counter offer records refusal without payment"))||!Money(A,12,12,TEXT("aria"),TEXT("aria")))return true;StartApproach(W,P);Stage=2;return false;}
        if(Stage==2){if(!Persona(C,A,ELivingTownCafeWorldPersona::Aria)||!Walk(W,P))return Done;if(!Need(A->GetPresentation().bReachable,TEXT("Actual Aria counter rays/facing permit offer")))return true;
            Tap(EKeys::O);if(!Need(ReadWorld(A,K)&&K.offer().present&&K.offer().kind=="sale"&&K.offer().owner=="aria"&&Count(K,"pay")==0,TEXT("Owner's actual O input opens sale without charge")))return true;Tap(EKeys::F2);Stage=3;return false;}
        if(Stage==3){if(!Persona(C,A,ELivingTownCafeWorldPersona::Ben))return Done;if(!V.bMealAvailable){if(!ObservePendingSameBind(A,C,P))return true;return false;}auto* Source=Provider(P,A);if(!Source)return Done;if(!Need(Source->GetUniqueID()!=FirstProviderId&&Retired(FirstProvider)&&Inactive(P,A,Source),TEXT("Returning Ben reacquired a fresh current-owner provider")))return true;ReacquiredProvider=Source;ReacquiredProviderId=Source->GetUniqueID();StartApproach(W,P);Stage=4;return false;}
        if(Stage==4){
            if(!Persona(C,A,ELivingTownCafeWorldPersona::Ben))return Done;auto* Source=Provider(P,A);if(!Source)return Done;
            if(!Need(ReacquiredProvider.Get()==Source,TEXT("Same reacquired provider remains owned throughout the counter tenure")))return true;
            if(ProviderPhase==0){
                if(!Walk(W,P))return Done;if(!Need(A->GetPresentation().bReachable,TEXT("Actual Ben counter rays/facing permit purchase")))return true;
                Tap(EKeys::B);if(!Money(A,24,0,TEXT("ben"),TEXT("ben"))||!Need(ReadWorld(A,K)&&Count(K,"pay")==1&&Count(K,"property_deed_transferred")==1&&K.title().revision==1,TEXT("One actual sale payment and deed")))return true;
                Tap(EKeys::L);if(!Need(ReadWorld(A,K)&&K.offer().present&&K.offer().kind=="lease"&&K.offer().owner=="ben",TEXT("New owner explicitly lists a fixed lease"))||!BlockedCandidate(W,P,A,Source))return true;
                ProviderObserver=FWorldDelegates::OnWorldPostActorTick.AddRaw(this,&FCurrentTownPropertyJourney::ObserveProvider);FreshEntrySeen=false;ProbeStarted=W->GetTimeSeconds();ProbeInputFrame=GFrameCounter;
                Tap(EKeys::E);if(!Need(A->GetPresentation().bMealActive&&Source->IsPhysicalUseActive()&&A->GetPresentation().Stock==OpeningStock-1&&ReadWorld(A,K)&&Count(K,"pay")==1,TEXT("Actual owner E starts qualified physical entry, consumes one stock and no money")))return true;
                ExpectedStock=OpeningStock-1;ProviderPhase=1;return false;
            }
            if(ProviderPhase==1){
                if(!Need(ProbeFailure.IsEmpty()&&Source->GetFailure().IsEmpty()&&W->GetTimeSeconds()-ProbeStarted<1,TEXT("Finite natural provider entry observation without stale action or benefit")))return true;
                if(!FreshEntrySeen)return false;Tap(EKeys::X);RemoveProviderObserver();
                if(!Inactive(P,A,Source)||!Money(A,24,0,TEXT("ben"),TEXT("ben")))return true;StageTime=W->GetTimeSeconds();ProviderPhase=2;return false;
            }
            if(!Inactive(P,A,Source))return true;if(W->GetTimeSeconds()-StageTime<.5)return false;
            Tap(EKeys::F1);Stage=5;return false;
        }
        if(Stage==5){if(!Persona(C,A,ELivingTownCafeWorldPersona::Aria))return Done;if(!Need(Retired(ReacquiredProvider),TEXT("Successful switch retires the used old provider after cancellation")))return true;StartApproach(W,P);Stage=6;return false;}
        if(Stage==6){if(!Persona(C,A,ELivingTownCafeWorldPersona::Aria)||!Walk(W,P))return Done;if(!Need(A->GetPresentation().bReachable,TEXT("Actual former owner reaches lease counter")))return true;
            Tap(EKeys::K);if(!Money(A,20,4,TEXT("ben"),TEXT("aria"))||!Need(ReadWorld(A,K)&&K.lease().active&&!K.recurring_lease()&&K.lease().end-K.lease().start==720&&Count(K,"pay")==2&&Count(K,"property_lease_granted")==1&&K.can_operate("aria","cafe","1f",A->GetPresentation().Clock)&&!K.can_operate("aria","cafe","2f",A->GetPresentation().Clock),TEXT("One paid fixed lease grants commercial operation, never private upstairs")))return true;
            SavedWorld=K.save_bytes();Tap(EKeys::F5);TArray<uint8> Bytes;FString SavedText;W3::CareEnvelope SavedEnvelope;W3::Kernel SavedKernel;const FString Slot=FPaths::ProjectSavedDir()/TEXT("CafeWorldV3/CafeWorldResidentialCareV6.slot.json");
            if(!Need(C->GetOperationNotice()==TEXT("Cafe saved.")&&FFileHelper::LoadFileToArray(Bytes,*Slot)&&LivingTownCafeJournal::Sha256(Bytes,SlotSha)&&FFileHelper::LoadFileToString(SavedText,*Slot)&&ReadDocument(SavedText,SavedKernel,&SavedEnvelope)&&SavedKernel.save_bytes()==SavedWorld,TEXT("Actual F5 publishes readable current V6 slot and exact paid state")))return true;SavedClock=SavedEnvelope.clock;StageTime=W->GetTimeSeconds();Stage=7;return false;}
        if(Stage==7){if(!Need(W->GetTimeSeconds()-StageTime<3,TEXT("Finite natural clock-advance observation before F9")))return true;if(V.Clock<=SavedClock.tick)return false;W3::CareEnvelope RestoredEnvelope;const auto PawnBefore=C->GetPawn();const FTransform Transform=P->GetActorTransform();const FRotator Control=C->GetControlRotation();Tap(EKeys::F9);
            if(!Need(C->GetOperationNotice().StartsWith(TEXT("Cafe restored."))&&C->GetPawn()==PawnBefore&&P->GetActorTransform().Equals(Transform,0)&&C->GetControlRotation().Equals(Control,0)&&ReadWorld(A,K,&RestoredEnvelope)&&RestoredEnvelope.clock.tick==SavedClock.tick&&RestoredEnvelope.clock.fraction_bits==SavedClock.fraction_bits&&A->GetPresentation().Clock==SavedClock.tick&&K.save_bytes()==SavedWorld&&Count(K,"pay")==2&&!A->GetPresentation().bMealActive,TEXT("Actual F9 restores paid rights with no double charge, pawn move or physical resume"))||!Money(A,20,4,TEXT("ben"),TEXT("aria")))return true;
            Tap(EKeys::R);if(!Money(A,20,4,TEXT("ben"),TEXT("ben"))||!Need(ReadWorld(A,K)&&!K.lease().active&&Count(K,"pay")==2&&Count(K,"property_lease_ended")==1,TEXT("Tenant R surrenders operation without another payment")))return true;Tap(EKeys::F2);Stage=8;return false;}
        if(Stage==8){if(!Persona(C,A,ELivingTownCafeWorldPersona::Ben))return Done;if(!V.bMealAvailable){if(!ObservePendingSameBind(A,C,P))return true;return false;}auto* Source=Provider(P,A);if(!Source)return Done;if(!Need(Source->GetUniqueID()!=ReacquiredProviderId&&Retired(ReacquiredProvider)&&Inactive(P,A,Source),TEXT("Final Ben gets another live current-owner provider, no saved action resumed")))return true;FinalProviderId=Source->GetUniqueID();StartApproach(W,P);Stage=9;return false;}
        if(!Persona(C,A,ELivingTownCafeWorldPersona::Ben)||!Walk(W,P))return Done;
        if(!Need(A->GetPresentation().bReachable&&A->GetPresentation().bMealAvailable&&CompletedApproaches==4&&RouteSamples>=48&&WalkCm>=1920,TEXT("Four real counter approaches end with independent qualified meal provider still present"))||!Money(A,20,4,TEXT("ben"),TEXT("ben"))||!Census(W))return true;
        auto Proof=MakeShared<FJsonObject>();Proof->SetStringField(TEXT("status"),TEXT("PASS_CURRENT_TOWN_PROPERTY_INPUT_STATE_ONLY"));Proof->SetStringField(TEXT("scope"),TEXT("Sale/fixed lease/F5-F9/surrender plus provider reacquisition, failed candidate retention and actual physical entry/cancel; no completed meal, cold process, recurring due, art or FPS qualification"));
        Proof->SetNumberField(TEXT("initial_bind_preload_epoch"),double(InitialBindEpoch));Proof->SetBoolField(TEXT("initial_bind_had_pending_handle"),InitialBindHadHandle);Proof->SetBoolField(TEXT("initial_bind_roles_ready"),InitialBindRolesReady);Proof->SetBoolField(TEXT("pending_same_pawn_rebind_observed"),PendingRebindObserved);Proof->SetNumberField(TEXT("initial_provider_id"),FirstProviderId);Proof->SetNumberField(TEXT("reacquired_provider_id"),ReacquiredProviderId);Proof->SetNumberField(TEXT("final_provider_id"),FinalProviderId);Proof->SetBoolField(TEXT("failed_candidate_retained_live_provider"),FailedCandidateRetained);Proof->SetBoolField(TEXT("actual_fresh_entry_seen"),FreshEntrySeen);Proof->SetStringField(TEXT("entry_input_frame"),FString::Printf(TEXT("%llu"),static_cast<unsigned long long>(ProbeInputFrame)));Proof->SetStringField(TEXT("entry_observed_frame"),FString::Printf(TEXT("%llu"),static_cast<unsigned long long>(FreshEntryFrame)));Proof->SetNumberField(TEXT("entry_observed_world_seconds"),FreshEntryWorldSeconds);Proof->SetNumberField(TEXT("explicit_owner_entry_stock_used"),OpeningStock-ExpectedStock);Proof->SetNumberField(TEXT("restored_clock_tick"),SavedClock.tick);Proof->SetStringField(TEXT("restored_fraction_bits"),FString::Printf(TEXT("%llu"),static_cast<unsigned long long>(SavedClock.fraction_bits)));Proof->SetNumberField(TEXT("walk_cm"),WalkCm);Proof->SetNumberField(TEXT("natural_walk_samples"),RouteSamples);Proof->SetNumberField(TEXT("completed_counter_approaches"),CompletedApproaches);Proof->SetNumberField(TEXT("census_samples"),CensusSamples);Proof->SetStringField(TEXT("paid_lease_slot_sha256"),SlotSha);Proof->SetObjectField(TEXT("final_native_status"),LatestTownStatus);
        const FString Directory=FPaths::ProjectSavedDir()/TEXT("WorldV3PropertyJourney");IFileManager::Get().MakeDirectory(*Directory,true);FString Text;
        if(!Need(FJsonSerializer::Serialize(Proof,TJsonWriterFactory<>::Create(&Text))&&FFileHelper::SaveStringToFile(Text,*(Directory/TEXT("NATIVE_PROPERTY_PROOF.json"))),TEXT("Actual source-bound property proof published")))return true;Release();Done=true;return true;
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
