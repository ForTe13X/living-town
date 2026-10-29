#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownReserveLandcover.generated.h"

// Editor-only fixed006 replay and explicit profile-bound preview. No runtime painting, caller paths or asset saves.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownReserveLandcover final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|Reserve Landcover")
    static FString ApplyReserveLandcoverPreview();

    UFUNCTION(BlueprintCallable, Category="LivingTown|Reserve Landcover")
    static FString ReadReserveLandcoverPreview();

    // Explicit v2: fixed Config path + exact command-line profile SHA. No fallback to fixed006.
    UFUNCTION(BlueprintCallable, Category="LivingTown|Reserve Landcover")
    static FString ApplyReserveLandcoverProfilePreview();

    UFUNCTION(BlueprintCallable, Category="LivingTown|Reserve Landcover")
    static FString ReadReserveLandcoverProfilePreview();
};
