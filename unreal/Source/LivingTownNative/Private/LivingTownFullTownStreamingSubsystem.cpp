#include "LivingTownFullTownStreamingSubsystem.h"
#include "LivingTownFullTownDriver.h"
#include "LivingTownTileDriver.h"
#include "LivingTownTileData.h"
#include "LivingTownMaterialUsage.h"
#include "LivingTownCafeGameMode.h"
#include "LivingTownCafeProjectionSubsystem.h"
#include "LivingTownCafeVenue.h"
#include "LivingTownCafeCharacter.h"
#include "Components/CapsuleComponent.h"
#include "Components/HierarchicalInstancedStaticMeshComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/AssetManager.h"
#include "Engine/Level.h"
#include "Engine/StaticMesh.h"
#include "Engine/StreamableManager.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/PlayerController.h"
#include "HAL/PlatformProperties.h"
#include "HAL/PlatformTime.h"
#include "HAL/FileManager.h"
#include "Materials/MaterialInterface.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Serialization/JsonSerializer.h"
#include "Dom/JsonObject.h"
#include "CoreGlobals.h"
#include "UObject/Package.h"

namespace
{
bool Refuse(FString& Error,const FString& Why) { Error=Why; return false; }
bool BaseActor(const AActor* A)
{
    const FString P=A->GetClass()->GetPathName();
    return P==TEXT("/Script/Engine.WorldSettings") || P==TEXT("/Script/Engine.Brush") ||
        P==TEXT("/Script/Engine.LevelScriptActor") || P==TEXT("/Script/Engine.DefaultPhysicsVolume");
}
}

bool ULivingTownFullTownTicket::Accepts(uint64 CurrentEpoch,uint64 CurrentToken) const
{ return !bCancelled && Phase!=ELivingTownFullTownPhase::Removed && Epoch==CurrentEpoch && Token==CurrentToken; }
bool ULivingTownFullTownTicket::ReservesTransition() const
{ return Phase!=ELivingTownFullTownPhase::Resident && Phase!=ELivingTownFullTownPhase::Removed; }
void ULivingTownFullTownTicket::MarkCancelled() { bCancelled=true; }
void ULivingTownFullTownTicket::ObserveLoaded() { bLoadedEvent=true; }
void ULivingTownFullTownTicket::ObserveShown() { bShownEvent=true; }
void ULivingTownFullTownTicket::ObserveHidden() { bHiddenEvent=true; }
void ULivingTownFullTownTicket::ObserveUnloaded() { bUnloadedEvent=true; }

bool ULivingTownFullTownStreamingSubsystem::DoesSupportWorldType(EWorldType::Type T) const
{ return T==EWorldType::Game || T==EWorldType::PIE; }
bool ULivingTownFullTownStreamingSubsystem::IsTickable() const
{ return bArmed && !bWorldEnding && !IsTemplate() && IsInitialized(); }
TStatId ULivingTownFullTownStreamingSubsystem::GetStatId() const
{ RETURN_QUICK_DECLARE_CYCLE_STAT(ULivingTownFullTownStreamingSubsystem,STATGROUP_Tickables); }

bool ULivingTownFullTownStreamingSubsystem::LockMovementBeforeGameMode(UWorld& W,FString& Error)
{
    int32 Count=0; APlayerController* PC=nullptr;
    for (FConstPlayerControllerIterator It=W.GetPlayerControllerIterator(); It; ++It) { PC=It->Get(); ++Count; }
    if (Count!=1 || !PC || !PC->IsLocalController() || PC->GetPawn())
        return Refuse(Error,TEXT("fulltown_pre_gamemode_requires_one_local_controller_and_no_pawn"));
    PC->SetIgnoreMoveInput(true); LockedController=PC; bMovementLockOwned=true;
    return PC->IsMoveInputIgnored() || Refuse(Error,TEXT("fulltown_owned_boot_lock_not_observed"));
}

void ULivingTownFullTownStreamingSubsystem::ReleaseOwnedMovementLock()
{
    if (bMovementLockOwned) { if (auto* PC=LockedController.Get()) PC->SetIgnoreMoveInput(false); bMovementLockOwned=false; }
}

void ULivingTownFullTownStreamingSubsystem::OnWorldBeginPlay(UWorld& W)
{
    Super::OnWorldBeginPlay(W);
    TArray<ALivingTownFullTownDriver*> Enabled;
    for (TActorIterator<ALivingTownFullTownDriver> It(&W); It; ++It) if (It->bEnableIntegrationSubset) Enabled.Add(*It);
    if (Enabled.IsEmpty()) return; // Original pilot/maps remain completely inactive here.
    bArmed=true; ArmedSeconds=FPlatformTime::Seconds(); ArmedFrame=GFrameCounter;
    FString Error;
    // UWorld::BeginPlay invokes this before GameMode::StartPlay or actor BeginPlay.
    if (!LockMovementBeforeGameMode(W,Error)) { Fail(Error); return; }
    if (Enabled.Num()!=1 || !Enabled[0]->IsIdentityPlacement() ||
        !W.GetAuthGameMode() || W.GetAuthGameMode()->GetClass()!=ALivingTownCafeGameMode::StaticClass() ||
        !W.GetStreamingLevels().IsEmpty() || W.GetNetMode()!=NM_Standalone || FPlatformProperties::RequiresCookedData())
    { Fail(TEXT("fulltown_requires_one_identity_driver_empty_uncooked_standalone_root_and_existing_cafe_gamemode")); return; }
    Driver=Enabled[0]; auto* D=Driver.Get();
    for (TActorIterator<ALivingTownTileDriver> It(&W); It; ++It) if (It->bEnableQualifiedPilot)
    { Fail(TEXT("fulltown_old_pilot_driver_would_duplicate_geometry")); return; }
    if (D->Manifest.IsNull() || D->ManifestSourceBytes<=0 || D->ManifestSourceBytes>8*1024*1024 ||
        !LivingTownTiles::IsSha256(D->ManifestSourceSha256) || !FMath::IsFinite(D->LoadRadiusCm) || !FMath::IsFinite(D->UnloadRadiusCm) ||
        D->LoadRadiusCm<0 || D->UnloadRadiusCm<D->LoadRadiusCm || D->UnloadRadiusCm>20000 ||
        !FMath::IsFinite(D->StartupDeadlineSeconds) || D->StartupDeadlineSeconds<1 || D->StartupDeadlineSeconds>600 ||
        !FMath::IsFinite(D->UnitDeadlineSeconds) || D->UnitDeadlineSeconds<1 || D->UnitDeadlineSeconds>D->StartupDeadlineSeconds ||
        !FMath::IsFinite(D->ValidationTimeTargetMs) || D->ValidationTimeTargetMs<=0 || D->ValidationTimeTargetMs>4 ||
        D->ComponentsPerFrame<1 || D->ComponentsPerFrame>8 || D->InstancesPerFrame<1 || D->InstancesPerFrame>256)
    { Fail(TEXT("fulltown_driver_profile_bounds")); return; }
    LoadRadius=D->LoadRadiusCm; UnloadRadius=D->UnloadRadiusCm; StartupDeadline=D->StartupDeadlineSeconds;
    UnitDeadline=D->UnitDeadlineSeconds; ValidationTargetMs=D->ValidationTimeTargetMs;
    ComponentBudget=D->ComponentsPerFrame; InstanceBudget=D->InstancesPerFrame;
    const FString ManifestFile=FPackageName::LongPackageNameToFilename(D->Manifest.GetLongPackageName(),FPackageName::GetAssetPackageExtension());
    TArray<uint8> ManifestBytes; FString ManifestHash;
    const double HashStart=FPlatformTime::Seconds();
    const bool ManifestBound=IFileManager::Get().FileSize(*ManifestFile)==D->ManifestSourceBytes && FFileHelper::LoadFileToArray(ManifestBytes,*ManifestFile) &&
        ManifestBytes.Num()==D->ManifestSourceBytes && LivingTownTiles::HashBytes(ManifestBytes,ManifestHash) && ManifestHash==D->ManifestSourceSha256;
    ManifestSourceHashSeconds=FPlatformTime::Seconds()-HashStart;
    if (!ManifestBound)
    { Fail(TEXT("fulltown_exact_uncooked_manifest_package_binding")); return; }
    const uint64 E=Epoch; TWeakObjectPtr<ULivingTownFullTownStreamingSubsystem> Weak(this);
    ManifestHandle=UAssetManager::GetStreamableManager().RequestAsyncLoad(D->Manifest.ToSoftObjectPath(),FStreamableDelegate::CreateLambda([Weak,E]()
    { if (auto* S=Weak.Get(); S && S->Epoch==E && !S->bFailed && !S->bWorldEnding) S->bManifestCompleted=true; }));
    if (!ManifestHandle.IsValid()) Fail(TEXT("fulltown_manifest_request_refused"));
    UE_LOG(LogTemp,Display,TEXT("FullTown pre-GameMode armed frame=%llu movement_owned=%d"),ArmedFrame,bMovementLockOwned);
}

bool ULivingTownFullTownStreamingSubsystem::WasArmedBeforeGameMode(const ALivingTownFullTownDriver* C) const
{ return bArmed && Driver.Get()==C && bMovementLockOwned; }
bool ULivingTownFullTownStreamingSubsystem::BeforeQualifiedPossess(APlayerController* PC,FString& Error)
{
    if (!bArmed) return true;
    if (bFailed || bStopping || bWorldEnding || bPossessionWindow || !PC || PC!=LockedController.Get() ||
        PC->GetPawn() || !bMovementLockOwned || !PC->IsMoveInputIgnored())
    { Error=TEXT("fulltown_before_possess_boot_ownership"); Fail(Error); return false; }
    // Same GT call stack: no ordinary input/movement tick occurs until After.
    // Balance our old contribution rather than assuming ClientRestart retained it.
    ReleaseOwnedMovementLock(); bPossessionWindow=true; return true;
}
bool ULivingTownFullTownStreamingSubsystem::AfterQualifiedPossess(APlayerController* PC,APawn* Pawn,FString& Error)
{
    if (!bArmed) return true;
    const bool Expected=bPossessionWindow && PC && PC==LockedController.Get() && !bWorldEnding;
    bPossessionWindow=false;
    if (Expected) { PC->SetIgnoreMoveInput(true); bMovementLockOwned=true; ++PossessionRelocks; }
    if (!Expected || bFailed || bStopping || !Pawn || PC->GetPawn()!=Pawn ||
        Pawn->GetClass()!=ALivingTownCafeCharacter::StaticClass() || !PC->IsMoveInputIgnored())
    { Error=TEXT("fulltown_after_possess_owned_relock_not_established"); Fail(Error); return false; }
    return true;
}
void ULivingTownFullTownStreamingSubsystem::NotifyDriverEnding(const ALivingTownFullTownDriver* C)
{ if (!bWorldEnding && Driver.Get()==C) RequestSafeStop(); }
void ULivingTownFullTownStreamingSubsystem::RequestSafeStop()
{
    if (!bArmed || bWorldEnding) return;
    bStopping=true; ++Epoch;
    // The synchronous post-Possess hook owns re-locking if a stop occurs inside
    // that stack; do not add a second contribution before ClientRestart resets it.
    if (!bMovementLockOwned && !bPossessionWindow) if (auto* PC=LockedController.Get()) { PC->SetIgnoreMoveInput(true); bMovementLockOwned=true; }
    if (ManifestHandle) ManifestHandle->CancelHandle();
    CancelHiddenWork();
    UE_LOG(LogTemp,Display,TEXT("FullTown live stop: resident support retained; no world teardown asserted"));
}
void ULivingTownFullTownStreamingSubsystem::Fail(const FString& Error)
{
    if (bFailed || bWorldEnding) return;
    LastError=Error; bFailed=true; RequestSafeStop();
    UE_LOG(LogTemp,Error,TEXT("FullTown subset refused: %s"),*LastError);
}

bool ULivingTownFullTownStreamingSubsystem::CurrentWorldAndOwner() const
{
    return GetWorld() && GetWorld()->OriginLocation==FIntVector::ZeroValue && Driver.IsValid() && Driver->GetWorld()==GetWorld() && Driver->IsIdentityPlacement() &&
        LockedController.IsValid() && LockedController->GetWorld()==GetWorld();
}

bool ULivingTownFullTownStreamingSubsystem::AcceptManifest(FString& Error)
{
    if (!bManifestCompleted) return true;
    auto* D=Driver.Get(); Data=D ? D->Manifest.Get() : nullptr;
    if (!Data || !LivingTownFullTown::ValidateManifest(*Data,Error)) return false;
    const FString Package=UWorld::RemovePIEPrefix(GetWorld()->GetOutermost()->GetName());
    if (Package!=Data->RootWorld.GetLongPackageName()) return Refuse(Error,TEXT("fulltown_manifest_wrong_root_map"));
    // Only the small descriptor is held here. Its map soft references were not bulk preloaded.
    return true;
}

bool ULivingTownFullTownStreamingSubsystem::CafeStillQualified(bool& Waiting,FString& Error) const
{
    Waiting=false;
    auto* P=GetWorld()->GetSubsystem<ULivingTownCafeProjectionSubsystem>();
    if (!P || !P->IsScenePrepared() || !P->IsReady()) { Waiting=true; return true; }
    const auto& B=P->GetBinding();
    if (!B.HasValidatedPartRoster() || B.BindingFileSha256!=Data->ExternalCafeBindingSha256 ||
        B.DeclaredPartCount!=262 || B.Parts.Num()!=262 || B.DeclaredPartIds.Num()!=Data->ExternalCafePartIds.Num())
        return Refuse(Error,TEXT("fulltown_external_cafe_binding_identity"));
    for (const FString& Id:Data->ExternalCafePartIds) if (!B.DeclaredPartIds.Contains(Id))
        return Refuse(Error,TEXT("fulltown_external_cafe_part_set"));
    int32 Venues=0;
    for (TActorIterator<ALivingTownCafeVenue> It(GetWorld()); It; ++It)
    {
        ++Venues; TArray<UStaticMeshComponent*> Parts; It->GetComponents<UStaticMeshComponent>(Parts);
        if (!It->IsQualified() || Parts.Num()!=262) return Refuse(Error,TEXT("fulltown_natural_cafe_actual_components"));
    }
    return Venues==1 || Refuse(Error,TEXT("fulltown_natural_cafe_duplicate_or_missing"));
}

ULivingTownFullTownTicket* ULivingTownFullTownStreamingSubsystem::FindTicket(int32 I) const
{ for (ULivingTownFullTownTicket* T:Tickets) if (T && T->UnitIndex==I && T->Phase!=ELivingTownFullTownPhase::Removed) return T; return nullptr; }
int32 ULivingTownFullTownStreamingSubsystem::TransitionReservations() const
{ int32 N=0; for (ULivingTownFullTownTicket* T:Tickets) if (T && T->ReservesTransition()) ++N; return N; }
bool ULivingTownFullTownStreamingSubsystem::DependenciesResident(int32 I) const
{
    for (const FString& Id:Data->Units[I].RequiredUnits)
    {
        const int32 J=Data->Units.IndexOfByPredicate([&](const auto& U){return U.UnitId==Id;});
        const auto* T=FindTicket(J); if (!T || T->Phase!=ELivingTownFullTownPhase::Resident) return false;
    }
    return true;
}
bool ULivingTownFullTownStreamingSubsystem::AllWantedResident() const
{ for (int32 I:Wanted) { const auto* T=FindTicket(I); if (!T || T->Phase!=ELivingTownFullTownPhase::Resident) return false; } return true; }
void ULivingTownFullTownStreamingSubsystem::RefreshWanted()
{
    Wanted.Empty(); const auto* PC=LockedController.Get(); const APawn* Pawn=PC?PC->GetPawn():nullptr;
    for (int32 I=0; I<Data->Units.Num(); ++I)
    {
        const auto& U=Data->Units[I]; const auto* T=FindTicket(I);
        const double Radius=T && T->Phase==ELivingTownFullTownPhase::Resident ? UnloadRadius : LoadRadius;
        if (!bReady || U.bPinnedSupport || (Pawn && LivingTownFullTown::DistanceToBoundsXY(Pawn->GetActorLocation(),U.ActualBoundsCm)<=Radius)) Wanted.Add(I);
    }
    // Current subset dependencies are exactly the pinned ground unit, validated in Data.cpp.
}

bool ULivingTownFullTownStreamingSubsystem::CheckSourceMap(const FLivingTownFullTownUnit& U,FString& Error)
{
    const double Start=FPlatformTime::Seconds();
    const auto Record=[&](bool Result)
    { const double Elapsed=FPlatformTime::Seconds()-Start; ++MapSourceHashCalls; MapSourceHashSecondsTotal+=Elapsed;
      MapSourceHashSecondsMax=FMath::Max(MapSourceHashSecondsMax,Elapsed); return Result; };
    const FString Filename=FPackageName::LongPackageNameToFilename(U.Map.GetLongPackageName(),FPackageName::GetMapPackageExtension());
    TArray<uint8> Bytes;
    if (IFileManager::Get().FileSize(*Filename)!=U.SourceMapBytes || !FFileHelper::LoadFileToArray(Bytes,*Filename))
        return Record(Refuse(Error,TEXT("fulltown_exact_uncooked_map_file_unavailable")));
    FString Hash;
    return Record((Bytes.Num()==U.SourceMapBytes && LivingTownTiles::HashBytes(Bytes,Hash) && Hash==U.SourceMapSha256) ||
        Refuse(Error,TEXT("fulltown_uncooked_map_bytes_differ_from_cold")));
}

void ULivingTownFullTownStreamingSubsystem::PumpLoads()
{
    if (bFailed || bStopping || !Data) return;
    int32 Reservations=TransitionReservations(); PeakTransitions=FMath::Max(PeakTransitions,Reservations);
    if (Reservations>=2) return;
    TArray<int32> Candidates=Wanted.Array();
    const APawn* Pawn=LockedController->GetPawn(); const FVector Focus=Pawn?Pawn->GetActorLocation():FVector::ZeroVector;
    Candidates.Sort([&](int32 A,int32 B)
    { if (Data->Units[A].bPinnedSupport!=Data->Units[B].bPinnedSupport) return Data->Units[A].bPinnedSupport;
      return LivingTownFullTown::DistanceToBoundsXY(Focus,Data->Units[A].ActualBoundsCm)<LivingTownFullTown::DistanceToBoundsXY(Focus,Data->Units[B].ActualBoundsCm); });
    for (int32 I:Candidates)
    {
        if (Reservations>=2) break;
        if (FindTicket(I) || !DependenciesResident(I)) continue;
        FString Error; if (!CheckSourceMap(Data->Units[I],Error)) { Fail(Error); return; }
        auto* T=NewObject<ULivingTownFullTownTicket>(this); T->Epoch=Epoch; T->Token=NextToken++; T->UnitIndex=I;
        T->StartedSeconds=FPlatformTime::Seconds(); Tickets.Add(T); ++Reservations; ++LoadsIssued;
        ULevelStreamingDynamic::FLoadLevelInstanceParams Params(GetWorld(),Data->Units[I].Map.GetLongPackageName(),FTransform::Identity);
        Params.bInitiallyVisible=false; Params.bAllowReuseExitingLevelStreaming=false; Params.bLoadAsTempPackage=false;
        Params.OptionalLevelStreamingClass=ULivingTownFullTownLevelStreaming::StaticClass();
        const FString InstanceName=FString::Printf(TEXT("LT_FullTown_%llu_%llu_U%04d"),Epoch,T->Token,Data->Units[I].DispatchIndex);
        Params.OptionalLevelNameOverride=&InstanceName;
        Params.LevelStreamingCreatedCallback=[T](ULevelStreaming* L)
        {
            T->Streaming=Cast<ULevelStreamingDynamic>(L);
            L->OnLevelLoaded.AddDynamic(T,&ULivingTownFullTownTicket::ObserveLoaded);
            L->OnLevelShown.AddDynamic(T,&ULivingTownFullTownTicket::ObserveShown);
            L->OnLevelHidden.AddDynamic(T,&ULivingTownFullTownTicket::ObserveHidden);
            L->OnLevelUnloaded.AddDynamic(T,&ULivingTownFullTownTicket::ObserveUnloaded);
        };
        bool Created=false; auto* Actual=ULevelStreamingDynamic::LoadLevelInstance(Params,Created);
        if (!Created || !Actual || Actual!=T->Streaming) { Fail(TEXT("fulltown_native_level_creation_refused")); return; }
        PeakTransitions=FMath::Max(PeakTransitions,Reservations);
    }
}

void ULivingTownFullTownStreamingSubsystem::BeginDrain(ULivingTownFullTownTicket& T)
{
    if (T.Phase==ELivingTownFullTownPhase::Removed || T.Phase==ELivingTownFullTownPhase::Unloading) return;
    if (!T.bCancelled) { T.MarkCancelled(); ++Cancellations; }
    T.RetireStartedSeconds=FPlatformTime::Seconds();
    T.Components.Empty(); T.RoleIndices.Empty(); // Do not keep asset actors alive while native unload/GC drains.
    if (!T.Streaming) { T.Phase=ELivingTownFullTownPhase::Removed; return; }
    T.Streaming->SetShouldBeVisible(false); T.Streaming->SetShouldBeLoaded(false);
    T.Streaming->SetIsRequestingUnloadAndRemoval(true); T.Phase=ELivingTownFullTownPhase::Unloading;
}

void ULivingTownFullTownStreamingSubsystem::CancelHiddenWork()
{
    for (ULivingTownFullTownTicket* T:Tickets) if (T && T->Phase!=ELivingTownFullTownPhase::Resident) BeginDrain(*T);
}

bool ULivingTownFullTownStreamingSubsystem::GatherHidden(ULivingTownFullTownTicket& T,FString& Error)
{
    auto* Level=T.Streaming?T.Streaming->GetLoadedLevel():nullptr;
    // GetWorld() on a loaded ULevel can be the owning runtime world, whose
    // streaming list necessarily includes our ticket. Do not mislabel that as
    // a nested-map definition. The exact Cold map bytes and global owned-ticket
    // streaming roster separately constrain the source and runtime lists.
    if (!Level || Level->Actors.Num()>64)
        return Refuse(Error,TEXT("fulltown_loaded_hidden_level_shape"));
    const auto& U=Data->Units[T.UnitIndex]; TSet<int32> Seen; int32 Owners=0, Bases=0;
    for (AActor* A:Level->Actors)
    {
        if (!A) continue;
        if (!A->ActorHasTag(TEXT("LT_FTW_OWNER")))
        { if (!BaseActor(A) || ++Bases>4) return Refuse(Error,TEXT("fulltown_foreign_level_actor")); continue; }
        if (++Owners>32 || A->GetClass()!=AActor::StaticClass() || !A->ActorHasTag(FName(*U.UnitId)) ||
            A->IsActorTickEnabled() || !LivingTownFullTown::SameQualifiedTransform(A->GetActorTransform(),FTransform::Identity))
            return Refuse(Error,TEXT("fulltown_owner_identity_or_behavior"));
        TArray<UStaticMeshComponent*> Components; A->GetComponents<UStaticMeshComponent>(Components);
        if (Components.Num()>256) return Refuse(Error,TEXT("fulltown_owner_component_bound"));
        for (auto* C:Components)
        {
            if (C->ComponentTags.Num()!=1) return Refuse(Error,TEXT("fulltown_role_tag_roster"));
            const FString Tag=C->ComponentTags[0].ToString();
            if (!Tag.StartsWith(TEXT("LT_FTW_ROLE="))) return Refuse(Error,TEXT("fulltown_missing_stable_role_tag"));
            const FString Id=Tag.Mid(12);
            const int32 R=U.Roles.IndexOfByPredicate([&](const auto& Q){return Q.RoleId==Id;});
            if (R==INDEX_NONE || Seen.Contains(R)) return Refuse(Error,TEXT("fulltown_foreign_or_duplicate_role"));
            Seen.Add(R); T.Components.Add(C); T.RoleIndices.Add(R);
        }
    }
    return (Owners>0 && Seen.Num()==U.Roles.Num()) || Refuse(Error,TEXT("fulltown_missing_saved_roles"));
}

bool ULivingTownFullTownStreamingSubsystem::ValidateComponent(ULivingTownFullTownTicket& T,int32 I,bool Registered,FString& Error)
{
    auto* C=T.Components[I].Get(); const auto& R=Data->Units[T.UnitIndex].Roles[T.RoleIndices[I]];
    UStaticMesh* Mesh=C?C->GetStaticMesh():nullptr;
    const bool HISM=R.Kind==ELivingTownFullTownComponentKind::HierarchicalInstances;
    if (!C || C->GetClass()!=(HISM?UHierarchicalInstancedStaticMeshComponent::StaticClass():UStaticMeshComponent::StaticClass()) ||
        !Mesh || FSoftObjectPath(Mesh)!=R.Mesh || !LivingTownFullTown::SameQualifiedTransform(C->GetComponentTransform(),R.WorldTransform) ||
        C->GetCollisionProfileName()!=R.CollisionProfile || C->GetCollisionEnabled()!=R.CollisionEnabled || C->IsComponentTickEnabled() ||
        (Registered && !C->IsRegistered()) || C->GetNumMaterials()!=R.Slots.Num() || Mesh->GetStaticMaterials().Num()!=R.Slots.Num() ||
        C->GetNumOverrideMaterials()!=(HISM?R.Slots.Num():0))
        return Refuse(Error,TEXT("fulltown_component_mesh_transform_collision_or_material_roster"));
    for (int32 S=0; S<R.Slots.Num(); ++S)
    {
        const auto& Slot=R.Slots[S]; const auto& Default=Mesh->GetStaticMaterials()[S]; auto* Effective=C->GetMaterial(S);
        if (Slot.SlotIndex!=S || FSoftObjectPath(Default.MaterialInterface.Get())!=Slot.OriginalDefault || Default.MaterialSlotName!=Slot.SlotName ||
            !Effective || FSoftObjectPath(Effective)!=(HISM?Slot.Override:Slot.OriginalDefault) || uint8(Effective->GetBlendMode())!=Slot.BlendMode)
            return Refuse(Error,TEXT("fulltown_exact_ordered_material_slot"));
        if (HISM && (C->OverrideMaterials[S]!=Effective || !LivingTownMaterials::ValidateInstancedUsage(Effective,R.RoleId,R.Mesh.ToString(),S,Error))) return false;
    }
    if (HISM && CastChecked<UHierarchicalInstancedStaticMeshComponent>(C)->GetInstanceCount()!=R.Instances.Num())
        return Refuse(Error,TEXT("fulltown_saved_hism_instance_count"));
    return true;
}

bool ULivingTownFullTownStreamingSubsystem::AdvanceValidation(ULivingTownFullTownTicket& T,bool Registered,FString& Error)
{
    const double Start=FPlatformTime::Seconds();
    while (T.NextComponent<T.Components.Num() && FrameComponents<ComponentBudget && FrameInstances<InstanceBudget &&
           (FPlatformTime::Seconds()-Start)*1000.0<ValidationTargetMs)
    {
        const int32 I=T.NextComponent; const auto& R=Data->Units[T.UnitIndex].Roles[T.RoleIndices[I]];
        if (T.NextInstance==0) { ++FrameComponents; if (!ValidateComponent(T,I,Registered,Error)) return false; }
        if (R.Kind==ELivingTownFullTownComponentKind::HierarchicalInstances)
        {
            auto* H=CastChecked<UHierarchicalInstancedStaticMeshComponent>(T.Components[I].Get());
            while (T.NextInstance<R.Instances.Num() && FrameInstances<InstanceBudget && (FPlatformTime::Seconds()-Start)*1000.0<ValidationTargetMs)
            {
                FTransform Actual; const auto& Instance=R.Instances[T.NextInstance];
                if (!H->GetInstanceTransform(T.NextInstance,Actual,true) || !LivingTownFullTown::SameQualifiedTransform(Actual,Instance.WorldTransform))
                    return Refuse(Error,TEXT("fulltown_saved_hism_index_transform"));
                ++T.NextInstance; ++FrameInstances;
            }
            if (T.NextInstance<R.Instances.Num()) return true;
        }
        ++T.NextComponent; T.NextInstance=0;
    }
    return true;
}

bool ULivingTownFullTownStreamingSubsystem::ObserveFooting(int32* SimpleUnit,int32* ComplexUnit) const
{
    const auto* PC=LockedController.Get(); const auto* Pawn=PC?Cast<ALivingTownCafeCharacter>(PC->GetPawn()):nullptr;
    if (!Pawn || !Pawn->GetCapsuleComponent() || !Pawn->GetCharacterMovement() || !Pawn->GetCharacterMovement()->IsMovingOnGround()) return false;
    const FVector Feet=Pawn->GetActorLocation()-FVector(0,0,Pawn->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());
    for (int32 Mode=0; Mode<2; ++Mode)
    {
        FCollisionQueryParams Q(SCENE_QUERY_STAT(FullTownRetainedFooting),Mode==1); Q.AddIgnoredActor(Pawn);
        FHitResult Hit;
        if (!GetWorld()->LineTraceSingleByChannel(Hit,Feet+FVector(0,0,10),Feet-FVector(0,0,50),ECC_Pawn,Q) ||
            !Hit.GetComponent() || Hit.ImpactNormal.Z<Pawn->GetCharacterMovement()->GetWalkableFloorZ()) return false;
        int32 Unit=INDEX_NONE; bool Known=false;
        if (const auto* Venue=Cast<ALivingTownCafeVenue>(Hit.GetActor())) Known=Venue->IsQualified() && Venue->IsFloorComponent(Hit.GetComponent());
        for (ULivingTownFullTownTicket* T:Tickets) if (T && T->Phase==ELivingTownFullTownPhase::Resident && T->Streaming &&
            Hit.GetActor() && Hit.GetActor()->GetLevel()==T->Streaming->GetLoadedLevel()) { Known=true; Unit=T->UnitIndex; break; }
        if (!Known) return false;
        if (Mode==0 && SimpleUnit) *SimpleUnit=Unit;
        if (Mode==1 && ComplexUnit) *ComplexUnit=Unit;
    }
    return true;
}

bool ULivingTownFullTownStreamingSubsystem::MayRetire(int32 I) const
{
    int32 Simple=INDEX_NONE, Complex=INDEX_NONE;
    return bReady && !bFailed && !bStopping && !Data->Units[I].bPinnedSupport && AllWantedResident() &&
        ObserveFooting(&Simple,&Complex) && Simple!=I && Complex!=I;
}

void ULivingTownFullTownStreamingSubsystem::AdvanceTickets(double TickStarted)
{
    const double Now=FPlatformTime::Seconds();
    for (ULivingTownFullTownTicket* T:Tickets)
    {
        if (!T || T->Phase==ELivingTownFullTownPhase::Removed) continue;
        if (T->Phase==ELivingTownFullTownPhase::Unloading)
        {
            const auto State=T->Streaming?T->Streaming->GetLevelStreamingState():ELevelStreamingState::Removed;
            if (!T->Streaming || (State==ELevelStreamingState::Removed && !GetWorld()->GetStreamingLevels().Contains(T->Streaming.Get())))
            { T->Streaming=nullptr; T->Phase=ELivingTownFullTownPhase::Removed; }
            else if (Now-T->RetireStartedSeconds>UnitDeadline) Fail(TEXT("fulltown_native_unload_deadline_reservation_retained"));
            continue;
        }
        if (bFailed || bStopping) continue;
        if (!T->Accepts(Epoch,T->Token) || !T->Streaming) { Fail(TEXT("fulltown_stale_or_missing_ticket")); return; }
        const auto State=T->Streaming->GetLevelStreamingState();
        if (State==ELevelStreamingState::FailedToLoad) { Fail(TEXT("fulltown_native_map_failed_to_load")); return; }
        if (T->Phase!=ELivingTownFullTownPhase::Resident && Now-T->StartedSeconds>UnitDeadline)
        { Fail(TEXT("fulltown_native_unit_deadline")); return; }
        if (!Wanted.Contains(T->UnitIndex) && T->Phase!=ELivingTownFullTownPhase::Resident) { BeginDrain(*T); continue; }
        FString Error;
        if (T->Phase==ELivingTownFullTownPhase::LoadingHidden && T->bLoadedEvent && State==ELevelStreamingState::LoadedNotVisible)
        {
            if (!GatherHidden(*T,Error)) { Fail(Error); return; }
            T->Phase=ELivingTownFullTownPhase::ValidatingHidden;
        }
        if (T->Phase==ELivingTownFullTownPhase::ValidatingHidden)
        {
            if (!AdvanceValidation(*T,false,Error)) { Fail(Error); return; }
            bool OtherShowing=false;
            for (ULivingTownFullTownTicket* Other:Tickets) if (Other!=T && Other->Phase==ELivingTownFullTownPhase::MakingVisible) OtherShowing=true;
            if (T->NextComponent==T->Components.Num() && !OtherShowing)
            { T->NextComponent=0; T->NextInstance=0; T->Phase=ELivingTownFullTownPhase::MakingVisible; T->Streaming->SetShouldBeVisible(true); }
        }
        if (T->Phase==ELivingTownFullTownPhase::MakingVisible && T->bShownEvent && State==ELevelStreamingState::LoadedVisible)
        {
            if (!AdvanceValidation(*T,true,Error)) { Fail(Error); return; }
            if (T->NextComponent==T->Components.Num())
            { T->Phase=ELivingTownFullTownPhase::Resident; ++ShownUnits; UE_LOG(LogTemp,Display,TEXT("FullTown unit resident %s token=%llu"),*Data->Units[T->UnitIndex].UnitId,T->Token); }
        }
        if (T->Phase==ELivingTownFullTownPhase::Resident && !Wanted.Contains(T->UnitIndex) && MayRetire(T->UnitIndex) && TransitionReservations()<2) BeginDrain(*T);
        if ((FPlatformTime::Seconds()-TickStarted)*1000.0>=ValidationTargetMs || FrameComponents>=ComponentBudget || FrameInstances>=InstanceBudget) break;
    }
    Tickets.RemoveAll([](const auto& T){return !T || T->Phase==ELivingTownFullTownPhase::Removed;});
}

void ULivingTownFullTownStreamingSubsystem::Tick(float Delta)
{
    Super::Tick(Delta); if (!bArmed || bWorldEnding || bInTick || bPossessionWindow) return;
    TGuardValue<bool> Guard(bInTick,true); ++Frames; FrameComponents=0; FrameInstances=0;
    const double Now=FPlatformTime::Seconds();
    if (!bFailed && !bStopping && !CurrentWorldAndOwner()) Fail(TEXT("fulltown_runtime_owner_or_controller_changed"));
    if (!bReady && !bFailed && Now-ArmedSeconds>StartupDeadline) Fail(TEXT("fulltown_finite_boot_deadline_no_player_release"));
    FString Error;
    if (!bFailed && !bStopping && !Data && bManifestCompleted && !AcceptManifest(Error)) Fail(Error);
    bool CafeWaiting=true;
    if (!bFailed && !bStopping && Data && !CafeStillQualified(CafeWaiting,Error)) Fail(Error);
    if (!bFailed && !bStopping && Data && !CafeWaiting)
    {
        for (ULevelStreaming* L:GetWorld()->GetStreamingLevels())
        {
            const bool Owned=Tickets.ContainsByPredicate([&](const auto& T){return T && T->Streaming==L;});
            if (!Owned) { Fail(TEXT("fulltown_foreign_streaming_object")); break; }
        }
        RefreshAccumulator+=Delta;
        if (Wanted.IsEmpty() || RefreshAccumulator>=0.25) { RefreshAccumulator=0; RefreshWanted(); }
    }
    AdvanceTickets(Now);
    if (!bFailed && !bStopping && Data && !CafeWaiting)
    {
        PumpLoads();
        if (!bReady && PossessionRelocks==1 && bMovementLockOwned && LockedController->IsMoveInputIgnored() && AllWantedResident() && ObserveFooting())
        {
            bReady=true; ReadySeconds=FPlatformTime::Seconds(); ReadyFrame=GFrameCounter; ReleaseOwnedMovementLock();
            UE_LOG(LogTemp,Display,TEXT("FullTown integration subset controllable seconds=%.6f frame=%llu units=%d; not full193/cooked/art/FPS qualification"),ReadySeconds-ArmedSeconds,ReadyFrame,Wanted.Num());
        }
    }
}

FString ULivingTownFullTownStreamingSubsystem::GetStatusJson() const
{
    auto J=MakeShared<FJsonObject>();
    J->SetStringField(TEXT("scope"),TEXT("IntegrationSubset_U0131_U0142_Ground151_ExternalCafe81"));
    J->SetStringField(TEXT("status"),bFailed?TEXT("FAILED_SUPPORT_RETAINED"):bStopping?TEXT("STOPPED_SUPPORT_RETAINED"):bReady?TEXT("SUBSET_CONTROLLABLE_NOT_FULL_TOWN"):bArmed?TEXT("BOOT_MOVEMENT_LOCKED"):TEXT("INACTIVE"));
    J->SetStringField(TEXT("error"),LastError); J->SetNumberField(TEXT("epoch"),double(Epoch));
    J->SetNumberField(TEXT("owned_tick_frames"),double(Frames)); J->SetNumberField(TEXT("armed_frame"),double(ArmedFrame));
    J->SetNumberField(TEXT("ready_frame"),double(ReadyFrame)); J->SetNumberField(TEXT("startup_seconds"),bReady?ReadySeconds-ArmedSeconds:0);
    J->SetBoolField(TEXT("owned_movement_lock"),bMovementLockOwned); J->SetNumberField(TEXT("transition_reservations"),TransitionReservations());
    J->SetNumberField(TEXT("peak_transition_reservations"),PeakTransitions); J->SetNumberField(TEXT("loads_issued"),LoadsIssued);
    J->SetNumberField(TEXT("shown_validated_units_total"),ShownUnits); J->SetNumberField(TEXT("cancellations"),Cancellations);
    J->SetNumberField(TEXT("post_possession_owned_relocks"),PossessionRelocks);
    J->SetBoolField(TEXT("inside_synchronous_possession_window"),bPossessionWindow);
    J->SetNumberField(TEXT("manifest_source_file_hash_seconds"),ManifestSourceHashSeconds);
    J->SetNumberField(TEXT("map_source_file_hash_calls"),MapSourceHashCalls);
    J->SetNumberField(TEXT("map_source_file_hash_total_seconds"),MapSourceHashSecondsTotal);
    J->SetNumberField(TEXT("map_source_file_hash_max_seconds"),MapSourceHashSecondsMax);
    J->SetNumberField(TEXT("last_tick_components_observed"),FrameComponents); J->SetNumberField(TEXT("last_tick_instances_observed"),FrameInstances);
    J->SetBoolField(TEXT("GPU_FPS_and_cooked_and_art_qualified"),false);
    TArray<TSharedPtr<FJsonValue>> Units;
    for (const ULivingTownFullTownTicket* T:Tickets)
    {
        auto U=MakeShared<FJsonObject>(); U->SetNumberField(TEXT("unit_index"),T->UnitIndex); U->SetNumberField(TEXT("token"),double(T->Token));
        U->SetNumberField(TEXT("phase"),int32(T->Phase)); U->SetBoolField(TEXT("cancelled"),T->bCancelled);
        U->SetStringField(TEXT("native_state"),T->Streaming?EnumToString(T->Streaming->GetLevelStreamingState()):TEXT("NO_STREAM_OBJECT"));
        Units.Add(MakeShared<FJsonValueObject>(U));
    }
    J->SetArrayField(TEXT("tickets"),Units); FString Out; auto Writer=TJsonWriterFactory<>::Create(&Out); FJsonSerializer::Serialize(J,Writer); return Out;
}

void ULivingTownFullTownStreamingSubsystem::TearDownOwnedReferences()
{
    bWorldEnding=true; ++Epoch;
    if (ManifestHandle) { ManifestHandle->CancelHandle(); ManifestHandle.Reset(); }
    for (ULivingTownFullTownTicket* T:Tickets) if (T && T->Streaming)
    {
        T->MarkCancelled(); T->Streaming->OnLevelLoaded.RemoveAll(T); T->Streaming->OnLevelShown.RemoveAll(T);
        T->Streaming->OnLevelHidden.RemoveAll(T); T->Streaming->OnLevelUnloaded.RemoveAll(T);
        T->Components.Empty(); T->Streaming=nullptr;
    }
    Tickets.Empty(); Data=nullptr; Driver.Reset(); ReleaseOwnedMovementLock(); LockedController.Reset();
}
void ULivingTownFullTownStreamingSubsystem::OnWorldEndPlay(UWorld& W)
{ TearDownOwnedReferences(); Super::OnWorldEndPlay(W); }
void ULivingTownFullTownStreamingSubsystem::Deinitialize()
{ if (!bWorldEnding) TearDownOwnedReferences(); Super::Deinitialize(); }

#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownFullTownTicketTest,"LivingTown.FullTown.CancelledLoadRetainsReservation",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownFullTownTicketTest::RunTest(const FString&)
{
    auto* T=NewObject<ULivingTownFullTownTicket>(); T->Epoch=7; T->Token=31;
    TestTrue(TEXT("current request accepts"),T->Accepts(7,31));
    TestFalse(TEXT("old epoch refused"),T->Accepts(6,31)); TestFalse(TEXT("old token refused"),T->Accepts(7,30));
    T->MarkCancelled(); T->ObserveLoaded(); T->ObserveShown();
    TestFalse(TEXT("late real delegate observations cannot resurrect cancelled ticket"),T->Accepts(7,31));
    TestTrue(TEXT("cancelled in-flight load still reserves"),T->ReservesTransition());
    T->Phase=ELivingTownFullTownPhase::Unloading; TestTrue(TEXT("unload still reserves"),T->ReservesTransition());
    T->Phase=ELivingTownFullTownPhase::Removed; TestFalse(TEXT("only actual removal releases"),T->ReservesTransition());
    return true;
}
#endif
