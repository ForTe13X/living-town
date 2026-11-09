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
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/SecureHash.h"
#include "Misc/App.h"
#include "Misc/CoreDelegates.h"
#include "Modules/ModuleManager.h"
#include "Containers/Ticker.h"
#include "Containers/Queue.h"
#include "HAL/Runnable.h"
#include "HAL/RunnableThread.h"
#include "HAL/Event.h"
#include "HAL/PlatformProcess.h"
#include "HAL/PlatformMisc.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "IImageWrapperModule.h"
#include "ImageCore.h"
#include "RenderingThread.h"
#include "RenderGraphBuilder.h"
#include "RenderGraphUtils.h"
#include "RHI.h"
#include "RHICommandList.h"
#include "RHIGPUReadback.h"
#include "RHISurfaceDataConversion.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonWriter.h"
#include <atomic>

// Continuous003 owns no actor, capture UObject, world clock or camera setter.
// GT alone owns UObjects/SceneViewport. RT owns readbacks. Writer owns plain CPU data.
namespace Continuous003 {
constexpr int32 Width=1014,Height=550,GpuSlots=4,CpuSlots=2,Rate=24,ScheduleCount=360;
constexpr double Duration=15.,ValidationLimit=12.,DrainLimit=12.;
const TCHAR* OwnedDirectory=TEXT("D:/Dev/LivingTownNativeRuns/2026-11-04/ContinuousCapturePilot_v003/ContinuousCapture");
FString Json(TSharedRef<FJsonObject> O){FString T;auto W=TJsonWriterFactory<>::Create(&T);FJsonSerializer::Serialize(O,W);return T;}
struct FMeta {
 int32 Role=0,Index=0,W=0,H=0,Pitch=0,BufferHeight=0;EPixelFormat Format=PF_Unknown;
 FString Stem,SourceJson,TextureAddress,TextureName;uint64 TextureFlags=0;uint32 TextureSamples=0;ETextureDimension TextureDimension=ETextureDimension::Texture2D;double CopySubmittedWall=0.,FenceReadyWall=0.;
 int32 ReadbackSlot=INDEX_NONE,ReadbackGeneration=0,AllocatedW=0,AllocatedH=0;EPixelFormat AllocatedFormat=PF_Unknown;
 uint32 AllocatedSamples=0;ETextureDimension AllocatedDimension=ETextureDimension::Texture2D;
 bool ReadbackRecreated=false,PriorPresent=false,PriorRetired=false,PriorReadyOrAbsent=false;
 TArray<FColor> Expected; // Private sentinel/parity only; no UObject or shared JSON.
};
struct FCpu {FMeta Meta{};TArray<uint8> Packed;};
struct FResult {FString Error,RowJson;int32 Role=-1,Index=-1;};
struct FSlot {
 TUniquePtr<FRHIGPUTextureReadback> Readback{};FTextureRHIRef SourceHold{};FMeta Meta{};
 bool Busy=false,ExpectedAttached=true,Retired=true;
 int32 AllocatedW=0,AllocatedH=0,Generation=0;EPixelFormat AllocatedFormat=PF_Unknown;
 uint32 AllocatedSamples=0;ETextureDimension AllocatedDimension=ETextureDimension::Texture2D;
};
struct FRenderState {
 FSlot Slots[GpuSlots];TQueue<TUniquePtr<FCpu>,EQueueMode::Spsc> CpuQueue;
 TQueue<TUniquePtr<FResult>,EQueueMode::Mpsc> Results;
 std::atomic<int32> Free{GpuSlots},CpuOccupancy{0};
 std::atomic<bool> PumpQueued{false},WriterActive{false},WriterExited{false},Closing{false},CleanupComplete{false},Fatal{false};
 FEvent* Wake=nullptr;
 FString Directory;IImageWrapperModule* ImageModule=nullptr; // Preloaded on GT, engine module stays loaded.
};
using FShared=TSharedRef<FRenderState,ESPMode::ThreadSafe>;
struct FState {
 TWeakObjectPtr<UWorld> World;TWeakObjectPtr<APlayerController> PC;TWeakObjectPtr<APawn> Pawn;
 TWeakObjectPtr<AHUD> HUD;TWeakObjectPtr<APlayerCameraManager> Camera;TWeakObjectPtr<UGameViewportClient> Client;
 TSharedPtr<FSceneViewport> Scene;FShared Shared;FDelegateHandle DrawHandle,WorldHandle,ExitHandle;
 FTSTicker::FDelegateHandle TickHandle;TSharedRef<FJsonObject> Report=MakeShared<FJsonObject>();
 TArray<TSharedPtr<FJsonValue>> Frames,Validation,Drops;FString Mode=TEXT("VALIDATING"),Error;
 double BeginWall=0.,RecordWall=0.,RecordWorld=0.,StopWall=0.;int32 NextIndex=0,ParitySlot=-1;
 uint32 OwnerPID=0;FString LaunchQPC;bool WriterJoined=false;uint64 LastFrame=MAX_uint64;bool ParitySubmitted=false,PersistenceFailed=false,Closed=false;
 explicit FState(FShared InShared):Shared(InShared){}
};
TUniquePtr<FState> State{};bool Attempted=false;
void RequestStop(const FString& Error);
bool Persist(){
 if(!State)return false;auto& O=State->Report;O->SetStringField(TEXT("status"),State->Mode);O->SetStringField(TEXT("error"),State->Error);
 O->SetArrayField(TEXT("validation"),State->Validation);O->SetArrayField(TEXT("frames"),State->Frames);O->SetArrayField(TEXT("drops"),State->Drops);
 O->SetNumberField(TEXT("GPU_free_slots"),State->Shared->Free.load());O->SetNumberField(TEXT("CPU_occupied_slots_including_writer"),State->Shared->CpuOccupancy.load());
 O->SetBoolField(TEXT("PNG_writer_active"),State->Shared->WriterActive.load());O->SetBoolField(TEXT("PNG_writer_thread_exited"),State->Shared->WriterExited.load());O->SetBoolField(TEXT("PNG_writer_thread_joined"),State->WriterJoined);O->SetBoolField(TEXT("RHI_cleanup_complete"),State->Shared->CleanupComplete.load());
 O->SetBoolField(TEXT("draw_delegate_removed"),!State->DrawHandle.IsValid());O->SetBoolField(TEXT("all_callbacks_removed"),State->Closed&&!State->TickHandle.IsValid()&&!State->WorldHandle.IsValid()&&!State->ExitHandle.IsValid()&&!State->DrawHandle.IsValid());
 const bool OK=FFileHelper::SaveStringToFile(Json(O),*(State->Shared->Directory/TEXT("CONTINUOUS_STATUS.json")),FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
 State->PersistenceFailed|=!OK;return OK;
}
void RTError(FShared S,const FString& Error){auto R=MakeUnique<FResult>();R->Error=Error;S->Fatal.store(true);S->Results.Enqueue(MoveTemp(R));}
void Drop(int32 Index,const TCHAR* Reason){
 auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("schedule_index"),Index);O->SetStringField(TEXT("reason"),Reason);
 O->SetStringField(TEXT("observed_game_frame_u64"),LexToString(GFrameCounter));O->SetNumberField(TEXT("observed_wall_seconds"),FPlatformTime::Seconds()-State->RecordWall);
 O->SetNumberField(TEXT("observed_world_seconds"),State->World.IsValid()?State->World->GetTimeSeconds():-1.);State->Drops.Add(MakeShared<FJsonValueObject>(O));
}
bool Identity(FString& Error){
 if(!State||!IsInGameThread()||!GIsEditor||!GEditor||!GEngine||IsRunningCommandlet()){Error=TEXT("Owned ordinary Editor GameThread required");return false;}
 UWorld* W=State->World.Get();APlayerController* PC=State->PC.Get();APawn* Pawn=State->Pawn.Get();UGameViewportClient* Client=State->Client.Get();
 int32 Count=0;for(const FWorldContext& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::PIE||C.WorldType==EWorldType::Game)){++Count;if(C.World()!=W){Error=TEXT("Foreign game world");return false;}}
 if(Count!=1||!W||W->WorldType!=EWorldType::PIE||W->IsPaused()||FApp::UseFixedTimeStep()||GEditor->IsSimulateInEditorInProgress()||!PC||!PC->IsLocalController()||!Pawn||!State->HUD.IsValid()||!State->Camera.IsValid()||PC->GetWorld()!=W||W->GetFirstPlayerController()!=PC||PC->GetPawn()!=Pawn||PC->GetViewTarget()!=Pawn||PC->GetHUD()!=State->HUD.Get()||PC->PlayerCameraManager!=State->Camera.Get()||!Client||!PC->GetLocalPlayer()||PC->GetLocalPlayer()->ViewportClient!=Client||W->GetGameViewport()!=Client||!State->Scene||Client->GetGameViewport()!=State->Scene.Get()||State->Scene->GetClient()!=Client||State->Scene->GetPlayInEditorIsSimulate()){Error=TEXT("Exact natural-clock world/player/pawn/HUD/camera/viewport identity changed");return false;}
 int32 X=0,Y=0;PC->GetViewportSize(X,Y);if(X!=Width||Y!=Height||State->Scene->GetSizeXY()!=FIntPoint(Width,Height)){Error=TEXT("Actual unchanged1014x550 required; never resize/resample");return false;}
 if(IMovieSceneCaptureModule::Get().GetFirstActiveMovieSceneCapture()){Error=TEXT("MovieSceneCapture/FrameGrabber must remain inactive");return false;}return true;
}
FMeta Observe(int32 Role,int32 Index){
 FMeta M{};M.Role=Role;M.Index=Index;M.W=Width;M.H=Height;M.Format=PF_A2B10G10R10;
 M.Stem=Role==1?TEXT("validation/Parity"):FString::Printf(TEXT("frames/Frame.%08d"),Index);
 auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("role"),Role);O->SetNumberField(TEXT("schedule_index"),Index);
 O->SetStringField(TEXT("source_game_frame_u64"),LexToString(GFrameCounter));O->SetStringField(TEXT("source_cycles64_u64"),LexToString(FPlatformTime::Cycles64()));
 O->SetNumberField(TEXT("source_wall_seconds"),FPlatformTime::Seconds()-State->RecordWall);O->SetNumberField(TEXT("source_world_seconds"),State->World->GetTimeSeconds());
 O->SetNumberField(TEXT("source_world_from_record_begin"),State->World->GetTimeSeconds()-State->RecordWorld);
 O->SetStringField(TEXT("pawn_transform"),State->Pawn->GetTransform().ToString());O->SetNumberField(TEXT("pawn_speed_cm_s"),State->Pawn->GetVelocity().Size());
 O->SetStringField(TEXT("camera_transform"),State->Camera->GetTransform().ToString());O->SetNumberField(TEXT("camera_FOV"),State->Camera->GetFOVAngle());
 O->SetStringField(TEXT("HUD"),State->HUD->GetPathName());O->SetStringField(TEXT("source_boundary"),TEXT("Exact existing FViewport OnViewportRendered after native Canvas flush, before EndRenderFrame; later Slate/UMG not included"));
 M.SourceJson=Json(O);return M;
}
// RT only: IsReady includes pending fence-write commands==0. No per-frame Wait or flush.
// RT-only ready snapshot, oldest original copy first; never waits for an unready fence.
bool OlderReadySourceCopy(double LeftSubmitted,int32 LeftIndex,int32 LeftSlot,double RightSubmitted,int32 RightIndex,int32 RightSlot){
 return LeftSubmitted<RightSubmitted||(LeftSubmitted==RightSubmitted&&(LeftIndex<RightIndex||(LeftIndex==RightIndex&&LeftSlot<RightSlot)));
}
void PumpRT(FShared S,FRHICommandListImmediate& Cmd){
 int32 Ready[GpuSlots];int32 ReadyCount=0;
 for(int32 I=0;I<GpuSlots;++I){
  const FSlot& Slot=S->Slots[I];
  if(!Slot.Busy||!Slot.ExpectedAttached||!Slot.Readback->IsReady())continue;
  int32 At=ReadyCount;
  while(At>0&&OlderReadySourceCopy(Slot.Meta.CopySubmittedWall,Slot.Meta.Index,I,S->Slots[Ready[At-1]].Meta.CopySubmittedWall,S->Slots[Ready[At-1]].Meta.Index,Ready[At-1])){
   Ready[At]=Ready[At-1];--At;
  }
  Ready[At]=I;++ReadyCount;
 }
 for(int32 Rank=0;Rank<ReadyCount;++Rank){
  if(S->CpuOccupancy.load()>=CpuSlots)break;
  FSlot& Slot=S->Slots[Ready[Rank]];
  int32 Pitch=0,BufferHeight=0;const void* Mapped=Slot.Readback->Lock(Pitch,&BufferHeight);
  if(!Mapped||Pitch<Slot.Meta.W||BufferHeight<Slot.Meta.H){if(Mapped)Slot.Readback->Unlock();RTError(S,TEXT("Ready mapped source pitch/height invalid"));continue;}
  auto Payload=MakeUnique<FCpu>();Payload->Meta=MoveTemp(Slot.Meta);Payload->Meta.Pitch=Pitch;Payload->Meta.BufferHeight=BufferHeight;Payload->Meta.FenceReadyWall=FPlatformTime::Seconds();
  Payload->Packed.SetNumUninitialized(Payload->Meta.W*Payload->Meta.H*4);
  for(int32 Y=0;Y<Payload->Meta.H;++Y)FMemory::Memcpy(Payload->Packed.GetData()+Y*Payload->Meta.W*4,static_cast<const uint8*>(Mapped)+static_cast<int64>(Y)*Pitch*4,Payload->Meta.W*4);
  Slot.Readback->Unlock();Slot.Retired=true;Slot.SourceHold.SafeRelease();Slot.Busy=false;S->CpuOccupancy.fetch_add(1);S->CpuQueue.Enqueue(MoveTemp(Payload));S->Free.fetch_add(1);if(S->Wake)S->Wake->Trigger();
 }
 bool AllRetired=true;for(const FSlot& Slot:S->Slots)if(Slot.Busy||!Slot.Retired||(Slot.Readback&&!Slot.Readback->IsReady()))AllRetired=false;
 if(AllRetired&&S->Closing.load()&&S->Free.load()==GpuSlots&&S->CpuOccupancy.load()==0&&!S->WriterActive.load()){
  for(FSlot& Slot:S->Slots){Slot.SourceHold.SafeRelease();Slot.Readback.Reset();}S->CleanupComplete.store(true);
 }
}
void QueuePump(){
 if(!State||State->Shared->CleanupComplete.load()||State->Shared->PumpQueued.exchange(true))return;FShared S=State->Shared;
 ENQUEUE_RENDER_COMMAND(LivingTownContinuousPump)([S](FRHICommandListImmediate& Cmd){PumpRT(S,Cmd);S->PumpQueued.store(false);});
}
// Actual producer key: FRHIGPUTextureReadback assumes format/size identity on reuse.
bool ReadbackDescriptorMatches(int32 AllocatedWidth,int32 AllocatedHeight,EPixelFormat AllocatedFormat,uint32 AllocatedSamples,ETextureDimension AllocatedDimension,int32 SourceWidth,int32 SourceHeight,EPixelFormat SourceFormat,uint32 SourceSamples,ETextureDimension SourceDimension){
 return AllocatedWidth==SourceWidth&&AllocatedHeight==SourceHeight&&AllocatedFormat==SourceFormat&&AllocatedSamples==SourceSamples&&AllocatedDimension==SourceDimension;
}
int32 EmptySlot(FShared S){for(int32 I=0;I<GpuSlots;++I)if(!S->Slots[I].Busy)return I;return INDEX_NONE;}
void SubmitRT(FShared S,FRHICommandListImmediate& Cmd,FRHITexture* Texture,FMeta Meta,bool ExpectedAttached){
 const int32 I=EmptySlot(S);if(I==INDEX_NONE){RTError(S,TEXT("GPU credit/slot invariant failed"));return;}
 if(!Texture||Texture->GetFormat()!=Meta.Format||Texture->GetDesc().Extent!=FIntPoint(Meta.W,Meta.H)||Texture->GetDesc().NumSamples!=1||Texture->GetDesc().Dimension!=ETextureDimension::Texture2D||GPixelFormats[Texture->GetFormat()].BlockBytes!=4){
  auto Observation=MakeShared<FJsonObject>();Observation->SetBoolField(TEXT("actual_texture_present"),Texture!=nullptr);Observation->SetStringField(TEXT("source_GT_metadata"),Meta.SourceJson);
  if(Texture){Observation->SetStringField(TEXT("actual_format"),GPixelFormats[Texture->GetFormat()].Name);Observation->SetNumberField(TEXT("actual_width"),Texture->GetDesc().Extent.X);Observation->SetNumberField(TEXT("actual_height"),Texture->GetDesc().Extent.Y);Observation->SetNumberField(TEXT("actual_samples"),Texture->GetDesc().NumSamples);Observation->SetStringField(TEXT("actual_flags_u64"),LexToString(static_cast<uint64>(Texture->GetDesc().Flags)));}
  S->Free.fetch_add(1);RTError(S,TEXT("Source descriptor rejected before copy; actual observation: ")+Json(Observation));return;
 }
 FSlot& Slot=S->Slots[I];const bool PriorPresent=bool(Slot.Readback);const bool PriorReadyOrAbsent=!PriorPresent||Slot.Readback->IsReady();
 if(!Slot.Retired||!PriorReadyOrAbsent){S->Free.fetch_add(1);RTError(S,TEXT("Free readback slot has not retired its prior fence/mapping; recreation refused"));return;}
 const bool SameDescriptor=ReadbackDescriptorMatches(Slot.AllocatedW,Slot.AllocatedH,Slot.AllocatedFormat,Slot.AllocatedSamples,Slot.AllocatedDimension,Meta.W,Meta.H,Meta.Format,Texture->GetDesc().NumSamples,Texture->GetDesc().Dimension);
 const bool Recreate=!Slot.Readback||!SameDescriptor;
 if(Recreate){
  // Only RT, after prior ready fence + Unlock/retirement; no in-flight map/copy may be destroyed.
  Slot.Readback.Reset();Slot.Readback=MakeUnique<FRHIGPUTextureReadback>(FName(*FString::Printf(TEXT("LivingTownContinuousSlot%d"),I)));
  Slot.AllocatedW=Meta.W;Slot.AllocatedH=Meta.H;Slot.AllocatedFormat=Meta.Format;Slot.AllocatedSamples=Texture->GetDesc().NumSamples;Slot.AllocatedDimension=Texture->GetDesc().Dimension;++Slot.Generation;
 }
 Meta.ReadbackSlot=I;Meta.PriorPresent=PriorPresent;Meta.PriorRetired=Slot.Retired;Meta.PriorReadyOrAbsent=PriorReadyOrAbsent;Meta.ReadbackRecreated=Recreate;Meta.ReadbackGeneration=Slot.Generation;
 Meta.AllocatedW=Slot.AllocatedW;Meta.AllocatedH=Slot.AllocatedH;Meta.AllocatedFormat=Slot.AllocatedFormat;Meta.AllocatedSamples=Slot.AllocatedSamples;Meta.AllocatedDimension=Slot.AllocatedDimension;
 Slot.Retired=false;Slot.Busy=true;Slot.ExpectedAttached=ExpectedAttached;Slot.SourceHold=Texture;Slot.Meta=MoveTemp(Meta);Slot.Meta.CopySubmittedWall=FPlatformTime::Seconds();
 Slot.Meta.TextureFlags=static_cast<uint64>(Texture->GetDesc().Flags);Slot.Meta.TextureSamples=Texture->GetDesc().NumSamples;Slot.Meta.TextureDimension=Texture->GetDesc().Dimension;
 Slot.Meta.TextureAddress=FString::Printf(TEXT("%p"),Texture);Slot.Meta.TextureName=Texture->GetName().ToString();
 FRDGBuilder Graph(Cmd);FRDGTextureRef Source=RegisterExternalTexture(Graph,Texture,TEXT("LivingTownExistingViewportReadbackSource"));
 AddEnqueueCopyPass(Graph,Slot.Readback.Get(),Source,FResolveRect(0,0,Slot.Meta.W,Slot.Meta.H));
 Graph.SetTextureAccessFinal(Source,ERHIAccess::SRVMask);Graph.Execute();
}
void SubmitScene(FMeta Meta,bool Parity){
 FShared S=State->Shared;FSceneViewport* Scene=State->Scene.Get();S->Free.fetch_sub(1);
 ENQUEUE_RENDER_COMMAND(LivingTownContinuousSourceCopy)([S,Scene,Meta=MoveTemp(Meta),Parity](FRHICommandListImmediate& Cmd)mutable{
  SubmitRT(S,Cmd,Scene->GetShaderResourceTexture(),MoveTemp(Meta),!Parity);
 });
}
void Sentinels(FShared S){
 S->Free.fetch_sub(2);
 ENQUEUE_RENDER_COMMAND(LivingTownContinuousSentinels)([S](FRHICommandListImmediate& Cmd){
  for(int32 K=0;K<2;++K){
   FMeta M{};M.Role=0;M.Index=K;M.W=17;M.H=11;M.Format=K==0?PF_B8G8R8A8:PF_A2B10G10R10;M.Stem=FString::Printf(TEXT("validation/Sentinel%d"),K);M.SourceJson=TEXT("{}");
   TArray<uint32> Packed;Packed.Reserve(17*11);
   for(int32 Y=0;Y<11;++Y)for(int32 X=0;X<17;++X){
    if(K==0){FColor C((X*17+Y*3)&255,(X*7+Y*19)&255,(X*29+Y*5)&255,255);M.Expected.Add(C);uint32 V=0;FMemory::Memcpy(&V,&C,4);Packed.Add(V);}
    else{const uint32 R=(X*67+Y*13)&1023,G=(X*29+Y*97)&1023,B=(X*101+Y*31)&1023;Packed.Add(R|(G<<10)|(B<<20)|(3u<<30));M.Expected.Add(FColor::MakeRequantizeFrom1010102(R,G,B,3));}
   }
   const FRHITextureCreateDesc Desc=FRHITextureCreateDesc::Create2D(TEXT("LivingTownContinuousPrivateSentinel"),17,11,M.Format).SetFlags(ETextureCreateFlags::ShaderResource).SetInitialState(ERHIAccess::CopyDest);
   FTextureRHIRef Texture=Cmd.CreateTexture(Desc);Cmd.UpdateTexture2D(Texture,0,FUpdateTextureRegion2D(0,0,0,0,17,11),17*4,reinterpret_cast<const uint8*>(Packed.GetData()));
   Cmd.Transition(FRHITransitionInfo(Texture,ERHIAccess::CopyDest,ERHIAccess::SRVMask));SubmitRT(S,Cmd,Texture,MoveTemp(M),true);
  }
 });
}
// One pre-recording parity read is intentionally synchronous, never called for recording frames.
void Parity(){
 State->ParitySubmitted=true;FMeta M=Observe(1,-1);const FString BeforePawn=State->Pawn->GetTransform().ToString(),BeforeCamera=State->Camera->GetTransform().ToString();
 const uint64 BeforeFrame=GFrameCounter;const double BeforeWorld=State->World->GetTimeSeconds();SubmitScene(MoveTemp(M),true);
 TArray<FColor> Expected;FReadSurfaceDataFlags Flags(RCM_UNorm);Flags.SetLinearToGamma(false);const double Beg=FPlatformTime::Seconds();
 const bool OK=State->Scene->ReadPixels(Expected,Flags,FIntRect(0,0,Width,Height));
 auto O=MakeShared<FJsonObject>();O->SetBoolField(TEXT("ReadPixels_return"),OK);O->SetNumberField(TEXT("pixels"),Expected.Num());O->SetNumberField(TEXT("wall_seconds"),FPlatformTime::Seconds()-Beg);
 O->SetStringField(TEXT("before_frame_u64"),LexToString(BeforeFrame));O->SetStringField(TEXT("after_frame_u64"),LexToString(GFrameCounter));O->SetNumberField(TEXT("before_world_seconds"),BeforeWorld);O->SetNumberField(TEXT("after_world_seconds"),State->World->GetTimeSeconds());
 TArray<uint8> StockRGB;StockRGB.Reserve(Expected.Num()*3);for(const FColor& C:Expected){StockRGB.Add(C.R);StockRGB.Add(C.G);StockRGB.Add(C.B);}
 const FString StockRaw=State->Shared->Directory/TEXT("validation/Parity.stock.rgb");const bool StockSaved=FFileHelper::SaveArrayToFile(StockRGB,*StockRaw);
 O->SetStringField(TEXT("stock_raw_rgb_file"),StockRaw);O->SetBoolField(TEXT("stock_raw_saved"),StockSaved);O->SetStringField(TEXT("stock_rgb_sha1"),FSHA1::HashBuffer(StockRGB.GetData(),static_cast<uint64>(StockRGB.Num())).ToString().ToLower());
 State->Report->SetObjectField(TEXT("one_prerecording_stock_ReadPixels_parity"),O);Persist();
 if(!OK||!StockSaved||Expected.Num()!=Width*Height||FPlatformTime::Seconds()-Beg>3.||GFrameCounter!=BeforeFrame||State->World->GetTimeSeconds()!=BeforeWorld||BeforePawn!=State->Pawn->GetTransform().ToString()||BeforeCamera!=State->Camera->GetTransform().ToString()){
  RequestStop(TEXT("One source parity stock read failed/count/3s/natural identity changed"));
 }
 FShared S=State->Shared;ENQUEUE_RENDER_COMMAND(LivingTownContinuousAttachParity)([S,Expected=MoveTemp(Expected)](FRHICommandListImmediate&)mutable{
  for(FSlot& Slot:S->Slots)if(Slot.Busy&&Slot.Meta.Role==1){Slot.Meta.Expected=MoveTemp(Expected);Slot.ExpectedAttached=true;return;}RTError(S,TEXT("Expected parity slot absent"));
 });
}
TUniquePtr<FResult> WriteCPU(FShared S,TUniquePtr<FCpu> P){
 auto R=MakeUnique<FResult>();R->Role=P->Meta.Role;R->Index=P->Meta.Index;auto O=MakeShared<FJsonObject>();
 auto Reader=TJsonReaderFactory<>::Create(P->Meta.SourceJson);TSharedPtr<FJsonObject> Source;FJsonSerializer::Deserialize(Reader,Source);if(Source)O=Source.ToSharedRef();
 const FMeta& M=P->Meta;TArray<FColor> Pixels;Pixels.SetNumUninitialized(M.W*M.H);
 if(M.Format==PF_A2B10G10R10)ConvertRawR10G10B10A2DataToFColor(M.W,M.H,P->Packed.GetData(),M.W*4,Pixels.GetData());
 else if(M.Format==PF_B8G8R8A8)FMemory::Memcpy(Pixels.GetData(),P->Packed.GetData(),P->Packed.Num());
 else{R->Error=TEXT("Unsupported async CPU conversion");return R;}
 int32 Mismatches=0;if(M.Role!=2){if(M.Expected.Num()!=Pixels.Num())Mismatches=-1;else for(int32 I=0;I<Pixels.Num();++I)if(Pixels[I].R!=M.Expected[I].R||Pixels[I].G!=M.Expected[I].G||Pixels[I].B!=M.Expected[I].B||(M.Role==0&&Pixels[I].A!=M.Expected[I].A))++Mismatches;}
 O->SetNumberField(TEXT("role"),M.Role);O->SetNumberField(TEXT("schedule_index"),M.Index);O->SetNumberField(TEXT("width"),M.W);O->SetNumberField(TEXT("height"),M.H);O->SetStringField(TEXT("source_format"),GPixelFormats[M.Format].Name);O->SetStringField(TEXT("source_RHI_texture_address"),M.TextureAddress);O->SetStringField(TEXT("source_RHI_texture_name"),M.TextureName);
 O->SetNumberField(TEXT("readback_slot_index"),M.ReadbackSlot);O->SetNumberField(TEXT("readback_allocation_generation"),M.ReadbackGeneration);O->SetBoolField(TEXT("readback_descriptor_recreated"),M.ReadbackRecreated);O->SetBoolField(TEXT("prior_readback_present"),M.PriorPresent);O->SetBoolField(TEXT("slot_retired_before_submit"),M.PriorRetired);O->SetBoolField(TEXT("prior_fence_ready_or_absent"),M.PriorReadyOrAbsent);
 O->SetNumberField(TEXT("readback_allocated_width"),M.AllocatedW);O->SetNumberField(TEXT("readback_allocated_height"),M.AllocatedH);O->SetStringField(TEXT("readback_allocated_format"),GPixelFormats[M.AllocatedFormat].Name);O->SetNumberField(TEXT("readback_allocated_samples"),M.AllocatedSamples);O->SetNumberField(TEXT("readback_allocated_dimension_enum"),static_cast<int32>(M.AllocatedDimension));
 O->SetNumberField(TEXT("source_dimension_enum"),static_cast<int32>(M.TextureDimension));O->SetNumberField(TEXT("source_samples"),M.TextureSamples);O->SetStringField(TEXT("source_flags_u64"),LexToString(M.TextureFlags));O->SetNumberField(TEXT("source_format_enum"),static_cast<int32>(M.Format));
 O->SetNumberField(TEXT("mapped_row_pitch_pixels"),M.Pitch);O->SetNumberField(TEXT("mapped_buffer_height"),M.BufferHeight);O->SetNumberField(TEXT("copy_submitted_wall_absolute"),M.CopySubmittedWall);O->SetNumberField(TEXT("fence_ready_wall_absolute"),M.FenceReadyWall);
 O->SetNumberField(TEXT("known_expected_mismatches"),Mismatches);O->SetBoolField(TEXT("fence_ready_before_Lock"),true);O->SetStringField(TEXT("conversion"),M.Format==PF_A2B10G10R10?TEXT("Installed ConvertRawR10G10B10A2DataToFColor/MakeRequantizeFrom1010102; post-conversion8bit only, not10bit preservation"):TEXT("Private sentinel BGRA8 direct bytes"));
 TArray<uint8> RGB;RGB.Reserve(Pixels.Num()*3);for(FColor& C:Pixels){RGB.Add(C.R);RGB.Add(C.G);RGB.Add(C.B);C.A=255;}
 const FString Raw=S->Directory/(M.Stem+TEXT(".rgb")),PNG=S->Directory/(M.Stem+TEXT(".png")),Receipt=S->Directory/(M.Stem+TEXT(".json"));
 O->SetStringField(TEXT("raw_rgb_file"),Raw);O->SetStringField(TEXT("png_file"),PNG);O->SetStringField(TEXT("canonical_rgb_hash_algorithm"),TEXT("SHA1"));O->SetStringField(TEXT("canonical_rgb_sha1_before_encode"),FSHA1::HashBuffer(RGB.GetData(),static_cast<uint64>(RGB.Num())).ToString().ToLower());O->SetNumberField(TEXT("canonical_rgb_bytes"),RGB.Num());
 O->SetNumberField(TEXT("writer_begin_wall_absolute"),FPlatformTime::Seconds());O->SetBoolField(TEXT("exact_decoded_PNG_RGB_host_comparison_pending"),true);
 // Preserve actual diagnostic metadata before any acceptance decision or PNG call.
 if(!FFileHelper::SaveStringToFile(Json(O),*Receipt,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM)){R->Error=TEXT("Before-acceptance source receipt write failed");return R;}
 if(M.Role!=2&&(Mismatches!=0||(M.Role==0&&M.Pitch<=17))){R->Error=TEXT("Async sentinel/parity mismatch or padded stride not exercised");return R;}
 if(IFileManager::Get().FileExists(*Raw)||IFileManager::Get().FileExists(*PNG)){R->Error=TEXT("Fresh per-source output collision");return R;}
 TArray64<uint8> Encoded;
 if(!FFileHelper::SaveArrayToFile(RGB,*Raw)||!S->ImageModule->CompressImage(Encoded,EImageFormat::PNG,FImageView(Pixels.GetData(),M.W,M.H,EGammaSpace::sRGB),-1)||Encoded.Num()<=0||Encoded.Num()>16*1024*1024||!FFileHelper::SaveArrayToFile(Encoded,*PNG)){R->Error=TEXT("Single bounded PNG writer/raw write failed");return R;}
 O->SetNumberField(TEXT("writer_finished_wall_absolute"),FPlatformTime::Seconds());O->SetNumberField(TEXT("png_bytes"),static_cast<double>(Encoded.Num()));
 R->RowJson=Json(O);if(!FFileHelper::SaveStringToFile(R->RowJson,*Receipt,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM))R->Error=TEXT("Final source receipt write failed");return R;
}
// One actual joinable native thread. No TaskGraph callable may outlive module unload.
struct FWriter final:FRunnable {
 FShared Shared;
 explicit FWriter(FShared InShared):Shared(InShared){}
 virtual uint32 Run() override {
  for(;;){
   TUniquePtr<FCpu> P;
   if(Shared->CpuQueue.Dequeue(P)){
    Shared->WriterActive.store(true);auto R=WriteCPU(Shared,MoveTemp(P));if(!R->Error.IsEmpty())Shared->Fatal.store(true);
    Shared->Results.Enqueue(MoveTemp(R));Shared->CpuOccupancy.fetch_sub(1);Shared->WriterActive.store(false);continue;
   }
   if(Shared->Closing.load()&&Shared->Free.load()==GpuSlots&&Shared->CpuOccupancy.load()==0)break;
   Shared->Wake->Wait(5);
  }
  Shared->WriterExited.store(true);return 0;
 }
};
TUniquePtr<FWriter> Writer{};TUniquePtr<FRunnableThread> WriterThread{};
void StartWriter(){if(State&&State->Shared->Wake)State->Shared->Wake->Trigger();}
void JoinExitedWriter(){
 if(State->WriterJoined||!State->Shared->WriterExited.load()||!WriterThread)return;
 WriterThread->WaitForCompletion();WriterThread.Reset();Writer.Reset();State->WriterJoined=true;
 if(State->Shared->Wake){FPlatformProcess::ReturnSynchEventToPool(State->Shared->Wake);State->Shared->Wake=nullptr;}
}
bool OwnedProcess(TSharedRef<FJsonObject> Observation){
 const FString Base=TEXT("D:/Dev/LivingTownNativeRuns/2026-11-04/ContinuousCapturePilot_v003");
 FString Project=FPaths::ConvertRelativePathToFull(FPaths::GetProjectFilePath());FPaths::NormalizeFilename(Project);
 FString User,Port;FParse::Value(FCommandLine::Get(),TEXT("UserDir="),User);FParse::Value(FCommandLine::Get(),TEXT("ModelContextProtocolPort="),Port);FPaths::NormalizeDirectoryName(User);
 const FString EnvQPC=FPlatformMisc::GetEnvironmentVariable(TEXT("LIVING_TOWN_BINDING_LAUNCH_QPC_NS"));
 FString EnvOutput=FPlatformMisc::GetEnvironmentVariable(TEXT("LT_ENTRANCE_OUTPUT"));FPaths::NormalizeDirectoryName(EnvOutput);
 Observation->SetNumberField(TEXT("actual_PID"),FPlatformProcess::GetCurrentProcessId());Observation->SetStringField(TEXT("actual_project"),Project);Observation->SetStringField(TEXT("actual_UserDir"),User);Observation->SetStringField(TEXT("actual_MCP_port"),Port);Observation->SetStringField(TEXT("launcher_environment_QPC_ns"),EnvQPC);Observation->SetStringField(TEXT("launcher_output_environment"),EnvOutput);
 FString Raw;TSharedPtr<FJsonObject> Job;
 if(!FFileHelper::LoadFileToString(Raw,*(Base/TEXT("LIVE_JOB.json"))))return false;
 auto Reader=TJsonReaderFactory<>::Create(Raw);if(!FJsonSerializer::Deserialize(Reader,Job)||!Job)return false;Observation->SetObjectField(TEXT("host_LIVE_JOB"),Job.ToSharedRef());
 double PID=0.,JobPort=0.;bool Only=false;FString Kind,QPC;
 if(!Job->TryGetNumberField(TEXT("root_pid"),PID)||!Job->TryGetNumberField(TEXT("port"),JobPort)||!Job->TryGetBoolField(TEXT("only_owned_tree"),Only)||!Job->TryGetStringField(TEXT("kind"),Kind)||!Job->TryGetStringField(TEXT("launch_qpc_ns"),QPC))return false;
 return PID==FPlatformProcess::GetCurrentProcessId()&&Only&&Kind==TEXT("UnrealD3D12SM6Editor")&&JobPort==20351.&&Port==TEXT("20351")&&Project==Base/TEXT("Project/LivingTown.uproject")&&User==Base/TEXT("private/User")&&EnvOutput==Base&&!EnvQPC.IsEmpty()&&EnvQPC.IsNumeric()&&QPC==EnvQPC&&FParse::Param(FCommandLine::Get(),TEXT("unattended"))&&FParse::Param(FCommandLine::Get(),TEXT("NoLiveCoding"));
}
void DrainResults(){
 TUniquePtr<FResult> R;while(State->Shared->Results.Dequeue(R)){
  if(!R->Error.IsEmpty()){RequestStop(R->Error);continue;}TSharedPtr<FJsonObject> O;auto Reader=TJsonReaderFactory<>::Create(R->RowJson);
  if(!FJsonSerializer::Deserialize(Reader,O)||!O){RequestStop(TEXT("Worker result JSON invalid"));continue;}
  (R->Role==2?State->Frames:State->Validation).Add(MakeShared<FJsonValueObject>(O));
 }
}
void RequestStop(const FString& Error){
 if(!State||State->Closed)return;if(!Error.IsEmpty()&&State->Error.IsEmpty())State->Error=Error;
 if(State->DrawHandle.IsValid()){UGameViewportClient::OnViewportRendered().Remove(State->DrawHandle);State->DrawHandle.Reset();}
 if(State->Mode==TEXT("RECORDING"))while(State->NextIndex<ScheduleCount)Drop(State->NextIndex++,TEXT("NO_SOURCE_OBSERVATION_BEFORE_RECORD_END"));
 if(State->StopWall==0.)State->StopWall=FPlatformTime::Seconds();State->Mode=TEXT("STOPPING_AND_DRAINING");State->Shared->Closing.store(true);Persist();QueuePump();
}
void PostCanvas(FViewport* Rendered){
 if(!State||Rendered!=State->Scene.Get())return;FString Error;if(!Identity(Error)){RequestStop(Error);return;}
 if(State->Mode==TEXT("VALIDATING")){if(!State->ParitySubmitted&&State->Shared->Free.load()>0)Parity();return;}
 if(State->Mode!=TEXT("RECORDING"))return;const double Elapsed=FPlatformTime::Seconds()-State->RecordWall;
 if(Elapsed>=Duration){RequestStop(TEXT(""));return;}if(State->LastFrame==GFrameCounter)return;State->LastFrame=GFrameCounter;
 const int32 Index=FMath::Min(ScheduleCount-1,FMath::FloorToInt(Elapsed*Rate));if(Index<State->NextIndex)return;
 while(State->NextIndex<Index)Drop(State->NextIndex++,TEXT("MISSED_24HZ_OPPORTUNITY_NO_DUPLICATED_FRAME"));State->NextIndex=Index+1;
 if(State->Shared->Free.load()<=0){Drop(Index,TEXT("BOUNDED_GPU_OR_WRITER_BACKPRESSURE"));return;}
 SubmitScene(Observe(2,Index),false);
}
void WorldCleanup(UWorld* W,bool,bool){if(State&&State->World.Get()==W)RequestStop(TEXT("Source world ended; drain pure RHI/CPU without touching destroyed UObjects"));}
void PreExit(){
 if(!State||State->Closed)return;
 RequestStop(TEXT("Natural Editor shutdown before recording admission; no source reuse"));
 const double Deadline=FPlatformTime::Seconds()+DrainLimit;
 // Shutdown only: renderer fences may block; the root-owned600s/900s supervisor
 // still bounds a stalled engine call. Module unload cannot proceed past this hook.
 while(FPlatformTime::Seconds()<Deadline){
  DrainResults();StartWriter();QueuePump();FlushRenderingCommands();DrainResults();
  if(State->Shared->CleanupComplete.load()&&State->Shared->WriterExited.load()&&!State->Shared->PumpQueued.load()){
   JoinExitedWriter();if(State->WriterJoined){
    FTSTicker::RemoveTicker(State->TickHandle);State->TickHandle.Reset();FWorldDelegates::OnWorldCleanup.Remove(State->WorldHandle);State->WorldHandle.Reset();
    FCoreDelegates::OnEnginePreExit.Remove(State->ExitHandle);State->ExitHandle.Reset();State->Scene.Reset();State->World.Reset();State->PC.Reset();State->Pawn.Reset();State->HUD.Reset();State->Camera.Reset();State->Client.Reset();State->Closed=true;State->Mode=TEXT("FAILED_NATURAL_SHUTDOWN_DRAINED_AND_THREAD_JOINED");Persist();return;
   }
  }
  FPlatformProcess::Sleep(.001f);
 }
 State->Mode=TEXT("ROOT_REAP_REQUIRED_OWNED_SHUTDOWN_FAILURE");auto Owner=MakeShared<FJsonObject>();const bool Owned=OwnedProcess(Owner)&&FPlatformProcess::GetCurrentProcessId()==State->OwnerPID&&FPlatformMisc::GetEnvironmentVariable(TEXT("LIVING_TOWN_BINDING_LAUNCH_QPC_NS"))==State->LaunchQPC;
 State->Report->SetObjectField(TEXT("shutdown_owner_recheck_before_forced_self_exit"),Owner);State->Report->SetBoolField(TEXT("forced_owned_self_exit_required"),Owned);Persist();
 // Ownership was required before thread creation and is rechecked here. This is
 // failure95, never positive controlled92. No foreign process handle is used.
 if(Owned)FPlatformMisc::RequestExitWithStatus(true,95,TEXT("LivingTownContinuousOwnedShutdownDrainFailure"));
 // If ownership custody was violated, never return into module unload with a live
 // writer. The external owned-job supervisor must reap this exact failed root.
 for(;;){FPlatformProcess::Sleep(.05f);}
}
bool Tick(float){
 if(!State||State->Closed)return false;DrainResults();StartWriter();QueuePump();const double Now=FPlatformTime::Seconds();
 if(State->PersistenceFailed&&State->Error.IsEmpty())RequestStop(TEXT("Required status persistence failed"));
 if(State->Shared->Fatal.load()&&State->Error.IsEmpty())RequestStop(TEXT("Async RT/writer fatal observation pending retained diagnostic"));
 if(State->Mode==TEXT("VALIDATING")&&State->Validation.Num()==3){State->Mode=TEXT("READY_AFTER_ASYNC_SENTINELS_AND_EXACT_PARITY");Persist();}
 if((State->Mode==TEXT("VALIDATING")||State->Mode==TEXT("READY_AFTER_ASYNC_SENTINELS_AND_EXACT_PARITY"))&&Now-State->BeginWall>ValidationLimit)RequestStop(TEXT("12s finite asynchronous validation deadline"));
 if(State->Mode==TEXT("RECORDING")&&Now-State->RecordWall>=Duration)RequestStop(TEXT(""));
 if(State->StopWall>0.&&State->Shared->CleanupComplete.load()&&State->Shared->WriterExited.load()&&!State->Shared->PumpQueued.load()){
  JoinExitedWriter();if(!State->WriterJoined)return true;
  DrainResults();State->Scene.Reset();State->World.Reset();State->PC.Reset();State->Pawn.Reset();State->HUD.Reset();State->Camera.Reset();State->Client.Reset();
  FWorldDelegates::OnWorldCleanup.Remove(State->WorldHandle);FCoreDelegates::OnEnginePreExit.Remove(State->ExitHandle);State->WorldHandle.Reset();State->ExitHandle.Reset();State->Closed=true;
  State->Mode=State->Error.IsEmpty()?TEXT("COMPLETE_CONTINUOUS_RAW_HOST_PIXEL_AND_VISUAL_REVIEW_PENDING"):TEXT("FAILED_CONTINUOUS_DRAINED_RAW_RETAINED");Persist();return false;
 }
 if(State->StopWall>0.&&Now-State->StopWall>DrainLimit){if(State->Error.IsEmpty())State->Error=TEXT("12s bounded drain exceeded; late closure cannot admit success");State->Mode=TEXT("ROOT_REAP_REQUIRED");Persist();return true;}
 return true;
}
}

FString ULivingTownCapturePilotLibrary::BeginExistingGameViewportContinuousCapture(const FString& OutputDirectory){
 using namespace Continuous003;auto Refusal=MakeShared<FJsonObject>();Refusal->SetStringField(TEXT("status"),TEXT("REFUSED"));auto Refuse=[&](const TCHAR* Why){Refusal->SetStringField(TEXT("error"),Why);return Json(Refusal);};
 if(!IsInGameThread()||Attempted||State)return Refuse(TEXT("One fresh continuous capture per ordinary Editor process"));Attempted=true;
 FString Directory=FPaths::ConvertRelativePathToFull(OutputDirectory);FPaths::NormalizeDirectoryName(Directory);FString Expected=FPaths::ConvertRelativePathToFull(OwnedDirectory);FPaths::NormalizeDirectoryName(Expected);
 if(Directory!=Expected||IFileManager::Get().DirectoryExists(*Directory))return Refuse(TEXT("Exact fresh ContinuousCapturePilot_v003 owned directory required"));
 const FString Probe=ProbeExistingGameViewport();TSharedPtr<FJsonObject> Original;auto Reader=TJsonReaderFactory<>::Create(Probe);if(!FJsonSerializer::Deserialize(Reader,Original)||!Original||Original->GetStringField(TEXT("status"))!=TEXT("PROBED_EXACT_EXISTING_GAME_VIEWPORT_NO_CAPTURE"))return Refuse(TEXT("Unchanged positive native existing-world probe refused"));
 UWorld* W=nullptr;for(const FWorldContext& C:GEngine->GetWorldContexts())if(C.WorldType==EWorldType::PIE)W=C.World();APlayerController* PC=W?W->GetFirstPlayerController():nullptr;
 const FWorldContext* Context=W?GEngine->GetWorldContextFromWorld(W):nullptr;const FSlatePlayInEditorInfo* Info=Context?GEditor->SlatePlayInEditorMap.Find(Context->ContextHandle):nullptr;auto View=Info?Info->DestinationSlateViewport.Pin():TSharedPtr<IAssetViewport>();auto Scene=View?View->GetSharedActiveViewport():nullptr;
 if(!W||!PC||!Scene)return Refuse(TEXT("No exact existing PIE viewport"));
 auto Owner=MakeShared<FJsonObject>();const bool Owned=OwnedProcess(Owner);Refusal->SetObjectField(TEXT("actual_owned_process_observation"),Owner);if(!Owned)return Refuse(TEXT("Host LIVE_JOB PID/QPC, launcher environment, exact private project/UserDir/port ownership required before worker"));
 IImageWrapperModule& Images=FModuleManager::LoadModuleChecked<IImageWrapperModule>(TEXT("ImageWrapper"));
 FShared S=MakeShared<FRenderState,ESPMode::ThreadSafe>();S->Directory=Directory;S->ImageModule=&Images;State=MakeUnique<FState>(S);
 State->World=W;State->PC=PC;State->Pawn=PC->GetPawn();State->HUD=PC->GetHUD();State->Camera=PC->PlayerCameraManager;State->Client=W->GetGameViewport();State->Scene=Scene;State->BeginWall=State->RecordWall=FPlatformTime::Seconds();State->RecordWorld=W->GetTimeSeconds();
 if(!IFileManager::Get().MakeDirectory(*(Directory/TEXT("validation")),true)||!IFileManager::Get().MakeDirectory(*(Directory/TEXT("frames")),true)){State.Reset();return Refuse(TEXT("Fresh owned output creation failed"));}
 State->OwnerPID=FPlatformProcess::GetCurrentProcessId();State->LaunchQPC=FPlatformMisc::GetEnvironmentVariable(TEXT("LIVING_TOWN_BINDING_LAUNCH_QPC_NS"));State->Report->SetObjectField(TEXT("actual_owned_process_observation"),Owner);
 State->Report->SetObjectField(TEXT("original_existing_world_probe"),Original.ToSharedRef());State->Report->SetNumberField(TEXT("scheduled_rate_Hz_not_world_clock"),Rate);State->Report->SetNumberField(TEXT("scheduled_opportunities"),ScheduleCount);State->Report->SetNumberField(TEXT("duration_wall_seconds"),Duration);State->Report->SetNumberField(TEXT("GPU_slot_limit"),GpuSlots);State->Report->SetNumberField(TEXT("CPU_slot_limit_including_writer"),CpuSlots);State->Report->SetNumberField(TEXT("PNG_writer_limit"),1);State->Report->SetBoolField(TEXT("world_camera_quality_clock_resolution_or_pose_setters_used"),false);State->Report->SetBoolField(TEXT("FrameGrabber_or_movie_capture_started"),false);State->Report->SetBoolField(TEXT("source_precision_preserved"),false);State->Report->SetStringField(TEXT("source_format_policy"),TEXT("Actual PF_A2B10G10R10 single-sample1014x550 only; installed10bit toFColor8 conversion, no silent fallback"));
 FString Error;if(!Identity(Error)){State->Error=Error;State->Mode=TEXT("REFUSED_BEFORE_ASYNC_SUBMISSION");State->Scene.Reset();Persist();return Json(State->Report);}
 S->Wake=FPlatformProcess::GetSynchEventFromPool(false);if(!S->Wake){State->Error=TEXT("Private writer event allocation failed before thread/RHI submission");State->Mode=TEXT("REFUSED_BEFORE_ASYNC_SUBMISSION");Persist();return Json(State->Report);}Writer=MakeUnique<FWriter>(S);WriterThread.Reset(FRunnableThread::Create(Writer.Get(),TEXT("LivingTownSinglePNGWriter"),0,TPri_BelowNormal));
 if(!WriterThread){FPlatformProcess::ReturnSynchEventToPool(S->Wake);S->Wake=nullptr;Writer.Reset();State->Error=TEXT("Dedicated writer thread creation failed before RHI submission");State->Mode=TEXT("REFUSED_BEFORE_ASYNC_SUBMISSION");Persist();return Json(State->Report);}
 Sentinels(S);State->DrawHandle=UGameViewportClient::OnViewportRendered().AddStatic(&PostCanvas);State->WorldHandle=FWorldDelegates::OnWorldCleanup.AddStatic(&WorldCleanup);State->ExitHandle=FCoreDelegates::OnEnginePreExit.AddStatic(&PreExit);State->TickHandle=FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateStatic(&Tick));Persist();return Json(State->Report);
}
FString ULivingTownCapturePilotLibrary::StartExistingGameViewportContinuousCapture(){
 using namespace Continuous003;if(!State)return TEXT("{\"status\":\"NO_CONTINUOUS_CAPTURE\"}");DrainResults();FString Error;
 if(State->Mode!=TEXT("READY_AFTER_ASYNC_SENTINELS_AND_EXACT_PARITY")||!Identity(Error)||State->Shared->Free.load()!=GpuSlots||State->Shared->CpuOccupancy.load()!=0||State->Shared->WriterActive.load()){RequestStop(Error.IsEmpty()?TEXT("Start requires exact validated idle ring and same source identity"):Error);return Json(State->Report);}
 State->RecordWall=FPlatformTime::Seconds();State->RecordWorld=State->World->GetTimeSeconds();State->Report->SetNumberField(TEXT("record_begin_world_seconds"),State->RecordWorld);State->Report->SetNumberField(TEXT("record_begin_wall_absolute"),State->RecordWall);State->Mode=TEXT("RECORDING");Persist();return Json(State->Report);
}
FString ULivingTownCapturePilotLibrary::ReadExistingGameViewportContinuousCapture(){using namespace Continuous003;if(!State)return TEXT("{\"status\":\"NO_CONTINUOUS_CAPTURE\"}");if(!State->Closed){DrainResults();StartWriter();QueuePump();}Persist();return Json(State->Report);}
FString ULivingTownCapturePilotLibrary::StopExistingGameViewportContinuousCapture(){using namespace Continuous003;if(!State)return TEXT("{\"status\":\"NO_CONTINUOUS_CAPTURE\"}");RequestStop(TEXT("Caller stopped before full15s completion"));return Json(State->Report);}
FString ULivingTownCapturePilotLibrary::CancelExistingGameViewportContinuousCapture(){using namespace Continuous003;if(!State)return TEXT("{\"status\":\"NO_CONTINUOUS_CAPTURE\"}");RequestStop(TEXT("Caller cancelled; raw retained and bounded drain required"));return Json(State->Report);}
