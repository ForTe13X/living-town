#pragma once
#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/HUD.h"
#include "LivingTownCafeWorldV3Types.h"
#include "LivingTownCafePropertyV2Types.h"
#include "LivingTownCafeWorldV3Scenario.generated.h"
class ULivingTownMetaHumanVisualPreload;
enum class ELivingTownCafePersonaRequestResult : uint8 { Selected, Pending, Refused };
UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownCafeWorldV3Controller final : public APlayerController {
    GENERATED_BODY()
public:
    ALivingTownCafeWorldV3Controller();
    virtual void BeginPlay()override;
    virtual void SetupInputComponent()override;
    bool HasNativePersona()const{return bAuthorized;}
    ELivingTownCafeWorldPersona GetNativePersona()const{return Persona;}
    const FString& GetOperationNotice()const{return OperationNotice;}
    bool AreControlsVisible()const{return bControlsVisible;}
    FLivingTownCafeWorldReceipt RequestMeal(const FLivingTownCafeMealCommand& Command);
    FLivingTownCafeWorldReceipt RequestCancelMeal();
    FLivingTownCafeWorldReceipt RequestRecurringLeaseOffer(const FString& RequestId);
    FLivingTownCafeWorldReceipt RequestLeaseAgreement(const FString& RequestId,bool bRecurring,int64 ObservedOfferRevision,int64 ObservedTitleRevision);
private:
    friend class ALivingTownCafeWorldV3GameMode;
    bool bAuthorized=false;
    ELivingTownCafeWorldPersona Persona=ELivingTownCafeWorldPersona::Ben;
    FString OperationNotice;
    UPROPERTY(Transient) bool bControlsVisible=false;
    void ToggleControls();
    void SelectAria();void SelectBen();void Eat();void Cancel();void Save();void Load();void ImportOlderSave();
    void OfferSale();void OfferLease();void OfferRecurringLease();void Buy();void Lease();void EndLease();
    void SendProperty(ELivingTownCafePropertyAction Action);
};
UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownCafeWorldV3GameMode final : public AGameModeBase {
    GENERATED_BODY()
public:
    ALivingTownCafeWorldV3GameMode();
    virtual void StartPlay()override;
    virtual void EndPlay(const EEndPlayReason::Type Reason)override;
    virtual void HandleStartingNewPlayer_Implementation(APlayerController* NewPlayer)override;
    virtual APawn* SpawnDefaultPawnAtTransform_Implementation(AController*,const FTransform&)override;
    // Pending retains the currently authorized pawn and paired native session.
    ELivingTownCafePersonaRequestResult RequestPersona(ALivingTownCafeWorldV3Controller* Controller,ELivingTownCafeWorldPersona Persona,FString& Error);
    ELivingTownCafePersonaRequestResult GetPersonaRequestResult()const{return PersonaRequestResult;}
    // Immediate API for existing synchronous consumers. Never starts an asset load.
    bool SelectPersona(ALivingTownCafeWorldV3Controller* Controller,ELivingTownCafeWorldPersona Persona,FString& Error);
private:
    void StartScenarioPlayer(APlayerController* Controller);
    bool ValidatePersonaSelection(ALivingTownCafeWorldV3Controller* Controller,ELivingTownCafeWorldPersona Persona,FString& Error)const;
    bool SelectPersonaImmediate(ALivingTownCafeWorldV3Controller* Controller,ELivingTownCafeWorldPersona Persona,FString& Error);
    void CancelPendingPersonaRequest(bool bReleaseReadyPreload=false);
    void CompletePersonaRequest(uint64 ExpectedEpoch);
    UPROPERTY(Transient) TObjectPtr<ULivingTownMetaHumanVisualPreload> MetaHumanPreload;
    TWeakObjectPtr<ALivingTownCafeWorldV3Controller> PendingController;
    FString PendingDescriptorSha256;
    uint64 PersonaSelectionEpoch=0;
    ELivingTownCafePersonaRequestResult PersonaRequestResult=ELivingTownCafePersonaRequestResult::Refused;
    bool bEndingPlay=false;
};
UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownCafeWorldV3HUD final : public AHUD {
    GENERATED_BODY()
public:
    virtual void DrawHUD()override;
    bool IsCounterContextVisible()const;
    TArray<FString> GetControlRows()const;
    // These are the exact text rows drawn below the live interaction prompt.
    // Authority outcomes and the last controller result have distinct rows.
    TArray<FString> GetFeedbackRows()const;
};
