#include "LivingTownViewportCsvSubsystem.h"

#include "CoreGlobals.h"
#include "Camera/PlayerCameraManager.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/Pawn.h"
#include "Engine/GameViewportClient.h"
#include "Engine/World.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "ProfilingDebugging/CsvProfiler.h"
#include "Stats/Stats.h"
#include "UObject/Package.h"

namespace
{
bool MatchesOwnedViewportCsvScope(const UWorld* World)
{
    FString Map;
    return World != nullptr
        && World->WorldType == EWorldType::Game
        && FParse::Param(FCommandLine::Get(), TEXT("LivingTownViewportCsv"))
        && FParse::Value(FCommandLine::Get(), TEXT("LivingTownViewportCsvMap="), Map)
        && Map.StartsWith(TEXT("/Game/LivingTown_UEPilot/"))
        && World->GetOutermost()->GetName() == Map;
}
}

bool ULivingTownViewportCsvSubsystem::ShouldCreateSubsystem(UObject* Outer) const
{
#if CSV_PROFILER && !CSV_PROFILER_MINIMAL
    return MatchesOwnedViewportCsvScope(Cast<UWorld>(Outer))
        && Super::ShouldCreateSubsystem(Outer);
#else
    (void)Outer;
    return false;
#endif
}

bool ULivingTownViewportCsvSubsystem::DoesSupportWorldType(EWorldType::Type WorldType) const
{
    return WorldType == EWorldType::Game;
}

void ULivingTownViewportCsvSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
    Super::Initialize(Collection);
    bOwnedScope = MatchesOwnedViewportCsvScope(GetWorld());
}

void ULivingTownViewportCsvSubsystem::Deinitialize()
{
    bOwnedScope = false;
    Super::Deinitialize(); // Cancels the normal world-subsystem tick registration.
}

void ULivingTownViewportCsvSubsystem::Tick(float DeltaTime)
{
    Super::Tick(DeltaTime);
#if CSV_PROFILER && !CSV_PROFILER_MINIMAL
    if (!bOwnedScope || !MatchesOwnedViewportCsvScope(GetWorld()) || !FCsvProfiler::IsCapturing())
    {
        return;
    }
    check(IsInGameThread());

    FVector2D Size = FVector2D::ZeroVector;
    if (const UGameViewportClient* Client = GetWorld()->GetGameViewport())
    {
        Client->GetViewportSize(Size); // Native FViewport::GetSizeXY, no HWND/DPI conversion.
    }

    // Avoid the installed CSV double overload's float cast. This bounded fresh-process
    // benchmark uses exact integer stats; an excessive counter emits a refusing sentinel.
    constexpr uint64 MaximumExactFrame = (1ULL << 24) - 1;
    const int32 Frame = GFrameCounter <= MaximumExactFrame
        ? static_cast<int32>(GFrameCounter) : -1;
    CSV_CUSTOM_STAT_GLOBAL(LTViewportWidth, static_cast<int32>(Size.X), ECsvCustomStatOp::Set);
    CSV_CUSTOM_STAT_GLOBAL(LTViewportHeight, static_cast<int32>(Size.Y), ECsvCustomStatOp::Set);
    CSV_CUSTOM_STAT_GLOBAL(LTViewportGTFrame, Frame, ECsvCustomStatOp::Set);
    // Accumulate exposes duplicate ticks. Missing ticks produce zero/empty CSV rows.
    CSV_CUSTOM_STAT_GLOBAL(LTViewportSamples, int32(1), ECsvCustomStatOp::Accumulate);

    // Observe the normal world/player camera once per natural subsystem tick.
    // These diagnostics never select a target, move a pawn or update a camera.
    APlayerController* PC = GetWorld()->GetFirstPlayerController();
    const bool bControllerValid = IsValid(PC) && PC->IsLocalController();
    APawn* Pawn = bControllerValid ? PC->GetPawn() : nullptr;
    const bool bPawnValid = IsValid(Pawn) && Pawn->GetController() == PC;
    APlayerCameraManager* Manager = bControllerValid ? PC->PlayerCameraManager.Get() : nullptr;
    AActor* ViewTarget = bControllerValid ? PC->GetViewTarget() : nullptr;
    const bool bTargetIsPawn = bPawnValid && ViewTarget == Pawn;
    const bool bManagerTargetIsPawn = bPawnValid && IsValid(Manager) && Manager->GetViewTarget() == Pawn;
    FVector Location = FVector::ZeroVector;
    FRotator Rotation = FRotator::ZeroRotator;
    if (bControllerValid)
    {
        PC->GetPlayerViewPoint(Location, Rotation);
    }
    const float FOV = IsValid(Manager) ? Manager->GetFOVAngle() : -1.f;
    const bool bFiniteView = bControllerValid && IsValid(Manager)
        && FMath::IsFinite(Location.X) && FMath::IsFinite(Location.Y) && FMath::IsFinite(Location.Z)
        && FMath::IsFinite(Rotation.Pitch) && FMath::IsFinite(Rotation.Yaw) && FMath::IsFinite(Rotation.Roll)
        && FMath::IsFinite(FOV) && FOV > 0.f && FOV < 180.f;
    const int32 AutoManage = bControllerValid ? int32(PC->bAutoManageActiveCameraTarget) : -1;
    CSV_CUSTOM_STAT_GLOBAL(LTPlayerControllerValid, int32(bControllerValid), ECsvCustomStatOp::Set);
    CSV_CUSTOM_STAT_GLOBAL(LTPlayerPawnValid, int32(bPawnValid), ECsvCustomStatOp::Set);
    CSV_CUSTOM_STAT_GLOBAL(LTPlayerViewTargetIsPawn, int32(bTargetIsPawn), ECsvCustomStatOp::Set);
    CSV_CUSTOM_STAT_GLOBAL(LTPlayerManagerTargetIsPawn, int32(bManagerTargetIsPawn), ECsvCustomStatOp::Set);
    CSV_CUSTOM_STAT_GLOBAL(LTPlayerAutoManage, AutoManage, ECsvCustomStatOp::Set);
    CSV_CUSTOM_STAT_GLOBAL(LTPlayerViewFinite, int32(bFiniteView), ECsvCustomStatOp::Set);
    // CSV native scalar storage is float32; the first-positive log retains
    // round-trip precision coordinates. Flags and bounded GT frame are integers.
    CSV_CUSTOM_STAT_GLOBAL(LTPlayerViewX, static_cast<float>(Location.X), ECsvCustomStatOp::Set);
    CSV_CUSTOM_STAT_GLOBAL(LTPlayerViewY, static_cast<float>(Location.Y), ECsvCustomStatOp::Set);
    CSV_CUSTOM_STAT_GLOBAL(LTPlayerViewZ, static_cast<float>(Location.Z), ECsvCustomStatOp::Set);
    CSV_CUSTOM_STAT_GLOBAL(LTPlayerViewPitch, static_cast<float>(Rotation.Pitch), ECsvCustomStatOp::Set);
    CSV_CUSTOM_STAT_GLOBAL(LTPlayerViewYaw, static_cast<float>(Rotation.Yaw), ECsvCustomStatOp::Set);
    CSV_CUSTOM_STAT_GLOBAL(LTPlayerViewRoll, static_cast<float>(Rotation.Roll), ECsvCustomStatOp::Set);
    CSV_CUSTOM_STAT_GLOBAL(LTPlayerViewFOV, FOV, ECsvCustomStatOp::Set);
    CSV_CUSTOM_STAT_GLOBAL(LTPlayerViewGTFrame, Frame, ECsvCustomStatOp::Set);
    CSV_CUSTOM_STAT_GLOBAL(LTPlayerViewSamples, int32(1), ECsvCustomStatOp::Accumulate);
    if (!bLoggedPositivePlayerView && Frame >= 0 && bPawnValid && bTargetIsPawn
        && bManagerTargetIsPawn && bFiniteView && AutoManage == 0)
    {
        bLoggedPositivePlayerView = true;
        UE_LOG(LogTemp, Display, TEXT("LT_NATIVE_PLAYER_VIEW_POSITIVE map=%s frame=%d controller=%s controller_class=%s pawn=%s pawn_class=%s view_target=%s auto_manage=%d xyz=(%.17g,%.17g,%.17g) rotation=(%.17g,%.17g,%.17g) fov=%.9g"),
            *GetWorld()->GetOutermost()->GetName(), Frame, *PC->GetPathName(), *PC->GetClass()->GetPathName(),
            *Pawn->GetPathName(), *Pawn->GetClass()->GetPathName(), *ViewTarget->GetPathName(), AutoManage,
            Location.X, Location.Y, Location.Z, Rotation.Pitch, Rotation.Yaw, Rotation.Roll, double(FOV));
    }

#endif
}

TStatId ULivingTownViewportCsvSubsystem::GetStatId() const
{
    RETURN_QUICK_DECLARE_CYCLE_STAT(ULivingTownViewportCsvSubsystem, STATGROUP_Tickables);
}
