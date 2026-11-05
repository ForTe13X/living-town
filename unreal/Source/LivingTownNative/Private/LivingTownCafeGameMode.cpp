#include "LivingTownCafeGameMode.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownCafeProjectionSubsystem.h"
#include "LivingTownCafePlayerController.h"
#include "LivingTownCafeHUD.h"
#include "LivingTownFullTownStreamingSubsystem.h"
#include "LivingTownMetaHumanVisualAssembly.h"
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
    const auto& B=P->GetBinding();
    if(B.MetaHumanActor.IsSet())
    {
        auto* Preload=FindComponentByClass<ULivingTownMetaHumanVisualPreload>();
        if(!Preload)
        {
            Preload=NewObject<ULivingTownMetaHumanVisualPreload>(this,TEXT("MetaHumanBenPreload"));
            if(!Preload){UE_LOG(LogTemp,Error,TEXT("MetaHuman Ben preload component creation refused"));return;}
            AddInstanceComponent(Preload);Preload->RegisterComponent();
        }
        FString PreloadError;TWeakObjectPtr<ALivingTownCafeGameMode> WeakMode(this);TWeakObjectPtr<APlayerController> WeakPlayer(PC);
        const auto State=Preload->Request(B.MetaHumanActor.GetValue(),FSimpleDelegate::CreateLambda([WeakMode,WeakPlayer]()
        {if(auto* Mode=WeakMode.Get();Mode&&WeakPlayer.IsValid())Mode->StartQualifiedPlayer(WeakPlayer.Get());}),PreloadError);
        if(State==ELivingTownMetaHumanPreloadState::Pending)return; // no pawn, possession or qualified success yet
        if(State!=ELivingTownMetaHumanPreloadState::Ready)
        {UE_LOG(LogTemp,Error,TEXT("MetaHuman Ben preload refused: %s"),*PreloadError);return;}
        if(PC->GetPawn()||P->IsReady())return; // an immediate completion already consumed readiness
    }
    const FTransform T(B.SpawnRotation,B.SpawnFeetCm+FVector(0,0,B.CapsuleHalfHeightCm));
    ALivingTownCafeCharacter* Ben=GetWorld()->SpawnActorDeferred<ALivingTownCafeCharacter>(ALivingTownCafeCharacter::StaticClass(),T,nullptr,nullptr,ESpawnActorCollisionHandlingMethod::AlwaysSpawn);FString Error;
    // A child actor's BeginPlay is deferred until its native parent has begun.
    // Let the complete MetaHuman run normal SDK setup before visual validation.
    if(Ben&&B.MetaHumanActor.IsSet())Ben->FinishSpawning(T);
    if(!Ben||!Ben->ConfigureQualifiedBen(B,Error)){if(Ben)Ben->Destroy();UE_LOG(LogTemp,Error,TEXT("Ben source visual refused: %s"),*Error);return;}
    if(!B.MetaHumanActor.IsSet())Ben->FinishSpawning(T);
    FCollisionQueryParams Q(SCENE_QUERY_STAT(CafeActualBenSpawn),true);Q.AddIgnoredActor(Ben);
    if(GetWorld()->OverlapBlockingTestByChannel(Ben->GetActorLocation(),FQuat::Identity,ECC_Pawn,FCollisionShape::MakeCapsule(B.CapsuleRadiusCm,B.CapsuleHalfHeightCm),Q)){Ben->Destroy();UE_LOG(LogTemp,Error,TEXT("Actual configured Ben spawn collision refused"));return;}
    auto* FullTown=GetWorld()->GetSubsystem<ULivingTownFullTownStreamingSubsystem>();
    if(FullTown&&!FullTown->BeforeQualifiedPossess(PC,Error)){Ben->Destroy();UE_LOG(LogTemp,Error,TEXT("FullTown boot possession refused: %s"),*Error);return;}
    PC->Possess(Ben);
    if(FullTown&&!FullTown->AfterQualifiedPossess(PC,Ben,Error)){PC->UnPossess();Ben->Destroy();UE_LOG(LogTemp,Error,TEXT("FullTown post-possession lock refused: %s"),*Error);return;}
    PC->SetControlRotation(B.SpawnRotation);
    if(!P->AttachQualifiedPlayer(Ben,Error)){PC->UnPossess();Ben->Destroy();UE_LOG(LogTemp,Error,TEXT("Ben physical binding refused: %s"),*Error);return;}
    PC->SetViewTarget(Ben);
}
