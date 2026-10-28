#include "LivingTownTileStreamingSubsystem.h"
#include "LivingTownTileDriver.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Components/BoxComponent.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/WorldInitializationValues.h"
#include "UObject/UObjectGlobals.h"
#include "UObject/Package.h"

// Synthetic engine primitives in a disposable world only. This friend is not
// reflected and does not change StartQualified or qualify a production asset.
struct FLivingTownTileLifecycleTestAccess
{
    struct FObserved
    {
        bool Alive=false,Registered=false,Visible=false,Hidden=true,Physics=false;
        ECollisionEnabled::Type Collision=ECollisionEnabled::NoCollision;
    };
    struct FHarness
    {
        FAutomationTestBase& Test;
        UWorld* World=nullptr;
        ULivingTownTileStreamingSubsystem* S=nullptr;
        ALivingTownTileDriver* Driver=nullptr;
        AActor* Focus=nullptr;
        TArray<TWeakObjectPtr<UPrimitiveComponent>> Created;
        int32 Ticks=0,TotalRegistrations=0,TotalVisibility=0,TotalCollision=0,TotalDestructions=0;
        explicit FHarness(FAutomationTestBase& InTest):Test(InTest){}
        ~FHarness()
        {
            if(World)
            {
                if(S)S->TearDownAll();
                if(GEngine)GEngine->DestroyWorldContext(World);
                World->DestroyWorld(false);
            }
        }
        bool Initialize()
        {
            if(!Test.TestNotNull(TEXT("engine exists"),GEngine))return false;
            UWorld::InitializationValues IV;
            IV.InitializeScenes(true).AllowAudioPlayback(false).RequiresHitProxies(false)
              .CreatePhysicsScene(true).CreateNavigation(false).CreateAISystem(false)
              .ShouldSimulatePhysics(false).EnableTraceCollision(true).CreateFXSystem(false)
              .SetTransactional(false);
            const FName Name=MakeUniqueObjectName(GetTransientPackage(),UWorld::StaticClass(),TEXT("TownLifecycleAutomation"));
            World=UWorld::CreateWorld(EWorldType::Game,false,Name,GetTransientPackage(),true,ERHIFeatureLevel::Num,&IV);
            if(!Test.TestNotNull(TEXT("isolated synthetic world"),World))return false;
            World->SetFlags(RF_Transient);GEngine->CreateNewWorldContext(EWorldType::Game).SetCurrentWorld(World);
            S=World->GetSubsystem<ULivingTownTileStreamingSubsystem>();
            if(!Test.TestNotNull(TEXT("initialized real world subsystem"),S))return false;
            if(!Test.TestTrue(TEXT("subsystem initialized"),S->IsInitialized()))return false;
            Driver=World->SpawnActor<ALivingTownTileDriver>();Focus=World->SpawnActor<AActor>();
            if(!Test.TestNotNull(TEXT("synthetic driver"),Driver)||!Test.TestNotNull(TEXT("synthetic focus"),Focus))return false;
            Driver->FocusActor=Focus;
            S->AutomationFactory=[this](AActor* Owner,const FString&,int32 Index)->UPrimitiveComponent*
            {
                UBoxComponent* Box=NewObject<UBoxComponent>(Owner);
                Box->SetBoxExtent(FVector(30,30,10),false);
                Box->SetRelativeLocation(FVector(Index*100,0,0));Created.Add(Box);return Box;
            };
            if(!Test.TestTrue(TEXT("hook only recognizes transient automation world"),S->IsAutomationWorld()))return false;
            // This fixture deliberately has false qualification flags and no
            // mesh paths. Only friend setup supplies real synthetic primitives.
            S->Root=NewObject<ULivingTownTileRootData>(S);S->Driver=Driver;
            TArray<FLivingTownTileUnitRef> Refs;
            for(const FString& Id:TArray<FString>{TEXT("a"),TEXT("b"),TEXT("c"),TEXT("d")})
            {
                FLivingTownTileUnitRef Ref;Ref.UnitId=Id;Ref.ActualNativeBoundsCm=FBox(FVector(-10),FVector(10));
                Refs.Add(Ref);S->Catalog.Add(Id,Ref);
            }
            FString Error;if(!Test.TestTrue(TEXT("synthetic demand graph"),S->Demand.Initialize(Refs,Error)))return false;
            if(!Test.TestTrue(TEXT("world owns geometry actor"),S->CreateGeometryOwner()))return false;
            Test.TestTrue(TEXT("geometry is not owned by driver"),S->GeometryOwner.Get()!=Driver&&S->GeometryOwner->GetOwner()==nullptr);
            Test.TestNull(TEXT("geometry owner has no implicit root registration"),S->GeometryOwner->GetRootComponent());
            S->bActive=true;++S->Epoch;S->ComponentOperationBudget=1;return true;
        }
        TArray<FObserved> Snapshot() const
        {
            TArray<FObserved> Rows;
            for(const auto& Weak:Created)
            {
                FObserved O;if(const auto* C=Weak.Get())
                {O.Alive=true;O.Registered=C->IsRegistered();O.Visible=C->GetVisibleFlag();O.Hidden=C->bHiddenInGame;O.Collision=C->GetCollisionEnabled();O.Physics=C->IsPhysicsStateCreated();}
                Rows.Add(O);
            }
            return Rows;
        }
        bool Tick()
        {
            if(++Ticks>512){Test.AddError(TEXT("synthetic lifecycle tick cap exceeded"));return false;}
            const auto Before=Snapshot();S->Tick(0.016f);const auto After=Snapshot();
            int32 Registrations=0,Visibility=0,Collision=0,Destructions=0;
            for(int32 I=0;I<After.Num();++I)
            {
                const FObserved A=After[I],B=Before.IsValidIndex(I)?Before[I]:FObserved{};
                if(!B.Alive&&A.Alive)
                {
                    Registrations+=A.Registered?1:0;
                    Test.TestTrue(TEXT("new registration starts hidden/noncolliding"),A.Registered&&!A.Visible&&A.Hidden&&A.Collision==ECollisionEnabled::NoCollision);
                }
                else if(B.Alive&&!A.Alive)++Destructions;
                else if(B.Alive&&A.Alive)
                {
                    Test.TestEqual(TEXT("live geometry remains registered"),A.Registered,B.Registered);
                    if(B.Visible!=A.Visible||B.Hidden!=A.Hidden)++Visibility;
                    if(B.Collision!=A.Collision)
                    {++Collision;if(A.Collision!=ECollisionEnabled::NoCollision)Test.TestTrue(TEXT("enabling collision creates actual physics state"),A.Physics);}
                    if(!B.Visible&&A.Visible)
                        Test.TestTrue(TEXT("collision enabled before exposing supporting primitive"),A.Collision==ECollisionEnabled::QueryAndPhysics);
                }
            }
            TotalRegistrations+=Registrations;TotalVisibility+=Visibility;TotalCollision+=Collision;TotalDestructions+=Destructions;
            const int32 Observed=Registrations+Visibility+Collision+Destructions;
            Test.TestTrue(TEXT("actual component state changes share one per-tick budget"),Observed<=S->ComponentOperationBudget);
            Test.TestEqual(TEXT("registration counter matches actual engine state"),S->LastFrame.Registrations,Registrations);
            Test.TestEqual(TEXT("visibility counter matches actual engine state"),S->LastFrame.VisibilityTransitions,Visibility);
            Test.TestEqual(TEXT("collision counter matches actual engine state"),S->LastFrame.CollisionTransitions,Collision);
            Test.TestEqual(TEXT("destruction counter matches actual weak objects"),S->LastFrame.Destructions,Destructions);
            int32 Live=0;TSet<const UPrimitiveComponent*> Unique;
            for(const auto& Weak:Created)if(const auto* C=Weak.Get())
            {
                ++Live;Test.TestFalse(TEXT("no duplicate live component pointer"),Unique.Contains(C));Unique.Add(C);
                Test.TestTrue(TEXT("registered component owned in actual actor registry"),S->GeometryOwner&&S->GeometryOwner->GetInstanceComponents().Contains(C));
            }
            if(S->GeometryOwner)Test.TestEqual(TEXT("actor registry has exactly live synthetic geometry"),S->GeometryOwner->GetInstanceComponents().Num(),Live);
            TSet<FString> EntryIds;TSet<const UPrimitiveComponent*> Assigned;
            for(const auto& Pair:S->Installed)
            {
                const auto& U=Pair.Value;Test.TestTrue(TEXT("fixed source slots match geometry count"),U.Data&&U.Components.Num()==U.Data->Geometry.Num());
                for(int32 I=0;I<U.Components.Num();++I)if(const auto* C=U.Components[I].Get())
                {
                    const FString& Entry=U.Data->Geometry[I].EntryId;
                    Test.TestFalse(TEXT("no duplicate live source entry"),EntryIds.Contains(Entry));EntryIds.Add(Entry);
                    Test.TestFalse(TEXT("one component cannot occupy two source slots"),Assigned.Contains(C));Assigned.Add(C);
                    Test.TestTrue(TEXT("component retains exact source entry tag"),C->ComponentTags.Contains(FName(*Entry)));
                }
            }
            Test.TestEqual(TEXT("all live engine primitives have exactly one source slot"),Assigned.Num(),Live);
            Test.TestTrue(TEXT("test primitive creation stays bounded"),Created.Num()<=32);return true;
        }
        bool Want(const TArray<FString>& Ids)
        {
            TMap<FString,TArray<FString>> Supports;if(!Ids.IsEmpty())Supports.Add(TEXT("synthetic"),Ids);
            FString Error;return Test.TestTrue(TEXT("set actual demand"),S->Demand.SetSupports(Supports,Error))&&Test.TestTrue(TEXT("reconcile actual demand"),S->ReconcileDemand(Error));
        }
        bool Inject(const FString& Id,int32 Count,bool Complete)
        {
            if(!Test.TestFalse(TEXT("synthetic source unit not already requested"),S->Requests.Contains(Id)))return false;
            ULivingTownRenderUnitData* Data=NewObject<ULivingTownRenderUnitData>(S);Data->UnitId=Id;
            for(int32 I=0;I<Count;++I)
            {
                FLivingTownTileGeometry G;G.EntryId=FString::Printf(TEXT("synthetic_%s_%d"),*Id,I);G.bBlockingCollision=true;Data->Geometry.Add(G);
            }
            FLivingTownInstalledUnit U;U.Data=Data;U.Components.SetNum(Count);S->Installed.Add(Id,MoveTemp(U));
            ULivingTownTileStreamingSubsystem::FRequest R;R.Token=S->Demand.BeginRequest(Id);R.Phase=ULivingTownTileStreamingSubsystem::EPhase::Meshes;
            if(!Test.TestTrue(TEXT("fresh synthetic request token"),R.Token!=0))return false;
            S->Requests.Add(Id,MoveTemp(R));if(Complete)S->OnMeshes(Id,S->Epoch,S->Requests[Id].Token);return true;
        }
        bool Resident(const FString& Id) const
        {const auto* R=S->Requests.Find(Id);return R&&R->Phase==ULivingTownTileStreamingSubsystem::EPhase::Resident;}
        bool RunUntil(TFunctionRef<bool()> Done)
        {for(int32 I=0;I<192;++I){if(Done())return true;if(!Tick())return false;}Test.AddError(TEXT("bounded lifecycle did not reach expected state"));return false;}
        TArray<TWeakObjectPtr<UPrimitiveComponent>> Unit(const FString& Id) const
        {TArray<TWeakObjectPtr<UPrimitiveComponent>> Out;if(const auto* U=S->Installed.Find(Id))for(const auto& C:U->Components)Out.Add(C.Get());return Out;}
        bool Exposed(const TArray<TWeakObjectPtr<UPrimitiveComponent>>& Components) const
        {for(const auto& W:Components){const auto* C=W.Get();if(!C||!C->IsRegistered()||!C->GetVisibleFlag()||C->bHiddenInGame||C->GetCollisionEnabled()!=ECollisionEnabled::QueryAndPhysics)return false;}return true;}
        int32 LiveCount(const TArray<TWeakObjectPtr<UPrimitiveComponent>>& Components) const
        {int32 N=0;for(const auto& W:Components)if(W.IsValid())++N;return N;}
    };
    static bool Run(FAutomationTestBase& Test)
    {
        FHarness H(Test);if(!H.Initialize())return false;auto* S=H.S;
        if(!H.Want({TEXT("a")})||!H.Inject(TEXT("a"),7,true)||!H.RunUntil([&](){return H.Resident(TEXT("a"));}))return false;
        const auto A=H.Unit(TEXT("a"));Test.TestTrue(TEXT("all seven arrival components exposed"),H.Exposed(A));
        Test.TestTrue(TEXT("synthetic physics state exists"),A[0]->IsPhysicsStateCreated());
        const uint64 OldEpoch=S->Epoch,OldA=S->Requests[TEXT("a")].Token;
        // Outgoing support must remain intact while the destination is loading.
        if(!H.Want({TEXT("b")})||!H.Inject(TEXT("b"),7,false))return false;
        for(int32 I=0;I<4;++I){if(!H.Tick())return false;Test.TestTrue(TEXT("loading destination pins old collision and visibility"),H.Exposed(A));}
        S->OnMeshes(TEXT("a"),OldEpoch,OldA);S->OnData(TEXT("a"),OldEpoch,OldA);
        Test.TestTrue(TEXT("stale completion cannot revive retiring unit"),S->Requests[TEXT("a")].Phase==ULivingTownTileStreamingSubsystem::EPhase::Retiring);
        S->OnMeshes(TEXT("b"),S->Epoch,S->Requests[TEXT("b")].Token);
        while(!H.Resident(TEXT("b")))
        {if(!H.Tick())return false;if(!H.Resident(TEXT("b")))Test.TestTrue(TEXT("partial destination activation still pins outgoing floor"),H.Exposed(A));}
        // Permit one actual destruction, then reenter: retained slots survive and
        // the single tombstone is recreated without duplicating source entries.
        if(!H.RunUntil([&](){return H.LiveCount(A)<A.Num();}))return false;
        TArray<TWeakObjectPtr<UPrimitiveComponent>> Survivors;for(const auto& W:A)if(W.IsValid())Survivors.Add(W);
        if(!H.Want({TEXT("a"),TEXT("b")}))return false;
        Test.TestTrue(TEXT("reentry creates a fresh token"),S->Requests[TEXT("a")].Token!=OldA);
        S->OnMeshes(TEXT("a"),OldEpoch,OldA);S->OnData(TEXT("a"),OldEpoch,OldA);
        if(!H.RunUntil([&](){return H.Resident(TEXT("a"));}))return false;
        const auto Restored=H.Unit(TEXT("a"));Test.TestEqual(TEXT("exact source-entry slots restored"),Restored.Num(),7);
        for(const auto& W:Survivors)Test.TestTrue(TEXT("reentry keeps every surviving engine component"),Restored.Contains(W));
        Test.TestTrue(TEXT("restored source unit exposed"),H.Exposed(Restored));
        // Missing focus is a conservative active-cohort pin, never a stop pin.
        H.Driver->FocusActor=nullptr;
        Test.TestNull(TEXT("no fallback pawn in isolated world"),H.Driver->ResolveFocus());
        if(!H.Want({TEXT("b")}))return false;
        for(int32 I=0;I<4;++I){if(!H.Tick())return false;Test.TestTrue(TEXT("missing active focus holds ordinary retirement"),H.Exposed(Restored));}
        H.Driver->FocusActor=H.Focus;
        // Cancel a partly installed incoming unit; no bulk destruction at demand update.
        if(!H.Want({TEXT("b"),TEXT("c")})||!H.Inject(TEXT("c"),7,true)||!H.Tick()||!H.Tick())return false;
        const auto C=H.Unit(TEXT("c"));const int32 CBefore=H.LiveCount(C);
        Test.TestTrue(TEXT("partly installed cancellation fixture"),CBefore>0&&CBefore<7);
        const uint64 CToken=S->Requests[TEXT("c")].Token;
        if(!H.Want({TEXT("b")}))return false;
        Test.TestEqual(TEXT("cancel does not synchronously destroy components"),H.LiveCount(C),CBefore);
        S->OnMeshes(TEXT("c"),S->Epoch,CToken);S->OnData(TEXT("c"),S->Epoch,CToken);
        if(!H.RunUntil([&](){return !S->Requests.Contains(TEXT("a"))&&!S->Requests.Contains(TEXT("c"));}))return false;
        // Stop drains even without focus, refuses new generation until the last
        // owned component/actor is gone, and rejects old epoch callbacks.
        H.Driver->FocusActor=nullptr;const uint64 StopEpoch=S->Epoch,StopToken=S->Requests[TEXT("b")].Token;
        const auto B=H.Unit(TEXT("b"));S->Stop(H.Driver);
        Test.TestTrue(TEXT("stop returns before any component destruction"),H.Exposed(B));
        Test.TestTrue(TEXT("stopped subsystem remains tickable for drain"),S->IsTickable());
        H.Driver->bEnableQualifiedPilot=true;FString Error;
        Test.TestFalse(TEXT("new public generation refuses undrained owner"),S->StartQualified(H.Driver,S->Root,Error));
        S->OnMeshes(TEXT("b"),StopEpoch,StopToken);S->OnData(TEXT("b"),StopEpoch,StopToken);
        if(!H.RunUntil([&](){return S->Requests.IsEmpty();}))return false;
        Test.TestTrue(TEXT("stop clears all owned geometry and handles"),S->Installed.IsEmpty()&&!S->GeometryOwner&&!S->IsTickable());
        ULivingTownTileRootData* Unqualified=NewObject<ULivingTownTileRootData>(S);
        Test.TestFalse(TEXT("test hook does not bypass public qualification"),S->StartQualified(H.Driver,Unqualified,Error));
        // Driver destruction is different from world teardown: world-owned
        // geometry survives Destroy() and is retired by subsequent budgeted ticks.
        FString DemandError;TArray<FLivingTownTileUnitRef> Refs;FLivingTownTileUnitRef Ref;Ref.UnitId=TEXT("d");Refs.Add(Ref);
        Test.TestTrue(TEXT("fresh synthetic demand generation"),S->Demand.Initialize(Refs,DemandError));S->Catalog.Add(TEXT("d"),Ref);
        S->Driver=H.Driver;S->Root=NewObject<ULivingTownTileRootData>(S);S->bActive=true;++S->Epoch;
        if(!S->CreateGeometryOwner()||!H.Want({TEXT("d")})||!H.Inject(TEXT("d"),7,true)||!H.RunUntil([&](){return H.Resident(TEXT("d"));}))return false;
        const auto D=H.Unit(TEXT("d"));const uint64 DestroyEpoch=S->Epoch,DestroyToken=S->Requests[TEXT("d")].Token;
        H.Driver->Destroy();Test.TestTrue(TEXT("destroying driver cannot implicitly destroy proxy geometry"),H.Exposed(D));
        if(!H.Tick())return false;
        Test.TestFalse(TEXT("lost driver begins inactive drain"),S->bActive);
        S->OnMeshes(TEXT("d"),DestroyEpoch,DestroyToken);S->OnData(TEXT("d"),DestroyEpoch,DestroyToken);
        if(!H.RunUntil([&](){return S->Requests.IsEmpty();}))return false;
        Test.TestTrue(TEXT("destroyed driver drain releases owner"),!S->GeometryOwner&&S->Installed.IsEmpty());
        // Model the conservative Frozen state without logging a manufactured
        // production qualification error. Real world ownership must still be
        // polled if its driver is later destroyed before a begun-play EndPlay.
        H.Driver=H.World->SpawnActor<ALivingTownTileDriver>();if(!Test.TestNotNull(TEXT("frozen-cohort synthetic driver"),H.Driver))return false;
        H.Driver->FocusActor=H.Focus;
        Test.TestTrue(TEXT("frozen synthetic demand graph"),S->Demand.Initialize(Refs,DemandError));S->Catalog.Add(TEXT("d"),Ref);
        S->Driver=H.Driver;S->Root=NewObject<ULivingTownTileRootData>(S);S->bActive=true;++S->Epoch;
        if(!S->CreateGeometryOwner()||!H.Want({TEXT("d")})||!H.Inject(TEXT("d"),3,true)||!H.RunUntil([&](){return H.Resident(TEXT("d"));}))return false;
        const auto Frozen=H.Unit(TEXT("d"));S->bActive=false;S->Requests[TEXT("d")].Phase=ULivingTownTileStreamingSubsystem::EPhase::Frozen;
        Test.TestTrue(TEXT("frozen owned cohort remains tickable for driver lifetime"),S->IsTickable());
        if(!H.Tick())return false;Test.TestTrue(TEXT("live driver preserves frozen supporting geometry"),H.Exposed(Frozen));
        H.Driver->Destroy();Test.TestTrue(TEXT("driver destruction cannot implicitly destroy frozen geometry"),H.Exposed(Frozen));
        if(!H.RunUntil([&](){return S->Requests.IsEmpty();}))return false;
        Test.TestTrue(TEXT("lost frozen driver drains owner and components"),!S->GeometryOwner&&S->Installed.IsEmpty()&&H.LiveCount(Frozen)==0);
        // Explicit teardown exception invokes the same synchronous cleanup used
        // by Deinitialize; callbacks after its epoch invalidation remain inert.
        H.Driver=H.World->SpawnActor<ALivingTownTileDriver>();H.Driver->FocusActor=H.Focus;
        Test.TestNotNull(TEXT("second synthetic driver"),H.Driver);if(!H.Driver)return false;
        Test.TestTrue(TEXT("teardown synthetic demand graph"),S->Demand.Initialize(Refs,DemandError));S->Catalog.Add(TEXT("d"),Ref);
        S->Driver=H.Driver;S->Root=NewObject<ULivingTownTileRootData>(S);S->bActive=true;++S->Epoch;
        if(!S->CreateGeometryOwner()||!H.Want({TEXT("d")})||!H.Inject(TEXT("d"),4,true)||!H.RunUntil([&](){return H.Resident(TEXT("d"));}))return false;
        const uint64 TearEpoch=S->Epoch,TearToken=S->Requests[TEXT("d")].Token;const auto Tear=H.Unit(TEXT("d"));
        S->TearDownAll();Test.TestEqual(TEXT("explicit teardown synchronously releases all primitives"),H.LiveCount(Tear),0);
        S->OnMeshes(TEXT("d"),TearEpoch,TearToken);S->OnData(TEXT("d"),TearEpoch,TearToken);
        Test.TestTrue(TEXT("teardown leaves no requests, installed units or owner"),S->Requests.IsEmpty()&&S->Installed.IsEmpty()&&!S->GeometryOwner);
        Test.TestFalse(TEXT("teardown removes test factory"),bool(S->AutomationFactory));
        Test.TestEqual(TEXT("every created primitive registered through budgeted path"),H.TotalRegistrations,H.Created.Num());
        Test.TestEqual(TEXT("all ordinary destructions plus explicit teardown close ownership"),H.TotalDestructions+Tear.Num(),H.Created.Num());
        Test.AddInfo(FString::Printf(TEXT("TownLifecycleBudgetWorld observed: ticks=%d registrations=%d visibility=%d collision=%d destructions=%d teardown=%d budget=1; synthetic primitives only"),H.Ticks,H.TotalRegistrations,H.TotalVisibility,H.TotalCollision,H.TotalDestructions,Tear.Num()));
        return true;
    }
};

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownTileLifecycleBudgetWorld,"LivingTown.Native.TileLifecycleBudgetWorld",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownTileLifecycleBudgetWorld::RunTest(const FString&)
{return FLivingTownTileLifecycleTestAccess::Run(*this);}
#endif
