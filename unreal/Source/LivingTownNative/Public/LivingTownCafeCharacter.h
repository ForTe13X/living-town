#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "LivingTownCafeBinding.h"
#include "LivingTownCafeCharacter.generated.h"
class USpringArmComponent;
class UCameraComponent;
class UBlendSpace;

UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownCafeCharacter final : public ACharacter
{
    GENERATED_BODY()
public:
    ALivingTownCafeCharacter();
    bool ConfigureQualifiedBen(const FLivingTownCafeBinding& Binding,FString& Error);
    bool HasQualifiedVisual() const {return bVisualQualified;}
    FVector InteractionHand() const;
    virtual void Tick(float DeltaSeconds) override;
    virtual void SetupPlayerInputComponent(UInputComponent* Input) override;
private:
    UPROPERTY() TObjectPtr<USpringArmComponent> CameraArm;
    UPROPERTY() TObjectPtr<UCameraComponent> Camera;
    UPROPERTY() TObjectPtr<UBlendSpace> IdleWalk;
    FString UseSocket;
    bool bVisualQualified=false;
    void Forward(float Value);
    void Right(float Value);
    void Yaw(float Value);
    void Pitch(float Value);
};
