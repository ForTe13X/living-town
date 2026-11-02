#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownCurrent61AvatarPreparation.generated.h"
class USkeletalMesh;
class UAnimSequence;
class USkeletalMeshComponent;

// Candidate authoring and current-pose observation are deliberately separate.
// No function qualifies a contact, advances a pose, or adopts a runtime binding.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownCurrent61AvatarPreparation final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable,Category="LivingTown|Current61Candidate")
    static FString CreateCandidateAvatar(USkeletalMesh* SourceMesh,UAnimSequence* Idle,UAnimSequence* Walk,double CandidateSpeedCmS,FTransform CandidatePalmLocal);

    // Outer root owner handles bounded readiness. This never waits/finishes compilation.
    UFUNCTION(BlueprintCallable,Category="LivingTown|Current61Candidate")
    static FString FinalizeCandidateAvatar(USkeletalMesh* Candidate);

    // Loads only the fixed candidate saved bulk into its existing transient wrapper.
    UFUNCTION(BlueprintCallable,Category="LivingTown|Current61Candidate")
    static FString CacheCandidateMeshDescription(USkeletalMesh* Candidate,const FString& ExpectedSavedCandidateSha256);

    // Exact saved clean candidate only; indices are render-LOD0 indices, not source vertices.
    UFUNCTION(BlueprintCallable,Category="LivingTown|Current61Candidate")
    static FString ReadCandidatePose(USkeletalMeshComponent* Component,const TArray<int32>& RenderVertexIndices,const FString& ExpectedSavedCandidateSha256);
};
