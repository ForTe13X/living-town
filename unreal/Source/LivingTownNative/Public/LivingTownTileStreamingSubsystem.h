#pragma once

#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "LivingTownTileData.h"
#include "LivingTownTilePlan.h"
#include "LivingTownTileStreamingSubsystem.generated.h"

class ALivingTownTileDriver;
class AActor;
struct FStreamableHandle;
class UPrimitiveComponent;

USTRUCT()
struct FLivingTownInstalledUnit
{
    GENERATED_BODY()
    UPROPERTY(Transient) TObjectPtr<ULivingTownRenderUnitData> Data;
    // Fixed source-entry slots; retirement leaves tombstones for safe reentry.
    UPROPERTY(Transient) TArray<TObjectPtr<UPrimitiveComponent>> Components;
    int32 NextGeometry = 0;
    int32 NextActivation = 0;
    uint8 ActivationStep = 0; // collision, then visibility
    int32 NextRetirement = 0;
    uint8 RetirementStep = 0; // disable collision, hide, destroy
    bool bVisible = false;
};

// Counts component lifecycle policies (registration, collision, visibility or
// destruction), not every internal engine call, milliseconds or draw calls.
struct FLivingTownTileLifecycleFrame
{
    int32 Registrations=0,VisibilityTransitions=0,CollisionTransitions=0,Destructions=0;
    int32 Total() const{return Registrations+VisibilityTransitions+CollisionTransitions+Destructions;}
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
    int32 ResidentUnitCount() const;
    const UPrimitiveComponent* FindDeferredDoorComponent(const FString& EntryId) const;
private:
    enum class EPhase : uint8 { Data, Meshes, QueuedRestore, Installing, Activating, Resident, Retiring, Frozen };
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
    // No geometry is owned by the opt-in driver: its EndPlay cannot bypass the
    // ordinary drain budget by implicitly destroying every geometry component.
    UPROPERTY(Transient) TObjectPtr<AActor> GeometryOwner;
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
    FString LastServicedUnit;
    double RefreshRemainder = 0;
    uint64 Epoch = 1;
    bool bActive = false;
    bool bVerifiedMeshThisFrame = false;
    int32 RequestBudget = 2;
    int32 ComponentOperationBudget = 4;
    double LoadRadiusCm = 8000;
    double UnloadRadiusCm = 10000;
    FLivingTownTileLifecycleFrame LastFrame;
    void TearDownAll(); // explicit world/subsystem teardown; synchronous exception
    void BeginStop();
    void FinishDrainIfEmpty();
    void Fail(const FString& Error);
    bool ParentAndCafeStillQualified() const;
    bool CreateGeometryOwner();
    bool HasRetiringWork() const;
    bool HasExposedComponents(const FLivingTownInstalledUnit& Unit) const;
    bool RetirementAllowed() const;
    bool RefreshDemand(FString& Error);
    bool ReconcileDemand(FString& Error);
    void BeginRetirement(const FString& Id);
    void ReleaseUnit(const FString& Id); // components must already be gone
    void PumpRequests();
    void RequestMeshes(const FString& Id,uint64 RequestEpoch,uint64 Token);
    void OnData(const FString& Id,uint64 RequestEpoch,uint64 Token);
    void OnMeshes(const FString& Id,uint64 RequestEpoch,uint64 Token);
    bool AcceptCompletion(const FString& Id,uint64 RequestEpoch,uint64 Token) const;
    bool AdvanceOne(const FString& Id,bool& bOperated,bool& bProgressed,FString& Error);
    bool CreateOne(const FString& Id,FLivingTownInstalledUnit& Unit,bool& bWaiting,FString& Error);
    bool ValidateLoadedGeometry(const FLivingTownTileGeometry& Geometry,UStaticMesh* Mesh,bool& bWaiting,FString& Error);
#if WITH_DEV_AUTOMATION_TESTS
    friend struct FLivingTownTileLifecycleTestAccess;
    // No reflected API or release-build path. Requires an isolated transient
    // automation world and synthetic engine primitives, never imported assets.
    TFunction<UPrimitiveComponent*(AActor*,const FString&,int32)> AutomationFactory;
    bool IsAutomationWorld() const;
#endif
};
