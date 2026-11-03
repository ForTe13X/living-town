#include "LivingTownFullTownDriver.h"
#include "LivingTownFullTownStreamingSubsystem.h"
#include "Engine/World.h"

ALivingTownFullTownDriver::ALivingTownFullTownDriver()
{ PrimaryActorTick.bCanEverTick=false; bReplicates=false; }

bool ALivingTownFullTownDriver::IsIdentityPlacement() const
{ return GetAttachParentActor()==nullptr && GetActorTransform().Equals(FTransform::Identity,0); }

void ALivingTownFullTownDriver::BeginPlay()
{
    Super::BeginPlay();
    if (!bEnableIntegrationSubset) return;
    auto* S=GetWorld()->GetSubsystem<ULivingTownFullTownStreamingSubsystem>();
    if (!S || !S->WasArmedBeforeGameMode(this))
        UE_LOG(LogTemp,Error,TEXT("FullTown driver refused: not armed in pre-GameMode OnWorldBeginPlay; late actors do not start streaming"));
}

void ALivingTownFullTownDriver::EndPlay(EEndPlayReason::Type Reason)
{
    if (auto* S=GetWorld()->GetSubsystem<ULivingTownFullTownStreamingSubsystem>()) S->NotifyDriverEnding(this);
    Super::EndPlay(Reason);
}
