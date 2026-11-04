#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownOriginalWorkerPreview.generated.h"

// Editor-only ordinary PIE/window adapter. It grants no asset/gameplay qualification.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownOriginalWorkerPreview final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    // One request per Editor process; no inherited PIE, camera placement or CDO change.
    UFUNCTION(BlueprintCallable, Category="LivingTown|Original Worker Preview")
    static FString RequestOrdinaryPreview(int32 ViewportWidth, int32 ViewportHeight);

    // Poll on later natural Slate frames. Restores/sizes only this session's floating window.
    // READY requires two distinct real-frame PC/scene viewport witnesses at the exact size.
    UFUNCTION(BlueprintCallable, Category="LivingTown|Original Worker Preview")
    static FString AdvanceOrdinaryPreview(const FString& ScopeToken);

    // No window operation. Rechecks the owned world/controller/pawn/window and exact size.
    UFUNCTION(BlueprintCallable, Category="LivingTown|Original Worker Preview")
    static FString InspectOrdinaryPreview(const FString& ScopeToken);
};
