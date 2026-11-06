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
#include "Components/PrimitiveComponent.h"
#include "Components/SceneComponent.h"
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
#include "Policies/CondensedJsonPrintPolicy.h"
#include "Dom/JsonObject.h"
#include "CoreGlobals.h"
#include "UObject/Package.h"

namespace
{
bool Refuse(FString& Error,const FString& Why) { Error=Why; return false; }
const TCHAR* const B749Profile=TEXT("B749_U0131_66_Ground156_ExternalCafe81_v001");
const TCHAR* const B749RootPackage=TEXT("/Game/LivingTown_UEPilot/FullTownIntegrationB749_v001/L_B749_Subset_v001");
const TCHAR* const B749Manifest=TEXT("/Game/LivingTown_UEPilot/FullTownIntegrationB749_v001/DA_B749_Subset_v001.DA_B749_Subset_v001");
// Actual saved descriptor bytes and SHA, independently reopened without unit-world loads.
// The serialized driver's claim alone is not a new-profile source admission.
const int64 B749ManifestSourceBytes=1315578;
const TCHAR* const B749ManifestSourceSha=TEXT("910a95cf5d083a30d0401ced33083c66ce1f7d1092c5b22ee47e4594cc598926");
bool IsB749(const ULivingTownFullTownData* D) { return D && D->ProfileId==B749Profile; }
bool StaticOverridesMatch(const UStaticMeshComponent* C,const FLivingTownFullTownRole& R,bool AllowB749)
{
    if (!C) return false;
    const int32 Expected=AllowB749 && R.Slots.Num()==1 && !R.Slots[0].Override.IsNull()?1:0;
    if (C->GetNumOverrideMaterials()!=Expected) return false;
    // Compare the stored array, even when the pointer equals the mesh default.
    // A padded null or extra slot is not the qualified empty-array shape.
    return Expected==0 || (C->OverrideMaterials[0] && FSoftObjectPath(C->OverrideMaterials[0].Get())==R.Slots[0].Override);
}
// These small production selectors are also exercised by the Automation regression.
enum class EFullTownDeadlineViolation : uint8 { None, Unit, Unload };
EFullTownDeadlineViolation FullTownDeadlineViolation(const ULivingTownFullTownTicket& T,double Now,double Limit)
{
    if (T.Phase==ELivingTownFullTownPhase::Unloading)
        return Now-T.RetireStartedSeconds>Limit ? EFullTownDeadlineViolation::Unload : EFullTownDeadlineViolation::None;
    return T.Phase!=ELivingTownFullTownPhase::Resident && T.Phase!=ELivingTownFullTownPhase::Removed && Now-T.StartedSeconds>Limit
        ? EFullTownDeadlineViolation::Unit : EFullTownDeadlineViolation::None;
}
double FullTownValidationDeadline(double ValidationStarted,double TargetMs)
{ return ValidationStarted+TargetMs*0.001; }
bool FullTownCanValidate(double Now,double Deadline,int32 Components,int32 ComponentLimit,int32 Instances,int32 InstanceLimit)
{ return Now<Deadline && Components<ComponentLimit && Instances<InstanceLimit; }
int32 FullTownNextPendingTicket(const TArray<TObjectPtr<ULivingTownFullTownTicket>>& InTickets,int32& Cursor)
{
    const int32 Num=InTickets.Num();
    if (Num==0) { Cursor=0; return INDEX_NONE; }
    Cursor=Cursor%Num;
    for (int32 Offset=0; Offset<Num; ++Offset)
    {
        const int32 Index=(Cursor+Offset)%Num; const auto* T=InTickets[Index].Get();
        if (T && !T->bCancelled && (T->Phase==ELivingTownFullTownPhase::LoadingHidden ||
            T->Phase==ELivingTownFullTownPhase::ValidatingHidden || T->Phase==ELivingTownFullTownPhase::MakingVisible))
        { Cursor=(Index+1)%Num; return Index; }
    }
    return INDEX_NONE;
}
bool BaseActor(const AActor* A)
{
    const FString P=A->GetClass()->GetPathName();
    return P==TEXT("/Script/Engine.WorldSettings") || P==TEXT("/Script/Engine.Brush") ||
        P==TEXT("/Script/Engine.LevelScriptActor") || P==TEXT("/Script/Engine.DefaultPhysicsVolume");
}
}

namespace
{

// Hidden levels have not reached component registration. Under this exact saved
// two-level identity hierarchy, serialized relative TRS is the declared world TRS.
// No registration, update, physics creation or component setter is permitted here.
bool B749HiddenSerializedTransform(const UStaticMeshComponent* C,const FTransform& LevelTransform,
    bool Registered,const FTransform& Expected,FTransform& Actual,FString& Predicate)
{
    auto Reject=[&](const TCHAR* Why) { Predicate=Why; return false; };
    if (Registered) return Reject(TEXT("hidden_helper_registered_phase"));
    if (!C || C->GetClass()!=UStaticMeshComponent::StaticClass()) return Reject(TEXT("hidden_exact_static_component"));
    Actual=C->GetRelativeTransform();
    const AActor* Actor=C->GetOwner(); const USceneComponent* Root=Actor?Actor->GetRootComponent():nullptr;
    if (!Actor || Actor->GetClass()!=AActor::StaticClass() || Actor->GetAttachParentActor())
        return Reject(TEXT("hidden_plain_unattached_owner"));
    if (!Root || Root==C || Root->GetClass()!=USceneComponent::StaticClass() || Root->GetOwner()!=Actor || Root->GetAttachParent())
        return Reject(TEXT("hidden_plain_identity_root_hierarchy"));
    if (C->GetAttachParent()!=Root || !Root->GetAttachSocketName().IsNone() || !C->GetAttachSocketName().IsNone())
        return Reject(TEXT("hidden_direct_root_no_socket"));
    if (Root->IsUsingAbsoluteLocation() || Root->IsUsingAbsoluteRotation() || Root->IsUsingAbsoluteScale() ||
        C->IsUsingAbsoluteLocation() || C->IsUsingAbsoluteRotation() || C->IsUsingAbsoluteScale())
        return Reject(TEXT("hidden_no_absolute_transform"));
    if (!LivingTownFullTown::SameQualifiedTransform(Root->GetRelativeTransform(),FTransform::Identity) ||
        !LivingTownFullTown::SameQualifiedTransform(LevelTransform,FTransform::Identity))
        return Reject(TEXT("hidden_serialized_root_and_level_identity"));
    if (!LivingTownFullTown::SameQualifiedTransform(Actual,Expected))
        return Reject(TEXT("hidden_serialized_relative_transform"));
    Predicate.Empty(); return true;
}
TSharedRef<FJsonObject> ComponentDiagnosticTransform(const FTransform& Transform)
{
    auto Object=MakeShared<FJsonObject>();
    auto Values=[&](const TCHAR* Name,const TArray<double>& Numbers)
    {
        TArray<TSharedPtr<FJsonValue>> JsonValues,Bits;
        for (double Number:Numbers)
        {
            uint64 Raw=0; FMemory::Memcpy(&Raw,&Number,sizeof(Raw));
            Bits.Add(MakeShared<FJsonValueString>(FString::Printf(TEXT("%016llx"),static_cast<unsigned long long>(Raw))));
            if (FMath::IsFinite(Number)) JsonValues.Add(MakeShared<FJsonValueNumber>(Number));
            else JsonValues.Add(MakeShared<FJsonValueString>(FMath::IsNaN(Number)?TEXT("NaN"):(Number>0?TEXT("+Inf"):TEXT("-Inf"))));
        }
        Object->SetArrayField(Name,JsonValues); Object->SetArrayField(FString(Name)+TEXT("_IEEE754_F64_bits"),Bits);
    };
    const FVector P=Transform.GetTranslation(),S=Transform.GetScale3D(); const FQuat Q=Transform.GetRotation();
    Values(TEXT("translation_cm"),{P.X,P.Y,P.Z}); Values(TEXT("rotation_xyzw"),{Q.X,Q.Y,Q.Z,Q.W}); Values(TEXT("scale"),{S.X,S.Y,S.Z});
    return Object;
}
void LogFirstComponentRefusal(const ULivingTownFullTownTicket& Ticket,int32 ComponentIndex,
    const FLivingTownFullTownUnit& Unit,const FLivingTownFullTownRole& Role,const UStaticMeshComponent* C,
    const UStaticMesh* Mesh,bool Registered,const FString& Predicate,int32 SlotIndex=INDEX_NONE)
{
    auto D=MakeShared<FJsonObject>(); const AActor* Actor=C?C->GetOwner():nullptr;
    const USceneComponent* Root=Actor?Actor->GetRootComponent():nullptr;
    auto Path=[](const UObject* Object) { return Object?Object->GetPathName():FString(); };
    D->SetStringField(TEXT("schema"),TEXT("LivingTown.FullTownFirstComponentRefusal.v1"));
    D->SetStringField(TEXT("first_predicate"),Predicate); D->SetStringField(TEXT("unit_id"),Unit.UnitId);
    D->SetNumberField(TEXT("dispatch_index"),Unit.DispatchIndex); D->SetNumberField(TEXT("unit_index"),Ticket.UnitIndex);
    D->SetNumberField(TEXT("component_index"),ComponentIndex); D->SetStringField(TEXT("role_id"),Role.RoleId);
    D->SetStringField(TEXT("component"),Path(C)); D->SetStringField(TEXT("component_class"),C?Path(C->GetClass()):FString());
    D->SetStringField(TEXT("owner_attach_parent_actor"),Actor?Path(Actor->GetAttachParentActor()):FString());
    D->SetStringField(TEXT("owner"),Path(Actor)); D->SetStringField(TEXT("owner_class"),Actor?Path(Actor->GetClass()):FString());
    D->SetStringField(TEXT("world"),C?Path(C->GetWorld()):FString()); D->SetStringField(TEXT("root"),Path(Root));
    D->SetBoolField(TEXT("registered_phase"),Registered); D->SetBoolField(TEXT("registered"),C && C->IsRegistered());
    D->SetBoolField(TEXT("pre_registered"),C && C->IsPreRegistered()); D->SetStringField(TEXT("mesh_actual"),Path(Mesh));
    D->SetStringField(TEXT("mesh_expected"),Role.Mesh.ToString()); D->SetObjectField(TEXT("expected_transform"),ComponentDiagnosticTransform(Role.WorldTransform));
    if (Ticket.Streaming) D->SetObjectField(TEXT("level_transform"),ComponentDiagnosticTransform(Ticket.Streaming->LevelTransform));
    if (C)
    {
        D->SetObjectField(TEXT("cached_world_transform"),ComponentDiagnosticTransform(C->GetComponentTransform()));
        D->SetObjectField(TEXT("serialized_relative_transform"),ComponentDiagnosticTransform(C->GetRelativeTransform()));
        D->SetStringField(TEXT("parent"),Path(C->GetAttachParent())); D->SetStringField(TEXT("socket"),C->GetAttachSocketName().ToString());
        D->SetBoolField(TEXT("absolute_location"),C->IsUsingAbsoluteLocation()); D->SetBoolField(TEXT("absolute_rotation"),C->IsUsingAbsoluteRotation()); D->SetBoolField(TEXT("absolute_scale"),C->IsUsingAbsoluteScale());
        D->SetStringField(TEXT("profile_actual"),C->GetCollisionProfileName().ToString()); D->SetNumberField(TEXT("enabled_actual"),int32(C->GetCollisionEnabled()));
        D->SetBoolField(TEXT("tick_actual"),C->IsComponentTickEnabled()); D->SetNumberField(TEXT("materials_actual"),C->GetNumMaterials()); D->SetNumberField(TEXT("overrides_actual"),C->GetNumOverrideMaterials());
    }
    if (Root)
    {
        D->SetObjectField(TEXT("root_serialized_relative_transform"),ComponentDiagnosticTransform(Root->GetRelativeTransform()));
        D->SetObjectField(TEXT("root_cached_world_transform"),ComponentDiagnosticTransform(Root->GetComponentTransform()));
        D->SetStringField(TEXT("root_class"),Path(Root->GetClass())); D->SetStringField(TEXT("root_parent"),Path(Root->GetAttachParent())); D->SetStringField(TEXT("root_socket"),Root->GetAttachSocketName().ToString());
        D->SetBoolField(TEXT("root_absolute_location"),Root->IsUsingAbsoluteLocation()); D->SetBoolField(TEXT("root_absolute_rotation"),Root->IsUsingAbsoluteRotation()); D->SetBoolField(TEXT("root_absolute_scale"),Root->IsUsingAbsoluteScale());
    }
    D->SetStringField(TEXT("profile_expected"),Role.CollisionProfile.ToString()); D->SetNumberField(TEXT("enabled_expected"),int32(Role.CollisionEnabled));
    D->SetNumberField(TEXT("materials_expected"),Role.Slots.Num()); D->SetNumberField(TEXT("mesh_slots_actual"),Mesh?Mesh->GetStaticMaterials().Num():0);
    D->SetNumberField(TEXT("slot_index"),SlotIndex); D->SetBoolField(TEXT("observation_only_no_component_mutation"),true);
    if (C && Mesh && Role.Slots.IsValidIndex(SlotIndex) && Mesh->GetStaticMaterials().IsValidIndex(SlotIndex))
    {
        const auto& Expected=Role.Slots[SlotIndex]; const auto& Default=Mesh->GetStaticMaterials()[SlotIndex]; const auto* Effective=C->GetMaterial(SlotIndex);
        D->SetStringField(TEXT("slot_name_actual"),Default.MaterialSlotName.ToString()); D->SetStringField(TEXT("slot_name_expected"),Expected.SlotName.ToString());
        D->SetStringField(TEXT("default_actual"),Path(Default.MaterialInterface.Get())); D->SetStringField(TEXT("default_expected"),Expected.OriginalDefault.ToString());
        D->SetStringField(TEXT("override_expected"),Expected.Override.ToString()); D->SetStringField(TEXT("effective_actual"),Path(Effective));
        D->SetNumberField(TEXT("blend_expected"),Expected.BlendMode); D->SetNumberField(TEXT("blend_actual"),Effective?int32(Effective->GetBlendMode()):-1);
    }
    FString Json; auto Writer=TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Json); FJsonSerializer::Serialize(D,Writer);
    const FTCHARToUTF8 Encoded(*Json);
    if (Encoded.Length()>32*1024)
    {
        // Never truncate JSON or claim that oversized field values were retained.
        auto Overflow=MakeShared<FJsonObject>(); Overflow->SetStringField(TEXT("schema"),TEXT("LivingTown.FullTownFirstComponentRefusal.v1"));
        Overflow->SetStringField(TEXT("first_predicate"),Predicate); Overflow->SetBoolField(TEXT("diagnostic_fields_overflow_32KiB"),true);
        Overflow->SetNumberField(TEXT("unpublished_UTF8_bytes"),Encoded.Length()); Json.Empty(); auto Small=TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Json); FJsonSerializer::Serialize(Overflow,Small);
    }
    UE_LOG(LogTemp,Warning,TEXT("LT_FULLTOWN_COMPONENT_REFUSAL %s"),*Json);
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
    const bool NamedBRoot=UWorld::RemovePIEPrefix(W.GetOutermost()->GetName())==B749RootPackage;
    const bool NamedBManifest=D->Manifest.ToSoftObjectPath().ToString()==B749Manifest;
    if (NamedBRoot || NamedBManifest)
    {
        if (!(NamedBRoot && NamedBManifest))
        { Fail(TEXT("fulltown_b749_exact_root_and_descriptor_before_load")); return; }
        if (B749ManifestSourceBytes<=0 || !LivingTownTiles::IsSha256(B749ManifestSourceSha))
        { Fail(TEXT("fulltown_b749_DRAFT_REFUSE_pending_actual_descriptor_package_pin")); return; }
        if (D->ManifestSourceBytes!=B749ManifestSourceBytes || D->ManifestSourceSha256!=B749ManifestSourceSha)
        { Fail(TEXT("fulltown_b749_exact_descriptor_source_pin")); return; }
    }
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
    const bool NamedBRoot=Package==B749RootPackage;
    const bool NamedBManifest=D && D->Manifest.ToSoftObjectPath().ToString()==B749Manifest;
    if ((IsB749(Data) || NamedBRoot || NamedBManifest) && !(IsB749(Data) && NamedBRoot && NamedBManifest))
        return Refuse(Error,TEXT("fulltown_b749_exact_root_descriptor_profile"));
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
    const bool BProfile=IsB749(Data), BUnit=BProfile && U.DispatchIndex==193;
    TSet<int32> BPartitions;
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
        if (BProfile)
        {
            TArray<UPrimitiveComponent*> Primitives; A->GetComponents<UPrimitiveComponent>(Primitives);
            if (Primitives.Num()!=Components.Num())
                return Refuse(Error,TEXT("fulltown_b749_unbound_owner_primitive"));
        }
        if (BUnit && (A->Tags.Num()!=2 || !A->GetRootComponent() ||
            A->GetRootComponent()->GetClass()!=USceneComponent::StaticClass() ||
            !LivingTownFullTown::SameQualifiedTransform(A->GetRootComponent()->GetComponentTransform(),FTransform::Identity)))
            return Refuse(Error,TEXT("fulltown_b749_identity_plain_scene_root"));
        int32 BPartition=INDEX_NONE;
        for (auto* C:Components)
        {
            if (C->ComponentTags.Num()!=1) return Refuse(Error,TEXT("fulltown_role_tag_roster"));
            const FString Tag=C->ComponentTags[0].ToString();
            if (!Tag.StartsWith(TEXT("LT_FTW_ROLE="))) return Refuse(Error,TEXT("fulltown_missing_stable_role_tag"));
            const FString Id=Tag.Mid(12);
            const int32 R=U.Roles.IndexOfByPredicate([&](const auto& Q){return Q.RoleId==Id;});
            if (R==INDEX_NONE || Seen.Contains(R)) return Refuse(Error,TEXT("fulltown_foreign_or_duplicate_role"));
            if (BUnit)
            {
                const int32 Partition=R/256;
                if (BPartition!=INDEX_NONE && BPartition!=Partition)
                    return Refuse(Error,TEXT("fulltown_b749_owner_mixes_partitions"));
                BPartition=Partition;
            }
            Seen.Add(R); T.Components.Add(C); T.RoleIndices.Add(R);
        }
        if (BUnit)
        {
            if (BPartition<0 || BPartition>2 || BPartitions.Contains(BPartition) ||
                Components.Num()!=(BPartition==2?237:256))
                return Refuse(Error,TEXT("fulltown_b749_exact_three_carrier_partitions"));
            BPartitions.Add(BPartition);
        }
    }
    if (BUnit && (Owners!=3 || BPartitions.Num()!=3))
        return Refuse(Error,TEXT("fulltown_b749_exact_three_carriers"));
    return (Owners>0 && Seen.Num()==U.Roles.Num()) || Refuse(Error,TEXT("fulltown_missing_saved_roles"));
}

bool ULivingTownFullTownStreamingSubsystem::ValidateComponent(ULivingTownFullTownTicket& T,int32 I,bool Registered,FString& Error)
{
    auto* C=T.Components[I].Get(); const auto& R=Data->Units[T.UnitIndex].Roles[T.RoleIndices[I]];
    UStaticMesh* Mesh=C?C->GetStaticMesh():nullptr;
    const bool HISM=R.Kind==ELivingTownFullTownComponentKind::HierarchicalInstances;
    const bool BOverrides=IsB749(Data) && Data->Units[T.UnitIndex].DispatchIndex==193;
    FString Predicate;
    FTransform HiddenActual=FTransform::Identity;
    if (!C) Predicate=TEXT("component_missing");
    else if (C->GetClass()!=(HISM?UHierarchicalInstancedStaticMeshComponent::StaticClass():UStaticMeshComponent::StaticClass())) Predicate=TEXT("component_class");
    else if (!Mesh) Predicate=TEXT("mesh_missing");
    else if (FSoftObjectPath(Mesh)!=R.Mesh) Predicate=TEXT("mesh_path");
    else if (IsB749(Data) && !Registered)
    {
        if (!T.Streaming) Predicate=TEXT("streaming_object_missing");
        else B749HiddenSerializedTransform(C,T.Streaming->LevelTransform,Registered,R.WorldTransform,HiddenActual,Predicate);
    }
    else if (!LivingTownFullTown::SameQualifiedTransform(C->GetComponentTransform(),R.WorldTransform)) Predicate=TEXT("registered_or_legacy_cached_world_transform");
    if (Predicate.IsEmpty() && C->GetCollisionProfileName()!=R.CollisionProfile) Predicate=TEXT("collision_profile");
    if (Predicate.IsEmpty() && C->GetCollisionEnabled()!=R.CollisionEnabled) Predicate=TEXT("collision_enabled");
    if (Predicate.IsEmpty() && C->IsComponentTickEnabled()) Predicate=TEXT("component_tick_enabled");
    if (Predicate.IsEmpty() && Registered && !C->IsRegistered()) Predicate=TEXT("registered_required");
    if (Predicate.IsEmpty() && C->GetNumMaterials()!=R.Slots.Num()) Predicate=TEXT("component_material_count");
    if (Predicate.IsEmpty() && Mesh->GetStaticMaterials().Num()!=R.Slots.Num()) Predicate=TEXT("mesh_material_slot_count");
    if (Predicate.IsEmpty() && (HISM?C->GetNumOverrideMaterials()!=R.Slots.Num():!StaticOverridesMatch(C,R,BOverrides))) Predicate=TEXT("stored_override_array");
    if (!Predicate.IsEmpty())
    {
        LogFirstComponentRefusal(T,I,Data->Units[T.UnitIndex],R,C,Mesh,Registered,Predicate);
        return Refuse(Error,TEXT("fulltown_component_mesh_transform_collision_or_material_roster"));
    }
    for (int32 S=0; S<R.Slots.Num(); ++S)
    {
        const auto& Slot=R.Slots[S]; const auto& Default=Mesh->GetStaticMaterials()[S]; auto* Effective=C->GetMaterial(S);
        if (Slot.SlotIndex!=S || FSoftObjectPath(Default.MaterialInterface.Get())!=Slot.OriginalDefault || Default.MaterialSlotName!=Slot.SlotName ||
            !Effective || FSoftObjectPath(Effective)!=((HISM || (BOverrides && !Slot.Override.IsNull()))?Slot.Override:Slot.OriginalDefault) ||
            uint8(Effective->GetBlendMode())!=Slot.BlendMode)
        {
            LogFirstComponentRefusal(T,I,Data->Units[T.UnitIndex],R,C,Mesh,Registered,TEXT("ordered_material_slot"),S);
            return Refuse(Error,TEXT("fulltown_exact_ordered_material_slot"));
        }
        if (HISM && (C->OverrideMaterials[S]!=Effective || !LivingTownMaterials::ValidateInstancedUsage(Effective,R.RoleId,R.Mesh.ToString(),S,Error)))
        { LogFirstComponentRefusal(T,I,Data->Units[T.UnitIndex],R,C,Mesh,Registered,TEXT("hism_override_or_material_usage"),S); return false; }
    }
    if (HISM && CastChecked<UHierarchicalInstancedStaticMeshComponent>(C)->GetInstanceCount()!=R.Instances.Num())
    {
        LogFirstComponentRefusal(T,I,Data->Units[T.UnitIndex],R,C,Mesh,Registered,TEXT("hism_instance_count"));
        return Refuse(Error,TEXT("fulltown_saved_hism_instance_count"));
    }
    return true;
}

bool ULivingTownFullTownStreamingSubsystem::AdvanceValidation(ULivingTownFullTownTicket& T,bool Registered,double Deadline,FString& Error)
{
    while (T.NextComponent<T.Components.Num() && FullTownCanValidate(FPlatformTime::Seconds(),Deadline,
           FrameComponents,ComponentBudget,FrameInstances,InstanceBudget))
    {
        const int32 I=T.NextComponent; const auto& R=Data->Units[T.UnitIndex].Roles[T.RoleIndices[I]];
        if (T.NextInstance==0) { ++FrameComponents; if (!ValidateComponent(T,I,Registered,Error)) return false; }
        if (R.Kind==ELivingTownFullTownComponentKind::HierarchicalInstances)
        {
            auto* H=CastChecked<UHierarchicalInstancedStaticMeshComponent>(T.Components[I].Get());
            while (T.NextInstance<R.Instances.Num() && FrameInstances<InstanceBudget && FPlatformTime::Seconds()<Deadline)
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

void ULivingTownFullTownStreamingSubsystem::AdvanceTickets()
{
    const double ControlStarted=FPlatformTime::Seconds(); LastValidationSeconds=0;
    // Safety/deadlines/retirement are never behind the validation-time break.
    // This control scan does not recreate geometry or change any acceptance rule.
    for (ULivingTownFullTownTicket* T:Tickets)
    {
        if (!T || T->Phase==ELivingTownFullTownPhase::Removed) continue;
        if (T->Phase==ELivingTownFullTownPhase::Unloading)
        {
            const auto State=T->Streaming?T->Streaming->GetLevelStreamingState():ELevelStreamingState::Removed;
            if (!T->Streaming || (State==ELevelStreamingState::Removed && !GetWorld()->GetStreamingLevels().Contains(T->Streaming.Get())))
            { T->Streaming=nullptr; T->Phase=ELivingTownFullTownPhase::Removed; }
            else if (FullTownDeadlineViolation(*T,ControlStarted,UnitDeadline)==EFullTownDeadlineViolation::Unload)
            { Fail(TEXT("fulltown_native_unload_deadline_reservation_retained")); break; }
            continue;
        }
        if (bFailed || bStopping) continue;
        if (!T->Accepts(Epoch,T->Token) || !T->Streaming) { Fail(TEXT("fulltown_stale_or_missing_ticket")); break; }
        if (T->Streaming->GetLevelStreamingState()==ELevelStreamingState::FailedToLoad)
        { Fail(TEXT("fulltown_native_map_failed_to_load")); break; }
        if (FullTownDeadlineViolation(*T,ControlStarted,UnitDeadline)==EFullTownDeadlineViolation::Unit)
        { Fail(TEXT("fulltown_native_unit_deadline")); break; }
        if (!Wanted.Contains(T->UnitIndex) && T->Phase!=ELivingTownFullTownPhase::Resident) { BeginDrain(*T); continue; }
        if (T->Phase==ELivingTownFullTownPhase::Resident && !Wanted.Contains(T->UnitIndex) && MayRetire(T->UnitIndex) && TransitionReservations()<2) BeginDrain(*T);
    }
    Tickets.RemoveAll([](const auto& T){return !T || T->Phase==ELivingTownFullTownPhase::Removed;});
    LastTicketControlSeconds=FPlatformTime::Seconds()-ControlStarted;
    if (bFailed || bStopping) return;

    // ONE shared target window, beginning at validation work, not before the
    // caller's owner/Cafe safety checks. Resident tickets cannot consume its turn.
    const double ValidationStarted=FPlatformTime::Seconds();
    const double Deadline=FullTownValidationDeadline(ValidationStarted,ValidationTargetMs);
    const int32 MaximumVisits=Tickets.Num();
    for (int32 Visit=0; Visit<MaximumVisits && FullTownCanValidate(FPlatformTime::Seconds(),Deadline,
         FrameComponents,ComponentBudget,FrameInstances,InstanceBudget); ++Visit)
    {
        const int32 Index=FullTownNextPendingTicket(Tickets,NextTicketCursor);
        if (Index==INDEX_NONE) break;
        ULivingTownFullTownTicket* T=Tickets[Index];
        const auto State=T->Streaming->GetLevelStreamingState(); FString Error;
        if (T->Phase==ELivingTownFullTownPhase::LoadingHidden && T->bLoadedEvent && State==ELevelStreamingState::LoadedNotVisible)
        {
            if (!GatherHidden(*T,Error)) { Fail(Error); break; }
            T->Phase=ELivingTownFullTownPhase::ValidatingHidden;
        }
        if (T->Phase==ELivingTownFullTownPhase::ValidatingHidden)
        {
            if (!AdvanceValidation(*T,false,Deadline,Error)) { Fail(Error); break; }
            bool OtherShowing=false;
            for (ULivingTownFullTownTicket* Other:Tickets) if (Other!=T && Other->Phase==ELivingTownFullTownPhase::MakingVisible) OtherShowing=true;
            if (T->NextComponent==T->Components.Num() && !OtherShowing)
            { T->NextComponent=0; T->NextInstance=0; T->Phase=ELivingTownFullTownPhase::MakingVisible; T->Streaming->SetShouldBeVisible(true); }
        }
        if (T->Phase==ELivingTownFullTownPhase::MakingVisible && T->bShownEvent && State==ELevelStreamingState::LoadedVisible)
        {
            if (!AdvanceValidation(*T,true,Deadline,Error)) { Fail(Error); break; }
            if (T->NextComponent==T->Components.Num())
            { T->Phase=ELivingTownFullTownPhase::Resident; ++ShownUnits; UE_LOG(LogTemp,Display,TEXT("FullTown unit resident %s token=%llu"),*Data->Units[T->UnitIndex].UnitId,T->Token); }
        }
    }
    LastValidationSeconds=FPlatformTime::Seconds()-ValidationStarted;
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
    LastPreValidationSafetySeconds=FPlatformTime::Seconds()-Now;
    AdvanceTickets();
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
    // Soft identity is observable during async boot; never dereference Data
    // until it exists. A requested profile does not imply manifest acceptance.
    const auto* StatusDriver=Driver.Get();
    const bool NamedBWorld=GetWorld() && UWorld::RemovePIEPrefix(GetWorld()->GetOutermost()->GetName())==B749RootPackage;
    const bool BRequested=IsB749(Data) || NamedBWorld || (StatusDriver &&
        StatusDriver->Manifest.ToSoftObjectPath().ToString()==B749Manifest);
    J->SetStringField(TEXT("scope"),BRequested?TEXT("IntegrationSubset_B749_U0131_66_Ground156_ExternalCafe81"):
        TEXT("IntegrationSubset_U0131_U0142_Ground151_ExternalCafe81"));
    if (BRequested)
    {
        J->SetStringField(TEXT("profile_id"),B749Profile);
        J->SetBoolField(TEXT("manifest_loaded"),Data!=nullptr);
        J->SetBoolField(TEXT("manifest_accepted"),Data!=nullptr && !bFailed && bManifestCompleted);
        J->SetNumberField(TEXT("declared_streamed_role_count"),971);
        J->SetNumberField(TEXT("external_cafe_part_count"),262);
    }
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
    J->SetNumberField(TEXT("last_pre_validation_safety_seconds"),LastPreValidationSafetySeconds);
    J->SetNumberField(TEXT("last_ticket_control_seconds"),LastTicketControlSeconds);
    J->SetNumberField(TEXT("last_validation_seconds"),LastValidationSeconds);
    J->SetNumberField(TEXT("next_pending_ticket_cursor"),NextTicketCursor);
    J->SetBoolField(TEXT("GPU_FPS_and_cooked_and_art_qualified"),false);
    TArray<TSharedPtr<FJsonValue>> Units;
    for (const ULivingTownFullTownTicket* T:Tickets)
    {
        auto U=MakeShared<FJsonObject>(); U->SetNumberField(TEXT("unit_index"),T->UnitIndex); U->SetNumberField(TEXT("token"),double(T->Token));
        U->SetNumberField(TEXT("phase"),int32(T->Phase)); U->SetBoolField(TEXT("cancelled"),T->bCancelled);
        U->SetStringField(TEXT("native_state"),T->Streaming?EnumToString(T->Streaming->GetLevelStreamingState()):TEXT("NO_STREAM_OBJECT"));
        U->SetBoolField(TEXT("loaded_event"),T->bLoadedEvent); U->SetBoolField(TEXT("shown_event"),T->bShownEvent);
        U->SetBoolField(TEXT("hidden_event"),T->bHiddenEvent); U->SetBoolField(TEXT("unloaded_event"),T->bUnloadedEvent);
        U->SetNumberField(TEXT("next_component"),T->NextComponent); U->SetNumberField(TEXT("next_instance"),T->NextInstance);
        U->SetNumberField(TEXT("captured_components"),T->Components.Num());
        U->SetBoolField(TEXT("loaded_level_present"),T->Streaming && T->Streaming->GetLoadedLevel()!=nullptr);
        U->SetNumberField(TEXT("age_seconds"),FMath::Max(0.0,FPlatformTime::Seconds()-T->StartedSeconds));
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
#include "Materials/Material.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownB749HiddenSerializedTransformTest,"LivingTown.FullTown.B749HiddenSerializedTransform",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownB749HiddenSerializedTransformTest::RunTest(const FString&)
{
    auto* Actor=NewObject<AActor>(GetTransientPackage());
    auto* Root=NewObject<USceneComponent>(Actor); Actor->SetRootComponent(Root);
    auto* Child=NewObject<UStaticMeshComponent>(Actor); Child->SetupAttachment(Root);
    Root->SetRelativeLocation_Direct(FVector::ZeroVector); Root->SetRelativeRotation_Direct(FRotator::ZeroRotator); Root->SetRelativeScale3D_Direct(FVector::OneVector);
    const FTransform Expected(FQuat::Identity,FVector(-4606.303115624708,-2905.3108644939884,336.09147160231004),FVector::OneVector);
    Child->SetRelativeLocation_Direct(Expected.GetTranslation()); Child->SetRelativeRotation_Direct(FRotator::ZeroRotator); Child->SetRelativeScale3D_Direct(FVector::OneVector);
    TestFalse(TEXT("fixture is unregistered"),Child->IsRegistered());
    TestFalse(TEXT("serialized nonidentity child does not initialize cached world"),LivingTownFullTown::SameQualifiedTransform(Child->GetComponentTransform(),Expected));
    FTransform Actual; FString Predicate;
    auto Check=[&](const FTransform& Want,bool Registered=false) { return B749HiddenSerializedTransform(Child,FTransform::Identity,Registered,Want,Actual,Predicate); };
    TestTrue(TEXT("hidden exact serialized G1 translation accepted"),Check(Expected));
    TestTrue(TEXT("readback retains exact declared transform"),LivingTownFullTown::SameQualifiedTransform(Actual,Expected));
    FTransform Wrong=Expected; Wrong.AddToTranslation(FVector(1,0,0)); TestFalse(TEXT("wrong expected translation refuses"),Check(Wrong));
    TestFalse(TEXT("registered phase cannot use hidden helper"),Check(Expected,true));
    Root->SetRelativeLocation_Direct(FVector(1,0,0)); TestFalse(TEXT("nonidentity serialized root refuses"),Check(Expected)); Root->SetRelativeLocation_Direct(FVector::ZeroVector);
    auto* Nested=NewObject<USceneComponent>(Actor); Nested->SetupAttachment(Root); Child->SetupAttachment(Nested); TestFalse(TEXT("nested parent refuses"),Check(Expected));
    Child->SetupAttachment(Root,TEXT("UnqualifiedSocket")); TestFalse(TEXT("socket attachment refuses"),Check(Expected)); Child->SetupAttachment(Root);
    Child->SetUsingAbsoluteLocation(true); TestFalse(TEXT("absolute child refuses"),Check(Expected)); Child->SetUsingAbsoluteLocation(false);
    TestFalse(TEXT("nonidentity streaming transform refuses"),B749HiddenSerializedTransform(Child,Wrong,false,Expected,Actual,Predicate));
    TestTrue(TEXT("restored exact hierarchy accepted"),Check(Expected));
    TestFalse(TEXT("helper did not register component"),Child->IsRegistered());
    TestFalse(TEXT("helper did not repair cached world"),LivingTownFullTown::SameQualifiedTransform(Child->GetComponentTransform(),Expected));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownB749OverrideArrayTest,"LivingTown.FullTown.B749ExactStoredOverrideArrays",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownB749OverrideArrayTest::RunTest(const FString&)
{
    auto* C=NewObject<UStaticMeshComponent>(); auto* M=NewObject<UMaterial>();
    FLivingTownFullTownRole Role; auto& Slot=Role.Slots.AddDefaulted_GetRef(); Slot.SlotIndex=0;
    TestTrue(TEXT("B empty stored array accepted"),StaticOverridesMatch(C,Role,true));
    TestTrue(TEXT("legacy empty array retained"),StaticOverridesMatch(C,Role,false));
    Slot.OriginalDefault=FSoftObjectPath(M); Slot.Override=FSoftObjectPath(M);
    TestFalse(TEXT("descriptor override cannot be silently absent"),StaticOverridesMatch(C,Role,true));
    C->OverrideMaterials.Add(M);
    TestTrue(TEXT("exact stored pointer accepted even equal to original default"),StaticOverridesMatch(C,Role,true));
    TestFalse(TEXT("legacy profile never admits stored override"),StaticOverridesMatch(C,Role,false));
    C->OverrideMaterials.Add(nullptr);
    TestFalse(TEXT("padded null slot refuses"),StaticOverridesMatch(C,Role,true));
    C->OverrideMaterials.SetNum(1); C->OverrideMaterials[0]=nullptr;
    TestFalse(TEXT("length1 null refuses"),StaticOverridesMatch(C,Role,true));
    Slot.Override.Reset(); C->OverrideMaterials.Empty();
    C->OverrideMaterials.Add(nullptr);
    TestFalse(TEXT("explicit null array differs from qualified empty array"),StaticOverridesMatch(C,Role,true));
    return true;
}
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
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownFullTownFairValidationTest,"LivingTown.FullTown.FairValidationBudgetAndDeadlines",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownFullTownFairValidationTest::RunTest(const FString&)
{
    auto* Ground=NewObject<ULivingTownFullTownTicket>(); Ground->Phase=ELivingTownFullTownPhase::Resident;
    auto* A=NewObject<ULivingTownFullTownTicket>(); A->bLoadedEvent=true; A->UnitIndex=0;
    auto* B=NewObject<ULivingTownFullTownTicket>(); B->bLoadedEvent=true; B->UnitIndex=1;
    TArray<TObjectPtr<ULivingTownFullTownTicket>> Work={Ground,A,B}; int32 Cursor=0;
    const double CallerStarted=10.0,ValidationStarted=20.0;
    TestTrue(TEXT("regression caller already consumed old1ms before resident first"),(ValidationStarted-CallerStarted)*1000.0>1.0);
    const double Deadline=FullTownValidationDeadline(ValidationStarted,1.0);
    TestTrue(TEXT("production shared validation slice starts AFTER safety work"),FullTownCanValidate(20.0001,Deadline,0,8,0,256));
    TestEqual(TEXT("resident ground cannot take pending selection"),FullTownNextPendingTicket(Work,Cursor),1);
    TestEqual(TEXT("second pending ticket gets next fair selection"),FullTownNextPendingTicket(Work,Cursor),2);
    TestEqual(TEXT("round robin returns to first pending"),FullTownNextPendingTicket(Work,Cursor),1);
    TestFalse(TEXT("same shared deadline not reset by next ticket"),FullTownCanValidate(20.0011,Deadline,0,8,0,256));
    TestFalse(TEXT("8 component cap retained"),FullTownCanValidate(20.0001,Deadline,8,8,0,256));
    TestFalse(TEXT("256 instance cap retained"),FullTownCanValidate(20.0001,Deadline,0,8,256,256));
    TestTrue(TEXT("resident first has no unit deadline"),FullTownDeadlineViolation(*Ground,181.0,180.0)==EFullTownDeadlineViolation::None);
    TestTrue(TEXT("production safety scan sees later pending expiry independently of exhausted validation slice"),FullTownDeadlineViolation(*A,181.0,180.0)==EFullTownDeadlineViolation::Unit);
    A->Phase=ELivingTownFullTownPhase::Unloading;
    TestTrue(TEXT("unload deadline remains independent"),FullTownDeadlineViolation(*A,181.0,180.0)==EFullTownDeadlineViolation::Unload);
    A->MarkCancelled(); TestEqual(TEXT("cancelled/unloading ticket cannot be scheduled"),FullTownNextPendingTicket(Work,Cursor),2);
    B->Phase=ELivingTownFullTownPhase::Resident; TestEqual(TEXT("all residents produce no pending work"),FullTownNextPendingTicket(Work,Cursor),INDEX_NONE);
    return true;
}

#endif
