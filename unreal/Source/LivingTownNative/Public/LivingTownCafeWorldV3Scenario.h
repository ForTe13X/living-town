#pragma once
#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/HUD.h"
#include "LivingTownCafeWorldV3Types.h"
#include "LivingTownCafePropertyV2Types.h"
#include "LivingTownCafeWorldV3Scenario.generated.h"
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
    FLivingTownCafeWorldReceipt RequestMeal(const FLivingTownCafeMealCommand& Command);
    FLivingTownCafeWorldReceipt RequestCancelMeal();
private:
    friend class ALivingTownCafeWorldV3GameMode;
    bool bAuthorized=false;
    ELivingTownCafeWorldPersona Persona=ELivingTownCafeWorldPersona::Ben;
    FString OperationNotice;
    void SelectAria();void SelectBen();void Eat();void Cancel();void Save();void Load();
    void OfferSale();void OfferLease();void Buy();void Lease();void EndLease();
    void SendProperty(ELivingTownCafePropertyAction Action);
};
UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownCafeWorldV3GameMode final : public AGameModeBase {
    GENERATED_BODY()
public:
    ALivingTownCafeWorldV3GameMode();
    virtual void StartPlay()override;
    virtual void HandleStartingNewPlayer_Implementation(APlayerController* NewPlayer)override;
    virtual APawn* SpawnDefaultPawnAtTransform_Implementation(AController*,const FTransform&)override;
    bool SelectPersona(ALivingTownCafeWorldV3Controller* Controller,ELivingTownCafeWorldPersona Persona,FString& Error);
private:
    void StartScenarioPlayer(APlayerController* Controller);
};
UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownCafeWorldV3HUD final : public AHUD {
    GENERATED_BODY()
public:
    virtual void DrawHUD()override;
    // These are the exact text rows drawn below the live interaction prompt.
    // Authority outcomes and the last controller result have distinct rows.
    TArray<FString> GetFeedbackRows()const;
};
