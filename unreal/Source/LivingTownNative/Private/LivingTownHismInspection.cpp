#include "LivingTownHismInspection.h"
#include "Components/HierarchicalInstancedStaticMeshComponent.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "GameFramework/Actor.h"
#include "Materials/MaterialInterface.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "UObject/Package.h"
#include "UObject/UnrealType.h"
#include "UObject/UObjectGlobals.h"
#include <limits>

namespace LivingTownHismInspectionInternal
{
constexpr int32 HismInspectionMaximumInstances=20000;
constexpr int32 HismInspectionMaximumMembers=256;
constexpr int32 HismInspectionMaximumMaterials=64;
FString HismInspectionSerialize(const TSharedRef<FJsonObject>& HismInspectionObject)
{
    FString HismInspectionResult;
    FJsonSerializer::Serialize(HismInspectionObject,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&HismInspectionResult));
    return HismInspectionResult;
}
FString HismInspectionError(const TCHAR* HismInspectionReason)
{
    auto HismInspectionObject=MakeShared<FJsonObject>();
    HismInspectionObject->SetStringField(TEXT("schema"),TEXT("LivingTown.BoundedHismInspection.v1"));
    HismInspectionObject->SetStringField(TEXT("status"),TEXT("ERROR"));
    HismInspectionObject->SetStringField(TEXT("error"),HismInspectionReason);
    HismInspectionObject->SetBoolField(TEXT("operation_writes_or_repairs"),false);
    return HismInspectionSerialize(HismInspectionObject);
}
bool HismInspectionCountAllowed(int32 HismInspectionCount,int32 HismInspectionMaximum)
{
    return HismInspectionCount>=0&&HismInspectionCount<=HismInspectionMaximum;
}
}

FString ULivingTownHismInspection::ReadHismComponent(UHierarchicalInstancedStaticMeshComponent* Component)
{
    using namespace LivingTownHismInspectionInternal;
    if(!IsInGameThread())return HismInspectionError(TEXT("game_thread_required"));
    if(!IsValid(Component)||!Component->IsA<UHierarchicalInstancedStaticMeshComponent>()||Component->IsTemplate()||!Component->GetClass()->HasAnyClassFlags(CLASS_Native))return HismInspectionError(TEXT("live_native_HISM_required"));
    const UHierarchicalInstancedStaticMeshComponent* HismInspectionComponent=Component;
    const AActor* HismInspectionOwner=HismInspectionComponent->GetOwner();
    const UWorld* HismInspectionWorld=HismInspectionComponent->GetWorld();
    if(!IsValid(HismInspectionOwner)||HismInspectionOwner->IsTemplate()||HismInspectionOwner->IsActorBeingDestroyed()||HismInspectionComponent->GetOuter()!=HismInspectionOwner||!IsValid(HismInspectionWorld)||HismInspectionOwner->GetWorld()!=HismInspectionWorld)return HismInspectionError(TEXT("valid_owner_outer_world_required"));
    if(HismInspectionWorld->WorldType!=EWorldType::Editor&&HismInspectionWorld->WorldType!=EWorldType::Game&&HismInspectionWorld->WorldType!=EWorldType::PIE)return HismInspectionError(TEXT("live_editor_game_or_PIE_world_required"));
    const UClass* HismInspectionParent=UHierarchicalInstancedStaticMeshComponent::StaticClass();
    const FIntProperty* HismInspectionBuilt=FindFProperty<FIntProperty>(HismInspectionParent,TEXT("NumBuiltInstances"));
    const FIntProperty* HismInspectionRender=FindFProperty<FIntProperty>(HismInspectionParent,TEXT("InstanceCountToRender"));
    const FArrayProperty* HismInspectionSorted=FindFProperty<FArrayProperty>(HismInspectionParent,TEXT("SortedInstances"));
    const FIntProperty* HismInspectionSortedItem=HismInspectionSorted?CastField<FIntProperty>(HismInspectionSorted->Inner):nullptr;
    const FBoolProperty* HismInspectionDensity=FindFProperty<FBoolProperty>(HismInspectionParent,TEXT("bEnableDensityScaling"));
    const FBoolProperty* HismInspectionTranslated=FindFProperty<FBoolProperty>(HismInspectionParent,TEXT("bUseTranslatedInstanceSpace"));
    if(!HismInspectionBuilt||!HismInspectionRender||!HismInspectionSorted||!HismInspectionSortedItem||!HismInspectionDensity||!HismInspectionTranslated)return HismInspectionError(TEXT("exact_parent_property_types_required"));
    for(const FProperty* HismInspectionProperty:{static_cast<const FProperty*>(HismInspectionBuilt),static_cast<const FProperty*>(HismInspectionRender),static_cast<const FProperty*>(HismInspectionSorted),static_cast<const FProperty*>(HismInspectionDensity),static_cast<const FProperty*>(HismInspectionTranslated)})
        if(FindFProperty<FProperty>(HismInspectionComponent->GetClass(),HismInspectionProperty->GetFName())!=HismInspectionProperty)return HismInspectionError(TEXT("subclass_must_retain_exact_parent_fields"));
    const int32 HismInspectionInstanceCount=HismInspectionComponent->GetInstanceCount();
    const int32 HismInspectionRenderCount=HismInspectionComponent->GetNumRenderInstances();
    const int32 HismInspectionBuiltCount=HismInspectionBuilt->GetPropertyValue_InContainer(HismInspectionComponent);
    const int32 HismInspectionToRender=HismInspectionRender->GetPropertyValue_InContainer(HismInspectionComponent);
    FScriptArrayHelper HismInspectionArray(HismInspectionSorted,HismInspectionSorted->ContainerPtrToValuePtr<void>(HismInspectionComponent));
    const auto& HismInspectionMembers=HismInspectionOwner->GetInstanceComponents();
    const int32 HismInspectionMaterialCount=HismInspectionComponent->GetNumMaterials();
    if(!HismInspectionCountAllowed(HismInspectionInstanceCount,HismInspectionMaximumInstances)||!HismInspectionCountAllowed(HismInspectionRenderCount,HismInspectionMaximumInstances)||!HismInspectionCountAllowed(HismInspectionBuiltCount,HismInspectionMaximumInstances)||!HismInspectionCountAllowed(HismInspectionToRender,HismInspectionMaximumInstances)||!HismInspectionCountAllowed(HismInspectionArray.Num(),HismInspectionMaximumInstances)||!HismInspectionCountAllowed(HismInspectionMembers.Num(),HismInspectionMaximumMembers)||!HismInspectionCountAllowed(HismInspectionMaterialCount,HismInspectionMaximumMaterials))return HismInspectionError(TEXT("fixed_finite_count_cap_exceeded"));
    const float HismInspectionDistanceScale=HismInspectionComponent->InstanceLODDistanceScale;
    if(!FMath::IsFinite(HismInspectionDistanceScale))return HismInspectionError(TEXT("finite_instance_LOD_distance_scale_required"));
    const UPackage* HismInspectionPackage=HismInspectionComponent->GetOutermost();
    const UPackage* HismInspectionMapPackage=HismInspectionWorld->GetOutermost();
    if(!HismInspectionPackage||!HismInspectionMapPackage)return HismInspectionError(TEXT("live_package_required"));
    const bool HismInspectionDirtyBefore=HismInspectionPackage->IsDirty(),HismInspectionMapDirtyBefore=HismInspectionMapPackage->IsDirty();
    auto HismInspectionObject=MakeShared<FJsonObject>();
    HismInspectionObject->SetStringField(TEXT("schema"),TEXT("LivingTown.BoundedHismInspection.v1"));
    HismInspectionObject->SetStringField(TEXT("component"),HismInspectionComponent->GetPathName());
    HismInspectionObject->SetStringField(TEXT("class"),HismInspectionComponent->GetClass()->GetPathName());
    HismInspectionObject->SetStringField(TEXT("owner"),HismInspectionOwner->GetPathName());
    HismInspectionObject->SetStringField(TEXT("owner_class"),HismInspectionOwner->GetClass()->GetPathName());
    HismInspectionObject->SetStringField(TEXT("outer"),HismInspectionComponent->GetOuter()->GetPathName());
    HismInspectionObject->SetStringField(TEXT("world"),HismInspectionWorld->GetPathName());
    HismInspectionObject->SetStringField(TEXT("map"),HismInspectionMapPackage->GetName());
    HismInspectionObject->SetNumberField(TEXT("world_type"),int32(HismInspectionWorld->WorldType));
    HismInspectionObject->SetNumberField(TEXT("engine_frame"),double(GFrameCounter));
#if WITH_EDITOR
    HismInspectionObject->SetStringField(TEXT("owner_label"),HismInspectionOwner->GetActorLabel(false));
    HismInspectionObject->SetBoolField(TEXT("owner_label_available"),true);
#else
    HismInspectionObject->SetStringField(TEXT("owner_label"),TEXT(""));
    HismInspectionObject->SetBoolField(TEXT("owner_label_available"),false);
#endif
    const UStaticMesh* HismInspectionMesh=HismInspectionComponent->GetStaticMesh();
    HismInspectionObject->SetStringField(TEXT("mesh"),HismInspectionMesh?HismInspectionMesh->GetPathName():FString());
    TArray<TSharedPtr<FJsonValue>> HismInspectionMaterialPaths,HismInspectionSortedValues,HismInspectionMembership;
    for(int32 HismInspectionIndex=0;HismInspectionIndex<HismInspectionMaterialCount;++HismInspectionIndex){const UMaterialInterface* HismInspectionMaterial=HismInspectionComponent->GetMaterial(HismInspectionIndex);HismInspectionMaterialPaths.Add(MakeShared<FJsonValueString>(HismInspectionMaterial?HismInspectionMaterial->GetPathName():FString()));}
    for(int32 HismInspectionIndex=0;HismInspectionIndex<HismInspectionArray.Num();++HismInspectionIndex)HismInspectionSortedValues.Add(MakeShared<FJsonValueNumber>(HismInspectionSortedItem->GetPropertyValue(HismInspectionArray.GetRawPtr(HismInspectionIndex))));
    for(const UActorComponent* HismInspectionMember:HismInspectionMembers)HismInspectionMembership.Add(MakeShared<FJsonValueString>(HismInspectionMember?HismInspectionMember->GetPathName():FString()));
    HismInspectionObject->SetArrayField(TEXT("materials"),HismInspectionMaterialPaths);HismInspectionObject->SetArrayField(TEXT("SortedInstances"),HismInspectionSortedValues);HismInspectionObject->SetArrayField(TEXT("owner_instance_components"),HismInspectionMembership);
    HismInspectionObject->SetNumberField(TEXT("instance_count"),HismInspectionInstanceCount);HismInspectionObject->SetNumberField(TEXT("render_instance_count"),HismInspectionRenderCount);HismInspectionObject->SetNumberField(TEXT("NumBuiltInstances"),HismInspectionBuiltCount);HismInspectionObject->SetNumberField(TEXT("InstanceCountToRender"),HismInspectionToRender);
    HismInspectionObject->SetBoolField(TEXT("bEnableDensityScaling"),HismInspectionDensity->GetPropertyValue_InContainer(HismInspectionComponent));HismInspectionObject->SetBoolField(TEXT("bUseTranslatedInstanceSpace"),HismInspectionTranslated->GetPropertyValue_InContainer(HismInspectionComponent));
    HismInspectionObject->SetBoolField(TEXT("registered"),HismInspectionComponent->IsRegistered());HismInspectionObject->SetBoolField(TEXT("async_building"),HismInspectionComponent->IsAsyncBuilding());HismInspectionObject->SetBoolField(TEXT("tree_fully_built"),HismInspectionComponent->IsTreeFullyBuilt());
    HismInspectionObject->SetBoolField(TEXT("owner_root_is_component"),HismInspectionOwner->GetRootComponent()==HismInspectionComponent);HismInspectionObject->SetBoolField(TEXT("exact_single_actor_instance_member"),HismInspectionMembers.Num()==1&&HismInspectionMembers[0]==HismInspectionComponent);
    HismInspectionObject->SetNumberField(TEXT("creation_method_value"),int32(HismInspectionComponent->CreationMethod));HismInspectionObject->SetStringField(TEXT("creation_method_name"),StaticEnum<EComponentCreationMethod>()->GetNameStringByValue(int64(HismInspectionComponent->CreationMethod)));
    int32 HismInspectionStart=0,HismInspectionEnd=0;HismInspectionComponent->GetCullDistances(HismInspectionStart,HismInspectionEnd);HismInspectionObject->SetNumberField(TEXT("start_cull_cm"),HismInspectionStart);HismInspectionObject->SetNumberField(TEXT("end_cull_cm"),HismInspectionEnd);HismInspectionObject->SetNumberField(TEXT("forced_lod_model"),HismInspectionComponent->GetForcedLodModel());HismInspectionObject->SetNumberField(TEXT("instance_LOD_distance_scale"),HismInspectionDistanceScale);
    HismInspectionObject->SetBoolField(TEXT("visible_flag"),HismInspectionComponent->IsVisible());HismInspectionObject->SetBoolField(TEXT("hidden_in_game"),HismInspectionComponent->bHiddenInGame);HismInspectionObject->SetBoolField(TEXT("owner_hidden"),HismInspectionOwner->IsHidden());HismInspectionObject->SetNumberField(TEXT("collision_enabled"),int32(HismInspectionComponent->GetCollisionEnabled()));HismInspectionObject->SetBoolField(TEXT("can_affect_navigation"),HismInspectionComponent->CanEverAffectNavigation());
    HismInspectionObject->SetBoolField(TEXT("package_dirty_before"),HismInspectionDirtyBefore);HismInspectionObject->SetBoolField(TEXT("package_dirty_after"),HismInspectionPackage->IsDirty());HismInspectionObject->SetBoolField(TEXT("map_dirty_before"),HismInspectionMapDirtyBefore);HismInspectionObject->SetBoolField(TEXT("map_dirty_after"),HismInspectionMapPackage->IsDirty());
    if(HismInspectionPackage->IsDirty()!=HismInspectionDirtyBefore||HismInspectionMapPackage->IsDirty()!=HismInspectionMapDirtyBefore)return HismInspectionError(TEXT("read_changed_dirty_state"));
    HismInspectionObject->SetNumberField(TEXT("finite_instance_cap"),HismInspectionMaximumInstances);HismInspectionObject->SetBoolField(TEXT("operation_writes_or_repairs"),false);HismInspectionObject->SetBoolField(TEXT("visible_instances_LOD_GPU_or_FPS_qualified"),false);
    HismInspectionObject->SetStringField(TEXT("scope"),TEXT("Game-thread native HISM identity/typed parent fields/public readiness; render count is pool state, not visible/drawn leaf count; host binds source/map/group authority; no rebuild/flush/wait/save"));
    HismInspectionObject->SetStringField(TEXT("status"),TEXT("READ_ONLY_BOUNDED_NATIVE_HISM_SNAPSHOT"));
    return HismInspectionSerialize(HismInspectionObject);
}

#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownHismInspectionBoundary,"LivingTown.HismInspection.BoundedReadOnly",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownHismInspectionBoundary::RunTest(const FString&)
{
    using namespace LivingTownHismInspectionInternal;
    auto HismInspectionDecode=[](const FString& HismInspectionText){TSharedPtr<FJsonObject> HismInspectionResult;FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(HismInspectionText),HismInspectionResult);return HismInspectionResult;};
    auto HismInspectionNull=HismInspectionDecode(ULivingTownHismInspection::ReadHismComponent(nullptr));
    TestTrue(TEXT("Null refuses with explicit bounded schema"),HismInspectionNull.IsValid()&&HismInspectionNull->GetStringField(TEXT("status"))==TEXT("ERROR")&&HismInspectionNull->GetStringField(TEXT("schema"))==TEXT("LivingTown.BoundedHismInspection.v1"));
    auto HismInspectionCDO=HismInspectionDecode(ULivingTownHismInspection::ReadHismComponent(GetMutableDefault<UHierarchicalInstancedStaticMeshComponent>()));TestEqual(TEXT("CDO is not a live observation"),HismInspectionCDO->GetStringField(TEXT("status")),FString(TEXT("ERROR")));
    auto* HismInspectionOwnerless=NewObject<UHierarchicalInstancedStaticMeshComponent>(GetTransientPackage());auto HismInspectionOwnerlessResult=HismInspectionDecode(ULivingTownHismInspection::ReadHismComponent(HismInspectionOwnerless));TestEqual(TEXT("Ownerless refuses without register/repair"),HismInspectionOwnerlessResult->GetStringField(TEXT("error")),FString(TEXT("valid_owner_outer_world_required")));
    TestTrue(TEXT("Fixed cap includes endpoints"),HismInspectionCountAllowed(0,HismInspectionMaximumInstances)&&HismInspectionCountAllowed(20000,HismInspectionMaximumInstances));TestFalse(TEXT("Cap rejects negative"),HismInspectionCountAllowed(-1,HismInspectionMaximumInstances));TestFalse(TEXT("Cap rejects one-over without allocating huge JSON"),HismInspectionCountAllowed(20001,HismInspectionMaximumInstances));
    UWorld* HismInspectionTestWorld=UWorld::CreateWorld(EWorldType::Game,false,MakeUniqueObjectName(GetTransientPackage(),UWorld::StaticClass(),TEXT("HismInspectionBoundaryWorld")),GetTransientPackage(),false);
    if(!TestNotNull(TEXT("Transient test world"),HismInspectionTestWorld))return false;
    AActor* HismInspectionTestOwner=HismInspectionTestWorld->SpawnActor<AActor>();
    if(!TestNotNull(TEXT("Transient test owner"),HismInspectionTestOwner)){HismInspectionTestWorld->DestroyWorld(false);return false;}
    auto* HismInspectionPending=NewObject<UHierarchicalInstancedStaticMeshComponent>(HismInspectionTestOwner,NAME_None,RF_Transient);
    const bool HismInspectionBefore=HismInspectionTestWorld->GetOutermost()->IsDirty();auto HismInspectionLive=HismInspectionDecode(ULivingTownHismInspection::ReadHismComponent(HismInspectionPending));
    TestTrue(TEXT("Live owned unregistered native pending state can be observed without repair"),HismInspectionLive.IsValid()&&HismInspectionLive->GetStringField(TEXT("status"))==TEXT("READ_ONLY_BOUNDED_NATIVE_HISM_SNAPSHOT"));
    if(HismInspectionLive.IsValid()&&HismInspectionLive->GetStringField(TEXT("status"))!=TEXT("ERROR")){
        TestEqual(TEXT("Actual world identity returned"),HismInspectionLive->GetStringField(TEXT("world")),HismInspectionTestWorld->GetPathName());TestEqual(TEXT("Actual owner identity returned"),HismInspectionLive->GetStringField(TEXT("owner")),HismInspectionTestOwner->GetPathName());TestFalse(TEXT("Reader does not register pending component"),HismInspectionLive->GetBoolField(TEXT("registered")));TestEqual(TEXT("Actual zero count retained"),HismInspectionLive->GetNumberField(TEXT("instance_count")),0.);TestFalse(TEXT("Read is not GPU qualification"),HismInspectionLive->GetBoolField(TEXT("visible_instances_LOD_GPU_or_FPS_qualified")));TestFalse(TEXT("Read has no mutation authority"),HismInspectionLive->GetBoolField(TEXT("operation_writes_or_repairs")));
    }
    const float HismInspectionSavedDistanceScale=HismInspectionPending->InstanceLODDistanceScale;
    HismInspectionPending->InstanceLODDistanceScale=std::numeric_limits<float>::quiet_NaN();auto HismInspectionNaN=HismInspectionDecode(ULivingTownHismInspection::ReadHismComponent(HismInspectionPending));TestEqual(TEXT("NaN scalar refuses explicitly before JSON numeric output"),HismInspectionNaN->GetStringField(TEXT("error")),FString(TEXT("finite_instance_LOD_distance_scale_required")));
    HismInspectionPending->InstanceLODDistanceScale=std::numeric_limits<float>::infinity();auto HismInspectionInfinity=HismInspectionDecode(ULivingTownHismInspection::ReadHismComponent(HismInspectionPending));TestEqual(TEXT("Infinite scalar refuses explicitly before JSON numeric output"),HismInspectionInfinity->GetStringField(TEXT("error")),FString(TEXT("finite_instance_LOD_distance_scale_required")));
    HismInspectionPending->InstanceLODDistanceScale=HismInspectionSavedDistanceScale;
    TestEqual(TEXT("Observation preserved transient world dirty state"),HismInspectionTestWorld->GetOutermost()->IsDirty(),HismInspectionBefore);TestFalse(TEXT("Observation did not silently register"),HismInspectionPending->IsRegistered());
    HismInspectionTestWorld->DestroyWorld(false);return true;
}
#endif
