#include "LivingTownCafeHUD.h"
#include "LivingTownCafePlayerController.h"
#include "LivingTownCafeProjectionSubsystem.h"
#include "LivingTownCafeGameMode.h"
#include "LivingTownCafeWorldV3Scenario.h"
#include "LivingTownCafeWorldV3Subsystem.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Tests/AutomationCommon.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "Engine/GameViewportClient.h"
#include "GameFramework/Character.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/PlayerInput.h"
#include "InputCoreTypes.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformTime.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "UnrealClient.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonReader.h"

namespace {
UWorld* GameWorld(FAutomationTestBase* Test,bool& Invalid)
{
    UWorld* World=nullptr;int32 Count=0;
    for(const auto& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::PIE||C.WorldType==EWorldType::Game)){World=C.World();++Count;}
    if(Count>1){Test->AddError(TEXT("HUD input regression requires one actual game world"));Invalid=true;return nullptr;}
    return World;
}
bool StockSaveLoadBinding(const FKeyBind& Bind)
{
    const bool Modifiers=!Bind.Control&&!Bind.Shift&&!Bind.Alt&&!Bind.Cmd&&!Bind.bIgnoreCtrl&&!Bind.bIgnoreAlt&&!Bind.bIgnoreCmd;
    return Modifiers&&!Bind.bIgnoreShift&&((Bind.Key==EKeys::F5&&Bind.Command==TEXT("viewmode shadercomplexity"))||(Bind.Key==EKeys::F9&&Bind.Command==TEXT("shot showui")));
}
TArray<FString> OtherBindings(const UPlayerInput* Input)
{
    TArray<FString> Rows;
    for(const auto& B:Input->DebugExecBindings)if(!StockSaveLoadBinding(B))Rows.Add(FString::Printf(TEXT("%s|%s|%d%d%d%d%d%d%d%d%d"),*B.Key.ToString(),*B.Command,int(B.Control),int(B.Shift),int(B.Alt),int(B.Cmd),int(B.bIgnoreCtrl),int(B.bIgnoreShift),int(B.bIgnoreAlt),int(B.bIgnoreCmd),int(B.bDisabled)));
    return Rows;
}
class FCafeHudSaveLoadInput final:public IAutomationLatentCommand {
    FAutomationTestBase* Test;double Deadline=FPlatformTime::Seconds()+60,PressedAt=0;uint64 PressedFrame=0;
    TWeakObjectPtr<ALivingTownCafePlayerController> Controller;TWeakObjectPtr<ACharacter> OriginalPawn;
    FTransform OriginalTransform;FLivingTownLeaseView Before;TArray<FString> OtherBefore;FString SavedHash,ScreenshotFilename;
    FDelegateHandle ScreenshotHandle;int32 ScreenshotsProcessed=0,ViewMode=0,Stage=0;int64 RefusalEventCount=0;FKey PressedKey;bool bPressed=false;
    bool Need(bool Ok,const TCHAR* Why){if(!Ok)Test->AddError(Why);return Ok;}
    void Press(ALivingTownCafePlayerController* PC,FKey Key){Controller=PC;PressedKey=Key;bPressed=true;PressedAt=FPlatformTime::Seconds();PressedFrame=GFrameCounter;PC->InputKey(FInputKeyEventArgs::CreateSimulated(Key,IE_Pressed,1.f));}
    void Release(){if(bPressed)if(auto* PC=Controller.Get())PC->InputKey(FInputKeyEventArgs::CreateSimulated(PressedKey,IE_Released,0.f));bPressed=false;}
    bool LaterFrame()const{return GFrameCounter>=PressedFrame+2&&FPlatformTime::Seconds()-PressedAt>=.1;}
public:
    explicit FCafeHudSaveLoadInput(FAutomationTestBase* In):Test(In){}
    virtual ~FCafeHudSaveLoadInput(){Release();if(ScreenshotHandle.IsValid())FScreenshotRequest::OnScreenshotRequestProcessed().Remove(ScreenshotHandle);}
    virtual bool Update()override{
        if(FPlatformTime::Seconds()>Deadline){Release();Need(false,TEXT("Actual Cafe E/F5/F9 input regression timed out"));return true;}
        bool Invalid=false;UWorld* W=GameWorld(Test,Invalid);if(Invalid)return true;if(!W||!W->HasBegunPlay())return false;
        if(!Need(W->GetNetMode()==NM_Standalone&&W->GetAuthGameMode()&&W->GetAuthGameMode()->GetClass()==ALivingTownCafeGameMode::StaticClass(),TEXT("Exact standalone Cafe HUD/controller scenario required")))return true;
        auto* P=W->GetSubsystem<ULivingTownCafeProjectionSubsystem>();auto* PC=Cast<ALivingTownCafePlayerController>(W->GetFirstPlayerController());auto* Pawn=PC?Cast<ACharacter>(PC->GetPawn()):nullptr;auto* HUD=PC?Cast<ALivingTownCafeHUD>(PC->GetHUD()):nullptr;auto* Viewport=W->GetGameInstance()?W->GetGameInstance()->GetGameViewportClient():nullptr;
        if(!P||!P->IsReady()||!PC||!Pawn||!HUD||!Viewport||!PC->PlayerInput||!Pawn->GetCharacterMovement()->IsMovingOnGround())return false;
        const FString Slot=FPaths::ProjectSavedDir()/TEXT("CafePilot/CafeProjection.slot.json");
        if(Stage==0){
            if(!Need(!W->IsPaused()&&PC->GetViewTarget()==Pawn&&Pawn->GetController()==PC&&!P->GetPresentation().bReachable&&!HUD->IsCounterContextVisible()&&!IFileManager::Get().FileExists(*Slot)&&PC->GetOperationNotice().IsEmpty()&&!FScreenshotRequest::IsScreenshotRequested(),TEXT("Fresh off-counter game session and native slot required; no relocation or save substitution")))return true;
            int32 F5=0,F9=0;
            for(const auto& Bind:PC->PlayerInput->DebugExecBindings)if(StockSaveLoadBinding(Bind)){
                if(!Need(Bind.bDisabled,TEXT("Exact conflicting stock debug command must be disabled on the actual PlayerInput")))return true;
                if(Bind.Key==EKeys::F5)++F5;else ++F9;
            }
            if(!Need(F5>0&&F9>0,TEXT("Both installed stock conflicts must actually be present and suppressed")))return true;
            OriginalPawn=Pawn;OriginalTransform=Pawn->GetActorTransform();Before=P->GetLeaseView();OtherBefore=OtherBindings(PC->PlayerInput);ViewMode=Viewport->ViewModeIndex;ScreenshotFilename=FScreenshotRequest::GetFilename();
            ScreenshotHandle=FScreenshotRequest::OnScreenshotRequestProcessed().AddLambda([this](){++ScreenshotsProcessed;});
            // Generate a genuine live refusal first, so a later saved notice
            // cannot replace it. Authority still decides the off-counter action.
            Press(PC,EKeys::E);Stage=1;return false;
        }
        if(!Need(OriginalPawn.Get()==Pawn&&Pawn->GetActorTransform().Equals(OriginalTransform,.1f)&&PC->GetViewTarget()==Pawn&&Pawn->GetController()==PC,TEXT("HUD/save/load input must retain the same possessed pawn, camera target and transform")))return true;
        const auto Now=P->GetLeaseView();
        if(!Need(Now.BenCoins==Before.BenCoins&&Now.AriaCoins==Before.AriaCoins&&Now.OperatorId.Value==Before.OperatorId.Value&&Now.OwnerId.Value==Before.OwnerId.Value,TEXT("Off-counter refusal and save/load cannot pay or transfer property or operator authority")))return true;
        if(!Need(Viewport->ViewModeIndex==ViewMode&&ScreenshotsProcessed==0&&!FScreenshotRequest::IsScreenshotRequested()&&FScreenshotRequest::GetFilename()==ScreenshotFilename&&OtherBindings(PC->PlayerInput)==OtherBefore,TEXT("F5/F9 must not change debug view, request a screenshot or mutate unrelated debug bindings")))return true;
        if(Stage>=2&&!Need(Now.EventCount==RefusalEventCount,TEXT("F5/F9 must retain exactly the one recorded refusal event without appending events")))return true;
        if(Stage==1){
            if(!Need(Now.EventCount>=Before.EventCount&&Now.EventCount<=Before.EventCount+1,TEXT("One E press may append exactly one refusal event")))return true;
            if(P->GetStatus()!=TEXT("Action refused: not_at_commercial_counter")||!LaterFrame())return false;
            if(!Need(Now.EventCount==Before.EventCount+1,TEXT("Actual off-counter E refusal appends one authoritative property_refused event")))return true;
            RefusalEventCount=Now.EventCount;Release();Press(PC,EKeys::F5);Stage=2;return false;
        }
        if(Stage==2){
            if(PC->GetOperationNotice()!=TEXT("Café ledger saved.")||!LaterFrame())return false;
            Release();TArray<uint8> Bytes;FString Saved,Inner,Error;
            if(!Need(FFileHelper::LoadFileToArray(Bytes,*Slot)&&LivingTownCafeJournal::Sha256(Bytes,SavedHash)&&FFileHelper::LoadFileToString(Saved,*Slot)&&LivingTownCafeJournal::Decode(Saved,P->GetBinding(),Inner,Error),TEXT("Actual F5 callback must write the real valid source-bound slot")))return true;
            // Inspect the real F5-written, source-bound envelope through the
            // existing Decode API. No new public accessor or direct Save call.
            TSharedPtr<FJsonObject> JournalObject;const TArray<TSharedPtr<FJsonValue>>* Events=nullptr;
            if(!Need(FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Inner),JournalObject)&&JournalObject.IsValid()&&JournalObject->TryGetArrayField(TEXT("journal"),Events)&&Events&&Events->Num()==RefusalEventCount&&!Events->IsEmpty()&&Events->Last().IsValid()&&Events->Last()->Type==EJson::Object,TEXT("Actual saved inner journal contains exactly the recorded native event count")))return true;
            const auto Refusal=Events->Last()->AsObject();FString Type,Note;bool Accepted=true;
            if(!Need(Refusal.IsValid()&&Refusal->TryGetStringField(TEXT("type"),Type)&&Type==TEXT("property_refused")&&Refusal->TryGetStringField(TEXT("note"),Note)&&Note==TEXT("not_at_commercial_counter")&&Refusal->TryGetBoolField(TEXT("accepted"),Accepted)&&!Accepted&&Refusal->HasTypedField<EJson::Null>(TEXT("amt"))&&Refusal->HasTypedField<EJson::Null>(TEXT("amount"))&&Refusal->HasTypedField<EJson::Null>(TEXT("pay_event_id")),TEXT("F5 preserves the exact uncharged property_refused event and reason")))return true;
            const auto Rows=HUD->GetFeedbackRows();const auto& Live=P->GetPresentation().Feedback;
            if(!Need(P->GetStatus()==TEXT("Action refused: not_at_commercial_counter")&&!Live.IsEmpty()&&Rows.Num()==Live.Num()+1,TEXT("The exact live off-counter failure and saved operation result remain separate")))return true;
            for(int32 I=0;I<Live.Num();++I)if(!Need(Rows[I]==Live[I],TEXT("Saving cannot mask any live authority feedback row")))return true;
            if(!Need(Rows.Last()==TEXT("Last action: Café ledger saved."),TEXT("Actual saved feedback remains observable outside counter context")))return true;
            Press(PC,EKeys::F9);Stage=3;return false;
        }
        if(PC->GetOperationNotice()!=TEXT("Matching café ledger loaded; position unchanged.")||!LaterFrame())return false;
        Release();TArray<uint8> Bytes;FString AfterHash;
        if(!Need(FFileHelper::LoadFileToArray(Bytes,*Slot)&&LivingTownCafeJournal::Sha256(Bytes,AfterHash)&&AfterHash==SavedHash,TEXT("Actual F9 loads the saved slot without rewriting or replacing it")))return true;
        auto Evidence=MakeShared<FJsonObject>();Evidence->SetStringField(TEXT("status"),TEXT("PASS_ACTUAL_CAFE_OFFCOUNTER_E_F5_F9_INPUT_SLOT_AND_HUD"));Evidence->SetStringField(TEXT("slot_sha256"),SavedHash);Evidence->SetStringField(TEXT("refusal_reason"),TEXT("not_at_commercial_counter"));Evidence->SetStringField(TEXT("event_count_before_E"),LexToString(Before.EventCount));Evidence->SetStringField(TEXT("event_count_after_E"),LexToString(RefusalEventCount));Evidence->SetBoolField(TEXT("one_refusal_event_persisted"),true);Evidence->SetBoolField(TEXT("save_load_appended_no_events"),true);Evidence->SetBoolField(TEXT("same_pawn_transform_possession_and_authority"),true);Evidence->SetBoolField(TEXT("no_debug_view_or_screenshot"),true);Evidence->SetBoolField(TEXT("live_feedback_independent_from_history"),true);Evidence->SetBoolField(TEXT("pixels_or_hardware_keypress_claimed"),false);FString Json;FJsonSerializer::Serialize(Evidence,TJsonWriterFactory<>::Create(&Json));const FString Out=FPaths::ProjectSavedDir()/TEXT("CafePilot/HudSaveLoadInput.json");
        Need(!IFileManager::Get().FileExists(*Out)&&FFileHelper::SaveStringToFile(Json,*Out,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM),TEXT("Fresh native input evidence retained"));return true;
    }
};
class FWorldV3HelpInput final:public IAutomationLatentCommand {
    FAutomationTestBase* Test;double Deadline=FPlatformTime::Seconds()+60;uint64 PressedFrame=0;int32 Stage=0;bool bPressed=false;
    TWeakObjectPtr<ALivingTownCafeWorldV3Controller> Controller;TWeakObjectPtr<ACharacter> OriginalPawn;FTransform OriginalTransform;int64 Aria=0,Ben=0,Stock=0,Revision=0;
    bool Need(bool Ok,const TCHAR* Why){if(!Ok)Test->AddError(Why);return Ok;}
    void Press(ALivingTownCafeWorldV3Controller* PC){Controller=PC;bPressed=true;PressedFrame=GFrameCounter;PC->InputKey(FInputKeyEventArgs::CreateSimulated(EKeys::H,IE_Pressed,1.f));}
    void Release(){if(bPressed)if(auto* PC=Controller.Get())PC->InputKey(FInputKeyEventArgs::CreateSimulated(EKeys::H,IE_Released,0.f));bPressed=false;}
public:
    explicit FWorldV3HelpInput(FAutomationTestBase* In):Test(In){}
    virtual ~FWorldV3HelpInput(){Release();}
    virtual bool Update()override{
        if(FPlatformTime::Seconds()>Deadline){Release();Need(false,TEXT("Actual WorldV3 H controls input timed out"));return true;}
        bool Invalid=false;UWorld* W=GameWorld(Test,Invalid);if(Invalid)return true;if(!W||!W->HasBegunPlay())return false;
        if(!Need(W->GetNetMode()==NM_Standalone&&W->GetAuthGameMode()&&W->GetAuthGameMode()->GetClass()==ALivingTownCafeWorldV3GameMode::StaticClass(),TEXT("Exact standalone WorldV3 scenario required")))return true;
        auto* P=W->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();auto* PC=Cast<ALivingTownCafeWorldV3Controller>(W->GetFirstPlayerController());auto* Pawn=PC?Cast<ACharacter>(PC->GetPawn()):nullptr;auto* HUD=PC?Cast<ALivingTownCafeWorldV3HUD>(PC->GetHUD()):nullptr;
        if(!P||!P->IsPrepared()||!PC||!PC->HasNativePersona()||!Pawn||!HUD||!Pawn->GetCharacterMovement()->IsMovingOnGround())return false;
        const auto& V=P->GetPresentation();
        if(Stage==0){
            if(!Need(!W->IsPaused()&&PC->GetViewTarget()==Pawn&&Pawn->GetController()==PC&&!V.bReachable&&!V.bMealActive&&!HUD->IsCounterContextVisible()&&!PC->AreControlsVisible()&&HUD->GetControlRows().Num()==1,TEXT("Real off-counter WorldV3 starts compact with no nearby-counter card")))return true;
            OriginalPawn=Pawn;OriginalTransform=Pawn->GetActorTransform();Aria=V.AriaCoins;Ben=V.BenCoins;Stock=V.Stock;Revision=V.Revision;Press(PC);Stage=1;return false;
        }
        if(!Need(OriginalPawn.Get()==Pawn&&Pawn->GetActorTransform().Equals(OriginalTransform,.1f)&&PC->GetViewTarget()==Pawn&&Pawn->GetController()==PC&&V.AriaCoins==Aria&&V.BenCoins==Ben&&V.Stock==Stock&&V.Revision==Revision,TEXT("Help input cannot change pawn, possession, money, stock or authority revision")))return true;
        if(GFrameCounter<PressedFrame+2)return false;
        if(Stage==1){
            if(!PC->AreControlsVisible())return false;Release();const auto Rows=HUD->GetControlRows();
            const bool AdvertisesEat=Rows.ContainsByPredicate([](const FString& Row){return Row.StartsWith(TEXT("E "));});
            if(!Need(Rows.Contains(TEXT("I Import older save"))&&AdvertisesEat==(V.bMealAvailable&&!V.bMealActive),TEXT("Expanded controls preserve I import and only advertise an available eat action")))return true;
            PressedFrame=GFrameCounter;Stage=2;return false;
        }
        if(Stage==2){Press(PC);Stage=3;return false;}
        if(PC->AreControlsVisible())return false;Release();Need(HUD->GetControlRows().Num()==1&&!HUD->IsCounterContextVisible(),TEXT("Second real H input closes help without creating cafe context"));return true;
    }
};
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafeHudSaveLoadInput,"LivingTown.Native.CafeHudSaveLoadInput",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafeHudSaveLoadInput::RunTest(const FString&)
{
    if(LivingTownCafeNativeBackend::Selected()!=living_town::cafe_backend_v3::Backend::LegacyV1||!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeHudInput"))){AddError(TEXT("Explicit qualified Cafe HUD input opt-in required"));return false;}
    if(!AutomationOpenMap(TEXT("/Engine/Maps/Entry"),true))return false;ADD_LATENT_AUTOMATION_COMMAND(FCafeHudSaveLoadInput(this));return true;
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownWorldV3ControlsInput,"LivingTown.WorldV3.ControlsInput",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownWorldV3ControlsInput::RunTest(const FString&)
{
    if(LivingTownCafeNativeBackend::Selected()!=living_town::cafe_backend_v3::Backend::WorldV3||!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeWorldHudJourney"))){AddError(TEXT("Explicit WorldV3 HUD input opt-in required"));return false;}
    if(!AutomationOpenMap(TEXT("/Engine/Maps/Entry"),true))return false;ADD_LATENT_AUTOMATION_COMMAND(FWorldV3HelpInput(this));return true;
}
#endif
