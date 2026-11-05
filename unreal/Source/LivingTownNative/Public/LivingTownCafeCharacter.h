#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "LivingTownCafeBinding.h"
#include "LivingTownCafeCharacter.generated.h"
class USpringArmComponent;
class UCameraComponent;
class UBlendSpace;
class USkeletalMeshComponent;
class ULivingTownOriginalWorkerAssembly;
class ULivingTownMetaHumanVisualAssembly;

UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownCafeCharacter final : public ACharacter
{
    GENERATED_BODY()
public:
    ALivingTownCafeCharacter();
    bool ConfigureQualifiedBen(const FLivingTownCafeBinding& Binding,FString& Error);
    bool HasQualifiedVisual() const;
    bool HasBoundCurrent61HeadParts() const { return bCurrent61HeadBound; }
    bool HasOriginalWorkerAssembly() const;
    bool HasMetaHumanVisual() const;
    USkeletalMeshComponent* GetVisualBody() const;
    FVector InteractionHand() const;
    virtual void PossessedBy(AController* NewController) override;
    virtual void UnPossessed() override;
    virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;
    virtual void TeleportSucceeded(bool bIsATest) override;
    virtual void Tick(float DeltaSeconds) override;
    virtual void SetupPlayerInputComponent(UInputComponent* Input) override;
private:
    UPROPERTY() TObjectPtr<USpringArmComponent> CameraArm;
    UPROPERTY() TObjectPtr<UCameraComponent> Camera;
    UPROPERTY() TObjectPtr<UBlendSpace> IdleWalk;
    UPROPERTY() TObjectPtr<USkeletalMeshComponent> HairCards;
    UPROPERTY() TObjectPtr<USkeletalMeshComponent> HairUnderlayer;
    UPROPERTY() TObjectPtr<ULivingTownOriginalWorkerAssembly> OriginalWorkerAssembly;
    UPROPERTY() TObjectPtr<ULivingTownMetaHumanVisualAssembly> MetaHumanVisual;
    bool bCurrent61HeadBound=false;
    FString UseSocket;
    bool bVisualQualified=false;
    bool bWorker110VisualQualified=false, bPossessedBonePolicyApplied=false;
    bool bCurrent61BakedVisualQualified=false;
    bool bOriginalWorkerRatePolicyApplied=false, PreviousOriginalWorkerUpdateRateOptimization=false;
    uint8 PreviousPossessedBonePolicy=0;
    void RestorePossessedBonePolicy();
    void UpdatePossessedBonePolicy();
    bool ConfigureOriginalWorkerBen(const FLivingTownCafeBinding& Binding,FString& Error);
    bool ConfigureMetaHumanBen(const FLivingTownCafeBinding& Binding,FString& Error);
    void Forward(float Value);
    void Right(float Value);
    void Yaw(float Value);
    void Pitch(float Value);
};
