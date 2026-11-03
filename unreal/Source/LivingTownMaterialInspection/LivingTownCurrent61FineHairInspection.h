#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownCurrent61FineHairInspection.generated.h"
class USkeletalMesh;
// Exact FineTwoMap14400-face/61sourcejoint/UV1 scope; same qualified binary packet format, old APIs unchanged.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownCurrent61FineHairInspection final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|FineHairInspection")
    static FString CacheFineHairMeshDescription(USkeletalMesh* Mesh,const FString& ExpectedPackageSha256);
    UFUNCTION(BlueprintCallable, Category="LivingTown|FineHairInspection")
    static FString ExportFineHairRestAsset(USkeletalMesh* Mesh,const FString& ExpectedPackageSha256,const FString& RelativeOutputDirectory);
};
