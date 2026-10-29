#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownRootCorrectionInspection.generated.h"
class USkeletalMeshComponent;
class UBlendSpace;
class UAnimSequence;

/** Owned transient editor fixture only; no asset authoring, saves or Game enablement. */
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownRootCorrectionInspection final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|RootCorrectionInspection")
    static FString ConfigureTemporaryComponent(USkeletalMeshComponent* Component, UBlendSpace* Motion,
        UAnimSequence* Idle, UAnimSequence* Walk, FVector ComponentDeltaCm, bool bEnableCorrection);
    /** Explicitly ticks at zero time once through the qualified reader, then reads that same evaluation's pre/post pose. */
    UFUNCTION(BlueprintCallable, Category="LivingTown|RootCorrectionInspection")
    static FString ReadCorrectionPoseProof(USkeletalMeshComponent* Component);
    /** Same explicit base evaluation plus its actual current public tick-record cache, not inferred from input speed. */
    UFUNCTION(BlueprintCallable, Category="LivingTown|RootCorrectionInspection")
    static FString ReadBaseSingleNodePoseProof(USkeletalMeshComponent* Component, UBlendSpace* ExpectedMotion);
    UFUNCTION(BlueprintCallable, Category="LivingTown|RootCorrectionInspection")
    static FString RunCorrectionGuardNegativeControls(UBlendSpace* Motion, UAnimSequence* Idle, UAnimSequence* Walk);
};
