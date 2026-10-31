#include "LivingTownCafePlayerController.h"
#include "LivingTownCafeProjectionSubsystem.h"
#include "Components/InputComponent.h"
#include "Engine/World.h"
#include "Camera/PlayerCameraManager.h"
#include "InputCoreTypes.h"
ALivingTownCafePlayerController::ALivingTownCafePlayerController()
{
    bAutoManageActiveCameraTarget=false;
}
void ALivingTownCafePlayerController::BeginPlay()
{
    Super::BeginPlay();bShowMouseCursor=false;SetInputMode(FInputModeGameOnly());if(PlayerCameraManager){PlayerCameraManager->ViewPitchMin=-55;PlayerCameraManager->ViewPitchMax=25;}
}
void ALivingTownCafePlayerController::SetupInputComponent()
{
    Super::SetupInputComponent();check(InputComponent);InputComponent->BindKey(EKeys::E,IE_Pressed,this,&ALivingTownCafePlayerController::LeaseCafe);InputComponent->BindKey(EKeys::R,IE_Pressed,this,&ALivingTownCafePlayerController::EndLease);InputComponent->BindKey(EKeys::F5,IE_Pressed,this,&ALivingTownCafePlayerController::SaveCafe);InputComponent->BindKey(EKeys::F9,IE_Pressed,this,&ALivingTownCafePlayerController::LoadCafe);
}
void ALivingTownCafePlayerController::LeaseCafe(){OperationNotice.Reset();if(auto* P=GetWorld()->GetSubsystem<ULivingTownCafeProjectionSubsystem>())P->RequestAction(ELivingTownLeaseAction::Lease);}
void ALivingTownCafePlayerController::EndLease(){OperationNotice.Reset();if(auto* P=GetWorld()->GetSubsystem<ULivingTownCafeProjectionSubsystem>())P->RequestAction(ELivingTownLeaseAction::EndLease);}
void ALivingTownCafePlayerController::SaveCafe(){FString Error;auto* P=GetWorld()->GetSubsystem<ULivingTownCafeProjectionSubsystem>();OperationNotice=P&&P->SaveSlot(Error)?TEXT("Café ledger saved."):TEXT("Café ledger save refused: ")+Error;}
void ALivingTownCafePlayerController::LoadCafe(){FString Error;auto* P=GetWorld()->GetSubsystem<ULivingTownCafeProjectionSubsystem>();OperationNotice=P&&P->LoadSlot(Error)?TEXT("Matching café ledger loaded; position unchanged."):TEXT("Café ledger load refused: ")+Error;}
