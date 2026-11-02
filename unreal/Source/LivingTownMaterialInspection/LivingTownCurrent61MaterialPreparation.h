#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownCurrent61MaterialPreparation.generated.h"
class UMaterial;

// Explicit resource initialization is separate from the pure readiness reader.
// These Editor-only methods are restricted to the nine saved current61 materials.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownCurrent61MaterialPreparation final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|Current61MaterialPreparation")
    static FString PrepareCurrent61SavedMaterialResource(UMaterial* Material, const FString& ExpectedPackageSha256);
    UFUNCTION(BlueprintCallable, Category="LivingTown|Current61MaterialPreparation")
    static FString ReadCurrent61SavedMaterialResource(UMaterial* Material, const FString& ExpectedPackageSha256);
};
