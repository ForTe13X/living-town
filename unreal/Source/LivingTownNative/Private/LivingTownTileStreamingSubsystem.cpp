#include "LivingTownTileStreamingSubsystem.h"
#include "LivingTownTileDriver.h"
#include "LivingTownCafeProjectionSubsystem.h"
#include "LivingTownCafeGeometryLibrary.h"
#include "Components/InstancedStaticMeshComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/AssetManager.h"
#include "Engine/StaticMesh.h"
#include "Engine/StreamableManager.h"
#include "Engine/World.h"
#include "Engine/Level.h"
#include "GameFramework/Actor.h"
#include "PhysicsEngine/BodySetup.h"
#include "Materials/MaterialInterface.h"
#include "UObject/UObjectGlobals.h"

bool ULivingTownTileStreamingSubsystem::DoesSupportWorldType(EWorldType::Type Type) const
{return Type==EWorldType::Game||Type==EWorldType::PIE;}

TStatId ULivingTownTileStreamingSubsystem::GetStatId() const
{RETURN_QUICK_DECLARE_CYCLE_STAT(ULivingTownTileStreamingSubsystem,STATGROUP_Tickables);}

bool ULivingTownTileStreamingSubsystem::IsTickable() const
{return (bActive||!Requests.IsEmpty())&&!IsTemplate()&&IsInitialized();}

bool ULivingTownTileStreamingSubsystem::HasRetiringWork() const
{for(const auto& Pair:Requests)if(Pair.Value.Phase==EPhase::Retiring)return true;return false;}

int32 ULivingTownTileStreamingSubsystem::ResidentUnitCount() const
{int32 N=0;for(const auto& Pair:Requests)if(Pair.Value.Phase==EPhase::Resident)++N;return N;}

void ULivingTownTileStreamingSubsystem::Deinitialize()
{TearDownAll();Super::Deinitialize();}

#if WITH_DEV_AUTOMATION_TESTS
bool ULivingTownTileStreamingSubsystem::IsAutomationWorld() const
{
    return AutomationFactory&&GetWorld()&&GetWorld()->WorldType==EWorldType::Game&&
        GetWorld()->HasAnyFlags(RF_Transient)&&GetWorld()->GetName().StartsWith(TEXT("TownLifecycleAutomation"));
}
#endif

bool ULivingTownTileStreamingSubsystem::CreateGeometryOwner()
{
    if(GeometryOwner)return false;
    FActorSpawnParameters P;P.Name=MakeUniqueObjectName(GetWorld()->PersistentLevel,AActor::StaticClass(),TEXT("LivingTownStreamGeometry"));
    GeometryOwner=GetWorld()->SpawnActor<AActor>(AActor::StaticClass(),FTransform::Identity,P);
    if(!GeometryOwner)return false;
    // Intentionally no scene root: every geometry component is unattached,
    // with its source-native transform and an identity world-owned actor.
    GeometryOwner->PrimaryActorTick.bCanEverTick=false;GeometryOwner->SetActorTickEnabled(false);
    GeometryOwner->Tags.Add(TEXT("LivingTown.InternalStreamGeometry"));return true;
}

bool ULivingTownTileStreamingSubsystem::ParentAndCafeStillQualified() const
{
    const auto* Owner=Driver.Get();
    if(!Owner||Owner->IsActorBeingDestroyed()||!Owner->IsIdentityPlacement()||!IsValid(GeometryOwner.Get())||GeometryOwner->IsActorBeingDestroyed()||
       GeometryOwner->GetWorld()!=GetWorld()||GeometryOwner->GetRootComponent()||!GeometryOwner->GetActorTransform().Equals(FTransform::Identity,0))return false;
#if WITH_DEV_AUTOMATION_TESTS
    if(IsAutomationWorld())return true;
#endif
    const auto* Cafe=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeProjectionSubsystem>():nullptr;
    return Cafe&&Cafe->IsScenePrepared()&&Cafe->IsReady()&&Cafe->GetBinding().BindingFileSha256==CafeBindingSha256;
}

bool ULivingTownTileStreamingSubsystem::StartQualified(ALivingTownTileDriver* Owner,ULivingTownTileRootData* Candidate,FString& Error)
{
    if(!IsInGameThread()||!Owner||!Candidate||Owner->GetWorld()!=GetWorld()||!Owner->bEnableQualifiedPilot||
       !Owner->IsIdentityPlacement()||bActive||!Requests.IsEmpty()||!Installed.IsEmpty()||GeometryOwner)
    {Error=TEXT("tile_driver_world_owner_or_prior_generation_not_drained");return false;}
    if(!FMath::IsFinite(Owner->LoadRadiusCm)||!FMath::IsFinite(Owner->UnloadRadiusCm)||
       Owner->LoadRadiusCm<0||Owner->LoadRadiusCm>20000||Owner->UnloadRadiusCm<Owner->LoadRadiusCm||Owner->UnloadRadiusCm>20000||
       Owner->MaxConcurrentRequests<1||Owner->MaxConcurrentRequests>2||Owner->ComponentsPerFrame<1||Owner->ComponentsPerFrame>4)
    {Error=TEXT("tile_driver_budget_or_radius");return false;}
    // No test-mode branch in this production entry point: all native gates stay.
    if(!LivingTownTiles::ValidateRoot(*Candidate,Error))return false;
    auto* Cafe=GetWorld()->GetSubsystem<ULivingTownCafeProjectionSubsystem>();
    if(!Cafe||!Cafe->IsScenePrepared()||!Cafe->IsReady()||Cafe->GetBinding().BindingFileSha256!=Candidate->ExistingCafeBindingSha256)
    {Error=TEXT("tile_existing_native_cafe_not_qualified");return false;}
    FLivingTownTileDemand CandidateDemand;if(!CandidateDemand.Initialize(Candidate->Units,Error))return false;
    Root=Candidate;Driver=Owner;Qualification=Candidate->Qualification;
    RequestBudget=Owner->MaxConcurrentRequests;ComponentOperationBudget=Owner->ComponentsPerFrame;
    LoadRadiusCm=Owner->LoadRadiusCm;UnloadRadiusCm=Owner->UnloadRadiusCm;
    Supports=Candidate->Supports;PersistentUnits=Candidate->PersistentUnits;CafeBindingSha256=Candidate->ExistingCafeBindingSha256;
    for(const auto& Ref:Candidate->Units)Catalog.Add(Ref.UnitId,Ref);
    for(const auto& F:Candidate->SourceFixtureInventory)FixtureInventory.Add(F.SourceGroupId,F);
    if(!Demand.Initialize(Candidate->Units,Error)||!CreateGeometryOwner()){TearDownAll();Error=TEXT("tile_start_demand_or_geometry_owner");return false;}
    ++Epoch;bActive=true;LastError.Empty();LastServicedUnit.Empty();RefreshRemainder=0;
    if(!RefreshDemand(Error)){Fail(Error);return false;}PumpRequests();return bActive;
}

void ULivingTownTileStreamingSubsystem::Stop(ALivingTownTileDriver* Owner)
{if(Driver.Get()==Owner)BeginStop();}

void ULivingTownTileStreamingSubsystem::BeginStop()
{
    bActive=false;++Epoch;Demand.Reset();ActiveSupports.Empty();Driver.Reset();
    TArray<FString> Ids;Requests.GetKeys(Ids);for(const auto& Id:Ids)BeginRetirement(Id);
    FinishDrainIfEmpty();
}

void ULivingTownTileStreamingSubsystem::FinishDrainIfEmpty()
{
    if(bActive||!Requests.IsEmpty()||!Installed.IsEmpty())return;
    if(IsValid(GeometryOwner.Get()))GeometryOwner->Destroy(); // no owned geometry remains
    GeometryOwner=nullptr;Root=nullptr;Driver.Reset();Catalog.Empty();Supports.Empty();PersistentUnits.Empty();FixtureInventory.Empty();ActiveSupports.Empty();VerifiedMeshes.Empty();CafeBindingSha256.Empty();RefreshRemainder=0;LastServicedUnit.Empty();
}

void ULivingTownTileStreamingSubsystem::TearDownAll()
{
    // World/subsystem teardown is the explicit synchronous exception. Ordinary
    // Stop, demand cancellation and failures never enter this component loop.
    bActive=false;++Epoch;Demand.Reset();
    for(auto& Pair:Installed)for(auto& Ref:Pair.Value.Components)if(auto* C=Ref.Get())
    {if(AActor* A=C->GetOwner())A->RemoveInstanceComponent(C);C->DestroyComponent();Ref=nullptr;}
    TArray<FString> Ids;Requests.GetKeys(Ids);for(const auto& Id:Ids)ReleaseUnit(Id);
    Installed.Empty();Requests.Empty();FinishDrainIfEmpty();
#if WITH_DEV_AUTOMATION_TESTS
    AutomationFactory=nullptr;
#endif
}

bool ULivingTownTileStreamingSubsystem::HasExposedComponents(const FLivingTownInstalledUnit& Unit) const
{
    for(const auto& Ref:Unit.Components)if(const auto* C=Ref.Get())
        if(C->IsRegistered()&&(C->GetCollisionEnabled()!=ECollisionEnabled::NoCollision||(C->GetVisibleFlag()&&!C->bHiddenInGame)))return true;
    return false;
}

void ULivingTownTileStreamingSubsystem::Fail(const FString& Error)
{
    LastError=Error;bActive=false;++Epoch;Demand.Reset();
    TArray<FString> Ids;Requests.GetKeys(Ids);
    for(const auto& Id:Ids)
    {
        auto* U=Installed.Find(Id);
        // Already exposed qualified components can support the player even
        // while a unit is only partly activated. Freeze them until Stop.
        if(U&&HasExposedComponents(*U)){Requests[Id].Phase=EPhase::Frozen;continue;}
        BeginRetirement(Id);
    }
    UE_LOG(LogTemp,Error,TEXT("Town pilot refused; exposed qualified geometry frozen, hidden work drains: %s"),*LastError);
    FinishDrainIfEmpty();
}

bool ULivingTownTileStreamingSubsystem::RetirementAllowed() const
{
    // Explicit stop/failure cleanup must drain without a live driver or focus.
    if(!bActive)return true;
    const auto* Owner=Driver.Get();if(!Owner||!Owner->ResolveFocus())return false;
    for(const auto& Pair:Demand.Counts())
    {const auto* R=Requests.Find(Pair.Key);if(!R||R->Phase!=EPhase::Resident)return false;}
    return true;
}

void ULivingTownTileStreamingSubsystem::BeginRetirement(const FString& Id)
{
    Demand.Cancel(Id);auto* R=Requests.Find(Id);if(!R)return;
    // Async lanes without any components can release immediately. Retained
    // installed handles are held until the last component is destroyed.
    auto* U=Installed.Find(Id);
    if(!U||U->Components.IsEmpty()){ReleaseUnit(Id);return;}
    if(R->Phase==EPhase::Retiring)return;
    if(R->Phase==EPhase::Data||R->Phase==EPhase::Meshes)
    {if(R->MeshHandle)R->MeshHandle->CancelHandle();}
    R->Phase=EPhase::Retiring;U->NextRetirement=0;U->RetirementStep=0;
}

bool ULivingTownTileStreamingSubsystem::ReconcileDemand(FString& Error)
{
    TArray<FString> Ids;Requests.GetKeys(Ids);
    for(const auto& Id:Ids)
    {
        auto* R=Requests.Find(Id);if(!R)continue;
        if(!Demand.Counts().Contains(Id)){BeginRetirement(Id);continue;}
        if(R->Phase==EPhase::Retiring)
        {
            auto* U=Installed.Find(Id);if(!U||!U->Data){Error=TEXT("tile_restore_data_lost");return false;}
            const uint64 Token=Demand.BeginRequest(Id);if(!Token){Error=TEXT("tile_restore_token");return false;}
            R->Token=Token;R->Phase=EPhase::QueuedRestore;U->NextGeometry=0;U->NextActivation=0;U->ActivationStep=0;U->bVisible=false;
        }
    }
    return true;
}

bool ULivingTownTileStreamingSubsystem::RefreshDemand(FString& Error)
{
    const auto* Owner=Driver.Get();if(!Owner){Error=TEXT("tile_driver_lost");return false;}
    const AActor* Focus=Owner->ResolveFocus();if(Focus&&Focus->GetActorLocation().ContainsNaN()){Error=TEXT("tile_focus_nonfinite");return false;}
    TSet<FString> Next;TMap<FString,TArray<FString>> Active;Active.Add(TEXT("persistent"),PersistentUnits);
    if(Focus)
    {
        const FVector P=Focus->GetActorLocation();for(const auto& S:Supports)
        {
            const double X=FMath::Clamp(P.X,S.MinNativeXYCm.X,S.MaxNativeXYCm.X),Y=FMath::Clamp(P.Y,S.MinNativeXYCm.Y,S.MaxNativeXYCm.Y);
            const double Radius=ActiveSupports.Contains(S.SupportId)?UnloadRadiusCm:LoadRadiusCm;
            if(FMath::Square(P.X-X)+FMath::Square(P.Y-Y)<=FMath::Square(Radius)){Next.Add(S.SupportId);Active.Add(S.SupportId,S.Units);}
        }
    }
    if(!Demand.SetSupports(Active,Error))return false;ActiveSupports=MoveTemp(Next);return ReconcileDemand(Error);
}

void ULivingTownTileStreamingSubsystem::PumpRequests()
{
    auto* Owner=Driver.Get();if(!bActive||!Owner)return;
    int32 ActiveCount=0;for(const auto& Pair:Requests)
        if(Pair.Value.Phase==EPhase::Data||Pair.Value.Phase==EPhase::Meshes||Pair.Value.Phase==EPhase::Installing||Pair.Value.Phase==EPhase::Activating)++ActiveCount;
    TArray<FString> Pending;
    for(const auto& Pair:Demand.Counts())
    {
        const auto* Existing=Requests.Find(Pair.Key);if(Existing&&Existing->Phase!=EPhase::QueuedRestore)continue;
        const auto* Ref=Catalog.Find(Pair.Key);if(!Ref){Fail(TEXT("tile_catalog_lost"));return;}
        bool Ready=true;for(const auto& D:Ref->Dependencies){const auto* R=Requests.Find(D);if(!R||R->Phase!=EPhase::Resident){Ready=false;break;}}
        if(Ready)Pending.Add(Pair.Key);
    }
    FVector Focus=FVector::ZeroVector;if(const auto* A=Owner->ResolveFocus())Focus=A->GetActorLocation();
    Pending.Sort([this,Focus](const FString& A,const FString& B){const double DA=Catalog[A].ActualNativeBoundsCm.ComputeSquaredDistanceToPoint(Focus),DB=Catalog[B].ActualNativeBoundsCm.ComputeSquaredDistanceToPoint(Focus);return DA==DB?A<B:DA<DB;});
    for(const auto& Id:Pending)
    {
        if(ActiveCount>=RequestBudget)break;
        if(auto* Restore=Requests.Find(Id))
        {
            ++ActiveCount;
#if WITH_DEV_AUTOMATION_TESTS
            if(IsAutomationWorld()){Restore->Phase=EPhase::Installing;continue;}
#endif
            // Reentry may follow cancellation during the mesh lane. Reissue a
            // fresh bounded request even when some surviving slots are loaded.
            RequestMeshes(Id,Epoch,Restore->Token);if(!bActive)return;continue;
        }
        const uint64 Token=Demand.BeginRequest(Id);if(!Token){Fail(TEXT("tile_request_token"));return;}
        FRequest R;R.Token=Token;Requests.Add(Id,MoveTemp(R));++ActiveCount;const uint64 RequestedEpoch=Epoch;
        const TWeakObjectPtr<ULivingTownTileStreamingSubsystem> Weak(this);TArray<FSoftObjectPath> Paths{Catalog[Id].Asset.ToSoftObjectPath()};
        auto H=UAssetManager::GetStreamableManager().RequestAsyncLoad(Paths,FStreamableDelegate::CreateLambda([Weak,Id,RequestedEpoch,Token](){if(auto* S=Weak.Get())S->OnData(Id,RequestedEpoch,Token);}),FStreamableManager::DefaultAsyncLoadPriority,false,false,TEXT("LivingTownPilotUnit"));
        if(!H){Fail(TEXT("tile_data_request_failed"));return;}if(auto* Current=Requests.Find(Id))Current->DataHandle=MoveTemp(H);
    }
}

bool ULivingTownTileStreamingSubsystem::AcceptCompletion(const FString& Id,uint64 RequestEpoch,uint64 Token) const
{
    const auto* R=Requests.Find(Id);
    return bActive&&Epoch==RequestEpoch&&GetWorld()&&Driver.IsValid()&&IsValid(GeometryOwner.Get())&&R&&R->Token==Token&&
        (R->Phase==EPhase::Data||R->Phase==EPhase::Meshes)&&Demand.Accepts(Id,Token);
}

void ULivingTownTileStreamingSubsystem::OnData(const FString& Id,uint64 RequestEpoch,uint64 Token)
{
    check(IsInGameThread());if(!AcceptCompletion(Id,RequestEpoch,Token)||Requests[Id].Phase!=EPhase::Data)return;
    const auto* Ref=Catalog.Find(Id);auto* Data=Ref?Ref->Asset.Get():nullptr;FString Error;
    if(!Ref||!Data||!LivingTownTiles::ValidateUnit(*Data,*Ref,Qualification,Error)){Fail(Error.IsEmpty()?TEXT("tile_data_unavailable"):Error);return;}
    for(const auto& F:Data->DeferredFixtures){const auto* E=FixtureInventory.Find(F.SourceGroupId);if(!E||E->SourcePlacementIds!=F.SourcePlacementIds||E->SourceMetadataSha256!=F.SourceMetadataSha256||E->SourceMetadataCanonicalUtf8!=F.SourceMetadataCanonicalUtf8){Fail(TEXT("tile_unit_fixture_metadata_differs_from_root_inventory"));return;}}
    FLivingTownInstalledUnit U;U.Data=Data;U.Components.SetNum(Data->Geometry.Num());Installed.Add(Id,MoveTemp(U));RequestMeshes(Id,RequestEpoch,Token);
}

void ULivingTownTileStreamingSubsystem::RequestMeshes(const FString& Id,uint64 RequestEpoch,uint64 Token)
{
    auto* R=Requests.Find(Id);const auto* U=Installed.Find(Id);
    if(!R||!U||!U->Data||!bActive||Epoch!=RequestEpoch||R->Token!=Token||!Demand.Accepts(Id,Token))return;
    if(R->MeshHandle){R->MeshHandle->CancelHandle();R->MeshHandle.Reset();}
    TArray<FSoftObjectPath> Paths;for(const auto& G:U->Data->Geometry)Paths.AddUnique(G.Mesh.ToSoftObjectPath());
    R->Phase=EPhase::Meshes;const TWeakObjectPtr<ULivingTownTileStreamingSubsystem> Weak(this);
    auto H=UAssetManager::GetStreamableManager().RequestAsyncLoad(Paths,FStreamableDelegate::CreateLambda([Weak,Id,RequestEpoch,Token](){if(auto* S=Weak.Get())S->OnMeshes(Id,RequestEpoch,Token);}),FStreamableManager::DefaultAsyncLoadPriority,false,false,TEXT("LivingTownPilotGeometry"));
    if(!H){Fail(TEXT("tile_mesh_request_failed"));return;}if(auto* Current=Requests.Find(Id))Current->MeshHandle=MoveTemp(H);
}

void ULivingTownTileStreamingSubsystem::OnMeshes(const FString& Id,uint64 RequestEpoch,uint64 Token)
{check(IsInGameThread());if(!AcceptCompletion(Id,RequestEpoch,Token)||Requests[Id].Phase!=EPhase::Meshes)return;Requests[Id].Phase=EPhase::Installing;}

// The native hash/material/collision identity inspector below remains byte-exact
// to9c2. Lifecycle work does not weaken imported-asset qualification.
bool ULivingTownTileStreamingSubsystem::ValidateLoadedGeometry(const FLivingTownTileGeometry& G,UStaticMesh* Mesh,bool& bWaiting,FString& Error)
{
    bWaiting=false;
    if(!Mesh||!Mesh->bAllowCPUAccess||!Mesh->GetBodySetup())
    {Error=TEXT("tile_native_CPU_readback_or_body_unavailable");return false;}
    const FString Key=G.Mesh.ToSoftObjectPath().ToString();
    const FString BodyGuid=Mesh->GetBodySetup()->BodySetupGuid.ToString(EGuidFormats::Digits).ToLower();
    if(BodyGuid!=G.NativeCollisionGuid){Error=TEXT("tile_native_collision_GUID_mismatch");return false;}
    FVerifiedMesh Observed;Observed.Mesh=Mesh;Observed.LightingGuid=Mesh->GetLightingGuid();
    for(const FStaticMaterial& Slot:Mesh->GetStaticMaterials())
    {
        const UMaterialInterface* Material=Slot.MaterialInterface.Get();
        if(!Material){Error=TEXT("tile_native_material_missing");return false;}
        Observed.MaterialPaths.Add(FSoftObjectPath(Material));
        Observed.MaterialSlotNames.Add(Slot.MaterialSlotName.ToString());
        Observed.MaterialBlendModes.Add(uint8(Material->GetBlendMode()));
    }
    if(Observed.MaterialPaths!=G.QualifiedMaterialPaths||Observed.MaterialSlotNames!=G.QualifiedMaterialSlotNames||
        Observed.MaterialBlendModes!=G.QualifiedMaterialBlendModes)
    {Error=TEXT("tile_native_material_slot_path_name_or_mode_mismatch");return false;}
    const FVerifiedMesh* Cached=VerifiedMeshes.Find(Key);
    if(Cached&&Cached->Mesh.Get()==Mesh&&Cached->LightingGuid==Observed.LightingGuid&&Cached->CollisionGuid==BodyGuid&&
        Cached->MaterialPaths==Observed.MaterialPaths&&Cached->MaterialSlotNames==Observed.MaterialSlotNames&&Cached->MaterialBlendModes==Observed.MaterialBlendModes)
    {
        if(Cached->RenderSha256!=G.NativeRenderSha256){Error=TEXT("tile_native_cached_full_render_hash_mismatch");return false;}
        return true;
    }
    if(bVerifiedMeshThisFrame){bWaiting=true;return true;}
    FString Why;
    if(!ULivingTownCafeGeometryLibrary::InspectCafeMesh(Mesh,Observed.RenderSha256,Observed.CollisionGuid,Why)||
        Observed.RenderSha256!=G.NativeRenderSha256||Observed.CollisionGuid!=G.NativeCollisionGuid)
    {Error=TEXT("tile_native_full_mesh_identity_mismatch: ")+Why;return false;}
    bVerifiedMeshThisFrame=true;VerifiedMeshes.Add(Key,MoveTemp(Observed));return true;
}

bool ULivingTownTileStreamingSubsystem::CreateOne(const FString& Id,FLivingTownInstalledUnit& Unit,bool& bWaiting,FString& Error)
{
    bWaiting=false;
    if(!IsValid(GeometryOwner.Get())||!Unit.Data||!Unit.Data->Geometry.IsValidIndex(Unit.NextGeometry)||!Unit.Components.IsValidIndex(Unit.NextGeometry))
    {Error=TEXT("tile_install_cursor_or_geometry_owner");return false;}
    const auto& G=Unit.Data->Geometry[Unit.NextGeometry];UPrimitiveComponent* Component=nullptr;
#if WITH_DEV_AUTOMATION_TESTS
    if(IsAutomationWorld())Component=AutomationFactory(GeometryOwner.Get(),Id,Unit.NextGeometry);
    else
#endif
    {
        UStaticMesh* Mesh=G.Mesh.Get();if(!Mesh){Error=TEXT("tile_mesh_load_failed");return false;}
#if WITH_EDITOR
        if(Mesh->IsCompiling()){bWaiting=true;return true;}
#endif
        if(!ValidateLoadedGeometry(G,Mesh,bWaiting,Error))return false;if(bWaiting)return true;
        if(G.Kind==ELivingTownTileEntryKind::Instanced)
        {
            auto* ISM=NewObject<UInstancedStaticMeshComponent>(GeometryOwner.Get());Component=ISM;Unit.Components[Unit.NextGeometry]=ISM;
            if(!ISM->SetStaticMesh(Mesh)){Error=TEXT("tile_set_instanced_mesh");return false;}
            TArray<FTransform> Transforms;for(const auto& P:G.Placements)Transforms.Add(P.QualifiedNativeTransform);
            ISM->AddInstances(Transforms,false,false,false);
            if(ISM->GetInstanceCount()!=Transforms.Num()){Error=TEXT("tile_instance_count");return false;}
        }
        else
        {
            auto* Static=NewObject<UStaticMeshComponent>(GeometryOwner.Get());Component=Static;Unit.Components[Unit.NextGeometry]=Static;
            if(!Static->SetStaticMesh(Mesh)){Error=TEXT("tile_set_static_mesh");return false;}
            Static->SetRelativeTransform(G.Placements[0].QualifiedNativeTransform);
        }
    }
    if(!Component||Component->GetOwner()!=GeometryOwner.Get()||Component->IsRegistered())
    {Error=TEXT("tile_new_owned_unregistered_component_required");return false;}
    Component->SetMobility(EComponentMobility::Static);Component->PrimaryComponentTick.bCanEverTick=false;Component->SetComponentTickEnabled(false);
    Component->SetCanEverAffectNavigation(false);Component->SetGenerateOverlapEvents(false);
    // Initial unregistered configuration is part of this one registration op;
    // no registered component is toggled in these setup calls.
    Component->SetCollisionProfileName(TEXT("BlockAll"));Component->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    Component->SetVisibility(false,true);Component->SetHiddenInGame(true);Component->ComponentTags.Add(FName(*Id));Component->ComponentTags.Add(FName(*G.EntryId));
    if(G.Kind==ELivingTownTileEntryKind::DeferredDoor)Component->ComponentTags.Add(TEXT("Town.DeferredDoor.NoBehavior"));
    GeometryOwner->AddInstanceComponent(Component);Unit.Components[Unit.NextGeometry]=Component;Component->RegisterComponent();
    if(!Component->IsRegistered()){Error=TEXT("tile_component_registration");return false;}
    ++Unit.NextGeometry;++LastFrame.Registrations;return true;
}

bool ULivingTownTileStreamingSubsystem::AdvanceOne(const FString& Id,bool& bOperated,bool& bProgressed,FString& Error)
{
    bOperated=false;bProgressed=false;auto* R=Requests.Find(Id);auto* U=Installed.Find(Id);
    if(!R||!U||!U->Data)return true;
    if(R->Phase==EPhase::Installing)
    {
        while(U->NextGeometry<U->Components.Num()&&IsValid(U->Components[U->NextGeometry].Get()))++U->NextGeometry;
        if(U->NextGeometry==U->Components.Num())
        {R->Phase=EPhase::Activating;U->NextActivation=0;U->ActivationStep=0;bProgressed=true;return true;}
        bool Waiting=false;if(!CreateOne(Id,*U,Waiting,Error))return false;bOperated=!Waiting;bProgressed=bOperated;return true;
    }
    if(R->Phase==EPhase::Activating)
    {
        while(U->NextActivation<U->Components.Num())
        {
            auto* C=U->Components[U->NextActivation].Get();if(!IsValid(C)||!C->IsRegistered()){Error=TEXT("tile_activation_component_lost");return false;}
            const auto Desired=U->Data->Geometry[U->NextActivation].bBlockingCollision?ECollisionEnabled::QueryAndPhysics:ECollisionEnabled::NoCollision;
            if(U->ActivationStep==0)
            {
                U->ActivationStep=1;
                if(C->GetCollisionEnabled()!=Desired)
                {C->SetCollisionEnabled(Desired);++LastFrame.CollisionTransitions;bOperated=bProgressed=true;return true;}
            }
            // Enable supporting collision first; reveal in a separately charged
            // component operation. Two visibility flags are one atomic policy.
            if(!C->GetVisibleFlag()||C->bHiddenInGame)
            {C->SetVisibility(true,true);C->SetHiddenInGame(false);++U->NextActivation;U->ActivationStep=0;++LastFrame.VisibilityTransitions;bOperated=bProgressed=true;return true;}
            ++U->NextActivation;U->ActivationStep=0;
        }
        U->bVisible=true;R->Phase=EPhase::Resident;bProgressed=true;return true;
    }
    if(R->Phase==EPhase::Retiring)
    {
        if(!RetirementAllowed())return true;
        while(U->NextRetirement<U->Components.Num())
        {
            auto* C=U->Components[U->NextRetirement].Get();
            if(!IsValid(C)){U->Components[U->NextRetirement]=nullptr;++U->NextRetirement;U->RetirementStep=0;continue;}
            if(U->RetirementStep==0)
            {
                U->RetirementStep=1;
                if(C->GetCollisionEnabled()!=ECollisionEnabled::NoCollision)
                {C->SetCollisionEnabled(ECollisionEnabled::NoCollision);++LastFrame.CollisionTransitions;bOperated=bProgressed=true;return true;}
            }
            if(U->RetirementStep==1)
            {
                U->RetirementStep=2;
                if(C->GetVisibleFlag()||!C->bHiddenInGame)
                {C->SetVisibility(false,true);C->SetHiddenInGame(true);U->bVisible=false;++LastFrame.VisibilityTransitions;bOperated=bProgressed=true;return true;}
            }
            if(AActor* Owner=C->GetOwner())Owner->RemoveInstanceComponent(C);C->DestroyComponent();U->Components[U->NextRetirement]=nullptr;
            ++U->NextRetirement;U->RetirementStep=0;++LastFrame.Destructions;bOperated=bProgressed=true;return true;
        }
        ReleaseUnit(Id);bProgressed=true;return true;
    }
    return true;
}

void ULivingTownTileStreamingSubsystem::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);LastFrame={};bVerifiedMeshThisFrame=false;
    if(!bActive)
    {
        // A frozen safety cohort still owns resources. Poll driver lifetime
        // even if EndPlay did not call Stop (for example before BeginPlay).
        const auto* Owner=Driver.Get();
        if(!Requests.IsEmpty()&&(!Owner||Owner->IsActorBeingDestroyed()))BeginStop();
        if(!HasRetiringWork())return;
    }
    if(bActive)
    {
        const auto* Owner=Driver.Get();
        if(!Owner||Owner->IsActorBeingDestroyed())BeginStop();
        else if(!ParentAndCafeStillQualified())Fail(TEXT("tile_parent_or_cafe_qualification_lost"));
    }
    if(bActive)
    {
        RefreshRemainder+=DeltaSeconds;FString Error;
#if WITH_DEV_AUTOMATION_TESTS
        const bool bRefresh=!IsAutomationWorld();
#else
        constexpr bool bRefresh=true;
#endif
        if(bRefresh&&RefreshRemainder>=0.25){RefreshRemainder=0;if(!RefreshDemand(Error))Fail(Error);}
        if(bActive)PumpRequests();
    }
    int32 Budget=ComponentOperationBudget;TSet<FString> Blocked;
    while(Budget>0)
    {
        TArray<FString> Keys;Requests.GetKeys(Keys);Keys.Sort();if(Keys.IsEmpty())break;
        int32 Start=0;for(int32 I=0;I<Keys.Num();++I)if(Keys[I]<=LastServicedUnit)Start=I+1;Start%=Keys.Num();
        bool Progress=false;
        for(int32 I=0;I<Keys.Num();++I)
        {
            const FString Id=Keys[(Start+I)%Keys.Num()];if(Blocked.Contains(Id))continue;
            bool Operated=false,Advanced=false;FString Error;
            if(!AdvanceOne(Id,Operated,Advanced,Error)){Fail(Error);Blocked.Add(Id);continue;}
            if(Operated){--Budget;LastServicedUnit=Id;Progress=true;break;}
            if(Advanced){Progress=true;break;}Blocked.Add(Id);
        }
        if(!Progress)break;
    }
    check(LastFrame.Total()<=ComponentOperationBudget);
    if(bActive)PumpRequests();FinishDrainIfEmpty();
}

void ULivingTownTileStreamingSubsystem::ReleaseUnit(const FString& Id)
{
    Demand.Cancel(Id);
    if(auto* U=Installed.Find(Id))
    {
        for(const auto& C:U->Components)check(!IsValid(C.Get()));
        if(U->Data)for(const auto& G:U->Data->Geometry)VerifiedMeshes.Remove(G.Mesh.ToSoftObjectPath().ToString());
    }
    Installed.Remove(Id);
    if(auto* R=Requests.Find(Id))
    {
        if(R->MeshHandle){R->MeshHandle->CancelHandle();R->MeshHandle.Reset();}
        if(R->DataHandle){R->DataHandle->CancelHandle();R->DataHandle.Reset();}
    }
    Requests.Remove(Id);
}

const UPrimitiveComponent* ULivingTownTileStreamingSubsystem::FindDeferredDoorComponent(const FString& EntryId) const
{
    for(const auto& Pair:Installed)
    {
        const auto& U=Pair.Value;if(!U.Data)continue;
        for(int32 I=0;I<U.Data->Geometry.Num();++I)
            if(U.Data->Geometry[I].Kind==ELivingTownTileEntryKind::DeferredDoor&&U.Data->Geometry[I].EntryId==EntryId&&U.Components.IsValidIndex(I))
                if(const auto* C=U.Components[I].Get())if(C->GetVisibleFlag()&&!C->bHiddenInGame)return C;
    }
    return nullptr;
}

