#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownReserveLandscape.generated.h"

class UHierarchicalInstancedStaticMeshComponent;

// Editor-only fixed preview family. No caller paths, runtime enablement or asset saves.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownReserveLandscape final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|Reserve Landscape")
    static FString CreateReserveLandscapePreview();

    UFUNCTION(BlueprintCallable, Category="LivingTown|Reserve Landscape")
    static FString ReadReserveLandscapePreview();

    // Explicit bounded ConnectorA source; original fixed wrappers remain unchanged.
    UFUNCTION(BlueprintCallable, Category="LivingTown|Reserve Landscape")
    static FString CreateReserveConnectorLandscapePreview();

    UFUNCTION(BlueprintCallable, Category="LivingTown|Reserve Landscape")
    static FString ReadReserveConnectorLandscapePreview();

    UFUNCTION(BlueprintCallable, Category="LivingTown|Reserve Landscape")
    static FString ReadReserveHismComponent(UHierarchicalInstancedStaticMeshComponent* Component);
};
