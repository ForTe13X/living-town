#pragma once

#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownHismInspection.generated.h"

class UHierarchicalInstancedStaticMeshComponent;

/** Bounded game-thread observation only; the caller binds scene/source authority. */
UCLASS()
class LIVINGTOWNNATIVE_API ULivingTownHismInspection : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|Inspection")
    static FString ReadHismComponent(UHierarchicalInstancedStaticMeshComponent* Component);
};
