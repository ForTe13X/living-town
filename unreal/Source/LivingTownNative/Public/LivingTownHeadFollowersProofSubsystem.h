#pragma once
#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "LivingTownHeadFollowersProofSubsystem.generated.h"

class AActor;
class USkeletalMeshComponent;
class UAnimSequence;
class UCameraComponent;
class FJsonObject;
class FJsonValue;

// Development proof only. No object is created without the explicit owned-run
// flag. Existing character, head binding and Configure contracts are unchanged.
UCLASS(Transient, NotBlueprintable)
class LIVINGTOWNNATIVE_API ULivingTownHeadFollowersProofSubsystem final : public UWorldSubsystem
{
    GENERATED_BODY()
public:
    virtual bool ShouldCreateSubsystem(UObject* Outer) const override;
    virtual bool DoesSupportWorldType(EWorldType::Type Type) const override;
    virtual void OnWorldBeginPlay(UWorld& World) override;
    virtual void OnWorldEndPlay(UWorld& World) override;
    virtual void Deinitialize() override;
private:
    void Observe(UWorld* World, ELevelTick Tick, float DeltaSeconds);
    void ShotProcessed();
    void Finish(const FString& Reason, bool bCaptured);
    bool Setup();
    bool OwnScreenMaterialsReady() const;
    TSharedPtr<FJsonObject> Sample();
    void Cleanup();
    UPROPERTY(Transient) TObjectPtr<AActor> Owner;
    UPROPERTY(Transient) TObjectPtr<USkeletalMeshComponent> Body;
    UPROPERTY(Transient) TObjectPtr<USkeletalMeshComponent> Hair;
    UPROPERTY(Transient) TObjectPtr<USkeletalMeshComponent> Cap;
    UPROPERTY(Transient) TObjectPtr<UAnimSequence> Idle;
    UPROPERTY(Transient) TObjectPtr<UAnimSequence> Walk;
    UPROPERTY(Transient) TObjectPtr<UCameraComponent> Camera;
    FDelegateHandle PostTick, ShotComplete;
    FString Root, ManifestHash;
    TSharedPtr<FJsonObject> Config;
    TArray<TSharedPtr<FJsonValue>> Samples;
    TArray<TSharedPtr<FJsonValue>> Screenshots;
    TSharedPtr<FJsonObject> PendingShotRecord;
    TArray<int32> HairVertices, CapVertices;
    double Started=0, LastSample=-1;
    int32 Phase=0, PhaseSamples=0, WaitFrames=0, PendingShot=INDEX_NONE;
    bool bTerminal=false, bConfigured=false, bOwnedOutput=false, bShotProcessed=false, bAnimationStarted=false;
    bool bDiagnosticArtPreview=false, bCapColdBound=false;
};
