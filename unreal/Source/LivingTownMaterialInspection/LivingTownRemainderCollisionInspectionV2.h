#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownRemainderCollisionInspectionV2.generated.h"
class UStaticMesh;

// New-only exact twelve-asset source scope. Old generic/context/ground APIs unchanged.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownRemainderCollisionInspectionV2 final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    // Imported owned asset metadata before explicit owner configuration/save; no raw arrays.
    UFUNCTION(BlueprintCallable, Category="LivingTown|RemainderCollisionInspectionV2")
    static FString ReadRemainderConfigurationMetadataV2(UStaticMesh* Mesh);
    // Saved clean assets only, binary ID-aware MD/provider/Chaos arrays; no cook/repair/save.
    UFUNCTION(BlueprintCallable, Category="LivingTown|RemainderCollisionInspectionV2")
    static FString ExportRemainderCollisionMeshesV2(const TArray<FString>& AssetPaths,
        const FString& RelativeOutputDirectory);
};
