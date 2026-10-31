#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownStaticMeshCollisionInspection.generated.h"

class UStaticMesh;

// Editor inspection only. The caller owns the already-loaded asset/source binding.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownStaticMeshCollisionInspection final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|Collision Inspection")
    static FString ReadStaticMeshCollision(UStaticMesh* Mesh);
};
