#pragma once
#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "LivingTownCafePlayerController.generated.h"
UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownCafePlayerController final : public APlayerController
{
    GENERATED_BODY()
public:
    ALivingTownCafePlayerController();
    virtual void SetupInputComponent()override;
    virtual void BeginPlay()override;
    const FString& GetOperationNotice()const{return OperationNotice;}
private:
    FString OperationNotice;
    void LeaseCafe();
    void EndLease();
    void SaveCafe();
    void LoadCafe();
};
