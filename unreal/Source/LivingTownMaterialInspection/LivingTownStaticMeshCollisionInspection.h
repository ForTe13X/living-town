#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownStaticMeshCollisionInspection.generated.h"

class UStaticMesh;
class UStaticMeshComponent;
class UWorld;

// Editor inspection only. The caller owns the already-loaded asset/source binding.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownStaticMeshCollisionInspection final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|Collision Inspection")
    static FString ReadStaticMeshCollision(UStaticMesh* Mesh);

    // Already-loaded author components only; no body copy, state creation or writes.
    UFUNCTION(BlueprintCallable, Category="LivingTown|Collision Inspection")
    static FString ReadAuthorComponentCollisionResponses(const TArray<UStaticMeshComponent*>& Components);

    // Explicit already-loaded Editor/Inactive world scope, including private author maps.
    // ExpectedWorldPackage is the caller's declaration, not an ownership/source admission.
    // No loading, world switch, registration, physics creation, body copy or setters.
    UFUNCTION(BlueprintCallable, Category="LivingTown|Collision Inspection")
    static FString ReadOwnedWorldComponentCollisionResponses(UWorld* ExpectedWorld,
        const FString& ExpectedWorldPackage, const TArray<UStaticMeshComponent*>& Components);
};
