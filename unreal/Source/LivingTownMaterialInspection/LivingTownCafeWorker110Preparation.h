#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownCafeWorker110Preparation.generated.h"

// Fixed editor staging only. No runtime player, binding, physical or contact enablement.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownCafeWorker110Preparation final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|CafeWorker110Preparation")
    static FString BuildCafeWorker110Derivative();
    UFUNCTION(BlueprintCallable, Category="LivingTown|CafeWorker110Preparation")
    static FString ReadCafeWorker110Sampler();
};
