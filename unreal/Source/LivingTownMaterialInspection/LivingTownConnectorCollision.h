#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownConnectorCollision.generated.h"

// Bounded Editor-only29-mesh collision candidate. No caller paths, scene merge or asset saves.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownConnectorCollision final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|Connector Collision")
    static FString BuildConnectorCollidersPreview();
    UFUNCTION(BlueprintCallable, Category="LivingTown|Connector Collision")
    static FString ReadConnectorCollidersPreview();
};
