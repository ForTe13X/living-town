#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownCurrent61HairInspection.generated.h"
class USkeletalMesh;
class UMaterial;

// Editor-only exact owned hair asset. Cache staging is explicit and separate
// from raw readback. Neither method imports, builds, saves or spawns anything.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownCurrent61HairInspection final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|Current61HairInspection")
    static FString CacheCurrent61HairMeshDescription(USkeletalMesh* Mesh, const FString& ExpectedPackageSha256);
    UFUNCTION(BlueprintCallable, Category="LivingTown|Current61HairInspection")
    static FString ExportCurrent61HairRestAsset(USkeletalMesh* Mesh, const FString& ExpectedPackageSha256, const FString& RelativeOutputDirectory);
    UFUNCTION(BlueprintCallable, Category="LivingTown|Current61HairInspection")
    static FString ReadCurrent61HairMaterialReadiness(UMaterial* Material, const FString& ExpectedPackageSha256, bool bDefaultLitControl);
};
