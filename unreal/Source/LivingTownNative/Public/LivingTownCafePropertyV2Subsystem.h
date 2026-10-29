#pragma once
#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "LivingTownCafeBinding.h"
#include "LivingTownCafePropertyV2Types.h"
#include "LivingTownCafePropertyV2Subsystem.generated.h"
class ALivingTownCafeVenue;
class ALivingTownCafePropertyV2Controller;
class ACharacter;

UCLASS()
class LIVINGTOWNNATIVE_API ULivingTownCafePropertyV2Subsystem final:public UTickableWorldSubsystem {
    GENERATED_BODY()
public:
    ULivingTownCafePropertyV2Subsystem();
    virtual ~ULivingTownCafePropertyV2Subsystem()override;
    virtual bool ShouldCreateSubsystem(UObject* Outer)const override;
    virtual bool DoesSupportWorldType(EWorldType::Type Type)const override;
    virtual void Deinitialize()override;
    virtual void Tick(float DeltaSeconds)override;
    virtual TStatId GetStatId()const override;
    bool PrepareScenario(FString& Error);
    bool BindNativeSession(ALivingTownCafePropertyV2Controller* Controller,ACharacter* Pawn,FString& Error);
    void DetachNativeSession();
    bool IsPrepared()const{return bPrepared;}
    const FLivingTownCafeBinding& GetBinding()const{return Binding;}
    const FLivingTownCafePropertyView& GetPresentation()const{return Presentation;}
    FLivingTownCafePropertyReceipt SubmitCommand(const FLivingTownCafePropertyCommand& Command);
    bool SaveSlot(FString& Error,FString* SavedSha256=nullptr)const;
    bool LoadSlot(FString& Error);
    // Public testable envelope API; still requires an active source-bound scenario.
    bool EncodeJournal(FString& Json,FString& Error)const;
    bool LoadJournal(const FString& Json,FString& Error);
private:
    struct FState;
    struct FStateDeleter{void operator()(FState* Pointer)const;};
    TUniquePtr<FState,FStateDeleter> State;
    UPROPERTY() TObjectPtr<ALivingTownCafeVenue> Venue;
    TWeakObjectPtr<ALivingTownCafePropertyV2Controller> SessionController;
    TWeakObjectPtr<ACharacter> SessionPawn;
    FLivingTownCafeBinding Binding;
    FLivingTownCafePropertyView Presentation;
    bool bPrepared=false;
    double ClockRemainder=0;
    float PresentationElapsed=0;
    FString Notice;
    bool ObserveCounter(bool& Reachable,FString& Why)const;
    bool AdvanceNaturalClockTo(int64 NewTick,FString& Error);
    void RefreshPresentation();
    FString SlotPath()const;
};
