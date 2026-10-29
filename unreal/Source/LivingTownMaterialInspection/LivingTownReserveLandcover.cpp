#include "LivingTownReserveLandcover.h"
#include "LivingTownTileData.h"
#include "Editor.h"
#include "Engine/World.h"
#include "Engine/StaticMeshActor.h"
#include "Engine/StaticMesh.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/Texture2D.h"
#include "EngineUtils.h"
#include "Landscape.h"
#include "LandscapeProxy.h"
#include "LandscapeInfo.h"
#include "LandscapeComponent.h"
#include "LandscapeEdit.h"
#include "LandscapeEditLayer.h"
#include "LandscapeLayerInfoObject.h"
#include "LandscapeSettings.h"
#include "LandscapeUtils.h"
#include "Materials/Material.h"
#include "MaterialDomain.h"
#include "Materials/MaterialInstance.h"
#include "Materials/MaterialExpressionCustom.h"
#include "Materials/MaterialExpressionLandscapeLayerBlend.h"
#include "StaticParameterSet.h"
#include "MaterialShared.h"
#include "RHIShaderPlatform.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "Misc/Paths.h"
#include "Misc/PackageName.h"
#include "Misc/FileHelper.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "HAL/FileManager.h"
#include "UObject/Package.h"
#include "CoreGlobals.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#endif

namespace
{
constexpr int32 Side=505, Channels=4, LandcoverSampleCount=Side*Side, Bytes=LandcoverSampleCount*Channels;
constexpr const TCHAR* MapPath=TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/ReserveLandscape_v001/L_ReserveLandscape_v001");
constexpr const TCHAR* MaterialPath=TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/ReserveLandscape_v001/M_ReserveLandscape_v001.M_ReserveLandscape_v001");
constexpr const TCHAR* Folder=TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/ReserveBiome_v001");
constexpr const TCHAR* WeightRelative=TEXT("Content/ReserveLandcoverSource_v001/Landcover_Actual229_505_RGBA8.bin");
constexpr const TCHAR* HeightRelative=TEXT("Content/ReserveLandscapeSource_v001/Height505.r16");
constexpr const TCHAR* WeightSHA=TEXT("d83c74821b884ad75a80a9efa278374fcfa3674f8a8cf40c27db3bd59ba69ad9");
constexpr const TCHAR* HeightSHA=TEXT("2b5839619c03277cc4e73bb97e0d250661e9aec1efe5efe61850e5c16170b5cb");
constexpr const TCHAR* LandscapeGuid=TEXT("43D98B784ED85B59DCB8E8A35B77809F");
constexpr const TCHAR* EditGuid=TEXT("ACD1BFF8470AC16A8FFF82965B8FD569");
const TCHAR* const Names[Channels]={TEXT("Meadow"),TEXT("WoodlandLitter"),TEXT("SteepRock"),TEXT("PondSoil")};
bool AppliedInThisProcess=false;

FString Json(const TSharedRef<FJsonObject>& O){FString Text;const auto Writer=TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Text);FJsonSerializer::Serialize(O,Writer);return Text;}
FString LandcoverErrorReply(const FString& Why){auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("ERROR"));O->SetStringField(TEXT("error"),Why);return Json(O);}
bool Fail(FString& Why,const TCHAR* Text){Why=Text;return false;}
bool Partition(const TArray<uint8>& Data){if(Data.Num()!=Bytes)return false;for(int32 I=0;I<LandcoverSampleCount;++I){int32 Sum=0;for(int32 K=0;K<Channels;++K)Sum+=Data[I*Channels+K];if(Sum!=255)return false;}return true;}
int32 Role(const FName& Name){for(int32 K=0;K<Channels;++K)if(Name==FName(Names[K]))return K;return INDEX_NONE;}
FString LayerPackage(int32 K){return FString::Printf(TEXT("%s/LI_%s_v001"),Folder,Names[K]);}
FString LayerObject(int32 K){return LayerPackage(K)+FString::Printf(TEXT(".LI_%s_v001"),Names[K]);}
bool HashEquals(const TArray<uint8>& Data,const TCHAR* Expected){FString H;return LivingTownTiles::HashBytes(Data,H)&&H==Expected;}
bool Source(TArray<uint8>& W,TArray<uint8>& H,FString& Why)
{
    if(!FFileHelper::LoadFileToArray(W,*FPaths::Combine(FPaths::ProjectDir(),WeightRelative))||!Partition(W)||!HashEquals(W,WeightSHA))return Fail(Why,TEXT("fixed_actual229_weight_source_shape_partition_or_sha"));
    if(!FFileHelper::LoadFileToArray(H,*FPaths::Combine(FPaths::ProjectDir(),HeightRelative))||H.Num()!=LandcoverSampleCount*2||!HashEquals(H,HeightSHA))return Fail(Why,TEXT("fixed_source_height_shape_or_sha"));return true;
}
bool Graph(UMaterial* M,FString& Why)
{
    if(!M||M->GetPathName()!=MaterialPath||M->MaterialDomain!=MD_Surface||M->GetBlendMode()!=BLEND_Opaque)return Fail(Why,TEXT("fixed_new_opaque_surface_material_required"));
    int32 Blends=0;
    for(UMaterialExpression* E:M->GetExpressions())
    {
        if(Cast<UMaterialExpressionCustom>(E))return Fail(Why,TEXT("legacy_custom_evaluator_refused"));
        if(const auto* B=Cast<UMaterialExpressionLandscapeLayerBlend>(E))
        {
            ++Blends;if(B->Layers.Num()!=Channels)return Fail(Why,TEXT("four_explicit_landcover_layer_inputs"));TSet<FName> Seen;
            for(const FLayerBlendInput& I:B->Layers){if(Role(I.LayerName)==INDEX_NONE||Seen.Contains(I.LayerName)||I.BlendType!=LB_WeightBlend||I.PreviewWeight!=0.f||!I.LayerInput.Expression||I.HeightInput.Expression)return Fail(Why,TEXT("typed_weight_blend_no_height_or_preview_fallback"));Seen.Add(I.LayerName);}
        }
    }
    return (Blends>=1&&Blends<=4)||Fail(Why,TEXT("new_native_layer_blend_graph_required"));
}
bool World(ALandscape*& L,ULandscapeInfo*& Info,FGuid& Guid,FString& Why)
{
    if(!IsInGameThread()||!GEditor||GEditor->PlayWorld)return Fail(Why,TEXT("editor_GT_no_PIE_required"));UWorld* W=GEditor->GetEditorWorldContext().World();
    if(!W||W->WorldType!=EWorldType::Editor||W->IsGameWorld()||W->GetOutermost()->GetName()!=MapPath)return Fail(Why,TEXT("fixed_editor_map_required"));
    int32 N=0;for(TActorIterator<ALandscapeProxy> It(W);It;++It){++N;L=Cast<ALandscape>(*It);}if(N!=1||!L||L->GetActorLabel(false)!=TEXT("LT_RESERVE_LANDSCAPE_v001")||L->GetLandscapeGuid().ToString(EGuidFormats::Digits)!=LandscapeGuid)return Fail(Why,TEXT("exact_qualified_Pond126_landscape_identity"));
    if(!L->GetActorLocation().Equals(FVector(-60000,-22400,4000),0.)||!L->GetActorScale3D().Equals(FVector(100,100,25),0.)||!L->GetActorRotation().Equals(FRotator::ZeroRotator,0.)||L->LandscapeComponents.Num()!=16||L->CollisionComponents.Num()!=16||L->IsNaniteEnabled()||L->CollisionMipLevel!=0||L->SimpleCollisionMipLevel!=0)return Fail(Why,TEXT("qualified_landscape_transform_layout_physics_required"));
    for(TActorIterator<AActor> It(W);It;++It)if(It->GetActorLabel(false).StartsWith(TEXT("LT_RESERVE_DENSITY500_")))return Fail(Why,TEXT("Actual229_source_only_future500_requires_new_explicit_lineage"));
    int32 Ponds=0;
    for(TActorIterator<AStaticMeshActor> It(W);It;++It)if(It->GetActorLabel(false)==TEXT("LT_RESERVE_POND_WATER_00"))
    {
        ++Ponds;const UStaticMeshComponent* C=It->GetStaticMeshComponent();
        if(!C||!C->GetStaticMesh()||C->GetStaticMesh()->GetPathName()!=TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/ReservePond_v001/SM_ReservePond_Water_v001.SM_ReservePond_Water_v001")||C->GetNumMaterials()!=1||!C->GetMaterial(0)||C->GetMaterial(0)->GetPathName()!=TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/ReservePond_v001/M_ReservePond_SingleLayerWater_v001.M_ReservePond_SingleLayerWater_v001")||!It->GetActorLocation().Equals(FVector(-22500,9500,2500),0.)||!It->GetActorRotation().Equals(FRotator::ZeroRotator,0.)||!It->GetActorScale3D().Equals(FVector::OneVector,0.)||C->GetCollisionEnabled()!=ECollisionEnabled::NoCollision)return Fail(Why,TEXT("qualified_Pond126_water_identity_required"));
    }
    if(Ponds!=1)return Fail(Why,TEXT("qualified_Pond126_one_water_actor_required"));
    const auto Layers=L->GetEditLayersConst();if(Layers.Num()!=1||!Layers[0]||Layers[0]->GetGuid().ToString(EGuidFormats::Digits)!=EditGuid)return Fail(Why,TEXT("exact_bound_single_edit_layer_GUID_required"));Guid=Layers[0]->GetGuid();Info=L->GetLandscapeInfo();
    int32 X0=0,Y0=0,X1=0,Y1=0;if(!Info||!Info->GetLandscapeExtent(X0,Y0,X1,Y1)||X0!=0||Y0!=0||X1!=504||Y1!=504)return Fail(Why,TEXT("exact505_native_vertex_extent_required"));return Graph(Cast<UMaterial>(L->LandscapeMaterial.Get()),Why);
}
bool Heights(ULandscapeInfo* Info,const TArray<uint8>& SourceHeight,FString& Why)
{
    TArray<uint16> V;V.SetNumZeroed(LandcoverSampleCount);{FLandscapeEditDataInterface D(Info,FGuid(),false);D.SetShouldDirtyPackage(false);D.GetHeightDataFast(0,0,504,504,V.GetData(),0);}
    for(int32 I=0;I<LandcoverSampleCount;++I)if(V[I]!=(uint16(SourceHeight[I*2])|(uint16(SourceHeight[I*2+1])<<8)))return Fail(Why,TEXT("any_source_height_sample_change_refused"));return true;
}
ULandscapeLayerInfoObject* StockVisibility()
{
    ULandscapeLayerInfoObject* V=ALandscapeProxy::VisibilityLayer;
    return V&&UE::Landscape::IsVisibilityLayer(V)&&V->GetPathName()==TEXT("/Engine/EngineResources/LandscapeVisibilityLayerInfo.LandscapeVisibilityLayerInfo")&&Role(V->GetLayerName())==INDEX_NONE?V:nullptr;
}
FString LandcoverObjectPath(const UObject* Object){return Object?Object->GetPathName():FString();}
TSharedRef<FJsonObject> LayerInventory(ALandscape* L,ULandscapeInfo* Info)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("schema"),TEXT("LivingTown.NativeLandcoverLayerInventory.v1"));O->SetNumberField(TEXT("native_frame"),double(GFrameCounter));O->SetStringField(TEXT("stock_visibility_object"),LandcoverObjectPath(StockVisibility()));TArray<TSharedPtr<FJsonValue>> Targets,Rows;
    for(const auto& P:L->GetTargetLayers()){auto X=MakeShared<FJsonObject>();X->SetStringField(TEXT("name"),P.Key.ToString());X->SetStringField(TEXT("target_layer_info"),LandcoverObjectPath(P.Value.LayerInfoObj.Get()));X->SetNumberField(TEXT("info_index_by_name"),Info->GetLayerInfoIndex(P.Key,L));X->SetBoolField(TEXT("is_stock_visibility_name"),StockVisibility()&&P.Key==StockVisibility()->GetLayerName());Targets.Add(MakeShared<FJsonValueObject>(X));}
    for(int32 I=0;I<Info->Layers.Num();++I){const FLandscapeInfoLayerSettings& V=Info->Layers[I];auto X=MakeShared<FJsonObject>();X->SetNumberField(TEXT("index"),I);X->SetStringField(TEXT("name"),V.GetLayerName().ToString());X->SetStringField(TEXT("layer_info"),LandcoverObjectPath(V.LayerInfoObj.Get()));X->SetStringField(TEXT("owner"),LandcoverObjectPath(V.Owner.Get()));X->SetBoolField(TEXT("is_stock_visibility_object"),V.LayerInfoObj.Get()==StockVisibility());Rows.Add(MakeShared<FJsonValueObject>(X));}
    O->SetArrayField(TEXT("targets"),Targets);O->SetArrayField(TEXT("info_layers"),Rows);return O;
}
bool WriteLayerInventory(ALandscape* L,ULandscapeInfo* Info,FString& Why)
{
    const FString Relative=FString::Printf(TEXT("Saved/ReserveLandcover_v001/BeforeApplyLayers_frame%llu.json"),static_cast<unsigned long long>(GFrameCounter));const FString File=FPaths::Combine(FPaths::ProjectDir(),Relative);IFileManager::Get().MakeDirectory(*FPaths::GetPath(File),true);
    return FFileHelper::SaveStringToFile(Json(LayerInventory(L,Info)),*File,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM,&IFileManager::Get(),FILEWRITE_NoReplaceExisting)||Fail(Why,TEXT("pre_mutation_layer_inventory_write_failed"));
}
bool VisibilityIdentity(ALandscape* L,ULandscapeInfo* Info,int32& Index,FString& Why)
{
    ULandscapeLayerInfoObject* V=StockVisibility();if(!V)return Fail(Why,TEXT("exact_engine_visibility_object_required"));const FLandscapeTargetLayerSettings* Target=L->GetTargetLayers().Find(V->GetLayerName());Index=Info->GetLayerInfoIndex(V,L);
    if(!Target||(Target->LayerInfoObj&&Target->LayerInfoObj!=V)||Index<0||Index>=Info->Layers.Num()||Info->Layers[Index].LayerInfoObj!=V||Info->Layers[Index].Owner.Get()!=L||Info->Layers[Index].GetLayerName()!=V->GetLayerName())return Fail(Why,TEXT("stock_visibility_target_info_identity_required"));return true;
}
bool VisibilityNoHolesUnallocated(ALandscape* L,ULandscapeInfo* Info,const FGuid& Guid,TArray<uint8>& Edit,TArray<uint8>& Merged,FString& Why)
{
    int32 Index=INDEX_NONE;if(!VisibilityIdentity(L,Info,Index,Why))return false;
    for(const ULandscapeComponent* C:L->LandscapeComponents)
    {
        if(!C||!C->GetLayerData(Guid))return Fail(Why,TEXT("actual_bound_edit_component_data_required_no_merged_fallback"));
        for(const FGuid& LayerGuid:{Guid,FGuid()})for(const FWeightmapLayerAllocationInfo& A:C->GetWeightmapLayerAllocations(LayerGuid))if(A.LayerInfo&&UE::Landscape::IsVisibilityLayer(A.LayerInfo))return Fail(Why,TEXT("preexisting_or_new_visibility_allocation_refused_preserve_narrow_no_holes_source"));
    }
    auto ReadPlane=[Info](const FGuid& LayerGuid,TArray<uint8>& Data){Data.SetNumZeroed(LandcoverSampleCount);FLandscapeEditDataInterface D(Info,LayerGuid,false);D.SetShouldDirtyPackage(false);D.GetWeightDataFast(StockVisibility(),0,0,504,504,Data.GetData(),Side);};ReadPlane(Guid,Edit);ReadPlane(FGuid(),Merged);
    for(int32 I=0;I<LandcoverSampleCount;++I)if(Edit[I]!=0||Merged[I]!=0)return Fail(Why,TEXT("nonzero_visibility_refused_no_holes_source"));return true;
}
bool LayerInfos(ALandscape* L,ULandscapeInfo* Info,TArray<ULandscapeLayerInfoObject*>& Objects,FString& Why)
{
    int32 VisibilityIndex=INDEX_NONE;if(!VisibilityIdentity(L,Info,VisibilityIndex,Why))return false;
    if(L->GetTargetLayers().Num()!=Info->Layers.Num())return Fail(Why,TEXT("actual_target_info_roster_cardinality_required"));Objects.SetNumZeroed(Channels);TSet<int32> Indices;
    for(const auto& P:L->GetTargetLayers())if(P.Key!=StockVisibility()->GetLayerName()&&Role(P.Key)==INDEX_NONE)return Fail(Why,TEXT("foreign_target_layer_refused"));
    for(int32 K=0;K<Channels;++K)
    {
        const FLandscapeTargetLayerSettings* Target=L->GetTargetLayers().Find(FName(Names[K]));ULandscapeLayerInfoObject* Obj=Target?Target->LayerInfoObj.Get():nullptr;
        if(!Obj||Obj->GetPathName()!=LayerObject(K)||Obj->GetLayerName()!=FName(Names[K])||Obj->GetBlendMethod()!=ELandscapeTargetLayerBlendMethod::None)return Fail(Why,TEXT("fixed_layerinfo_identity_and_independent_source_weight_mode"));
        const int32 Index=Info->GetLayerInfoIndex(Obj,L);if(Index<0||Index>=Info->Layers.Num()||Index==VisibilityIndex||Indices.Contains(Index)||Info->Layers[Index].LayerInfoObj!=Obj||Info->Layers[Index].Owner.Get()!=L)return Fail(Why,TEXT("actual_layerinfo_index_binding"));Indices.Add(Index);Objects[K]=Obj;
    }
    if(Indices.Num()+1!=Info->Layers.Num())return Fail(Why,TEXT("only_four_roles_plus_exact_stock_visibility_permitted"));return true;
}
bool Reorder(const TArray<uint8>& SourceWeights,const TArray<uint8>& PriorVisibility,const TArray<int32>& RoleToIndex,int32 NativeLayerCount,int32 VisibilityIndex,TArray<uint8>& Ordered)
{
    if(!Partition(SourceWeights)||PriorVisibility.Num()!=LandcoverSampleCount||RoleToIndex.Num()!=Channels||NativeLayerCount<1||NativeLayerCount>64||VisibilityIndex<0||VisibilityIndex>=NativeLayerCount)return false;TSet<int32> Seen;
    for(int32 V:RoleToIndex){if(V<0||V>=NativeLayerCount||V==VisibilityIndex||Seen.Contains(V))return false;Seen.Add(V);}if(Seen.Num()+1!=NativeLayerCount)return false;
    Ordered.SetNumZeroed(LandcoverSampleCount*NativeLayerCount);for(int32 I=0;I<LandcoverSampleCount;++I){Ordered[I*NativeLayerCount+VisibilityIndex]=PriorVisibility[I];for(int32 K=0;K<Channels;++K)Ordered[I*NativeLayerCount+RoleToIndex[K]]=SourceWeights[I*Channels+K];}return true;
}
bool ReadWeights(ULandscapeInfo* Info,const FGuid& Guid,const TArray<ULandscapeLayerInfoObject*>& Objects,TArray<uint8>& Interleaved,FString& Why)
{
    Interleaved.SetNumZeroed(Bytes);FLandscapeEditDataInterface D(Info,Guid,false);D.SetShouldDirtyPackage(false);
    for(int32 K=0;K<Channels;++K){TArray<uint8> Plane;Plane.SetNumZeroed(LandcoverSampleCount);D.GetWeightDataFast(Objects[K],0,0,504,504,Plane.GetData(),Side);for(int32 I=0;I<LandcoverSampleCount;++I)Interleaved[I*Channels+K]=Plane[I];}
    if(!Partition(Interleaved)||!HashEquals(Interleaved,WeightSHA))return Fail(Why,TEXT("all4x505_source_weight_bytes_or_partition_differ"));return true;
}
TArray<TSharedPtr<FJsonValue>> LandcoverTerrainParameterRows(const TArray<FStaticTerrainLayerWeightParameter>& Parameters)
{
    TArray<TSharedPtr<FJsonValue>> Rows;for(const FStaticTerrainLayerWeightParameter& P:Parameters){auto V=MakeShared<FJsonObject>();V->SetStringField(TEXT("layer"),P.LayerName.ToString());V->SetNumberField(TEXT("weightmap_index"),P.WeightmapIndex);Rows.Add(MakeShared<FJsonValueObject>(V));}return Rows;
}
bool LandcoverObserveComponentMaterial(const ULandscapeComponent* Component,const UMaterialInstance* Child,const TSharedRef<FJsonObject>& Out,bool& ShaderPending,bool& ShaderFailure,FString& Why)
{
    const UMaterialInterface* Cursor=Child;const UMaterialInstance* ParameterOwner=nullptr;TSet<const UMaterialInterface*> Seen;TArray<TSharedPtr<FJsonValue>> Chain;TMap<FName,int32> Effective;
    int32 InstanceDepth=0;
    while(const UMaterialInstance* Instance=Cast<UMaterialInstance>(Cursor))
    {
        if(InstanceDepth>=8||Seen.Contains(Instance)||Instance->GetOutermost()->GetName()!=MapPath||!Instance->GetMaterial()||Instance->GetMaterial()->GetPathName()!=MaterialPath)return Fail(Why,TEXT("bounded_owned_component_material_parent_chain_required"));Seen.Add(Instance);
        const auto& Local=Instance->GetEditorOnlyStaticParameters().TerrainLayerWeightParameters;auto Row=MakeShared<FJsonObject>();Row->SetStringField(TEXT("path"),Instance->GetPathName());Row->SetStringField(TEXT("class"),Instance->GetClass()->GetPathName());Row->SetNumberField(TEXT("depth"),InstanceDepth);Row->SetStringField(TEXT("parent"),LandcoverObjectPath(Instance->Parent.Get()));Row->SetBoolField(TEXT("has_static_permutation_resource"),Instance->bHasStaticPermutationResource);Row->SetArrayField(TEXT("raw_local_terrain_weight_parameters"),LandcoverTerrainParameterRows(Local));Chain.Add(MakeShared<FJsonValueObject>(Row));
        if(!Local.IsEmpty())
        {
            if(ParameterOwner)return Fail(Why,TEXT("multiple_terrain_weight_parameter_owners_refused"));ParameterOwner=Instance;
            for(const FStaticTerrainLayerWeightParameter& P:Local){if(Role(P.LayerName)==INDEX_NONE||P.WeightmapIndex<0||Effective.Contains(P.LayerName))return Fail(Why,TEXT("foreign_duplicate_or_negative_effective_terrain_parameter"));Effective.Add(P.LayerName,P.WeightmapIndex);}
        }
        Cursor=Instance->Parent.Get();++InstanceDepth;
    }
    const UMaterial* Base=Cast<UMaterial>(Cursor);
    if(!Base||Base->GetPathName()!=MaterialPath||InstanceDepth!=2||!ParameterOwner||ParameterOwner==Child)return Fail(Why,TEXT("exact_child_combination_parent_fixed_base_chain_required"));
    auto BaseRow=MakeShared<FJsonObject>();BaseRow->SetStringField(TEXT("path"),Base->GetPathName());BaseRow->SetStringField(TEXT("class"),Base->GetClass()->GetPathName());BaseRow->SetNumberField(TEXT("depth"),InstanceDepth);BaseRow->SetStringField(TEXT("parent"),TEXT(""));BaseRow->SetArrayField(TEXT("raw_local_terrain_weight_parameters"),TArray<TSharedPtr<FJsonValue>>());Chain.Add(MakeShared<FJsonValueObject>(BaseRow));
    TMap<FName,int32> Allocated;
    for(const FWeightmapLayerAllocationInfo& A:Component->GetWeightmapLayerAllocations()){if(!A.LayerInfo||Role(A.LayerInfo->GetLayerName())==INDEX_NONE||Allocated.Contains(A.LayerInfo->GetLayerName()))return Fail(Why,TEXT("actual_component_allocation_parameter_identity"));Allocated.Add(A.LayerInfo->GetLayerName(),A.WeightmapTextureIndex);}
    if(Allocated.Num()!=Effective.Num())return Fail(Why,TEXT("effective_parent_terrain_parameter_count_matches_allocations"));for(const auto& A:Allocated){const int32* V=Effective.Find(A.Key);if(!V||*V!=A.Value)return Fail(Why,TEXT("effective_parent_terrain_parameters_match_actual_allocation_indices"));}
    Out->SetStringField(TEXT("material_observation_schema"),TEXT("LivingTown.NativeLandcoverInheritedMaterialResource.v1"));Out->SetArrayField(TEXT("material_inheritance_chain"),Chain);Out->SetStringField(TEXT("effective_parameter_source"),ParameterOwner->GetPathName());Out->SetArrayField(TEXT("effective_static_weight_parameters"),LandcoverTerrainParameterRows(ParameterOwner->GetEditorOnlyStaticParameters().TerrainLayerWeightParameters));
    const EShaderPlatform Platform=GMaxRHIShaderPlatform;const auto Quality=GetCurrentMaterialQualityLevelChecked();const FMaterialResource* Resource=Child->GetMaterialResource(Platform,Quality);auto Info=MakeShared<FJsonObject>();Info->SetNumberField(TEXT("query_shader_platform"),int32(Platform));Info->SetNumberField(TEXT("query_material_quality"),int32(Quality));Info->SetBoolField(TEXT("resource_present"),Resource!=nullptr);Info->SetStringField(TEXT("instruction_count_status"),TEXT("MEL_REPRESENTATIVE_ORDINARY_LANDSCAPE_BASEPASS_INSTRUCTIONS_UNAVAILABLE_NOT_ZERO_COST"));Info->SetBoolField(TEXT("instruction_budget_qualified"),false);Info->SetBoolField(TEXT("native_does_not_compile_flush_or_wait"),true);
    if(!Resource){ShaderPending=true;Out->SetObjectField(TEXT("compiled_resource"),Info);return true;}
    const UMaterialInterface* ResourceOwner=Resource->GetMaterialInterface();Info->SetStringField(TEXT("resource_owner"),LandcoverObjectPath(ResourceOwner));Info->SetNumberField(TEXT("resource_shader_platform"),int32(Resource->GetShaderPlatform()));Info->SetNumberField(TEXT("resource_quality"),int32(Resource->GetQualityLevel()));Info->SetBoolField(TEXT("game_thread_shader_map_complete"),Resource->IsGameThreadShaderMapComplete());TArray<TSharedPtr<FJsonValue>> Errors;for(const FString& E:Resource->GetCompileErrors())Errors.Add(MakeShared<FJsonValueString>(E));Info->SetArrayField(TEXT("compile_errors"),Errors);
    if(ResourceOwner!=ParameterOwner||Resource->GetShaderPlatform()!=Platform||(Resource->GetQualityLevel()!=Quality&&Resource->GetQualityLevel()!=EMaterialQualityLevel::Num))return Fail(Why,TEXT("actual_current_platform_quality_resource_owner_must_match_effective_parent"));
    const FMaterialShaderMap* ShaderMap=Resource->GetGameThreadShaderMap();Info->SetBoolField(TEXT("shader_map_present"),ShaderMap!=nullptr);Info->SetBoolField(TEXT("shader_map_compilation_finalized"),ShaderMap&&ShaderMap->IsCompilationFinalized());Info->SetBoolField(TEXT("shader_map_compiled_successfully"),ShaderMap&&ShaderMap->CompiledSuccessfully());
    // SetGameThreadShaderMap caches IsComplete(this,true); compiler lifecycle flags can remain false under per-shader-job DDC.
    Info->SetBoolField(TEXT("compiler_lifecycle_flags_are_diagnostic_not_readiness_gates"),true);
    const bool Complete=ShaderMap&&Resource->IsGameThreadShaderMapComplete()&&Errors.IsEmpty();
    Info->SetBoolField(TEXT("semantic_game_thread_shader_map_ready"),Complete);
    if(!Errors.IsEmpty())ShaderFailure=true;else if(!Complete)ShaderPending=true;
    Info->SetBoolField(TEXT("sampler_fetch_available"),Complete);
    if(Complete)
    {
        Info->SetNumberField(TEXT("num_samplers"),Resource->GetSamplerUsage());uint32 VS=0,PS=0;Resource->GetEstimatedNumTextureSamples(VS,PS);Info->SetNumberField(TEXT("num_vertex_texture_samples"),VS);Info->SetNumberField(TEXT("num_pixel_texture_samples"),PS);
        const auto& Compiled=ShaderMap->GetShaderMapId().GetTerrainLayerWeightParameters();TSet<FName> CompiledNames;TMap<FName,int32> CompiledPresent;
        for(const FStaticTerrainLayerWeightParameter& P:Compiled){if(Role(P.LayerName)==INDEX_NONE||P.WeightmapIndex<INDEX_NONE||CompiledNames.Contains(P.LayerName))return Fail(Why,TEXT("bounded_actual_shader_map_terrain_permutation"));CompiledNames.Add(P.LayerName);if(P.WeightmapIndex>=0)CompiledPresent.Add(P.LayerName,P.WeightmapIndex);else if(Allocated.Contains(P.LayerName))return Fail(Why,TEXT("nonzero_allocated_layer_absent_from_compiled_permutation"));}
        if(CompiledPresent.Num()!=Allocated.Num())return Fail(Why,TEXT("actual_shader_map_role_count_matches_allocations"));for(const auto& A:Allocated){const int32* V=CompiledPresent.Find(A.Key);if(!V||*V!=A.Value)return Fail(Why,TEXT("actual_compiled_permutation_matches_component_allocation"));}
        Info->SetArrayField(TEXT("actual_shader_map_terrain_weight_parameters"),LandcoverTerrainParameterRows(Compiled));Info->SetBoolField(TEXT("compiled_permutation_matches_all_actual_allocations"),true);
    }
    Out->SetObjectField(TEXT("compiled_resource"),Info);return true;
}

TSharedRef<FJsonObject> Receipt(ALandscape* L,const FGuid& Guid)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("schema"),TEXT("LivingTown.NativeReserveLandcover.v1"));O->SetStringField(TEXT("map"),MapPath);O->SetStringField(TEXT("material"),MaterialPath);O->SetStringField(TEXT("landscape"),L->GetPathName());O->SetStringField(TEXT("edit_layer_guid"),Guid.ToString(EGuidFormats::Digits));O->SetStringField(TEXT("source_weight_sha256"),WeightSHA);O->SetStringField(TEXT("source_height_sha256"),HeightSHA);O->SetNumberField(TEXT("width"),Side);O->SetNumberField(TEXT("height"),Side);O->SetNumberField(TEXT("source_weight_bytes"),Bytes);O->SetNumberField(TEXT("native_frame"),double(GFrameCounter));O->SetBoolField(TEXT("asset_save_or_Runtime_paint"),false);O->SetBoolField(TEXT("pixel_visible_layer_pruning_GPU_or_FPS_qualified"),false);return O;
}
}

FString ULivingTownReserveLandcover::ApplyReserveLandcoverPreview()
{
    FString Token;FString Project=FPaths::ConvertRelativePathToFull(FPaths::ProjectDir());FPaths::NormalizeDirectoryName(Project);
    if(!FParse::Value(FCommandLine::Get(),TEXT("LivingTownReserveLandcoverAuthor="),Token)||Token!=WeightSHA||!Project.EndsWith(TEXT("/Author/Project"))||AppliedInThisProcess)return LandcoverErrorReply(TEXT("explicit_exact_source_author_flag_private_project_once_required"));
    ALandscape* L=nullptr;ULandscapeInfo* Info=nullptr;FGuid Guid;FString Why;TArray<uint8> W,H;
    const bool WorldReady=World(L,Info,Guid,Why);if(L&&Info&&!WriteLayerInventory(L,Info,Why))return LandcoverErrorReply(Why);
    if(!WorldReady||!Source(W,H,Why)||!L->IsUpToDate()||!Heights(Info,H,Why))return LandcoverErrorReply(Why.IsEmpty()?TEXT("native_merge_must_be_ready_before_author"):Why);
    if(!GetDefault<ULandscapeSettings>()->GetDefaultLayerInfoObject().IsNull())return LandcoverErrorReply(TEXT("external_default_layerinfo_template_refused"));
    int32 VisibilityIndex=INDEX_NONE;TArray<uint8> VisibilityBeforeEdit,VisibilityBeforeMerged;
    if(!VisibilityNoHolesUnallocated(L,Info,Guid,VisibilityBeforeEdit,VisibilityBeforeMerged,Why))return LandcoverErrorReply(Why);if(!VisibilityIdentity(L,Info,VisibilityIndex,Why))return LandcoverErrorReply(Why);
    const FString VisibilityTargetBefore=LandcoverObjectPath(L->GetTargetLayers().FindChecked(StockVisibility()->GetLayerName()).LayerInfoObj.Get());
    for(const auto& P:L->GetTargetLayers())if(P.Key!=StockVisibility()->GetLayerName()&&(Role(P.Key)==INDEX_NONE||P.Value.LayerInfoObj))return LandcoverErrorReply(TEXT("preexisting_or_foreign_target_layerinfo_refused"));
    for(int32 K=0;K<Channels;++K)if(FindPackage(nullptr,*LayerPackage(K))||FPackageName::DoesPackageExist(LayerPackage(K)))return LandcoverErrorReply(TEXT("new_layerinfo_packages_must_be_absent_no_overwrite"));
    AppliedInThisProcess=true;L->Modify();
    for(int32 K=0;K<Channels;++K)
    {
        const FString FileName=FString::Printf(TEXT("LI_%s_v001"),Names[K]);ULandscapeLayerInfoObject* Obj=UE::Landscape::CreateTargetLayerInfo(FName(Names[K]),Folder,FileName);
        if(!Obj||Obj->GetPathName()!=LayerObject(K))return LandcoverErrorReply(TEXT("new_exact_layerinfo_factory_failed_partial_state_retained"));
        Obj->SetBlendMethod(ELandscapeTargetLayerBlendMethod::None,false);
        const FLandscapeTargetLayerSettings Setting(Obj);if(L->HasTargetLayer(FName(Names[K])))L->UpdateTargetLayer(FName(Names[K]),Setting,false);else L->AddTargetLayer(FName(Names[K]),Setting,false);
    }
    Info->UpdateLayerInfoMap(L,true);TArray<ULandscapeLayerInfoObject*> Objects;if(!LayerInfos(L,Info,Objects,Why))return LandcoverErrorReply(Why);
    TArray<int32> Indices;TSet<ULandscapeLayerInfoObject*> Dirty;for(int32 K=0;K<Channels;++K){Indices.Add(Info->GetLayerInfoIndex(Objects[K],L));Dirty.Add(Objects[K]);}
    VisibilityIndex=Info->GetLayerInfoIndex(StockVisibility(),L);const int32 NativeLayerCount=Info->Layers.Num();
    TArray<uint8> Ordered;if(!Reorder(W,VisibilityBeforeEdit,Indices,NativeLayerCount,VisibilityIndex,Ordered))return LandcoverErrorReply(TEXT("closed_bulk_ordering_failed"));
    {FLandscapeEditDataInterface D(Info,Guid,true);D.SetAlphaData(Dirty,0,0,504,504,Ordered.GetData(),Side*NativeLayerCount,ELandscapeLayerPaintingRestriction::None);D.Flush();}
    TArray<uint8> Read;if(!ReadWeights(Info,Guid,Objects,Read,Why)||Read!=W||!Heights(Info,H,Why))return LandcoverErrorReply(Why);
    TArray<uint8> VisibilityAfterEdit,VisibilityAfterMerged;if(!VisibilityNoHolesUnallocated(L,Info,Guid,VisibilityAfterEdit,VisibilityAfterMerged,Why)||VisibilityBeforeEdit!=VisibilityAfterEdit||VisibilityBeforeMerged!=VisibilityAfterMerged||VisibilityTargetBefore!=LandcoverObjectPath(L->GetTargetLayers().FindChecked(StockVisibility()->GetLayerName()).LayerInfoObj.Get()))return LandcoverErrorReply(Why.IsEmpty()?TEXT("stock_visibility_changed_by_bulk_write"):Why);
    L->RequestLayersContentUpdate(ELandscapeLayerUpdateMode::Update_Weightmap_All);auto O=Receipt(L,Guid);O->SetStringField(TEXT("status"),TEXT("APPLIED_EXACT_EDIT_LAYER_WEIGHTS_PENDING_NATIVE_MERGE_AND_SAVE"));O->SetBoolField(TEXT("all255025_heights_unchanged"),true);O->SetBoolField(TEXT("all1020100_edit_layer_weight_bytes_exact"),true);O->SetObjectField(TEXT("actual_layer_inventory_after_apply"),LayerInventory(L,Info));O->SetNumberField(TEXT("native_bulk_layers"),NativeLayerCount);O->SetNumberField(TEXT("native_bulk_row_stride"),Side*NativeLayerCount);O->SetBoolField(TEXT("stock_visibility_edit_merged_zero_unallocated_preserved"),true);return Json(O);
}

FString ULivingTownReserveLandcover::ReadReserveLandcoverPreview()
{
    ALandscape* L=nullptr;ULandscapeInfo* Info=nullptr;FGuid Guid;FString Why;TArray<uint8> W,H;
    if(!World(L,Info,Guid,Why)||!Source(W,H,Why))return LandcoverErrorReply(Why);auto O=Receipt(L,Guid);
    if(!L->IsUpToDate()){O->SetStringField(TEXT("status"),TEXT("PENDING_NATIVE_WEIGHTMAP_MERGE"));return Json(O);}const bool MapDirty=L->GetOutermost()->IsDirty();
    TArray<ULandscapeLayerInfoObject*> Objects;if(!LayerInfos(L,Info,Objects,Why)||!Heights(Info,H,Why))return LandcoverErrorReply(Why);TArray<uint8> VisibilityEdit,VisibilityMerged;if(!VisibilityNoHolesUnallocated(L,Info,Guid,VisibilityEdit,VisibilityMerged,Why))return LandcoverErrorReply(Why);FString VisibilityEditHash,VisibilityMergedHash;if(!LivingTownTiles::HashBytes(VisibilityEdit,VisibilityEditHash)||!LivingTownTiles::HashBytes(VisibilityMerged,VisibilityMergedHash))return LandcoverErrorReply(TEXT("visibility_read_hash_failed"));TArray<uint8> Edit,Merged;
    if(!ReadWeights(Info,Guid,Objects,Edit,Why)||!ReadWeights(Info,FGuid(),Objects,Merged,Why)||Edit!=W||Merged!=W)return LandcoverErrorReply(Why);
    TArray<TSharedPtr<FJsonValue>> Components;TSet<FIntPoint> Bases;bool MaterialShaderPending=false,MaterialShaderFailure=false;
    for(const ULandscapeComponent* C:L->LandscapeComponents)
    {
        if(!C||!C->IsRegistered()||Bases.Contains(C->GetSectionBase()))return LandcoverErrorReply(TEXT("exact_registered_component_set_required"));Bases.Add(C->GetSectionBase());auto Row=MakeShared<FJsonObject>();Row->SetStringField(TEXT("component"),C->GetPathName());Row->SetNumberField(TEXT("base_x"),C->GetSectionBase().X);Row->SetNumberField(TEXT("base_y"),C->GetSectionBase().Y);
        TArray<TSharedPtr<FJsonValue>> Allocations;const auto& Textures=C->GetWeightmapTextures();
        for(const FWeightmapLayerAllocationInfo& A:C->GetWeightmapLayerAllocations())
        {
            if(!A.LayerInfo||Role(A.LayerInfo->GetLayerName())==INDEX_NONE||A.WeightmapTextureIndex>=Textures.Num()||A.WeightmapTextureChannel>3||!Textures[A.WeightmapTextureIndex])return LandcoverErrorReply(TEXT("bounded_actual_component_weight_allocation_required"));auto X=MakeShared<FJsonObject>();X->SetStringField(TEXT("layer"),A.LayerInfo->GetLayerName().ToString());X->SetStringField(TEXT("layer_info"),A.LayerInfo->GetPathName());X->SetNumberField(TEXT("texture_index"),A.WeightmapTextureIndex);X->SetNumberField(TEXT("channel"),A.WeightmapTextureChannel);X->SetStringField(TEXT("texture"),Textures[A.WeightmapTextureIndex]->GetPathName());Allocations.Add(MakeShared<FJsonValueObject>(X));
        }
        Row->SetArrayField(TEXT("allocations"),Allocations);TArray<TSharedPtr<FJsonValue>> Tex;
        for(const UTexture2D* T:Textures){if(!T||!T->Source.IsValid())return LandcoverErrorReply(TEXT("actual_weight_texture_source_required"));auto X=MakeShared<FJsonObject>();X->SetStringField(TEXT("path"),T->GetPathName());X->SetNumberField(TEXT("source_width"),T->Source.GetSizeX());X->SetNumberField(TEXT("source_height"),T->Source.GetSizeY());X->SetNumberField(TEXT("source_mips"),T->Source.GetNumMips());X->SetBoolField(TEXT("srgb"),T->SRGB);X->SetBoolField(TEXT("platform_residency_claimed"),false);Tex.Add(MakeShared<FJsonValueObject>(X));}Row->SetArrayField(TEXT("weightmap_textures"),Tex);
        TArray<TSharedPtr<FJsonValue>> Mats;const int32 N=C->GetMaterialInstanceCount(true);if(N<1||N>16)return LandcoverErrorReply(TEXT("bounded_actual_desktop_MI_roster_required"));
        for(int32 I=0;I<N;++I){const UMaterialInstance* M=C->GetMaterialInstance(I,true);const UMaterial* Base=M?M->GetMaterial():nullptr;if(!Base||Base->GetPathName()!=MaterialPath)return LandcoverErrorReply(TEXT("owned_component_MI_base_required"));auto X=MakeShared<FJsonObject>();X->SetStringField(TEXT("path"),M->GetPathName());TArray<TSharedPtr<FJsonValue>> Params;for(const FStaticTerrainLayerWeightParameter& P:M->GetEditorOnlyStaticParameters().TerrainLayerWeightParameters){if(Role(P.LayerName)==INDEX_NONE)return LandcoverErrorReply(TEXT("foreign_static_layer_parameter_refused"));auto V=MakeShared<FJsonObject>();V->SetStringField(TEXT("layer"),P.LayerName.ToString());V->SetNumberField(TEXT("weightmap_index"),P.WeightmapIndex);Params.Add(MakeShared<FJsonValueObject>(V));}X->SetArrayField(TEXT("static_weight_parameters"),Params);if(!LandcoverObserveComponentMaterial(C,M,X,MaterialShaderPending,MaterialShaderFailure,Why))return LandcoverErrorReply(Why);Mats.Add(MakeShared<FJsonValueObject>(X));}Row->SetArrayField(TEXT("materials"),Mats);Components.Add(MakeShared<FJsonValueObject>(Row));
    }
    if(Bases.Num()!=16||L->GetOutermost()->IsDirty()!=MapDirty)return LandcoverErrorReply(TEXT("read_changed_map_dirty_or_component_set"));
    O->SetArrayField(TEXT("components"),Components);O->SetBoolField(TEXT("all_component_resource_observations_collected_before_any_budget_assertion"),true);
    if(MaterialShaderFailure){O->SetStringField(TEXT("status"),TEXT("ERROR_NATIVE_COMPONENT_MATERIAL_SHADER_COMPILE"));O->SetStringField(TEXT("error"),TEXT("actual_component_resource_compile_errors_all_observations_retained"));return Json(O);}
    if(MaterialShaderPending){O->SetStringField(TEXT("status"),TEXT("PENDING_NATIVE_COMPONENT_MATERIAL_SHADER_MAP"));return Json(O);}
    const FString Relative=FString::Printf(TEXT("Saved/ReserveLandcover_v001/MergedWeights505_frame%llu.rgba8"),static_cast<unsigned long long>(GFrameCounter));const FString File=FPaths::Combine(FPaths::ProjectDir(),Relative);IFileManager::Get().MakeDirectory(*FPaths::GetPath(File),true);
    if(IFileManager::Get().FileExists(*File)){TArray<uint8> Prior;if(!FFileHelper::LoadFileToArray(Prior,*File)||Prior!=Merged)return LandcoverErrorReply(TEXT("readback_file_no_overwrite"));}else if(!FFileHelper::SaveArrayToFile(Merged,*File,&IFileManager::Get(),FILEWRITE_NoReplaceExisting))return LandcoverErrorReply(TEXT("readback_file_save_failed"));
    O->SetArrayField(TEXT("components"),Components);O->SetObjectField(TEXT("actual_layer_inventory"),LayerInventory(L,Info));O->SetStringField(TEXT("stock_visibility_edit_sha256"),VisibilityEditHash);O->SetStringField(TEXT("stock_visibility_merged_sha256"),VisibilityMergedHash);O->SetBoolField(TEXT("stock_visibility_edit_merged_allzero_unallocated"),true);O->SetStringField(TEXT("weight_file_project_relative"),Relative);O->SetBoolField(TEXT("all1020100_edit_and_merged_weight_bytes_exact"),true);O->SetBoolField(TEXT("all255025_heights_unchanged"),true);O->SetBoolField(TEXT("map_dirty_before"),MapDirty);O->SetBoolField(TEXT("map_dirty_after"),L->GetOutermost()->IsDirty());O->SetStringField(TEXT("status"),TEXT("READ_ONLY_EXACT_NATIVE_LANDCOVER_WEIGHTS_COMPONENTS"));return Json(O);
}

#if WITH_DEV_AUTOMATION_TESTS
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownLandcoverSourceFixture,"LivingTown.ReserveLandcover.ClosedSourceFixture",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownLandcoverSourceFixture::RunTest(const FString&)
{
    TArray<uint8> W,H;FString Why;if(!Source(W,H,Why)){AddError(Why);return false;}TestTrue(TEXT("Actual source partition and SHA"),Partition(W));
    TArray<uint8> Bad=W;Bad[0]^=1;TestFalse(TEXT("A changed source byte breaks SHA"),HashEquals(Bad,WeightSHA));Bad=W;Bad.SetNum(Bytes-1);TestFalse(TEXT("Truncated source refused"),Partition(Bad));
    const TArray<int32> Perm={4,0,3,1};const int32 NativeLayerCount=Channels+1;const int32 VisibilityIndex=2;TArray<uint8> PriorVisibility;PriorVisibility.SetNumUninitialized(LandcoverSampleCount);for(int32 I=0;I<LandcoverSampleCount;++I)PriorVisibility[I]=uint8(I%251);TArray<uint8> Ordered;
    TestTrue(TEXT("Actual source remaps four roles around engine Visibility slot"),Reorder(W,PriorVisibility,Perm,NativeLayerCount,VisibilityIndex,Ordered));
    for(int32 I=0;I<LandcoverSampleCount;++I){if(Ordered[I*NativeLayerCount+VisibilityIndex]!=PriorVisibility[I]){AddError(TEXT("Prior Visibility byte changed by packer"));return false;}for(int32 K=0;K<Channels;++K)if(Ordered[I*NativeLayerCount+Perm[K]]!=W[I*Channels+K]){AddError(TEXT("Cross-source role/index mismatch"));return false;}}
    TestFalse(TEXT("Repeated native layer index refused"),Reorder(W,PriorVisibility,TArray<int32>{0,0,3,4},NativeLayerCount,VisibilityIndex,Ordered));TestFalse(TEXT("Role cannot overwrite stock Visibility slot"),Reorder(W,PriorVisibility,TArray<int32>{0,1,2,4},NativeLayerCount,VisibilityIndex,Ordered));TestFalse(TEXT("Unrecognized extra native layer slot refused"),Reorder(W,PriorVisibility,Perm,NativeLayerCount+1,VisibilityIndex,Ordered));return true;
}
#endif
