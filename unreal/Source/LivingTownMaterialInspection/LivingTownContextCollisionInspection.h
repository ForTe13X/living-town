#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownContextCollisionInspection.generated.h"

// Editor-only readback for one exact1463 cleaned-context source roster. No cook/repair/save.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownContextCollisionInspection final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|ContextCollisionInspection")
    static FString ExportContextCollisionMeshes(const TArray<FString>& AssetPaths,
        const FString& RelativeOutputDirectory);
};
