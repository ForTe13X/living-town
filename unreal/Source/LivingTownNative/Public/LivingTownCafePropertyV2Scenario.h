#pragma once
#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/Character.h"
#include "GameFramework/HUD.h"
#include "LivingTownCafePropertyV2Types.h"
#include "LivingTownCafeBinding.h"
#include "LivingTownCafePropertyV2Scenario.generated.h"
class USpringArmComponent;
class UCameraComponent;
class UStaticMeshComponent;

UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownCafePropertyOwnerProxy final:public ACharacter {
    GENERATED_BODY()
public:
    ALivingTownCafePropertyOwnerProxy();
    bool ConfigureFunctionalOwner(const FLivingTownCafeBinding& Binding,FString& Error);
    bool IsFunctionalOwnerConfigured()const{return bConfigured;}
    virtual void SetupPlayerInputComponent(UInputComponent* Input)override;
private:
    UPROPERTY() TObjectPtr<USpringArmComponent> CameraArm;
    UPROPERTY() TObjectPtr<UCameraComponent> Camera;
    UPROPERTY() TObjectPtr<UStaticMeshComponent> FunctionalMarker;
    bool bConfigured=false;
    void Forward(float Value);void Right(float Value);void Yaw(float Value);void Pitch(float Value);
};

UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownCafePropertyV2Controller final:public APlayerController {
    GENERATED_BODY()
public:
    virtual void BeginPlay()override;
    virtual void SetupInputComponent()override;
    bool HasNativePersona()const{return bAuthorized;}
    ELivingTownCafePropertyPersona GetNativePersona()const{return Persona;}
    const FString& GetOperationNotice()const{return OperationNotice;}
private:
    friend class ALivingTownCafePropertyV2GameMode;
    bool bAuthorized=false;
    ELivingTownCafePropertyPersona Persona=ELivingTownCafePropertyPersona::Ben;
    FString OperationNotice;
    void SelectOwner();void SelectBuyer();void OfferSale();void OfferLease();void Buy();void Lease();void EndLease();void Save();void Load();
    void Send(ELivingTownCafePropertyAction Action);
    void ToggleDetails();void NextDetailsPage();void PreviousDetailsPage();
};

UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownCafePropertyV2GameMode final:public AGameModeBase {
    GENERATED_BODY()
public:
    ALivingTownCafePropertyV2GameMode();
    virtual void StartPlay()override;
    virtual void HandleStartingNewPlayer_Implementation(APlayerController* NewPlayer)override;
    virtual APawn* SpawnDefaultPawnAtTransform_Implementation(AController* NewPlayer,const FTransform& SpawnTransform)override;
    bool SelectPersona(ALivingTownCafePropertyV2Controller* Controller,ELivingTownCafePropertyPersona Persona,FString& Error);
private:
    void StartScenarioPlayer(APlayerController* Controller);
};

UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownCafePropertyV2HUD final:public AHUD {
    GENERATED_BODY()
public:
    virtual void DrawHUD()override;
    void ToggleDetails();void NextDetailsPage();void PreviousDetailsPage();
private:
    bool bDetailsVisible=false,bLastFeedbackWasWarning=false;
    int32 DetailsPage=0,DetailsPageCount=1;
    float CachedDetailsWidth=-1.f,CachedDetailsTextScale=-1.f;
    FString CachedPrompt,CachedNotice,CachedOperation,LastFeedback,FriendlyFeedback;
    TArray<FString> CachedSourceLines,CachedDetailLines;
};
