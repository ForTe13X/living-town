#include "LivingTownTileDriver.h"
#include "LivingTownTileStreamingSubsystem.h"
#include "Components/SceneComponent.h"
#include "Engine/AssetManager.h"
#include "Engine/StreamableManager.h"
#include "Engine/World.h"
#include "Kismet/GameplayStatics.h"
#include "GameFramework/Pawn.h"

ALivingTownTileDriver::ALivingTownTileDriver()
{
    PrimaryActorTick.bCanEverTick=false;
    auto* Origin=CreateDefaultSubobject<USceneComponent>(TEXT("QualifiedTownOrigin"));
    Origin->SetMobility(EComponentMobility::Static);SetRootComponent(Origin);
}

bool ALivingTownTileDriver::IsIdentityPlacement() const
{
    // This first source slice retains world-space vertex bytes. Origin rebasing
    // requires a separately qualified derivative; no rotated/scaled parent.
    return !GetAttachParentActor() && GetActorTransform().Equals(FTransform::Identity,0.0);
}

AActor* ALivingTownTileDriver::ResolveFocus() const
{
    return IsValid(FocusActor.Get())?FocusActor.Get():UGameplayStatics::GetPlayerPawn(this,0);
}

void ALivingTownTileDriver::BeginPlay()
{
    Super::BeginPlay();
    if(!bEnableQualifiedPilot) return;
    if(!IsIdentityPlacement()||!LivingTownTiles::IsPilotAssetPath(RootAsset.ToSoftObjectPath()))
    {UE_LOG(LogTemp,Error,TEXT("Town pilot refused: driver placement/root path"));return;}
    const uint64 RequestedEpoch=++RootEpoch;
    const TWeakObjectPtr<ALivingTownTileDriver> WeakThis(this);
    TArray<FSoftObjectPath> Paths{RootAsset.ToSoftObjectPath()};
    RootHandle=UAssetManager::GetStreamableManager().RequestAsyncLoad(Paths,FStreamableDelegate::CreateLambda([WeakThis,RequestedEpoch]()
    {
        auto* Self=WeakThis.Get();
        if(!Self||Self->RootEpoch!=RequestedEpoch||!Self->HasActorBegunPlay()||Self->IsActorBeingDestroyed()) return;
        Self->LoadedRoot=Self->RootAsset.Get();
        auto* Subsystem=Self->GetWorld()?Self->GetWorld()->GetSubsystem<ULivingTownTileStreamingSubsystem>():nullptr;
        FString Error;
        if(!Self->LoadedRoot||!Subsystem||!Subsystem->StartQualified(Self,Self->LoadedRoot,Error))
            UE_LOG(LogTemp,Error,TEXT("Town pilot refused: %s"),*Error);
    }),FStreamableManager::DefaultAsyncLoadPriority,false,false,TEXT("LivingTownPilotRoot"));
    if(!RootHandle) UE_LOG(LogTemp,Error,TEXT("Town pilot refused: root asynchronous request"));
}

void ALivingTownTileDriver::EndPlay(const EEndPlayReason::Type Reason)
{
    ++RootEpoch;
    if(GetWorld()) if(auto* S=GetWorld()->GetSubsystem<ULivingTownTileStreamingSubsystem>()) S->Stop(this);
    LoadedRoot=nullptr;
    if(RootHandle){RootHandle->CancelHandle();RootHandle.Reset();}
    Super::EndPlay(Reason);
}
