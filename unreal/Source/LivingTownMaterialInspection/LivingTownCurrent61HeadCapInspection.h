#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownCurrent61HeadCapInspection.generated.h"
class USkeletalMesh;
// Exact selected cap680-face scope; same qualified binary packet format, old APIs unchanged.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownCurrent61HeadCapInspection final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|HeadCapInspection")
    static FString CacheHeadCapMeshDescription(USkeletalMesh* Mesh,const FString& ExpectedPackageSha256);
    UFUNCTION(BlueprintCallable, Category="LivingTown|HeadCapInspection")
    static FString ExportHeadCapRestAsset(USkeletalMesh* Mesh,const FString& ExpectedPackageSha256,const FString& RelativeOutputDirectory);
};
