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
#include "PhysicsEngine/BodySetup.h"
#include "Materials/MaterialInterface.h"
#include "UObject/UObjectGlobals.h"

bool ULivingTownTileStreamingSubsystem::DoesSupportWorldType(EWorldType::Type Type) const
{return Type==EWorldType::Game||Type==EWorldType::PIE;}

TStatId ULivingTownTileStreamingSubsystem::GetStatId() const
{RETURN_QUICK_DECLARE_CYCLE_STAT(ULivingTownTileStreamingSubsystem,STATGROUP_Tickables);}

bool ULivingTownTileStreamingSubsystem::IsTickable() const
{return bActive && !IsTemplate() && IsInitialized();}

void ULivingTownTileStreamingSubsystem::Deinitialize()
{StopAll();Super::Deinitialize();}

bool ULivingTownTileStreamingSubsystem::ParentAndCafeStillQualified() const
{
    const auto* Owner=Driver.Get();
    const auto* Cafe=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeProjectionSubsystem>():nullptr;
    return Owner && !Owner->IsActorBeingDestroyed() && Owner->IsIdentityPlacement() && Cafe &&
        Cafe->IsScenePrepared() && Cafe->IsReady() && Cafe->GetBinding().BindingFileSha256==CafeBindingSha256;
}

bool ULivingTownTileStreamingSubsystem::StartQualified(ALivingTownTileDriver* Owner,ULivingTownTileRootData* Candidate,FString& Error)
{
    if(!IsInGameThread()||!Owner||!Candidate||Owner->GetWorld()!=GetWorld()||!Owner->bEnableQualifiedPilot||
        !Owner->IsIdentityPlacement()||(Driver.IsValid()&&Driver.Get()!=Owner))
    {Error=TEXT("tile_driver_world_owner_or_placement");return false;}
    if(!FMath::IsFinite(Owner->LoadRadiusCm)||!FMath::IsFinite(Owner->UnloadRadiusCm)||
        Owner->LoadRadiusCm<0||Owner->LoadRadiusCm>20000||Owner->UnloadRadiusCm<Owner->LoadRadiusCm||
        Owner->UnloadRadiusCm>20000||Owner->MaxConcurrentRequests<1||Owner->MaxConcurrentRequests>2||
        Owner->ComponentsPerFrame<1||Owner->ComponentsPerFrame>4)
    {Error=TEXT("tile_driver_budget_or_radius");return false;}
    if(!LivingTownTiles::ValidateRoot(*Candidate,Error)) return false;
    auto* Cafe=GetWorld()->GetSubsystem<ULivingTownCafeProjectionSubsystem>();
    if(!Cafe||!Cafe->IsScenePrepared()||!Cafe->IsReady()||Cafe->GetBinding().BindingFileSha256!=Candidate->ExistingCafeBindingSha256)
    {Error=TEXT("tile_existing_native_cafe_not_qualified");return false;}
    FLivingTownTileDemand CandidateDemand;
    if(!CandidateDemand.Initialize(Candidate->Units,Error)) return false;
    StopAll();Root=Candidate;Driver=Owner;Qualification=Candidate->Qualification;
    RequestBudget=Owner->MaxConcurrentRequests;CreationBudget=Owner->ComponentsPerFrame;
    LoadRadiusCm=Owner->LoadRadiusCm;UnloadRadiusCm=Owner->UnloadRadiusCm;
    Supports=Candidate->Supports;PersistentUnits=Candidate->PersistentUnits;CafeBindingSha256=Candidate->ExistingCafeBindingSha256;
    for(const auto& Ref:Candidate->Units) Catalog.Add(Ref.UnitId,Ref);
    for(const auto& Fixture:Candidate->SourceFixtureInventory) FixtureInventory.Add(Fixture.SourceGroupId,Fixture);
    if(!Demand.Initialize(Candidate->Units,Error)){StopAll();return false;}
    bActive=true;LastError.Empty();RefreshRemainder=0;
    if(!RefreshDemand(Error)){Fail(Error);return false;}
    PumpRequests();return bActive;
}

void ULivingTownTileStreamingSubsystem::Stop(ALivingTownTileDriver* Owner)
{if(Driver.Get()==Owner) StopAll();}

void ULivingTownTileStreamingSubsystem::StopAll()
{
    bActive=false;++Epoch;Demand.Reset();
    TArray<FString> Ids;Requests.GetKeys(Ids);
    for(const FString& Id:Ids) Unload(Id);
    Installed.Empty();Requests.Empty();Catalog.Empty();Supports.Empty();PersistentUnits.Empty();FixtureInventory.Empty();ActiveSupports.Empty();
    VerifiedMeshes.Empty();
    Root=nullptr;Driver.Reset();CafeBindingSha256.Empty();RefreshRemainder=0;
}

void ULivingTownTileStreamingSubsystem::Fail(const FString& Error)
{
    LastError=Error;bActive=false;++Epoch;Demand.Reset();
    // A failed incoming tile must not remove an already visible qualified floor
    // underneath the player. Freeze resident units until explicit stop/teardown.
    TArray<FString> Cancel;
    for(const auto& Pair:Requests) if(Pair.Value.Phase!=EPhase::Resident) Cancel.Add(Pair.Key);
    for(const FString& Id:Cancel) Unload(Id);
    UE_LOG(LogTemp,Error,TEXT("Town pilot streaming refused; resident units retained: %s"),*LastError);
}

bool ULivingTownTileStreamingSubsystem::RefreshDemand(FString& Error)
{
    const auto* Owner=Driver.Get();
    if(!Owner){Error=TEXT("tile_driver_lost");return false;}
    const AActor* Focus=Owner->ResolveFocus();
    if(Focus&&Focus->GetActorLocation().ContainsNaN()){Error=TEXT("tile_focus_nonfinite");return false;}
    TSet<FString> Next;
    TMap<FString,TArray<FString>> Active;
    Active.Add(TEXT("persistent"),PersistentUnits);
    if(Focus)
    {
        const FVector Position=Focus->GetActorLocation();
        for(const auto& Support:Supports)
        {
            const double X=FMath::Clamp(Position.X,Support.MinNativeXYCm.X,Support.MaxNativeXYCm.X);
            const double Y=FMath::Clamp(Position.Y,Support.MinNativeXYCm.Y,Support.MaxNativeXYCm.Y);
            const double DistSq=FMath::Square(Position.X-X)+FMath::Square(Position.Y-Y);
            const double Radius=ActiveSupports.Contains(Support.SupportId)?UnloadRadiusCm:LoadRadiusCm;
            if(DistSq<=FMath::Square(Radius)){Next.Add(Support.SupportId);Active.Add(Support.SupportId,Support.Units);}
        }
    }
    if(!Demand.SetSupports(Active,Error)) return false;
    ActiveSupports=MoveTemp(Next);
    TArray<FString> Remove;
    for(const auto& Pair:Requests) if(!Demand.Counts().Contains(Pair.Key)) Remove.Add(Pair.Key);
    for(const FString& Id:Remove) Unload(Id);
    return true;
}

void ULivingTownTileStreamingSubsystem::PumpRequests()
{
    auto* Owner=Driver.Get();if(!bActive||!Owner) return;
    int32 ActiveCount=0;
    for(const auto& Pair:Requests) if(Pair.Value.Phase!=EPhase::Resident) ++ActiveCount;
    TArray<FString> Pending;
    for(const auto& Pair:Demand.Counts())
    {
        if(Requests.Contains(Pair.Key)) continue;
        const auto* Ref=Catalog.Find(Pair.Key);if(!Ref){Fail(TEXT("tile_catalog_lost"));return;}
        // Load leaves first. This also bounds ready-but-not-installed units and
        // avoids filling both lanes with parents awaiting unloaded dependencies.
        bool bDependenciesResident=true;
        for(const FString& Dependency:Ref->Dependencies)
        {const auto* Found=Requests.Find(Dependency);if(!Found||Found->Phase!=EPhase::Resident){bDependenciesResident=false;break;}}
        if(bDependenciesResident) Pending.Add(Pair.Key);
    }
    FVector Focus=FVector::ZeroVector;if(const AActor* Actor=Owner->ResolveFocus()) Focus=Actor->GetActorLocation();
    Pending.Sort([this,Focus](const FString& A,const FString& B)
    {
        const double DA=Catalog[A].ActualNativeBoundsCm.ComputeSquaredDistanceToPoint(Focus);
        const double DB=Catalog[B].ActualNativeBoundsCm.ComputeSquaredDistanceToPoint(Focus);
        return DA==DB?A<B:DA<DB;
    });
    for(const FString& Id:Pending)
    {
        if(ActiveCount>=RequestBudget) break;
        const uint64 Token=Demand.BeginRequest(Id);if(!Token){Fail(TEXT("tile_request_token"));return;}
        FRequest Request;Request.Token=Token;Requests.Add(Id,MoveTemp(Request));++ActiveCount;
        const uint64 RequestedEpoch=Epoch;
        const TWeakObjectPtr<ULivingTownTileStreamingSubsystem> WeakThis(this);
        TArray<FSoftObjectPath> Paths{Catalog[Id].Asset.ToSoftObjectPath()};
        auto Handle=UAssetManager::GetStreamableManager().RequestAsyncLoad(Paths,FStreamableDelegate::CreateLambda([WeakThis,Id,RequestedEpoch,Token]()
        {if(auto* Self=WeakThis.Get()) Self->OnData(Id,RequestedEpoch,Token);}),FStreamableManager::DefaultAsyncLoadPriority,false,false,TEXT("LivingTownPilotUnit"));
        if(!Handle){Fail(TEXT("tile_data_request_failed"));return;}
        if(auto* Current=Requests.Find(Id)) Current->DataHandle=MoveTemp(Handle);
    }
}

bool ULivingTownTileStreamingSubsystem::AcceptCompletion(const FString& Id,uint64 RequestEpoch,uint64 Token) const
{
    return bActive&&Epoch==RequestEpoch&&GetWorld()&&Driver.IsValid()&&Requests.Contains(Id)&&Demand.Accepts(Id,Token);
}

void ULivingTownTileStreamingSubsystem::OnData(const FString& Id,uint64 RequestEpoch,uint64 Token)
{
    check(IsInGameThread());if(!AcceptCompletion(Id,RequestEpoch,Token)) return;
    const auto* Ref=Catalog.Find(Id);
    auto* Data=Ref?Ref->Asset.Get():nullptr;FString Error;
    if(!Ref||!Data||!LivingTownTiles::ValidateUnit(*Data,*Ref,Qualification,Error))
    {Fail(Error.IsEmpty()?TEXT("tile_data_unavailable"):Error);return;}
    for(const auto& Fixture:Data->DeferredFixtures)
    {
        const auto* Expected=FixtureInventory.Find(Fixture.SourceGroupId);
        if(!Expected||Expected->SourcePlacementIds!=Fixture.SourcePlacementIds||Expected->SourceMetadataSha256!=Fixture.SourceMetadataSha256||
            Expected->SourceMetadataCanonicalUtf8!=Fixture.SourceMetadataCanonicalUtf8)
        {Fail(TEXT("tile_unit_fixture_metadata_differs_from_root_inventory"));return;}
    }
    FLivingTownInstalledUnit Unit;Unit.Data=Data;Installed.Add(Id,MoveTemp(Unit));
    TArray<FSoftObjectPath> Paths;
    for(const auto& Geometry:Data->Geometry) Paths.AddUnique(Geometry.Mesh.ToSoftObjectPath());
    Requests[Id].Phase=EPhase::Meshes;
    const TWeakObjectPtr<ULivingTownTileStreamingSubsystem> WeakThis(this);
    auto Handle=UAssetManager::GetStreamableManager().RequestAsyncLoad(Paths,FStreamableDelegate::CreateLambda([WeakThis,Id,RequestEpoch,Token]()
    {if(auto* Self=WeakThis.Get()) Self->OnMeshes(Id,RequestEpoch,Token);}),FStreamableManager::DefaultAsyncLoadPriority,false,false,TEXT("LivingTownPilotGeometry"));
    if(!Handle){Fail(TEXT("tile_mesh_request_failed"));return;}
    if(auto* Current=Requests.Find(Id)) Current->MeshHandle=MoveTemp(Handle);
}

void ULivingTownTileStreamingSubsystem::OnMeshes(const FString& Id,uint64 RequestEpoch,uint64 Token)
{
    check(IsInGameThread());if(!AcceptCompletion(Id,RequestEpoch,Token)) return;
    Requests[Id].Phase=EPhase::Installing;
}

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
    auto* Owner=Driver.Get();
    if(!Owner||!Unit.Data||!Unit.Data->Geometry.IsValidIndex(Unit.NextGeometry)){Error=TEXT("tile_install_cursor");return false;}
    const auto& Geometry=Unit.Data->Geometry[Unit.NextGeometry];
    UStaticMesh* Mesh=Geometry.Mesh.Get();
    if(!Mesh){Error=TEXT("tile_mesh_load_failed");return false;}
#if WITH_EDITOR
    if(Mesh->IsCompiling()){bWaiting=true;return true;}
#endif
    if(!ValidateLoadedGeometry(Geometry,Mesh,bWaiting,Error)) return false;
    if(bWaiting) return true;
    if(Geometry.bBlockingCollision&&!Mesh->GetBodySetup()){Error=TEXT("tile_qualified_body_setup_missing");return false;}
    UStaticMeshComponent* Component=nullptr;
    if(Geometry.Kind==ELivingTownTileEntryKind::Instanced)
    {
        auto* ISM=NewObject<UInstancedStaticMeshComponent>(Owner);Component=ISM;
        if(!ISM->SetStaticMesh(Mesh)){ISM->DestroyComponent();Error=TEXT("tile_set_instanced_mesh");return false;}
        TArray<FTransform> Transforms;Transforms.Reserve(Geometry.Placements.Num());
        for(const auto& Placement:Geometry.Placements) Transforms.Add(Placement.QualifiedNativeTransform);
        ISM->AddInstances(Transforms,false,false,false);
        if(ISM->GetInstanceCount()!=Transforms.Num()){ISM->DestroyComponent();Error=TEXT("tile_instance_count");return false;}
    }
    else
    {
        Component=NewObject<UStaticMeshComponent>(Owner);
        if(!Component->SetStaticMesh(Mesh)){Component->DestroyComponent();Error=TEXT("tile_set_static_mesh");return false;}
        Component->SetRelativeTransform(Geometry.Placements[0].QualifiedNativeTransform);
    }
    Component->SetMobility(EComponentMobility::Static);
    Component->SetupAttachment(Owner->GetRootComponent());
    Component->PrimaryComponentTick.bCanEverTick=false;Component->SetComponentTickEnabled(false);
    Component->SetCanEverAffectNavigation(false);Component->SetGenerateOverlapEvents(false);
    Component->SetCollisionProfileName(TEXT("BlockAll"));Component->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    Component->SetVisibility(false,true);Component->SetHiddenInGame(true);
    Component->ComponentTags.Add(FName(*Id));Component->ComponentTags.Add(FName(*Geometry.EntryId));
    if(Geometry.Kind==ELivingTownTileEntryKind::DeferredDoor) Component->ComponentTags.Add(FName(TEXT("Town.DeferredDoor.NoBehavior")));
    Owner->AddInstanceComponent(Component);Unit.Components.Add(Component);
    Component->RegisterComponent();
    if(!Component->IsRegistered()){Error=TEXT("tile_component_registration");return false;}
    ++Unit.NextGeometry;return true;
}

void ULivingTownTileStreamingSubsystem::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);if(!bActive) return;
    bVerifiedMeshThisFrame=false;
    if(!ParentAndCafeStillQualified()){Fail(TEXT("tile_parent_or_cafe_qualification_lost"));return;}
    RefreshRemainder+=DeltaSeconds;FString Error;
    if(RefreshRemainder>=0.25){RefreshRemainder=0;if(!RefreshDemand(Error)){Fail(Error);return;}}
    int32 Budget=CreationBudget;
    TArray<FString> Keys;Requests.GetKeys(Keys);Keys.Sort();
    for(const FString& Id:Keys)
    {
        auto* Request=Requests.Find(Id);auto* Unit=Installed.Find(Id);
        if(!Request||Request->Phase!=EPhase::Installing||!Unit||!Unit->Data) continue;
        while(Budget>0&&Unit->NextGeometry<Unit->Data->Geometry.Num())
        {
            bool bWaiting=false;
            if(!CreateOne(Id,*Unit,bWaiting,Error)){Fail(Error);return;}
            if(bWaiting) break;
            --Budget;
        }
        if(Unit->NextGeometry==Unit->Data->Geometry.Num())
        {
            // Every dependency was resident before this request began. Demand
            // closure keeps it resident for the whole unit lifetime.
            for(int32 I=0;I<Unit->Components.Num();++I)
            {
                auto* Component=Unit->Components[I].Get();
                Component->SetVisibility(true,true);Component->SetHiddenInGame(false);
                Component->SetCollisionEnabled(Unit->Data->Geometry[I].bBlockingCollision?ECollisionEnabled::QueryAndPhysics:ECollisionEnabled::NoCollision);
            }
            Unit->bVisible=true;Request->Phase=EPhase::Resident;
        }
        if(Budget==0) break;
    }
    PumpRequests();
}

void ULivingTownTileStreamingSubsystem::Unload(const FString& Id)
{
    Demand.Cancel(Id);
    if(auto* Unit=Installed.Find(Id))
    {
        // Conservative release invalidation: even when another unit still owns
        // this asset, the next installation rechecks its full native identity.
        if(Unit->Data) for(const auto& G:Unit->Data->Geometry) VerifiedMeshes.Remove(G.Mesh.ToSoftObjectPath().ToString());
        for(const auto& Reference:Unit->Components) if(auto* Component=Reference.Get())
        {if(AActor* Owner=Component->GetOwner()) Owner->RemoveInstanceComponent(Component);Component->DestroyComponent();}
    }
    Installed.Remove(Id);
    if(auto* Request=Requests.Find(Id))
    {
        if(Request->MeshHandle){Request->MeshHandle->CancelHandle();Request->MeshHandle.Reset();}
        if(Request->DataHandle){Request->DataHandle->CancelHandle();Request->DataHandle.Reset();}
    }
    Requests.Remove(Id);
}

const UPrimitiveComponent* ULivingTownTileStreamingSubsystem::FindDeferredDoorComponent(const FString& EntryId) const
{
    for(const auto& Pair:Installed)
    {
        const auto& Unit=Pair.Value;if(!Unit.bVisible||!Unit.Data) continue;
        for(int32 I=0;I<Unit.Data->Geometry.Num();++I)
            if(Unit.Data->Geometry[I].Kind==ELivingTownTileEntryKind::DeferredDoor&&Unit.Data->Geometry[I].EntryId==EntryId)
                return Unit.Components.IsValidIndex(I)?Unit.Components[I].Get():nullptr;
    }
    return nullptr;
}
