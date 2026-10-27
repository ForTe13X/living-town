#pragma once
#include "CoreMinimal.h"
#include "LivingTownTileData.h"

// Plain game-thread state. No UObject creation, asset IO or authority writes.
// Shared dependencies count once per active support, including diamond graphs.
class LIVINGTOWNNATIVE_API FLivingTownTileDemand final
{
public:
    bool Initialize(const TArray<FLivingTownTileUnitRef>& Units, FString& Error);
    bool SetSupports(const TMap<FString, TArray<FString>>& ActiveSupports, FString& Error);
    const TMap<FString, int32>& Counts() const { return RefCounts; }
    uint64 BeginRequest(const FString& UnitId);
    bool Accepts(const FString& UnitId, uint64 Token) const;
    void Cancel(const FString& UnitId);
    void Reset();
private:
    TMap<FString, TArray<FString>> Dependencies;
    TMap<FString, int32> RefCounts;
    TMap<FString, uint64> Tokens;
    uint64 NextToken = 1;
    bool Visit(const FString& Id, TSet<FString>& Path, TSet<FString>& Done, FString& Error) const;
};
