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

    // Read-only raw export of exactly SM_Chair and SM_Table, in either order.
    // C++ ABI is bool + two FString outs; stock Python packs tuple2 on true, None on false.
    UFUNCTION(BlueprintCallable,Category="LivingTown|CafeFurnitureReadback")
    static bool ExportCafeFurnitureMeshes(const TArray<FString>& AssetPaths,const FString& RelativeOutputDirectory,
        FString& ReceiptJson,FString& Error);

};
