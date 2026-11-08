#pragma once

#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "Engine/LevelStreamingDynamic.h"
#include "LivingTownFullTownData.h"
#include "LivingTownFullTownStreamingSubsystem.generated.h"

class ALivingTownFullTownDriver;
class APlayerController;
class APawn;
class UStaticMeshComponent;
struct FStreamableHandle;

UCLASS()
class LIVINGTOWNNATIVE_API ULivingTownFullTownLevelStreaming final : public ULevelStreamingDynamic
{
    GENERATED_BODY()
public:
    virtual bool ShouldRequireFullVisibilityToRender() const override { return true; }
};

enum class ELivingTownFullTownPhase : uint8
{ LoadingHidden, ValidatingHidden, MakingVisible, Resident, MakingInvisible, Unloading, Removed };

// Delegates only record observations. All engine actions happen in the owned Tick.
UCLASS()
class LIVINGTOWNNATIVE_API ULivingTownFullTownTicket final : public UObject
{
    GENERATED_BODY()
public:
    uint64 Epoch=0, Token=0;
    int32 UnitIndex=INDEX_NONE, NextComponent=0, NextInstance=0;
    double StartedSeconds=0, RetireStartedSeconds=0;
    ELivingTownFullTownPhase Phase=ELivingTownFullTownPhase::LoadingHidden;
    bool bCancelled=false, bLoadedEvent=false, bShownEvent=false, bHiddenEvent=false, bUnloadedEvent=false;
    UPROPERTY(Transient) TObjectPtr<ULevelStreamingDynamic> Streaming;
    UPROPERTY(Transient) TArray<TObjectPtr<UStaticMeshComponent>> Components;
    TArray<int32> RoleIndices;
    bool Accepts(uint64 CurrentEpoch,uint64 CurrentToken) const;
    bool ReservesTransition() const;
    void MarkCancelled();
    UFUNCTION() void ObserveLoaded();
    UFUNCTION() void ObserveShown();
    UFUNCTION() void ObserveHidden();
    UFUNCTION() void ObserveUnloaded();
};

UCLASS()
class LIVINGTOWNNATIVE_API ULivingTownFullTownStreamingSubsystem final : public UTickableWorldSubsystem
{
    GENERATED_BODY()
public:
    virtual bool DoesSupportWorldType(EWorldType::Type Type) const override;
    virtual void OnWorldBeginPlay(UWorld& World) override;
    virtual void OnWorldEndPlay(UWorld& World) override;
    virtual void Tick(float DeltaSeconds) override;
    virtual bool IsTickable() const override;
    virtual TStatId GetStatId() const override;
    virtual void Deinitialize() override;
    bool WasArmedBeforeGameMode(const ALivingTownFullTownDriver* Candidate) const;
    // Synchronous opt-in pair around native Cafe/WorldV3 PC->Possess. The
    // engine ClientRestart resets input flags, so the old lock is balanced before
    // possession and a new owned contribution is acquired before input can tick.
    bool BeforeQualifiedPossess(APlayerController* Controller,FString& Error);
    bool AfterQualifiedPossess(APlayerController* Controller,APawn* Pawn,FString& Error);
    bool IsBootPossessionPending() const { return bArmed && !bReady; }
    void NotifyDriverEnding(const ALivingTownFullTownDriver* Candidate);
    // Live stop retains supporting resident levels and movement lock. World
    // teardown owns final level destruction; this is not a synchronous drain API.
    void RequestSafeStop();
    UFUNCTION(BlueprintPure,Category="Full-town diagnostics") FString GetStatusJson() const;
private:
    UPROPERTY(Transient) TObjectPtr<ULivingTownFullTownData> Data;
    UPROPERTY(Transient) TArray<TObjectPtr<ULivingTownFullTownTicket>> Tickets;
    TWeakObjectPtr<ALivingTownFullTownDriver> Driver;
    TWeakObjectPtr<APlayerController> LockedController;
    TSharedPtr<FStreamableHandle> ManifestHandle;
    TSet<int32> Wanted;
    uint64 Epoch=1, NextToken=1, Frames=0, ArmedFrame=0, ReadyFrame=0;
    double ArmedSeconds=0, ReadySeconds=0, RefreshAccumulator=0;
    double ManifestSourceHashSeconds=0, MapSourceHashSecondsTotal=0, MapSourceHashSecondsMax=0;
    double LastPreValidationSafetySeconds=0, LastTicketControlSeconds=0, LastValidationSeconds=0;
    int32 NextTicketCursor=0;
    int32 MapSourceHashCalls=0;
    int32 PeakTransitions=0, LoadsIssued=0, ShownUnits=0, Cancellations=0, PossessionRelocks=0;
    int32 FrameComponents=0, FrameInstances=0;
    bool bArmed=false, bMovementLockOwned=false, bManifestCompleted=false;
    bool bFailed=false, bStopping=false, bReady=false, bWorldEnding=false, bInTick=false;
    bool bPossessionWindow=false;
    bool bWorldV3Root=false;
    FString LastError;
    double StartupDeadline=360, UnitDeadline=180, LoadRadius=8000, UnloadRadius=10000, ValidationTargetMs=1;
    int32 ComponentBudget=8, InstanceBudget=256;
    void Fail(const FString& Error);
    bool LockMovementBeforeGameMode(UWorld& World,FString& Error);
    void ReleaseOwnedMovementLock();
    bool AcceptManifest(FString& Error);
    bool CafeStillQualified(bool& bWaiting,FString& Error) const;
    bool CurrentWorldAndOwner() const;
    ULivingTownFullTownTicket* FindTicket(int32 UnitIndex) const;
    int32 TransitionReservations() const;
    bool DependenciesResident(int32 UnitIndex) const;
    bool AllWantedResident() const;
    void RefreshWanted();
    bool CheckSourceMap(const FLivingTownFullTownUnit& Unit,FString& Error);
    void PumpLoads();
    void BeginDrain(ULivingTownFullTownTicket& Ticket);
    bool GatherHidden(ULivingTownFullTownTicket& Ticket,FString& Error);
    bool AdvanceValidation(ULivingTownFullTownTicket& Ticket,bool bRegistered,double Deadline,FString& Error);
    bool ValidateComponent(ULivingTownFullTownTicket& Ticket,int32 Index,bool bRegistered,FString& Error);
    bool ObserveFooting(int32* SimpleUnit=nullptr,int32* ComplexUnit=nullptr) const;
    bool MayRetire(int32 UnitIndex) const;
    void AdvanceTickets();
    void CancelHiddenWork();
    void TearDownOwnedReferences();
};
