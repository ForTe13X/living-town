#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "LivingTownTileData.h"
#include "LivingTownTileDriver.generated.h"
struct FStreamableHandle;

// Opt-in map actor only. No actor tick, global map/default change or resident spawn.
UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownTileDriver final : public AActor
{
    GENERATED_BODY()
public:
    ALivingTownTileDriver();
    UPROPERTY(EditInstanceOnly,Category="Qualified pilot") bool bEnableQualifiedPilot = false;
    UPROPERTY(EditInstanceOnly,Category="Qualified pilot") TSoftObjectPtr<ULivingTownTileRootData> RootAsset;
    UPROPERTY(EditInstanceOnly,Category="Qualified pilot") TObjectPtr<AActor> FocusActor;
    UPROPERTY(EditInstanceOnly,Category="Qualified pilot",meta=(ClampMin="0",ClampMax="20000")) double LoadRadiusCm = 8000;
    UPROPERTY(EditInstanceOnly,Category="Qualified pilot",meta=(ClampMin="0",ClampMax="20000")) double UnloadRadiusCm = 10000;
    UPROPERTY(EditInstanceOnly,Category="Qualified pilot",meta=(ClampMin="1",ClampMax="2")) int32 MaxConcurrentRequests = 2;
    UPROPERTY(EditInstanceOnly,Category="Qualified pilot",meta=(ClampMin="1",ClampMax="4")) int32 ComponentsPerFrame = 4;
    bool IsIdentityPlacement() const;
    AActor* ResolveFocus() const;
protected:
    virtual void BeginPlay() override;
    virtual void EndPlay(const EEndPlayReason::Type Reason) override;
private:
    UPROPERTY(Transient) TObjectPtr<ULivingTownTileRootData> LoadedRoot;
    TSharedPtr<FStreamableHandle> RootHandle;
    uint64 RootEpoch = 1;
};
