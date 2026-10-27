#pragma once

#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "LivingTownTileData.h"
#include "LivingTownTilePlan.h"
#include "LivingTownTileStreamingSubsystem.generated.h"

class ALivingTownTileDriver;
struct FStreamableHandle;
class UPrimitiveComponent;

USTRUCT()
struct FLivingTownInstalledUnit
{
    GENERATED_BODY()
    UPROPERTY(Transient) TObjectPtr<ULivingTownRenderUnitData> Data;
    UPROPERTY(Transient) TArray<TObjectPtr<UPrimitiveComponent>> Components;
    int32 NextGeometry = 0;
    bool bVisible = false;
};

UCLASS()
class LIVINGTOWNNATIVE_API ULivingTownTileStreamingSubsystem final : public UTickableWorldSubsystem
{
    GENERATED_BODY()
public:
    virtual bool DoesSupportWorldType(EWorldType::Type Type) const override;
    virtual void Tick(float DeltaSeconds) override;
    virtual TStatId GetStatId() const override;
    virtual bool IsTickable() const override;
    virtual void Deinitialize() override;
    bool StartQualified(ALivingTownTileDriver* Owner,ULivingTownTileRootData* Root,FString& Error);
    void Stop(ALivingTownTileDriver* Owner);
    const FString& GetLastError() const { return LastError; }
    int32 ResidentUnitCount() const { int32 Count=0;for(const auto& Pair:Installed) if(Pair.Value.bVisible) ++Count;return Count; }
    const UPrimitiveComponent* FindDeferredDoorComponent(const FString& EntryId) const;
private:
    enum class EPhase : uint8 { Data, Meshes, Installing, Resident };
    struct FRequest
    {
        uint64 Token = 0;
        EPhase Phase = EPhase::Data;
        TSharedPtr<FStreamableHandle> DataHandle;
        TSharedPtr<FStreamableHandle> MeshHandle;
    };
    struct FVerifiedMesh
    {
        TWeakObjectPtr<UStaticMesh> Mesh;
        FGuid LightingGuid;
        FString RenderSha256;
        FString CollisionGuid;
        TArray<FSoftObjectPath> MaterialPaths;
        TArray<FString> MaterialSlotNames;
        TArray<uint8> MaterialBlendModes;
    };
    UPROPERTY(Transient) TObjectPtr<ULivingTownTileRootData> Root;
    UPROPERTY(Transient) TMap<FString,FLivingTownInstalledUnit> Installed;
    TWeakObjectPtr<ALivingTownTileDriver> Driver;
    TMap<FString,FLivingTownTileUnitRef> Catalog;
    TArray<FLivingTownTileSupport> Supports;
    TArray<FString> PersistentUnits;
    TMap<FString,FLivingTownDeferredFixture> FixtureInventory;
    FLivingTownTileQualification Qualification;
    TMap<FString,FRequest> Requests;
    TMap<FString,FVerifiedMesh> VerifiedMeshes;
    FLivingTownTileDemand Demand;
    TSet<FString> ActiveSupports;
    FString CafeBindingSha256;
    FString LastError;
    double RefreshRemainder = 0;
    uint64 Epoch = 1;
    bool bActive = false;
    bool bVerifiedMeshThisFrame = false;
    int32 RequestBudget = 2;
    int32 CreationBudget = 4;
    double LoadRadiusCm = 8000;
    double UnloadRadiusCm = 10000;
    void StopAll();
    void Fail(const FString& Error);
    bool ParentAndCafeStillQualified() const;
    bool RefreshDemand(FString& Error);
    void PumpRequests();
    void OnData(const FString& Id,uint64 RequestEpoch,uint64 Token);
    void OnMeshes(const FString& Id,uint64 RequestEpoch,uint64 Token);
    bool AcceptCompletion(const FString& Id,uint64 RequestEpoch,uint64 Token) const;
    bool CreateOne(const FString& Id,FLivingTownInstalledUnit& Unit,bool& bWaiting,FString& Error);
    bool ValidateLoadedGeometry(const FLivingTownTileGeometry& Geometry,UStaticMesh* Mesh,bool& bWaiting,FString& Error);
    void Unload(const FString& Id);
};
