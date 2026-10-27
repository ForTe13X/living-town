#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownCafeMotionPreparation.generated.h"
class UBlendSpace;

// Editor module only. Runtime characters validate existing interpolation and
// never call this derivative authoring API or mutate an imported source asset.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownCafeMotionPreparation final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintPure, Category="LivingTown|MotionPreparation")
    static FString ReadCafeMotionInterpolation(UBlendSpace* Motion);
    UFUNCTION(BlueprintCallable, Category="LivingTown|MotionPreparation")
    static FString BuildCafeMotionInterpolationDerivative(UBlendSpace* Source);
};
