#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownCurrent61SourcePreparation.generated.h"

class USkeletalMesh;
class UAnimSequence;

// Narrow Editor-only cache staging and read-only import provenance for exact baked assets.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownCurrent61SourcePreparation final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|Current61SourcePreparation")
    static FString CacheCurrent61PbrMeshDescription(USkeletalMesh* Mesh);

    UFUNCTION(BlueprintCallable, Category="LivingTown|Current61SourcePreparation")
    static FString ReadCurrent61AnimationSourceName(UAnimSequence* Animation);
};
