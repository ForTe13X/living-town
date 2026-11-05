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

    // Passive native topology of the one existing Editor world/current viewport.
    // Callers bind their own expected world and on-disk package; this reports
    // loaded topology only and never authorizes an asset edit or save.
    UFUNCTION(BlueprintCallable, Category="LivingTown|Viewport Review")
    static FString ReadCurrentEditorWorldTopology();

    // Exact GCurrent client used by installed MCP CaptureViewport. Fixed Mid
    // camera; perspective/Lit/GameView off; real-time temporary override;
    // scene-driven exposure and standard atmosphere/lighting flags.
    UFUNCTION(BlueprintCallable, Category="LivingTown|Viewport Review")
    static FString ConfigureFixedMidViewport();

    // Exact current Entry editor viewport, reversible shared-owner scope.
    // Temporary true realtime override; no camera/FOV or persistent settings write.
    UFUNCTION(BlueprintCallable, Category="LivingTown|Viewport Review")
    static FString ConfigureWallLightingViewport();

    // Separate exact saved Mill Court B finish inspection map. Same reversible
    // shared-owner scope; never widens ConfigureWallLightingViewport's Entry guard.
    // Caller must release any capture camera lock before the common restore API.
    UFUNCTION(BlueprintCallable, Category="LivingTown|Viewport Review")
    static FString ConfigureBMaterialViewport();

    // ScopeToken must equal the sole active scope. Original client must still
    // be registered with the same viewport/world; never dereference a stale one.
    UFUNCTION(BlueprintCallable, Category="LivingTown|Viewport Review")
    static FString RestoreCurrentLevelViewport(const FString& ScopeToken);
};
