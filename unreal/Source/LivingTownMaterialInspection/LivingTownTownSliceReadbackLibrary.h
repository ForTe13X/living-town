#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownTownSliceReadbackLibrary.generated.h"

// This module is Editor-only. No game runtime path writes mesh buffers/files.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownTownSliceReadbackLibrary final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable,Category="LivingTown|TownSliceReadback")
    static bool ExportTownSliceMeshes(const TArray<FString>& AssetPaths,const FString& RelativeOutputDirectory,
        FString& ReceiptJson,FString& Error);
};
