#include "LivingTownTileData.h"
#include "LivingTownTilePlan.h"
#include "LivingTownCafeBinding.h"
#include "Engine/EngineTypes.h"
#include "Misc/PackageName.h"
#include <limits>

namespace
{
constexpr const TCHAR* AssemblySha=TEXT("35d58cc554c24be0a5fd0eb540b2eb2275444bea6bdb9c17fd41c676be67ddaf");
constexpr const TCHAR* SliceSha=TEXT("d31db5a8dd8a0907c79e043249abcccca9a80c87b422bcca5e784066baaeda81");
bool Fail(FString& Error,const TCHAR* Message){Error=Message;return false;}
bool StableId(const FString& Id)
{
    if(Id.IsEmpty() || Id.Len()>256) return false;
    for(TCHAR C:Id) if(!((C>='a'&&C<='z')||(C>='A'&&C<='Z')||(C>='0'&&C<='9')||C=='_'||C==':'||C=='-'||C=='.')) return false;
    return true;
}
bool UniqueIds(const TArray<FString>& Ids,TSet<FString>& Out)
{
    for(const FString& Id:Ids) if(!StableId(Id)||Out.Contains(Id)) return false;else Out.Add(Id);
    return true;
}
bool SameSet(const TSet<FString>& A,const TArray<FString>& B)
{
    if(A.Num()!=B.Num()) return false;
    TSet<FString> Unique;
    if(!UniqueIds(B,Unique)) return false;
    for(const FString& Id:A) if(!Unique.Contains(Id)) return false;
    return true;
}
bool ValidBox(const FBox& Box)
{
    return Box.IsValid && !Box.Min.ContainsNaN() && !Box.Max.ContainsNaN() &&
        Box.Min.X<=Box.Max.X && Box.Min.Y<=Box.Max.Y && Box.Min.Z<=Box.Max.Z;
}
bool CollisionDigits(const FString& Value)
{
    if(Value.Len()!=32) return false;
    for(TCHAR C:Value) if(!((C>='0'&&C<='9')||(C>='a'&&C<='f'))) return false;
    return true;
}
bool ValidFixture(const FLivingTownDeferredFixture& Fixture)
{
    if(!StableId(Fixture.SourceGroupId)||Fixture.SourcePlacementIds.IsEmpty()||Fixture.SourcePlacementIds.Num()>6000||
        Fixture.Qualification!=TEXT("DEFERRED_NO_BEHAVIOR")||Fixture.SourceMetadataCanonicalUtf8.IsEmpty()||
        Fixture.SourceMetadataCanonicalUtf8.Num()>65536||!LivingTownTiles::IsSha256(Fixture.SourceMetadataSha256)) return false;
    TSet<FString> Unique;
    if(!UniqueIds(Fixture.SourcePlacementIds,Unique)) return false;
    FString Actual;
    return LivingTownCafeJournal::Sha256(Fixture.SourceMetadataCanonicalUtf8,Actual)&&Actual==Fixture.SourceMetadataSha256;
}
}

bool LivingTownTiles::HashBytes(const TArray<uint8>& Bytes,FString& Out)
{return LivingTownCafeJournal::Sha256(Bytes,Out);}

bool LivingTownTiles::IsSha256(const FString& Value)
{
    if(Value.Len()!=64) return false;
    for(TCHAR C:Value) if(!((C>='0'&&C<='9')||(C>='a'&&C<='f'))) return false;
    return true;
}

bool LivingTownTiles::IsPilotAssetPath(const FSoftObjectPath& Path)
{
    const FString Text=Path.ToString();
    return Text.StartsWith(TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/"),ESearchCase::CaseSensitive) &&
        !Path.IsNull() && FPackageName::IsValidObjectPath(Text) && Path.GetSubPathString().IsEmpty() && !Text.Contains(TEXT("..")) &&
        !Text.Contains(TEXT("\\")) && !Text.Contains(TEXT(":")) && !Text.Contains(TEXT("'"));
}

bool LivingTownTiles::IsReservedCafeSourceId(const FString& Id)
{
    const FString Prefix=TEXT("town_10_urban_core:node:");
    if(!Id.StartsWith(Prefix,ESearchCase::IgnoreCase)) return false;
    const FString Suffix=Id.Mid(Prefix.Len());
    if(Suffix.IsEmpty()) return false;
    int32 Number=0;
    return LexTryParseString(Number,*Suffix) && Number>=8534 && Number<=8822;
}

bool LivingTownTiles::ValidateQualification(const FLivingTownTileQualification& Q,FString& Error)
{
    if(Q.SourceAssemblySha256!=AssemblySha || Q.SourceSliceSha256!=SliceSha ||
        !IsSha256(Q.QualifiedDerivativeSha256)||!IsSha256(Q.NativeReadbackReceiptSha256))
        return Fail(Error,TEXT("tile_source_or_readback_identity"));
    if(!Q.bAssetsQualified||!Q.bCoordinatesQualified||!Q.bMaterialsQualified||!Q.bCollisionQualified)
        return Fail(Error,TEXT("tile_native_qualification_pending"));
    return true;
}

bool LivingTownTiles::ValidatePlacement(const FLivingTownTilePlacement& P,FString& Error)
{
    if(!StableId(P.SourcePlacementId)||IsReservedCafeSourceId(P.SourcePlacementId)||P.SourceWorldMatrixRowMajor.Num()!=16)
        return Fail(Error,TEXT("tile_placement_identity_or_matrix_count"));
    const auto& M=P.SourceWorldMatrixRowMajor;
    for(double V:M) if(!FMath::IsFinite(V)) return Fail(Error,TEXT("tile_nonfinite_matrix"));
    if(M[12]!=0||M[13]!=0||M[14]!=0||M[15]!=1) return Fail(Error,TEXT("tile_nonaffine_matrix"));
    const FVector Columns[3]={FVector(M[0],M[4],M[8]),FVector(M[1],M[5],M[9]),FVector(M[2],M[6],M[10])};
    double Length[3];
    for(int32 I=0;I<3;++I)
    {
        Length[I]=Columns[I].Size();
        if(!FMath::IsFinite(Length[I])||Length[I]<=0) return Fail(Error,TEXT("tile_singular_scale"));
    }
    // This is a numerical representability boundary, not an art/geometry error
    // budget. No reflection or shear is accepted by the first pilot.
    constexpr double Numerical=64*std::numeric_limits<double>::epsilon();
    for(int32 I=0;I<3;++I) for(int32 J=I+1;J<3;++J)
        if(FMath::Abs(FVector::DotProduct(Columns[I]/Length[I],Columns[J]/Length[J]))>Numerical)
            return Fail(Error,TEXT("tile_shear_unqualified"));
    if(FVector::DotProduct(Columns[0],FVector::CrossProduct(Columns[1],Columns[2]))<=0)
        return Fail(Error,TEXT("tile_reflection_unqualified"));
    const FTransform& T=P.QualifiedNativeTransform;
    if(T.ContainsNaN()||!T.GetRotation().IsNormalized()||T.GetScale3D().GetMin()<=0)
        return Fail(Error,TEXT("tile_invalid_qualified_transform"));
    FMatrix Expected=FMatrix::Identity;
    const int32 Swap[3]={0,2,1};
    for(int32 I=0;I<3;++I) for(int32 J=0;J<3;++J) Expected.M[I][J]=M[Swap[J]*4+Swap[I]];
    Expected.M[3][0]=100*M[3];Expected.M[3][1]=100*M[11];Expected.M[3][2]=100*M[7];
    const FMatrix Actual=T.ToMatrixWithScale();
    for(int32 I=0;I<4;++I) for(int32 J=0;J<4;++J)
        if(FMath::Abs(Actual.M[I][J]-Expected.M[I][J])>Numerical*FMath::Max(1.0,FMath::Abs(Expected.M[I][J])))
            return Fail(Error,TEXT("tile_source_native_transform_mismatch"));
    return true;
}

bool LivingTownTiles::ValidateRoot(const ULivingTownTileRootData& R,FString& Error)
{
    if(R.SchemaVersion!=1) return Fail(Error,TEXT("tile_root_schema_version"));
    if(!ValidateQualification(R.Qualification,Error)) return false;
    if(!IsSha256(R.ExistingCafeBindingSha256)||R.Units.IsEmpty()||R.Units.Num()>2048||R.Supports.Num()!=24)
        return Fail(Error,TEXT("tile_root_identity_or_count"));
    if(R.SourceMeshDefinitions!=1488||R.SourcePlacedNodes!=2023||R.SourceRepeatedPlacements!=587||
        R.SourcePrototypeMeshes!=52||R.SourceDeferredDoorBatches!=150||R.SourceFixtureGroups!=385||R.SourceFixtureInventory.Num()!=385)
        return Fail(Error,TEXT("tile_pilot_census_mismatch"));
    TSet<FString> UnitIds,EntryIds,InstanceEntryIds,PrototypeKeys,InstanceIds,DoorIds,AssetPaths,FoldedUnits,FoldedEntries;
    for(const auto& U:R.Units)
    {
        if(!StableId(U.UnitId)||FoldedUnits.Contains(U.UnitId.ToLower())||!IsPilotAssetPath(U.Asset.ToSoftObjectPath())||!ValidBox(U.ActualNativeBoundsCm))
            return Fail(Error,TEXT("tile_unit_id_or_path"));
        FoldedUnits.Add(U.UnitId.ToLower());
        const FString Asset=U.Asset.ToSoftObjectPath().ToString().ToLower();
        if(AssetPaths.Contains(Asset)) return Fail(Error,TEXT("tile_unit_asset_alias"));
        AssetPaths.Add(Asset);UnitIds.Add(U.UnitId);
        if(U.DeclaredEntryIds.IsEmpty()||U.DeclaredEntryIds.Num()>256||!UniqueIds(U.DeclaredEntryIds,EntryIds)||
            !UniqueIds(U.DeclaredInstanceEntryIds,InstanceEntryIds)||!UniqueIds(U.DeclaredInstanceSourceIds,InstanceIds)||
            !UniqueIds(U.DeclaredDeferredDoorEntryIds,DoorIds)) return Fail(Error,TEXT("tile_declared_entry_alias_or_count"));
        for(const FString& Id:U.DeclaredEntryIds)
            if(FoldedEntries.Contains(Id.ToLower())) return Fail(Error,TEXT("tile_entry_case_alias"));else FoldedEntries.Add(Id.ToLower());
        TSet<FString> LocalPrototypes;
        if(!UniqueIds(U.DeclaredPrototypeMeshKeys,LocalPrototypes)) return Fail(Error,TEXT("tile_prototype_key"));
        for(const FString& Id:LocalPrototypes) PrototypeKeys.Add(Id);
        for(const FString& Id:U.DeclaredInstanceSourceIds) if(IsReservedCafeSourceId(Id)) return Fail(Error,TEXT("tile_existing_cafe_duplicate"));
        for(const FString& Id:U.DeclaredInstanceEntryIds) if(!U.DeclaredEntryIds.Contains(Id)) return Fail(Error,TEXT("tile_instance_entry_not_declared"));
        for(const FString& Id:U.DeclaredDeferredDoorEntryIds) if(!U.DeclaredEntryIds.Contains(Id)||U.DeclaredInstanceEntryIds.Contains(Id)) return Fail(Error,TEXT("tile_door_entry_not_separate"));
    }
    if(EntryIds.Num()-InstanceEntryIds.Num()!=1436||PrototypeKeys.Num()!=52||InstanceIds.Num()!=587||DoorIds.Num()!=150)
        return Fail(Error,TEXT("tile_declared_census_mismatch"));
    FLivingTownTileDemand Graph;
    if(!Graph.Initialize(R.Units,Error)) return false;
    const TSet<FString> CellIds={TEXT("cell:-1:0"),TEXT("cell:0:0"),TEXT("cell:1:0"),TEXT("cell:2:0"),TEXT("cell:3:0"),TEXT("cell:0:-1"),TEXT("cell:0:1")};
    TSet<FString> SupportIds,SeenCells;
    for(const auto& S:R.Supports)
    {
        if(!StableId(S.SupportId)||SupportIds.Contains(S.SupportId)||S.MinNativeXYCm.ContainsNaN()||S.MaxNativeXYCm.ContainsNaN()||
            S.MinNativeXYCm.X>=S.MaxNativeXYCm.X||S.MinNativeXYCm.Y>=S.MaxNativeXYCm.Y||S.Units.IsEmpty())
            return Fail(Error,TEXT("tile_support_bounds_or_identity"));
        SupportIds.Add(S.SupportId);
        if(S.bRequestedCell){if(!CellIds.Contains(S.SupportId)) return Fail(Error,TEXT("tile_unexpected_cell"));SeenCells.Add(S.SupportId);}
        TSet<FString> Unique;
        for(const FString& Id:S.Units) if(!UnitIds.Contains(Id)||Unique.Contains(Id)) return Fail(Error,TEXT("tile_support_unit_reference"));else Unique.Add(Id);
    }
    if(SeenCells.Num()!=7||R.PersistentUnits.IsEmpty()) return Fail(Error,TEXT("tile_initial_cells_or_background"));
    TSet<FString> Persistent;
    for(const FString& Id:R.PersistentUnits) if(!UnitIds.Contains(Id)||Persistent.Contains(Id)) return Fail(Error,TEXT("tile_persistent_unit_reference"));else Persistent.Add(Id);
    TMap<FString,TArray<FString>> AllSupports;
    AllSupports.Add(TEXT("persistent"),R.PersistentUnits);
    for(const auto& S:R.Supports) AllSupports.Add(S.SupportId,S.Units);
    if(!Graph.SetSupports(AllSupports,Error)) return false;
    if(Graph.Counts().Num()!=UnitIds.Num()) return Fail(Error,TEXT("tile_unreachable_catalog_unit"));
    TSet<FString> FixtureIds;int64 FixtureBytes=0;
    for(const auto& F:R.SourceFixtureInventory)
    {
        if(!ValidFixture(F)||FixtureIds.Contains(F.SourceGroupId))
            return Fail(Error,TEXT("tile_fixture_inventory"));
        FixtureIds.Add(F.SourceGroupId);FixtureBytes+=F.SourceMetadataCanonicalUtf8.Num();
    }
    if(FixtureBytes>1024*1024) return Fail(Error,TEXT("tile_fixture_metadata_budget"));
    return true;
}

bool LivingTownTiles::ValidateUnit(const ULivingTownRenderUnitData& U,const FLivingTownTileUnitRef& Expected,
    const FLivingTownTileQualification& RootQ,FString& Error)
{
    if(U.SchemaVersion!=1||U.UnitId!=Expected.UnitId||U.Geometry.IsEmpty()||U.Geometry.Num()>256)
        return Fail(Error,TEXT("tile_unit_schema_identity_or_count"));
    if(!ValidateQualification(U.Qualification,Error)) return false;
    const auto& Q=U.Qualification;
    if(Q.QualifiedDerivativeSha256!=RootQ.QualifiedDerivativeSha256||Q.NativeReadbackReceiptSha256!=RootQ.NativeReadbackReceiptSha256)
        return Fail(Error,TEXT("tile_unit_root_qualification_mismatch"));
    TSet<FString> EntryIds,InstanceEntries,PrototypeKeys,InstanceIds,DoorIds;
    FBox ActualUnion(ForceInit);
    for(const auto& G:U.Geometry)
    {
        if(!StableId(G.EntryId)||EntryIds.Contains(G.EntryId)||!StableId(G.SourceMeshKey)||
            !IsPilotAssetPath(G.Mesh.ToSoftObjectPath())||!IsSha256(G.NativeMeshReceiptSha256)||
            !IsSha256(G.NativeRenderSha256)||!CollisionDigits(G.NativeCollisionGuid)||!ValidBox(G.ActualNativeBoundsCm)||
            G.SourcePlacementIds.IsEmpty()||G.SourcePlacementIds.Num()>6000||G.Placements.IsEmpty()||G.Placements.Num()>587)
            return Fail(Error,TEXT("tile_geometry_identity_bounds_or_count"));
        EntryIds.Add(G.EntryId);
        if(G.QualifiedMaterialPaths.IsEmpty()||G.QualifiedMaterialPaths.Num()>128||
            G.QualifiedMaterialPaths.Num()!=G.QualifiedMaterialBlendModes.Num()||G.QualifiedMaterialPaths.Num()!=G.QualifiedMaterialSlotNames.Num())
            return Fail(Error,TEXT("tile_material_slot_count"));
        for(int32 I=0;I<G.QualifiedMaterialPaths.Num();++I)
        {
            const FString Path=G.QualifiedMaterialPaths[I].ToString();
            if(!Path.StartsWith(TEXT("/Game/LivingTown_UEPilot/"),ESearchCase::CaseSensitive)||!FPackageName::IsValidObjectPath(Path)||
                !G.QualifiedMaterialPaths[I].GetSubPathString().IsEmpty()||G.QualifiedMaterialBlendModes[I]>=uint8(BLEND_MAX)||
                G.QualifiedMaterialSlotNames[I].IsEmpty()||G.QualifiedMaterialSlotNames[I].Len()>256)
                return Fail(Error,TEXT("tile_material_slot_identity"));
        }
        ActualUnion+=G.ActualNativeBoundsCm;
        TSet<FString> LocalSourceIds;
        if(!UniqueIds(G.SourcePlacementIds,LocalSourceIds)) return Fail(Error,TEXT("tile_duplicate_geometry_source"));
        for(const FString& Id:G.SourcePlacementIds) if(IsReservedCafeSourceId(Id)) return Fail(Error,TEXT("tile_existing_cafe_or_bad_source"));
        if(G.Kind!=ELivingTownTileEntryKind::Static&&G.Kind!=ELivingTownTileEntryKind::Instanced&&G.Kind!=ELivingTownTileEntryKind::DeferredDoor)
            return Fail(Error,TEXT("tile_entry_kind"));
        if(G.Kind!=ELivingTownTileEntryKind::Instanced&&G.Placements.Num()!=1) return Fail(Error,TEXT("tile_static_entry_placement_count"));
        if(G.Kind==ELivingTownTileEntryKind::Instanced){InstanceEntries.Add(G.EntryId);PrototypeKeys.Add(G.SourceMeshKey);}
        if(G.Kind==ELivingTownTileEntryKind::DeferredDoor) DoorIds.Add(G.EntryId);
        for(const auto& P:G.Placements)
        {
            if(!ValidatePlacement(P,Error)) return false;
            if(G.Kind==ELivingTownTileEntryKind::Instanced)
            {
                if(InstanceIds.Contains(P.SourcePlacementId)||!LocalSourceIds.Contains(P.SourcePlacementId)) return Fail(Error,TEXT("tile_duplicate_or_unbound_instance_source"));
                InstanceIds.Add(P.SourcePlacementId);
            }
            else if(!P.QualifiedNativeTransform.Equals(FTransform::Identity,0.0))
                return Fail(Error,TEXT("tile_baked_static_double_transform"));
        }
        if(G.Kind==ELivingTownTileEntryKind::Instanced&&LocalSourceIds.Num()!=G.Placements.Num())
            return Fail(Error,TEXT("tile_instance_provenance_count"));
    }
    if(!SameSet(EntryIds,Expected.DeclaredEntryIds)||!SameSet(InstanceEntries,Expected.DeclaredInstanceEntryIds)||
        !SameSet(PrototypeKeys,Expected.DeclaredPrototypeMeshKeys)||!SameSet(InstanceIds,Expected.DeclaredInstanceSourceIds)||
        !SameSet(DoorIds,Expected.DeclaredDeferredDoorEntryIds)) return Fail(Error,TEXT("tile_declared_loaded_unit_mismatch"));
    if(ActualUnion.Min!=Expected.ActualNativeBoundsCm.Min||ActualUnion.Max!=Expected.ActualNativeBoundsCm.Max)
        return Fail(Error,TEXT("tile_unit_actual_bounds_mismatch"));
    if(U.DeferredFixtures.Num()>385) return Fail(Error,TEXT("tile_fixture_group_count"));
    TSet<FString> FixtureIds;int64 FixtureBytes=0;
    for(const auto& F:U.DeferredFixtures)
    {
        if(!ValidFixture(F)||FixtureIds.Contains(F.SourceGroupId))
            return Fail(Error,TEXT("tile_deferred_fixture"));
        FixtureIds.Add(F.SourceGroupId);FixtureBytes+=F.SourceMetadataCanonicalUtf8.Num();
    }
    if(FixtureBytes>1024*1024) return Fail(Error,TEXT("tile_fixture_metadata_budget"));
    return true;
}
