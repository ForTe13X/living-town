#include "LivingTownViewportInspection.h"
#include "Editor.h"
#include "EditorViewportClient.h"
#include "LevelEditorViewport.h"
#include "Engine/World.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "HAL/IConsoleManager.h"

namespace
{
using JObject = TSharedPtr<FJsonObject>;
const TCHAR* ReviewWorldPath = TEXT("/Game/LivingTown_UEPilot/Review_v001/L_TownSlice_Stage_v001.L_TownSlice_Stage_v001");
const FText RealtimeTag = FText::FromString(TEXT("LivingTown.ClosedMidViewportReview.v1"));

struct FSavedViewport
{
    FLevelEditorViewportClient* Client;
    FViewport* Viewport;
    TWeakObjectPtr<UWorld> World;
    FViewportCameraTransform Perspective;
    FViewportCameraTransform Orthographic;
    ELevelViewportType Type;
    EViewModeIndex PerspectiveMode;
    EViewModeIndex OrthographicMode;
    FEngineShowFlags Flags;
    FEngineShowFlags LastFlags;
    FExposureSettings Exposure;
    float FOV;
    bool GameView;
    bool ShowWidget;
    bool Realtime;
    FString Token;
    explicit FSavedViewport(FLevelEditorViewportClient* In)
        : Client(In), Viewport(In->Viewport), World(In->GetWorld()),
          Perspective(In->ViewTransformPerspective), Orthographic(In->ViewTransformOrthographic),
          Type(In->GetViewportType()), PerspectiveMode(In->GetPerspViewMode()),
          OrthographicMode(In->GetOrthoViewMode()), Flags(In->EngineShowFlags),
          LastFlags(In->LastEngineShowFlags), Exposure(In->ExposureSettings), FOV(In->ViewFOV),
          GameView(In->IsInGameView()), ShowWidget(In->GetShowWidget()), Realtime(In->IsRealtime()),
          Token(FGuid::NewGuid().ToString(EGuidFormats::Digits)) {}
};
TUniquePtr<FSavedViewport> Saved;

FString Result(const TCHAR* Status, const FString& Error, JObject Data = MakeShared<FJsonObject>())
{
    JObject Root = MakeShared<FJsonObject>();
    Root->SetStringField(TEXT("schema"), TEXT("living_town.current_viewport_review.v1"));
    Root->SetStringField(TEXT("status"), Status);
    Root->SetStringField(TEXT("error"), Error);
    Root->SetObjectField(TEXT("readback"), Data);
    FString Out;
    const TSharedRef<TJsonWriter<>> Writer = TJsonWriterFactory<>::Create(&Out);
    FJsonSerializer::Serialize(Root.ToSharedRef(), Writer);
    return Out;
}

bool Registered(FLevelEditorViewportClient* Client)
{
    return IsInGameThread() && GEditor && Client && GEditor->GetLevelViewportClients().Contains(Client);
}

bool SameTransform(const FViewportCameraTransform& A, const FViewportCameraTransform& B)
{
    return A.GetLocation() == B.GetLocation() && A.GetRotation() == B.GetRotation() &&
        A.GetLookAt() == B.GetLookAt() && A.GetOrthoZoom() == B.GetOrthoZoom();
}

JObject Flags(const FEngineShowFlags& In)
{
    JObject Out = MakeShared<FJsonObject>();
    Out->SetBoolField(TEXT("Atmosphere"), In.Atmosphere != 0);
    Out->SetBoolField(TEXT("SkyLighting"), In.SkyLighting != 0);
    Out->SetBoolField(TEXT("Lighting"), In.Lighting != 0);
    Out->SetBoolField(TEXT("Materials"), In.Materials != 0);
    Out->SetBoolField(TEXT("Tonemapper"), In.Tonemapper != 0);
    Out->SetBoolField(TEXT("EyeAdaptation"), In.EyeAdaptation != 0);
    return Out;
}

JObject Observe(FLevelEditorViewportClient* Client)
{
    JObject Out = MakeShared<FJsonObject>();
    Out->SetStringField(TEXT("client_identity_diagnostic_only"), FString::Printf(TEXT("%p"), static_cast<void*>(Client)));
    Out->SetStringField(TEXT("viewport_identity_diagnostic_only"), FString::Printf(TEXT("%p"), static_cast<void*>(Client->Viewport)));
    Out->SetBoolField(TEXT("is_exact_current_MCP_client"), Client == GCurrentLevelEditingViewportClient);
    Out->SetStringField(TEXT("world_path"), Client->GetWorld() ? Client->GetWorld()->GetPathName() : TEXT(""));
    Out->SetNumberField(TEXT("API_viewport_type"), static_cast<int32>(Client->GetViewportType()));
    Out->SetBoolField(TEXT("perspective"), Client->IsPerspective());
    Out->SetNumberField(TEXT("API_view_mode"), static_cast<int32>(Client->GetViewMode()));
    Out->SetBoolField(TEXT("lit"), Client->GetViewMode() == VMI_Lit);
    Out->SetBoolField(TEXT("game_view"), Client->IsInGameView());
    Out->SetBoolField(TEXT("realtime"), Client->IsRealtime());
    Out->SetBoolField(TEXT("temporary_realtime_override_present"), Client->HasRealtimeOverride(RealtimeTag));
    Out->SetBoolField(TEXT("showflag_override_function_present"), Client->IsEngineShowFlagsOverrideEnabled());
    const FVector Location = Client->GetViewLocation();
    const FRotator Rotation = Client->GetViewRotation();
    Out->SetArrayField(TEXT("location_cm"), {MakeShared<FJsonValueNumber>(Location.X), MakeShared<FJsonValueNumber>(Location.Y), MakeShared<FJsonValueNumber>(Location.Z)});
    Out->SetArrayField(TEXT("rotation_pitch_yaw_roll"), {MakeShared<FJsonValueNumber>(Rotation.Pitch), MakeShared<FJsonValueNumber>(Rotation.Yaw), MakeShared<FJsonValueNumber>(Rotation.Roll)});
    Out->SetNumberField(TEXT("fov"), Client->ViewFOV);
    const FIntPoint Size = Client->Viewport ? Client->Viewport->GetSizeXY() : FIntPoint::ZeroValue;
    Out->SetNumberField(TEXT("viewport_width"), Size.X);
    Out->SetNumberField(TEXT("viewport_height"), Size.Y);
    Out->SetObjectField(TEXT("client_show_flags"), Flags(Client->EngineShowFlags));
    JObject Overrides = MakeShared<FJsonObject>();
    for (const TCHAR* Name : {TEXT("Atmosphere"), TEXT("SkyLighting"), TEXT("Lighting"), TEXT("Materials"), TEXT("Tonemapper"), TEXT("EyeAdaptation")})
    {
        const IConsoleVariable* Variable = IConsoleManager::Get().FindConsoleVariable(*(FString(TEXT("ShowFlag.")) + Name));
        if (Variable) Overrides->SetNumberField(Name, Variable->GetInt());
        else Overrides->SetField(Name, MakeShared<FJsonValueNull>());
    }
    Out->SetObjectField(TEXT("showflag_console_overrides"), Overrides);
    Out->SetStringField(TEXT("showflag_readback_scope"), TEXT("Exact live client flags and console overrides; later view extensions/render-family adjustments are not observed."));
    JObject Exposure = MakeShared<FJsonObject>();
    Exposure->SetBoolField(TEXT("fixed"), Client->ExposureSettings.bFixed);
    Exposure->SetNumberField(TEXT("fixed_ev100"), Client->ExposureSettings.FixedEV100);
    Out->SetObjectField(TEXT("current_exposure_settings"), Exposure);
    Out->SetBoolField(TEXT("scope_active"), Saved.IsValid());
    Out->SetStringField(TEXT("scope_token"), Saved ? Saved->Token : TEXT(""));
    Out->SetBoolField(TEXT("asset_or_runtime_acceptance"), false);
    return Out;
}
}

FString ULivingTownViewportInspection::ReadCurrentLevelViewport()
{
    auto* Client = GCurrentLevelEditingViewportClient;
    if (!Registered(Client) || !Client->Viewport)
        return Result(TEXT("REFUSED"), TEXT("No registered live GCurrent level viewport on the game thread."));
    return Result(TEXT("READ_EXACT_CURRENT_LEVEL_VIEWPORT"), TEXT(""), Observe(Client));
}

FString ULivingTownViewportInspection::ConfigureFixedMidViewport()
{
    auto* Client = GCurrentLevelEditingViewportClient;
    if (Saved) return Result(TEXT("REFUSED"), TEXT("One active viewport review scope only; restore it first."));
    if (!Registered(Client) || !Client->Viewport || !Client->GetWorld() || GEditor->PlayWorld ||
        Client->GetWorld()->WorldType != EWorldType::Editor || Client->GetWorld()->GetPathName() != ReviewWorldPath)
        return Result(TEXT("REFUSED"), TEXT("Fixed saved review editor world/current viewport required; PIE forbidden."));
    if (Client->IsAnyActorLocked() || Client->IsEngineShowFlagsOverrideEnabled() || Client->HasRealtimeOverride(RealtimeTag) ||
        Client->ViewTransformPerspective.IsPlaying() || Client->ViewTransformOrthographic.IsPlaying())
        return Result(TEXT("REFUSED"), TEXT("Actor lock, animated camera, external showflag override or duplicate realtime scope prevents reversible review."));
    const JObject Before = Observe(Client);
    Saved = MakeUnique<FSavedViewport>(Client);
    Client->SetViewportType(LVT_Perspective);
    Client->SetViewMode(VMI_Lit);
    Client->SetGameView(false);
    Client->SetViewLocation(FVector(6500., 4500., 3800.));
    Client->SetViewRotation((FVector(1500., 1500., 300.) - FVector(6500., 4500., 3800.)).Rotation());
    Client->ViewFOV = 55.f;
    Client->ExposureSettings.bFixed = false;
    Client->EngineShowFlags.SetAtmosphere(true);
    Client->EngineShowFlags.SetSkyLighting(true);
    Client->EngineShowFlags.SetLighting(true);
    Client->EngineShowFlags.SetMaterials(true);
    Client->EngineShowFlags.SetTonemapper(true);
    Client->EngineShowFlags.SetEyeAdaptation(true);
    Client->AddRealtimeOverride(true, RealtimeTag);
    Client->Invalidate();
    JObject Data = MakeShared<FJsonObject>();
    Data->SetObjectField(TEXT("before"), Before);
    Data->SetObjectField(TEXT("after"), Observe(Client));
    Data->SetStringField(TEXT("scope_token"), Saved->Token);
    Data->SetStringField(TEXT("camera_source"), TEXT("capture_resume_prepare_v1_007/editor_stage_worker.py CAMERAS LT_REVIEW_Mid"));
    return Result(TEXT("CONFIGURED_FIXED_MID_EXACT_CURRENT_VIEWPORT"), TEXT(""), Data);
}

FString ULivingTownViewportInspection::RestoreCurrentLevelViewport(const FString& ScopeToken)
{
    if (!Saved || ScopeToken != Saved->Token)
        return Result(TEXT("REFUSED"), TEXT("Exact active viewport scope token required."));
    auto* Client = Saved->Client;
    if (!Registered(Client) || Client->Viewport != Saved->Viewport || Client->GetWorld() != Saved->World.Get())
        return Result(TEXT("REFUSED"), TEXT("Owned original client/viewport/world no longer live; no stale pointer dereference."));
    Client->RemoveRealtimeOverride(RealtimeTag, false);
    Client->SetViewportType(Saved->Type);
    Client->SetViewModes(Saved->PerspectiveMode, Saved->OrthographicMode);
    Client->SetGameView(Saved->GameView);
    Client->ShowWidget(Saved->ShowWidget);
    Client->ViewTransformPerspective = Saved->Perspective;
    Client->ViewTransformOrthographic = Saved->Orthographic;
    Client->ViewFOV = Saved->FOV;
    Client->ExposureSettings = Saved->Exposure;
    Client->EngineShowFlags = Saved->Flags;
    Client->LastEngineShowFlags = Saved->LastFlags;
    Client->Invalidate();
    const bool Restored = Client->GetViewportType() == Saved->Type && Client->GetPerspViewMode() == Saved->PerspectiveMode &&
        Client->GetOrthoViewMode() == Saved->OrthographicMode && Client->IsInGameView() == Saved->GameView &&
        Client->ViewFOV == Saved->FOV && Client->GetShowWidget() == Saved->ShowWidget &&
        SameTransform(Client->ViewTransformPerspective, Saved->Perspective) && SameTransform(Client->ViewTransformOrthographic, Saved->Orthographic) &&
        Client->ExposureSettings.bFixed == Saved->Exposure.bFixed &&
        Client->ExposureSettings.FixedEV100 == Saved->Exposure.FixedEV100 && Client->IsRealtime() == Saved->Realtime &&
        Client->EngineShowFlags.ToString() == Saved->Flags.ToString() && Client->LastEngineShowFlags.ToString() == Saved->LastFlags.ToString() &&
        !Client->HasRealtimeOverride(RealtimeTag);
    JObject Data = Observe(Client);
    Data->SetBoolField(TEXT("original_state_restored"), Restored);
    Saved.Reset();
    Data->SetBoolField(TEXT("scope_active"), false);
    Data->SetStringField(TEXT("scope_token"), TEXT(""));
    return Result(Restored ? TEXT("RESTORED_EXACT_ORIGINAL_VIEWPORT") : TEXT("RESTORE_READBACK_MISMATCH"), Restored ? TEXT("") : TEXT("Restored fields did not match saved values."), Data);
}
