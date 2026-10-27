#include "LivingTownCafeGameMode.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownCafeProjectionSubsystem.h"
#include "LivingTownCafePlayerController.h"
#include "LivingTownCafeHUD.h"
#include "Engine/World.h"
#include "Misc/Paths.h"
#include "GameFramework/PlayerController.h"
#include "Components/CapsuleComponent.h"
ALivingTownCafeGameMode::ALivingTownCafeGameMode()
{
    DefaultPawnClass=nullptr;SpectatorClass=nullptr;PlayerControllerClass=ALivingTownCafePlayerController::StaticClass();HUDClass=ALivingTownCafeHUD::StaticClass();bUseSeamlessTravel=false;
}
APawn* ALivingTownCafeGameMode::SpawnDefaultPawnAtTransform_Implementation(AController*,const FTransform&){return nullptr;}
void ALivingTownCafeGameMode::StartPlay()
{
    Super::StartPlay();FString Error;auto* P=GetWorld()->GetSubsystem<ULivingTownCafeProjectionSubsystem>();
    if(!P||!P->PrepareQualifiedScene(FPaths::Combine(FPaths::ProjectContentDir(),TEXT("LivingTown/CafeProjectionBinding.json")),Error)){UE_LOG(LogTemp,Error,TEXT("Cafe journey refused: %s"),*Error);return;}
    for(FConstPlayerControllerIterator It=GetWorld()->GetPlayerControllerIterator();It;++It)StartQualifiedPlayer(It->Get());
}
void ALivingTownCafeGameMode::HandleStartingNewPlayer_Implementation(APlayerController* PC){Super::HandleStartingNewPlayer_Implementation(PC);StartQualifiedPlayer(PC);}
void ALivingTownCafeGameMode::StartQualifiedPlayer(APlayerController* PC)
{
    auto* P=GetWorld()->GetSubsystem<ULivingTownCafeProjectionSubsystem>();if(!PC||PC->GetPawn()||!P||!P->IsScenePrepared()||P->IsReady()||PC!=GetWorld()->GetFirstPlayerController())return;
    const auto& B=P->GetBinding();const FTransform T(B.SpawnRotation,B.SpawnFeetCm+FVector(0,0,B.CapsuleHalfHeightCm));
    ALivingTownCafeCharacter* Ben=GetWorld()->SpawnActorDeferred<ALivingTownCafeCharacter>(ALivingTownCafeCharacter::StaticClass(),T,nullptr,nullptr,ESpawnActorCollisionHandlingMethod::AlwaysSpawn);FString Error;
    if(!Ben||!Ben->ConfigureQualifiedBen(B,Error)){if(Ben)Ben->Destroy();UE_LOG(LogTemp,Error,TEXT("Ben source visual refused: %s"),*Error);return;}
    Ben->FinishSpawning(T);
    FCollisionQueryParams Q(SCENE_QUERY_STAT(CafeActualBenSpawn),true);Q.AddIgnoredActor(Ben);
    if(GetWorld()->OverlapBlockingTestByChannel(Ben->GetActorLocation(),FQuat::Identity,ECC_Pawn,FCollisionShape::MakeCapsule(B.CapsuleRadiusCm,B.CapsuleHalfHeightCm),Q)){Ben->Destroy();UE_LOG(LogTemp,Error,TEXT("Actual configured Ben spawn collision refused"));return;}
    PC->Possess(Ben);PC->SetControlRotation(B.SpawnRotation);
    if(!P->AttachQualifiedPlayer(Ben,Error)){PC->UnPossess();Ben->Destroy();UE_LOG(LogTemp,Error,TEXT("Ben physical binding refused: %s"),*Error);}
}
