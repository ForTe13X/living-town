#include "LivingTownConnectorCollision.h"
#include "LivingTownTileData.h"
#include "Editor.h"
#include "Engine/World.h"
#include "Engine/StaticMesh.h"
#include "Materials/Material.h"
#include "MaterialDomain.h"
#include "MeshDescription.h"
#include "StaticMeshAttributes.h"
#include "StaticMeshResources.h"
#include "PhysicsEngine/BodySetup.h"
#include "PhysicsEngine/BodyInstance.h"
#include "Interfaces/Interface_CollisionDataProvider.h"
#include "Chaos/TriangleMeshImplicitObject.h"
#include "AssetRegistry/AssetRegistryModule.h"
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

namespace
{
constexpr const TCHAR* ConnectorRelative=TEXT("Content/ConnectorCollisionSource_v001/ConnectorWalk29.ltcoll");
constexpr const TCHAR* ConnectorSourceSHA=TEXT("b7cf9f1d56b7159e7a57ddc17dd95d3120b22ed8bd92f79f5099f5a18798eb2e");
constexpr const TCHAR* ConnectorFolder=TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/ReserveConnectorPhysics_v002/Colliders");
constexpr int32 ConnectorMeshCount=29,ConnectorTriangleCount=1424,ConnectorSourceBytes=73798;
bool ConnectorApplied=false;
struct FConnectorMeshSource{FString Name;TArray<FVector3f> Positions;TArray<FIntVector> Triangles;};
FString ConnectorJson(const TSharedRef<FJsonObject>& O){FString S;FJsonSerializer::Serialize(O,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&S));return S;}
FString ConnectorError(const FString& Why){auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("ERROR"));O->SetStringField(TEXT("error"),Why);return ConnectorJson(O);}
uint32 ConnectorBits(float V){uint32 B=0;FMemory::Memcpy(&B,&V,4);return B;}
bool ConnectorSame(const FVector3f& A,const FVector3f& B){return ConnectorBits(A.X)==ConnectorBits(B.X)&&ConnectorBits(A.Y)==ConnectorBits(B.Y)&&ConnectorBits(A.Z)==ConnectorBits(B.Z);}
FString ConnectorPointKey(const FVector3f& P){return FString::Printf(TEXT("%08x,%08x,%08x"),ConnectorBits(P.X),ConnectorBits(P.Y),ConnectorBits(P.Z));}
FString ConnectorTriangleKey(const FVector3f& A,const FVector3f& B,const FVector3f& C)
{
    const FString X=ConnectorPointKey(A),Y=ConnectorPointKey(B),Z=ConnectorPointKey(C);FString K=X+TEXT("|")+Y+TEXT("|")+Z;
    const FString BKey=Y+TEXT("|")+Z+TEXT("|")+X,CKey=Z+TEXT("|")+X+TEXT("|")+Y;
    if(BKey.Compare(K)<0)K=BKey;if(CKey.Compare(K)<0)K=CKey;return K;
}
void ConnectorCount(TMap<FString,int32>& Values,const FVector3f& A,const FVector3f& B,const FVector3f& C){++Values.FindOrAdd(ConnectorTriangleKey(A,B,C));}
bool ConnectorEqual(const TMap<FString,int32>& A,const TMap<FString,int32>& B){if(A.Num()!=B.Num())return false;for(const auto& P:A){const int32* V=B.Find(P.Key);if(!V||*V!=P.Value)return false;}return true;}
TSharedRef<FJsonValue> ConnectorPoint(const FVector3f& P){return MakeShared<FJsonValueArray>(TArray<TSharedPtr<FJsonValue>>{MakeShared<FJsonValueNumber>(double(ConnectorBits(P.X))),MakeShared<FJsonValueNumber>(double(ConnectorBits(P.Y))),MakeShared<FJsonValueNumber>(double(ConnectorBits(P.Z)))});}
TSharedRef<FJsonValue> ConnectorTriangle(int32 A,int32 B,int32 C){return MakeShared<FJsonValueArray>(TArray<TSharedPtr<FJsonValue>>{MakeShared<FJsonValueNumber>(A),MakeShared<FJsonValueNumber>(B),MakeShared<FJsonValueNumber>(C)});}
bool ConnectorContext(bool Author,FString& Why)
{
    if(!IsInGameThread()||!GEditor||GEditor->PlayWorld){Why=TEXT("Editor_GT_outside_PIE_required");return false;}
    UWorld* W=GEditor->GetEditorWorldContext().World();if(!W||W->WorldType!=EWorldType::Editor||W->IsGameWorld()){Why=TEXT("Editor_world_required");return false;}
    FString Project=FPaths::ConvertRelativePathToFull(FPaths::ProjectDir());FPaths::NormalizeDirectoryName(Project);
    if(!(Project.EndsWith(TEXT("/Author/Project"))||(!Author&&Project.EndsWith(TEXT("/Review/Project"))))){Why=TEXT("private_Author_or_Review_Project_required");return false;}
    if(Author)
    {
        const TCHAR* Cursor=FCommandLine::Get();FString Token;int32 Matches=0;
        while(FParse::Token(Cursor,Token,false))if(Token.StartsWith(TEXT("-LivingTownConnectorAuthor"),ESearchCase::IgnoreCase))
        {if(Token!=FString(TEXT("-LivingTownConnectorAuthor="))+ConnectorSourceSHA||++Matches!=1){Why=TEXT("one_exact_source_Author_flag_required");return false;}}
        if(Matches!=1||ConnectorApplied){Why=TEXT("explicit_Author_intent_once_required");return false;}
    }
    return true;
}
struct FConnectorBinaryReader
{
    const TArray<uint8>& Data;int32 Cursor=0;bool Good=true;
    uint32 U32(){if(Cursor+4>Data.Num()){Good=false;return 0;}uint32 X=0;for(int32 I=0;I<4;++I)X|=uint32(Data[Cursor++])<<(8*I);return X;}
    double F64(){if(Cursor+8>Data.Num()){Good=false;return 0;}uint64 B=0;for(int32 I=0;I<8;++I)B|=uint64(Data[Cursor++])<<(8*I);double V=0;FMemory::Memcpy(&V,&B,8);if(!FMath::IsFinite(V)||FMath::Abs(V)>1e8)Good=false;return V;}
};
bool ConnectorSource(TArray<FConnectorMeshSource>& Meshes,FString& Why)
{
    const FString File=FPaths::Combine(FPaths::ProjectDir(),ConnectorRelative);if(IFileManager::Get().FileSize(*File)!=ConnectorSourceBytes){Why=TEXT("bounded_source_size_required");return false;}TArray<uint8> Data;
    FString Hash;if(!FFileHelper::LoadFileToArray(Data,*File)||Data.Num()!=ConnectorSourceBytes||!LivingTownTiles::HashBytes(Data,Hash)||Hash!=ConnectorSourceSHA){Why=TEXT("exact_closed_source_SHA_required");return false;}
    const uint8 Magic[16]={'L','T','C','O','L','L','2','9','V','0','0','1',0,0,0,0};if(FMemory::Memcmp(Data.GetData(),Magic,16)){Why=TEXT("source_magic");return false;}FConnectorBinaryReader R{Data,16};if(R.U32()!=ConnectorMeshCount||R.U32()!=ConnectorTriangleCount){Why=TEXT("source_counts");return false;}
    int32 Sum=0;TSet<FString> Names;
    for(int32 I=0;I<ConnectorMeshCount;++I)
    {
        const uint32 N=R.U32(),V=R.U32(),T=R.U32();if(!R.Good||N<1||N>96||V<3||V>10000||T<1||T>10000||R.Cursor+int32(N)>Data.Num()){Why=TEXT("bounded_mesh_header");return false;}FConnectorMeshSource M;
        for(uint32 J=0;J<N;++J){const uint8 C=Data[R.Cursor++];if(!((C>='A'&&C<='Z')||(C>='a'&&C<='z')||(C>='0'&&C<='9')||C=='_')){Why=TEXT("bounded_asset_name");return false;}M.Name.AppendChar(TCHAR(C));}
        if(!M.Name.StartsWith(FString::Printf(TEXT("SM_CA_%02d_"),I))||!M.Name.EndsWith(TEXT("_WALK_COLLIDER"))||Names.Contains(M.Name)){Why=TEXT("exact_ordered_source_mesh_names");return false;}Names.Add(M.Name);M.Positions.Reserve(V);
        for(uint32 J=0;J<V;++J){const double X=R.F64(),Y=R.F64(),Z=R.F64();M.Positions.Add(FVector3f(float(X),float(Y),float(Z)));}
        M.Triangles.Reserve(T);for(uint32 J=0;J<T;++J){const uint32 A=R.U32(),B=R.U32(),C=R.U32();if(!R.Good||A>=V||B>=V||C>=V||A==B||B==C||A==C){Why=TEXT("source_triangle_index");return false;}const FVector3f Nrm=FVector3f::CrossProduct(M.Positions[B]-M.Positions[A],M.Positions[C]-M.Positions[A]);if(Nrm.SizeSquared()<=1e-12f){Why=TEXT("F32_collapsed_triangle");return false;}M.Triangles.Add(FIntVector(A,B,C));}Sum+=T;Meshes.Add(MoveTemp(M));
    }
    if(!R.Good||R.Cursor!=Data.Num()||Sum!=ConnectorTriangleCount){Why=TEXT("closed_binary_no_trailing_bytes");return false;}return true;
}
FString ConnectorPackage(const FConnectorMeshSource& S){return FString(ConnectorFolder)+TEXT("/")+S.Name;}
FString ConnectorObject(const FConnectorMeshSource& S){return ConnectorPackage(S)+TEXT(".")+S.Name;}
TSharedRef<FJsonObject> ConnectorReadOne(const FConnectorMeshSource& S,bool& AllExact,bool& Pending)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("asset"),ConnectorObject(S));UStaticMesh* M=LoadObject<UStaticMesh>(nullptr,*ConnectorObject(S));
    if(!M){O->SetStringField(TEXT("error"),TEXT("missing_owned_static_mesh"));AllExact=false;return O;}
    const bool Dirty=M->GetOutermost()->IsDirty();O->SetBoolField(TEXT("package_dirty_before"),Dirty);
    if(M->IsCompiling()){O->SetStringField(TEXT("status"),TEXT("PENDING_NATIVE_STATIC_MESH_COMPILATION"));Pending=true;return O;}
    FMeshDescription* D=M->GetMeshDescription(0);if(!D||D->Vertices().Num()>10000||D->Triangles().Num()>10000){O->SetStringField(TEXT("error"),TEXT("bounded_committed_MeshDescription_required"));AllExact=false;return O;}
    FStaticMeshAttributes A(*D);const auto Positions=A.GetVertexPositions();TArray<TSharedPtr<FJsonValue>> Points,Tris;bool Exact=D->Vertices().Num()==S.Positions.Num()&&D->Triangles().Num()==S.Triangles.Num();
    for(int32 I=0;I<D->Vertices().Num();++I){if(!D->IsVertexValid(FVertexID(I))){Exact=false;continue;}const FVector3f P=Positions[FVertexID(I)];Points.Add(ConnectorPoint(P));if(!S.Positions.IsValidIndex(I)||!ConnectorSame(P,S.Positions[I]))Exact=false;}
    for(int32 I=0;I<D->Triangles().Num();++I){if(!D->IsTriangleValid(FTriangleID(I))){Exact=false;continue;}const auto V=D->GetTriangleVertices(FTriangleID(I));Tris.Add(ConnectorTriangle(V[0].GetValue(),V[1].GetValue(),V[2].GetValue()));if(!S.Triangles.IsValidIndex(I)||V[0].GetValue()!=S.Triangles[I].X||V[1].GetValue()!=S.Triangles[I].Y||V[2].GetValue()!=S.Triangles[I].Z)Exact=false;}
    O->SetArrayField(TEXT("MeshDescription_positions_F32_bits"),Points);O->SetArrayField(TEXT("MeshDescription_source_vertex_indices"),Tris);O->SetBoolField(TEXT("MeshDescription_source_F64_to_F32_and_indices_exact"),Exact);
    FTriMeshCollisionData Input;if(!M->GetPhysicsTriMeshData(&Input,true)||Input.Indices.Num()>10000||Input.Vertices.Num()>10000){O->SetStringField(TEXT("error"),TEXT("bounded_actual_physics_provider_required"));AllExact=false;return O;}
    Points.Reset();Tris.Reset();for(const FVector3f& P:Input.Vertices)Points.Add(ConnectorPoint(P));TMap<FString,int32> Expected,Provider,CookExpected,Cooked;
    for(const FIntVector& T:S.Triangles)ConnectorCount(Expected,S.Positions[T.X],S.Positions[T.Y],S.Positions[T.Z]);
    for(const FTriIndices& T:Input.Indices){if(!Input.Vertices.IsValidIndex(T.v0)||!Input.Vertices.IsValidIndex(T.v1)||!Input.Vertices.IsValidIndex(T.v2)){Exact=false;continue;}Tris.Add(ConnectorTriangle(T.v0,T.v1,T.v2));const FVector3f X=Input.Vertices[T.v0],Y=Input.Vertices[T.v1],Z=Input.Vertices[T.v2];ConnectorCount(Provider,X,Y,Z);if(Input.bFlipNormals)ConnectorCount(CookExpected,Y,X,Z);else ConnectorCount(CookExpected,X,Y,Z);}
    Exact&=ConnectorEqual(Expected,Provider);O->SetArrayField(TEXT("provider_positions_F32_bits"),Points);O->SetArrayField(TEXT("provider_indices"),Tris);O->SetBoolField(TEXT("provider_source_oriented_triangle_multiset_exact"),ConnectorEqual(Expected,Provider));O->SetBoolField(TEXT("provider_bFlipNormals"),Input.bFlipNormals);
    const UBodySetup* B=M->GetBodySetup();const bool Policy=B&&B->CollisionTraceFlag==CTF_UseComplexAsSimple&&B->AggGeom.GetElementCount()==0&&!B->bDoubleSidedGeometry&&B->DefaultInstance.GetCollisionProfileName()==FName(TEXT("BlockAll"))&&B->DefaultInstance.GetCollisionEnabled()==ECollisionEnabled::QueryAndPhysics&&!B->DefaultInstance.bSimulatePhysics&&B->DefaultInstance.GetResponseToChannel(ECC_Pawn)==ECR_Block&&B->DefaultInstance.GetResponseToChannel(ECC_Camera)==ECR_Block;
    O->SetBoolField(TEXT("complex_as_simple_static_BlockAll_no_simple_shapes"),Policy);O->SetBoolField(TEXT("Nanite_enabled"),M->GetNaniteSettings().bEnabled);O->SetBoolField(TEXT("support_ray_tracing"),M->bSupportRayTracing);Exact&=Policy&&!M->GetNaniteSettings().bEnabled&&!M->bSupportRayTracing;
    if(!B||!B->bCreatedPhysicsMeshes||B->bFailedToCreatePhysicsMeshes||B->TriMeshGeometries.Num()!=1){O->SetStringField(TEXT("error"),TEXT("one_actual_created_Chaos_trimesh_required"));AllExact=false;return O;}
    const auto& Shape=B->TriMeshGeometries[0];if(Shape.GetReference()==nullptr){O->SetStringField(TEXT("error"),TEXT("actual_Chaos_shape_pointer_required"));AllExact=false;return O;}const auto& P=Shape->Particles();const auto& E=Shape->Elements();if(P.Size()>10000u||E.GetNumTriangles()>10000){O->SetStringField(TEXT("error"),TEXT("bounded_cooked_Chaos_shape"));AllExact=false;return O;}const int32 ConnectorParticlesCount=static_cast<int32>(P.Size());Points.Reset();Tris.Reset();TArray<TSharedPtr<FJsonValue>> Faces;
    for(int32 I=0;I<ConnectorParticlesCount;++I){const auto& V=P.GetX(I);Points.Add(ConnectorPoint(FVector3f(V[0],V[1],V[2])));}
    for(int32 I=0;I<E.GetNumTriangles();++I)
    {
        int32 X=0,Y=0,Z=0;if(E.RequiresLargeIndices()){const auto& T=E.GetLargeIndexBuffer()[I];X=T[0];Y=T[1];Z=T[2];}else{const auto& T=E.GetSmallIndexBuffer()[I];X=T[0];Y=T[1];Z=T[2];}
        Tris.Add(ConnectorTriangle(X,Y,Z));Faces.Add(MakeShared<FJsonValueNumber>(Shape->GetExternalFaceIndexFromInternal(I)));
        if(X<0||Y<0||Z<0||X>=ConnectorParticlesCount||Y>=ConnectorParticlesCount||Z>=ConnectorParticlesCount){Exact=false;continue;}const auto Xp=P.GetX(X),Yp=P.GetX(Y),Zp=P.GetX(Z);ConnectorCount(Cooked,FVector3f(Xp[0],Xp[1],Xp[2]),FVector3f(Yp[0],Yp[1],Yp[2]),FVector3f(Zp[0],Zp[1],Zp[2]));
    }
    const bool CookExact=E.GetNumTriangles()==S.Triangles.Num()&&ConnectorEqual(CookExpected,Cooked);Exact&=CookExact;O->SetArrayField(TEXT("Chaos_cooked_positions_F32_bits"),Points);O->SetArrayField(TEXT("Chaos_cooked_indices"),Tris);O->SetArrayField(TEXT("Chaos_cooked_external_face_indices"),Faces);O->SetBoolField(TEXT("cooked_oriented_triangle_multiset_exact_after_recorded_flip"),CookExact);O->SetStringField(TEXT("BodySetup_guid"),B->BodySetupGuid.ToString(EGuidFormats::Digits));O->SetBoolField(TEXT("bHasCookedCollisionData_diagnostic_not_Editor_authority"),B->bHasCookedCollisionData);O->SetBoolField(TEXT("package_dirty_after"),M->GetOutermost()->IsDirty());Exact&=M->GetOutermost()->IsDirty()==Dirty;O->SetBoolField(TEXT("all_source_and_cooked_checks_exact"),Exact);AllExact&=Exact;return O;
}
FString ConnectorRead(const TArray<FConnectorMeshSource>& Meshes)
{
    auto O=MakeShared<FJsonObject>();TArray<TSharedPtr<FJsonValue>> Rows;bool Exact=true,Pending=false;for(const FConnectorMeshSource& S:Meshes)Rows.Add(MakeShared<FJsonValueObject>(ConnectorReadOne(S,Exact,Pending)));
    O->SetStringField(TEXT("schema"),TEXT("LivingTown.NativeConnectorCollisionReadback.v1"));O->SetStringField(TEXT("status"),!Exact?TEXT("ERROR_NATIVE_COLLIDER_SOURCE_OR_COOK"):Pending?TEXT("PENDING_NATIVE_COLLIDER_COMPILATION"):TEXT("READ_ONLY_EXACT_NATIVE_29_COLLIDER_ASSETS_AND_COOKED_CHAOS"));O->SetStringField(TEXT("source_sha256"),ConnectorSourceSHA);O->SetArrayField(TEXT("meshes"),Rows);O->SetNumberField(TEXT("source_triangles"),ConnectorTriangleCount);O->SetBoolField(TEXT("asset_save_or_actor_spawn"),false);O->SetBoolField(TEXT("reader_explicit_build_cook_compile_flush_wait"),false);O->SetBoolField(TEXT("full_walk_camera_rails_or_final_render_qualified"),false);return ConnectorJson(O);
}
}

FString ULivingTownConnectorCollision::BuildConnectorCollidersPreview()
{
    FString Why;if(!ConnectorContext(true,Why))return ConnectorError(Why);TArray<FConnectorMeshSource> Meshes;if(!ConnectorSource(Meshes,Why))return ConnectorError(Why);
    for(const FConnectorMeshSource& S:Meshes)if(FindPackage(nullptr,*ConnectorPackage(S))||FPackageName::DoesPackageExist(ConnectorPackage(S)))return ConnectorError(TEXT("all29_new_asset_packages_must_be_absent_no_overwrite"));
    TArray<FConnectorMeshSource> Again;if(!ConnectorSource(Again,Why))return ConnectorError(Why);ConnectorApplied=true;
    for(const FConnectorMeshSource& S:Meshes)
    {
        UPackage* P=CreatePackage(*ConnectorPackage(S));UStaticMesh* M=NewObject<UStaticMesh>(P,FName(*S.Name),RF_Public|RF_Standalone);if(!M)return ConnectorError(TEXT("new_static_mesh_failed_partial_state_retained"));M->bAllowCPUAccess=true;M->bSupportRayTracing=false;M->GetNaniteSettings().bEnabled=false;M->GetStaticMaterials().Add(FStaticMaterial(UMaterial::GetDefaultMaterial(MD_Surface),FName(TEXT("CollisionPreview"))));
        FMeshDescription D;FStaticMeshAttributes A(D);A.Register();auto Pos=A.GetVertexPositions();auto Norm=A.GetVertexInstanceNormals();auto Tang=A.GetVertexInstanceTangents();auto Sign=A.GetVertexInstanceBinormalSigns();auto UV=A.GetVertexInstanceUVs();auto Color=A.GetVertexInstanceColors();UV.SetNumChannels(1);const FPolygonGroupID Group=D.CreatePolygonGroup();A.GetPolygonGroupMaterialSlotNames()[Group]=FName(TEXT("CollisionPreview"));
        for(const FVector3f& V:S.Positions){const FVertexID Id=D.CreateVertex();Pos[Id]=V;}
        for(const FIntVector& T:S.Triangles)
        {
            const int32 Values[3]={T.X,T.Y,T.Z};const FVector3f P0=S.Positions[T.X],U=(S.Positions[T.Y]-P0).GetSafeNormal(),N=FVector3f::CrossProduct(S.Positions[T.Y]-P0,S.Positions[T.Z]-P0).GetSafeNormal(),V=FVector3f::CrossProduct(N,U);TArray<FVertexInstanceID> Corners;
            for(int32 K=0;K<3;++K){const FVertexInstanceID Id=D.CreateVertexInstance(FVertexID(Values[K]));Corners.Add(Id);Norm[Id]=N;Tang[Id]=U;Sign[Id]=1.f;const FVector3f Delta=S.Positions[Values[K]]-P0;UV.Set(Id,0,FVector2f(FVector3f::DotProduct(Delta,U)/100.f,FVector3f::DotProduct(Delta,V)/100.f));Color[Id]=FVector4f(1,1,1,1);}D.CreateTriangle(Group,Corners);
        }
        UStaticMesh::FBuildMeshDescriptionsParams Params;Params.bFastBuild=true;Params.bBuildSimpleCollision=false;Params.bCommitMeshDescription=true;Params.bAllowCpuAccess=true;Params.bUseHashAsGuid=true;Params.PerLODOverrides.AddDefaulted();Params.PerLODOverrides[0].bUseHighPrecisionTangentBasis=true;Params.PerLODOverrides[0].bUseFullPrecisionUVs=true;
        if(!M->BuildFromMeshDescriptions(TArray<const FMeshDescription*>{&D},Params))return ConnectorError(TEXT("native_MeshDescription_build_failed_partial_state_retained"));
        M->CreateBodySetup();UBodySetup* B=M->GetBodySetup();if(!B)return ConnectorError(TEXT("BodySetup_required_partial_state_retained"));B->AggGeom.EmptyElements();B->CollisionTraceFlag=CTF_UseComplexAsSimple;B->bDoubleSidedGeometry=false;B->bNeverNeedsCookedCollisionData=false;B->bSupportFaceRemapOnMeshBVH=true;B->DefaultInstance.SetCollisionProfileName(FName(TEXT("BlockAll")));B->DefaultInstance.SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);B->DefaultInstance.bSimulatePhysics=false;B->InvalidatePhysicsData();B->CreatePhysicsMeshes();FAssetRegistryModule::AssetCreated(M);M->MarkPackageDirty();
    }
    TArray<FConnectorMeshSource> After;if(!ConnectorSource(After,Why))return ConnectorError(TEXT("source_changed_after_build_partial_state_retained"));return ConnectorRead(Meshes);
}
FString ULivingTownConnectorCollision::ReadConnectorCollidersPreview()
{
    FString Why;if(!ConnectorContext(false,Why))return ConnectorError(Why);TArray<FConnectorMeshSource> Meshes;if(!ConnectorSource(Meshes,Why))return ConnectorError(Why);const FString Reply=ConnectorRead(Meshes);TArray<FConnectorMeshSource> After;if(!ConnectorSource(After,Why))return ConnectorError(TEXT("source_changed_during_read"));return Reply;
}
