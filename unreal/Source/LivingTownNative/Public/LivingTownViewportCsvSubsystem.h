#pragma once

#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "LivingTownViewportCsvSubsystem.generated.h"

// Explicit benchmark process/map scope only. No actor, asset or global delegate hook.
UCLASS(Transient)
class LIVINGTOWNNATIVE_API ULivingTownViewportCsvSubsystem final : public UTickableWorldSubsystem
{
    GENERATED_BODY()

public:
    virtual bool ShouldCreateSubsystem(UObject* Outer) const override;
    virtual bool DoesSupportWorldType(EWorldType::Type WorldType) const override;
    virtual void Initialize(FSubsystemCollectionBase& Collection) override;
    virtual void Deinitialize() override;
    virtual void Tick(float DeltaTime) override;
    virtual TStatId GetStatId() const override;

private:
    bool bOwnedScope = false;
    bool bLoggedPositivePlayerView = false;
};
