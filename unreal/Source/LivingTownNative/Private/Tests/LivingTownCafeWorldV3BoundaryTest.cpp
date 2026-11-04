#include "LivingTownCafeWorldV3Subsystem.h"
#include "LivingTownCafeWorldV3Scenario.h"
#include "LivingTownCafePropertyV2Subsystem.h"
#include "LivingTownCafeProjectionSubsystem.h"
#include "LivingTownLeaseSubsystem.h"
#include "../../ThirdParty/CafeWorldV3Envelope.hpp"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Tests/AutomationCommon.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "GameFramework/Character.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Animation/AnimSequence.h"
#include "LivingTownRootCorrectedSingleNodeInstance.h"
#include "HAL/PlatformTime.h"
#include "HAL/PlatformProcess.h"
#include "HAL/FileManager.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/Base64.h"
#include "InputKeyEventArgs.h"
#include "InputCoreTypes.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
namespace {
namespace B=living_town::cafe_backend_v3;
namespace W3=living_town::cafe_world_v3;
bool HashFile(const FString& Path,FString& H){TArray<uint8> Data;return FFileHelper::LoadFileToArray(Data,*Path)&&LivingTownCafeJournal::Sha256(Data,H);}
bool Object(const FString& Json,TSharedPtr<FJsonObject>& O){return LivingTownCafeJournal::HasUniqueObjectKeys(Json)&&FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),O)&&O.IsValid();}
bool Payload(const FString& Json,W3::CareEnvelope& E){TSharedPtr<FJsonObject> O;FString Encoded;TArray<uint8> Data;if(!Object(Json,O)||!O->TryGetStringField(TEXT("payload_base64"),Encoded)||!FBase64::Decode(Encoded,Data)||Data.IsEmpty())return false;const auto Parsed=W3::decode_care_envelope_document(std::string(reinterpret_cast<const char*>(Data.GetData()),size_t(Data.Num())));if(!Parsed)return false;E=*Parsed;return true;}
bool HashEnvelope(TSharedPtr<FJsonObject> O,FString& Json){W3::detail::Writer Writer;for(const TCHAR* Key:{TEXT("format"),TEXT("version"),TEXT("capability"),TEXT("source_sha256"),TEXT("payload_sha256"),TEXT("payload_base64")}){FString V;if(!O->TryGetStringField(Key,V))return false;Writer.s(std::string(TCHAR_TO_UTF8(Key)));Writer.s(std::string(TCHAR_TO_UTF8(*V)));}TArray<uint8> Data;Data.Append(reinterpret_cast<const uint8*>(Writer.bytes.data()),int32(Writer.bytes.size()));FString H;if(!LivingTownCafeJournal::Sha256(Data,H))return false;O->SetStringField(TEXT("envelope_sha256"),H);return FJsonSerializer::Serialize(O.ToSharedRef(),TJsonWriterFactory<>::Create(&Json));}
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafeWorldV3SelectionTest,"LivingTown.WorldV3.ExclusiveBackendSelection",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafeWorldV3SelectionTest::RunTest(const FString&){
    for(int32 Mask=0;Mask<16;++Mask){const B::Flags F{bool(Mask&1),bool(Mask&2),bool(Mask&4),bool(Mask&8)};const auto Selected=B::select(F);const int32 Count=int32(F.property_v2)+int32(F.world_v3)+int32(F.explicit_legacy);const bool Invalid=Count>1||(F.worker_preview&&(F.property_v2||F.world_v3));
        TestTrue(TEXT("Conflicting requests select no authority"),(Selected==B::Backend::Invalid)==Invalid);
        int32 Active=0;for(const auto Mode:{B::ExactMode::Other,B::ExactMode::LegacyV1,B::ExactMode::PropertyV2,B::ExactMode::WorldV3}){Active+=B::can_activate(Selected,Mode,true,F.worker_preview)?1:0;TestFalse(TEXT("Network world cannot activate local cafe authority"),B::can_activate(Selected,Mode,false,F.worker_preview));}
        TestEqual(TEXT("Exactly one eligible scenario or none"),Active,Invalid||F.worker_preview?0:1);
    }
    TestTrue(TEXT("World flag selects WorldV3 only"),B::select({false,true,false,false})==B::Backend::WorldV3);
    TestTrue(TEXT("Existing PropertyV2 flag remains exclusive"),B::select({true,false,false,false})==B::Backend::PropertyV2);TestTrue(TEXT("Default remains legacy"),B::select({})==B::Backend::LegacyV1);return true;
}
namespace {
class FWorldV3Boundary final:public IAutomationLatentCommand {
    FAutomationTestBase* Test;FLivingTownCafeBinding Binding;TArray<FVector> Route;bool bCold=false,bDone=false,bQualified=false,bRequireRootCorrected=false;double Deadline=FPlatformTime::Seconds()+120,LastSample=-1,FaceSince=-1,WalkDistance=0;FVector LastFeet=FVector::ZeroVector;int32 Waypoint=1,Samples=0,PlaybackStage=0;
    TWeakObjectPtr<USkeletalMeshComponent> TestedMesh;
    TWeakObjectPtr<ALivingTownCafeWorldV3Controller> TestedController;
    TWeakObjectPtr<UAnimSingleNodeInstance> OriginalPlayer;
    TWeakObjectPtr<UAnimationAsset> OriginalAsset;
    TWeakObjectPtr<UClass> OriginalPlayerClass;
    float OriginalRate=1,RestoreTime=0,OriginalGlobalRate=1;
    bool bOriginalPlaying=false,bOriginalLooping=false,bOriginalEnable=true;
    uint64 OriginalConfiguration=0;
    FString QualifiedBase;
    double NegativeSince=0;
    int32 BeforeFrozenHunger=0,BeforeFrozenFun=0;
    bool Restored(USkeletalMeshComponent* Mesh,bool CheckTime){
        auto* Player=Mesh?Mesh->GetSingleNodeInstance():nullptr;
        if(!Need(Player&&Player==OriginalPlayer.Get()&&Player->GetClass()==OriginalPlayerClass.Get()&&Player->GetCurrentAsset()==OriginalAsset.Get()&&Player->IsLooping()==bOriginalLooping&&Player->IsPlaying()==bOriginalPlaying&&FMath::IsNearlyEqual(Player->GetPlayRate(),.75f,.0001f)&&(!CheckTime||FMath::IsNearlyEqual(Player->GetCurrentTime(),RestoreTime,.0001f)),TEXT("Every terminal path must retain the exact configured player/class and restore asset/time/loop/play/nondefault rate")))return false;
        if(const auto* Corrected=Cast<ULivingTownRootCorrectedSingleNodeInstance>(Player)){FLivingTownRootCorrectionDiagnostic D;if(!Need(Corrected->CopyRootCorrectionDiagnostic(D)&&D.ConfigurationGeneration==OriginalConfiguration,TEXT("Meal playback must never reset root-corrected proxy configuration")))return false;}return true;
    }
    bool QualifiedPlayback(UWorld* World,ALivingTownCafeWorldV3Controller* PC,ULivingTownCafeWorldV3Subsystem* A,ACharacter* Pawn){
        auto* Mesh=Pawn->GetMesh();auto* Player=Mesh?Mesh->GetSingleNodeInstance():nullptr;auto* Provider=Pawn->FindComponentByClass<ULivingTownCafeMealContactComponent>();FString Error;
        if(!Need(Mesh&&Player&&Provider&&Provider->ValidateRecipe(Pawn,Binding.BindingFileSha256,Error),TEXT("Positive animation tests require a real reviewed source-bound provider/clip; missing qualification is an error, never a synthetic pass")))return true;
        const auto Request=[&](const TCHAR* Id){FLivingTownCafeMealCommand C;C.RequestId=Id;C.ExpectedRevision=A->GetPresentation().Revision;return PC->RequestMeal(C);};
        if(PlaybackStage==0){
            if(bRequireRootCorrected&&!Need(Cast<ULivingTownRootCorrectedSingleNodeInstance>(Player)!=nullptr,TEXT("Root-corrected ownership test requires the actual qualified configured worker player; plain SingleNode cannot stand in")))return true;
            TestedMesh=Mesh;TestedController=PC;OriginalPlayer=Player;OriginalPlayerClass=Player->GetClass();OriginalAsset=Player->GetCurrentAsset();OriginalRate=Player->GetPlayRate();OriginalGlobalRate=Mesh->GlobalAnimRateScale;bOriginalEnable=Mesh->bEnableAnimation;bOriginalPlaying=Player->IsPlaying();bOriginalLooping=Player->IsLooping();
            if(const auto* Corrected=Cast<ULivingTownRootCorrectedSingleNodeInstance>(Player)){FLivingTownRootCorrectionDiagnostic D;if(!Need(Corrected->CopyRootCorrectionDiagnostic(D),TEXT("Read actual configured root-correction generation")))return true;OriginalConfiguration=D.ConfigurationGeneration;}
            // Deliberate negative controls change playback controls only. No
            // manual animation tick, virtual world tick, pose or time setter.
            Player->SetPlayRate(.75f);RestoreTime=Player->GetCurrentTime();Mesh->bEnableAnimation=false;const auto Before=A->GetPresentation();const auto R=Request(TEXT("native/world-v3/disabled-animation"));const auto After=A->GetPresentation();
            if(!Need(!R.bAccepted&&!After.bMealActive&&Before.Stock==After.Stock&&Before.AriaCoins==After.AriaCoins&&Before.BenCoins==After.BenCoins&&Before.Hunger==After.Hunger&&Before.Fun==After.Fun,TEXT("Disabled real animation must refuse before settlement, consumption or any care effect"))||!Restored(Mesh,true))return true;
            Mesh->bEnableAnimation=bOriginalEnable;if(!Need(A->EncodeJournal(QualifiedBase,Error),TEXT("Capture public source-bound baseline for independent terminal-path controls")))return true;
            RestoreTime=Player->GetCurrentTime();const auto Started=Request(TEXT("native/world-v3/cancel-ownership"));
            if(!Need(Started.bAccepted&&!Started.bAlreadyApplied&&Mesh->GetSingleNodeInstance()==Player&&Player->GetCurrentAsset()!=OriginalAsset.Get()&&Player->GetPlayRate()==1.f,TEXT("Only an actual reviewed meal clip may start on the exact existing player")))return true;
            const auto Cancelled=PC->RequestCancelMeal();if(!Need(Cancelled.bAccepted,TEXT("Public controller cancellation must succeed"))||!Restored(Mesh,true))return true;
            RestoreTime=Player->GetCurrentTime();const auto LoadStarted=Request(TEXT("native/world-v3/load-ownership"));FString Active;
            if(!Need(LoadStarted.bAccepted&&A->EncodeJournal(Active,Error)&&A->LoadJournal(Active,Error),TEXT("Public save/load of actual active meal must invalidate use"))||!Restored(Mesh,true))return true;
            if(!Need(!A->GetPresentation().bMealActive&&A->LoadJournal(QualifiedBase,Error),TEXT("AfterLoad stays stopped; restore actual public baseline for the frozen-playback control")))return true;
            RestoreTime=Player->GetCurrentTime();const auto Frozen=Request(TEXT("native/world-v3/frozen-clip"));
            if(!Need(Frozen.bAccepted,TEXT("Frozen-time control must first start the actual reviewed meal")))return true;
            BeforeFrozenHunger=A->GetPresentation().Hunger;BeforeFrozenFun=A->GetPresentation().Fun;Mesh->GlobalAnimRateScale=0;NegativeSince=World->GetTimeSeconds();PlaybackStage=1;return false;
        }
        if(PlaybackStage==1){
            if(World->GetTimeSeconds()-NegativeSince<1.25)return false;
            const auto After=A->GetPresentation();FString Json;W3::CareEnvelope E;
            if(!Need(!After.bMealActive&&After.Hunger<=BeforeFrozenHunger&&After.Fun==BeforeFrozenFun&&A->EncodeJournal(Json,Error)&&Payload(Json,E),TEXT("Natural frozen-clip frames must interrupt without needs/fun gain")))return true;
            const auto Care=W3::decode_care_document(E.care_payload);
            if(!Need(Care&&!Care->requests.empty()&&Care->requests.back().progressed_ticks==0&&Care->requests.back().end==W3::care::End::Interrupted,TEXT("Actual frozen playback must record zero contact progress, even if playing/rate flags and bone revisions survive"))||!Restored(Mesh,true))return true;
            Mesh->GlobalAnimRateScale=OriginalGlobalRate;if(!Need(A->LoadJournal(QualifiedBase,Error),TEXT("Restore public baseline for permission-loss control")))return true;
            RestoreTime=Player->GetCurrentTime();const auto Permission=Request(TEXT("native/world-v3/permission-loss"));FLivingTownCafePropertyCommand Lease;Lease.RequestId=TEXT("native/world-v3/change-current-operator");Lease.Action=ELivingTownCafePropertyAction::Lease;
            if(!Need(Permission.bAccepted&&A->SubmitProperty(Lease).bAccepted,TEXT("Actual property command must change current operator during the real meal")))return true;
            NegativeSince=World->GetTimeSeconds();PlaybackStage=2;return false;
        }
        if(World->GetTimeSeconds()-NegativeSince>2){Need(false,TEXT("Changed operator did not interrupt active meal within the next natural authority tick"));return true;}
        if(A->GetPresentation().bMealActive)return false;
        if(!Restored(Mesh,false))return true;
        return true;
    }
    bool Need(bool Ok,const TCHAR* Why){if(!Ok){Test->AddError(Why);bDone=true;}return Ok;}
    bool Boundary(UWorld* World,ALivingTownCafeWorldV3Controller* PC,ULivingTownCafeWorldV3Subsystem* A,ACharacter* Pawn){
        if(!Need(!Pawn->FindComponentByClass<ULivingTownCafeMealContactComponent>(),TEXT("This refusal test requires the honest no-provider build; never synthesize qualification")))return false;
        const auto Before=A->GetPresentation();FLivingTownCafeMealCommand C;C.RequestId=TEXT("native/world-v3/no-eat-provider");C.ExpectedRevision=Before.Revision;
        const auto R=PC->RequestMeal(C);const auto After=A->GetPresentation();
        if(!Need(!R.bAccepted&&R.Reason==TEXT("qualified_meal_clip_required")&&After.AriaCoins==Before.AriaCoins&&After.BenCoins==Before.BenCoins&&After.Stock==Before.Stock&&After.Hunger==Before.Hunger&&After.Fun==Before.Fun&&!After.bMealActive,TEXT("Actual reachable public command must refuse absent eating clip without payment/stock/needs mutation")))return false;
        const auto Repeat=PC->RequestMeal(C);if(!Need(!Repeat.bAccepted&&Repeat.bAlreadyApplied&&Repeat.EventId==R.EventId&&A->GetPresentation().Revision==After.Revision,TEXT("Same refused request returns original receipt without adding a second event")))return false;
        C.SiteId=TEXT("not-the-cafe");if(!Need(PC->RequestMeal(C).Reason==TEXT("request_id_conflict")&&A->GetPresentation().Revision==After.Revision,TEXT("Reusing request identity with another intent cannot mutate the book")))return false;
        const auto Cancel=PC->RequestCancelMeal();if(!Need(Cancel.bAccepted&&Cancel.bAlreadyApplied&&A->GetPresentation().Revision==After.Revision,TEXT("Repeated no-use cancellation cannot release or pay again")))return false;
        FString Json,Error;if(!Need(A->EncodeJournal(Json,Error),TEXT("Public native source-bound V5 encode must succeed")))return false;
        TSharedPtr<FJsonObject> O;FString Bad;bool Built=Object(Json,O);if(Built){O->SetStringField(TEXT("version"),TEXT("3"));Built=HashEnvelope(O,Bad);}if(!Need(Built&&!A->LoadJournal(Bad,Error),TEXT("Rehashed unsupported native version must be refused")))return false;
        FString AfterBad;if(!Need(A->EncodeJournal(AfterBad,Error)&&AfterBad==Json,TEXT("Failed version load leaves exact paired live bytes and clock unchanged")))return false;
        const auto Transform=Pawn->GetActorTransform();const auto Persona=PC->GetNativePersona();if(!Need(A->LoadJournal(Json,Error)&&PC->GetPawn()==Pawn&&PC->GetNativePersona()==Persona&&Pawn->GetActorTransform().Equals(Transform,0),TEXT("Public V5 restore cannot change possession/persona/position or regenerate reach")))return false;
        FString SlotHash;if(!Need(A->SaveSlot(Error,&SlotHash),TEXT("Public V5 atomic save and final readback must succeed")))return false;
        auto Receipt=MakeShared<FJsonObject>();Receipt->SetStringField(TEXT("format"),TEXT("LivingTown.CafeWorldV3.RefusalSlotProducer"));Receipt->SetStringField(TEXT("slot_sha256"),SlotHash);Receipt->SetStringField(TEXT("producer_process_id"),LexToString(FPlatformProcess::GetCurrentProcessId()));Receipt->SetStringField(TEXT("physical_eating"),TEXT("UNQUALIFIED_NO_PROVIDER"));Receipt->SetNumberField(TEXT("natural_samples"),Samples);Receipt->SetNumberField(TEXT("walk_distance_cm"),WalkDistance);
        FString ReceiptJson;FJsonSerializer::Serialize(Receipt,TJsonWriterFactory<>::Create(&ReceiptJson));const FString Path=FPaths::ProjectSavedDir()/TEXT("CafeWorldV3/RefusalSlotProducer.json");return Need(!IFileManager::Get().FileExists(*Path)&&FFileHelper::SaveStringToFile(ReceiptJson,*Path,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM),TEXT("Preserve existing producer evidence; host must use fresh owned Saved directory"));
    }
    bool Cold(ALivingTownCafeWorldV3Controller* PC,ULivingTownCafeWorldV3Subsystem* A,ACharacter* Pawn){
        const FString Dir=FPaths::ProjectSavedDir()/TEXT("CafeWorldV3");FString ProducerJson,IncomingSha,Error;TSharedPtr<FJsonObject> Producer;
        if(!Need(FFileHelper::LoadFileToString(ProducerJson,*(Dir/TEXT("RefusalSlotProducer.json")))&&Object(ProducerJson,Producer),TEXT("Host must copy actual producer receipt and slot into fresh consumer Saved directory")))return false;
        FString Format,Hash,Pid;if(!Need(Producer->TryGetStringField(TEXT("format"),Format)&&Format==TEXT("LivingTown.CafeWorldV3.RefusalSlotProducer")&&Producer->TryGetStringField(TEXT("slot_sha256"),Hash)&&Producer->TryGetStringField(TEXT("producer_process_id"),Pid)&&Pid!=LexToString(FPlatformProcess::GetCurrentProcessId())&&HashFile(Dir/TEXT("CafeWorldRentCareV5.slot.json"),IncomingSha)&&IncomingSha==Hash,TEXT("Cold restore requires different actual producer process and untouched copied slot SHA256")))return false;
        FString Incoming;W3::CareEnvelope Envelope;if(!Need(FFileHelper::LoadFileToString(Incoming,*(Dir/TEXT("CafeWorldRentCareV5.slot.json")))&&Payload(Incoming,Envelope),TEXT("Read actual portable V5 producer payload")))return false;
        const auto Transform=Pawn->GetActorTransform();const auto Persona=PC->GetNativePersona();if(!Need(A->LoadSlot(Error)&&PC->GetPawn()==Pawn&&PC->GetNativePersona()==Persona&&Pawn->GetActorTransform().Equals(Transform,0),TEXT("Cold public LoadSlot must retain actual live possession and transform")))return false;
        FString Restored;W3::CareEnvelope Replay;if(!Need(A->EncodeJournal(Restored,Error)&&Payload(Restored,Replay)&&Replay.world_payload==Envelope.world_payload&&Replay.care_payload==Envelope.care_payload&&Replay.clock.tick==Envelope.clock.tick&&Replay.clock.fraction_bits==Envelope.clock.fraction_bits&&!A->GetPresentation().bMealActive,TEXT("Cold refused-meal replay must preserve exact paired authority and fractional clock with no active use")))return false;
        FString AfterSha;return Need(HashFile(Dir/TEXT("CafeWorldRentCareV5.slot.json"),AfterSha)&&AfterSha==Hash,TEXT("Cold consumer must not rewrite producer slot"));
    }
public:
    FWorldV3Boundary(FAutomationTestBase* T,const FLivingTownCafeBinding& InBinding,const TArray<FVector>& InRoute,bool Cold,bool Qualified=false,bool RequireRootCorrected=false):Test(T),Binding(InBinding),Route(InRoute),bCold(Cold),bQualified(Qualified),bRequireRootCorrected(RequireRootCorrected){}
    virtual ~FWorldV3Boundary(){
        if(auto* PC=TestedController.Get())PC->RequestCancelMeal();
        if(auto* Mesh=TestedMesh.Get()){Mesh->bEnableAnimation=bOriginalEnable;Mesh->GlobalAnimRateScale=OriginalGlobalRate;if(auto* Player=Mesh->GetSingleNodeInstance())if(Player==OriginalPlayer.Get())Player->SetPlayRate(OriginalRate);}
    }
    virtual bool Update()override{
        if(bDone)return true;if(FPlatformTime::Seconds()>Deadline){Need(false,TEXT("Actual WorldV3 public boundary timed out"));return true;}
        UWorld* World=nullptr;int32 Count=0;for(const auto& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::PIE||C.WorldType==EWorldType::Game)){World=C.World();++Count;}
        if(!Need(Count<=1,TEXT("Exactly one actual game world is required"))||!World||!World->HasBegunPlay())return bDone;
        if(!Need(World->GetAuthGameMode()&&World->GetAuthGameMode()->GetClass()==ALivingTownCafeWorldV3GameMode::StaticClass()&&World->GetNetMode()==NM_Standalone&&World->GetGameInstance()&&!World->GetGameInstance()->GetSubsystem<ULivingTownLeaseSubsystem>()&&!World->GetSubsystem<ULivingTownCafePropertyV2Subsystem>(),TEXT("Exact standalone WorldV3 scenario must have no competing legacy or PropertyV2 authority")))return true;
        auto* A=World->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();auto* PC=Cast<ALivingTownCafeWorldV3Controller>(World->GetFirstPlayerController());auto* Pawn=PC?Cast<ACharacter>(PC->GetPawn()):nullptr;
        if(!A||!A->IsPrepared()||!PC||!PC->HasNativePersona()||!Pawn||!Pawn->GetCharacterMovement()->IsMovingOnGround())return false;
        if(!Need(PC->GetNativePersona()==ELivingTownCafeWorldPersona::Ben&&Pawn->GetController()==PC&&PC->GetViewTarget()==Pawn&&!World->IsPaused(),TEXT("Actual live authored Ben session required")))return true;
        if(const auto* Old=World->GetSubsystem<ULivingTownCafeProjectionSubsystem>())if(!Need(!Old->IsReady()&&!Old->IsScenePrepared(),TEXT("Legacy projection cannot prepare beside WorldV3")))return true;
        if(bCold){bDone=true;Cold(PC,A,Pawn);return true;}
        const auto Feet=Pawn->GetActorLocation()-FVector(0,0,Pawn->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());const double Time=World->GetTimeSeconds();
        if(LastSample<0){if(!Need(Feet.Equals(Route[0],2),TEXT("Natural journey must start at the exact source spawn")))return true;LastFeet=Feet;LastSample=Time;}
        if(Time-LastSample>=.05){const double D=FVector::Dist2D(Feet,LastFeet);if(!Need(D<=Binding.WalkSpeedCmPerSecond*(Time-LastSample)+2,TEXT("No position/time/animation substitution is permitted")))return true;WalkDistance+=D;LastFeet=Feet;LastSample=Time;++Samples;}
        if(Waypoint<Route.Num()){FVector Delta=Route[Waypoint]-Feet;Delta.Z=0;if(Delta.Size2D()>2){PC->SetControlRotation(Delta.Rotation());Pawn->AddMovementInput(Delta.GetSafeNormal2D(),1);return false;}Pawn->GetCharacterMovement()->StopMovementImmediately();++Waypoint;return false;}
        if(FaceSince<0){if(!Need(Samples>=12&&WalkDistance>=480,TEXT("Walk the entire authored cafe route before requesting a meal")))return true;Pawn->SetActorRotation(FRotator(0,(Binding.CounterUsePointCm-Pawn->GetActorLocation()).Rotation().Yaw,0));FaceSince=Time;return false;}
        if(Time-FaceSince<.25||(PlaybackStage==0&&!A->GetPresentation().bReachable))return false;
        if(bQualified){const bool Finished=QualifiedPlayback(World,PC,A,Pawn);if(Finished)bDone=true;return Finished;}
        bDone=true;Boundary(World,PC,A,Pawn);return true;
    }
};
bool StartBoundary(FAutomationTestBase* Test,bool Cold,bool Qualified=false,bool RequireRootCorrected=false){
    if(LivingTownCafeNativeBackend::Selected()!=B::Backend::WorldV3||!FParse::Param(FCommandLine::Get(),Qualified?TEXT("LivingTownCafeWorldQualifiedJourney"):Cold?TEXT("LivingTownCafeWorldColdRestore"):TEXT("LivingTownCafeWorldRefusalJourney"))){Test->AddError(TEXT("Explicit WorldV3 and exact boundary test opt-in required"));return false;}
    const FString Folder=FPaths::ProjectContentDir()/TEXT("LivingTown");FLivingTownCafeBinding Binding;FString H,Json,Error;TSharedPtr<FJsonObject> O;const TArray<TSharedPtr<FJsonValue>>* Points=nullptr;TArray<FVector> Route;
    if(!FLivingTownCafeBinding::ReadQualifiedFile(Folder/TEXT("CafeProjectionBinding.json"),Binding,Error)||!HashFile(Folder/TEXT("CafeJourneyRoute.json"),H)||H!=TEXT("38d98ee0c968647be6a1a89eac2abfe7c4b8a65b8732248f62fd3e7f54113846")||!FFileHelper::LoadFileToString(Json,*(Folder/TEXT("CafeJourneyRoute.json")))||!Object(Json,O)||!O->TryGetArrayField(TEXT("route_feet_cm"),Points)||Points->Num()!=3){Test->AddError(TEXT("Actual qualified cafe binding and frozen three-point source route required"));return false;}
    for(const auto& V:*Points){if(!V||V->Type!=EJson::Array||V->AsArray().Num()!=3){Test->AddError(TEXT("Invalid source route"));return false;}const auto& XYZ=V->AsArray();Route.Add(FVector(XYZ[0]->AsNumber(),XYZ[1]->AsNumber(),XYZ[2]->AsNumber()));}
    if(!Route[0].Equals(Binding.SpawnFeetCm,.1)){Test->AddError(TEXT("Source route spawn mismatch"));return false;}
    if(!AutomationOpenMap(TEXT("/Engine/Maps/Entry"),true))return false;ADD_LATENT_AUTOMATION_COMMAND(FWorldV3Boundary(Test,Binding,Route,Cold,Qualified,RequireRootCorrected));return true;
}
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafeWorldV3RefusalJourney,"LivingTown.WorldV3.ActualPublicBoundaryRefusal",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafeWorldV3RefusalJourney::RunTest(const FString&){return StartBoundary(this,false);}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafeWorldV3ColdRestore,"LivingTown.WorldV3.ColdPublicBoundaryRestore",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafeWorldV3ColdRestore::RunTest(const FString&){return StartBoundary(this,true);}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafeWorldV3QualifiedPlayback,"LivingTown.WorldV3.QualifiedProviderAnimationOwnership",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafeWorldV3QualifiedPlayback::RunTest(const FString&){return StartBoundary(this,false,true);}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafeWorldV3QualifiedRootCorrectedPlayback,"LivingTown.WorldV3.QualifiedProviderRootCorrectedOwnership",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafeWorldV3QualifiedRootCorrectedPlayback::RunTest(const FString&){return StartBoundary(this,false,true,true);}
namespace {
class FOffCounterSaveInput final:public IAutomationLatentCommand {
    FAutomationTestBase* Test;double Deadline=FPlatformTime::Seconds()+60;
    TWeakObjectPtr<ALivingTownCafeWorldV3Controller> InputController;
    FTransform SpawnTransform;FString AuthorityBefore;int64 AriaBefore=0,BenBefore=0,StockBefore=0,RevisionBefore=0;bool bPressed=false;
    bool Need(bool Ok,const TCHAR* Why){if(!Ok)Test->AddError(Why);return Ok;}
    void Release(){if(bPressed)if(auto* PC=InputController.Get())PC->InputKey(FInputKeyEventArgs::CreateSimulated(EKeys::F5,IE_Released,0.f));bPressed=false;}
public:
    explicit FOffCounterSaveInput(FAutomationTestBase* InTest):Test(InTest){}
    virtual ~FOffCounterSaveInput(){Release();}
    virtual bool Update()override{
        if(FPlatformTime::Seconds()>Deadline){Release();Need(false,TEXT("Actual off-counter F5 input/save feedback timed out"));return true;}
        UWorld* World=nullptr;int32 Count=0;for(const auto& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::PIE||C.WorldType==EWorldType::Game)){World=C.World();++Count;}
        if(!Need(Count<=1,TEXT("One actual game world required for F5 regression")))return true;if(!World||!World->HasBegunPlay())return false;
        if(!Need(World->GetNetMode()==NM_Standalone&&World->GetAuthGameMode()&&World->GetAuthGameMode()->GetClass()==ALivingTownCafeWorldV3GameMode::StaticClass()&&World->GetGameInstance()&&!World->GetGameInstance()->GetSubsystem<ULivingTownLeaseSubsystem>()&&!World->GetSubsystem<ULivingTownCafePropertyV2Subsystem>(),TEXT("Exact exclusive standalone WorldV3 scenario required for F5 input")))return true;
        auto* A=World->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();auto* PC=Cast<ALivingTownCafeWorldV3Controller>(World->GetFirstPlayerController());auto* Pawn=PC?Cast<ACharacter>(PC->GetPawn()):nullptr;auto* HUD=PC?Cast<ALivingTownCafeWorldV3HUD>(PC->GetHUD()):nullptr;
        if(!A||!A->IsPrepared()||!PC||!PC->HasNativePersona()||!Pawn||!HUD||!Pawn->GetCharacterMovement()->IsMovingOnGround())return false;
        const auto& V=A->GetPresentation();const FVector Feet=Pawn->GetActorLocation()-FVector(0,0,Pawn->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());
        if(!Need(!World->IsPaused()&&PC->GetNativePersona()==ELivingTownCafeWorldPersona::Ben&&PC->GetViewTarget()==Pawn&&Pawn->GetController()==PC&&V.bSessionReady&&!V.bReachable&&!V.bMealActive&&Feet.Equals(A->GetBinding().SpawnFeetCm,2.f),TEXT("Real grounded Ben at the actual source spawn, outside counter reach; no pose/position/balance substitution")))return true;
        const FString Slot=FPaths::ProjectSavedDir()/TEXT("CafeWorldV3/CafeWorldRentCareV5.slot.json");
        if(!bPressed){
            if(!Need(!IFileManager::Get().FileExists(*Slot)&&PC->GetOperationNotice().IsEmpty(),TEXT("Fresh native slot and controller input history required")))return true;
            InputController=PC;SpawnTransform=Pawn->GetActorTransform();AuthorityBefore=V.Notice;AriaBefore=V.AriaCoins;BenBefore=V.BenCoins;StockBefore=V.Stock;RevisionBefore=V.Revision;
            PC->InputKey(FInputKeyEventArgs::CreateSimulated(EKeys::F5,IE_Pressed,1.f));bPressed=true;return false;
        }
        // InputKey enters the real controller/PlayerInput stack; natural world
        // frames process the bound F5 callback. Never call Save/SaveSlot directly.
        if(PC->GetOperationNotice().IsEmpty())return false;
        Release();const auto Rows=HUD->GetFeedbackRows();
        if(!Need(PC->GetOperationNotice()==TEXT("Cafe saved.")&&Rows.Num()==2&&Rows[0]==AuthorityBefore&&Rows[0]==V.Notice&&Rows[1]==TEXT("Last action: Cafe saved."),TEXT("Actual off-counter F5 result and live authority notice must occupy distinct displayed text rows")))return true;
        if(!Need(Pawn->GetActorTransform().Equals(SpawnTransform,.1f)&&V.AriaCoins==AriaBefore&&V.BenCoins==BenBefore&&V.Stock==StockBefore&&V.Revision==RevisionBefore,TEXT("Saving through input cannot move the pawn, pay, consume stock or add authority events")))return true;
        FString Json;W3::CareEnvelope Envelope;if(!Need(FFileHelper::LoadFileToString(Json,*Slot)&&Payload(Json,Envelope),TEXT("F5 callback must create the real paired V5 slot")))return true;
        auto Evidence=MakeShared<FJsonObject>();Evidence->SetStringField(TEXT("status"),TEXT("PASS_ACTUAL_CONTROLLER_F5_OFFCOUNTER_TEXT_COMPOSITION_ONLY"));Evidence->SetStringField(TEXT("input_route"),TEXT("FInputKeyEventArgs simulated F5 pressed/released through actual controller and natural PlayerInput frames"));Evidence->SetStringField(TEXT("authority_row"),Rows[0]);Evidence->SetStringField(TEXT("last_action_row"),Rows[1]);Evidence->SetBoolField(TEXT("actual_counter_reachable"),V.bReachable);Evidence->SetBoolField(TEXT("pixels_or_hardware_keypress_claimed"),false);FString SlotHash;HashFile(Slot,SlotHash);Evidence->SetStringField(TEXT("slot_sha256"),SlotHash);
        FString Text;FJsonSerializer::Serialize(Evidence,TJsonWriterFactory<>::Create(&Text));const FString Path=FPaths::ProjectSavedDir()/TEXT("CafeWorldV3/OffCounterSaveFeedback.json");Need(!IFileManager::Get().FileExists(*Path)&&FFileHelper::SaveStringToFile(Text,*Path,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM),TEXT("Fresh off-counter input evidence must be retained"));return true;
    }
};
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafeWorldV3OffCounterSaveFeedback,"LivingTown.WorldV3.OffCounterSaveFeedbackInput",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafeWorldV3OffCounterSaveFeedback::RunTest(const FString&){
    if(LivingTownCafeNativeBackend::Selected()!=B::Backend::WorldV3||!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeWorldHudJourney"))){AddError(TEXT("Explicit WorldV3 HUD input regression opt-in required"));return false;}
    if(!AutomationOpenMap(TEXT("/Engine/Maps/Entry"),true))return false;ADD_LATENT_AUTOMATION_COMMAND(FOffCounterSaveInput(this));return true;
}

#endif
