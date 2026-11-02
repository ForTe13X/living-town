#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "LivingTownFullTownData.h"
#include "LivingTownFullTownDriver.generated.h"

// Serialized opt-in actor. Startup is owned by OnWorldBeginPlay, never actor order.
UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownFullTownDriver final : public AActor
{
    GENERATED_BODY()
public:
    ALivingTownFullTownDriver();
    UPROPERTY(EditInstanceOnly,Category="Full-town subset") bool bEnableIntegrationSubset = false;
    UPROPERTY(EditInstanceOnly,Category="Full-town subset") TSoftObjectPtr<ULivingTownFullTownData> Manifest;
    UPROPERTY(EditInstanceOnly,Category="Full-town subset") int64 ManifestSourceBytes = 0;
    UPROPERTY(EditInstanceOnly,Category="Full-town subset") FString ManifestSourceSha256;
    UPROPERTY(EditInstanceOnly,Category="Full-town subset") double LoadRadiusCm = 8000;
    UPROPERTY(EditInstanceOnly,Category="Full-town subset") double UnloadRadiusCm = 10000;
    UPROPERTY(EditInstanceOnly,Category="Full-town subset") double StartupDeadlineSeconds = 360;
    UPROPERTY(EditInstanceOnly,Category="Full-town subset") double UnitDeadlineSeconds = 180;
    UPROPERTY(EditInstanceOnly,Category="Full-town subset") double ValidationTimeTargetMs = 1;
    UPROPERTY(EditInstanceOnly,Category="Full-town subset") int32 ComponentsPerFrame = 8;
    UPROPERTY(EditInstanceOnly,Category="Full-town subset") int32 InstancesPerFrame = 256;
    bool IsIdentityPlacement() const;
protected:
    virtual void BeginPlay() override;
    virtual void EndPlay(EEndPlayReason::Type Reason) override;
};
