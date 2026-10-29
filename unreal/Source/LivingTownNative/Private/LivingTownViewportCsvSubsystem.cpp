#include "LivingTownViewportCsvSubsystem.h"

#include "CoreGlobals.h"
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
    if (!bOwnedScope || !FCsvProfiler::IsCapturing())
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
#endif
}

TStatId ULivingTownViewportCsvSubsystem::GetStatId() const
{
    RETURN_QUICK_DECLARE_CYCLE_STAT(ULivingTownViewportCsvSubsystem, STATGROUP_Tickables);
}
