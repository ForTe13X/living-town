#include "LivingTownStaticMeshCollisionInspection.h"
#include "Engine/StaticMesh.h"
#include "Engine/StaticMeshSourceData.h"
#include "MeshDescription.h"
#include "MeshDescriptionBase.h"
#include "StaticMeshAttributes.h"
#include "StaticMeshResources.h"
#include "PhysicsEngine/BodySetup.h"
#include "PhysicsEngine/BodyInstance.h"
#include "PhysicsEngine/AggregateGeom.h"
#include "Interfaces/Interface_CollisionDataProvider.h"
#include "Chaos/TriangleMeshImplicitObject.h"
#include "Misc/ScopeTryLock.h"
#include "UObject/Package.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "Containers/StringConv.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "GameFramework/Actor.h"
#include "Editor.h"
#include "UObject/Class.h"

namespace LivingTownStaticMeshCollisionInspectionInternal
{
constexpr int32 StaticCollisionMaximumVertices=50000;
constexpr int32 StaticCollisionMaximumTriangles=20000;
constexpr int32 StaticCollisionMaximumIndices=60000;
constexpr int32 StaticCollisionMaximumLODs=8;
constexpr int32 StaticCollisionMaximumSections=64;
constexpr int32 StaticCollisionMaximumUVChannels=8;
constexpr int32 StaticCollisionMaximumShapes=8;
constexpr int32 StaticCollisionMaximumSimpleElements=256;
constexpr int32 StaticCollisionMaximumJsonBytes=16*1024*1024;

bool StaticCollisionCount(int64 Value,int64 Maximum){return Value>=0&&Value<=Maximum;}
bool StaticCollisionFinite(const FVector3f& Point){return FMath::IsFinite(Point.X)&&FMath::IsFinite(Point.Y)&&FMath::IsFinite(Point.Z);}
bool StaticCollisionIndices(int32 A,int32 B,int32 C,int32 Vertices){return A>=0&&B>=0&&C>=0&&A<Vertices&&B<Vertices&&C<Vertices&&A!=B&&B!=C&&A!=C;}
uint32 StaticCollisionBits(float Value){uint32 Bits=0;FMemory::Memcpy(&Bits,&Value,4);return Bits;}
TSharedRef<FJsonValue> StaticCollisionPoint(const FVector3f& Point)
{
    return MakeShared<FJsonValueArray>(TArray<TSharedPtr<FJsonValue>>{MakeShared<FJsonValueNumber>(double(StaticCollisionBits(Point.X))),MakeShared<FJsonValueNumber>(double(StaticCollisionBits(Point.Y))),MakeShared<FJsonValueNumber>(double(StaticCollisionBits(Point.Z)))});
}
TSharedRef<FJsonValue> StaticCollisionTriangle(int32 A,int32 B,int32 C)
{
    return MakeShared<FJsonValueArray>(TArray<TSharedPtr<FJsonValue>>{MakeShared<FJsonValueNumber>(A),MakeShared<FJsonValueNumber>(B),MakeShared<FJsonValueNumber>(C)});
}
FString StaticCollisionJson(const TSharedRef<FJsonObject>& Object)
{
    FString Text;FJsonSerializer::Serialize(Object,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Text));
    FTCHARToUTF8 Encoded(*Text);if(Encoded.Length()>StaticCollisionMaximumJsonBytes)return TEXT("{\"schema\":\"LivingTown.BoundedStaticMeshCollisionInspection.v1\",\"status\":\"ERROR\",\"error\":\"bounded_JSON_size_exceeded\",\"operation_writes_or_repairs\":false}");
    return Text;
}
const TCHAR* StaticCollisionMode(ECollisionTraceFlag Mode)
{
    switch(Mode){case CTF_UseDefault:return TEXT("CTF_UseDefault");case CTF_UseSimpleAndComplex:return TEXT("CTF_UseSimpleAndComplex");case CTF_UseSimpleAsComplex:return TEXT("CTF_UseSimpleAsComplex");case CTF_UseComplexAsSimple:return TEXT("CTF_UseComplexAsSimple");default:return TEXT("UNKNOWN_ENUM_VALUE");}
}
struct FStaticCollisionSnapshot
{
    TSharedRef<FJsonObject> Object=MakeShared<FJsonObject>();
    UStaticMesh* Mesh=nullptr;
    const UBodySetup* Body=nullptr;
    UPackage* MeshPackage=nullptr;
    UPackage* BodyPackage=nullptr;
    bool MeshDirty=false,BodyDirty=false,BodyObserved=false;
    FStaticCollisionSnapshot()
    {
        Object->SetStringField(TEXT("schema"),TEXT("LivingTown.BoundedStaticMeshCollisionInspection.v1"));
        Object->SetBoolField(TEXT("operation_writes_or_repairs"),false);Object->SetBoolField(TEXT("caller_source_binding_required"),true);
        Object->SetBoolField(TEXT("source_equality_saved_Cold_capsule_Map_Game_art_or_FPS_qualified"),false);
        Object->SetStringField(TEXT("position_format"),TEXT("native_float32_components_as_uint32_bits_no_position_tolerance"));
        auto Caps=MakeShared<FJsonObject>();Caps->SetNumberField(TEXT("vertices_each_domain_and_aggregate_cooked"),StaticCollisionMaximumVertices);Caps->SetNumberField(TEXT("triangles_each_domain_and_aggregate_cooked"),StaticCollisionMaximumTriangles);Caps->SetNumberField(TEXT("render_indices"),StaticCollisionMaximumIndices);Caps->SetNumberField(TEXT("LODs"),StaticCollisionMaximumLODs);Caps->SetNumberField(TEXT("sections"),StaticCollisionMaximumSections);Caps->SetNumberField(TEXT("UV_channels"),StaticCollisionMaximumUVChannels);Caps->SetNumberField(TEXT("cooked_shapes"),StaticCollisionMaximumShapes);Caps->SetNumberField(TEXT("simple_elements"),StaticCollisionMaximumSimpleElements);Caps->SetNumberField(TEXT("JSON_bytes"),StaticCollisionMaximumJsonBytes);Object->SetObjectField(TEXT("fixed_caps"),Caps);
    }
    FString Finish(const TCHAR* Status,const TCHAR* Reason)
    {
        if(MeshPackage){Object->SetBoolField(TEXT("package_dirty_before"),MeshDirty);Object->SetBoolField(TEXT("package_dirty_after"),MeshPackage->IsDirty());if(MeshDirty!=MeshPackage->IsDirty()){Status=TEXT("ERROR");Reason=TEXT("read_changed_mesh_package_dirty_state");}}
        if(BodyPackage){Object->SetBoolField(TEXT("body_package_dirty_before"),BodyDirty);Object->SetBoolField(TEXT("body_package_dirty_after"),BodyPackage->IsDirty());if(BodyDirty!=BodyPackage->IsDirty()){Status=TEXT("ERROR");Reason=TEXT("read_changed_body_package_dirty_state");}}
        if(BodyObserved&&Mesh){if(Mesh->IsCompiling()){Status=TEXT("ERROR");Reason=TEXT("mesh_started_compiling_during_read");}else if(Mesh->GetBodySetup()!=Body){Status=TEXT("ERROR");Reason=TEXT("body_identity_changed_during_read");}}
        Object->SetStringField(TEXT("status"),Status);Object->SetStringField(TEXT("reason"),Reason);return StaticCollisionJson(Object);
    }
};

bool StaticCollisionCachedMD(UStaticMesh* Mesh,TSharedRef<FJsonObject> Output,FString& Failure)
{
    const int32 LODs=Mesh->GetNumSourceModels();if(!StaticCollisionCount(LODs,StaticCollisionMaximumLODs)){Failure=TEXT("source_LOD_cap");return false;}
    Output->SetNumberField(TEXT("source_LODs"),LODs);
    if(LODs==0){Output->SetStringField(TEXT("state"),TEXT("SOURCE_MODEL_NOT_INITIALIZED"));return true;}
    const FStaticMeshSourceModel& Source=Mesh->GetSourceModel(0);FScopeTryLock TryLock(&Source.StaticMeshDescriptionBulkDataCS);
    if(!TryLock.IsLocked()){Output->SetStringField(TEXT("state"),TEXT("BUSY_NO_WAIT"));return true;}
    const UStaticMeshDescriptionBulkData* Bulk=Source.StaticMeshDescriptionBulkData;
    if(!Bulk){Output->SetStringField(TEXT("state"),TEXT("SOURCE_MODEL_NOT_INITIALIZED"));return true;}
    if(!Bulk->HasCachedMeshDescription()){Output->SetStringField(TEXT("state"),TEXT("NOT_RESIDENT_NO_LOAD"));return true;}
    const UMeshDescriptionBase* Wrapper=Bulk->GetMeshDescription();if(!Wrapper){Failure=TEXT("cached_MD_wrapper_inconsistent");return false;}
    const FMeshDescription& Description=Wrapper->GetMeshDescription();
    if(!StaticCollisionCount(Description.Vertices().Num(),StaticCollisionMaximumVertices)||!StaticCollisionCount(Description.Vertices().GetArraySize(),StaticCollisionMaximumVertices)||!StaticCollisionCount(Description.Triangles().Num(),StaticCollisionMaximumTriangles)||!StaticCollisionCount(Description.Triangles().GetArraySize(),StaticCollisionMaximumTriangles)){Failure=TEXT("cached_MD_count_or_ID_extent_cap");return false;}
    FStaticMeshConstAttributes Attributes(Description);const auto Positions=Attributes.GetVertexPositions();TArray<TSharedPtr<FJsonValue>> Vertices,Triangles;
    for(const FVertexID ID:Description.Vertices().GetElementIDs())
    {
        const FVector3f Point=Positions[ID];if(!StaticCollisionFinite(Point)){Failure=TEXT("nonfinite_cached_MD_position");return false;}auto Row=MakeShared<FJsonObject>();Row->SetNumberField(TEXT("id"),ID.GetValue());Row->SetField(TEXT("position_F32_bits"),StaticCollisionPoint(Point));Vertices.Add(MakeShared<FJsonValueObject>(Row));
    }
    for(const FTriangleID ID:Description.Triangles().GetElementIDs())
    {
        const auto V=Description.GetTriangleVertices(ID);if(V.Num()!=3||!Description.IsVertexValid(V[0])||!Description.IsVertexValid(V[1])||!Description.IsVertexValid(V[2])||V[0]==V[1]||V[1]==V[2]||V[0]==V[2]){Failure=TEXT("invalid_cached_MD_triangle");return false;}auto Row=MakeShared<FJsonObject>();Row->SetNumberField(TEXT("id"),ID.GetValue());Row->SetField(TEXT("vertex_ids"),StaticCollisionTriangle(V[0].GetValue(),V[1].GetValue(),V[2].GetValue()));Triangles.Add(MakeShared<FJsonValueObject>(Row));
    }
    Output->SetStringField(TEXT("state"),TEXT("RESIDENT_ID_AWARE_EXACT_ARRAYS"));Output->SetNumberField(TEXT("vertices"),Vertices.Num());Output->SetNumberField(TEXT("triangles"),Triangles.Num());Output->SetArrayField(TEXT("vertex_rows"),Vertices);Output->SetArrayField(TEXT("triangle_rows"),Triangles);return true;
}

bool StaticCollisionProviderValid(const FTriMeshCollisionData& Data,FString& Failure)
{
    if(!StaticCollisionCount(Data.Vertices.Num(),StaticCollisionMaximumVertices)||!StaticCollisionCount(Data.Indices.Num(),StaticCollisionMaximumTriangles)||!StaticCollisionCount(Data.MaterialIndices.Num(),StaticCollisionMaximumTriangles)||!StaticCollisionCount(Data.UVs.Num(),StaticCollisionMaximumUVChannels)){Failure=TEXT("provider_array_caps");return false;}
    if(Data.MaterialIndices.Num()!=0&&Data.MaterialIndices.Num()!=Data.Indices.Num()){Failure=TEXT("provider_material_count");return false;}
    for(const FVector3f& Point:Data.Vertices)if(!StaticCollisionFinite(Point)){Failure=TEXT("nonfinite_provider_position");return false;}
    for(const FTriIndices& T:Data.Indices)if(!StaticCollisionIndices(T.v0,T.v1,T.v2,Data.Vertices.Num())){Failure=TEXT("invalid_provider_triangle");return false;}
    for(const auto& Channel:Data.UVs){if(!StaticCollisionCount(Channel.Num(),StaticCollisionMaximumVertices)){Failure=TEXT("provider_UV_count");return false;}for(const auto& UV:Channel)if(!FMath::IsFinite(UV.X)||!FMath::IsFinite(UV.Y)){Failure=TEXT("nonfinite_provider_UV");return false;}}
    return true;
}
bool StaticCollisionRenderPreflight(const UStaticMesh* Mesh,TSharedRef<FJsonObject> Output,FString& Failure)
{
    const FStaticMeshRenderData* Data=Mesh->GetRenderData();
    if(!Data||Data->LODResources.Num()==0){Failure=TEXT("PENDING_RENDER_DATA");return false;}
    if(!StaticCollisionCount(Data->LODResources.Num(),StaticCollisionMaximumLODs)){Failure=TEXT("render_LOD_cap");return false;}
    const FStaticMeshLODResources& LOD=Data->LODResources[0];const uint32 Vertices=LOD.VertexBuffers.PositionVertexBuffer.GetNumVertices();const int32 Indices=LOD.IndexBuffer.GetNumIndices();
    if(!StaticCollisionCount(Vertices,StaticCollisionMaximumVertices)||!StaticCollisionCount(Indices,StaticCollisionMaximumIndices)||Indices%3!=0||!StaticCollisionCount(LOD.Sections.Num(),StaticCollisionMaximumSections)||!StaticCollisionCount(LOD.VertexBuffers.StaticMeshVertexBuffer.GetNumTexCoords(),StaticCollisionMaximumUVChannels)){Failure=TEXT("render_provider_preallocation_caps");return false;}
    if(Vertices==0||Indices==0){Failure=TEXT("PENDING_RENDER_DATA");return false;}
    if(!LOD.IndexBuffer.GetAllowCPUAccess()){Failure=TEXT("UNAVAILABLE_CPU_INDEX_DATA_NO_REPAIR");return false;}
    int64 SectionTriangles=0;
    for(const FStaticMeshSection& Section:LOD.Sections){SectionTriangles+=Section.NumTriangles;const uint64 End=uint64(Section.FirstIndex)+uint64(Section.NumTriangles)*3;if(!StaticCollisionCount(SectionTriangles,StaticCollisionMaximumTriangles)||End>uint64(Indices)){Failure=TEXT("invalid_or_unbounded_render_sections");return false;}}
    const FIndexArrayView View=LOD.IndexBuffer.GetArrayView();if(View.Num()!=Indices){Failure=TEXT("render_CPU_index_count_mismatch");return false;}
    for(int32 I=0;I<Indices;++I)if(View[I]>=Vertices){Failure=TEXT("invalid_render_vertex_index_before_provider");return false;}
    for(uint32 I=0;I<Vertices;++I)if(!StaticCollisionFinite(LOD.VertexBuffers.PositionVertexBuffer.VertexPosition(I))){Failure=TEXT("nonfinite_render_position_before_provider");return false;}
    if(Data->CollisionDataForCookedCooker&&!StaticCollisionProviderValid(*Data->CollisionDataForCookedCooker,Failure))return false;
    if(!Mesh->HasValidRenderData(true,0)){Failure=TEXT("PENDING_RENDER_DATA");return false;}
    Output->SetNumberField(TEXT("LOD0_vertices"),Vertices);Output->SetNumberField(TEXT("LOD0_indices"),Indices);Output->SetNumberField(TEXT("all_section_triangles"),double(SectionTriangles));Output->SetNumberField(TEXT("sections"),LOD.Sections.Num());Output->SetBoolField(TEXT("CPU_index_access"),true);Output->SetBoolField(TEXT("provider_allocation_prebounded"),true);return true;
}
bool StaticCollisionBodyMetadata(const UBodySetup* Body,TSharedRef<FJsonObject> Output,FString& Failure)
{
    if(!Body){Output->SetBoolField(TEXT("present"),false);return true;}
    Output->SetBoolField(TEXT("present"),true);Output->SetStringField(TEXT("path"),Body->GetPathName());Output->SetStringField(TEXT("outer"),Body->GetOuter()?Body->GetOuter()->GetPathName():TEXT(""));Output->SetStringField(TEXT("GUID"),Body->BodySetupGuid.ToString(EGuidFormats::Digits));Output->SetNumberField(TEXT("collision_mode"),int32(Body->CollisionTraceFlag));Output->SetStringField(TEXT("collision_mode_name"),StaticCollisionMode(Body->CollisionTraceFlag));Output->SetBoolField(TEXT("double_sided_geometry"),Body->bDoubleSidedGeometry);Output->SetBoolField(TEXT("created_physics_meshes"),Body->bCreatedPhysicsMeshes);Output->SetBoolField(TEXT("failed_to_create_physics_meshes"),Body->bFailedToCreatePhysicsMeshes);Output->SetBoolField(TEXT("has_cooked_data_Editor_diagnostic_only"),Body->bHasCookedCollisionData);
    const FBodyInstance& Default=Body->DefaultInstance;Output->SetStringField(TEXT("default_profile"),Default.GetCollisionProfileName().ToString());Output->SetNumberField(TEXT("default_object_type"),int32(Default.GetObjectType()));Output->SetNumberField(TEXT("default_collision_enabled"),int32(Default.GetCollisionEnabled()));Output->SetBoolField(TEXT("default_simulate_physics"),Default.bSimulatePhysics);Output->SetNumberField(TEXT("default_Pawn_response"),int32(Default.GetResponseToChannel(ECC_Pawn)));Output->SetNumberField(TEXT("default_Camera_response"),int32(Default.GetResponseToChannel(ECC_Camera)));Output->SetBoolField(TEXT("asset_defaults_are_not_live_component_floor_policy"),true);
    const FKAggregateGeom& Simple=Body->AggGeom;auto Counts=MakeShared<FJsonObject>();int64 Total=0;
    const auto Add=[&](const TCHAR* Name,int32 Count){Counts->SetNumberField(Name,Count);Total+=Count;return StaticCollisionCount(Count,StaticCollisionMaximumSimpleElements);};
    if(!Add(TEXT("sphere"),Simple.SphereElems.Num())||!Add(TEXT("box"),Simple.BoxElems.Num())||!Add(TEXT("capsule"),Simple.SphylElems.Num())||!Add(TEXT("convex"),Simple.ConvexElems.Num())||!Add(TEXT("tapered_capsule"),Simple.TaperedCapsuleElems.Num())||!Add(TEXT("level_set"),Simple.LevelSetElems.Num())||!Add(TEXT("skinned_level_set"),Simple.SkinnedLevelSetElems.Num())||!Add(TEXT("ML_level_set"),Simple.MLLevelSetElems.Num())||!Add(TEXT("skinned_triangle_mesh"),Simple.SkinnedTriangleMeshElems.Num())||!StaticCollisionCount(Total,StaticCollisionMaximumSimpleElements)){Failure=TEXT("simple_element_cap");return false;}
    Output->SetObjectField(TEXT("simple_element_counts"),Counts);Output->SetNumberField(TEXT("simple_elements"),double(Total));Output->SetNumberField(TEXT("cooked_triangle_shape_count"),Body->TriMeshGeometries.Num());return true;
}
bool StaticCollisionCookedPreflight(const UBodySetup* Body,FString& Failure)
{
    if(!StaticCollisionCount(Body->TriMeshGeometries.Num(),StaticCollisionMaximumShapes)){Failure=TEXT("cooked_shape_cap");return false;}int64 Vertices=0,Triangles=0;
    for(const auto& Shape:Body->TriMeshGeometries)
    {
        if(Shape.GetReference()==nullptr){Failure=TEXT("null_cooked_shape");return false;}const auto& Particles=Shape->Particles();const auto& Elements=Shape->Elements();Vertices+=Particles.Size();Triangles+=Elements.GetNumTriangles();if(!StaticCollisionCount(Vertices,StaticCollisionMaximumVertices)||!StaticCollisionCount(Triangles,StaticCollisionMaximumTriangles)){Failure=TEXT("aggregate_cooked_buffer_cap");return false;}
        for(int32 I=0;I<int32(Particles.Size());++I){const auto& P=Particles.GetX(I);if(!StaticCollisionFinite(FVector3f(P[0],P[1],P[2]))){Failure=TEXT("nonfinite_cooked_particle_before_JSON_allocation");return false;}}
        for(int32 I=0;I<Elements.GetNumTriangles();++I){int32 A=0,B=0,C=0;if(Elements.RequiresLargeIndices()){const auto& T=Elements.GetLargeIndexBuffer()[I];A=T[0];B=T[1];C=T[2];}else{const auto& T=Elements.GetSmallIndexBuffer()[I];A=T[0];B=T[1];C=T[2];}if(!StaticCollisionIndices(A,B,C,int32(Particles.Size()))){Failure=TEXT("invalid_cooked_triangle_before_JSON_allocation");return false;}const int32 External=Shape->GetExternalFaceIndexFromInternal(I);if(External<INDEX_NONE||External>=StaticCollisionMaximumTriangles){Failure=TEXT("unbounded_cooked_external_face_index");return false;}}
    }
    return true;
}
bool StaticCollisionCooked(const UBodySetup* Body,TSharedRef<FJsonObject> Output,FString& Failure)
{
    TArray<TSharedPtr<FJsonValue>> Shapes;int32 TotalVertices=0,TotalTriangles=0;
    for(int32 ShapeIndex=0;ShapeIndex<Body->TriMeshGeometries.Num();++ShapeIndex)
    {
        const auto& Shape=Body->TriMeshGeometries[ShapeIndex];const auto& Particles=Shape->Particles();const auto& Elements=Shape->Elements();const int32 Vertices=int32(Particles.Size());const int32 Triangles=Elements.GetNumTriangles();TArray<TSharedPtr<FJsonValue>> Points,Indices,Faces;
        for(int32 I=0;I<Vertices;++I){const auto& P=Particles.GetX(I);static_assert(sizeof(P[0])==sizeof(float),"Qualified Chaos triangle particles must retain nativeF32 storage");const FVector3f Point(P[0],P[1],P[2]);if(!StaticCollisionFinite(Point)){Failure=TEXT("nonfinite_cooked_particle");return false;}Points.Add(StaticCollisionPoint(Point));}
        for(int32 I=0;I<Triangles;++I)
        {
            int32 A=0,B=0,C=0;if(Elements.RequiresLargeIndices()){const auto& T=Elements.GetLargeIndexBuffer()[I];A=T[0];B=T[1];C=T[2];}else{const auto& T=Elements.GetSmallIndexBuffer()[I];A=T[0];B=T[1];C=T[2];}
            if(!StaticCollisionIndices(A,B,C,Vertices)){Failure=TEXT("invalid_cooked_triangle");return false;}Indices.Add(StaticCollisionTriangle(A,B,C));const int32 External=Shape->GetExternalFaceIndexFromInternal(I);if(External<INDEX_NONE||External>=StaticCollisionMaximumTriangles){Failure=TEXT("unbounded_cooked_external_face_index");return false;}Faces.Add(MakeShared<FJsonValueNumber>(External));
        }
        auto Row=MakeShared<FJsonObject>();Row->SetNumberField(TEXT("shape_index"),ShapeIndex);Row->SetNumberField(TEXT("vertices"),Vertices);Row->SetNumberField(TEXT("triangles"),Triangles);Row->SetBoolField(TEXT("large_indices"),Elements.RequiresLargeIndices());Row->SetArrayField(TEXT("positions_F32_bits"),Points);Row->SetArrayField(TEXT("indices"),Indices);Row->SetArrayField(TEXT("external_face_indices"),Faces);Shapes.Add(MakeShared<FJsonValueObject>(Row));TotalVertices+=Vertices;TotalTriangles+=Triangles;
    }
    Output->SetStringField(TEXT("state"),Shapes.Num()?TEXT("ACTUAL_CREATED_CHAOS_ARRAYS"):TEXT("COMPLETED_EMPTY_COOKED_TRIANGLE_SET"));Output->SetNumberField(TEXT("total_vertices"),TotalVertices);Output->SetNumberField(TEXT("total_triangles"),TotalTriangles);Output->SetArrayField(TEXT("shapes"),Shapes);return true;
}
}

FString ULivingTownStaticMeshCollisionInspection::ReadStaticMeshCollision(UStaticMesh* Mesh)
{
    using namespace LivingTownStaticMeshCollisionInspectionInternal;
    FStaticCollisionSnapshot Snapshot;
    if(!IsInGameThread())return Snapshot.Finish(TEXT("ERROR"),TEXT("game_thread_required"));
    if(!IsValid(Mesh)||Mesh->IsTemplate()||Mesh->GetClass()!=UStaticMesh::StaticClass()||Mesh->HasAnyFlags(RF_NeedLoad|RF_NeedPostLoad|RF_NeedPostLoadSubobjects))return Snapshot.Finish(TEXT("ERROR"),TEXT("already_loaded_exact_native_non_template_StaticMesh_required"));
    Snapshot.Mesh=Mesh;Snapshot.MeshPackage=Mesh->GetOutermost();Snapshot.MeshDirty=Snapshot.MeshPackage->IsDirty();Snapshot.Object->SetStringField(TEXT("asset"),Mesh->GetPathName());Snapshot.Object->SetStringField(TEXT("class"),Mesh->GetClass()->GetPathName());Snapshot.Object->SetStringField(TEXT("package"),Snapshot.MeshPackage->GetPathName());
    if(Mesh->IsCompiling())return Snapshot.Finish(TEXT("PENDING_STATIC_MESH_COLLISION_DATA"),TEXT("native_static_mesh_compilation"));
    Snapshot.Object->SetBoolField(TEXT("IsCompiling"),false);Snapshot.Object->SetBoolField(TEXT("allow_CPU_access"),Mesh->bAllowCPUAccess);Snapshot.Object->SetBoolField(TEXT("Nanite_enabled"),Mesh->GetNaniteSettings().bEnabled);Snapshot.Object->SetBoolField(TEXT("support_ray_tracing"),Mesh->bSupportRayTracing);
    Snapshot.Object->SetStringField(TEXT("external_complex_collision_mesh"),Mesh->ComplexCollisionMesh?Mesh->ComplexCollisionMesh->GetPathName():TEXT(""));
    if(Mesh->ComplexCollisionMesh&&Mesh->ComplexCollisionMesh!=Mesh)return Snapshot.Finish(TEXT("ERROR"),TEXT("external_complex_collision_override_outside_first_scope_no_load"));
    FString Failure;auto MD=MakeShared<FJsonObject>();Snapshot.Object->SetObjectField(TEXT("mesh_description"),MD);
    if(!StaticCollisionCachedMD(Mesh,MD,Failure))return Snapshot.Finish(TEXT("ERROR"),*Failure);
    Snapshot.Body=Mesh->GetBodySetup();Snapshot.BodyObserved=true;
    if(Snapshot.Body){Snapshot.BodyPackage=Snapshot.Body->GetOutermost();Snapshot.BodyDirty=Snapshot.BodyPackage->IsDirty();}
    auto Body=MakeShared<FJsonObject>();Snapshot.Object->SetObjectField(TEXT("body"),Body);
    if(!StaticCollisionBodyMetadata(Snapshot.Body,Body,Failure))return Snapshot.Finish(TEXT("ERROR"),*Failure);
    if(!Snapshot.Body)return Snapshot.Finish(TEXT("PENDING_STATIC_MESH_COLLISION_DATA"),TEXT("body_setup_not_present_no_creation"));
    Body->SetBoolField(TEXT("outer_is_input_mesh"),Snapshot.Body->GetOuter()==Mesh);
    if(Snapshot.Body->GetOuter()!=Mesh)return Snapshot.Finish(TEXT("ERROR"),TEXT("body_outer_is_not_input_mesh"));
    if(Snapshot.Body->bFailedToCreatePhysicsMeshes)return Snapshot.Finish(TEXT("ERROR"),TEXT("native_physics_creation_failed"));
    if(!Snapshot.Body->bCreatedPhysicsMeshes)return Snapshot.Finish(TEXT("PENDING_STATIC_MESH_COLLISION_DATA"),TEXT("native_physics_meshes_not_created_no_cook"));
    if(!StaticCollisionCookedPreflight(Snapshot.Body,Failure))return Snapshot.Finish(TEXT("ERROR"),*Failure);
    auto Render=MakeShared<FJsonObject>();Snapshot.Object->SetObjectField(TEXT("render_preflight"),Render);
    if(!StaticCollisionRenderPreflight(Mesh,Render,Failure))return Snapshot.Finish(Failure==TEXT("PENDING_RENDER_DATA")?TEXT("PENDING_STATIC_MESH_COLLISION_DATA"):TEXT("ERROR"),*Failure);
    FTriMeshCollisionData Data;
    if(!Mesh->GetPhysicsTriMeshData(&Data,true))return Snapshot.Finish(TEXT("ERROR"),TEXT("actual_provider_data_unavailable_no_repair"));
    if(!StaticCollisionProviderValid(Data,Failure))return Snapshot.Finish(TEXT("ERROR"),*Failure);
    TArray<TSharedPtr<FJsonValue>> Points,Indices,Materials;
    for(const FVector3f& Point:Data.Vertices)Points.Add(StaticCollisionPoint(Point));
    for(const FTriIndices& T:Data.Indices)Indices.Add(StaticCollisionTriangle(T.v0,T.v1,T.v2));
    for(const auto Material:Data.MaterialIndices)Materials.Add(MakeShared<FJsonValueNumber>(Material));
    auto Provider=MakeShared<FJsonObject>();Provider->SetStringField(TEXT("asset"),Mesh->GetPathName());Provider->SetBoolField(TEXT("all_tri_data_requested"),true);Provider->SetBoolField(TEXT("bFlipNormals"),Data.bFlipNormals);Provider->SetNumberField(TEXT("vertices"),Data.Vertices.Num());Provider->SetNumberField(TEXT("triangles"),Data.Indices.Num());Provider->SetArrayField(TEXT("positions_F32_bits"),Points);Provider->SetArrayField(TEXT("indices"),Indices);Provider->SetArrayField(TEXT("material_indices"),Materials);Provider->SetNumberField(TEXT("UV_channels_not_returned"),Data.UVs.Num());Snapshot.Object->SetObjectField(TEXT("provider"),Provider);
    auto Cooked=MakeShared<FJsonObject>();Snapshot.Object->SetObjectField(TEXT("cooked"),Cooked);
    if(!StaticCollisionCooked(Snapshot.Body,Cooked,Failure))return Snapshot.Finish(TEXT("ERROR"),*Failure);
    return Snapshot.Finish(TEXT("READ_ONLY_BOUNDED_STATIC_MESH_COLLISION_SNAPSHOT"),TEXT("bounded_actual_collision_arrays_caller_must_bind_source"));
}

namespace LivingTownAuthorCollisionResponsesInternal
{
constexpr int32 MaximumComponents=64;
// CollisionProfile.cpp uses the same64 serialized channels. ECC_MAX is65:
// deprecated64 is NOT a response-container element.
constexpr int32 MaxNumCollisionChannels=64;
constexpr int32 MaximumJsonBytes=2*1024*1024;
bool ContextFlags(bool GameThread,bool Editor,bool Commandlet,bool HasEditor,bool PlayWorld,bool HasEngine)
{ return GameThread && Editor && !Commandlet && HasEditor && !PlayWorld && HasEngine; }
bool InputCount(int32 Count) { return Count>=1 && Count<=MaximumComponents; }
bool ResponseDomain(int32 Value) { return Value>=int32(ECR_Ignore) && Value<=int32(ECR_Block); }
bool AllowedWorld(const FString& Package)
{
    // Exact literals from the two owned author plans. No prefix, PIE stripping,
    // map opening or context creation can broaden this read-only scope.
    return Package==TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_Material176_v001/MillCourtB_Material176Inspection_v001") ||
        Package==TEXT("/Game/LivingTown_UEPilot/FullTownIntegrationB749_v001/Units/L_B749_v001") ||
        Package==TEXT("/Game/LivingTown_UEPilot/FullTownWorld_v001/Units/L_U0151") ||
        Package==TEXT("/Game/LivingTown_UEPilot/FullTownIntegrationB749_v001/Units/L_Ground156_v001");
}
bool ResponseRows(const UStaticMeshComponent& Component,TArray<TSharedPtr<FJsonValue>>& Rows,FString& Error)
{
    const UEnum* Channels=StaticEnum<ECollisionChannel>();
    const UEnum* Responses=StaticEnum<ECollisionResponse>();
    const auto& Container=Component.GetCollisionResponseToChannels();
    if (int32(UE_ARRAY_COUNT(Container.EnumArray))!=MaxNumCollisionChannels ||
        int32(ECC_OverlapAll_Deprecated)!=64 || int32(ECC_MAX)!=65 || !Channels || !Responses)
    { Error=TEXT("unsupported_native_channel_container_or_enum_domain"); return false; }
    Rows.Reserve(MaxNumCollisionChannels);
    for (int32 Channel=0; Channel<MaxNumCollisionChannels; ++Channel)
    {
        const FString ChannelName=Channels->GetNameStringByValue(Channel);
        const int32 Response=int32(Component.GetCollisionResponseToChannel(static_cast<ECollisionChannel>(Channel)));
        const FString ResponseName=Responses->GetNameStringByValue(Response);
        if (ChannelName.IsEmpty() || !ResponseDomain(Response) || ResponseName.IsEmpty())
        { Error=TEXT("invalid_native_channel_name_or_response"); return false; }
        auto Row=MakeShared<FJsonObject>();
        Row->SetNumberField(TEXT("channel"),Channel); Row->SetStringField(TEXT("channel_cpp_name"),ChannelName);
        Row->SetNumberField(TEXT("response"),Response); Row->SetStringField(TEXT("response_cpp_name"),ResponseName);
        Rows.Add(MakeShared<FJsonValueObject>(Row));
    }
    return true;
}
struct FPackageRead
{
    UPackage* Package=nullptr; FString Path; bool Dirty=false;
};
struct FComponentRead
{
    UStaticMeshComponent* Component=nullptr; AActor* Actor=nullptr; UWorld* World=nullptr;
    FString ComponentPath,ActorPath,WorldPath;
};
struct FRead
{
    TSharedRef<FJsonObject> Object=MakeShared<FJsonObject>();
    TSharedRef<FJsonObject> Readback=MakeShared<FJsonObject>();
    TArray<FPackageRead> Packages;
    TArray<FComponentRead> Inputs;
    TArray<TSharedPtr<FJsonValue>> Rows;
    FRead()
    {
        Object->SetStringField(TEXT("schema"),TEXT("LivingTown.AuthorComponentCollisionResponses.v1"));
        Object->SetBoolField(TEXT("operation_writes_or_repairs"),false);
        Object->SetBoolField(TEXT("caller_source_binding_required"),true);
        Object->SetBoolField(TEXT("saved_Cold_contact_Game_art_or_FPS_qualified"),false);
        Object->SetObjectField(TEXT("readback"),Readback);
        Readback->SetNumberField(TEXT("serialized_channel_count"),MaxNumCollisionChannels);
        Readback->SetNumberField(TEXT("deprecated_channel_sentinel"),int32(ECC_OverlapAll_Deprecated));
        Readback->SetNumberField(TEXT("ECC_MAX_enum_sentinel_not_container_length"),int32(ECC_MAX));
        Readback->SetNumberField(TEXT("maximum_components"),MaximumComponents);
        Readback->SetNumberField(TEXT("maximum_JSON_bytes"),MaximumJsonBytes);
    }
    bool ObservePackage(UPackage* Package)
    {
        if (!Package || Package->HasAnyPackageFlags(PKG_PlayInEditor) || Package->GetPathName().Len()>4096) return false;
        if (!Packages.ContainsByPredicate([&](const auto& P){return P.Package==Package;}))
            Packages.Add({Package,Package->GetPathName(),Package->IsDirty()});
        return true;
    }
    FString Finish(FString Error)
    {
        TArray<TSharedPtr<FJsonValue>> PackageRows;
        for (const auto& P:Packages)
        {
            const bool After=P.Package->IsDirty();
            auto Row=MakeShared<FJsonObject>(); Row->SetStringField(TEXT("package_path"),P.Path);
            Row->SetBoolField(TEXT("dirty_before"),P.Dirty); Row->SetBoolField(TEXT("dirty_after"),After);
            PackageRows.Add(MakeShared<FJsonValueObject>(Row));
            if (After!=P.Dirty || P.Package->GetPathName()!=P.Path) Error=TEXT("read_changed_package_identity_or_dirty_state");
        }
        for (const auto& I:Inputs)
            if (!IsValid(I.Component) || !IsValid(I.Actor) || !IsValid(I.World) ||
                I.Component->GetOwner()!=I.Actor || I.Component->GetWorld()!=I.World || I.Actor->GetWorld()!=I.World ||
                I.Component->GetPathName()!=I.ComponentPath || I.Actor->GetPathName()!=I.ActorPath || I.World->GetPathName()!=I.WorldPath)
                Error=TEXT("read_changed_component_owner_or_world_identity");
        Readback->SetArrayField(TEXT("components"),Rows); Readback->SetArrayField(TEXT("packages"),PackageRows);
        Readback->SetNumberField(TEXT("returned_components"),Rows.Num());
        Object->SetBoolField(TEXT("readback_complete"),Error.IsEmpty());
        Object->SetStringField(TEXT("status"),Error.IsEmpty()?TEXT("READ_ONLY_AUTHOR_COMPONENT_COLLISION_RESPONSES"):TEXT("ERROR"));
        Object->SetStringField(TEXT("error"),Error);
        FString Text; FJsonSerializer::Serialize(Object,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Text));
        FTCHARToUTF8 Encoded(*Text);
        if (Encoded.Length()>MaximumJsonBytes)
            return TEXT("{\"schema\":\"LivingTown.AuthorComponentCollisionResponses.v1\",\"status\":\"ERROR\",\"error\":\"bounded_JSON_size_exceeded\",\"operation_writes_or_repairs\":false,\"readback_complete\":false,\"readback\":{}}");
        return Text;
    }
};
}

FString ULivingTownStaticMeshCollisionInspection::ReadAuthorComponentCollisionResponses(const TArray<UStaticMeshComponent*>& Components)
{
    using namespace LivingTownAuthorCollisionResponsesInternal;
    FRead Snapshot;
    // No UObject/Editor context dereference is performed by a non-GT refusal.
    if (!IsInGameThread()) return Snapshot.Finish(TEXT("game_thread_required"));
    if (!ContextFlags(true,GIsEditor,IsRunningCommandlet(),GEditor!=nullptr,
        GEditor && GEditor->PlayWorld!=nullptr,GEngine!=nullptr))
        return Snapshot.Finish(TEXT("existing_non_commandlet_Editor_without_play_required"));
    for (const FWorldContext& Context:GEngine->GetWorldContexts())
        if (Context.WorldType==EWorldType::PIE || Context.WorldType==EWorldType::Game ||
            Context.WorldType==EWorldType::GamePreview || Context.WorldType==EWorldType::GameRPC)
            return Snapshot.Finish(TEXT("game_or_PIE_context_exists"));
    if (!InputCount(Components.Num())) return Snapshot.Finish(TEXT("unique_component_count_must_be_1_to_64"));
    TSet<const UStaticMeshComponent*> Seen;
    for (int32 Index=0; Index<Components.Num(); ++Index)
    {
        UStaticMeshComponent* C=Components[Index];
        if (!IsValid(C) || C->IsTemplate() || C->GetClass()!=UStaticMeshComponent::StaticClass() ||
            C->HasAnyFlags(RF_NeedLoad|RF_NeedPostLoad|RF_NeedPostLoadSubobjects))
            return Snapshot.Finish(TEXT("already_loaded_exact_non_template_StaticMeshComponent_required"));
        if (Seen.Contains(C)) return Snapshot.Finish(TEXT("duplicate_component_input")); Seen.Add(C);
        AActor* A=C->GetOwner(); UWorld* W=C->GetWorld();
        if (!IsValid(A) || A->IsTemplate() || A->HasAnyFlags(RF_NeedLoad|RF_NeedPostLoad|RF_NeedPostLoadSubobjects) ||
            !IsValid(W) || W->IsTemplate() || W->HasAnyFlags(RF_NeedLoad|RF_NeedPostLoad|RF_NeedPostLoadSubobjects) ||
            A->GetWorld()!=W || (W->WorldType!=EWorldType::Editor && W->WorldType!=EWorldType::Inactive) ||
            !AllowedWorld(W->GetOutermost()->GetName()))
            return Snapshot.Finish(TEXT("valid_owner_and_exact_allowed_Editor_or_Inactive_world_required"));
        const FString CP=C->GetPathName(),AP=A->GetPathName(),WP=W->GetPathName();
        if (CP.Len()>4096 || AP.Len()>4096 || WP.Len()>4096 ||
            !Snapshot.ObservePackage(C->GetOutermost()) || !Snapshot.ObservePackage(A->GetOutermost()) ||
            !Snapshot.ObservePackage(W->GetOutermost()))
            return Snapshot.Finish(TEXT("bounded_non_PIE_component_owner_world_packages_required"));
        Snapshot.Inputs.Add({C,A,W,CP,AP,WP});
        TArray<TSharedPtr<FJsonValue>> Responses; FString Error;
        if (!ResponseRows(*C,Responses,Error)) return Snapshot.Finish(Error);
        const int32 Enabled=int32(C->GetCollisionEnabled()),ObjectType=int32(C->GetCollisionObjectType());
        if (Enabled<int32(ECollisionEnabled::NoCollision) || Enabled>int32(ECollisionEnabled::QueryAndProbe) ||
            ObjectType<0 || ObjectType>=MaxNumCollisionChannels)
            return Snapshot.Finish(TEXT("invalid_collision_enabled_or_object_type_domain"));
        const FString ObjectName=StaticEnum<ECollisionChannel>()->GetNameStringByValue(ObjectType);
        if (ObjectName.IsEmpty()) return Snapshot.Finish(TEXT("invalid_collision_object_type_name"));
        auto Row=MakeShared<FJsonObject>(); Row->SetNumberField(TEXT("input_index"),Index);
        Row->SetStringField(TEXT("component_path"),CP); Row->SetStringField(TEXT("component_class"),C->GetClass()->GetPathName());
        Row->SetStringField(TEXT("owner_path"),AP); Row->SetStringField(TEXT("owner_class"),A->GetClass()->GetPathName());
        Row->SetStringField(TEXT("world_path"),WP); Row->SetStringField(TEXT("world_package"),W->GetOutermost()->GetName());
        Row->SetStringField(TEXT("world_type"),LexToString(W->WorldType));
        Row->SetStringField(TEXT("component_package"),C->GetOutermost()->GetName());
        Row->SetStringField(TEXT("owner_package"),A->GetOutermost()->GetName());
        Row->SetStringField(TEXT("collision_profile"),C->GetCollisionProfileName().ToString());
        Row->SetNumberField(TEXT("collision_enabled"),Enabled);
        Row->SetNumberField(TEXT("object_type"),ObjectType); Row->SetStringField(TEXT("object_type_cpp_name"),ObjectName);
        Row->SetBoolField(TEXT("actor_enable_collision"),A->GetActorEnableCollision());
        Row->SetArrayField(TEXT("responses"),Responses); Snapshot.Rows.Add(MakeShared<FJsonValueObject>(Row));
    }
    return Snapshot.Finish(TEXT(""));
}

#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "UObject/StrongObjectPtr.h"
#include "Async/Async.h"
#include <limits>
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownStaticMeshCollisionInspectionBoundary,"LivingTown.StaticMeshCollisionInspection.BoundedReadOnly",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownStaticMeshCollisionInspectionBoundary::RunTest(const FString& Parameters)
{
    (void)Parameters;using namespace LivingTownStaticMeshCollisionInspectionInternal;
    TestTrue(TEXT("Null input refuses"),ULivingTownStaticMeshCollisionInspection::ReadStaticMeshCollision(nullptr).Contains(TEXT("already_loaded_exact_native_non_template")));
    TestTrue(TEXT("CDO refuses"),ULivingTownStaticMeshCollisionInspection::ReadStaticMeshCollision(GetMutableDefault<UStaticMesh>()).Contains(TEXT("already_loaded_exact_native_non_template")));
    TStrongObjectPtr<UStaticMesh> Mesh(NewObject<UStaticMesh>(GetTransientPackage()));if(!TestNotNull(TEXT("Real transient test input"),Mesh.Get()))return false;
    Mesh->SetFlags(RF_ArchetypeObject);TestTrue(TEXT("Archetype refuses"),ULivingTownStaticMeshCollisionInspection::ReadStaticMeshCollision(Mesh.Get()).Contains(TEXT("already_loaded_exact_native_non_template")));Mesh->ClearFlags(RF_ArchetypeObject);
    const bool Dirty=Mesh->GetOutermost()->IsDirty();const UBodySetup* Body=Mesh->GetBodySetup();const FString First=ULivingTownStaticMeshCollisionInspection::ReadStaticMeshCollision(Mesh.Get());
    TestTrue(TEXT("Empty native transient returns honest pending"),First.Contains(TEXT("PENDING_STATIC_MESH_COLLISION_DATA")));
    TestTrue(TEXT("No source model is explicit"),First.Contains(TEXT("SOURCE_MODEL_NOT_INITIALIZED")));
    TestTrue(TEXT("No body is explicit, no body created"),First.Contains(TEXT("body_setup_not_present_no_creation")));
    TestTrue(TEXT("Body pointer unchanged"),Body==Mesh->GetBodySetup());TestEqual(TEXT("Package dirty unchanged"),Mesh->GetOutermost()->IsDirty(),Dirty);
    TestEqual(TEXT("Repeated empty read stable"),ULivingTownStaticMeshCollisionInspection::ReadStaticMeshCollision(Mesh.Get()),First);
    TestTrue(TEXT("No source or physics qualification"),First.Contains(TEXT("\"source_equality_saved_Cold_capsule_Map_Game_art_or_FPS_qualified\":false")));
    TestTrue(TEXT("Exact maximum count allowed"),StaticCollisionCount(50000,StaticCollisionMaximumVertices));
    TestFalse(TEXT("Vertex overflow refused"),StaticCollisionCount(50001,StaticCollisionMaximumVertices));
    TestFalse(TEXT("Triangle overflow refused"),StaticCollisionCount(20001,StaticCollisionMaximumTriangles));
    TestFalse(TEXT("Negative count refused"),StaticCollisionCount(-1,StaticCollisionMaximumTriangles));
    TestFalse(TEXT("Shape overflow refused"),StaticCollisionCount(9,StaticCollisionMaximumShapes));
    TestTrue(TEXT("Finite point accepted"),StaticCollisionFinite(FVector3f(1,2,3)));
    TestFalse(TEXT("NaN point refused"),StaticCollisionFinite(FVector3f(std::numeric_limits<float>::quiet_NaN(),0,0)));
    TestFalse(TEXT("Infinity point refused"),StaticCollisionFinite(FVector3f(0,std::numeric_limits<float>::infinity(),0)));
    TestTrue(TEXT("Valid oriented indices accepted"),StaticCollisionIndices(0,1,2,3));
    TestFalse(TEXT("Out of range index refused"),StaticCollisionIndices(0,1,3,3));
    TestFalse(TEXT("Repeated triangle index refused"),StaticCollisionIndices(0,1,1,3));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownAuthorCollisionResponsesBoundary,"LivingTown.AuthorComponentCollisionResponses.BoundedReadOnly",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownAuthorCollisionResponsesBoundary::RunTest(const FString&)
{
    using namespace LivingTownAuthorCollisionResponsesInternal;
    TestTrue(TEXT("exact Editor context predicate"),ContextFlags(true,true,false,true,false,true));
    TestFalse(TEXT("nonGT refuses"),ContextFlags(false,true,false,true,false,true));
    TestFalse(TEXT("game process refuses"),ContextFlags(true,false,false,true,false,true));
    TestFalse(TEXT("commandlet refuses"),ContextFlags(true,true,true,true,false,true));
    TestFalse(TEXT("PIE refuses"),ContextFlags(true,true,false,true,true,true));
    TestTrue(TEXT("one input allowed"),InputCount(1)); TestTrue(TEXT("64 inputs allowed"),InputCount(64));
    TestFalse(TEXT("zero refuses"),InputCount(0)); TestFalse(TEXT("65 refuses"),InputCount(65));
    TestTrue(TEXT("exact B source allowed"),AllowedWorld(TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_Material176_v001/MillCourtB_Material176Inspection_v001")));
    TestTrue(TEXT("exact B owned map allowed"),AllowedWorld(TEXT("/Game/LivingTown_UEPilot/FullTownIntegrationB749_v001/Units/L_B749_v001")));
    TestTrue(TEXT("exact ground source allowed"),AllowedWorld(TEXT("/Game/LivingTown_UEPilot/FullTownWorld_v001/Units/L_U0151")));
    TestTrue(TEXT("exact ground owned map allowed"),AllowedWorld(TEXT("/Game/LivingTown_UEPilot/FullTownIntegrationB749_v001/Units/L_Ground156_v001")));
    TestFalse(TEXT("prefix lookalike refuses"),AllowedWorld(TEXT("/Game/LivingTown_UEPilot/FullTownIntegrationB749_v001/Units/L_B749_v001_extra")));
    TestFalse(TEXT("unrelated Editor map refuses"),AllowedWorld(TEXT("/Engine/Maps/Entry")));
    TestTrue(TEXT("serialized64 boundary differs from ECC_MAX65"),int32(ECC_OverlapAll_Deprecated)==64 && int32(ECC_MAX)==65);
    for (int32 Value=0; Value<=2; ++Value) TestTrue(TEXT("all native response values accepted"),ResponseDomain(Value));
    TestFalse(TEXT("negative response refuses"),ResponseDomain(-1)); TestFalse(TEXT("sentinel response refuses"),ResponseDomain(int32(ECR_MAX)));
    TStrongObjectPtr<UStaticMeshComponent> C(NewObject<UStaticMeshComponent>(GetTransientPackage()));
    if (!TestNotNull(TEXT("transient nonregistered getter fixture"),C.Get())) return false;
    const bool Dirty=C->GetOutermost()->IsDirty();
    TArray<TSharedPtr<FJsonValue>> Rows; FString Error;
    TestTrue(TEXT("real native component emits all64 response reads"),ResponseRows(*C,Rows,Error));
    TestEqual(TEXT("exact64 ordered rows"),Rows.Num(),64);
    if (Rows.Num()==64)
    {
        for (int32 Channel=0; Channel<64; ++Channel)
        {
            const auto Row=Rows[Channel]->AsObject();
            TestEqual(TEXT("numeric channel order"),Row->GetIntegerField(TEXT("channel")),Channel);
            TestEqual(TEXT("CPP native enum name"),Row->GetStringField(TEXT("channel_cpp_name")),
                StaticEnum<ECollisionChannel>()->GetNameStringByValue(Channel));
            TestEqual(TEXT("actual native getter response"),Row->GetIntegerField(TEXT("response")),
                int32(C->GetCollisionResponseToChannel(static_cast<ECollisionChannel>(Channel))));
        }
        TestEqual(TEXT("hidden final serialized channel is present"),Rows[63]->AsObject()->GetStringField(TEXT("channel_cpp_name")),FString(TEXT("ECC_GameTraceChannel50")));
    }
    TestEqual(TEXT("response read leaves package dirty unchanged"),C->GetOutermost()->IsDirty(),Dirty);
    TestFalse(TEXT("response getter creates no physics state"),C->IsPhysicsStateCreated());
    // Public operation must refuse an ownerless transient component even though
    // the internal getter is testable without loading or constructing a map.
    TestTrue(TEXT("ownerless public request never qualifies"),
        ULivingTownStaticMeshCollisionInspection::ReadAuthorComponentCollisionResponses({C.Get()}).Contains(TEXT("\"status\":\"ERROR\"")));
    return true;
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownAuthorCollisionResponsesThread,"LivingTown.AuthorComponentCollisionResponses.NonGTRefusal",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownAuthorCollisionResponsesThread::RunTest(const FString&)
{
    const FString Result=Async(EAsyncExecution::Thread,[]()
    {
        return ULivingTownStaticMeshCollisionInspection::ReadAuthorComponentCollisionResponses({});
    }).Get();
    TestTrue(TEXT("offGT exits before UObject/Editor reads"),Result.Contains(TEXT("\"error\":\"game_thread_required\"")));
    return true;
}
#endif
