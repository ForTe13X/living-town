#pragma once

#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownWestwoodMaterialLibrary.generated.h"

class UMaterial;

// Proposal only: these files require a new successful editor build before use.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownWestwoodMaterialLibrary final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|Westwood")
    static FString ReadWestwoodMaterial(UMaterial* Material);

    UFUNCTION(BlueprintCallable, Category="LivingTown|Westwood")
    static FString ClearWestwoodDerivedConstantOverrides(UMaterial* Material);
};
