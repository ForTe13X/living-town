#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownAvatarPreparation.generated.h"
class USkeletalMesh;
class USkeletalMeshComponent;
class UAnimSequence;
class UBlendSpace;
class UMaterialInterface;

/** Editor-only owned avatar authoring and numeric readback. No runtime enablement. */
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownAvatarPreparation final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|OwnedAvatar")
    static FString AuthorCafeWorkerAvatar(USkeletalMesh* SourceMesh, UAnimSequence* Idle,
        UAnimSequence* Walk, UMaterialInterface* ReviewedMaterial, FVector PalmLocalCm);
    UFUNCTION(BlueprintPure, Category="LivingTown|OwnedAvatar")
    static FString ReadAvatarSnapshot(USkeletalMesh* Mesh, UBlendSpace* Motion);
    /** Explicitly evaluates an owned temporary component at its caller-set time; never a natural-gameplay claim. */
    UFUNCTION(BlueprintCallable, Category="LivingTown|OwnedAvatar")
    static FString ReadAvatarPose(USkeletalMeshComponent* Component);
};
