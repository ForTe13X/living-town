#pragma once
#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "LivingTownCafeBinding.h"
#include "LivingTownCafePropertyV2Types.h"
#include "LivingTownCafeWorldV3Types.h"
#include "LivingTownCafeWorldV3Subsystem.generated.h"
class ALivingTownCafeVenue;
class ALivingTownCafeWorldV3Controller;
class ALivingTownCafeCharacter;
class ACharacter;
class UAnimationAsset;
class UAnimSequence;
class UAnimSingleNodeInstance;
class ULivingTownMetaHumanMealProducer;
struct FStreamableHandle;
UCLASS()
class LIVINGTOWNNATIVE_API ULivingTownCafeWorldV3Subsystem final : public UTickableWorldSubsystem {
    GENERATED_BODY()
public:
    ULivingTownCafeWorldV3Subsystem();
    virtual ~ULivingTownCafeWorldV3Subsystem()override;
    virtual bool ShouldCreateSubsystem(UObject* Outer)const override;
    virtual bool DoesSupportWorldType(EWorldType::Type Type)const override;
    virtual void Deinitialize()override;
    virtual void Tick(float DeltaSeconds)override;
    virtual TStatId GetStatId()const override;
    virtual bool IsTickableWhenPaused()const override{return true;}
    bool PrepareScenario(FString& Error);
    bool BindNativeSession(ALivingTownCafeWorldV3Controller* Controller,ACharacter* Pawn,FString& Error);
    void DetachNativeSession();
    bool IsPrepared()const{return bPrepared;}
    const FLivingTownCafeBinding& GetBinding()const{return Binding;}
    const FLivingTownCafeWorldView& GetPresentation()const{return Presentation;}
    FLivingTownCafeWorldReceipt SubmitMeal(const FLivingTownCafeMealCommand& Command);
    FLivingTownCafeWorldReceipt CancelMeal();
    FLivingTownCafeWorldReceipt SubmitProperty(const FLivingTownCafePropertyCommand& Command);
    FLivingTownCafeWorldReceipt SubmitRecurringLeaseOffer(const FString& RequestId);
    FLivingTownCafeWorldReceipt SubmitLeaseAgreement(const FString& RequestId,bool bRecurring,int64 ObservedOfferRevision,int64 ObservedTitleRevision);
    bool SaveSlot(FString& Error,FString* SavedSha256=nullptr)const;
    bool LoadSlot(FString& Error);
    bool EncodeJournal(FString& Json,FString& Error)const;
    bool LoadJournal(const FString& Json,FString& Error);
    // Explicit migration only; ordinary loading accepts native/portable V6.
    bool ImportLegacyV5Journal(const FString& Json,FString& Error);
    bool ImportLegacyV5Slot(FString& Error);
    bool ImportLegacyV4Journal(const FString& Json,FString& Error);
    bool ImportLegacyV4Slot(FString& Error);
private:
#if WITH_DEV_AUTOMATION_TESTS
    friend struct FWorldV3MealProviderLifecycleTestAccess; // Read-only native test snapshots.
#endif
    struct FState;
    struct FStateDeleter{void operator()(FState* Pointer)const;};
    TUniquePtr<FState,FStateDeleter> State;
    UPROPERTY() TObjectPtr<ALivingTownCafeVenue> Venue;
    TWeakObjectPtr<ALivingTownCafeWorldV3Controller> SessionController;
    TWeakObjectPtr<ACharacter> SessionPawn;
    FLivingTownCafeBinding Binding;
    FLivingTownCafeWorldView Presentation;
    bool bPrepared=false;
    double ClockRemainder=0;
    FString Notice;
    UPROPERTY(Transient) TObjectPtr<UAnimationAsset> PreviousAnimation;
    TWeakObjectPtr<UAnimSequence> PlayingMealClip;
    TWeakObjectPtr<UAnimSingleNodeInstance> MealAnimationPlayer;
    float PreviousAnimationTime=0,PreviousAnimationPlayRate=1;
    float LastObservedClipTime=0;
    double LastObservedWorldTime=0;
    uint32 LastObservedBoneRevision=0;
    bool bClipAdvancedThisFrame=false;
    bool bPreviousLooping=false,bPreviousPlaying=false;
    UPROPERTY(Transient) TObjectPtr<ULivingTownMetaHumanMealProducer> MetaHumanMeal;
    FDelegateHandle PostActorTickHandle;
    uint64 LastNaturalClockFrame=MAX_uint64;
    FString MetaHumanMealFailure;
    TSharedPtr<FStreamableHandle> MealPreload;
    uint64 MealPreloadEpoch=0;
    bool bMealRolesReady=false;
    void BeginMealPreload();
    void CompleteMealPreload(uint64 Epoch);
    void CancelMealPreload();
    void AfterActorTick(UWorld* World,ELevelTick TickType,float Delta);
    void TickNaturalClock(float Delta);
    void ConfigureMetaHumanMeal();
    bool TrustedMetaHumanMealSession(const ALivingTownCafeCharacter* Pawn)const;
    bool ObserveCounter(bool& Reachable,FString& Why)const;
    ULivingTownCafeMealContactComponent* MealProvider()const;
    bool StartPhysicalMeal(FString& Error);
    void StopPhysicalMeal();
    void ReleaseMetaHumanMealProvider();
    bool ObservePhysicalMeal(FString& Error);
    bool AdvanceNaturalClock(int64 Whole,bool bContinuous,FString& Error);
    void RefreshPresentation();
    FString SlotPath()const;
    FLivingTownCafeWorldReceipt SubmitPropertyInternal(const FLivingTownCafePropertyCommand& Command,bool bRecurringOffer,bool bRecurringAgreement,int64 ObservedOfferRevision,int64 ObservedTitleRevision);
    bool DecodeJournal(const FString& Json,uint8 Version,FString& Error);
};
