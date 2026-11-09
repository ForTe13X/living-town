#include "LivingTownCapturePilotLibrary.h"
#include "Modules/ModuleManager.h"
#include "Editor.h"
#include "CoreGlobals.h"
#include "IAssetViewport.h"
#include "EditorViewportClient.h"
#include "UnrealClient.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "UObject/Package.h"
#include "Engine/GameViewportClient.h"
#include "Engine/LocalPlayer.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/Pawn.h"
#include "GameFramework/HUD.h"
#include "Camera/PlayerCameraManager.h"
#include "Slate/SceneViewport.h"
#include "MovieSceneCaptureModule.h"
#include "MovieSceneCapture.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
IMPLEMENT_MODULE(FDefaultModuleImpl,LivingTownCapturePilot)
namespace {
TWeakObjectPtr<UWorld> ExpectedWorld;
TWeakObjectPtr<APlayerController> ExpectedPC;
TWeakObjectPtr<APawn> ExpectedPawn;
TWeakObjectPtr<AHUD> ExpectedHUD;
TWeakObjectPtr<APlayerCameraManager> ExpectedCameraManager;
TWeakPtr<FSceneViewport> ExpectedViewport;
bool bProbed=false,bStarted=false;
FString SerializeCaptureJson(TSharedRef<FJsonObject> O) {FString S;auto W=TJsonWriterFactory<>::Create(&S);FJsonSerializer::Serialize(O,W);return S;}
FString Run(bool Start) {
 auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("REFUSED"));
 auto Refuse=[&](const TCHAR* Why){O->SetStringField(TEXT("error"),Why);return SerializeCaptureJson(O);};
 if(!IsInGameThread()||!GIsEditor||!GEditor||!GEngine||IsRunningCommandlet())return Refuse(TEXT("Ordinary owned Editor GameThread required"));
 UWorld* World=nullptr;int32 Count=0;
 for(const FWorldContext& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::PIE||C.WorldType==EWorldType::Game)){++Count;World=C.World();}
 if(Count!=1||!World||World->WorldType!=EWorldType::PIE||GEditor->IsSimulateInEditorInProgress()||UWorld::RemovePIEPrefix(World->GetOutermost()->GetName())!=TEXT("/Game/LivingTown_UEPilot/FullTownWorldV3_289_v001/L_FullTownWorldV3_289_v001"))return Refuse(TEXT("One existing current saved-root normal PIE world required"));
 APlayerController* PC=World->GetFirstPlayerController();APawn* Pawn=PC?PC->GetPawn():nullptr;
 AGameModeBase* Mode=World->GetAuthGameMode();
 if(!PC||!Pawn||!PC->IsLocalController()||PC->GetViewTarget()!=Pawn||!PC->GetHUD()||!PC->PlayerCameraManager||!Mode||PC->GetClass()->GetPathName()!=TEXT("/Script/LivingTownNative.LivingTownCafeWorldV3Controller")||Pawn->GetClass()->GetPathName()!=TEXT("/Script/LivingTownNative.LivingTownCafeCharacter")||Mode->GetClass()->GetPathName()!=TEXT("/Script/LivingTownNative.LivingTownCafeWorldV3GameMode"))return Refuse(TEXT("Existing current native pawn/controller/HUD/PlayerCamera authority required"));
 const FWorldContext* Context=GEngine->GetWorldContextFromWorld(World);
 const FSlatePlayInEditorInfo* Info=Context?GEditor->SlatePlayInEditorMap.Find(Context->ContextHandle):nullptr;
 auto AssetViewport=Info?Info->DestinationSlateViewport.Pin():TSharedPtr<IAssetViewport>();
 TSharedPtr<FSceneViewport> Scene=AssetViewport?AssetViewport->GetSharedActiveViewport():nullptr;
 UGameViewportClient* Client=World->GetGameViewport();
 if(!Scene||!Client||!PC->GetLocalPlayer()||PC->GetLocalPlayer()->ViewportClient!=Client||Client->GetGameViewport()!=Scene.Get()||Scene->GetClient()!=Client||Scene->GetClient()->GetWorld()!=World||Scene->GetPlayInEditorIsSimulate())return Refuse(TEXT("Exact existing embedded game SceneViewport shared owner required"));
 const FIntPoint Size=Scene->GetSizeXY();int32 Width=0,Height=0;PC->GetViewportSize(Width,Height);
 if(Size.X!=Width||Size.Y!=Height||Width<16||Height<16||Width>1920||Height>1080)return Refuse(TEXT("Exact existing PC/game viewport must fit finite1920x1080 pilot"));
 auto& CaptureModule=IMovieSceneCaptureModule::Get();
 if(CaptureModule.GetFirstActiveMovieSceneCapture())return Refuse(TEXT("Never adopt or stop an inherited movie capture"));
 if(!Start){
  if(bProbed)return Refuse(TEXT("One recorder-integration probe per process"));
  ExpectedWorld=World;ExpectedPC=PC;ExpectedPawn=Pawn;ExpectedViewport=Scene;bProbed=true;
  ExpectedHUD=PC->GetHUD();ExpectedCameraManager=PC->PlayerCameraManager;
 }else{
  if(!bProbed||bStarted||ExpectedWorld.Get()!=World||ExpectedPC.Get()!=PC||ExpectedPawn.Get()!=Pawn||ExpectedViewport.Pin()!=Scene)return Refuse(TEXT("Exact once-probed unchanged world/player/viewport required"));
  bStarted=true;
  if(!CaptureModule.CreateMovieSceneCapture(Scene))return Refuse(TEXT("Stock base capture construction refused"));
 }
 O->SetStringField(TEXT("status"),Start?TEXT("STARTED_STOCK_BASE_ON_EXISTING_GAME_VIEWPORT"):TEXT("PROBED_EXACT_EXISTING_GAME_VIEWPORT_NO_CAPTURE"));
 O->SetStringField(TEXT("error"),TEXT(""));O->SetStringField(TEXT("world"),World->GetPathName());O->SetStringField(TEXT("pawn"),Pawn->GetPathName());O->SetStringField(TEXT("view_target"),PC->GetViewTarget()->GetPathName());O->SetStringField(TEXT("HUD"),PC->GetHUD()->GetPathName());O->SetStringField(TEXT("PlayerCameraManager"),PC->PlayerCameraManager->GetPathName());
 O->SetNumberField(TEXT("width"),Width);O->SetNumberField(TEXT("height"),Height);O->SetStringField(TEXT("plugin_dll"),FModuleManager::Get().GetModuleFilename(TEXT("LivingTownCapturePilot")));O->SetBoolField(TEXT("world_camera_HUD_pose_or_viewport_changed"),false);
 return SerializeCaptureJson(O);
}
}
FString ULivingTownCapturePilotLibrary::ProbeExistingGameViewport(){return Run(false);}
FString ULivingTownCapturePilotLibrary::StartExistingGameViewportCapture(){return Run(true);}

// Read-only: validate identity against the editor's client registry before access.
// An active game client is refused rather than cast to FEditorViewportClient.
FString ULivingTownCapturePilotLibrary::ReadActiveEditorViewportExposure() {
 auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("REFUSED"));
 auto Refuse=[&](const TCHAR* Why){O->SetStringField(TEXT("error"),Why);return SerializeCaptureJson(O);};
 if(!IsInGameThread()||!GIsEditor||!GEditor||IsRunningCommandlet())return Refuse(TEXT("Ordinary Editor GameThread required"));
 FViewport* Active=GEditor->GetActiveViewport();
 if(!Active||!Active->GetClient())return Refuse(TEXT("No active viewport/client"));
 FEditorViewportClient* Client=nullptr;int32 Matches=0;
 for(FEditorViewportClient* Candidate:GEditor->GetAllViewportClients()) {
  if(Candidate&&static_cast<FViewportClient*>(Candidate)==Active->GetClient()) {++Matches;Client=Candidate;}
 }
 if(Matches!=1||!Client||Client->Viewport!=Active)return Refuse(TEXT("Active viewport is not one exact registered editor viewport"));
 const FExposureSettings& Exposure=Client->ExposureSettings;
 O->SetStringField(TEXT("status"),TEXT("OBSERVED_ACTIVE_EDITOR_VIEWPORT_EXPOSURE_READ_ONLY"));
 O->SetNumberField(TEXT("FixedEV100"),Exposure.FixedEV100);O->SetBoolField(TEXT("bFixed"),Exposure.bFixed);
 O->SetBoolField(TEXT("IsInGameView"),Client->IsInGameView());
 O->SetBoolField(TEXT("EngineShowFlags_EyeAdaptation"),Client->EngineShowFlags.EyeAdaptation);
 O->SetBoolField(TEXT("EngineShowFlags_PostProcessing"),Client->EngineShowFlags.PostProcessing);
 O->SetStringField(TEXT("viewport_type"),FString::FromInt(static_cast<int32>(Client->GetViewportType())));
 O->SetStringField(TEXT("client_type"),TEXT("FEditorViewportClient registered exact pointer match"));
 O->SetBoolField(TEXT("native_live_ExposureSettings_directly_read"),true);
 O->SetBoolField(TEXT("world_camera_HUD_pose_or_viewport_changed"),false);
 O->SetStringField(TEXT("plugin_dll"),FModuleManager::Get().GetModuleFilename(TEXT("LivingTownCapturePilot")));
 return SerializeCaptureJson(O);
}


// Configured003: exact caller-owned transient instance; no CDO mutation/config reload.
FString ULivingTownCapturePilotLibrary::StartConfiguredExistingGameViewportCapture(UMovieSceneCapture* Capture) {
 auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("REFUSED"));
 auto Refuse=[&](const TCHAR* Why){O->SetStringField(TEXT("error"),Why);return SerializeCaptureJson(O);};
 if(!IsInGameThread()||!GIsEditor||!GEditor||!GEngine||IsRunningCommandlet())return Refuse(TEXT("Ordinary owned Editor GameThread required"));
 if(!IsValid(Capture))return Refuse(TEXT("Actual configured capture instance required"));
 UMovieSceneCaptureProtocolBase* Image=Capture->GetImageCaptureProtocol();
 UMovieSceneCaptureProtocolBase* Audio=Capture->GetAudioCaptureProtocol();
 const FMovieSceneCaptureSettings& S=Capture->GetSettings();
 O->SetStringField(TEXT("capture"),Capture->GetPathName());O->SetStringField(TEXT("capture_class"),Capture->GetClass()->GetPathName());
 O->SetStringField(TEXT("capture_outer"),Capture->GetOuter()?Capture->GetOuter()->GetPathName():TEXT(""));
 O->SetBoolField(TEXT("capture_is_CDO_or_archetype"),Capture->HasAnyFlags(RF_ClassDefaultObject|RF_ArchetypeObject));
 O->SetStringField(TEXT("image_protocol"),Image?Image->GetPathName():TEXT(""));O->SetStringField(TEXT("image_protocol_class"),Image?Image->GetClass()->GetPathName():TEXT(""));
 O->SetStringField(TEXT("audio_protocol"),Audio?Audio->GetPathName():TEXT(""));O->SetStringField(TEXT("audio_protocol_class"),Audio?Audio->GetClass()->GetPathName():TEXT(""));
 O->SetNumberField(TEXT("image_state_before_initialize"),Image?static_cast<int32>(Image->GetState()):-1);
 O->SetNumberField(TEXT("audio_state_before_initialize"),Audio?static_cast<int32>(Audio->GetState()):-1);
 O->SetNumberField(TEXT("base_rate_numerator"),S.FrameRate.Numerator);O->SetNumberField(TEXT("base_rate_denominator"),S.FrameRate.Denominator);
 O->SetNumberField(TEXT("custom_rate_numerator"),S.CustomFrameRate.Numerator);O->SetNumberField(TEXT("custom_rate_denominator"),S.CustomFrameRate.Denominator);
 O->SetBoolField(TEXT("use_custom_frame_rate"),S.bUseCustomFrameRate);O->SetNumberField(TEXT("settings_resolution_x"),S.Resolution.ResX);O->SetNumberField(TEXT("settings_resolution_y"),S.Resolution.ResY);
 O->SetStringField(TEXT("output_directory"),S.OutputDirectory.Path);O->SetStringField(TEXT("output_format"),S.OutputFormat);
 O->SetBoolField(TEXT("CDO_write_or_viewport_resize_requested"),false);
 if(Capture->GetClass()!=UMovieSceneCapture::StaticClass()||Capture->GetOuter()!=GetTransientPackage()||Capture->HasAnyFlags(RF_ClassDefaultObject|RF_ArchetypeObject))return Refuse(TEXT("Fresh exact-base nonCDO object directly in transient package required"));
 if(!Image||!Audio||Image->GetOuter()!=Capture||Audio->GetOuter()!=Capture||Image->GetClass()->GetPathName()!=TEXT("/Script/MovieSceneCapture.ImageSequenceProtocol_PNG")||Audio->GetClass()->GetPathName()!=TEXT("/Script/MovieSceneCapture.NullAudioCaptureProtocol")||Capture->ImageCaptureProtocolType.ToString()!=TEXT("/Script/MovieSceneCapture.ImageSequenceProtocol_PNG")||Capture->AudioCaptureProtocolType.ToString()!=TEXT("/Script/MovieSceneCapture.NullAudioCaptureProtocol"))return Refuse(TEXT("Actual owned exact PNG and NullAudio protocols must exist before initialization"));
 if(Image->GetState()!=EMovieSceneCaptureProtocolState::Idle||Audio->GetState()!=EMovieSceneCaptureProtocolState::Idle||Capture->GetMetrics().Width!=0||Capture->GetMetrics().Height!=0||Capture->GetMetrics().ElapsedSeconds!=0.f||Capture->GetMetrics().Frame!=0||Capture->GetMetrics().PreviousFrame!=INDEX_NONE)return Refuse(TEXT("Fresh never-initialized protocols and capture metrics required"));
 if(S.FrameRate!=FFrameRate(24,1)||!S.bUseCustomFrameRate||S.CustomFrameRate!=FFrameRate(24,1)||S.Resolution.ResX!=1014||S.Resolution.ResY!=550||S.OutputDirectory.Path.IsEmpty()||S.OutputFormat!=TEXT("Frame.{frame}")||S.bOverwriteExisting||!S.bUseRelativeFrameNumbers||S.ZeroPadFrameNumbers!=8||!S.bEnableTextureStreaming||S.bCinematicEngineScalability||S.bCinematicMode||S.GameModeOverride||S.bUsePathTracer)return Refuse(TEXT("Exact finite natural-clock PNG settings and observed1014x550 dimensions required"));
 UWorld* World=nullptr;int32 Count=0;
 for(const FWorldContext& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::PIE||C.WorldType==EWorldType::Game)){++Count;World=C.World();}
 if(Count!=1||!World||World->WorldType!=EWorldType::PIE||GEditor->IsSimulateInEditorInProgress()||UWorld::RemovePIEPrefix(World->GetOutermost()->GetName())!=TEXT("/Game/LivingTown_UEPilot/FullTownWorldV3_289_v001/L_FullTownWorldV3_289_v001"))return Refuse(TEXT("One existing current saved-root normal PIE world required"));
 APlayerController* PC=World->GetFirstPlayerController();APawn* Pawn=PC?PC->GetPawn():nullptr;AGameModeBase* Mode=World->GetAuthGameMode();
 if(!PC||!Pawn||!PC->IsLocalController()||PC->GetViewTarget()!=Pawn||!PC->GetHUD()||!PC->PlayerCameraManager||!Mode||PC->GetClass()->GetPathName()!=TEXT("/Script/LivingTownNative.LivingTownCafeWorldV3Controller")||Pawn->GetClass()->GetPathName()!=TEXT("/Script/LivingTownNative.LivingTownCafeCharacter")||Mode->GetClass()->GetPathName()!=TEXT("/Script/LivingTownNative.LivingTownCafeWorldV3GameMode"))return Refuse(TEXT("Existing current native pawn/controller/HUD/PlayerCamera authority required"));
 const FWorldContext* Context=GEngine->GetWorldContextFromWorld(World);const FSlatePlayInEditorInfo* Info=Context?GEditor->SlatePlayInEditorMap.Find(Context->ContextHandle):nullptr;
 auto AssetViewport=Info?Info->DestinationSlateViewport.Pin():TSharedPtr<IAssetViewport>();TSharedPtr<FSceneViewport> Scene=AssetViewport?AssetViewport->GetSharedActiveViewport():nullptr;UGameViewportClient* Client=World->GetGameViewport();
 if(!Scene||!Client||!PC->GetLocalPlayer()||PC->GetLocalPlayer()->ViewportClient!=Client||Client->GetGameViewport()!=Scene.Get()||Scene->GetClient()!=Client||Scene->GetClient()->GetWorld()!=World||Scene->GetPlayInEditorIsSimulate())return Refuse(TEXT("Exact existing embedded game SceneViewport shared owner required"));
 const FIntPoint Size=Scene->GetSizeXY();int32 Width=0,Height=0;PC->GetViewportSize(Width,Height);
 O->SetStringField(TEXT("world"),World->GetPathName());O->SetStringField(TEXT("pawn"),Pawn->GetPathName());O->SetStringField(TEXT("HUD"),PC->GetHUD()->GetPathName());O->SetStringField(TEXT("PlayerCameraManager"),PC->PlayerCameraManager->GetPathName());O->SetNumberField(TEXT("width"),Width);O->SetNumberField(TEXT("height"),Height);
 if(Size.X!=Width||Size.Y!=Height||Width!=1014||Height!=550||S.Resolution.ResX!=Size.X||S.Resolution.ResY!=Size.Y)return Refuse(TEXT("Settings exactly match same actual1014x550 PC and SceneViewport; never resize"));
 if(!bProbed||bStarted||ExpectedWorld.Get()!=World||ExpectedPC.Get()!=PC||ExpectedPawn.Get()!=Pawn||ExpectedHUD.Get()!=PC->GetHUD()||ExpectedCameraManager.Get()!=PC->PlayerCameraManager||ExpectedViewport.Pin()!=Scene)return Refuse(TEXT("Exact once-probed unchanged world/player/HUD/PlayerCamera/viewport required"));
 auto& CaptureModule=IMovieSceneCaptureModule::Get();if(CaptureModule.GetFirstActiveMovieSceneCapture())return Refuse(TEXT("Never adopt or stop an inherited movie capture"));
 bStarted=true;
 Capture->Initialize(Scene);
 // Stock Capture.Finalize alone skips protocol teardown when bCapturing is
 // false. This fresh synchronous pre-Start refusal owns both protocol objects.
 auto RefuseInitialized=[&](const TCHAR* Why){
  UMovieSceneCaptureProtocolBase* OwnedImage=Capture->GetImageCaptureProtocol();
  UMovieSceneCaptureProtocolBase* OwnedAudio=Capture->GetAudioCaptureProtocol();
  if(OwnedImage&&OwnedImage->GetOuter()==Capture)OwnedImage->Finalize();
  if(OwnedAudio&&OwnedAudio->GetOuter()==Capture)OwnedAudio->Finalize();
  Capture->Finalize();
  O->SetBoolField(TEXT("owned_pre_start_protocol_finalize_attempted"),true);
  O->SetBoolField(TEXT("owned_capture_registry_entry_released"),CaptureModule.GetFirstActiveMovieSceneCapture()!=Capture);
  O->SetNumberField(TEXT("owned_image_state_after_refusal_cleanup"),OwnedImage?static_cast<int32>(OwnedImage->GetState()):-1);
  O->SetNumberField(TEXT("owned_audio_state_after_refusal_cleanup"),OwnedAudio?static_cast<int32>(OwnedAudio->GetState()):-1);
  O->SetBoolField(TEXT("refusal_requires_owned_root_reap_no_closure_admission"),true);
  return Refuse(Why);
 };
 O->SetBoolField(TEXT("stock_initialize_registered_exact_instance"),CaptureModule.GetFirstActiveMovieSceneCapture()==Capture);
 O->SetNumberField(TEXT("initialized_metrics_width"),Capture->GetMetrics().Width);O->SetNumberField(TEXT("initialized_metrics_height"),Capture->GetMetrics().Height);
 O->SetNumberField(TEXT("image_state_after_initialize"),static_cast<int32>(Image->GetState()));O->SetNumberField(TEXT("audio_state_after_initialize"),static_cast<int32>(Audio->GetState()));
 if(CaptureModule.GetFirstActiveMovieSceneCapture()!=Capture||Capture->GetImageCaptureProtocol()!=Image||Capture->GetAudioCaptureProtocol()!=Audio||Image->GetState()!=EMovieSceneCaptureProtocolState::Initialized||Audio->GetState()!=EMovieSceneCaptureProtocolState::Initialized||Image->GetWorld()!=World||Audio->GetWorld()!=World||Capture->GetMetrics().Width!=Width||Capture->GetMetrics().Height!=Height)return RefuseInitialized(TEXT("Stock Initialize must register this exact instance and initialize both original protocols on actual viewport"));
 Capture->StartCapture();
 O->SetNumberField(TEXT("image_state_after_start"),static_cast<int32>(Image->GetState()));O->SetNumberField(TEXT("audio_state_after_start"),static_cast<int32>(Audio->GetState()));
 if(Image->GetState()!=EMovieSceneCaptureProtocolState::Capturing||Audio->GetState()!=EMovieSceneCaptureProtocolState::Initialized){Capture->Finalize();O->SetBoolField(TEXT("owned_post_start_finalize_attempted"),true);O->SetBoolField(TEXT("refusal_requires_owned_root_reap_no_closure_admission"),true);return Refuse(TEXT("Stock image protocol did not enter capturing state"));};
 O->SetStringField(TEXT("status"),TEXT("STARTED_CONFIGURED_STOCK_BASE_ON_EXISTING_GAME_VIEWPORT"));O->SetStringField(TEXT("error"),TEXT(""));O->SetStringField(TEXT("plugin_dll"),FModuleManager::Get().GetModuleFilename(TEXT("LivingTownCapturePilot")));O->SetBoolField(TEXT("world_camera_HUD_pose_or_viewport_changed"),false);
 return SerializeCaptureJson(O);
}
