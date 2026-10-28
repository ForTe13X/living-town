#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownMaterialInspection.generated.h"

// Editor-only readback. No setter, asset save or shader permutation update.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownMaterialInspection : public UBlueprintFunctionLibrary {
 GENERATED_BODY()
public:
 UFUNCTION(BlueprintPure, Category="LivingTown|Inspection")
 static UObject* ReadRerouteDeclaration(UObject* Expression);
 UFUNCTION(BlueprintPure, Category="LivingTown|Inspection")
 static FString ReadStaticSwitches(UObject* Material);
 UFUNCTION(BlueprintPure, Category="LivingTown|Inspection")
 static FString ReadFunctionInputDefault(UObject* Expression);
};
