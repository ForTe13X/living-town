#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownHeadCapMaterialPreparation.generated.h"
class UMaterial;

// Explicit resource initialization is separate from the pure readiness reader.
// These Editor-only methods are restricted to the nine saved current61 materials.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownHeadCapMaterialPreparation final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|Current61MaterialPreparation")
    static FString PrepareSavedCapMaterialResource(UMaterial* Material, const FString& ExpectedPackageSha256);
    UFUNCTION(BlueprintCallable, Category="LivingTown|Current61MaterialPreparation")
    static FString ReadSavedCapMaterialResource(UMaterial* Material, const FString& ExpectedPackageSha256);
};
