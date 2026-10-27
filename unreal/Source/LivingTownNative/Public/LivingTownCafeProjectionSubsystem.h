#pragma once
#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "LivingTownLeaseSubsystem.h"
#include "LivingTownCafeBinding.h"
#include "LivingTownCafeProjectionSubsystem.generated.h"
class ALivingTownCafeVenue;
class ALivingTownCafeCharacter;

// Display-only cache; refreshed with existing10Hz/event presentation updates.
// No widget can write authority, assets, clock or spatial observations through it.
struct FLivingTownCafePresentation
{
    FString Resident;
    FString Stewardship;
    FString Offer;
    FString Prompt;
    TArray<FString> Feedback;
    bool bReady=false;
    bool bReachable=false;
};

UCLASS()
class LIVINGTOWNNATIVE_API ULivingTownCafeProjectionSubsystem final : public UTickableWorldSubsystem
{
    GENERATED_BODY()
public:
    virtual bool DoesSupportWorldType(EWorldType::Type Type)const override;
    virtual void Initialize(FSubsystemCollectionBase& Collection)override;
    virtual void Deinitialize()override;
    virtual void Tick(float DeltaSeconds)override;
    virtual TStatId GetStatId()const override;
    // Native authority setup only; not reflected as a widget/client command.
    bool PrepareQualifiedScene(const FString& BindingPath,FString& Error);
    bool AttachQualifiedPlayer(ALivingTownCafeCharacter* Player,FString& Error);
    const FLivingTownCafeBinding& GetBinding()const{return Binding;}
    bool IsScenePrepared()const{return bScenePrepared;}
    bool IsReady()const{return bReady;}
    const TArray<FString>& GetPresentationLines()const{return PresentationLines;}
    const FLivingTownCafePresentation& GetPresentation()const{return Presentation;}
    bool IsCounterAffordanceReachable()const{return bCachedReach;}
    FString GetStatus()const{return Status;}
    FLivingTownLeaseView GetLeaseView()const;
    int64 GetOfferFee()const{return OfferFee;}
    int64 GetOfferDurationTicks()const{return OfferDuration;}
    bool ObserveCounter(FLivingTownTrustedInteraction& Out,FString& Why)const;
    FLivingTownLeaseReceipt RequestAction(ELivingTownLeaseAction Action);
    bool SaveProjection(FString& OutJson,FString& Error)const;
    bool LoadProjection(const FString& Json,FString& Error);
    bool SaveSlot(FString& Error)const;
    bool LoadSlot(FString& Error);
private:
    FLivingTownCafeBinding Binding;
    UPROPERTY() TObjectPtr<ALivingTownCafeVenue> Venue;
    TWeakObjectPtr<ALivingTownCafeCharacter> Player;
    bool bScenePrepared=false;
    bool bReady=false;
    double TickRemainder=0;
    int64 OfferFee=0;
    int64 OfferDuration=0;
    float AffordanceAccumulator=0;
    bool bCachedReady=false;
    bool bCachedReach=false;
    FLivingTownLeaseView CachedLease;
    FString CachedStatus;
    TArray<FString> PresentationLines;
    FLivingTownCafePresentation Presentation;
    FString Status=TEXT("Café unavailable: source assets and physical calibration are required.");
    ULivingTownLeaseSubsystem* Lease()const;
    FString SlotPath()const;
    void RefreshPresentation(bool Force=false);
};
