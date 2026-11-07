#pragma once
#include "CoreMinimal.h"
class UWorld;
namespace LivingTownCookedStartup
{
    bool IsRequested();
    void ArmWorld(const UWorld* World);
    void InvalidateWorld(const UWorld* World);
    bool VerifyPackage(const FString& Package,int64 SourceBytes,const FString& SourceSha,FString& Error);
    void Mark(const TCHAR* Event,const UWorld* World=nullptr);
    void ObserveReadyPlayerView(const UWorld* World);
}
