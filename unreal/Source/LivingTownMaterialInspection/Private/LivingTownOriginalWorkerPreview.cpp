#include "LivingTownOriginalWorkerPreview.h"
#include "Editor.h"
#include "PlayInEditorDataTypes.h"
#include "Settings/LevelEditorPlaySettings.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameViewportClient.h"
#include "Engine/LocalPlayer.h"
#include "Engine/SkeletalMesh.h"
#include "Components/SkeletalMeshComponent.h"
#include "Slate/SceneViewport.h"
#include "Widgets/SWindow.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownCafeWorldV3Scenario.h"
#include "LivingTownCafeWorldV3Subsystem.h"
#include "LivingTownOriginalWorkerAssembly.h"
#include "CoreGlobals.h"
#include "HAL/PlatformTime.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/Guid.h"
#include "UObject/Package.h"
#include "Dom/JsonObject.h"
#include "Dom/JsonValue.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"

namespace
{
enum class EPreviewPhase : uint8 { Requested, RestorePending, ResizePending, Ready, Failed };
struct FPreviewState
{
    FString Token=FGuid::NewGuid().ToString(EGuidFormats::Digits);
    FString Error;
    EPreviewPhase Phase=EPreviewPhase::Requested;
    FIntPoint Desired=FIntPoint::ZeroValue;
    double Deadline=0, LastResizeSeconds=0;
    uint64 RequestFrame=0, RestoreFrame=0, ResizeFrame=0, WitnessFrame=0;
    int32 RestoreCalls=0, ResizeCalls=0, Witnesses=0;
    bool bWorldLatched=false, bSessionLatched=false;
    TWeakObjectPtr<UWorld> World;
    TWeakObjectPtr<ALivingTownCafeWorldV3Controller> Controller;
    TWeakObjectPtr<ALivingTownCafeCharacter> Pawn;
    TWeakObjectPtr<UGameViewportClient> Client;
    TWeakPtr<SWindow> Window;
    FVector2D LastRequestedClient=FVector2D::ZeroVector;
};
TUniquePtr<FPreviewState> State;

const TCHAR* PhaseName(EPreviewPhase Phase)
{
    switch(Phase)
    {
    case EPreviewPhase::Requested:return TEXT("WAITING_FOR_ORDINARY_PIE");
    case EPreviewPhase::RestorePending:return TEXT("WAITING_FOR_ACTUAL_RESTORE");
    case EPreviewPhase::ResizePending:return TEXT("WAITING_FOR_ACTUAL_SIZE");
    case EPreviewPhase::Ready:return TEXT("READY_EXACT_VIEWPORT_SIZE");
    default:return TEXT("FAILED");
    }
}
void Point(const TSharedRef<FJsonObject>& Json,const TCHAR* Key,double X,double Y)
{
    Json->SetArrayField(Key,{MakeShared<FJsonValueNumber>(X),MakeShared<FJsonValueNumber>(Y)});
}
FString Report(const TCHAR* Status,const FString& Error=FString(),TSharedPtr<FJsonObject> Readback=nullptr)
{
    TSharedRef<FJsonObject> Root=MakeShared<FJsonObject>();
    Root->SetStringField(TEXT("schema"),TEXT("living_town.original_worker_ordinary_preview.v1"));
    Root->SetStringField(TEXT("status"),Status);
    Root->SetStringField(TEXT("error"),Error);
    Root->SetBoolField(TEXT("Editor_only"),true);
    Root->SetStringField(TEXT("natural_frame"),LexToString(GFrameCounter));
    if(State)
    {
        Root->SetStringField(TEXT("scope_token"),State->Token);
        Root->SetStringField(TEXT("phase"),PhaseName(State->Phase));
        Point(Root,TEXT("requested_GameViewport_pixels"),State->Desired.X,State->Desired.Y);
        Root->SetNumberField(TEXT("restore_calls"),State->RestoreCalls);
        Root->SetNumberField(TEXT("resize_calls"),State->ResizeCalls);
        Root->SetNumberField(TEXT("distinct_frame_size_witnesses"),State->Witnesses);
        Point(Root,TEXT("last_requested_usable_client_pixels"),State->LastRequestedClient.X,State->LastRequestedClient.Y);
    }
    if(Readback)Root->SetObjectField(TEXT("actual"),Readback);
    FString Json;const TSharedRef<TJsonWriter<>> Writer=TJsonWriterFactory<>::Create(&Json);
    FJsonSerializer::Serialize(Root,Writer);return Json;
}
FString Fail(const FString& Why,TSharedPtr<FJsonObject> Readback=nullptr)
{
    State->Phase=EPreviewPhase::Failed;State->Error=Why;return Report(TEXT("FAILED"),Why,Readback);
}
bool EditorThread()
{
    return IsInGameThread()&&GIsEditor&&GEditor&&GEngine;
}
bool StandaloneSettings()
{
    const ULevelEditorPlaySettings* Settings=GetDefault<ULevelEditorPlaySettings>();
    EPlayNetMode Mode=PIE_Client;Settings->GetPlayNetMode(Mode);
    bool bRunUnderOneProcess=false;Settings->GetRunUnderOneProcess(bRunUnderOneProcess);
    int32 NumberOfClients=0;Settings->GetPlayNumberOfClients(NumberOfClients);
    return Mode==PIE_Standalone&&bRunUnderOneProcess&&NumberOfClients==1&&!Settings->bLaunchSeparateServer;
}

// Waiting is allowed only while this one request is creating its real world/player.
bool Observe(TSharedRef<FJsonObject> Actual,bool& bWaiting,FString& Error)
{
    bWaiting=false;
    int32 Worlds=0;UWorld* World=nullptr;
    for(const FWorldContext& Context:GEngine->GetWorldContexts())
    {
        if(Context.World()&&(Context.WorldType==EWorldType::PIE||Context.WorldType==EWorldType::Game))
        {++Worlds;World=Context.World();}
    }
    if(Worlds>1){Error=TEXT("Exactly one owned ordinary PIE world is required");return false;}
    if(!World)
    {
        if(State->bWorldLatched){Error=TEXT("The owned PIE world closed");return false;}
        if(GFrameCounter>State->RequestFrame+1&&!GEditor->IsPlaySessionInProgress()){Error=TEXT("The ordinary play request ended before an owned world was observed");return false;}
        bWaiting=true;return true;
    }
    if(State->bWorldLatched&&State->World.Get()!=World){Error=TEXT("The owned PIE world was replaced");return false;}
    if(!State->bWorldLatched){State->World=World;State->bWorldLatched=true;}
    Actual->SetStringField(TEXT("world"),World->GetPathName());
    if(World->WorldType!=EWorldType::PIE||World->GetNetMode()!=NM_Standalone||GEditor->IsSimulateInEditorInProgress()||UWorld::RemovePIEPrefix(World->GetOutermost()->GetName())!=TEXT("/Engine/Maps/Entry"))
    {Error=TEXT("Only the requested standalone Entry PIE world is accepted");return false;}
    if(!World->HasBegunPlay())
    {
        if(State->bSessionLatched){Error=TEXT("The owned world lost BeginPlay");return false;}
        bWaiting=true;return true;
    }
    ALivingTownCafeWorldV3GameMode* Mode=World->GetAuthGameMode<ALivingTownCafeWorldV3GameMode>();
    if(!Mode){Error=TEXT("Actual WorldV3 GameMode is required");return false;}
    ALivingTownCafeWorldV3Controller* PC=nullptr;int32 Players=0;
    for(FConstPlayerControllerIterator It=World->GetPlayerControllerIterator();It;++It)
    {++Players;PC=Cast<ALivingTownCafeWorldV3Controller>(It->Get());}
    if(Players>1){Error=TEXT("Exactly one actual local controller is required");return false;}
    if(!PC)
    {
        if(Players||State->bSessionLatched){Error=TEXT("The actual controller is missing or has the wrong class");return false;}
        bWaiting=true;return true;
    }
    ALivingTownCafeCharacter* Pawn=Cast<ALivingTownCafeCharacter>(PC->GetPawn());
    if(!Pawn)
    {
        if(PC->GetPawn()||State->bSessionLatched){Error=TEXT("The owned Ben pawn is missing or has the wrong class");return false;}
        bWaiting=true;return true;
    }
    ULivingTownCafeWorldV3Subsystem* Authority=World->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();
    if(!PC->IsLocalPlayerController()||PC->GetViewTarget()!=Pawn||!PC->HasNativePersona()||PC->GetNativePersona()!=ELivingTownCafeWorldPersona::Ben||!Authority||!Authority->IsPrepared()||!Pawn->HasOriginalWorkerAssembly()||!Pawn->GetMesh()->GetSkeletalMeshAsset()||Pawn->GetMesh()->GetSkeletalMeshAsset()->GetPathName()!=LivingTownOriginalWorker::Body)
    {Error=TEXT("Actual prepared OriginalWorker Ben/controller/view target is required");return false;}
    UGameViewportClient* Client=World->GetGameViewport();
    if(!Client||!PC->GetLocalPlayer()||PC->GetLocalPlayer()->ViewportClient!=Client)
    {Error=TEXT("Actual local Ben GameViewportClient is required");return false;}
    const FWorldContext* Context=GEngine->GetWorldContextFromWorld(World);
    const FSlatePlayInEditorInfo* Info=Context?GEditor->SlatePlayInEditorMap.Find(Context->ContextHandle):nullptr;
    FSceneViewport* Scene=Client->GetGameViewport();
    TSharedPtr<SWindow> Window=Client->GetWindow();
    if(!Info||!Scene||!Window||!Info->SlatePlayInEditorWindow.IsValid()||!Info->SlatePlayInEditorWindowViewport.IsValid())
    {
        Error=TEXT("The actually playing Ben has no live owned floating PIE viewport/window");return false;
    }
    if(Info->DestinationSlateViewport.IsValid()||Info->SlatePlayInEditorWindow.Pin()!=Window||Info->SlatePlayInEditorWindowViewport.Get()!=Scene||Scene->FindWindow()!=Window||Scene->GetPlayInEditorIsSimulate()||Scene->HasFixedSize()||!Window->IsViewportSizeDrivenByWindow())
    {Error=TEXT("Only this request's floating ordinary PIE window may be operated");return false;}
    if(State->bSessionLatched&&(State->Controller.Get()!=PC||State->Pawn.Get()!=Pawn||State->Client.Get()!=Client||State->Window.Pin()!=Window))
    {Error=TEXT("The owned Ben/controller/viewport/window identity changed");return false;}
    State->Controller=PC;State->Pawn=Pawn;State->Client=Client;State->Window=Window;State->bSessionLatched=true;
    int32 Width=0,Height=0;PC->GetViewportSize(Width,Height);
    const FVector2D ClientSize=Window->GetClientSizeInScreen();
    Actual->SetStringField(TEXT("game_mode"),Mode->GetClass()->GetPathName());
    Actual->SetStringField(TEXT("controller"),PC->GetPathName());
    Actual->SetStringField(TEXT("pawn"),Pawn->GetPathName());
    Actual->SetStringField(TEXT("view_target"),PC->GetViewTarget()->GetPathName());
    Actual->SetStringField(TEXT("body"),Pawn->GetMesh()->GetSkeletalMeshAsset()->GetPathName());
    Point(Actual,TEXT("PC_viewport_pixels"),Width,Height);
    Point(Actual,TEXT("scene_viewport_pixels"),Scene->GetSizeXY().X,Scene->GetSizeXY().Y);
    Point(Actual,TEXT("usable_client_pixels"),ClientSize.X,ClientSize.Y);
    Actual->SetBoolField(TEXT("window_maximized"),Window->IsWindowMaximized());
    Actual->SetBoolField(TEXT("window_minimized"),Window->IsWindowMinimized());
    Actual->SetBoolField(TEXT("owned_floating_PIE_window_verified"),true);
    if(Width<=0||Height<=0||Scene->GetSizeXY().X<=0||Scene->GetSizeXY().Y<=0){bWaiting=true;return true;}
    return true;
}

FString Process(const FString& Token,bool bOperate)
{
    if(!EditorThread())return Report(TEXT("REFUSED"),TEXT("Editor game thread is required"));
    if(!State||Token!=State->Token)return Report(TEXT("REFUSED"),TEXT("An exact live preview scope token is required"));
    if(State->Phase==EPreviewPhase::Failed)return Report(TEXT("FAILED"),State->Error);
    TSharedRef<FJsonObject> Actual=MakeShared<FJsonObject>();bool bWaiting=false;FString Error;
    if(!Observe(Actual,bWaiting,Error))return Fail(Error,Actual);
    if(FPlatformTime::Seconds()>State->Deadline&&State->Phase!=EPreviewPhase::Ready)return Fail(TEXT("Ordinary preview creation/size deadline expired"),Actual);
    if(bWaiting)return Report(TEXT("PENDING"),FString(),Actual);
    TSharedPtr<SWindow> Window=State->Window.Pin();ALivingTownCafeWorldV3Controller* PC=State->Controller.Get();
    FSceneViewport* Scene=State->Client->GetGameViewport();
    int32 Width=0,Height=0;PC->GetViewportSize(Width,Height);
    const bool bExact=Width==State->Desired.X&&Height==State->Desired.Y&&Scene->GetSizeXY()==State->Desired&&!Window->IsWindowMaximized()&&!Window->IsWindowMinimized();
    if(State->Phase==EPreviewPhase::Ready)
    {
        if(!bExact)return Fail(TEXT("The ready owned viewport no longer has the exact requested size"),Actual);
        return Report(TEXT("READY"),FString(),Actual);
    }
    if(!bOperate)return Report(TEXT("PENDING"),FString(),Actual);
    if(State->Phase==EPreviewPhase::Requested)
    {
        Window->Restore();++State->RestoreCalls;State->RestoreFrame=GFrameCounter;
        State->Deadline=FPlatformTime::Seconds()+15.0;State->Phase=EPreviewPhase::RestorePending;
        return Report(TEXT("PENDING"),FString(),Actual);
    }
    if(Window->IsWindowMaximized()||Window->IsWindowMinimized()||GFrameCounter<=State->RestoreFrame)return Report(TEXT("PENDING"),FString(),Actual);
    if(State->Phase==EPreviewPhase::ResizePending&&bExact)
    {
        if(GFrameCounter!=State->WitnessFrame&&GFrameCounter>State->ResizeFrame)
        {State->WitnessFrame=GFrameCounter;++State->Witnesses;}
        if(State->Witnesses>=2){State->Phase=EPreviewPhase::Ready;return Report(TEXT("READY"),FString(),Actual);}
        return Report(TEXT("PENDING"),FString(),Actual);
    }
    State->Witnesses=0;
    if(State->Phase==EPreviewPhase::ResizePending&&(GFrameCounter<=State->ResizeFrame+2||FPlatformTime::Seconds()-State->LastResizeSeconds<.1))return Report(TEXT("PENDING"),FString(),Actual);
    if(State->ResizeCalls>=2)return Report(TEXT("PENDING"),FString(),Actual);
    // Measured physical client/viewport difference; SWindow adds its own title/borders.
    // No DPI factor, HWND, fixed viewport size, RHI resize or camera change is applied.
    const FVector2D CurrentClient=Window->GetClientSizeInScreen();
    const FVector2D RequestedClient=CurrentClient+FVector2D(State->Desired.X-Width,State->Desired.Y-Height);
    if(!FMath::IsFinite(RequestedClient.X)||!FMath::IsFinite(RequestedClient.Y)||RequestedClient.X<=0||RequestedClient.Y<=0||RequestedClient.X>4096||RequestedClient.Y>4096)return Fail(TEXT("Measured client-to-viewport size mapping is invalid"),Actual);
    Window->Resize(RequestedClient);State->LastRequestedClient=RequestedClient;++State->ResizeCalls;
    State->ResizeFrame=GFrameCounter;State->LastResizeSeconds=FPlatformTime::Seconds();State->Phase=EPreviewPhase::ResizePending;
    return Report(TEXT("PENDING"),FString(),Actual);
}
}

FString ULivingTownOriginalWorkerPreview::RequestOrdinaryPreview(int32 Width,int32 Height)
{
    if(!EditorThread())return Report(TEXT("REFUSED"),TEXT("Editor game thread is required"));
    if(State)return Report(TEXT("REFUSED"),TEXT("Only one ordinary preview request is allowed in this Editor process"));
    State=MakeUnique<FPreviewState>();State->Desired=FIntPoint(Width,Height);State->Deadline=FPlatformTime::Seconds()+30.0;State->RequestFrame=GFrameCounter;
    if(Width<64||Height<64||Width>1920||Height>1080)return Fail(TEXT("Requested viewport size is outside the bounded preview range"));
    if(GEditor->IsPlaySessionInProgress())return Fail(TEXT("An inherited or queued play session is not accepted"));
    for(const FWorldContext& Context:GEngine->GetWorldContexts())if(Context.World()&&(Context.WorldType==EWorldType::PIE||Context.WorldType==EWorldType::Game))return Fail(TEXT("An existing game/PIE world is not accepted"));
    UWorld* EditorWorld=GEditor->GetEditorWorldContext().World();
    if(!EditorWorld||EditorWorld->GetOutermost()->GetName()!=TEXT("/Engine/Maps/Entry")||!StandaloneSettings())return Fail(TEXT("Private one-client standalone settings and Entry are required"));
    FString Persona,Descriptor;
    if(!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeWorldV3"))||!FParse::Value(FCommandLine::Get(),TEXT("CafeWorldPersona="),Persona)||!Persona.Equals(TEXT("ben"),ESearchCase::IgnoreCase)||!FParse::Value(FCommandLine::Get(),TEXT("LivingTownOriginalWorkerBen="),Descriptor)||Descriptor.IsEmpty())return Fail(TEXT("Explicit WorldV3 OriginalWorker Ben inputs are required"));
    FRequestPlaySessionParams Params;
    // Same ordinary in-process New Editor Window path as PlayInEditorFloating.
    // The destination viewport, start transform, settings override and GameMode override stay unset.
    GEditor->RequestPlaySession(Params);
    return Report(TEXT("REQUESTED"));
}
FString ULivingTownOriginalWorkerPreview::AdvanceOrdinaryPreview(const FString& ScopeToken){return Process(ScopeToken,true);}
FString ULivingTownOriginalWorkerPreview::InspectOrdinaryPreview(const FString& ScopeToken){return Process(ScopeToken,false);}
