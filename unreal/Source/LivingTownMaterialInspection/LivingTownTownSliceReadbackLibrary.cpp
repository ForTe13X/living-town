#include "LivingTownTownSliceReadbackLibrary.h"
#include "LivingTownCafeGeometryLibrary.h"
#include "LivingTownTileData.h"
#include "Engine/StaticMesh.h"
#include "Engine/EngineTypes.h"
#include "StaticMeshResources.h"
#include "StaticMeshCompiler.h"
#include "Materials/MaterialInterface.h"
#include "PhysicsEngine/BodySetup.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/EngineVersion.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformMisc.h"
#include "UObject/Package.h"
#include "UObject/StrongObjectPtr.h"
#include "UObject/UObjectGlobals.h"
#if PLATFORM_WINDOWS
#include "Windows/WindowsHWrapper.h"
#endif

namespace
{
constexpr uint64 MaximumFileBytes=256ull*1024*1024;
constexpr uint64 MaximumTotalBinaryBytes=1024ull*1024*1024;
constexpr const TCHAR* AssetPrefix=TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/");
enum class EReadbackScope : uint8 { TownSlice, CafeFurniture };
constexpr const TCHAR* CafeChair=TEXT("/Game/LivingTown_UEPilot/CafeFurnitureCC0_v001/SM_Chair.SM_Chair");
constexpr const TCHAR* CafeTable=TEXT("/Game/LivingTown_UEPilot/CafeFurnitureCC0_v001/SM_Table.SM_Table");
bool CafeFurniturePair(const TArray<FString>& Paths)
{
    return Paths.Num()==2&&((Paths[0].Equals(CafeChair,ESearchCase::CaseSensitive)&&Paths[1].Equals(CafeTable,ESearchCase::CaseSensitive))||(Paths[0].Equals(CafeTable,ESearchCase::CaseSensitive)&&Paths[1].Equals(CafeChair,ESearchCase::CaseSensitive)));
}
bool AllowedAsset(const FString& Path,EReadbackScope Scope)
{
    return Scope==EReadbackScope::TownSlice?Path.StartsWith(AssetPrefix,ESearchCase::CaseSensitive):(Path.Equals(CafeChair,ESearchCase::CaseSensitive)||Path.Equals(CafeTable,ESearchCase::CaseSensitive));
}

constexpr const ANSICHAR* Magic="LTTOWNLOD0RB0001";
bool Refuse(FString& Error,const FString& Why){Error=Why;return false;}

bool ExistingPathHasNoReparsePoint(const FString& Absolute)
{
#if PLATFORM_WINDOWS
    FString Native=Absolute.Replace(TEXT("/"),TEXT("\\"));
    if(Native.Len()<3||Native[1]!=':'||Native[2]!='\\') return false;
    FString Prefix=Native.Left(3);TArray<FString> Parts;Native.Mid(3).ParseIntoArray(Parts,TEXT("\\"),true);
    auto Check=[](const FString& Path){const DWORD A=GetFileAttributesW(*Path);return A!=INVALID_FILE_ATTRIBUTES&&!(A&FILE_ATTRIBUTE_REPARSE_POINT);};
    if(!Check(Prefix)) return false;
    for(const FString& Part:Parts){if(Part==TEXT(".")||Part==TEXT("..")) return false;Prefix=FPaths::Combine(Prefix,Part);if(!Check(Prefix)) return false;}
    return true;
#else
    return false; // The first qualified file-output supervisor is Windows-only.
#endif
}

bool OutputLeafName(const FString& Name)
{
    if(Name.IsEmpty()||Name.Len()>64) return false;
    for(TCHAR C:Name) if(!((C>='A'&&C<='Z')||(C>='a'&&C<='z')||(C>='0'&&C<='9')||C=='_')) return false;
    return true;
}

bool NewJson(const FString& Filename,const TSharedRef<FJsonObject>& Object)
{
    FString Text;
    const auto Writer=TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Text);
    return FJsonSerializer::Serialize(Object,Writer) && FFileHelper::SaveStringToFile(Text+TEXT("\n"),*Filename,
        FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM,&IFileManager::Get(),FILEWRITE_NoReplaceExisting);
}

bool FileDigest(const FString& Filename,FString& Hash,int64& Bytes)
{
    if(!ExistingPathHasNoReparsePoint(Filename)) return false;
    const int64 Before=IFileManager::Get().FileSize(*Filename);
    if(Before<0||uint64(Before)>MaximumFileBytes) return false;
    TArray<uint8> Data;
    if(!FFileHelper::LoadFileToArray(Data,*Filename)||Data.Num()!=Before||IFileManager::Get().FileSize(*Filename)!=Before) return false;
    Bytes=Before;return LivingTownTiles::HashBytes(Data,Hash);
}

TSharedRef<FJsonObject> Record(const FString& Relative,int64 Bytes,const FString& Hash)
{
    auto Result=MakeShared<FJsonObject>();Result->SetStringField(TEXT("path"),Relative);Result->SetNumberField(TEXT("bytes"),double(Bytes));Result->SetStringField(TEXT("sha256"),Hash);return Result;
}

TArray<TSharedPtr<FJsonValue>> Vector(const FVector& V)
{return {MakeShared<FJsonValueNumber>(V.X),MakeShared<FJsonValueNumber>(V.Y),MakeShared<FJsonValueNumber>(V.Z)};}

class FBoundedLEWriter final
{
public:
    explicit FBoundedLEWriter(const FString& Filename)
    {File.Reset(IFileManager::Get().CreateFileWriter(*Filename,FILEWRITE_NoReplaceExisting));Buffer.Reserve(65536);bGood=File.IsValid();}
    void Byte(uint8 Value)
    {
        if(!bGood||Count>=MaximumFileBytes){bGood=false;return;}
        Buffer.Add(Value);++Count;if(Buffer.Num()>=65536) Flush();
    }
    void U32(uint32 Value){for(int32 I=0;I<4;++I) Byte(uint8(Value>>(8*I)));}
    void Float(float Value)
    {if(!FMath::IsFinite(Value)){bGood=false;return;}uint32 Bits=0;FMemory::Memcpy(&Bits,&Value,4);U32(Bits);}
    bool Finish()
    {Flush();if(!File)return false;const bool Closed=File->Close();bGood&=Closed&&!File->IsError();File.Reset();return bGood;}
    uint64 Bytes() const{return Count;}
private:
    TUniquePtr<FArchive> File;TArray<uint8> Buffer;uint64 Count=0;bool bGood=false;
    void Flush(){if(File&&Buffer.Num()){File->Serialize(Buffer.GetData(),Buffer.Num());bGood&=!File->IsError();Buffer.Reset();}}
};

bool WriteBuffers(const FString& Filename,const FStaticMeshLODResources& L,uint32& VertexStride,FString& Error)
{
    const uint32 V=L.VertexBuffers.PositionVertexBuffer.GetNumVertices();
    const uint32 UV=L.VertexBuffers.StaticMeshVertexBuffer.GetNumTexCoords();
    const uint32 C=L.VertexBuffers.ColorVertexBuffer.GetNumVertices();
    const uint32 I=L.IndexBuffer.GetNumIndices();const uint32 S=uint32(L.Sections.Num());
    if(V==0||V>1000000||UV==0||UV>8||(C&&C!=V)||I==0||I>3000000||I%3||S>4096)
        return Refuse(Error,TEXT("readback_unsupported_LOD0_layout"));
    if(!L.IndexBuffer.GetAllowCPUAccess()||!L.VertexBuffers.PositionVertexBuffer.GetVertexData()||
        !L.VertexBuffers.StaticMeshVertexBuffer.GetTangentData()||!L.VertexBuffers.StaticMeshVertexBuffer.GetTexCoordData()||
        (C&&!L.VertexBuffers.ColorVertexBuffer.GetAllowCPUAccess())) return Refuse(Error,TEXT("readback_CPU_buffers_unavailable"));
    const uint32 IndexStride=L.IndexBuffer.GetIndexDataSize()/I;
    if(IndexStride!=2&&IndexStride!=4) return Refuse(Error,TEXT("readback_native_index_stride"));
    VertexStride=56+8*UV+(C?4:0);
    const uint64 Expected=64ull+uint64(V)*VertexStride+uint64(I)*4+uint64(S)*20;
    if(Expected>MaximumFileBytes) return Refuse(Error,TEXT("readback_binary_size_cap"));
    const auto& VB=L.VertexBuffers.StaticMeshVertexBuffer;
    const uint32 Flags=(C?1u:0u)|(VB.GetUseFullPrecisionUVs()?2u:0u)|(VB.GetUseHighPrecisionTangentBasis()?4u:0u)|8u|(IndexStride==4?16u:0u);
    FBoundedLEWriter W(Filename);for(int32 N=0;N<16;++N) W.Byte(uint8(Magic[N]));
    for(uint32 X:{1u,64u,V,UV,C,I,S,VertexStride,4u,20u,Flags,0u}) W.U32(X);
    for(uint32 N=0;N<V;++N)
    {
        const FVector3f P=L.VertexBuffers.PositionVertexBuffer.VertexPosition(N);
        const FVector4f X=VB.VertexTangentX(N),Z=VB.VertexTangentZ(N);const FVector3f Y=VB.VertexTangentY(N);
        W.Float(P.X);W.Float(P.Y);W.Float(P.Z);
        for(int32 K=0;K<4;++K) W.Float(X[K]);for(int32 K=0;K<4;++K) W.Float(Z[K]);
        W.Float(Y.X);W.Float(Y.Y);W.Float(Y.Z);
        for(uint32 K=0;K<UV;++K){const FVector2f T=VB.GetVertexUV(N,K);W.Float(T.X);W.Float(T.Y);}
        if(C){const FColor Color=L.VertexBuffers.ColorVertexBuffer.VertexColor(N);W.Byte(Color.R);W.Byte(Color.G);W.Byte(Color.B);W.Byte(Color.A);}
    }
    const FIndexArrayView Indices=L.IndexBuffer.GetArrayView();
    for(int32 N=0;N<Indices.Num();++N){if(Indices[N]>=V)return Refuse(Error,TEXT("readback_index_outside_vertices"));W.U32(Indices[N]);}
    for(const FStaticMeshSection& Section:L.Sections)
    {W.U32(Section.MaterialIndex);W.U32(Section.FirstIndex);W.U32(Section.NumTriangles);W.U32(Section.MinVertexIndex);W.U32(Section.MaxVertexIndex);}
    if(!W.Finish()||W.Bytes()!=Expected) return Refuse(Error,TEXT("readback_binary_write_or_count"));
    return true;
}

TSharedRef<FJsonObject> BuildSettings(UStaticMesh* Mesh)
{
    auto O=MakeShared<FJsonObject>();O->SetBoolField(TEXT("source_model_present"),Mesh->GetNumSourceModels()>0);
    if(Mesh->GetNumSourceModels()<=0)return O;
    const auto& B=Mesh->GetSourceModel(0).BuildSettings;
    O->SetBoolField(TEXT("recompute_normals"),B.bRecomputeNormals);O->SetBoolField(TEXT("recompute_tangents"),B.bRecomputeTangents);
    O->SetBoolField(TEXT("use_mikk_t_space"),B.bUseMikkTSpace);O->SetBoolField(TEXT("remove_degenerates"),B.bRemoveDegenerates);
    O->SetBoolField(TEXT("full_precision_uvs"),B.bUseFullPrecisionUVs);O->SetBoolField(TEXT("high_precision_tangent_basis"),B.bUseHighPrecisionTangentBasis);
    O->SetBoolField(TEXT("generate_lightmap_uvs"),B.bGenerateLightmapUVs);O->SetBoolField(TEXT("build_reversed_index_buffer"),B.bBuildReversedIndexBuffer);
    O->SetNumberField(TEXT("src_lightmap_index"),B.SrcLightmapIndex);O->SetNumberField(TEXT("dst_lightmap_index"),B.DstLightmapIndex);
    O->SetArrayField(TEXT("build_scale3d"),Vector(B.BuildScale3D));return O;
}


bool ExportScopedNativeMeshes(const TArray<FString>& AssetPaths,const FString& RelativeOutputDirectory,FString& ReceiptJson,FString& Error,EReadbackScope Scope)
{
    ReceiptJson.Empty();Error.Empty();
    if(!IsInGameThread()||!GIsEditor||AssetPaths.IsEmpty()||AssetPaths.Num()>1488||!OutputLeafName(RelativeOutputDirectory))
        return Refuse(Error,TEXT("readback_editor_thread_count_or_output_name"));
    FString Owned=FPlatformMisc::GetEnvironmentVariable(TEXT("LIVING_TOWN_BOOTSTRAP_OUTPUT"));
    if(Owned.IsEmpty()||FPaths::IsRelative(Owned))return Refuse(Error,TEXT("readback_owned_output_environment_required"));
    Owned=FPaths::ConvertRelativePathToFull(Owned);FPaths::NormalizeDirectoryName(Owned);
    const FString Out=FPaths::Combine(Owned,RelativeOutputDirectory);
    const FString Content=FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir());
    if(!IFileManager::Get().DirectoryExists(*Owned)||!ExistingPathHasNoReparsePoint(Owned)||
        !FPaths::IsUnderDirectory(Out,Owned)||FPaths::IsUnderDirectory(Out,Content)||
        FPaths::IsUnderDirectory(Out,FPaths::ConvertRelativePathToFull(FPaths::EngineDir()))||
        IFileManager::Get().DirectoryExists(*Out)||IFileManager::Get().FileExists(*Out))
        return Refuse(Error,TEXT("readback_fresh_owned_output_boundary"));
    TSet<FString> Seen;TArray<TStrongObjectPtr<UStaticMesh>> Meshes;TArray<UStaticMesh*> CompilationInputs;
    TArray<FString> SourceFiles,SourceHashes;TArray<int64> SourceSizes;TArray<bool> DirtyBefore;
    for(const FString& Path:AssetPaths)
    {
        const FSoftObjectPath Soft(Path);
        if(!AllowedAsset(Path,Scope)||!FPackageName::IsValidObjectPath(Path)||!Soft.GetSubPathString().IsEmpty()||Seen.Contains(Path.ToLower()))
            return Refuse(Error,TEXT("readback_asset_namespace_or_alias"));
        Seen.Add(Path.ToLower());
        UStaticMesh* Mesh=LoadObject<UStaticMesh>(nullptr,*Path);
        if(!IsValid(Mesh)||Mesh->GetPathName()!=Path||Mesh->GetOutermost()->HasAnyPackageFlags(PKG_PlayInEditor)||!Mesh->bAllowCPUAccess)
            return Refuse(Error,TEXT("readback_asset_type_identity_or_CPU_access"));
        const FString Source=FPaths::ConvertRelativePathToFull(FPackageName::LongPackageNameToFilename(Mesh->GetOutermost()->GetName(),FPackageName::GetAssetPackageExtension()));
        FString Hash;int64 Bytes=0;
        if(!FPaths::IsUnderDirectory(Source,Content)||!FileDigest(Source,Hash,Bytes))return Refuse(Error,TEXT("readback_saved_source_asset_required"));
        Meshes.Emplace(Mesh);CompilationInputs.Add(Mesh);SourceFiles.Add(Source);SourceHashes.Add(Hash);SourceSizes.Add(Bytes);DirtyBefore.Add(Mesh->GetOutermost()->IsDirty());
    }
    int32 PendingBefore=0;for(const auto* Mesh:CompilationInputs)if(Mesh->IsCompiling())++PendingBefore;
    FStaticMeshCompilingManager::Get().FinishCompilation(CompilationInputs); // exactly one batch barrier
    for(const auto* Mesh:CompilationInputs)if(Mesh->IsCompiling())return Refuse(Error,TEXT("readback_compilation_still_pending"));
    if(!IFileManager::Get().MakeDirectory(*Out,false)||!ExistingPathHasNoReparsePoint(Out))return Refuse(Error,TEXT("readback_create_fresh_directory"));
    const FString Marker=FPaths::Combine(Out,TEXT("INCOMPLETE.txt"));
    if(!FFileHelper::SaveStringToFile(TEXT("Incomplete native readback; no qualification.\n"),*Marker,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM,&IFileManager::Get(),FILEWRITE_NoReplaceExisting))
        return Refuse(Error,TEXT("readback_incomplete_marker"));
    TArray<TSharedPtr<FJsonValue>> Exports;uint64 Total=0;
    for(int32 N=0;N<Meshes.Num();++N)
    {
        UStaticMesh* Mesh=Meshes[N].Get();FString NativeHash,Collision,Why;
        if(Mesh->IsCompiling()||!ULivingTownCafeGeometryLibrary::InspectCafeMesh(Mesh,NativeHash,Collision,Why))
            return Refuse(Error,TEXT("readback_full_native_inspector_failed: ")+Why);
        const auto* Data=Mesh->GetRenderData();
        if(!Data||Data->LODResources.IsEmpty())return Refuse(Error,TEXT("readback_native_LOD0_absent"));
        const auto& L=Data->LODResources[0];const auto& VB=L.VertexBuffers.StaticMeshVertexBuffer;
        const FString BinaryName=FString::Printf(TEXT("mesh_%05d.native-lod0.bin"),N),MetaName=FString::Printf(TEXT("mesh_%05d.json"),N);
        uint32 Stride=0;if(!WriteBuffers(FPaths::Combine(Out,BinaryName),L,Stride,Error))return false;
        FString BinaryHash;int64 BinaryBytes=0;
        if(!FileDigest(FPaths::Combine(Out,BinaryName),BinaryHash,BinaryBytes))return Refuse(Error,TEXT("readback_binary_SHA"));
        Total+=uint64(BinaryBytes);if(Total>MaximumTotalBinaryBytes)return Refuse(Error,TEXT("readback_total_binary_size_cap"));
        FString AfterHash;int64 AfterBytes=0;
        if(!FileDigest(SourceFiles[N],AfterHash,AfterBytes)||AfterHash!=SourceHashes[N]||AfterBytes!=SourceSizes[N]||Mesh->GetOutermost()->IsDirty()!=DirtyBefore[N])
            return Refuse(Error,TEXT("readback_source_asset_file_or_dirty_flag_changed"));
        auto Meta=MakeShared<FJsonObject>();Meta->SetStringField(TEXT("schema"),TEXT("living_town.town_slice_native_mesh.v1"));
        Meta->SetStringField(TEXT("asset_path"),AssetPaths[N]);Meta->SetStringField(TEXT("native_render_sha256"),NativeHash);Meta->SetStringField(TEXT("collision_guid"),Collision);
        Meta->SetObjectField(TEXT("binary"),Record(BinaryName,BinaryBytes,BinaryHash));
        auto LOD=MakeShared<FJsonObject>();const uint32 IndexCount=L.IndexBuffer.GetNumIndices();
        LOD->SetNumberField(TEXT("vertex_count"),L.VertexBuffers.PositionVertexBuffer.GetNumVertices());LOD->SetNumberField(TEXT("uv_channels"),VB.GetNumTexCoords());
        LOD->SetNumberField(TEXT("color_vertices"),L.VertexBuffers.ColorVertexBuffer.GetNumVertices());LOD->SetNumberField(TEXT("index_count"),IndexCount);LOD->SetNumberField(TEXT("section_count"),L.Sections.Num());
        LOD->SetNumberField(TEXT("vertex_stride_bytes"),Stride);LOD->SetBoolField(TEXT("native_buffer_full_precision_uvs"),VB.GetUseFullPrecisionUVs());
        LOD->SetBoolField(TEXT("native_buffer_high_precision_tangent_basis"),VB.GetUseHighPrecisionTangentBasis());LOD->SetNumberField(TEXT("native_source_index_stride_bytes"),IndexCount?L.IndexBuffer.GetIndexDataSize()/IndexCount:0);
        Meta->SetObjectField(TEXT("lod0"),LOD);Meta->SetObjectField(TEXT("build_settings_lod0"),BuildSettings(Mesh));
        auto Flags=MakeShared<FJsonObject>();Flags->SetBoolField(TEXT("allow_cpu_access"),Mesh->bAllowCPUAccess);Flags->SetBoolField(TEXT("distance_field_cpu_data_present"),L.DistanceFieldData!=nullptr);Flags->SetBoolField(TEXT("distance_field_gpu_residency_qualified"),false);Meta->SetObjectField(TEXT("mesh_flags"),Flags);
        auto Bounds=MakeShared<FJsonObject>();const auto& B=Mesh->GetBounds();const auto& R=Data->Bounds;
        Bounds->SetArrayField(TEXT("mesh_origin"),Vector(FVector(B.Origin)));Bounds->SetArrayField(TEXT("mesh_extent"),Vector(FVector(B.BoxExtent)));Bounds->SetNumberField(TEXT("mesh_sphere_radius"),B.SphereRadius);
        Bounds->SetArrayField(TEXT("render_origin"),Vector(FVector(R.Origin)));Bounds->SetArrayField(TEXT("render_extent"),Vector(FVector(R.BoxExtent)));Bounds->SetNumberField(TEXT("render_sphere_radius"),R.SphereRadius);Meta->SetObjectField(TEXT("bounds_cm"),Bounds);
        TArray<TSharedPtr<FJsonValue>> Materials;const auto& Slots=Mesh->GetStaticMaterials();
        for(int32 S=0;S<Slots.Num();++S)
        {
            const auto* Material=Slots[S].MaterialInterface.Get();auto Slot=MakeShared<FJsonObject>();Slot->SetNumberField(TEXT("slot_index"),S);
            Slot->SetStringField(TEXT("slot_name"),Slots[S].MaterialSlotName.ToString());Slot->SetStringField(TEXT("imported_slot_name"),Slots[S].ImportedMaterialSlotName.ToString());
            Slot->SetStringField(TEXT("asset_path"),Material?Material->GetPathName():TEXT(""));Slot->SetNumberField(TEXT("blend_mode"),Material?int32(Material->GetBlendMode()):-1);Slot->SetBoolField(TEXT("valid"),Material!=nullptr);Materials.Add(MakeShared<FJsonValueObject>(Slot));
        }
        Meta->SetArrayField(TEXT("materials"),Materials);auto Source=MakeShared<FJsonObject>();FString Relative=SourceFiles[N];FPaths::MakePathRelativeTo(Relative,*FPaths::ConvertRelativePathToFull(FPaths::ProjectDir()));
        Source->SetStringField(TEXT("project_relative_path"),Relative);Source->SetNumberField(TEXT("bytes"),double(SourceSizes[N]));Source->SetStringField(TEXT("sha256_before"),SourceHashes[N]);Source->SetStringField(TEXT("sha256_after"),AfterHash);Meta->SetObjectField(TEXT("source_asset_file"),Source);
        Meta->SetBoolField(TEXT("package_dirty_before"),DirtyBefore[N]);Meta->SetBoolField(TEXT("package_dirty_after"),Mesh->GetOutermost()->IsDirty());
        if(!NewJson(FPaths::Combine(Out,MetaName),Meta))return Refuse(Error,TEXT("readback_new_metadata_file"));
        FString MetaHash;int64 MetaBytes=0;if(!FileDigest(FPaths::Combine(Out,MetaName),MetaHash,MetaBytes))return Refuse(Error,TEXT("readback_metadata_SHA"));
        auto Entry=MakeShared<FJsonObject>();Entry->SetStringField(TEXT("asset_path"),AssetPaths[N]);Entry->SetObjectField(TEXT("binary"),Record(BinaryName,BinaryBytes,BinaryHash));Entry->SetObjectField(TEXT("metadata"),Record(MetaName,MetaBytes,MetaHash));Exports.Add(MakeShared<FJsonValueObject>(Entry));
    }
    // Final input closure recheck; no SavePackage, setters or source-file writes.
    for(int32 N=0;N<SourceFiles.Num();++N)
    {FString Hash;int64 Bytes=0;if(!FileDigest(SourceFiles[N],Hash,Bytes)||Hash!=SourceHashes[N]||Bytes!=SourceSizes[N]||Meshes[N]->GetOutermost()->IsDirty()!=DirtyBefore[N])return Refuse(Error,TEXT("readback_final_source_asset_guard"));}
    auto Manifest=MakeShared<FJsonObject>();Manifest->SetStringField(TEXT("schema"),TEXT("living_town.town_slice_native_readback.v1"));Manifest->SetStringField(TEXT("binary_schema"),TEXT("LTTOWNLOD0RB0001"));
    Manifest->SetArrayField(TEXT("exports"),Exports);Manifest->SetNumberField(TEXT("mesh_count"),Meshes.Num());Manifest->SetNumberField(TEXT("total_binary_bytes"),double(Total));
    Manifest->SetNumberField(TEXT("batch_finish_count"),1);Manifest->SetNumberField(TEXT("pending_before"),PendingBefore);Manifest->SetNumberField(TEXT("pending_after"),0);
    Manifest->SetStringField(TEXT("engine_version"),FEngineVersion::Current().ToString());Manifest->SetBoolField(TEXT("source_assets_saved"),false);
    const FString ManifestPath=FPaths::Combine(Out,TEXT("MANIFEST.json"));
    if(!NewJson(ManifestPath,Manifest))return Refuse(Error,TEXT("readback_new_manifest"));
    FString ManifestHash;int64 ManifestBytes=0;if(!FileDigest(ManifestPath,ManifestHash,ManifestBytes))return Refuse(Error,TEXT("readback_manifest_SHA"));
    if(!IFileManager::Get().Delete(*Marker,true,false,true))return Refuse(Error,TEXT("readback_owned_incomplete_marker_removal"));
    auto Result=MakeShared<FJsonObject>();Result->SetStringField(TEXT("status"),TEXT("EXPORTED_NATIVE_BUFFERS_SOURCE_COMPARISON_PENDING"));Result->SetStringField(TEXT("manifest_path"),ManifestPath);Result->SetStringField(TEXT("manifest_sha256"),ManifestHash);Result->SetNumberField(TEXT("mesh_count"),Meshes.Num());Result->SetNumberField(TEXT("total_binary_bytes"),double(Total));
    const auto Writer=TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&ReceiptJson);return FJsonSerializer::Serialize(Result,Writer);
}

} // Shared implementation remains private; only the two strict reflected endpoints call it.

bool ULivingTownTownSliceReadbackLibrary::ExportTownSliceMeshes(const TArray<FString>& AssetPaths,const FString& RelativeOutputDirectory,FString& ReceiptJson,FString& Error)
{
    return ExportScopedNativeMeshes(AssetPaths,RelativeOutputDirectory,ReceiptJson,Error,EReadbackScope::TownSlice);
}

bool ULivingTownTownSliceReadbackLibrary::ExportCafeFurnitureMeshes(const TArray<FString>& AssetPaths,const FString& RelativeOutputDirectory,FString& ReceiptJson,FString& Error)
{
    ReceiptJson.Empty();Error.Empty();
    if(!CafeFurniturePair(AssetPaths))return Refuse(Error,TEXT("readback_exact_two_cafe_furniture_assets_required"));
    return ExportScopedNativeMeshes(AssetPaths,RelativeOutputDirectory,ReceiptJson,Error,EReadbackScope::CafeFurniture);
}
