#include "LivingTownCapturePilotLibrary.h"
#include "Editor.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameViewportClient.h"
#include "Engine/LocalPlayer.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/Pawn.h"
#include "GameFramework/HUD.h"
#include "Camera/PlayerCameraManager.h"
#include "Slate/SceneViewport.h"
#include "IAssetViewport.h"
#include "MovieSceneCaptureModule.h"
#include "CoreGlobals.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformTime.h"
#include "HAL/IConsoleManager.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/SecureHash.h"
#include "Misc/App.h"
#include "ImageUtils.h"
#include "ImageCore.h"
#include "RenderingThread.h"
#include "RHI.h"
#include "RHICommandList.h"
#include "RHIGPUReadback.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"

namespace Direct004 {
constexpr int32 Width=1014,Height=550,SampleCount=6;
const TCHAR* OwnedDirectory=TEXT("D:/Dev/LivingTownNativeRuns/2026-11-04/DirectReadbackProbe_v002/DirectReadback");
struct FState {
 TWeakObjectPtr<UWorld> World;TWeakObjectPtr<APlayerController> PC;TWeakObjectPtr<APawn> Pawn;TWeakObjectPtr<AHUD> HUD;TWeakObjectPtr<APlayerCameraManager> Camera;
 TWeakObjectPtr<UGameViewportClient> Client;TSharedPtr<FSceneViewport> Scene;FDelegateHandle PostCanvasRender;FString Directory;TSharedRef<FJsonObject> Report=MakeShared<FJsonObject>();TArray<TSharedPtr<FJsonValue>> Samples;
 double Started=0.,Next=0.;uint64 LastFrame=MAX_uint64;bool Running=false,Armed=false,PersistenceFailed=false;FString PendingLabel;
 ~FState(){if(PostCanvasRender.IsValid())UGameViewportClient::OnViewportRendered().Remove(PostCanvasRender);}
};
TUniquePtr<FState> State;bool Attempted=false;
FString Json(TSharedRef<FJsonObject> O){FString Text;auto Writer=TJsonWriterFactory<>::Create(&Text);FJsonSerializer::Serialize(O,Writer);return Text;}
bool Persist(){if(!State)return false;const bool OK=FFileHelper::SaveStringToFile(Json(State->Report),*(State->Directory/TEXT("DIRECT_STATUS.json")),FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);State->PersistenceFailed|=!OK;return OK;}
void Detach(){if(State&&State->PostCanvasRender.IsValid())UGameViewportClient::OnViewportRendered().Remove(State->PostCanvasRender);if(State){State->PostCanvasRender.Reset();State->Running=false;State->Scene.Reset();}}
void Fail(const FString& Why){if(State){State->Report->SetStringField(TEXT("status"),TEXT("FAILED_DIRECT_READBACK_PROBE"));State->Report->SetStringField(TEXT("error"),Why);Detach();Persist();}}
FString RGBHash(const TArray<uint8>& RGB){return FSHA1::HashBuffer(RGB.GetData(),static_cast<uint64>(RGB.Num())).ToString().ToLower();}
TArray<uint8> Canonical(const TArray<FColor>& Pixels){TArray<uint8> RGB;RGB.Reserve(Pixels.Num()*3);for(const FColor& C:Pixels){RGB.Add(C.R);RGB.Add(C.G);RGB.Add(C.B);}return RGB;}
bool SavePixels(const FString& Stem,const TArray<FColor>& Pixels,int32 W,int32 H,TSharedRef<FJsonObject> Row){
 if(Pixels.Num()!=W*H)return false;
 TArray<uint8> RGB=Canonical(Pixels);Row->SetStringField(TEXT("canonical_rgb_hash_algorithm"),TEXT("SHA1"));Row->SetStringField(TEXT("canonical_rgb_sha1_before_encode"),RGBHash(RGB));Row->SetNumberField(TEXT("canonical_rgb_bytes"),RGB.Num());
 const FString Raw=State->Directory/(Stem+TEXT(".rgb"));const FString PNG=State->Directory/(Stem+TEXT(".png"));
 if(IFileManager::Get().FileExists(*Raw)||IFileManager::Get().FileExists(*PNG))return false;
 Row->SetStringField(TEXT("raw_rgb_file"),Raw);Row->SetStringField(TEXT("png_file"),PNG);Row->SetNumberField(TEXT("width"),W);Row->SetNumberField(TEXT("height"),H);Row->SetStringField(TEXT("pixel_policy"),TEXT("Canonical post-conversion FColor8 row-major RGB; PNG must preserve these CPU bytes exactly. Higher precision source conversion is recorded separately; sourceHDR/10bit precision is not preserved by8bitPNG"));
 if(!FFileHelper::SaveArrayToFile(RGB,*Raw))return false;
 TArray64<uint8> Encoded;if(!FImageUtils::CompressImage(Encoded,TEXT("png"),FImageView(Pixels.GetData(),W,H,EGammaSpace::sRGB)))return false;
 if(Encoded.Num()<=0||Encoded.Num()>16*1024*1024||!FFileHelper::SaveArrayToFile(Encoded,*PNG))return false;
 Row->SetNumberField(TEXT("png_bytes"),static_cast<double>(Encoded.Num()));Row->SetBoolField(TEXT("host_exact_decoded_RGB_comparison_pending"),true);return true;
}
struct FDescriptor {bool Valid=false;FString Name,Address;EPixelFormat Format=PF_Unknown;FIntPoint Size=FIntPoint::ZeroValue;uint32 Samples=0;uint64 Flags=0;};
FDescriptor Describe(FRHITexture* Texture){FDescriptor D;if(Texture){D.Valid=true;D.Name=Texture->GetName().ToString();D.Address=FString::Printf(TEXT("%p"),Texture);D.Format=Texture->GetFormat();D.Size=Texture->GetDesc().Extent;D.Samples=Texture->GetDesc().NumSamples;D.Flags=static_cast<uint64>(Texture->GetDesc().Flags);}return D;}
TSharedRef<FJsonObject> DescriptorJson(const FDescriptor& D){auto O=MakeShared<FJsonObject>();O->SetBoolField(TEXT("valid"),D.Valid);O->SetStringField(TEXT("name"),D.Name);O->SetStringField(TEXT("RHI_texture_address"),D.Address);O->SetNumberField(TEXT("format_enum"),static_cast<int32>(D.Format));O->SetStringField(TEXT("format"),GPixelFormats[D.Format].Name);O->SetNumberField(TEXT("bytes_per_pixel"),GPixelFormats[D.Format].BlockBytes);O->SetNumberField(TEXT("width"),D.Size.X);O->SetNumberField(TEXT("height"),D.Size.Y);O->SetNumberField(TEXT("samples"),D.Samples);O->SetStringField(TEXT("flags_u64"),LexToString(D.Flags));return O;}
bool Identity(FString& Error){
 if(!State||!IsInGameThread()||!GIsEditor||!GEditor||!GEngine||IsRunningCommandlet()){Error=TEXT("Owned normal Editor GameThread required");return false;}
 UWorld* W=State->World.Get();APlayerController* PC=State->PC.Get();APawn* Pawn=State->Pawn.Get();UGameViewportClient* Client=State->Client.Get();
 int32 Count=0;for(const FWorldContext& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::PIE||C.WorldType==EWorldType::Game)){++Count;if(C.World()!=W){Error=TEXT("Foreign game world");return false;}}
 if(Count!=1||!W||W->WorldType!=EWorldType::PIE||W->IsPaused()||FApp::UseFixedTimeStep()||GEditor->IsSimulateInEditorInProgress()||!PC||!PC->IsLocalController()||!Pawn||!State->HUD.IsValid()||!State->Camera.IsValid()||PC->GetWorld()!=W||W->GetFirstPlayerController()!=PC||PC->GetPawn()!=Pawn||PC->GetViewTarget()!=Pawn||PC->GetHUD()!=State->HUD.Get()||PC->PlayerCameraManager!=State->Camera.Get()||!Client||!PC->GetLocalPlayer()||PC->GetLocalPlayer()->ViewportClient!=Client||W->GetGameViewport()!=Client||!State->Scene||Client->GetGameViewport()!=State->Scene.Get()||State->Scene->GetClient()!=Client||State->Scene->GetPlayInEditorIsSimulate()){Error=TEXT("Existing natural-clock world/pawn/HUD/camera/viewport identity changed");return false;}
 int32 X=0,Y=0;PC->GetViewportSize(X,Y);if(X!=Width||Y!=Height||State->Scene->GetSizeXY()!=FIntPoint(Width,Height)){Error=TEXT("Unchanged1014x550 viewport required; never resize");return false;}
 if(IMovieSceneCaptureModule::Get().GetFirstActiveMovieSceneCapture()){Error=TEXT("Movie capture inherited/started; direct probe refuses it");return false;}return true;
}
bool Sentinel(){
 auto Row=MakeShared<FJsonObject>();State->Report->SetObjectField(TEXT("sentinel"),Row);Row->SetStringField(TEXT("stage"),TEXT("GPU_SENTINEL_BEFORE_SUBMISSION"));Persist();
 TArray<FColor> Expected,Actual;for(int32 Y=0;Y<11;++Y)for(int32 X=0;X<17;++X)Expected.Emplace((X*17+Y*3)&255,(X*7+Y*19)&255,(X*29+Y*5)&255,255);
 FDescriptor D;int32 Pitch=0,BufferHeight=0;bool ReadyBefore=false,ReadyAfter=false;FString Error;const double Begin=FPlatformTime::Seconds();
 ENQUEUE_RENDER_COMMAND(LivingTownDirectSentinel)([&](FRHICommandListImmediate& Cmd){
  const FRHITextureCreateDesc Desc=FRHITextureCreateDesc::Create2D(TEXT("LivingTownPrivatePaddedReadbackSentinel"),17,11,PF_B8G8R8A8).SetFlags(ETextureCreateFlags::ShaderResource).SetInitialState(ERHIAccess::CopyDest);
  FTextureRHIRef Texture=Cmd.CreateTexture(Desc);D=Describe(Texture.GetReference());
  if(!D.Valid||D.Format!=PF_B8G8R8A8||D.Size!=FIntPoint(17,11)||D.Samples!=1){Error=TEXT("Sentinel source descriptor mismatch");return;}
  Cmd.UpdateTexture2D(Texture,0,FUpdateTextureRegion2D(0,0,0,0,17,11),17*sizeof(FColor),reinterpret_cast<const uint8*>(Expected.GetData()));
  Cmd.Transition(FRHITransitionInfo(Texture,ERHIAccess::CopyDest,ERHIAccess::CopySrc));
  FRHIGPUTextureReadback Readback(TEXT("LivingTownDirectSentinelFence"));Readback.EnqueueCopy(Cmd,Texture,FIntVector::ZeroValue,0,FIntVector(17,11,1));ReadyBefore=Readback.IsReady();
  Cmd.ImmediateFlush(EImmediateFlushType::FlushRHIThread);Readback.Wait(Cmd,Readback.GetLastCopyGPUMask());ReadyAfter=Readback.IsReady();
  if(!ReadyAfter){Error=TEXT("Sentinel GPU fence not ready after explicit wait");return;}
  const void* Data=Readback.Lock(Pitch,&BufferHeight);
  if(!Data||Pitch<=17||BufferHeight<11){Error=TEXT("Sentinel mapped pitch/height invalid or padding not exercised");if(Data)Readback.Unlock();return;}
  const FColor* Source=static_cast<const FColor*>(Data);Actual.Reserve(17*11);for(int32 Y=0;Y<11;++Y)for(int32 X=0;X<17;++X)Actual.Add(Source[Y*Pitch+X]);Readback.Unlock();
 });FlushRenderingCommands();
 Row->SetObjectField(TEXT("source_texture"),DescriptorJson(D));Row->SetNumberField(TEXT("mapped_row_pitch_pixels"),Pitch);Row->SetNumberField(TEXT("mapped_buffer_height"),BufferHeight);Row->SetBoolField(TEXT("fence_ready_before_wait"),ReadyBefore);Row->SetBoolField(TEXT("fence_ready_after_wait"),ReadyAfter);Row->SetNumberField(TEXT("wall_seconds"),FPlatformTime::Seconds()-Begin);Row->SetStringField(TEXT("expected_rgb_sha1"),RGBHash(Canonical(Expected)));Row->SetStringField(TEXT("stage"),TEXT("GPU_SENTINEL_READBACK_BEFORE_ACCEPTANCE"));Persist();
 if(!Error.IsEmpty()||FPlatformTime::Seconds()-Begin>5.||Actual.Num()!=Expected.Num()){Fail(Error.IsEmpty()?TEXT("Sentinel timing/pixel count mismatch"):Error);return false;}
 int32 Mismatches=0;for(int32 I=0;I<Expected.Num();++I)if(Actual[I]!=Expected[I])++Mismatches;Row->SetNumberField(TEXT("exact_RGBA_mismatches"),Mismatches);Persist();
 if(Mismatches||!SavePixels(TEXT("Sentinel"),Actual,17,11,Row)){Fail(TEXT("Sentinel pixels/encoding failed; raw observations retained"));return false;}
 Row->SetStringField(TEXT("stage"),TEXT("GPU_SENTINEL_EXACT_RGBA_PASS_HOST_PNG_COMPARISON_PENDING"));Persist();return true;
}
void PostCanvasRender(FViewport* RenderedViewport){
 if(!State||!State->Running||RenderedViewport!=State->Scene.Get())return;FString Error;if(State->PersistenceFailed){Fail(TEXT("Required raw report persistence failed"));return;}if(!Identity(Error)){Fail(Error);return;}
 const double Now=FPlatformTime::Seconds();if(Now-State->Started>20.){Fail(TEXT("Finite direct probe20s budget exceeded"));return;}if(!State->Armed||Now<State->Next||State->LastFrame==GFrameCounter)return;
 State->LastFrame=GFrameCounter;const int32 Index=State->Samples.Num();State->Armed=false;auto Row=MakeShared<FJsonObject>();Row->SetNumberField(TEXT("index"),Index);Row->SetStringField(TEXT("requested_label"),State->PendingLabel);Row->SetStringField(TEXT("source_render_boundary"),TEXT("Existing exact FViewport after Canvas.Flush_GameThread via OnViewportRendered; stock ReadPixels/flush. Later Slate/UMG overlays not included; stall not FPS measurement"));Row->SetStringField(TEXT("game_frame_counter_u64"),LexToString(GFrameCounter));Row->SetNumberField(TEXT("world_seconds_before"),State->World->GetTimeSeconds());Row->SetNumberField(TEXT("wall_seconds_from_begin"),Now-State->Started);Row->SetStringField(TEXT("camera_transform_before"),State->Camera->GetTransform().ToString());Row->SetStringField(TEXT("pawn_transform_before"),State->Pawn->GetTransform().ToString());Row->SetNumberField(TEXT("pawn_speed_cm_s"),State->Pawn->GetVelocity().Size());State->Samples.Add(MakeShared<FJsonValueObject>(Row));State->Report->SetArrayField(TEXT("samples"),State->Samples);Row->SetStringField(TEXT("stage"),TEXT("SOURCE_DESCRIPTOR_BEFORE_READPIXELS"));Persist();
 if((Index<2&&State->Pawn->GetVelocity().Size()>1.)||(Index>=2&&State->Pawn->GetVelocity().Size()<20.)){Fail(TEXT("Requested stationary/moving phase not true at actual draw boundary"));return;}
 FDescriptor D;ENQUEUE_RENDER_COMMAND(LivingTownDirectDescriptor)([&](FRHICommandListImmediate&){D=Describe(State->Scene->GetShaderResourceTexture());});FlushRenderingCommands();Row->SetObjectField(TEXT("source_texture"),DescriptorJson(D));Persist();
 const bool SupportedFormat=D.Format==PF_B8G8R8A8||D.Format==PF_R8G8B8A8||D.Format==PF_A2B10G10R10||D.Format==PF_FloatRGBA;
 const int32 SourceBytes=D.Format==PF_FloatRGBA?8:4;
 IConsoleVariable* DefaultFormat=IConsoleManager::Get().FindConsoleVariable(TEXT("r.DefaultBackBufferPixelFormat"));Row->SetStringField(TEXT("readonly_DefaultBackBufferPixelFormat"),DefaultFormat?DefaultFormat->GetString():TEXT("UNAVAILABLE"));
 const TCHAR* Policy=D.Format==PF_FloatRGBA?TEXT("Installed ConvertRawR16G16B16A16FDataToFColor: per-channel extrema initially0..1, normalize, ToFColor(false). Canonical8bit post-conversion only; not HDR preservation"):D.Format==PF_A2B10G10R10?TEXT("Installed ConvertRawR10G10B10A2DataToFColor: MakeRequantizeFrom1010102 toFColor8. Canonical post-conversion only; not10bit preservation"):TEXT("Installed BGRA8/RGBA8 stock ReadPixels channel conversion toFColor8, LinearToGamma=false");Row->SetStringField(TEXT("conversion_policy"),Policy);Persist();
 if(!D.Valid||D.Size!=FIntPoint(Width,Height)||D.Samples!=1||!SupportedFormat||GPixelFormats[D.Format].BlockBytes!=SourceBytes){Fail(TEXT("Actual game source format/size/sample count has no declared installed conversion policy"));return;}
 TArray<FColor> Pixels;const double Begin=FPlatformTime::Seconds();FReadSurfaceDataFlags Flags(RCM_UNorm);Flags.SetLinearToGamma(false);const bool Read=State->Scene->ReadPixels(Pixels,Flags,FIntRect(0,0,Width,Height));
 Row->SetBoolField(TEXT("ReadPixels_return"),Read);Row->SetNumberField(TEXT("returned_pixels"),Pixels.Num());Row->SetNumberField(TEXT("read_wall_seconds"),FPlatformTime::Seconds()-Begin);Row->SetBoolField(TEXT("ReadPixels_LinearToGamma"),false);Row->SetStringField(TEXT("stage"),TEXT("CPU_READPIXELS_BEFORE_ACCEPTANCE"));Persist();
 if(!Identity(Error)||!Read||Pixels.Num()!=Width*Height||FPlatformTime::Seconds()-Begin>3.||State->Camera->GetTransform().ToString()!=Row->GetStringField(TEXT("camera_transform_before"))||State->Pawn->GetTransform().ToString()!=Row->GetStringField(TEXT("pawn_transform_before"))){Fail(Error.IsEmpty()?TEXT("ReadPixels identity/timing/count/pose changed during synchronous read"):Error);return;}
 int32 MinAlpha=255,MaxAlpha=0;for(FColor& C:Pixels){MinAlpha=FMath::Min(MinAlpha,int32(C.A));MaxAlpha=FMath::Max(MaxAlpha,int32(C.A));C.A=255;}Row->SetNumberField(TEXT("source_alpha_min"),MinAlpha);Row->SetNumberField(TEXT("source_alpha_max"),MaxAlpha);
 if(!SavePixels(FString::Printf(TEXT("frames/Sample.%08d"),Index),Pixels,Width,Height,Row)){Fail(TEXT("Typed PNG/raw canonicalRGB write refused"));return;}
 Row->SetNumberField(TEXT("world_seconds_after"),State->World->GetTimeSeconds());Row->SetStringField(TEXT("stage"),TEXT("CPU_AND_PNG_WRITTEN_HOST_EXACT_COMPARE_PENDING"));State->Next=Now+.4;Persist();
 if(State->PersistenceFailed){Fail(TEXT("Required raw report persistence failed"));return;}if(State->Samples.Num()==SampleCount){Detach();State->Report->SetStringField(TEXT("status"),TEXT("COMPLETE_DIRECT_PIXELS_HOST_EXACT_COMPARE_AND_VISUAL_REVIEW_PENDING"));State->Report->SetBoolField(TEXT("delegate_removed"),!State->PostCanvasRender.IsValid());Persist();}
}
}

FString ULivingTownCapturePilotLibrary::BeginExistingGameViewportReadbackProbe(const FString& OutputDirectory){
 using namespace Direct004;auto Refusal=MakeShared<FJsonObject>();Refusal->SetStringField(TEXT("status"),TEXT("REFUSED"));
 auto Refuse=[&](const TCHAR* Why){Refusal->SetStringField(TEXT("error"),Why);return Json(Refusal);};
 if(!IsInGameThread()||Attempted||State)return Refuse(TEXT("One new direct probe per ordinary Editor process"));Attempted=true;
 FString Directory=FPaths::ConvertRelativePathToFull(OutputDirectory);FPaths::NormalizeDirectoryName(Directory);FString Expected=FPaths::ConvertRelativePathToFull(OwnedDirectory);FPaths::NormalizeDirectoryName(Expected);
 if(Directory!=Expected||IFileManager::Get().DirectoryExists(*Directory))return Refuse(TEXT("Exact fresh owned DirectReadback directory required"));
 const FString Probe=ProbeExistingGameViewport();TSharedPtr<FJsonObject> Old;auto Reader=TJsonReaderFactory<>::Create(Probe);if(!FJsonSerializer::Deserialize(Reader,Old)||!Old||Old->GetStringField(TEXT("status"))!=TEXT("PROBED_EXACT_EXISTING_GAME_VIEWPORT_NO_CAPTURE"))return Refuse(TEXT("Positive existing-world native probe refused"));
 UWorld* World=nullptr;for(const FWorldContext& C:GEngine->GetWorldContexts())if(C.WorldType==EWorldType::PIE)World=C.World();APlayerController* PC=World?World->GetFirstPlayerController():nullptr;
 const FWorldContext* Context=World?GEngine->GetWorldContextFromWorld(World):nullptr;const FSlatePlayInEditorInfo* Info=Context?GEditor->SlatePlayInEditorMap.Find(Context->ContextHandle):nullptr;auto View=Info?Info->DestinationSlateViewport.Pin():TSharedPtr<IAssetViewport>();auto Scene=View?View->GetSharedActiveViewport():nullptr;
 if(!World||!PC||!Scene)return Refuse(TEXT("No unchanged normal PIE context after native probe"));
 State=MakeUnique<FState>();State->Directory=Directory;State->World=World;State->PC=PC;State->Pawn=PC->GetPawn();State->HUD=PC->GetHUD();State->Camera=PC->PlayerCameraManager;State->Client=World->GetGameViewport();State->Scene=Scene;
 if(!IFileManager::Get().MakeDirectory(*(Directory/TEXT("frames")),true)){State.Reset();return Refuse(TEXT("Fresh owned image directory creation failed"));}State->Report->SetStringField(TEXT("status"),TEXT("DIRECT_READBACK_SENTINEL_PENDING"));State->Report->SetObjectField(TEXT("original_existing_world_probe"),Old.ToSharedRef());State->Report->SetBoolField(TEXT("world_camera_quality_clock_or_resolution_setters_used"),false);State->Report->SetBoolField(TEXT("stock_movie_or_FrameGrabber_started"),false);State->Report->SetNumberField(TEXT("sample_limit"),SampleCount);Persist();
 FString Error;if(!Identity(Error)){Fail(Error);return Json(State->Report);}if(!Sentinel())return Json(State->Report);if(State->PersistenceFailed){Fail(TEXT("Required sentinel report persistence failed"));return Json(State->Report);}State->Started=FPlatformTime::Seconds();State->Next=State->Started;State->Running=true;State->PostCanvasRender=UGameViewportClient::OnViewportRendered().AddStatic(&PostCanvasRender);State->Report->SetStringField(TEXT("status"),TEXT("RUNNING_DIRECT_POSTCANVAS_SIX_SAMPLES"));Persist();return Json(State->Report);
}
FString ULivingTownCapturePilotLibrary::ReadExistingGameViewportReadbackProbe(){using namespace Direct004;if(!State){auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("NO_DIRECT_PROBE"));return Json(O);}if(State->PersistenceFailed)Fail(TEXT("Required raw report persistence failed"));else if(State->Running){FString Error;if(!Identity(Error))Fail(Error);else if(FPlatformTime::Seconds()-State->Started>20.)Fail(TEXT("Finite direct probe20s budget exceeded"));}return Json(State->Report);}
FString ULivingTownCapturePilotLibrary::RequestExistingGameViewportReadbackSample(const FString& Label){using namespace Direct004;if(!State||!State->Running)return ReadExistingGameViewportReadbackProbe();FString Error;const int32 Index=State->Samples.Num();const FString Expected=Index<2?FString::Printf(TEXT("stationary_%d"),Index):FString::Printf(TEXT("moving_%d"),Index);if(!Identity(Error)||Index>=SampleCount||State->Armed||Label!=Expected){Fail(Error.IsEmpty()?TEXT("Exact once-per-index stationary/moving request label required"):Error);return Json(State->Report);}State->PendingLabel=Label;State->Armed=true;State->Report->SetStringField(TEXT("armed_sample_label"),Label);Persist();return Json(State->Report);}
FString ULivingTownCapturePilotLibrary::CancelExistingGameViewportReadbackProbe(){using namespace Direct004;if(State&&State->Running)Fail(TEXT("Owned direct probe cancelled; no artifact admission"));return ReadExistingGameViewportReadbackProbe();}
