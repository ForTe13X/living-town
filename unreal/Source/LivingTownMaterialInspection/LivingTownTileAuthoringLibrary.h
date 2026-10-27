#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownTileAuthoringLibrary.generated.h"

class ULivingTownTileRootData;
class ULivingTownRenderUnitData;
class UWorld;

// New editor helper proposal. Requires its own successful future build; the
// already-qualified 9c2 runtime/editor DLL does not contain this class.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownTileAuthoringLibrary final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    // Objects must be newly created, unsaved assets at the exact frozen paths.
    // All qualifications and blocking collision remain false. No save occurs.
    UFUNCTION(BlueprintCallable, Category="LivingTown|Town Staging")
    static FString PopulateStagedTownAssets(ULivingTownTileRootData* Root,
        const TArray<ULivingTownRenderUnitData*>& Units,
        const FString& SourcePlanJson, const FString& NativeReceiptJson);

    UFUNCTION(BlueprintCallable, Category="LivingTown|Town Staging")
    static FString ReadStagedTownAssets(ULivingTownTileRootData* Root,
        const FString& SourcePlanJson);

    // One editor-only, noncolliding preview component per call. The Python
    // supervisor budgets calls and checks generation/world identity each tick.
    UFUNCTION(BlueprintCallable, Category="LivingTown|Town Staging")
    static FString AddDisabledPreviewEntry(UWorld* ReviewWorld,
        ULivingTownRenderUnitData* Unit, int32 EntryIndex);

    UFUNCTION(BlueprintCallable, Category="LivingTown|Town Staging")
    static FString ReadDisabledPreviewWorld(UWorld* ReviewWorld,
        ULivingTownTileRootData* Root);
};
