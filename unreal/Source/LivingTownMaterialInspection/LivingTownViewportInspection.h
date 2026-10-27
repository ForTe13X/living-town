#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownViewportInspection.generated.h"

// Editor-only closed review scope. No world/asset save or global CVar mutation.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownViewportInspection final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|Viewport Review")
    static FString ReadCurrentLevelViewport();

    // Exact GCurrent client used by installed MCP CaptureViewport. Fixed Mid
    // camera; perspective/Lit/GameView off; real-time temporary override;
    // scene-driven exposure and standard atmosphere/lighting flags.
    UFUNCTION(BlueprintCallable, Category="LivingTown|Viewport Review")
    static FString ConfigureFixedMidViewport();

    // ScopeToken must equal the sole active scope. Original client must still
    // be registered with the same viewport/world; never dereference a stale one.
    UFUNCTION(BlueprintCallable, Category="LivingTown|Viewport Review")
    static FString RestoreCurrentLevelViewport(const FString& ScopeToken);
};
