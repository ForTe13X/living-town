#include "LivingTownRemainderCollisionInspectionV2.h"
#include "LivingTownTileData.h"
#include "Engine/StaticMesh.h"
#include "Engine/StaticMeshSourceData.h"
#include "Engine/Texture2D.h"
#include "Engine/TextureLODSettings.h"
#include "MeshDescription.h"
#include "MeshDescriptionBase.h"
#include "StaticMeshAttributes.h"
#include "StaticMeshResources.h"
#include "PhysicsEngine/BodySetup.h"
#include "PhysicsEngine/BodyInstance.h"
#include "PhysicsEngine/AggregateGeom.h"
#include "Interfaces/Interface_CollisionDataProvider.h"
#include "Chaos/TriangleMeshImplicitObject.h"
#include "DeviceProfiles/DeviceProfile.h"
#include "DeviceProfiles/DeviceProfileManager.h"
#include "TextureResource.h"
#include "RenderingThread.h"
#include "RHI.h"
#include "RHIResources.h"
#include "DynamicRHI.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/ScopeTryLock.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformTime.h"
#include "HAL/PlatformMisc.h"
#include "UObject/StrongObjectPtr.h"
#include "UObject/Package.h"
#include <atomic>
#if WITH_DEV_AUTOMATION_TESTS
#include "Async/Async.h"
#endif
#include <type_traits>
#if PLATFORM_WINDOWS
#include "Windows/WindowsHWrapper.h"
#endif

namespace RemainderIntakeV2
{
constexpr uint32 MaxV=300000,MaxT=100000,MaxShapes=8,MaxSections=64,MaxUV=8,MaxSimple=256;
constexpr uint64 FileCap=32ull<<20,CallCap=256ull<<20,SessionCap=512ull<<20;
constexpr uint32 NoShape=0xffffffffu;
constexpr ANSICHAR Magic[]="LTREMAINDCHAO002";
static_assert(sizeof(Magic)==17,"16-byte protocol magic");
constexpr const TCHAR* Prefix=TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/TownRemainder_v001/");
struct FBound { const TCHAR* Path;uint32 W,T,Batch,LocalMesh;const TCHAR* Domain; };
const FBound MeshRoster[]={
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/TownRemainder_v001/B1_D06_D07/R1_static_000285.R1_static_000285"),171612u,57204u,1u,285u,TEXT("static_000285")},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/TownRemainder_v001/B3_D09_D10/R3_static_003362.R3_static_003362"),171612u,57204u,3u,911u,TEXT("static_003362")},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/TownRemainder_v001/B4_Reserve_Ownerless_Prototypes/R4_static_004877.R4_static_004877"),50640u,16880u,4u,829u,TEXT("static_004877")},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/TownRemainder_v001/B4_Reserve_Ownerless_Prototypes/R4_static_004895.R4_static_004895"),63936u,21312u,4u,847u,TEXT("static_004895")},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/TownRemainder_v001/B4_Reserve_Ownerless_Prototypes/R4_static_004920.R4_static_004920"),53460u,17820u,4u,871u,TEXT("static_004920")},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/TownRemainder_v001/B4_Reserve_Ownerless_Prototypes/R4_COMPLEMENT_static_005016.R4_COMPLEMENT_static_005016"),251856u,83952u,4u,967u,TEXT("static_005016")},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/TownRemainder_v001/B4_Reserve_Ownerless_Prototypes/R4_COMPLEMENT_static_005017.R4_COMPLEMENT_static_005017"),290664u,96888u,4u,968u,TEXT("static_005017")},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/TownRemainder_v001/B4_Reserve_Ownerless_Prototypes/R4_static_005029.R4_static_005029"),50976u,16992u,4u,980u,TEXT("static_005029")},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/TownRemainder_v001/B4_Reserve_Ownerless_Prototypes/R4_town_05_botanical_inland_mesh_6.R4_town_05_botanical_inland_mesh_6"),109500u,36500u,4u,1079u,TEXT("town_05_botanical_inland:mesh:6")},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/TownRemainder_v001/B4_Reserve_Ownerless_Prototypes/R4_town_05_botanical_inland_mesh_7.R4_town_05_botanical_inland_mesh_7"),109497u,36499u,4u,1080u,TEXT("town_05_botanical_inland:mesh:7")},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/TownRemainder_v001/B4_Reserve_Ownerless_Prototypes/R4_town_07_botanical_west_mesh_5.R4_town_07_botanical_west_mesh_5"),109500u,36500u,4u,1118u,TEXT("town_07_botanical_west:mesh:5")},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/TownRemainder_v001/B4_Reserve_Ownerless_Prototypes/R4_town_07_botanical_west_mesh_6.R4_town_07_botanical_west_mesh_6"),109497u,36499u,4u,1119u,TEXT("town_07_botanical_west:mesh:6")},
};
static_assert(UE_ARRAY_COUNT(MeshRoster)==12,"Exact declared twelve-asset full-remainder scope");
constexpr uint64 DeclaredAggregateCap=133751848;
enum class ECollisionSessionState : uint8 { Ready, Active, Terminal };
std::atomic<ECollisionSessionState> CollisionSessionState{ECollisionSessionState::Ready};
FString CollisionSessionRoot;uint64 CollisionSessionReserved=0;TSet<int32> CollisionSeen,MetadataSeen;
// Off-thread refusal may only touch this atomic and its caller-owned reply data.
void TerminateSession(){CollisionSessionState.store(ECollisionSessionState::Terminal,std::memory_order_seq_cst);}
bool SessionTerminal(){return CollisionSessionState.load(std::memory_order_seq_cst)==ECollisionSessionState::Terminal;}
FString Json(const TSharedRef<FJsonObject>& O)
{
    FString Text;FJsonSerializer::Serialize(O,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Text));
    if(Text.Len()>2*1024*1024){TerminateSession();return TEXT("{\"status\":\"ERROR\",\"reason\":\"json_bound\"}");}return Text;
}
FString Reply(const TCHAR* Status,const FString& Why)
{auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),Status);O->SetStringField(TEXT("reason"),Why);O->SetBoolField(TEXT("asset_repaired_or_saved"),false);return Json(O);}
bool Refuse(FString& Error,const FString& Why){TerminateSession();Error=Why;return false;}
bool BeginSession(FString& Error)
{
    ECollisionSessionState Expected=ECollisionSessionState::Ready;
    if(CollisionSessionState.compare_exchange_strong(Expected,ECollisionSessionState::Active,std::memory_order_seq_cst))return true;
    return Refuse(Error,Expected==ECollisionSessionState::Terminal?TEXT("terminal_session_refused_no_retry"):TEXT("active_session_reentry_refused"));
}
bool CompleteSession(FString& Error)
{
    ECollisionSessionState Expected=ECollisionSessionState::Active;
    if(CollisionSessionState.compare_exchange_strong(Expected,ECollisionSessionState::Ready,std::memory_order_seq_cst))return true;
    return Refuse(Error,TEXT("terminal_session_refused_no_retry"));
}
bool Count(int64 N,int64 Cap){return N>=0&&N<=Cap;}
template<typename V> bool FinitePoint(const V& P){return FMath::IsFinite(P[0])&&FMath::IsFinite(P[1])&&FMath::IsFinite(P[2]);}
bool Triangle(int64 A,int64 B,int64 C,int64 V){return A>=0&&B>=0&&C>=0&&A<V&&B<V&&C<V&&A!=B&&B!=C&&A!=C;}
int32 RosterIndex(const FString& Path)
{if(!Path.StartsWith(Prefix,ESearchCase::CaseSensitive))return INDEX_NONE;for(int32 I=0;I<UE_ARRAY_COUNT(MeshRoster);++I)if(Path.Equals(MeshRoster[I].Path,ESearchCase::CaseSensitive))return I;return INDEX_NONE;}
bool NoReparse(const FString& Absolute)
{
#if PLATFORM_WINDOWS
    FString N=Absolute.Replace(TEXT("/"),TEXT("\\"));if(N.Len()<3||N[1]!=':'||N[2]!='\\')return false;
    FString P=N.Left(3);TArray<FString> Parts;N.Mid(3).ParseIntoArray(Parts,TEXT("\\"),true);
    auto Check=[](const FString& X){const DWORD A=GetFileAttributesW(*X);return A!=INVALID_FILE_ATTRIBUTES&&!(A&FILE_ATTRIBUTE_REPARSE_POINT);};
    if(!Check(P))return false;for(const FString& X:Parts){if(X==TEXT(".")||X==TEXT(".."))return false;P=FPaths::Combine(P,X);if(!Check(P))return false;}return true;
#else
    return false;
#endif
}
bool Leaf(const FString& Name)
{if(Name.IsEmpty()||Name.Len()>64)return false;for(TCHAR C:Name)if(!((C>='a'&&C<='z')||(C>='A'&&C<='Z')||(C>='0'&&C<='9')||C=='_'))return false;return true;}
bool NewJson(const FString& P,const TSharedRef<FJsonObject>& O)
{return FFileHelper::SaveStringToFile(Json(O)+TEXT("\n"),*P,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM,&IFileManager::Get(),FILEWRITE_NoReplaceExisting);}
bool Digest(const FString& P,uint64 Cap,FString& Hash,int64& Bytes)
{Bytes=IFileManager::Get().FileSize(*P);if(Bytes<0||uint64(Bytes)>Cap||!NoReparse(P))return false;TArray<uint8> B;if(!FFileHelper::LoadFileToArray(B,*P)||B.Num()!=Bytes)return false;return LivingTownTiles::HashBytes(B,Hash)&&IFileManager::Get().FileSize(*P)==Bytes;}

class FWriter
{
    TUniquePtr<FArchive> File;TArray<uint8> Buffer;uint64 Written=0;bool Good=false;
    void Flush(){if(File&&Buffer.Num()){File->Serialize(Buffer.GetData(),Buffer.Num());Good&=!File->IsError();Buffer.Reset();}}
public:
    explicit FWriter(const FString& Path){File.Reset(IFileManager::Get().CreateFileWriter(*Path,FILEWRITE_NoReplaceExisting));Buffer.Reserve(65536);Good=File.IsValid();}
    void U8(uint8 X){if(!Good||Written>=FileCap){Good=false;return;}Buffer.Add(X);++Written;if(Buffer.Num()>=65536)Flush();}
    void U32(uint32 X){for(int32 I=0;I<4;++I)U8(uint8(X>>(8*I)));}
    void I32(int32 X){U32(uint32(X));}
    void U64(uint64 X){for(int32 I=0;I<8;++I)U8(uint8(X>>(8*I)));}
    template<typename Scalar> void Number(Scalar X)
    {static_assert(std::is_same_v<Scalar,float>||std::is_same_v<Scalar,double>);if(!FMath::IsFinite(X)){Good=false;return;}if constexpr(sizeof(Scalar)==4){uint32 B;FMemory::Memcpy(&B,&X,4);U32(B);}else{uint64 B;FMemory::Memcpy(&B,&X,8);U64(B);}}
    template<typename V> void Point(const V& P){using Scalar=std::remove_cv_t<std::remove_reference_t<decltype(P[0])>>;Number<Scalar>(P[0]);Number<Scalar>(P[1]);Number<Scalar>(P[2]);}
    uint64 Tell()const{return Written;}
    bool Finish(){Flush();if(!File)return false;const bool Closed=File->Close();Good&=Closed&&!File->IsError();File.Reset();return Good;}
};
struct FEntry
{
    uint32 Kind=0,Shape=NoShape,Stride=0,N=0,PositionBytes=0,IndexBytes=0,Flags=0;
    uint64 Offset=0,Bytes=0;TFunction<void(FWriter&)> Emit;
};
struct FSnapshot
{
    TStrongObjectPtr<UStaticMesh> Mesh;const UBodySetup* Body=nullptr;const FStaticMeshLODResources* Render=nullptr;
    const FMeshDescription* MD=nullptr;TUniquePtr<FScopeTryLock> MDLock;FTriMeshCollisionData Provider;
    TArray<FEntry> Entries;TSharedRef<FJsonObject> Meta=MakeShared<FJsonObject>();
    const FBound* Limit=nullptr;int32 Roster=INDEX_NONE;bool Dirty=false;FGuid Guid;FString PackageFile,PackageHash;int64 PackageBytes=0;uint64 Expected=0;
};

bool Preflight(FSnapshot& S,FString& Error)
{
    if(!S.Limit||S.Limit->W>MaxV||S.Limit->T>MaxT)return Refuse(Error,TEXT("invalid_frozen_per_asset_bounds"));
    UStaticMesh* M=S.Mesh.Get();
    if(M->IsCompiling())return Refuse(Error,TEXT("HOLD_mesh_compiling_no_wait"));
    if(M->GetNumSourceModels()!=1)return Refuse(Error,TEXT("source_LOD0_only"));
    if(!M->bAllowCPUAccess||M->GetNaniteSettings().bEnabled||(M->ComplexCollisionMesh&&M->ComplexCollisionMesh!=M))return Refuse(Error,TEXT("remainder_CPU_nonNanite_no_external_collision_required"));
    const FStaticMeshRenderData* RD=M->GetRenderData();if(!RD||RD->LODResources.Num()!=1)return Refuse(Error,TEXT("HOLD_render_LOD0_not_ready"));
    const auto& L=RD->LODResources[0];const uint32 V=L.VertexBuffers.PositionVertexBuffer.GetNumVertices(),NI=L.IndexBuffer.GetNumIndices();
    if(!V||!NI||NI%3||!Count(V,S.Limit->W)||!Count(NI/3,S.Limit->T)||!Count(L.Sections.Num(),MaxSections)||!Count(L.VertexBuffers.StaticMeshVertexBuffer.GetNumTexCoords(),MaxUV)||!L.IndexBuffer.GetAllowCPUAccess()||!L.VertexBuffers.PositionVertexBuffer.GetVertexData())return Refuse(Error,TEXT("render_preallocation_bounds_or_CPU_data"));
    S.Render=&L;uint64 ST=0;for(const auto& Section:L.Sections){ST+=Section.NumTriangles;if(ST>S.Limit->T||uint64(Section.FirstIndex)+uint64(Section.NumTriangles)*3>NI)return Refuse(Error,TEXT("render_sections_bound"));}
    if(ST!=NI/3)return Refuse(Error,TEXT("render_section_full_coverage"));
    const FIndexArrayView Ind=L.IndexBuffer.GetArrayView();if(Ind.Num()!=int32(NI))return Refuse(Error,TEXT("render_index_count"));
    for(uint32 I=0;I<V;++I)if(!FinitePoint(L.VertexBuffers.PositionVertexBuffer.VertexPosition(I)))return Refuse(Error,TEXT("render_nonfinite_P"));
    for(uint32 I=0;I<NI;I+=3)if(!Triangle(Ind[I],Ind[I+1],Ind[I+2],V))return Refuse(Error,TEXT("render_invalid_indices"));
    const FStaticMeshSourceModel& Source=M->GetSourceModel(0);S.MDLock=MakeUnique<FScopeTryLock>(&Source.StaticMeshDescriptionBulkDataCS);
    if(!S.MDLock->IsLocked())return Refuse(Error,TEXT("HOLD_source_MD_busy_no_wait"));
    const UStaticMeshDescriptionBulkData* Bulk=Source.StaticMeshDescriptionBulkData;
    if(!Bulk||!Bulk->HasCachedMeshDescription())return Refuse(Error,TEXT("HOLD_source_MD_not_resident_no_load"));
    const UMeshDescriptionBase* Wrapper=Bulk->GetMeshDescription();if(!Wrapper)return Refuse(Error,TEXT("source_MD_wrapper"));S.MD=&Wrapper->GetMeshDescription();const auto& D=*S.MD;
    if(!Count(D.Vertices().Num(),S.Limit->W)||!Count(D.Vertices().GetArraySize(),S.Limit->W)||!Count(D.Triangles().Num(),S.Limit->T)||!Count(D.Triangles().GetArraySize(),S.Limit->T)||!Count(D.VertexInstances().Num(),S.Limit->W)||!Count(D.VertexInstances().GetArraySize(),S.Limit->W)||!Count(D.PolygonGroups().GetArraySize(),MaxSections))return Refuse(Error,TEXT("source_MD_count_or_ID_extent"));
    const auto Pos=FStaticMeshConstAttributes(D).GetVertexPositions();for(FVertexID ID:D.Vertices().GetElementIDs())if(!FinitePoint(Pos[ID]))return Refuse(Error,TEXT("source_MD_nonfinite"));
    for(FTriangleID ID:D.Triangles().GetElementIDs()){const auto T=D.GetTriangleVertices(ID);if(T.Num()!=3||!D.IsVertexValid(T[0])||!D.IsVertexValid(T[1])||!D.IsVertexValid(T[2])||!D.IsPolygonGroupValid(D.GetTrianglePolygonGroup(ID))||!Triangle(T[0].GetValue(),T[1].GetValue(),T[2].GetValue(),D.Vertices().GetArraySize()))return Refuse(Error,TEXT("source_MD_invalid_triangle"));}
    S.Body=M->GetBodySetup();if(!S.Body||S.Body->GetOuter()!=M||!S.Body->bCreatedPhysicsMeshes)return Refuse(Error,TEXT("HOLD_created_BodySetup_not_ready_no_cook"));
    if(S.Body->bFailedToCreatePhysicsMeshes||!S.Body->BodySetupGuid.IsValid())return Refuse(Error,TEXT("body_failed_or_GUID_missing"));S.Guid=S.Body->BodySetupGuid;
    if(S.Body->TriMeshGeometries.IsEmpty())return Refuse(Error,TEXT("HOLD_actual_created_Chaos_arrays_missing_no_cook"));
    const auto& Simple=S.Body->AggGeom;const int64 NS=int64(Simple.SphereElems.Num())+Simple.BoxElems.Num()+Simple.SphylElems.Num()+Simple.ConvexElems.Num()+Simple.TaperedCapsuleElems.Num()+Simple.LevelSetElems.Num()+Simple.SkinnedLevelSetElems.Num()+Simple.MLLevelSetElems.Num()+Simple.SkinnedTriangleMeshElems.Num();if(!Count(NS,MaxSimple)||!Count(S.Body->TriMeshGeometries.Num(),MaxShapes))return Refuse(Error,TEXT("body_shape_bounds"));
    uint64 CV=0,CT=0;for(const auto& Shape:S.Body->TriMeshGeometries){if(!Shape)return Refuse(Error,TEXT("null_cooked_shape"));const auto& P=Shape->Particles();const auto& E=Shape->Elements();CV+=P.Size();CT+=E.GetNumTriangles();if(CV>S.Limit->W||CT>S.Limit->T)return Refuse(Error,TEXT("aggregate_cooked_bounds"));for(int32 I=0;I<int32(P.Size());++I)if(!FinitePoint(P.GetX(I)))return Refuse(Error,TEXT("cooked_nonfinite"));for(int32 I=0;I<E.GetNumTriangles();++I){int32 A,B,C;if(E.RequiresLargeIndices()){const auto& T=E.GetLargeIndexBuffer()[I];A=T[0];B=T[1];C=T[2];}else{const auto& T=E.GetSmallIndexBuffer()[I];A=T[0];B=T[1];C=T[2];}const int32 X=Shape->GetExternalFaceIndexFromInternal(I);if(!Triangle(A,B,C,P.Size())||X<INDEX_NONE||X>=int32(S.Limit->T))return Refuse(Error,TEXT("cooked_index_or_remap_range"));}}
    // GetPhysicsTriMeshData may allocate. Bound both possible native input domains first.
    if(RD->CollisionDataForCookedCooker){const auto& C=*RD->CollisionDataForCookedCooker;if(!Count(C.Vertices.Num(),S.Limit->W)||!Count(C.Indices.Num(),S.Limit->T)||!Count(C.MaterialIndices.Num(),S.Limit->T)||!Count(C.UVs.Num(),MaxUV))return Refuse(Error,TEXT("cached_provider_preallocation_bounds"));for(const auto& UV:C.UVs)if(!Count(UV.Num(),S.Limit->W))return Refuse(Error,TEXT("cached_provider_UV_bounds"));}
    if(!M->GetPhysicsTriMeshData(&S.Provider,true))return Refuse(Error,TEXT("provider_unavailable_no_repair"));const auto& C=S.Provider;
    if(!Count(C.Vertices.Num(),S.Limit->W)||!Count(C.Indices.Num(),S.Limit->T)||!Count(C.MaterialIndices.Num(),S.Limit->T)||!Count(C.UVs.Num(),MaxUV)||(C.MaterialIndices.Num()!=0&&C.MaterialIndices.Num()!=C.Indices.Num()))return Refuse(Error,TEXT("provider_actual_bounds"));
    for(const auto& P:C.Vertices)if(!FinitePoint(P))return Refuse(Error,TEXT("provider_nonfinite"));for(const auto& T:C.Indices)if(!Triangle(T.v0,T.v1,T.v2,C.Vertices.Num()))return Refuse(Error,TEXT("provider_invalid_indices"));for(const auto& UV:C.UVs){if(!Count(UV.Num(),S.Limit->W))return Refuse(Error,TEXT("provider_UV_bounds"));for(const auto& P:UV)if(!FMath::IsFinite(P.X)||!FMath::IsFinite(P.Y))return Refuse(Error,TEXT("provider_nonfinite_UV"));}
    S.Meta->SetStringField(TEXT("asset"),M->GetPathName());S.Meta->SetStringField(TEXT("body"),S.Body->GetPathName());S.Meta->SetStringField(TEXT("body_GUID"),S.Guid.ToString(EGuidFormats::Digits));S.Meta->SetNumberField(TEXT("collision_mode"),int32(S.Body->CollisionTraceFlag));S.Meta->SetBoolField(TEXT("double_sided_geometry"),S.Body->bDoubleSidedGeometry);S.Meta->SetBoolField(TEXT("created_physics_meshes"),S.Body->bCreatedPhysicsMeshes);S.Meta->SetBoolField(TEXT("failed_physics_meshes"),S.Body->bFailedToCreatePhysicsMeshes);S.Meta->SetNumberField(TEXT("simple_elements"),double(NS));S.Meta->SetBoolField(TEXT("provider_flip_normals"),C.bFlipNormals);S.Meta->SetNumberField(TEXT("provider_UV_channels_observed_not_exported"),C.UVs.Num());S.Meta->SetStringField(TEXT("cooked_stored_material_array"),TEXT("UNOBSERVED_PRIVATE_STORAGE"));S.Meta->SetStringField(TEXT("cooked_effective_material_kind12"),TEXT("GetMaterialIndex(internalTriangleI), native uint16 result; accessor returns fallback0 when backing array lacks that index; NOT raw stored-array proof"));
    const FBodyInstance& Defaults=S.Body->DefaultInstance;S.Meta->SetStringField(TEXT("default_collision_profile"),Defaults.GetCollisionProfileName().ToString());S.Meta->SetNumberField(TEXT("default_object_type"),int32(Defaults.GetObjectType()));S.Meta->SetNumberField(TEXT("default_collision_enabled"),int32(Defaults.GetCollisionEnabled()));S.Meta->SetBoolField(TEXT("default_simulate_physics"),Defaults.bSimulatePhysics);S.Meta->SetNumberField(TEXT("default_Pawn_response"),int32(Defaults.GetResponseToChannel(ECC_Pawn)));S.Meta->SetNumberField(TEXT("default_Camera_response"),int32(Defaults.GetResponseToChannel(ECC_Camera)));S.Meta->SetBoolField(TEXT("asset_defaults_not_live_world_policy"),true);S.Meta->SetBoolField(TEXT("outer_owner_all_source_sidecars_custody_required"),true);
    S.Meta->SetNumberField(TEXT("declared_native_W"),S.Limit->W);S.Meta->SetNumberField(TEXT("declared_positive_T"),S.Limit->T);S.Meta->SetNumberField(TEXT("payload_batch"),S.Limit->Batch);S.Meta->SetNumberField(TEXT("payload_mesh_index"),S.Limit->LocalMesh);S.Meta->SetStringField(TEXT("source_domain_id"),S.Limit->Domain);
    return true;
}

void Entries(FSnapshot& S)
{
    auto Add=[&](uint32 Kind,uint32 Shape,uint32 Stride,uint32 N,uint32 PB,uint32 IB,uint32 Flags,TFunction<void(FWriter&)> Emit){FEntry E;E.Kind=Kind;E.Shape=Shape;E.Stride=Stride;E.N=N;E.PositionBytes=PB;E.IndexBytes=IB;E.Flags=Flags;E.Bytes=uint64(Stride)*N;E.Emit=MoveTemp(Emit);S.Entries.Add(MoveTemp(E));};
    const auto& D=*S.MD;const auto Pos=FStaticMeshConstAttributes(D).GetVertexPositions();
    Add(1,NoShape,16,D.Vertices().Num(),4,4,1,[&D,Pos](FWriter& W){for(FVertexID ID:D.Vertices().GetElementIDs()){W.U32(ID.GetValue());W.Point(Pos[ID]);}});
    Add(2,NoShape,20,D.Triangles().Num(),0,4,1,[&D](FWriter& W){for(FTriangleID ID:D.Triangles().GetElementIDs()){const auto V=D.GetTriangleVertices(ID);W.U32(ID.GetValue());for(FVertexID X:V)W.U32(X.GetValue());W.I32(D.GetTrianglePolygonGroup(ID).GetValue());}});
    const auto& L=*S.Render;Add(3,NoShape,12,L.VertexBuffers.PositionVertexBuffer.GetNumVertices(),4,0,0,[&L](FWriter& W){for(uint32 I=0;I<L.VertexBuffers.PositionVertexBuffer.GetNumVertices();++I)W.Point(L.VertexBuffers.PositionVertexBuffer.VertexPosition(I));});
    Add(4,NoShape,12,L.IndexBuffer.GetNumIndices()/3,0,L.IndexBuffer.GetIndexDataSize()/L.IndexBuffer.GetNumIndices(),0,[&L](FWriter& W){const auto V=L.IndexBuffer.GetArrayView();for(int32 I=0;I<V.Num();++I)W.U32(V[I]);});
    Add(5,NoShape,20,L.Sections.Num(),0,4,0,[&L](FWriter& W){for(const auto& X:L.Sections){W.U32(X.MaterialIndex);W.U32(X.FirstIndex);W.U32(X.NumTriangles);W.U32(X.MinVertexIndex);W.U32(X.MaxVertexIndex);}});
    const auto& C=S.Provider;Add(6,NoShape,12,C.Vertices.Num(),4,0,0,[&C](FWriter& W){for(const auto& X:C.Vertices)W.Point(X);});
    Add(7,NoShape,12,C.Indices.Num(),0,sizeof(FTriIndices::v0),1,[&C](FWriter& W){for(const auto& X:C.Indices){W.I32(X.v0);W.I32(X.v1);W.I32(X.v2);}});
    Add(8,NoShape,4,C.MaterialIndices.Num(),0,sizeof(decltype(C.MaterialIndices)::ElementType),0,[&C](FWriter& W){for(const auto X:C.MaterialIndices)W.U32(X);});
    for(int32 Shape=0;Shape<S.Body->TriMeshGeometries.Num();++Shape)
    {
        const auto* Object=S.Body->TriMeshGeometries[Shape].GetReference();const auto& P=Object->Particles();const auto& E=Object->Elements();using Scalar=std::remove_cv_t<std::remove_reference_t<decltype(P.GetX(0)[0])>>;static_assert(std::is_same_v<Scalar,float>||std::is_same_v<Scalar,double>);
        Add(9,Shape,3*sizeof(Scalar),P.Size(),sizeof(Scalar),0,0,[Object](FWriter& W){const auto& V=Object->Particles();for(int32 I=0;I<int32(V.Size());++I)W.Point(V.GetX(I));});
        using LargeIndex=std::remove_cv_t<std::remove_reference_t<decltype(E.GetLargeIndexBuffer()[0][0])>>;using SmallIndex=std::remove_cv_t<std::remove_reference_t<decltype(E.GetSmallIndexBuffer()[0][0])>>;static_assert(sizeof(LargeIndex)==4&&sizeof(SmallIndex)==2);
        const uint32 IndexBytes=E.RequiresLargeIndices()?sizeof(LargeIndex):sizeof(SmallIndex),IndexSigned=E.RequiresLargeIndices()?uint32(std::is_signed_v<LargeIndex>):uint32(std::is_signed_v<SmallIndex>);
        Add(10,Shape,12,E.GetNumTriangles(),0,IndexBytes,IndexSigned,[Object](FWriter& W){const auto& V=Object->Elements();for(int32 I=0;I<V.GetNumTriangles();++I){if(V.RequiresLargeIndices()){const auto& T=V.GetLargeIndexBuffer()[I];for(int32 C=0;C<3;++C)W.U32(T[C]);}else{const auto& T=V.GetSmallIndexBuffer()[I];for(int32 C=0;C<3;++C)W.U32(T[C]);}}});
        Add(11,Shape,4,E.GetNumTriangles(),0,4,1,[Object](FWriter& W){for(int32 I=0;I<Object->Elements().GetNumTriangles();++I)W.I32(Object->GetExternalFaceIndexFromInternal(I));});
        static_assert(std::is_same_v<decltype(Object->GetMaterialIndex(0u)),uint16>);
        Add(12,Shape,4,E.GetNumTriangles(),0,sizeof(decltype(Object->GetMaterialIndex(0u))),0,[Object](FWriter& W){for(int32 I=0;I<Object->Elements().GetNumTriangles();++I)W.U32(Object->GetMaterialIndex(uint32(I)));});
    }
    S.Expected=64+uint64(S.Entries.Num())*64;for(auto& E:S.Entries){E.Offset=S.Expected;S.Expected+=E.Bytes;}
}


bool OwnedSession(FString& Owned,FString& Error)
{
    if(CollisionSessionState.load(std::memory_order_seq_cst)!=ECollisionSessionState::Active)return Refuse(Error,TEXT("terminal_session_refused_no_retry"));
    if(!IsInGameThread()||!GIsEditor||IsRunningCommandlet())return Refuse(Error,TEXT("owned_Editor_game_thread_no_commandlet"));
    Owned=FPlatformMisc::GetEnvironmentVariable(TEXT("LIVING_TOWN_BOOTSTRAP_OUTPUT"));if(Owned.IsEmpty()||FPaths::IsRelative(Owned))return Refuse(Error,TEXT("owned_output_environment"));
    Owned=FPaths::ConvertRelativePathToFull(Owned);FPaths::NormalizeDirectoryName(Owned);FString Project=FPaths::ConvertRelativePathToFull(FPaths::ProjectDir());FPaths::NormalizeDirectoryName(Project);
    if(!NoReparse(Owned)||!Project.Equals(FPaths::Combine(Owned,TEXT("Project")),ESearchCase::CaseSensitive)||FPaths::IsUnderDirectory(Owned,FPaths::ConvertRelativePathToFull(FPaths::EngineDir()))||(!CollisionSessionRoot.IsEmpty()&&CollisionSessionRoot!=Owned))return Refuse(Error,TEXT("exact_owned_Project_root_no_reparse_or_changed_owner"));
    CollisionSessionRoot=Owned;return true;
}
bool Quota(uint64 Reserved,uint64 CallBytes)
{return CallBytes<=CallCap&&Reserved<=SessionCap&&CallBytes<=SessionCap-Reserved&&Reserved<=DeclaredAggregateCap&&CallBytes<=DeclaredAggregateCap-Reserved;}

} // namespace RemainderIntakeV2

static bool ExportRemainderCollisionMeshesV2Impl(const TArray<FString>& Paths,const FString& Relative,FString& ReceiptJson,FString& Error)
{
    using namespace RemainderIntakeV2;ReceiptJson.Empty();Error.Empty();
    if(!IsInGameThread()||!GIsEditor||Paths.IsEmpty()||Paths.Num()>8||!Leaf(Relative))return Refuse(Error,TEXT("editor_thread_batch8_fresh_leaf_required"));
    FString Owned;if(!OwnedSession(Owned,Error))return false;const FString Out=FPaths::Combine(Owned,Relative);
    if(!FPaths::IsUnderDirectory(Out,Owned)||FPaths::IsUnderDirectory(Out,FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()))||FPaths::IsUnderDirectory(Out,FPaths::ConvertRelativePathToFull(FPaths::EngineDir()))||IFileManager::Get().FileExists(*Out)||IFileManager::Get().DirectoryExists(*Out))return Refuse(Error,TEXT("fresh_owned_output_boundary"));
    TArray<TUniquePtr<FSnapshot>> Snapshots;TSet<int32> Batch;uint64 CallBytes=0;
    for(const FString& Path:Paths)
    {
        const int32 ID=RosterIndex(Path);if(ID==INDEX_NONE||Batch.Contains(ID)||CollisionSeen.Contains(ID))return Refuse(Error,TEXT("exact12_remainder_roster_unique_not_previous_export"));Batch.Add(ID);
        UStaticMesh* M=FindObject<UStaticMesh>(nullptr,*Path);if(!IsValid(M)||M->GetClass()!=UStaticMesh::StaticClass()||M->IsTemplate()||M->HasAnyFlags(RF_NeedLoad|RF_NeedPostLoad|RF_NeedPostLoadSubobjects))return Refuse(Error,TEXT("already_loaded_exact_StaticMesh_no_load"));
        auto S=MakeUnique<FSnapshot>();S->Mesh.Reset(M);S->Roster=ID;S->Limit=&MeshRoster[ID];S->Dirty=M->GetOutermost()->IsDirty();if(S->Dirty)return Refuse(Error,TEXT("saved_clean_asset_required"));S->PackageFile=FPaths::ConvertRelativePathToFull(FPackageName::LongPackageNameToFilename(M->GetOutermost()->GetName(),FPackageName::GetAssetPackageExtension()));if(!FPaths::IsUnderDirectory(S->PackageFile,FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()))||!Digest(S->PackageFile,256ull<<20,S->PackageHash,S->PackageBytes))return Refuse(Error,TEXT("saved_owned_asset_file_boundary_or_hash"));
        if(!Preflight(*S,Error))return false;Entries(*S);if(S->Expected>FileCap)return Refuse(Error,TEXT("binary_file32MiB"));CallBytes+=S->Expected;if(CallBytes>CallCap)return Refuse(Error,TEXT("binary_call256MiB"));Snapshots.Add(MoveTemp(S));
    }
    if(!Quota(CollisionSessionReserved,CallBytes))return Refuse(Error,TEXT("binary_session512MiB_and_exact_declared12_aggregate"));CollisionSessionRoot=Owned;CollisionSessionReserved+=CallBytes;for(int32 ID:Batch)CollisionSeen.Add(ID); // Active until successful CAS completion; any refusal is permanent Terminal.
    if(!IFileManager::Get().MakeDirectory(*Out,false)||!NoReparse(Out))return Refuse(Error,TEXT("fresh_output_create"));TArray<TSharedPtr<FJsonValue>> Results;
    for(auto& Ptr:Snapshots)
    {
        auto& S=*Ptr;const FString Name=FString::Printf(TEXT("RemainderV2_%02d.bin"),S.Roster),File=FPaths::Combine(Out,Name);FWriter W(File);for(int32 I=0;I<16;++I)W.U8(uint8(Magic[I]));for(uint32 X:{2u,64u,uint32(S.Roster),uint32(S.Entries.Num()),0x01020304u,0u})W.U32(X);W.U64(S.Expected);W.U64(64);W.U64(uint64(S.Entries.Num())*64);
        for(const auto& E:S.Entries){for(uint32 X:{E.Kind,E.Shape,E.Stride,E.N})W.U32(X);W.U64(E.Offset);W.U64(E.Bytes);for(uint32 X:{E.PositionBytes,E.IndexBytes,E.Flags,0u})W.U32(X);W.U64(0);W.U64(0);}
        for(const auto& E:S.Entries){if(W.Tell()!=E.Offset)return Refuse(Error,TEXT("binary_offset_custody"));E.Emit(W);if(W.Tell()!=E.Offset+E.Bytes)return Refuse(Error,TEXT("binary_section_actual_size"));}if(!W.Finish()||W.Tell()!=S.Expected)return Refuse(Error,TEXT("binary_close_or_length"));
        FString Hash,NowHash;int64 Bytes=0,NowBytes=0;if(!Digest(File,FileCap,Hash,Bytes)||!Digest(S.PackageFile,256ull<<20,NowHash,NowBytes)||NowHash!=S.PackageHash||NowBytes!=S.PackageBytes||S.Mesh->IsCompiling()||S.Mesh->GetBodySetup()!=S.Body||S.Body->BodySetupGuid!=S.Guid||S.Mesh->GetOutermost()->IsDirty()!=S.Dirty)return Refuse(Error,TEXT("saved_asset_body_or_byte_custody_changed"));
        S.Meta->SetStringField(TEXT("binary"),Name);S.Meta->SetStringField(TEXT("binary_sha256"),Hash);S.Meta->SetNumberField(TEXT("binary_bytes"),double(Bytes));S.Meta->SetStringField(TEXT("source_package"),S.PackageFile);S.Meta->SetStringField(TEXT("source_package_sha256"),S.PackageHash);S.Meta->SetNumberField(TEXT("source_package_bytes"),double(S.PackageBytes));S.Meta->SetNumberField(TEXT("roster_index"),S.Roster);S.Meta->SetBoolField(TEXT("package_dirty_before"),S.Dirty);S.Meta->SetBoolField(TEXT("package_dirty_after"),S.Mesh->GetOutermost()->IsDirty());S.Meta->SetBoolField(TEXT("source_or_cooked_equality_qualified"),false);Results.Add(MakeShared<FJsonValueObject>(S.Meta));
    }
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("schema"),TEXT("LivingTown.RemainderCollisionBinary.v2"));O->SetStringField(TEXT("status"),TEXT("READ_ONLY_NATIVE_REMAINDER_COLLISION_RAW_ARRAYS_V2_EXPORTED"));O->SetArrayField(TEXT("exports"),Results);O->SetNumberField(TEXT("call_binary_bytes"),double(CallBytes));O->SetNumberField(TEXT("session_reserved_binary_bytes"),double(CollisionSessionReserved));O->SetBoolField(TEXT("asset_repaired_cooked_or_saved"),false);O->SetBoolField(TEXT("source_equality_art_world_GPU_DF_or_performance_qualified"),false);if(!NewJson(FPaths::Combine(Out,TEXT("MANIFEST.json")),O))return Refuse(Error,TEXT("manifest_new_write"));ReceiptJson=Json(O);if(!CompleteSession(Error)){ReceiptJson.Empty();return false;}return true;
}


FString ULivingTownRemainderCollisionInspectionV2::ReadRemainderConfigurationMetadataV2(UStaticMesh* Mesh)
{
    using namespace RemainderIntakeV2;FString Error,Owned;
    auto Fail=[&](const FString& Reason){Refuse(Error,Reason);return Reply(Reason.StartsWith(TEXT("HOLD_"))?TEXT("HOLD_RESOURCE_PENDING"):TEXT("REFUSED"),Reason);};
    if(!IsInGameThread())return Fail(TEXT("game_thread_required"));
    if(!BeginSession(Error))return Reply(TEXT("REFUSED"),Error);
    if(!IsValid(Mesh)||Mesh->GetClass()!=UStaticMesh::StaticClass()||Mesh->IsTemplate()||Mesh->HasAnyFlags(RF_NeedLoad|RF_NeedPostLoad|RF_NeedPostLoadSubobjects))return Fail(TEXT("already_loaded_exact_native_non_template_StaticMesh_required"));
    const int32 ID=RosterIndex(Mesh->GetPathName());if(ID==INDEX_NONE)return Fail(TEXT("exact12_remainder_roster_required"));
    if(MetadataSeen.Contains(ID))return Fail(TEXT("configuration_metadata_once_per_asset_no_retry"));
    if(!OwnedSession(Owned,Error))return Reply(TEXT("REFUSED"),Error);
    if(Mesh->IsCompiling())return Fail(TEXT("HOLD_mesh_compiling_no_wait"));
    const bool Dirty=Mesh->GetOutermost()->IsDirty();const UBodySetup* Body=Mesh->GetBodySetup();
    if(!Body||Body->GetOuter()!=Mesh)return Fail(TEXT("imported_BodySetup_present_and_outer_input_mesh_required_no_create"));
    const bool BodyDirty=Body->GetOutermost()->IsDirty();const FGuid GUID=Body->BodySetupGuid;
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("schema"),TEXT("LivingTown.RemainderConfigurationMetadata.v2"));O->SetStringField(TEXT("status"),TEXT("READ_ONLY_SCOPED_REMAINDER_CONFIGURATION_METADATA_V2"));O->SetStringField(TEXT("asset"),Mesh->GetPathName());O->SetStringField(TEXT("class"),Mesh->GetClass()->GetPathName());O->SetStringField(TEXT("package"),Mesh->GetOutermost()->GetPathName());O->SetBoolField(TEXT("package_dirty_before"),Dirty);O->SetBoolField(TEXT("allow_CPU_access"),Mesh->bAllowCPUAccess);O->SetBoolField(TEXT("Nanite_enabled"),Mesh->GetNaniteSettings().bEnabled);O->SetBoolField(TEXT("source_file_saved_byte_custody_qualified"),false);
    auto B=MakeShared<FJsonObject>();B->SetBoolField(TEXT("present"),true);B->SetStringField(TEXT("path"),Body->GetPathName());B->SetBoolField(TEXT("outer_is_input_mesh"),true);B->SetStringField(TEXT("GUID"),GUID.ToString(EGuidFormats::Digits));B->SetNumberField(TEXT("collision_trace_flag"),int32(Body->CollisionTraceFlag));B->SetBoolField(TEXT("double_sided_geometry"),Body->bDoubleSidedGeometry);B->SetBoolField(TEXT("created_physics_meshes"),Body->bCreatedPhysicsMeshes);B->SetBoolField(TEXT("failed_physics_meshes"),Body->bFailedToCreatePhysicsMeshes);O->SetObjectField(TEXT("body"),B);
    if(Mesh->IsCompiling()||Mesh->GetBodySetup()!=Body||Body->BodySetupGuid!=GUID||Mesh->GetOutermost()->IsDirty()!=Dirty||Body->GetOutermost()->IsDirty()!=BodyDirty)return Fail(TEXT("configuration_metadata_custody_changed"));
    O->SetBoolField(TEXT("package_dirty_after"),Mesh->GetOutermost()->IsDirty());O->SetBoolField(TEXT("asset_repaired_or_saved"),false);O->SetBoolField(TEXT("raw_MD_provider_cooked_arrays_or_world_physics_qualified"),false);MetadataSeen.Add(ID);const FString Result=Json(O);if(!CompleteSession(Error))return Reply(TEXT("REFUSED"),Error);return Result;
}
FString ULivingTownRemainderCollisionInspectionV2::ExportRemainderCollisionMeshesV2(const TArray<FString>& Paths,const FString& Relative)
{
    using namespace RemainderIntakeV2;FString Receipt,Error;
    if(!IsInGameThread()){Refuse(Error,TEXT("editor_thread_batch8_fresh_leaf_required"));return Reply(TEXT("REFUSED"),Error);}
    if(!BeginSession(Error))return Reply(TEXT("REFUSED"),Error);
    if(ExportRemainderCollisionMeshesV2Impl(Paths,Relative,Receipt,Error))return Receipt;
    return RemainderIntakeV2::Reply(Error.StartsWith(TEXT("HOLD_"))?TEXT("HOLD_RESOURCE_PENDING"):TEXT("REFUSED"),Error);
}
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
namespace
{
struct FRemainderV2TestState
{
    FString Root=RemainderIntakeV2::CollisionSessionRoot;uint64 Reserved=RemainderIntakeV2::CollisionSessionReserved;RemainderIntakeV2::ECollisionSessionState State=RemainderIntakeV2::CollisionSessionState.load();TSet<int32> Seen=RemainderIntakeV2::CollisionSeen,Metadata=RemainderIntakeV2::MetadataSeen;
    FRemainderV2TestState(){RemainderIntakeV2::CollisionSessionRoot.Empty();RemainderIntakeV2::CollisionSessionReserved=0;RemainderIntakeV2::CollisionSessionState.store(RemainderIntakeV2::ECollisionSessionState::Ready);RemainderIntakeV2::CollisionSeen.Empty();RemainderIntakeV2::MetadataSeen.Empty();}
    ~FRemainderV2TestState(){RemainderIntakeV2::CollisionSessionRoot=MoveTemp(Root);RemainderIntakeV2::CollisionSessionReserved=Reserved;RemainderIntakeV2::CollisionSessionState.store(State);RemainderIntakeV2::CollisionSeen=MoveTemp(Seen);RemainderIntakeV2::MetadataSeen=MoveTemp(Metadata);}
};
bool RemainderV2Reason(const FString& Text,const TCHAR* Reason)
{TSharedPtr<FJsonObject> O;FString Status,Actual;return FJsonSerializer::Deserialize(TJsonReaderFactory<TCHAR>::Create(Text),O)&&O.IsValid()&&O->TryGetStringField(TEXT("status"),Status)&&O->TryGetStringField(TEXT("reason"),Actual)&&Status==TEXT("REFUSED")&&Actual==Reason;}
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownRemainderV2RefusalTest,"LivingTown.RemainderCollisionV2.Refusals",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownRemainderV2RefusalTest::RunTest(const FString& Parameters)
{
    {FRemainderV2TestState Guard;const FString R=ULivingTownRemainderCollisionInspectionV2::ReadRemainderConfigurationMetadataV2(nullptr);TestTrue(TEXT("actual API null refuses"),RemainderV2Reason(R,TEXT("already_loaded_exact_native_non_template_StaticMesh_required")));TestTrue(TEXT("all later API calls terminally refuse"),RemainderV2Reason(ULivingTownRemainderCollisionInspectionV2::ExportRemainderCollisionMeshesV2({},TEXT("Test")),TEXT("terminal_session_refused_no_retry")));}
    {FRemainderV2TestState Guard;UStaticMesh* Foreign=NewObject<UStaticMesh>(GetTransientPackage(),NAME_None,RF_Transient);TestTrue(TEXT("actual metadata API rejects foreign transient mesh"),RemainderV2Reason(ULivingTownRemainderCollisionInspectionV2::ReadRemainderConfigurationMetadataV2(Foreign),TEXT("exact12_remainder_roster_required")));}
    {FRemainderV2TestState Guard;TArray<FString> Foreign={TEXT("/Game/Foreign.Mesh")};TestTrue(TEXT("actual export API rejects traversal before output creation"),RemainderV2Reason(ULivingTownRemainderCollisionInspectionV2::ExportRemainderCollisionMeshesV2(Foreign,TEXT("../escape")),TEXT("editor_thread_batch8_fresh_leaf_required")));}
    {FRemainderV2TestState Guard;TArray<FString> Foreign={TEXT("/Game/Foreign.Mesh")};const FString R=ULivingTownRemainderCollisionInspectionV2::ExportRemainderCollisionMeshesV2(Foreign,TEXT("Test"));TestTrue(TEXT("actual export refuses absent owner/foreign asset without load"),R.Contains(TEXT("REFUSED"))&&RemainderIntakeV2::SessionTerminal());}
    // Exercise production transitions and real off-thread public APIs. A successful
    // exporter completion must never erase a refusal observed while Active.
    for(bool MetadataAPI:{true,false})
    {
        FRemainderV2TestState Guard;FString Error;
        TestTrue(TEXT("production Ready to Active succeeds"),RemainderIntakeV2::BeginSession(Error));
        TFuture<FString> Worker=Async(EAsyncExecution::Thread,[MetadataAPI]()
        {
            return MetadataAPI?ULivingTownRemainderCollisionInspectionV2::ReadRemainderConfigurationMetadataV2(nullptr):ULivingTownRemainderCollisionInspectionV2::ExportRemainderCollisionMeshesV2({},TEXT("Test"));
        });
        const FString Refusal=Worker.Get();
        TestTrue(TEXT("actual off-thread API refuses without touching session containers"),RemainderV2Reason(Refusal,MetadataAPI?TEXT("game_thread_required"):TEXT("editor_thread_batch8_fresh_leaf_required")));
        TestTrue(TEXT("off-thread refusal makes active production state Terminal"),RemainderIntakeV2::SessionTerminal());
        TestFalse(TEXT("production completion cannot reset concurrent refusal"),RemainderIntakeV2::CompleteSession(Error));
        TestTrue(TEXT("completion leaves Terminal permanent"),RemainderIntakeV2::SessionTerminal());
        TestTrue(TEXT("subsequent actual public API remains refused"),RemainderV2Reason(ULivingTownRemainderCollisionInspectionV2::ExportRemainderCollisionMeshesV2({},TEXT("Test")),TEXT("terminal_session_refused_no_retry")));
    }
    {FRemainderV2TestState Guard;FString Error;TestTrue(TEXT("ordinary production begin"),RemainderIntakeV2::BeginSession(Error));TestTrue(TEXT("ordinary production completion"),RemainderIntakeV2::CompleteSession(Error));TestFalse(TEXT("ordinary completion is not Terminal"),RemainderIntakeV2::SessionTerminal());TestTrue(TEXT("next ordinary production begin"),RemainderIntakeV2::BeginSession(Error));TestFalse(TEXT("reentry terminally refuses"),RemainderIntakeV2::BeginSession(Error));TestFalse(TEXT("reentry cannot be cleared by completion"),RemainderIntakeV2::CompleteSession(Error));TestTrue(TEXT("reentry remains Terminal"),RemainderIntakeV2::SessionTerminal());}
    return true;
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownRemainderV2ScopeBudgetTest,"LivingTown.RemainderCollisionV2.ScopeBudget",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownRemainderV2ScopeBudgetTest::RunTest(const FString& Parameters)
{
    using namespace RemainderIntakeV2;uint64 Budget=0;TSet<FString> Names;
    for(int32 I=0;I<UE_ARRAY_COUNT(MeshRoster);++I){const auto& B=MeshRoster[I];TestEqual(TEXT("exact case-sensitive roster lookup"),RosterIndex(B.Path),I);TestEqual(TEXT("case-changed path refuses"),RosterIndex(FString(B.Path).ToLower()),INDEX_NONE);Names.Add(B.Path);TestTrue(TEXT("perasset frozen W/T"),B.W<=300000&&B.T<=100000&&B.W>=uint64(B.T)*3);Budget+=uint64(B.W)*64+uint64(B.T)*68+3904;}
    TestEqual(TEXT("twelve unique assets"),Names.Num(),12);TestEqual(TEXT("independent fixed-layout aggregate"),Budget,uint64(133751848));TestTrue(TEXT("exact declared boundary accepts"),Quota(0,Budget));TestFalse(TEXT("one byte beyond declared scope refuses"),Quota(0,Budget+1));TestFalse(TEXT("over call cap refuses"),Quota(0,CallCap+1));TestFalse(TEXT("over session refuses without unsigned underflow"),Quota(SessionCap+1,1));TestFalse(TEXT("negative vertex count refuses"),Count(-1,MeshRoster[0].W));return true;
}
#endif
