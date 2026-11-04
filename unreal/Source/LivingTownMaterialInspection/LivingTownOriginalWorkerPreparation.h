#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownOriginalWorkerPreparation.generated.h"

UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownOriginalWorkerPreparation final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    // Existing admitted packages must already be staged. No import, material,
    // geometry, source motion or runtime repair is performed by this producer.
    UFUNCTION(BlueprintCallable,Category="LivingTown|OriginalWorker")
    static FString PrepareOriginalWorkerBen(const FString& CalibrationPath,const FString& ReportDirectory);
};
