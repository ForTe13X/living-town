#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownCurrent61Inspection.generated.h"
class USkeletalMesh;

// Editor-only raw observation. No import, build, save, skinning or component creation.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownCurrent61Inspection final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|Current61Inspection")
    static FString ExportCurrent61RestAsset(USkeletalMesh* Mesh, const FString& RelativeOutputDirectory);
};
