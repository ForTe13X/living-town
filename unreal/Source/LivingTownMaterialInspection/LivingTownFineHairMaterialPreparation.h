#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownFineHairMaterialPreparation.generated.h"
class UMaterial;

// Explicit resource initialization is separate from the pure readiness reader.
// Editor-only: exactly the new saved DefaultLit FineTwoMap surface-card material.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownFineHairMaterialPreparation final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|Current61MaterialPreparation")
    static FString PrepareSavedFineHairMaterialResource(UMaterial* Material, const FString& ExpectedPackageSha256);
    UFUNCTION(BlueprintCallable, Category="LivingTown|Current61MaterialPreparation")
    static FString ReadSavedFineHairMaterialResource(UMaterial* Material, const FString& ExpectedPackageSha256);
};
