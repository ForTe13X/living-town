#include "LivingTownCafeGeometryLibrary.h"
#include "LivingTownCafeBinding.h"
#include "Engine/StaticMesh.h"
#include "StaticMeshResources.h"
#include "PhysicsEngine/BodySetup.h"

bool ULivingTownCafeGeometryLibrary::InspectCafeMesh(UStaticMesh* Mesh, FString& RenderSha256, FString& CollisionGuid, FString& Error)
{
    RenderSha256.Reset(); CollisionGuid.Reset(); Error.Reset();
    if (!IsInGameThread() || !IsValid(Mesh) || !Mesh->bAllowCPUAccess) { Error=TEXT("qualified_mesh_requires_CPU_readback"); return false; }
    const FStaticMeshRenderData* Data=Mesh->GetRenderData();
    UBodySetup* Body=Mesh->GetBodySetup();
    if (!Data || Data->LODResources.IsEmpty() || !Body || !Body->BodySetupGuid.IsValid()) { Error=TEXT("render_or_collision_resource_missing"); return false; }
    const FStaticMeshLODResources& L=Data->LODResources[0];
    const uint32 Count=L.VertexBuffers.PositionVertexBuffer.GetNumVertices();
    const uint32 UVs=L.VertexBuffers.StaticMeshVertexBuffer.GetNumTexCoords();
    const uint32 Colors=L.VertexBuffers.ColorVertexBuffer.GetNumVertices();
    if(!L.VertexBuffers.PositionVertexBuffer.GetVertexData()||!L.VertexBuffers.StaticMeshVertexBuffer.GetTangentData()||!L.VertexBuffers.StaticMeshVertexBuffer.GetTexCoordData()||!L.IndexBuffer.GetAllowCPUAccess()||L.IndexBuffer.GetIndexDataSize()<=0||(Colors&&!L.VertexBuffers.ColorVertexBuffer.GetAllowCPUAccess())) {Error=TEXT("CPU_vertex_or_index_readback_unavailable");return false;}
    if (Count==0 || Count>1000000 || UVs==0 || UVs>8 || (Colors!=0 && Colors!=Count) || L.IndexBuffer.GetNumIndices()%3!=0) { Error=TEXT("unsupported_mesh_layout"); return false; }
    const ANSICHAR Magic[]="LivingTown.CafeRenderLOD.v1\n";TArray<uint8> Bytes;
    const uint64 Required=uint64(UE_ARRAY_COUNT(Magic)-1)+20ull+uint64(Count)*(44ull+uint64(UVs)*8ull+(Colors?4ull:0ull))+uint64(L.IndexBuffer.GetNumIndices())*4ull+uint64(L.Sections.Num())*20ull;
    if(Required>uint64(MAX_int32)){Error=TEXT("render_binding_buffer_oversize");return false;}Bytes.Reserve(int32(Required));
    auto U32=[&Bytes](uint32 V) { for(int I=0;I<4;++I) Bytes.Add(uint8(V>>(I*8))); };
    bool Finite=true;
    auto Float=[&U32,&Finite](float V) { Finite &= FMath::IsFinite(V); uint32 Bits=0; FMemory::Memcpy(&Bits,&V,4); U32(Bits); };
    Bytes.Append(reinterpret_cast<const uint8*>(Magic),UE_ARRAY_COUNT(Magic)-1);
    U32(Count); U32(UVs); U32(Colors); U32(L.IndexBuffer.GetNumIndices()); U32(L.Sections.Num());
    for(uint32 I=0;I<Count;++I)
    {
        const FVector3f P=L.VertexBuffers.PositionVertexBuffer.VertexPosition(I); Float(P.X); Float(P.Y); Float(P.Z);
        const FVector4f X=L.VertexBuffers.StaticMeshVertexBuffer.VertexTangentX(I), Z=L.VertexBuffers.StaticMeshVertexBuffer.VertexTangentZ(I);
        for(int J=0;J<4;++J) Float(X[J]); for(int J=0;J<4;++J) Float(Z[J]);
        for(uint32 J=0;J<UVs;++J) { const FVector2f V=L.VertexBuffers.StaticMeshVertexBuffer.GetVertexUV(I,J); Float(V.X); Float(V.Y); }
        if(Colors) { const FColor C=L.VertexBuffers.ColorVertexBuffer.VertexColor(I); Bytes.Add(C.R); Bytes.Add(C.G); Bytes.Add(C.B); Bytes.Add(C.A); }
    }
    const FIndexArrayView Indices=L.IndexBuffer.GetArrayView();
    for(int32 I=0;I<Indices.Num();++I) { if(Indices[I]>=Count) { Error=TEXT("invalid_mesh_index"); return false; } U32(Indices[I]); }
    for(const FStaticMeshSection& S:L.Sections) { U32(S.MaterialIndex); U32(S.FirstIndex); U32(S.NumTriangles); U32(S.MinVertexIndex); U32(S.MaxVertexIndex); }
    if(!Finite || !LivingTownCafeJournal::Sha256(Bytes,RenderSha256)) { Error=TEXT("nonfinite_mesh_or_SHA256_unavailable"); return false; }
    CollisionGuid=Body->BodySetupGuid.ToString(EGuidFormats::Digits).ToLower();
    return true;
}
