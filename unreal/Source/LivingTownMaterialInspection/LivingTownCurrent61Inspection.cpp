#include "LivingTownCurrent61Inspection.h"
#include "LivingTownTileData.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/SkeletalMeshSourceModel.h"
#include "Animation/Skeleton.h"
#include "Materials/MaterialInterface.h"
#include "Animation/MorphTarget.h"
#include "EditorFramework/AssetImportData.h"
#include "MeshDescription.h"
#include "MeshDescriptionBase.h"
#include "SkeletalMeshAttributes.h"
#include "Rendering/SkeletalMeshModel.h"
#include "Rendering/SkeletalMeshLODModel.h"
#include "Rendering/SkeletalMeshRenderData.h"
#include "Rendering/SkeletalMeshLODRenderData.h"
#include "Rendering/SkinWeightVertexBuffer.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformMisc.h"
#include "UObject/Package.h"
#include "UObject/StrongObjectPtr.h"
#include "UObject/UnrealType.h"
#include <type_traits>
#if PLATFORM_WINDOWS
#include "Windows/WindowsHWrapper.h"
#endif

namespace Current61
{
constexpr uint64 FileCap=96ull<<20,TotalCap=384ull<<20,JsonCap=1ull<<20;
constexpr uint32 MaxV=250000,MaxT=100000,MaxUV=8,MaxBones=64,MaxSections=32,MaxMorph=16,MaxDelta=2500000;
constexpr ANSICHAR Magic[]="LTC61RESTBIN0001";
static_assert(sizeof(Magic)==17,"16 byte magic");
static_assert(sizeof(float)==4&&sizeof(double)==8&&sizeof(uint16)==2&&sizeof(uint32)==4,"protocol native scalar types");
constexpr const TCHAR* Prefix=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/");
enum EScalar:uint32{U8=1,U16=2,U32=3,I32=4,U64=5,F32=6,F64=7};
uint32 Size(uint32 S){return S==U8?1:S==U16?2:(S==U32||S==I32||S==F32)?4:(S==U64||S==F64)?8:0;}
FString Json(const TSharedRef<FJsonObject>& O){FString T;FJsonSerializer::Serialize(O,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&T));FTCHARToUTF8 U(*T);return uint64(U.Length())<=JsonCap?T:TEXT("{\"status\":\"REFUSED\",\"reason\":\"JSON_1MiB\"}");}
FString Reply(const TCHAR* Status,const FString& Reason){auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),Status);O->SetStringField(TEXT("reason"),Reason);O->SetBoolField(TEXT("source_or_runtime_parity_qualified"),false);return Json(O);}
bool Fail(FString& E,const TCHAR* Why){E=Why;return false;}
bool Count(int64 N,uint64 C){return N>=0&&uint64(N)<=C;}
bool Leaf(const FString& N){if(N.IsEmpty()||N.Len()>64)return false;for(TCHAR X:N)if(!((X>='a'&&X<='z')||(X>='A'&&X<='Z')||(X>='0'&&X<='9')||X=='_'))return false;return true;}
bool NoReparse(const FString& Absolute)
{
#if PLATFORM_WINDOWS
    FString N=Absolute.Replace(TEXT("/"),TEXT("\\"));if(N.Len()<3||N[1]!=':'||N[2]!='\\')return false;
    FString P=N.Left(3);TArray<FString> Parts;N.Mid(3).ParseIntoArray(Parts,TEXT("\\"),true);
    auto Check=[](const FString& X){DWORD A=GetFileAttributesW(*X);return A!=INVALID_FILE_ATTRIBUTES&&!(A&FILE_ATTRIBUTE_REPARSE_POINT);};
    if(!Check(P))return false;for(const FString& X:Parts){if(X==TEXT(".")||X==TEXT(".."))return false;P=FPaths::Combine(P,X);if(!Check(P))return false;}return true;
#else
    return false;
#endif
}
bool Digest(const FString& P,uint64 Cap,FString& H,int64& N){N=IFileManager::Get().FileSize(*P);if(N<0||uint64(N)>Cap||!NoReparse(P))return false;TArray<uint8> B;if(!FFileHelper::LoadFileToArray(B,*P)||B.Num()!=N)return false;return LivingTownTiles::HashBytes(B,H)&&IFileManager::Get().FileSize(*P)==N;}
TArray<TSharedPtr<FJsonValue>> Names(const TArray<FName>& A){TArray<TSharedPtr<FJsonValue>> R;for(FName N:A)R.Add(MakeShared<FJsonValueString>(N.ToString()));return R;}
template<typename A> TArray<TSharedPtr<FJsonValue>> Numbers(const A& V){TArray<TSharedPtr<FJsonValue>> R;for(auto X:V)R.Add(MakeShared<FJsonValueNumber>(double(X)));return R;}
TSharedRef<FJsonObject> Properties(const UStruct* Type,const void* Data,UObject* Owner)
{
    auto O=MakeShared<FJsonObject>();int32 N=0;TArray<TSharedPtr<FJsonValue>> NotScalar;
    for(TFieldIterator<FProperty> It(Type);It;++It){const FProperty* P=*It;if(++N>256){O->SetBoolField(TEXT("HOLD_property_count_bound"),true);break;}const FStructProperty* SP=CastField<FStructProperty>(P);const FString ST=SP?SP->Struct->GetName():TEXT("");const bool Vector=SP&&(ST==TEXT("Vector")||ST==TEXT("Rotator")||ST==TEXT("Transform")||ST==TEXT("Vector3f")||ST==TEXT("Rotator3f"));const bool Scalar=CastField<FBoolProperty>(P)||CastField<FNumericProperty>(P)||CastField<FEnumProperty>(P)||CastField<FNameProperty>(P)||CastField<FStrProperty>(P);if(!Scalar&&!Vector){NotScalar.Add(MakeShared<FJsonValueString>(P->GetName()));continue;}if(const FStrProperty* String=CastField<FStrProperty>(P)){if(String->GetPropertyValue_InContainer(Data).Len()>8192){O->SetBoolField(TEXT("HOLD_property_text_bound"),true);continue;}}FString V;P->ExportText_InContainer(0,V,Data,Data,Owner,PPF_None);if(V.Len()>8192){O->SetBoolField(TEXT("HOLD_property_text_bound"),true);continue;}auto Row=MakeShared<FJsonObject>();Row->SetStringField(TEXT("native_property_type"),P->GetClass()->GetName());Row->SetStringField(TEXT("native_CPP_type"),P->GetCPPType());Row->SetStringField(TEXT("value_export_text_diagnostic_not_bit_encoding"),V);O->SetObjectField(P->GetName(),Row);}O->SetArrayField(TEXT("non_scalar_unobserved_properties"),NotScalar);return O;
}
class FWriter
{
    TUniquePtr<FArchive> File;TArray<uint8> Buffer;uint64 Written=0;bool Good=false;
    void Flush(){if(File&&Buffer.Num()){File->Serialize(Buffer.GetData(),Buffer.Num());Good&=!File->IsError();Buffer.Reset();}}
public:
    explicit FWriter(const FString& P){File.Reset(IFileManager::Get().CreateFileWriter(*P,FILEWRITE_NoReplaceExisting));Buffer.Reserve(65536);Good=File.IsValid();}
    void Byte(uint8 V){if(!Good||Written>=FileCap){Good=false;return;}Buffer.Add(V);++Written;if(Buffer.Num()>=65536)Flush();}
    void Int(uint64 V,uint32 Bytes){for(uint32 I=0;I<Bytes;++I)Byte(uint8(V>>(8*I)));}
    void Float(double V,uint32 Bytes){if(!FMath::IsFinite(V)){Good=false;return;}if(Bytes==4){float F=float(V);if(!FMath::IsFinite(F)){Good=false;return;}uint32 B;FMemory::Memcpy(&B,&F,4);Int(B,4);}else{uint64 B;FMemory::Memcpy(&B,&V,8);Int(B,8);}}
    template<typename V>void Vec(const V& X,uint32 Width,uint32 Bytes=4){for(uint32 I=0;I<Width;++I)Float(double(X[int32(I)]),Bytes);}
    void Quat(const FQuat& Q){Float(Q.X,8);Float(Q.Y,8);Float(Q.Z,8);Float(Q.W,8);}
    void Raw(const void* Data,uint64 Bytes){if(!Data&&Bytes){Good=false;return;}const uint8* P=static_cast<const uint8*>(Data);for(uint64 I=0;I<Bytes;++I)Byte(P[I]);}
    uint64 Tell()const{return Written;}bool Finish(){Flush();if(!File)return false;bool Closed=File->Close();Good&=Closed&&!File->IsError();File.Reset();return Good;}
};
struct FEntry{uint32 Kind=0,Domain=0,Scalar=0,Width=0;uint64 N=0,Offset=0,Bytes=0;TFunction<void(FWriter&)> Emit;};
struct FPacket
{
    FString Name;TArray<FEntry> E;uint64 Bytes=0;
    bool Add(uint32 K,uint32 D,uint32 S,uint32 W,uint64 N,TFunction<void(FWriter&)> Emit){uint32 Z=Size(S);if(!Z||!W||W>64||N>uint64(MaxDelta)*12||N>FileCap/(uint64(W)*Z)||E.Num()>=96)return false;for(const auto& X:E)if(X.Kind==K&&X.Domain==D)return false;FEntry X;X.Kind=K;X.Domain=D;X.Scalar=S;X.Width=W;X.N=N;X.Bytes=N*W*Z;X.Emit=MoveTemp(Emit);E.Add(MoveTemp(X));return true;}
    bool Layout(){uint64 O=32+uint64(E.Num())*48;for(auto& X:E){O=(O+7)&~7ull;X.Offset=O;if(X.Bytes>FileCap-O)return false;O+=X.Bytes;}Bytes=O;return Bytes<=FileCap;}
    bool Write(const FString& Directory){FWriter W(FPaths::Combine(Directory,Name));for(int32 I=0;I<16;++I)W.Byte(uint8(Magic[I]));W.Int(1,4);W.Int(E.Num(),4);W.Int(Bytes,8);for(const auto& X:E){for(uint32 V:{X.Kind,X.Domain,X.Scalar,X.Width})W.Int(V,4);for(uint64 V:{X.N,X.Offset,X.Bytes,0ull})W.Int(V,8);}for(const auto& X:E){while(W.Tell()<X.Offset)W.Byte(0);if(W.Tell()!=X.Offset)return false;X.Emit(W);if(W.Tell()!=X.Offset+X.Bytes)return false;}return W.Finish()&&W.Tell()==Bytes;}
};
struct FState
{
    TStrongObjectPtr<USkeletalMesh> Mesh;const FMeshDescription* MD=nullptr;const FSkeletalMeshLODModel* Model=nullptr;const FSkeletalMeshLODRenderData* Render=nullptr;const USkeletalMeshDescriptionBulkData* Bulk=nullptr;
    TSharedRef<FJsonObject> Meta=MakeShared<FJsonObject>();TArray<FPacket> Packets;FString Package,Hash;int64 PackageBytes=0;uint64 Total=0,MorphVectors=0;bool Dirty=false;
};
bool Preflight(FState& S,FString& E)
{
    USkeletalMesh* M=S.Mesh.Get();if(M->IsCompiling())return Fail(E,TEXT("HOLD_asset_compiling_no_wait"));
    if(M->GetLODNum()!=1||M->GetNumSourceModels()!=1||M->GetRefSkeleton().GetNum()<61||!Count(M->GetRefSkeleton().GetNum(),MaxBones)||!M->GetSkeleton()||!Count(M->GetMaterials().Num(),MaxSections))return Fail(E,TEXT("LOD0_bone_material_bounds"));
    const auto* Imported=M->GetImportedModel();const auto* Render=M->GetResourceForRendering();if(!Imported||Imported->LODModels.Num()!=1||!Render||Render->LODRenderData.Num()!=1)return Fail(E,TEXT("HOLD_imported_or_render_model_missing"));
    S.Model=&Imported->LODModels[0];S.Render=&Render->LODRenderData[0];const auto& I=*S.Model;const auto& L=*S.Render;
    if(!I.NumVertices||!Count(I.NumVertices,MaxV)||!I.IndexBuffer.Num()||!Count(I.IndexBuffer.Num(),uint64(MaxT)*3)||I.IndexBuffer.Num()%3||!Count(I.Sections.Num(),MaxSections)||!I.NumTexCoords||!Count(I.NumTexCoords,MaxUV)||I.NumTexCoords>sizeof(((FSoftSkinVertex*)nullptr)->UVs)/sizeof(FVector2f)||!L.GetNumVertices()||!Count(L.GetNumVertices(),MaxV)||!Count(L.RenderSections.Num(),MaxSections))return Fail(E,TEXT("imported_render_preallocation_bounds"));
    if(!L.MultiSizeIndexContainer.IsIndexBufferValid())return Fail(E,TEXT("HOLD_index_buffer_missing"));const auto* Index=L.MultiSizeIndexContainer.GetIndexBuffer();
    if(!Index->GetNeedsCPUAccess()||!Index->Num()||!Count(Index->Num(),uint64(MaxT)*3)||Index->Num()%3||!L.StaticVertexBuffers.PositionVertexBuffer.GetVertexData()||!L.StaticVertexBuffers.StaticMeshVertexBuffer.GetTangentData()||!L.StaticVertexBuffers.StaticMeshVertexBuffer.GetTexCoordData()||!L.StaticVertexBuffers.StaticMeshVertexBuffer.GetNumTexCoords()||!Count(L.StaticVertexBuffers.StaticMeshVertexBuffer.GetNumTexCoords(),MaxUV))return Fail(E,TEXT("HOLD_render_CPU_buffers_or_bounds"));
    const auto* Skin=L.GetSkinWeightVertexBuffer();if(!Skin||Skin->GetNumVertices()!=L.GetNumVertices()||Skin->GetMaxBoneInfluences()>MAX_TOTAL_INFLUENCES||(!Skin->GetDataVertexBuffer()->GetWeightData()||!Skin->GetDataVertexBuffer()->GetVertexDataSize())||!Count(Skin->GetVertexDataSize(),FileCap))return Fail(E,TEXT("HOLD_skin_CPU_buffers_or_bounds"));
    const FSkeletalMeshSourceModel& Source=M->GetSourceModel(0);if(!Source.IsInitialized())return Fail(E,TEXT("HOLD_source_model_uninitialized"));
    const FObjectPropertyBase* Property=FindFProperty<FObjectPropertyBase>(FSkeletalMeshSourceModel::StaticStruct(),TEXT("MeshDescriptionBulkData"));if(!Property)return Fail(E,TEXT("HOLD_bound_source_cache_property_missing"));S.Bulk=Cast<USkeletalMeshDescriptionBulkData>(Property->GetObjectPropertyValue_InContainer(&Source));
    if(!S.Bulk||!S.Bulk->HasCachedMeshDescription())return Fail(E,TEXT("HOLD_source_MD_not_cached_no_load_or_bone_update"));const auto* Wrapper=S.Bulk->GetMeshDescription();if(!Wrapper)return Fail(E,TEXT("HOLD_cached_wrapper_missing"));S.MD=&Wrapper->GetMeshDescription();const auto& D=*S.MD;
    if(!D.Vertices().Num()||!Count(D.Vertices().GetArraySize(),MaxV)||!Count(D.VertexInstances().GetArraySize(),MaxV)||!Count(D.Triangles().GetArraySize(),MaxT)||!Count(D.Polygons().GetArraySize(),MaxT)||!Count(D.Edges().GetArraySize(),uint64(MaxT)*3)||!Count(D.PolygonGroups().GetArraySize(),MaxSections))return Fail(E,TEXT("source_MD_preallocation_bounds"));
    const FSkeletalMeshConstAttributes A(D);if(!A.HasSourceGeometryParts()||A.GetNumSourceGeometryParts()!=7||!A.HasBoneNameAttribute()||!A.HasBoneParentIndexAttribute()||!A.HasBonePoseAttribute()||!Count(A.GetNumBones(),MaxBones)||A.GetNumBones()<61||!A.GetVertexSkinWeights().IsValid()||!Count(A.GetVertexInstanceUVs().GetNumChannels(),MaxUV)||A.GetMorphTargetNames().Num()>int32(MaxMorph)||A.GetSkinWeightProfileNames().Num()!=1)return Fail(E,TEXT("required_seven_sourceparts_bone_skin_UV_morph_profile_domains"));
    if(I.MeshToImportVertexMap.Num()!=int32(I.NumVertices)||I.GetRawPointIndices().Num()!=int32(I.NumVertices))return Fail(E,TEXT("HOLD_imported_vertex_maps_missing"));
    uint64 SumV=0,SumT=0;for(const auto& X:I.Sections){if(X.NumVertices!=X.SoftVertices.Num()||!Count(X.NumVertices,MaxV)||!Count(X.BoneMap.Num(),MaxBones)||uint64(X.BaseVertexIndex)+uint64(X.NumVertices)>I.NumVertices||uint64(X.BaseIndex)+uint64(X.NumTriangles)*3>uint64(I.IndexBuffer.Num()))return Fail(E,TEXT("imported_section_bounds"));SumV+=X.NumVertices;SumT+=X.NumTriangles;}if(SumV!=I.NumVertices||SumT*3!=uint64(I.IndexBuffer.Num()))return Fail(E,TEXT("imported_section_coverage"));
    SumV=SumT=0;for(const auto& X:L.RenderSections){if(!Count(X.BoneMap.Num(),MaxBones)||uint64(X.BaseVertexIndex)+X.NumVertices>L.GetNumVertices()||uint64(X.BaseIndex)+uint64(X.NumTriangles)*3>uint64(Index->Num()))return Fail(E,TEXT("render_section_bounds"));SumV+=X.NumVertices;SumT+=X.NumTriangles;}if(SumV!=L.GetNumVertices()||SumT*3!=uint64(Index->Num()))return Fail(E,TEXT("render_section_coverage"));
    const auto& Morphs=M->GetMorphTargets();if(!Count(Morphs.Num(),MaxMorph))return Fail(E,TEXT("morph_count"));uint64 Deltas=0;for(const UMorphTarget* T:Morphs){if(!T||T->GetMorphLODModels().Num()!=1)return Fail(E,TEXT("morph_LOD0_missing"));Deltas+=T->GetMorphTargetDeltas(0).Num();if(Deltas>MaxDelta)return Fail(E,TEXT("morph_delta_bound"));}
    S.Meta->SetNumberField(TEXT("native_raw_MD_vertices"),D.Vertices().Num());S.Meta->SetNumberField(TEXT("native_MD_vertex_instances"),D.VertexInstances().Num());S.Meta->SetNumberField(TEXT("native_MD_triangles"),D.Triangles().Num());S.Meta->SetNumberField(TEXT("imported_vertices"),I.NumVertices);S.Meta->SetNumberField(TEXT("render_vertices"),L.GetNumVertices());S.Meta->SetBoolField(TEXT("source_cache_loaded_or_bones_updated_by_observer"),false);return true;
}
bool MeshDescriptionPacket(FState& S,FString& Error)
{
    const auto& D=*S.MD;const FSkeletalMeshConstAttributes A(D);auto Pos=A.GetVertexPositions();auto N=A.GetVertexInstanceNormals();auto T=A.GetVertexInstanceTangents();auto Sign=A.GetVertexInstanceBinormalSigns();auto Color=A.GetVertexInstanceColors();auto UV=A.GetVertexInstanceUVs();auto Weights=A.GetVertexSkinWeights();
    if(!Pos.IsValid()||!N.IsValid()||!T.IsValid()||!Sign.IsValid()||!Color.IsValid()||!UV.IsValid())return Fail(Error,TEXT("HOLD_MD_standard_attributes_missing"));
    FPacket P;P.Name=TEXT("MeshDescription.bin");
#define ADD(K,Domain,Scalar,Width,Rows,...) if(!P.Add(K,Domain,Scalar,Width,Rows,__VA_ARGS__))return Fail(Error,TEXT("MD_entry_bound"))
    ADD(1,0,I32,1,D.Vertices().Num(),[&D](FWriter& W){for(auto ID:D.Vertices().GetElementIDs())W.Int(uint32(ID.GetValue()),4);});
    ADD(2,0,F32,3,D.Vertices().Num(),[&D,Pos](FWriter& W){for(auto ID:D.Vertices().GetElementIDs())W.Vec(Pos[ID],3);});
    ADD(3,0,I32,1,D.VertexInstances().Num(),[&D](FWriter& W){for(auto ID:D.VertexInstances().GetElementIDs())W.Int(uint32(ID.GetValue()),4);});
    ADD(4,0,I32,1,D.VertexInstances().Num(),[&D](FWriter& W){for(auto ID:D.VertexInstances().GetElementIDs())W.Int(uint32(D.GetVertexInstanceVertex(ID).GetValue()),4);});
    ADD(5,0,F32,3,D.VertexInstances().Num(),[&D,N](FWriter& W){for(auto ID:D.VertexInstances().GetElementIDs())W.Vec(N[ID],3);});
    ADD(6,0,F32,3,D.VertexInstances().Num(),[&D,T](FWriter& W){for(auto ID:D.VertexInstances().GetElementIDs())W.Vec(T[ID],3);});
    ADD(7,0,F32,1,D.VertexInstances().Num(),[&D,Sign](FWriter& W){for(auto ID:D.VertexInstances().GetElementIDs())W.Float(Sign[ID],4);});
    ADD(8,0,F32,4,D.VertexInstances().Num(),[&D,Color](FWriter& W){for(auto ID:D.VertexInstances().GetElementIDs())W.Vec(Color[ID],4);});
    for(int32 U=0;U<UV.GetNumChannels();++U){ADD(9,uint32(U),F32,2,D.VertexInstances().Num(),[&D,UV,U](FWriter& W){for(auto ID:D.VertexInstances().GetElementIDs())W.Vec(UV.Get(ID,U),2);});}
    ADD(10,0,I32,6,D.Triangles().Num(),[&D](FWriter& W){for(auto ID:D.Triangles().GetElementIDs()){W.Int(uint32(ID.GetValue()),4);W.Int(uint32(D.GetTrianglePolygon(ID).GetValue()),4);W.Int(uint32(D.GetTrianglePolygonGroup(ID).GetValue()),4);for(auto V:D.GetTriangleVertexInstances(ID))W.Int(uint32(V.GetValue()),4);}});
    ADD(11,0,I32,3,D.Edges().Num(),[&D](FWriter& W){for(auto ID:D.Edges().GetElementIDs()){W.Int(uint32(ID.GetValue()),4);for(auto V:D.GetEdgeVertices(ID))W.Int(uint32(V.GetValue()),4);}});
    ADD(12,0,I32,2,D.Polygons().Num(),[&D](FWriter& W){for(auto ID:D.Polygons().GetElementIDs()){W.Int(uint32(ID.GetValue()),4);W.Int(uint32(D.GetPolygonPolygonGroup(ID).GetValue()),4);}});
    uint64 PolyCorners=0,Influences=0;for(auto ID:D.Polygons().GetElementIDs()){PolyCorners+=D.GetPolygonVertexInstances(ID).Num();if(PolyCorners>uint64(MaxT)*3)return Fail(Error,TEXT("MD_polygon_corner_bound"));}for(auto ID:D.Vertices().GetElementIDs()){auto V=Weights.Get(ID);if(V.Num()>MAX_TOTAL_INFLUENCES)return Fail(Error,TEXT("MD_influence_pervertex_bound"));Influences+=V.Num();}
    ADD(13,0,I32,2,PolyCorners,[&D](FWriter& W){for(auto ID:D.Polygons().GetElementIDs())for(auto V:D.GetPolygonVertexInstances(ID)){W.Int(uint32(ID.GetValue()),4);W.Int(uint32(V.GetValue()),4);}});
    ADD(14,0,I32,1,D.PolygonGroups().Num(),[&D](FWriter& W){for(auto ID:D.PolygonGroups().GetElementIDs())W.Int(uint32(ID.GetValue()),4);});
    auto PartName=A.GetSourceGeometryPartNames();auto PartRange=A.GetSourceGeometryPartVertexOffsetAndCounts();TArray<TSharedPtr<FJsonValue>> Parts;
    for(auto ID:A.SourceGeometryParts().GetElementIDs()){auto V=PartRange.Get(ID);if(V.Num()!=2||V[0]<0||V[1]<0||uint64(V[0])+uint64(V[1])>MaxV||PartName.Get(ID).ToString().Len()>256)return Fail(Error,TEXT("source_part_range_or_name"));auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("ID"),ID.GetValue());O->SetStringField(TEXT("name"),PartName.Get(ID).ToString());O->SetNumberField(TEXT("vertex_offset"),V[0]);O->SetNumberField(TEXT("vertex_count"),V[1]);Parts.Add(MakeShared<FJsonValueObject>(O));}S.Meta->SetArrayField(TEXT("source_geometry_parts"),Parts);
    ADD(15,0,I32,3,A.GetNumSourceGeometryParts(),[A,PartRange](FWriter& W){for(auto ID:A.SourceGeometryParts().GetElementIDs()){auto V=PartRange.Get(ID);W.Int(uint32(ID.GetValue()),4);W.Int(uint32(V[0]),4);W.Int(uint32(V[1]),4);}});
    ADD(16,0,I32,2,Influences,[&D,Weights](FWriter& W){for(auto ID:D.Vertices().GetElementIDs())for(auto B:Weights.Get(ID)){W.Int(uint32(ID.GetValue()),4);W.Int(uint32(B.ToInt32()),4);}});
    ADD(17,0,U16,2,Influences,[&D,Weights](FWriter& W){for(auto ID:D.Vertices().GetElementIDs())for(auto B:Weights.Get(ID)){W.Int(B.GetBoneIndex(),2);W.Int(B.GetRawWeight(),2);}});
    auto BoneNames=A.GetBoneNames();auto BoneParents=A.GetBoneParentIndices();auto BonePoses=A.GetBonePoses();TArray<TSharedPtr<FJsonValue>> Bones;
    for(auto ID:A.Bones().GetElementIDs()){auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("ID"),ID.GetValue());O->SetStringField(TEXT("name"),BoneNames.Get(ID).ToString());O->SetNumberField(TEXT("parent"),BoneParents.Get(ID));Bones.Add(MakeShared<FJsonValueObject>(O));}S.Meta->SetArrayField(TEXT("MD_bones"),Bones);
    ADD(18,0,I32,2,A.GetNumBones(),[A,BoneParents](FWriter& W){for(auto ID:A.Bones().GetElementIDs()){W.Int(uint32(ID.GetValue()),4);W.Int(uint32(BoneParents.Get(ID)),4);}});
    ADD(19,0,F64,10,A.GetNumBones(),[A,BonePoses](FWriter& W){for(auto ID:A.Bones().GetElementIDs()){const auto B=BonePoses.Get(ID);W.Vec(B.GetTranslation(),3,8);W.Quat(B.GetRotation());W.Vec(B.GetScale3D(),3,8);}});
    auto Morphs=A.GetMorphTargetNames();S.Meta->SetArrayField(TEXT("MD_morph_names"),Names(Morphs));uint64 DeltaN=0;
    for(int32 J=0;J<Morphs.Num();++J){auto MP=A.GetVertexMorphPositionDelta(Morphs[J]);if(!MP.IsValid())return Fail(Error,TEXT("MD_morph_P_missing"));DeltaN+=D.Vertices().Num();if(DeltaN>MaxDelta)return Fail(Error,TEXT("MD_morph_vector_bound"));ADD(20,uint32(J),F32,3,D.Vertices().Num(),[&D,MP](FWriter& W){for(auto ID:D.Vertices().GetElementIDs())W.Vec(MP.Get(ID),3);});auto MN=A.GetVertexInstanceMorphNormalDelta(Morphs[J]);if(MN.IsValid()){DeltaN+=D.VertexInstances().Num();if(DeltaN>MaxDelta)return Fail(Error,TEXT("MD_morph_vector_bound"));ADD(21,uint32(J),F32,3,D.VertexInstances().Num(),[&D,MN](FWriter& W){for(auto ID:D.VertexInstances().GetElementIDs())W.Vec(MN.Get(ID),3);});}}
    TArray<TSharedPtr<FJsonValue>> Groups;auto Slot=A.GetPolygonGroupMaterialSlotNames();for(auto ID:D.PolygonGroups().GetElementIDs()){auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("ID"),ID.GetValue());O->SetStringField(TEXT("imported_slot_name"),Slot.Get(ID).ToString());Groups.Add(MakeShared<FJsonValueObject>(O));}S.Meta->SetArrayField(TEXT("MD_polygon_groups"),Groups);S.Meta->SetStringField(TEXT("MD_skin_encoding"),TEXT("actual FBoneWeight packed int32 via lossless FromInt32/ToInt32 view, decoded uint16 index/rawweight; no float normalization"));S.Meta->SetNumberField(TEXT("MD_UV_channels"),UV.GetNumChannels());S.Meta->SetNumberField(TEXT("MD_morph_vector_records"),double(DeltaN));
#undef ADD
    S.MorphVectors=DeltaN;S.Packets.Add(MoveTemp(P));return true;
}
template<typename Section> TSharedRef<FJsonObject> SectionJson(const Section& X)
{
    auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("material_index"),X.MaterialIndex);O->SetNumberField(TEXT("base_index"),X.BaseIndex);O->SetNumberField(TEXT("triangles"),X.NumTriangles);O->SetNumberField(TEXT("base_vertex"),X.BaseVertexIndex);O->SetNumberField(TEXT("vertices"),X.NumVertices);O->SetNumberField(TEXT("max_influences"),X.MaxBoneInfluences);O->SetArrayField(TEXT("bone_map"),Numbers(X.BoneMap));O->SetBoolField(TEXT("disabled"),X.bDisabled);O->SetBoolField(TEXT("recompute_tangent"),X.bRecomputeTangent);O->SetBoolField(TEXT("cast_shadow"),X.bCastShadow);O->SetBoolField(TEXT("visible_raytracing"),X.bVisibleInRayTracing);return O;
}
bool ImportedPacket(FState& S,FString& Error)
{
    const auto& I=*S.Model;FPacket P;P.Name=TEXT("ImportedLOD.bin");uint64 V=0;for(const auto& X:I.Sections)V+=X.SoftVertices.Num();
#define ADD(K,Domain,Scalar,Width,Rows,...) if(!P.Add(K,Domain,Scalar,Width,Rows,__VA_ARGS__))return Fail(Error,TEXT("imported_entry_bound"))
    ADD(30,0,F32,3,V,[&I](FWriter& W){for(const auto& X:I.Sections)for(const auto& V:X.SoftVertices)W.Vec(V.Position,3);});
    ADD(31,0,F32,3,V,[&I](FWriter& W){for(const auto& X:I.Sections)for(const auto& V:X.SoftVertices)W.Vec(V.TangentX,3);});
    ADD(32,0,F32,3,V,[&I](FWriter& W){for(const auto& X:I.Sections)for(const auto& V:X.SoftVertices)W.Vec(V.TangentY,3);});
    ADD(33,0,F32,4,V,[&I](FWriter& W){for(const auto& X:I.Sections)for(const auto& V:X.SoftVertices)W.Vec(V.TangentZ,4);});
    for(uint32 U=0;U<I.NumTexCoords;++U){ADD(34,U,F32,2,V,[&I,U](FWriter& W){for(const auto& X:I.Sections)for(const auto& V:X.SoftVertices)W.Vec(V.UVs[U],2);});}
    ADD(35,0,U8,4,V,[&I](FWriter& W){for(const auto& X:I.Sections)for(const auto& V:X.SoftVertices){W.Byte(V.Color.R);W.Byte(V.Color.G);W.Byte(V.Color.B);W.Byte(V.Color.A);}});
    ADD(36,0,U16,MAX_TOTAL_INFLUENCES,V,[&I](FWriter& W){for(const auto& X:I.Sections)for(const auto& V:X.SoftVertices)for(uint16 B:V.InfluenceBones)W.Int(B,2);});
    ADD(37,0,U16,MAX_TOTAL_INFLUENCES,V,[&I](FWriter& W){for(const auto& X:I.Sections)for(const auto& V:X.SoftVertices)for(uint16 B:V.InfluenceWeights)W.Int(B,2);});
    ADD(38,0,U32,1,I.IndexBuffer.Num(),[&I](FWriter& W){for(uint32 X:I.IndexBuffer)W.Int(X,4);});
    ADD(39,0,I32,1,I.MeshToImportVertexMap.Num(),[&I](FWriter& W){for(int32 X:I.MeshToImportVertexMap)W.Int(uint32(X),4);});
    ADD(40,0,U32,1,I.GetRawPointIndices().Num(),[&I](FWriter& W){for(uint32 X:I.GetRawPointIndices())W.Int(X,4);});
    ADD(42,0,U32,1,V,[&I](FWriter& W){for(const auto& X:I.Sections)for(int32 J=0;J<X.SoftVertices.Num();++J)W.Int(uint64(X.BaseVertexIndex)+uint32(J),4);});
    TArray<TSharedPtr<FJsonValue>> Sections;for(const auto& X:I.Sections){auto O=SectionJson(X);O->SetNumberField(TEXT("original_data_section_index"),X.OriginalDataSectionIndex);O->SetNumberField(TEXT("chunked_parent_section_index"),X.ChunkedParentSectionIndex);O->SetBoolField(TEXT("uses16bit_bone_index"),X.bUse16BitBoneIndex);Sections.Add(MakeShared<FJsonValueObject>(O));}S.Meta->SetArrayField(TEXT("imported_sections"),Sections);S.Meta->SetArrayField(TEXT("imported_active_bones"),Numbers(I.ActiveBoneIndices));S.Meta->SetArrayField(TEXT("imported_required_bones"),Numbers(I.RequiredBones));S.Meta->SetNumberField(TEXT("imported_num_UV"),I.NumTexCoords);S.Meta->SetStringField(TEXT("imported_vertex_array_order"),TEXT("native Sections iteration then SoftVertices; kind42 gives actual BaseVertexIndex+local ordinal; maps39/40 indexed by original importedLOD global vertex"));
#undef ADD
    S.Packets.Add(MoveTemp(P));return true;
}
bool RenderPacket(FState& S,FString& Error)
{
    const auto& L=*S.Render;const auto& B=L.StaticVertexBuffers;const auto& PVB=B.PositionVertexBuffer;const auto& SV=B.StaticMeshVertexBuffer;const auto& C=B.ColorVertexBuffer;const auto* Skin=L.GetSkinWeightVertexBuffer();const auto* Data=Skin->GetDataVertexBuffer();const auto* Lookup=Skin->GetLookupVertexBuffer();const auto* Indices=L.MultiSizeIndexContainer.GetIndexBuffer();const uint32 V=L.GetNumVertices(),NI=uint32(Indices->Num()),IndexBytes=L.MultiSizeIndexContainer.GetDataTypeSize();
    if((IndexBytes!=2&&IndexBytes!=4)||uint64(Indices->GetResourceDataSize())!=uint64(NI)*IndexBytes||(!C.GetVertexData()&&C.GetNumVertices())||(C.GetNumVertices()!=0&&C.GetNumVertices()!=V)||(!Lookup->GetLookupData()&&Lookup->GetVertexDataSize())||(Skin->GetVariableBonesPerVertex()&&(!Lookup->GetLookupData()||Lookup->GetNumVertices()!=V||uint64(Lookup->GetVertexDataSize())!=uint64(V)*sizeof(uint32)))||Data->GetBoneIndexByteSize()>2||Data->GetBoneWeightByteSize()>2)return Fail(Error,TEXT("HOLD_render_raw_buffer_layout"));
    FPacket P;P.Name=TEXT("RenderLOD.bin");
#define ADD(K,Domain,Scalar,Width,Rows,...) if(!P.Add(K,Domain,Scalar,Width,Rows,__VA_ARGS__))return Fail(Error,TEXT("render_entry_bound"))
    ADD(50,0,F32,3,V,[&PVB,V](FWriter& W){for(uint32 J=0;J<V;++J)W.Vec(PVB.VertexPosition(J),3);});
    ADD(51,0,F32,4,V,[&SV,V](FWriter& W){for(uint32 J=0;J<V;++J)W.Vec(SV.VertexTangentX(J),4);});
    ADD(52,0,F32,3,V,[&SV,V](FWriter& W){for(uint32 J=0;J<V;++J)W.Vec(SV.VertexTangentY(J),3);});
    ADD(53,0,F32,4,V,[&SV,V](FWriter& W){for(uint32 J=0;J<V;++J)W.Vec(SV.VertexTangentZ(J),4);});
    for(uint32 U=0;U<SV.GetNumTexCoords();++U){ADD(54,U,F32,2,V,[&SV,V,U](FWriter& W){for(uint32 J=0;J<V;++J)W.Vec(SV.GetVertexUV(J,U),2);});}
    if(C.GetNumVertices()){ADD(55,0,U8,4,V,[&C,V](FWriter& W){for(uint32 J=0;J<V;++J){const auto X=C.VertexColor(J);W.Byte(X.R);W.Byte(X.G);W.Byte(X.B);W.Byte(X.A);}});}
    ADD(56,0,IndexBytes==2?U16:U32,1,NI,[Indices,IndexBytes,NI](FWriter& W){for(uint32 J=0;J<NI;++J)W.Int(Indices->Get(J),IndexBytes);});
    ADD(57,0,U8,1,Data->GetVertexDataSize(),[Data](FWriter& W){W.Raw(Data->GetWeightData(),Data->GetVertexDataSize());});
    ADD(58,0,U8,1,Lookup->GetVertexDataSize(),[Lookup](FWriter& W){W.Raw(Lookup->GetLookupData(),Lookup->GetVertexDataSize());});
    for(uint32 J=0;J<V;++J){uint32 O=0,N=0;Skin->GetVertexInfluenceOffsetCount(J,O,N);if(N>MAX_TOTAL_INFLUENCES||uint64(O)+uint64(N)*Skin->GetBoneIndexAndWeightByteSize()>Data->GetVertexDataSize())return Fail(Error,TEXT("skin_lookup_range_or_influence_bound"));}
    ADD(59,0,U32,MAX_TOTAL_INFLUENCES,V,[Skin,V](FWriter& W){for(uint32 J=0;J<V;++J){uint32 O=0,N=0;Skin->GetVertexInfluenceOffsetCount(J,O,N);for(uint32 K=0;K<MAX_TOTAL_INFLUENCES;++K)W.Int(K<N?Skin->GetBoneIndex(J,K):0,4);}});
    ADD(60,0,U16,MAX_TOTAL_INFLUENCES,V,[Skin,V](FWriter& W){for(uint32 J=0;J<V;++J){uint32 O=0,N=0;Skin->GetVertexInfluenceOffsetCount(J,O,N);for(uint32 K=0;K<MAX_TOTAL_INFLUENCES;++K)W.Int(K<N?Skin->GetBoneWeight(J,K):0,2);}});
    ADD(61,0,U32,2,V,[Skin,V](FWriter& W){for(uint32 J=0;J<V;++J){uint32 O=0,N=0;Skin->GetVertexInfluenceOffsetCount(J,O,N);W.Int(O,4);W.Int(N,4);}});
    ADD(62,0,U8,1,uint64(PVB.GetStride())*V,[&PVB,V](FWriter& W){W.Raw(PVB.GetVertexData(),uint64(PVB.GetStride())*V);});
    ADD(63,0,U8,1,SV.GetTangentSize(),[&SV](FWriter& W){W.Raw(SV.GetTangentData(),SV.GetTangentSize());});
    ADD(64,0,U8,1,SV.GetTexCoordSize(),[&SV](FWriter& W){W.Raw(SV.GetTexCoordData(),SV.GetTexCoordSize());});
    ADD(65,0,U8,1,uint64(C.GetStride())*C.GetNumVertices(),[&C](FWriter& W){W.Raw(C.GetVertexData(),uint64(C.GetStride())*C.GetNumVertices());});
    TArray<TSharedPtr<FJsonValue>> Sections;for(const auto& X:L.RenderSections){auto O=SectionJson(X);O->SetBoolField(TEXT("unified_bone_map"),X.bUnifiedBoneMap);Sections.Add(MakeShared<FJsonValueObject>(O));}S.Meta->SetArrayField(TEXT("render_sections"),Sections);S.Meta->SetArrayField(TEXT("render_unified_bone_map"),Numbers(L.GetUnifiedBoneMap()));S.Meta->SetArrayField(TEXT("render_active_bones"),Numbers(L.ActiveBoneIndices));S.Meta->SetArrayField(TEXT("render_required_bones"),Numbers(L.RequiredBones));S.Meta->SetNumberField(TEXT("render_UV_channels"),SV.GetNumTexCoords());S.Meta->SetNumberField(TEXT("render_index_bytes"),IndexBytes);S.Meta->SetNumberField(TEXT("render_weight_bytes"),Skin->GetBoneWeightByteSize());S.Meta->SetNumberField(TEXT("render_bone_index_bytes"),Skin->GetBoneIndexByteSize());S.Meta->SetNumberField(TEXT("render_max_influences"),Skin->GetMaxBoneInfluences());S.Meta->SetBoolField(TEXT("render_variable_influences"),Skin->GetVariableBonesPerVertex());S.Meta->SetBoolField(TEXT("render_high_precision_TBN"),SV.GetUseHighPrecisionTangentBasis());S.Meta->SetBoolField(TEXT("render_full_precision_UV"),SV.GetUseFullPrecisionUVs());S.Meta->SetBoolField(TEXT("render_vertex_color_buffer_present"),C.GetNumVertices()!=0);S.Meta->SetNumberField(TEXT("native_skin_byte_storage_total"),Skin->GetVertexDataSize());S.Meta->SetStringField(TEXT("render_skin_decoded_padding"),TEXT("kinds59/60 zero-pad beyond actual per-vertex kind61 count; raw57/58 remains authoritative; no source weight normalization"));S.Meta->SetStringField(TEXT("render_index_encoding"),TEXT("native CPU values re-emitted in actual16/32-bit LE width; not a GPU texel read"));
#undef ADD
    S.Packets.Add(MoveTemp(P));return true;
}
bool SkeletonAndMorphPackets(FState& S,FString& Error)
{
    const auto* M=S.Mesh.Get();const auto& Ref=M->GetRefSkeleton();const auto& Local=Ref.GetRefBonePose();const auto& Raw=Ref.GetRawRefBonePose();const auto& Inv=M->GetRefBasesInvMatrix();if(Local.Num()!=Ref.GetNum()||Inv.Num()!=Ref.GetNum()||Raw.Num()!=Ref.GetRawBoneNum())return Fail(Error,TEXT("HOLD_refpose_inversebind_count"));
    TArray<FMatrix> Components;Components.SetNum(Local.Num());TArray<TSharedPtr<FJsonValue>> Bones;
    for(int32 J=0;J<Ref.GetNum();++J){int32 Parent=Ref.GetParentIndex(J);if(Parent<-1||Parent>=J)return Fail(Error,TEXT("ref_parent_order_or_cycle"));Components[J]=Local[J].ToMatrixWithScale();if(Parent>=0)Components[J]=Components[J]*Components[Parent];auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("index"),J);O->SetStringField(TEXT("name"),Ref.GetBoneName(J).ToString());O->SetNumberField(TEXT("parent"),Parent);Bones.Add(MakeShared<FJsonValueObject>(O));}
    FPacket P;P.Name=TEXT("Skeleton.bin");
#define ADD(K,Domain,Scalar,Width,Rows,...) if(!P.Add(K,Domain,Scalar,Width,Rows,__VA_ARGS__))return Fail(Error,TEXT("skeleton_entry_bound"))
    ADD(70,0,F64,10,Local.Num(),[&Local](FWriter& W){for(const auto& B:Local){W.Vec(B.GetTranslation(),3,8);W.Quat(B.GetRotation());W.Vec(B.GetScale3D(),3,8);}});
    ADD(71,0,F64,16,Local.Num(),[&Local](FWriter& W){for(const auto& B:Local){const auto A=B.ToMatrixWithScale();for(int32 J=0;J<4;++J)for(int32 K=0;K<4;++K)W.Float(A.M[J][K],8);}});
    ADD(72,0,F64,16,Components.Num(),[Components](FWriter& W){for(const auto& A:Components)for(int32 J=0;J<4;++J)for(int32 K=0;K<4;++K)W.Float(A.M[J][K],8);});
    ADD(73,0,F32,16,Inv.Num(),[&Inv](FWriter& W){for(const auto& A:Inv)for(int32 J=0;J<4;++J)for(int32 K=0;K<4;++K)W.Float(A.M[J][K],4);});
    ADD(74,0,F64,10,Raw.Num(),[&Raw](FWriter& W){for(const auto& B:Raw){W.Vec(B.GetTranslation(),3,8);W.Quat(B.GetRotation());W.Vec(B.GetScale3D(),3,8);}});
    ADD(75,0,I32,1,Ref.GetNum(),[&Ref](FWriter& W){for(int32 J=0;J<Ref.GetNum();++J)W.Int(uint32(Ref.GetParentIndex(J)),4);});
    S.Meta->SetArrayField(TEXT("ref_bones"),Bones);S.Meta->SetNumberField(TEXT("ref_raw_bones"),Ref.GetRawBoneNum());S.Meta->SetNumberField(TEXT("ref_final_bones"),Ref.GetNum());S.Meta->SetStringField(TEXT("skeleton_asset"),M->GetSkeleton()->GetPathName());S.Meta->SetStringField(TEXT("reference_matrix_convention"),TEXT("native row-major UE matrices; component=local*parentComponent; raw TRS Txyz/Qxyzw/Sxyz; component matrices derived without source mutation"));S.Meta->SetNumberField(TEXT("native_FTransform_bytes"),double(sizeof(FTransform)));S.Meta->SetNumberField(TEXT("native_inversebind_matrix_bytes"),double(sizeof(FMatrix44f)));S.Meta->SetBoolField(TEXT("component_default_morphs_or_morph_aware_skinning_observed"),false);
#undef ADD
    S.Packets.Add(MoveTemp(P));FPacket MP;MP.Name=TEXT("Morphs.bin");TArray<TSharedPtr<FJsonValue>> Morphs;uint64 Total=0;
    const auto& Targets=M->GetMorphTargets();
    for(int32 J=0;J<Targets.Num();++J){const UMorphTarget* Target=Targets[J];const auto D=Target->GetMorphTargetDeltas(0);const auto& ML=Target->GetMorphLODModels()[0];Total+=D.Num();if(Total+S.MorphVectors>MaxDelta)return Fail(Error,TEXT("morph_delta_bound"));auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("domain"),J);O->SetStringField(TEXT("name"),Target->GetFName().ToString());O->SetNumberField(TEXT("delta_count"),D.Num());O->SetNumberField(TEXT("base_mesh_vertices"),ML.NumBaseMeshVerts);O->SetArrayField(TEXT("section_indices"),Numbers(ML.SectionIndices));Morphs.Add(MakeShared<FJsonValueObject>(O));
     if(!MP.Add(80,uint32(J),U32,1,D.Num(),[D](FWriter& W){for(const auto& X:D)W.Int(X.SourceIdx,4);})||!MP.Add(81,uint32(J),F32,3,D.Num(),[D](FWriter& W){for(const auto& X:D)W.Vec(X.PositionDelta,3);})||!MP.Add(82,uint32(J),F32,3,D.Num(),[D](FWriter& W){for(const auto& X:D)W.Vec(X.TangentZDelta,3);}))return Fail(Error,TEXT("morph_entry_bound"));}
    S.Meta->SetArrayField(TEXT("native_morph_targets"),Morphs);S.Meta->SetStringField(TEXT("morph_default_policy"),TEXT("UNOBSERVED: asset delta observation does not initialize component weights or import FBX DeformPercent; later producer must map SourceDefaults REST=1/stress=0 explicitly"));S.Meta->SetNumberField(TEXT("native_morph_delta_struct_bytes"),double(sizeof(FMorphTargetDelta)));S.Meta->SetNumberField(TEXT("all_morph_vector_and_delta_records"),double(Total+S.MorphVectors));S.Packets.Add(MoveTemp(MP));return true;
}
bool SessionUsed=false;
bool Export(USkeletalMesh* Mesh,const FString& Relative,FString& OutJson,FString& Error)
{
    if(!IsInGameThread()||!GIsEditor||SessionUsed||!Leaf(Relative))return Fail(Error,TEXT("Editor_GameThread_fresh_single_call_leaf_required"));
    if(!IsValid(Mesh)||Mesh->GetClass()!=USkeletalMesh::StaticClass()||Mesh->IsTemplate()||Mesh->HasAnyFlags(RF_NeedLoad|RF_NeedPostLoad|RF_NeedPostLoadSubobjects)||!Mesh->GetPathName().StartsWith(Prefix,ESearchCase::CaseSensitive)||Mesh->GetOutermost()->HasAnyPackageFlags(PKG_PlayInEditor))return Fail(Error,TEXT("already_loaded_exact_scoped_skeletal_asset_required"));
    FString Owned=FPlatformMisc::GetEnvironmentVariable(TEXT("LIVING_TOWN_BOOTSTRAP_OUTPUT"));if(Owned.IsEmpty()||FPaths::IsRelative(Owned))return Fail(Error,TEXT("owned_output_environment_required"));Owned=FPaths::ConvertRelativePathToFull(Owned);FPaths::NormalizeDirectoryName(Owned);const FString Out=FPaths::Combine(Owned,Relative);
    if(!NoReparse(Owned)||!FPaths::IsUnderDirectory(Out,Owned)||FPaths::IsUnderDirectory(Out,FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()))||FPaths::IsUnderDirectory(Out,FPaths::ConvertRelativePathToFull(FPaths::EngineDir()))||IFileManager::Get().FileExists(*Out)||IFileManager::Get().DirectoryExists(*Out))return Fail(Error,TEXT("fresh_owned_output_boundary"));
    FState S;S.Mesh.Reset(Mesh);S.Dirty=Mesh->GetOutermost()->IsDirty();if(S.Dirty)return Fail(Error,TEXT("saved_clean_asset_required"));S.Package=FPaths::ConvertRelativePathToFull(FPackageName::LongPackageNameToFilename(Mesh->GetOutermost()->GetName(),FPackageName::GetAssetPackageExtension()));if(!FPaths::IsUnderDirectory(S.Package,FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()))||!Digest(S.Package,256ull<<20,S.Hash,S.PackageBytes))return Fail(Error,TEXT("saved_package_bytes_or_boundary"));
    if(!Preflight(S,Error)||!MeshDescriptionPacket(S,Error)||!ImportedPacket(S,Error)||!RenderPacket(S,Error)||!SkeletonAndMorphPackets(S,Error))return false;
    for(auto& P:S.Packets){if(!P.Layout()||S.Total>TotalCap-P.Bytes)return Fail(Error,TEXT("file96MiB_or_total384MiB_bound"));S.Total+=P.Bytes;}
    const auto* Info=Mesh->GetLODInfo(0);if(!Info)return Fail(Error,TEXT("HOLD_LOD_info_missing"));S.Meta->SetObjectField(TEXT("LOD_build_settings"),Properties(FSkeletalMeshBuildSettings::StaticStruct(),&Info->BuildSettings,Mesh));S.Meta->SetObjectField(TEXT("LOD_reduction_scalar_settings"),Properties(FSkeletalMeshOptimizationSettings::StaticStruct(),&Info->ReductionSettings,Mesh));const auto* Import=Mesh->GetAssetImportData();if(!Import)return Fail(Error,TEXT("HOLD_import_metadata_missing"));S.Meta->SetStringField(TEXT("asset_import_data_class"),Import->GetClass()->GetPathName());S.Meta->SetStringField(TEXT("source_filename"),Import->GetFirstFilename());S.Meta->SetObjectField(TEXT("import_scalar_settings"),Properties(Import->GetClass(),Import,const_cast<UAssetImportData*>(Import)));
    TArray<TSharedPtr<FJsonValue>> Materials;for(const auto& X:Mesh->GetMaterials()){auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("slot_name"),X.MaterialSlotName.ToString());O->SetStringField(TEXT("imported_slot_name"),X.ImportedMaterialSlotName.ToString());O->SetStringField(TEXT("material"),X.MaterialInterface?X.MaterialInterface->GetPathName():TEXT("NONE"));Materials.Add(MakeShared<FJsonValueObject>(O));}S.Meta->SetArrayField(TEXT("material_slots"),Materials);S.Meta->SetArrayField(TEXT("LOD_material_map"),Numbers(Info->LODMaterialMap));S.Meta->SetStringField(TEXT("asset"),Mesh->GetPathName());S.Meta->SetStringField(TEXT("package"),S.Package);S.Meta->SetStringField(TEXT("package_sha256_before"),S.Hash);S.Meta->SetNumberField(TEXT("package_bytes"),double(S.PackageBytes));S.Meta->SetNumberField(TEXT("binary_total_bytes"),double(S.Total));S.Meta->SetStringField(TEXT("schema"),TEXT("LivingTown.Current61RestRawReadback.v1"));S.Meta->SetStringField(TEXT("weight_authority"),TEXT("Stock filtered/quantized UE derivative; exact full-positive source FBX/NPZ remains separate immutable authority; no source-positive preservation claimed"));S.Meta->SetBoolField(TEXT("source_geometry_weights_defaults_or_runtime_qualified"),false);S.Meta->SetBoolField(TEXT("asset_built_normalized_skinned_saved_reimported_or_spawned"),false);S.Meta->SetStringField(TEXT("source_cache_access"),TEXT("reflected cached MeshDescriptionBulkData only, no getter load/UpdateBonesDataIfNeeded; GameThread and IsCompiling=false required"));
    SessionUsed=true;
    if(!IFileManager::Get().MakeDirectory(*Out,false)||!NoReparse(Out))return Fail(Error,TEXT("fresh_owned_directory_create"));TArray<TSharedPtr<FJsonValue>> Files;
    for(auto& P:S.Packets){if(!P.Write(Out))return Fail(Error,TEXT("binary_write_or_nonfinite_value"));FString Hash;int64 Bytes=0;if(!Digest(FPaths::Combine(Out,P.Name),FileCap,Hash,Bytes)||uint64(Bytes)!=P.Bytes)return Fail(Error,TEXT("binary_exact_bytes_or_hash"));auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("file"),P.Name);O->SetStringField(TEXT("sha256"),Hash);O->SetNumberField(TEXT("bytes"),double(Bytes));O->SetNumberField(TEXT("entries"),P.E.Num());Files.Add(MakeShared<FJsonValueObject>(O));}
    FString After;int64 AfterBytes=0;if(!Digest(S.Package,256ull<<20,After,AfterBytes)||After!=S.Hash||AfterBytes!=S.PackageBytes||Mesh->IsCompiling()||Mesh->GetOutermost()->IsDirty()!=S.Dirty||!S.Bulk->HasCachedMeshDescription()||&S.Bulk->GetMeshDescription()->GetMeshDescription()!=S.MD)return Fail(Error,TEXT("asset_or_cached_source_custody_changed"));S.Meta->SetStringField(TEXT("package_sha256_after"),After);S.Meta->SetBoolField(TEXT("package_dirty_before"),S.Dirty);S.Meta->SetBoolField(TEXT("package_dirty_after"),Mesh->GetOutermost()->IsDirty());S.Meta->SetArrayField(TEXT("files"),Files);S.Meta->SetStringField(TEXT("status"),TEXT("EXPORTED_READ_ONLY_CURRENT61_REST_RAW_DOMAINS_NOT_ASSET_PARITY"));OutJson=Json(S.Meta);FTCHARToUTF8 Final(*OutJson);if(uint64(Final.Length())>JsonCap||OutJson.Contains(TEXT("JSON_1MiB")))return Fail(Error,TEXT("JSON_1MiB"));return FFileHelper::SaveStringToFile(OutJson+TEXT("\n"),*FPaths::Combine(Out,TEXT("MANIFEST.json")),FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM,&IFileManager::Get(),FILEWRITE_NoReplaceExisting)||Fail(Error,TEXT("new_manifest_write"));
}
} // namespace Current61

FString ULivingTownCurrent61Inspection::ExportCurrent61RestAsset(USkeletalMesh* Mesh,const FString& RelativeOutputDirectory)
{
    FString Result,Error;if(Current61::Export(Mesh,RelativeOutputDirectory,Result,Error))return Result;return Current61::Reply(Error.StartsWith(TEXT("HOLD_"))?TEXT("HOLD_RESOURCE_PENDING"):TEXT("REFUSED"),Error);
}
