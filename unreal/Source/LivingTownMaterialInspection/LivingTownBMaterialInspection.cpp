#include "LivingTownBMaterialInspection.h"
#include "Editor.h"
#include "LevelEditorViewport.h"
#include "Engine/World.h"
#include "Engine/Texture2D.h"
#include "Engine/TextureLODSettings.h"
#include "DeviceProfiles/DeviceProfile.h"
#include "DeviceProfiles/DeviceProfileManager.h"
#include "TextureResource.h"
#include "RenderingThread.h"
#include "RHI.h"
#include "RHIResources.h"
#include "DynamicRHI.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "HAL/PlatformTime.h"
#include "UObject/Package.h"
#include "UObject/StrongObjectPtr.h"
#include <atomic>

namespace LivingTownBMaterial
{
constexpr double DeadlineSeconds = 5.;
const TCHAR* InspectionWorld = TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_StaticFinish_v002/MillCourtB_StaticFinishInspection_v002.MillCourtB_StaticFinishInspection_v002");

struct FExpectedTexture
{
    const TCHAR* Path;
    int32 SourceWidth;
    int32 SourceHeight;
};
// These are the nine saved additions accepted with the static-finish B map.
// This new roster does not extend GroundIntakeInspection's exact12 terrain API.
const FExpectedTexture Roster[] = {
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_StaticFinish_v002/Textures/Plaster/BaseColor/T_Plaster_BaseColor.T_Plaster_BaseColor"),4096,4096},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_StaticFinish_v002/Textures/Plaster/Normal/T_Plaster_Normal.T_Plaster_Normal"),2048,2048},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_StaticFinish_v002/Textures/Plaster/Roughness/T_Plaster_Roughness.T_Plaster_Roughness"),2048,2048},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_StaticFinish_v002/Textures/OakJoinery/BaseColor/T_OakJoinery_BaseColor.T_OakJoinery_BaseColor"),4096,4096},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_StaticFinish_v002/Textures/OakJoinery/Normal/T_OakJoinery_Normal.T_OakJoinery_Normal"),2048,2048},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_StaticFinish_v002/Textures/OakJoinery/Roughness/T_OakJoinery_Roughness.T_OakJoinery_Roughness"),2048,2048},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_StaticFinish_v002/Textures/OakFloor/BaseColor/T_OakFloor_BaseColor.T_OakFloor_BaseColor"),2048,2048},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_StaticFinish_v002/Textures/OakFloor/Normal/T_OakFloor_Normal.T_OakFloor_Normal"),2048,2048},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_StaticFinish_v002/Textures/OakFloor/Roughness/T_OakFloor_Roughness.T_OakFloor_Roughness"),2048,2048},
};

FString Json(const TSharedRef<FJsonObject>& Object)
{
    FString Out;
    const auto Writer = TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Out);
    FJsonSerializer::Serialize(Object,Writer);
    return Out;
}

FString Reply(const TCHAR* Status,const TCHAR* Reason)
{
    const auto Out=MakeShared<FJsonObject>();
    Out->SetStringField(TEXT("schema"),TEXT("LivingTown.BMaterialTextureNativeScalars.v1"));
    Out->SetStringField(TEXT("status"),Status);
    Out->SetStringField(TEXT("reason"),Reason);
    Out->SetBoolField(TEXT("asset_saved_reimported_recompiled_or_stream_forced"),false);
    return Json(Out);
}

const FExpectedTexture* Expected(const FString& Path)
{
    for(const auto& Row:Roster)if(Path==Row.Path)return &Row;
    return nullptr;
}

UWorld* CurrentWorld()
{
    if(!IsInGameThread()||!GIsEditor||IsRunningCommandlet()||!GEditor||GEditor->PlayWorld)return nullptr;
    UWorld* World=GEditor->GetEditorWorldContext().World();
    auto* Client=GCurrentLevelEditingViewportClient;
    if(!IsValid(World)||World->WorldType!=EWorldType::Editor||World->IsGameWorld()||World->GetPathName()!=InspectionWorld||
        World->GetOutermost()->IsDirty()||!Client||!GEditor->GetLevelViewportClients().Contains(Client)||
        !Client->Viewport||Client->GetWorld()!=World)return nullptr;
    return World;
}

struct FRHIObserved
{
    // All scalar writes happen on RT before release-store; GT reads only after
    // acquire-load. The queued command owns this packet even after a timeout.
    std::atomic<bool> Done{false};
    bool Valid=false;
    int32 Width=0,Height=0,Mips=0,Format=0;
    uint64 Flags=0;
    double Finished=0.;
};

struct FPendingRead
{
    TStrongObjectPtr<UTexture2D> Texture;
    TWeakObjectPtr<UWorld> World;
    FLevelEditorViewportClient* Client=nullptr;
    FViewport* Viewport=nullptr;
    FTextureResource* Resource=nullptr;
    const FExpectedTexture* ExpectedTexture=nullptr;
    FString Token,SourceId;
    TSharedRef<FJsonObject> Before=MakeShared<FJsonObject>();
    TSharedRef<FRHIObserved,ESPMode::ThreadSafe> RHI=MakeShared<FRHIObserved,ESPMode::ThreadSafe>();
    double Started=0.;
    bool DeadlineExceeded=false;
};
TUniquePtr<FPendingRead> Pending;
bool SessionFailed=false;
TSet<FString> Completed;

// Call only after non-proxy, noncompiling, nonvirtual platform/resource checks.
// Do not call Blueprint_GetSizeX/Y: they may resolve the default/proxy texture.
TSharedRef<FJsonObject> Scalars(UTexture2D* Texture)
{
    const auto Out=MakeShared<FJsonObject>();
    Out->SetStringField(TEXT("asset"),Texture->GetPathName());
    Out->SetBoolField(TEXT("package_dirty"),Texture->GetOutermost()->IsDirty());
    Out->SetStringField(TEXT("source_GUID"),Texture->Source.GetId().ToString(EGuidFormats::Digits));
    Out->SetNumberField(TEXT("source_width"),Texture->Source.GetSizeX());
    Out->SetNumberField(TEXT("source_height"),Texture->Source.GetSizeY());
    Out->SetNumberField(TEXT("source_mips"),Texture->Source.GetNumMips());
    Out->SetNumberField(TEXT("source_format"),int32(Texture->Source.GetFormat()));
    Out->SetNumberField(TEXT("source_blocks"),Texture->Source.GetNumBlocks());
    Out->SetNumberField(TEXT("source_layers"),Texture->Source.GetNumLayers());
    const FTexturePlatformData* Platform=Texture->GetPlatformData();
    Out->SetNumberField(TEXT("platform_width"),Platform->SizeX);
    Out->SetNumberField(TEXT("platform_height"),Platform->SizeY);
    Out->SetNumberField(TEXT("platform_format"),int32(Platform->PixelFormat));
    Out->SetNumberField(TEXT("platform_mips"),Platform->Mips.Num());
    TArray<TSharedPtr<FJsonValue>> Mips;
    for(int32 Index=0;Index<Platform->Mips.Num();++Index)
    {
        const auto& Mip=Platform->Mips[Index];const auto Row=MakeShared<FJsonObject>();
        Row->SetNumberField(TEXT("index"),Index);Row->SetNumberField(TEXT("width"),Mip.SizeX);
        Row->SetNumberField(TEXT("height"),Mip.SizeY);Row->SetNumberField(TEXT("depth"),Mip.SizeZ);
        Mips.Add(MakeShared<FJsonValueObject>(Row));
    }
    Out->SetArrayField(TEXT("platform_mip_rows"),Mips);
    Out->SetNumberField(TEXT("resident_mips"),Texture->GetNumResidentMips());
    Out->SetNumberField(TEXT("allowed_mips"),Texture->GetNumMipsAllowed(false));
    const auto& State=Texture->GetStreamableResourceState();
    Out->SetBoolField(TEXT("streamable_resource_state_valid"),State.IsValid());
    if(State.IsValid())
    {
        Out->SetNumberField(TEXT("requested_mips"),State.NumRequestedLODs);
        Out->SetNumberField(TEXT("cached_resident_mips"),State.NumResidentLODs);
        Out->SetNumberField(TEXT("resource_max_mips"),State.MaxNumLODs);
        Out->SetNumberField(TEXT("resource_asset_LOD_bias"),State.AssetLODBias);
    }
    else
    {
        for(const TCHAR* Key:{TEXT("requested_mips"),TEXT("cached_resident_mips"),TEXT("resource_max_mips"),TEXT("resource_asset_LOD_bias")})
            Out->SetField(Key,MakeShared<FJsonValueNull>());
    }
#if !UE_BUILD_SHIPPING
    Out->SetNumberField(TEXT("cached_wanted_mips_debug_only"),Texture->GetCachedNumWantedLODs());
#else
    Out->SetField(TEXT("cached_wanted_mips_debug_only"),MakeShared<FJsonValueNull>());
#endif
    Out->SetStringField(TEXT("wanted_mips_scope"),TEXT("Streaming manager last-computed visualization cache; not a current demand/readiness guarantee; zero may mean not yet computed."));
    Out->SetBoolField(TEXT("pending_init_or_streaming"),Texture->HasPendingInitOrStreaming());
    Out->SetBoolField(TEXT("streaming_manager_registered"),Texture->IsStreamable());
    Out->SetBoolField(TEXT("resource_supports_streaming"),Texture->RenderResourceSupportsStreaming());
    Out->SetNumberField(TEXT("asset_max_texture_size"),Texture->MaxTextureSize);
    Out->SetNumberField(TEXT("LOD_bias"),Texture->LODBias);
    Out->SetNumberField(TEXT("texture_group"),int32(Texture->LODGroup));
    Out->SetBoolField(TEXT("sRGB"),Texture->SRGB);
    Out->SetNumberField(TEXT("compression_settings"),int32(Texture->CompressionSettings));
    Out->SetBoolField(TEXT("flip_green_channel"),Texture->bFlipGreenChannel);
    Out->SetBoolField(TEXT("virtual_streaming"),Texture->VirtualTextureStreaming);
    Out->SetBoolField(TEXT("never_stream"),Texture->NeverStream);
    Out->SetNumberField(TEXT("address_x"),int32(Texture->AddressX));
    Out->SetNumberField(TEXT("address_y"),int32(Texture->AddressY));
    Out->SetNumberField(TEXT("filter"),int32(Texture->Filter));
    Out->SetNumberField(TEXT("mip_gen_settings"),int32(Texture->MipGenSettings));
    const UDeviceProfile* Profile=UDeviceProfileManager::Get().GetActiveProfile();
    Out->SetStringField(TEXT("active_device_profile"),Profile?Profile->GetName():TEXT(""));
    if(Profile&&Profile->GetTextureLODSettings()&&int32(Texture->LODGroup)>=0&&int32(Texture->LODGroup)<TEXTUREGROUP_MAX)
    {
        const auto& Group=Profile->GetTextureLODSettings()->GetTextureLODGroup(Texture->LODGroup);
        Out->SetNumberField(TEXT("group_max_LOD_size"),Group.MaxLODSize);
        Out->SetNumberField(TEXT("group_max_LOD_mips"),Group.MaxLODMipCount);
        Out->SetNumberField(TEXT("group_LOD_bias"),Group.LODBias);
        Out->SetNumberField(TEXT("resolved_combined_LOD_bias"),Profile->GetTextureLODSettings()->CalculateLODBias(Texture));
    }
    else for(const TCHAR* Key:{TEXT("group_max_LOD_size"),TEXT("group_max_LOD_mips"),TEXT("group_LOD_bias"),TEXT("resolved_combined_LOD_bias")})
        Out->SetField(Key,MakeShared<FJsonValueNull>());
    Out->SetStringField(TEXT("native_RHI"),GDynamicRHI?FString(GDynamicRHI->GetName()):TEXT("NONE"));
    return Out;
}

bool CanRead(UTexture2D* Texture)
{
    if(Texture->IsCompiling()||!Texture->Source.IsValid()||Texture->VirtualTextureStreaming||
        !Texture->GetResource()||Texture->GetResource()->IsProxy())return false;
    const auto* Platform=Texture->GetPlatformData();
    return Platform&&Platform->SizeX>0&&Platform->SizeY>0&&Platform->Mips.Num()>0&&Platform->Mips.Num()<=15;
}
} // namespace LivingTownBMaterial

FString ULivingTownBMaterialInspection::BeginBTextureRead(UTexture2D* Texture)
{
    using namespace LivingTownBMaterial;
    UWorld* World=CurrentWorld();if(!World)return Reply(TEXT("REFUSED"),TEXT("exact_clean_B_saved_world_current_editor_viewport_no_PIE_required"));
    if(SessionFailed||Pending)return Reply(TEXT("REFUSED"),TEXT("one_pending_read_or_closed_failed_session"));
    if(!IsValid(Texture)||Texture->GetClass()!=UTexture2D::StaticClass()||Texture->IsTemplate()||
        Texture->HasAnyFlags(RF_NeedLoad|RF_NeedPostLoad|RF_NeedPostLoadSubobjects))
        return Reply(TEXT("REFUSED"),TEXT("already_loaded_exact_Texture2D_required_no_load"));
    const auto* Row=Expected(Texture->GetPathName());
    if(!Row||Completed.Contains(Texture->GetPathName()))return Reply(TEXT("REFUSED"),TEXT("exact_nine_B_finish_roster_once_each"));
    if(Texture->GetOutermost()->IsDirty())return Reply(TEXT("REFUSED"),TEXT("saved_clean_texture_required_no_save"));
    if(!CanRead(Texture))return Reply(TEXT("HOLD_RESOURCE_PENDING"),TEXT("compiling_invalid_source_proxy_virtual_or_platform_pending_no_wait"));
    if(Texture->Source.GetNumBlocks()!=1||Texture->Source.GetNumLayers()!=1)
        return Reply(TEXT("REFUSED"),TEXT("single_block_layer_source_required"));
    Pending=MakeUnique<FPendingRead>();Pending->Texture.Reset(Texture);Pending->World=World;
    Pending->Client=GCurrentLevelEditingViewportClient;Pending->Viewport=Pending->Client->Viewport;
    Pending->Resource=Texture->GetResource();Pending->ExpectedTexture=Row;
    Pending->SourceId=Texture->Source.GetId().ToString(EGuidFormats::Digits);
    Pending->Before=Scalars(Texture);Pending->Token=FGuid::NewGuid().ToString(EGuidFormats::Digits);
    Pending->Started=FPlatformTime::Seconds();
    const auto Shared=Pending->RHI;FTextureResource* Resource=Pending->Resource;
    // GT owns a strong UObject until Done is acquired on GT, including timeout.
    // Resource release/replacement initiated later on GT queues behind this
    // command. RT acquires its own RHI ref before reading the descriptor. No
    // UObject or GT platform data is dereferenced by the queued render command.
    ENQUEUE_RENDER_COMMAND(LivingTownBTextureScalars)([Shared,Resource](FRHICommandListImmediate&)
    {
        FTextureRHIRef Hold=Resource?Resource->TextureRHI:FTextureRHIRef();
        FRHITexture* Native=Hold.IsValid()?Hold->GetTexture2D():nullptr;
        if(Native)
        {
            const FRHITextureDesc Desc=Native->GetDesc();Shared->Valid=true;
            Shared->Width=Desc.Extent.X;Shared->Height=Desc.Extent.Y;
            Shared->Mips=Desc.NumMips;Shared->Format=int32(Desc.Format);Shared->Flags=uint64(Desc.Flags);
        }
        Shared->Finished=FPlatformTime::Seconds();Shared->Done.store(true,std::memory_order_release);
    });
    const auto Out=MakeShared<FJsonObject>();Out->SetStringField(TEXT("schema"),TEXT("LivingTown.BMaterialTextureNativeScalars.v1"));
    Out->SetStringField(TEXT("status"),TEXT("PENDING_RENDER_THREAD_SCALARS"));Out->SetStringField(TEXT("token"),Pending->Token);
    Out->SetObjectField(TEXT("before"),Pending->Before);Out->SetNumberField(TEXT("deadline_seconds"),DeadlineSeconds);
    Out->SetBoolField(TEXT("flush_wait_or_force_stream_called"),false);return Json(Out);
}

FString ULivingTownBMaterialInspection::PollBTextureRead(const FString& Token)
{
    using namespace LivingTownBMaterial;
    if(!IsInGameThread()||!GIsEditor||IsRunningCommandlet()||!Pending||Token!=Pending->Token)
        return Reply(TEXT("REFUSED"),TEXT("exact_pending_token_Editor_game_thread_required"));
    const double Now=FPlatformTime::Seconds();
    if(!Pending->RHI->Done.load(std::memory_order_acquire))
    {
        if(Now-Pending->Started<=DeadlineSeconds)return Reply(TEXT("PENDING_RENDER_THREAD_SCALARS"),TEXT("not_ready_no_wait"));
        // Keep both strong Texture ownership and packet until RT completes. A
        // terminal timeout never permits another request in this Editor process.
        Pending->DeadlineExceeded=true;SessionFailed=true;
        return Reply(TEXT("HOLD_RESOURCE_PENDING"),TEXT("render_thread_deadline_owner_retained_until_completion_no_retry"));
    }
    auto Job=MoveTemp(Pending);UTexture2D* Texture=Job->Texture.Get();
    const auto Out=MakeShared<FJsonObject>();Out->SetStringField(TEXT("schema"),TEXT("LivingTown.BMaterialTextureNativeScalars.v1"));
    Out->SetStringField(TEXT("token"),Job->Token);Out->SetObjectField(TEXT("before"),Job->Before);
    Out->SetBoolField(TEXT("asset_saved_reimported_recompiled_or_stream_forced"),false);
    Out->SetBoolField(TEXT("GPU_texels_sampling_LOD_or_appearance_qualified"),false);
    const auto RHI=MakeShared<FJsonObject>();RHI->SetBoolField(TEXT("valid"),Job->RHI->Valid);
    if(Job->RHI->Valid)
    {
        RHI->SetNumberField(TEXT("extent_x"),Job->RHI->Width);RHI->SetNumberField(TEXT("extent_y"),Job->RHI->Height);
        RHI->SetNumberField(TEXT("mips"),Job->RHI->Mips);RHI->SetNumberField(TEXT("format"),Job->RHI->Format);
        RHI->SetStringField(TEXT("flags_u64_decimal"),LexToString(Job->RHI->Flags));
    }
    else for(const TCHAR* Key:{TEXT("extent_x"),TEXT("extent_y"),TEXT("mips"),TEXT("format"),TEXT("flags_u64_decimal")})
        RHI->SetField(Key,MakeShared<FJsonValueNull>());
    RHI->SetNumberField(TEXT("request_to_RT_seconds"),Job->RHI->Finished-Job->Started);Out->SetObjectField(TEXT("render_thread_RHI"),RHI);
    UWorld* World=CurrentWorld();
    if(!World||World!=Job->World.Get()||GCurrentLevelEditingViewportClient!=Job->Client||
        GCurrentLevelEditingViewportClient->Viewport!=Job->Viewport||!IsValid(Texture)||!CanRead(Texture)||
        Texture->GetResource()!=Job->Resource||Texture->Source.GetId().ToString(EGuidFormats::Digits)!=Job->SourceId||Texture->GetOutermost()->IsDirty())
    {
        SessionFailed=true;Out->SetStringField(TEXT("status"),TEXT("HOLD_WORLD_OR_TEXTURE_RESOURCE_CHANGED"));return Json(Out);
    }
    const auto After=Scalars(Texture);Out->SetObjectField(TEXT("after"),After);
    const auto* Platform=Texture->GetPlatformData();const auto& Expected=*Job->ExpectedTexture;
    const bool SourceMatches=Texture->Source.GetSizeX()==Expected.SourceWidth&&Texture->Source.GetSizeY()==Expected.SourceHeight&&
        Texture->Source.GetNumBlocks()==1&&Texture->Source.GetNumLayers()==1;
    // Compare source/settings/platform/residency independently of the debug
    // wanted cache, which can legitimately update between these two GT ticks.
    auto BeforeStable=MakeShared<FJsonObject>(*Job->Before);auto AfterStable=MakeShared<FJsonObject>(*After);
    BeforeStable->RemoveField(TEXT("cached_wanted_mips_debug_only"));AfterStable->RemoveField(TEXT("cached_wanted_mips_debug_only"));
    const bool Stable=Json(BeforeStable)==Json(AfterStable);
    const int32 Resident=Texture->GetNumResidentMips();const int32 First=Platform->Mips.Num()-Resident;
    bool RHIConsistent=Job->RHI->Valid&&Resident>0&&First>=0&&First<Platform->Mips.Num()&&
        Job->RHI->Mips==Resident&&Job->RHI->Format==int32(Platform->PixelFormat);
    if(RHIConsistent)RHIConsistent=Job->RHI->Width==Platform->Mips[First].SizeX&&Job->RHI->Height==Platform->Mips[First].SizeY;
    const bool Timely=!Job->DeadlineExceeded&&Job->RHI->Finished-Job->Started<=DeadlineSeconds&&Now-Job->Started<=DeadlineSeconds;
    Out->SetBoolField(TEXT("expected_source_dimensions_match"),SourceMatches);
    Out->SetBoolField(TEXT("stable_source_platform_settings_and_residency"),Stable);
    Out->SetBoolField(TEXT("RHI_matches_reported_resident_mips"),RHIConsistent);
    Out->SetBoolField(TEXT("fully_resident_within_current_asset_LOD_limits"),Stable&&RHIConsistent&&
        !Texture->HasPendingInitOrStreaming()&&Resident==Texture->GetNumMipsAllowed(false));
    Out->SetBoolField(TEXT("read_completed_within_deadline"),Timely);
    const bool Observed=SourceMatches&&Stable&&RHIConsistent&&Timely;
    Out->SetStringField(TEXT("status"),Observed?TEXT("READ_ONLY_B_TEXTURE_NATIVE_SCALARS_OBSERVED"):TEXT("HOLD_B_TEXTURE_STATE_NOT_STABLE_OR_EXPECTED"));
    if(Observed)Completed.Add(Texture->GetPathName());else SessionFailed=true;
    return Json(Out);
}
