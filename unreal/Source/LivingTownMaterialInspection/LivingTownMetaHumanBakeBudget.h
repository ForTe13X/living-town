#pragma once

#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownMetaHumanBakeBudget.generated.h"

/** Typed Editor bridge for assembly settings whose enums are not exported to Python. */
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownMetaHumanBakeBudget : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|MetaHuman")
    static FString InspectPipeline(UObject* Pipeline);

    /** Changes only five measured oversized outputs, on an owned transient High pipeline. */
    UFUNCTION(BlueprintCallable, Category="LivingTown|MetaHuman")
    static FString Configure2KOutputs(UObject* Pipeline);

    /** Native parameters keep PipelineOverride protected from Python property writes. */
    UFUNCTION(BlueprintCallable, Category="LivingTown|MetaHuman")
    static FString BuildConfiguredHigh(UObject* Character, UObject* Pipeline, const FString& AssemblyRoot, const FString& CommonRoot);
};
