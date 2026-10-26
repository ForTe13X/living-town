#pragma once
#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "LivingTownCafeGameMode.generated.h"
UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownCafeGameMode final : public AGameModeBase
{
    GENERATED_BODY()
public:
    ALivingTownCafeGameMode();
    virtual void StartPlay()override;
    virtual APawn* SpawnDefaultPawnAtTransform_Implementation(AController* Player,const FTransform& Transform)override;
    virtual void HandleStartingNewPlayer_Implementation(APlayerController* Player)override;
private:void StartQualifiedPlayer(APlayerController* Player);
};
