#include "LivingTownTileData.h"
#include "LivingTownTilePlan.h"
#include "LivingTownCafeBinding.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "UObject/StrongObjectPtr.h"
#include "UObject/UObjectGlobals.h"
#include "Engine/StaticMesh.h"

namespace
{
FLivingTownTileQualification MetadataFixture()
{
    FLivingTownTileQualification Q;
    Q.SourceAssemblySha256=TEXT("35d58cc554c24be0a5fd0eb540b2eb2275444bea6bdb9c17fd41c676be67ddaf");
    Q.SourceSliceSha256=TEXT("d31db5a8dd8a0907c79e043249abcccca9a80c87b422bcca5e784066baaeda81");
    Q.QualifiedDerivativeSha256=FString::ChrN(64,'a');Q.NativeReadbackReceiptSha256=FString::ChrN(64,'b');
    Q.bAssetsQualified=Q.bCoordinatesQualified=Q.bMaterialsQualified=Q.bCollisionQualified=true;return Q;
}
FLivingTownTilePlacement IdentityPlacement()
{
    FLivingTownTilePlacement P;P.SourcePlacementId=TEXT("town_04_reserve:node:123");
    P.SourceWorldMatrixRowMajor={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1};return P;
}
FLivingTownTileUnitRef Unit(const FString& Id,TArray<FString> Dependencies={})
{FLivingTownTileUnitRef U;U.UnitId=Id;U.Dependencies=MoveTemp(Dependencies);return U;}

void PopulateRootMetadataFixture(ULivingTownTileRootData& R)
{
    // Synthetic metadata only. These assets do not exist, their receipts are
    // deliberately fake, and this fixture cannot activate the runtime driver.
    R.Qualification=MetadataFixture();R.ExistingCafeBindingSha256=FString::ChrN(64,'c');
    for(int32 Batch=0;Batch<6;++Batch)
    {
        auto U=Unit(FString::Printf(TEXT("static_%d"),Batch));
        U.Asset=TSoftObjectPtr<ULivingTownRenderUnitData>(FSoftObjectPath(FString::Printf(TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/U_%d.U_%d"),Batch,Batch)));
        U.ActualNativeBoundsCm=FBox(FVector(-1),FVector(1));
        for(int32 I=Batch*256;I<FMath::Min(1436,(Batch+1)*256);++I)
        {
            const FString Id=FString::Printf(TEXT("static_entry_%d"),I);U.DeclaredEntryIds.Add(Id);
            if(I<150) U.DeclaredDeferredDoorEntryIds.Add(Id);
        }
        R.Units.Add(MoveTemp(U));
    }
    auto Instances=Unit(TEXT("instances"));
    Instances.Asset=TSoftObjectPtr<ULivingTownRenderUnitData>(FSoftObjectPath(TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/U_instances.U_instances")));
    Instances.ActualNativeBoundsCm=FBox(FVector(-1),FVector(1));
    for(int32 I=0;I<52;++I)
    {
        const FString Id=FString::Printf(TEXT("instance_entry_%d"),I);
        Instances.DeclaredEntryIds.Add(Id);Instances.DeclaredInstanceEntryIds.Add(Id);
        Instances.DeclaredPrototypeMeshKeys.Add(FString::Printf(TEXT("prototype_%d"),I));
    }
    for(int32 I=0;I<587;++I) Instances.DeclaredInstanceSourceIds.Add(FString::Printf(TEXT("town_04_reserve:node:%d"),I));
    R.Units.Add(MoveTemp(Instances));
    const TArray<FString> CellIds={TEXT("cell:-1:0"),TEXT("cell:0:0"),TEXT("cell:1:0"),TEXT("cell:2:0"),TEXT("cell:3:0"),TEXT("cell:0:-1"),TEXT("cell:0:1")};
    for(int32 I=0;I<24;++I)
    {
        FLivingTownTileSupport S;S.SupportId=I<7?CellIds[I]:FString::Printf(TEXT("owner:%d"),I-7);S.bRequestedCell=I<7;
        S.MinNativeXYCm=FVector2D(0,0);S.MaxNativeXYCm=FVector2D(100,100);
        for(const auto& U:R.Units) S.Units.Add(U.UnitId);R.Supports.Add(MoveTemp(S));
    }
    R.PersistentUnits={R.Units[0].UnitId};
    for(int32 I=0;I<385;++I)
    {FLivingTownDeferredFixture F;F.SourceGroupId=FString::Printf(TEXT("fixture:%d"),I);F.SourcePlacementIds={TEXT("town_04_reserve:node:1")};
        F.SourceMetadataCanonicalUtf8={uint8('{'),uint8('}')};LivingTownCafeJournal::Sha256(F.SourceMetadataCanonicalUtf8,F.SourceMetadataSha256);
        R.SourceFixtureInventory.Add(MoveTemp(F));}
}
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownTileMatrixBoundary,"LivingTown.Native.TileMatrixBoundary",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownTileMatrixBoundary::RunTest(const FString&)
{
    FString Error;const auto Original=IdentityPlacement();auto P=Original;
    TestTrue(TEXT("identity source/native metadata"),LivingTownTiles::ValidatePlacement(P,Error));
    P.SourceWorldMatrixRowMajor={2,0,0,1,0,3,0,2,0,0,4,3,0,0,0,1};
    P.QualifiedNativeTransform=FTransform(FQuat::Identity,FVector(100,300,200),FVector(2,4,3));
    TestTrue(TEXT("nonuniform scale and single metre/cm basis conversion"),LivingTownTiles::ValidatePlacement(P,Error));
    P.QualifiedNativeTransform.SetTranslation(FVector(100,200,300));
    TestFalse(TEXT("double/wrong basis conversion refuses"),LivingTownTiles::ValidatePlacement(P,Error));
    P=Original;P.SourceWorldMatrixRowMajor[1]=0.125;
    TestFalse(TEXT("shear refuses"),LivingTownTiles::ValidatePlacement(P,Error));
    P=Original;P.SourceWorldMatrixRowMajor[0]=-1;
    TestFalse(TEXT("reflection unqualified"),LivingTownTiles::ValidatePlacement(P,Error));
    P=Original;P.SourceWorldMatrixRowMajor[0]=0;
    TestFalse(TEXT("singular scale refuses"),LivingTownTiles::ValidatePlacement(P,Error));
    P=Original;P.SourceWorldMatrixRowMajor[12]=1;
    TestFalse(TEXT("nonaffine input refuses"),LivingTownTiles::ValidatePlacement(P,Error));
    P=Original;P.SourceWorldMatrixRowMajor.Pop();
    TestFalse(TEXT("truncated raw evidence refuses"),LivingTownTiles::ValidatePlacement(P,Error));
    P=Original;P.SourcePlacementId=TEXT("town_10_urban_core:node:8534");
    TestFalse(TEXT("existing cafe source refuses"),LivingTownTiles::ValidatePlacement(P,Error));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownTileDemandBoundary,"LivingTown.Native.TileDemandBoundary",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownTileDemandBoundary::RunTest(const FString&)
{
    FString Error;FLivingTownTileDemand D;
    const TArray<FLivingTownTileUnitRef> Graph={Unit(TEXT("terrain")),Unit(TEXT("left"),{TEXT("terrain")}),Unit(TEXT("right"),{TEXT("terrain")}),Unit(TEXT("owner"),{TEXT("left"),TEXT("right")})};
    TestTrue(TEXT("dependency graph"),D.Initialize(Graph,Error));
    TMap<FString,TArray<FString>> Supports;Supports.Add(TEXT("a"),{TEXT("owner")});
    TestTrue(TEXT("diamond closure"),D.SetSupports(Supports,Error));
    TestEqual(TEXT("shared dependency once per support"),D.Counts().FindRef(TEXT("terrain")),1);
    const uint64 Old=D.BeginRequest(TEXT("owner"));TestTrue(TEXT("wanted completion"),D.Accepts(TEXT("owner"),Old));
    D.Cancel(TEXT("owner"));TestFalse(TEXT("cancel invalidates queued callback"),D.Accepts(TEXT("owner"),Old));
    const uint64 Fresh=D.BeginRequest(TEXT("owner"));TestTrue(TEXT("fresh request token"),Fresh!=0&&Fresh!=Old);
    TestFalse(TEXT("old callback cannot install replacement"),D.Accepts(TEXT("owner"),Old));
    Supports.Add(TEXT("b"),{TEXT("terrain")});TestTrue(TEXT("second support"),D.SetSupports(Supports,Error));
    TestEqual(TEXT("two independent references"),D.Counts().FindRef(TEXT("terrain")),2);
    Supports.Remove(TEXT("a"));TestTrue(TEXT("owner leaves"),D.SetSupports(Supports,Error));
    TestEqual(TEXT("remaining terrain reference"),D.Counts().FindRef(TEXT("terrain")),1);
    TestFalse(TEXT("completion after leaving support"),D.Accepts(TEXT("owner"),Fresh));
    auto Bad=Supports;Bad.Add(TEXT("bad"),{TEXT("missing")});
    TestFalse(TEXT("missing dependency refuses atomically"),D.SetSupports(Bad,Error));
    TestEqual(TEXT("old demand preserved"),D.Counts().FindRef(TEXT("terrain")),1);
    D.Reset();TestFalse(TEXT("teardown invalidates completion"),D.Accepts(TEXT("owner"),Fresh));
    TestTrue(TEXT("restart graph"),D.Initialize(Graph,Error));Supports.Empty();Supports.Add(TEXT("a"),{TEXT("owner")});D.SetSupports(Supports,Error);
    const uint64 Restart=D.BeginRequest(TEXT("owner"));TestTrue(TEXT("world restart never reuses token"),Restart!=Fresh&&Restart!=Old);
    const TArray<FLivingTownTileUnitRef> Cycle={Unit(TEXT("a"),{TEXT("b")}),Unit(TEXT("b"),{TEXT("a")})};
    TestFalse(TEXT("cycle refuses"),D.Initialize(Cycle,Error));
    TestTrue(TEXT("failed replacement preserves current token"),D.Accepts(TEXT("owner"),Restart));
    const TArray<FLivingTownTileUnitRef> Alias={Unit(TEXT("A")),Unit(TEXT("a"))};
    TestFalse(TEXT("case alias refuses"),D.Initialize(Alias,Error));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownTileMetadataBoundary,"LivingTown.Native.TileMetadataBoundary",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownTileMetadataBoundary::RunTest(const FString&)
{
    FString Error;TStrongObjectPtr<ULivingTownTileRootData> Root(NewObject<ULivingTownTileRootData>());
    TestFalse(TEXT("default unauthored root cannot activate"),LivingTownTiles::ValidateRoot(*Root,Error));
    PopulateRootMetadataFixture(*Root);
    TestTrue(TEXT("synthetic complete logical metadata only"),LivingTownTiles::ValidateRoot(*Root,Error));
    Root->Qualification.bMaterialsQualified=false;
    TestFalse(TEXT("material proof absent"),LivingTownTiles::ValidateRoot(*Root,Error));Root->Qualification.bMaterialsQualified=true;
    const FString Original=Root->Units.Last().DeclaredInstanceSourceIds[0];Root->Units.Last().DeclaredInstanceSourceIds[0]=TEXT("town_10_urban_core:node:8822");
    TestFalse(TEXT("cafe duplication in root"),LivingTownTiles::ValidateRoot(*Root,Error));Root->Units.Last().DeclaredInstanceSourceIds[0]=Original;
    Root->Units[1].Asset=Root->Units[0].Asset;
    TestFalse(TEXT("same asset under two unit identities"),LivingTownTiles::ValidateRoot(*Root,Error));
    TestFalse(TEXT("source drive path refuses"),LivingTownTiles::IsPilotAssetPath(FSoftObjectPath(TEXT("F:/authoring/Model.Model"))));
    TestFalse(TEXT("cafe asset path refuses"),LivingTownTiles::IsPilotAssetPath(FSoftObjectPath(TEXT("/Game/LivingTown_UEPilot/CafeSource_v001/M.M"))));
    TestFalse(TEXT("subobject refuses"),LivingTownTiles::IsPilotAssetPath(FSoftObjectPath(TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/M.M:Sub"))));
    // Root/mesh async IO, actual world cancellation and physical registration
    // require the later imported-asset integration run; not claimed here.
    return true;
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownTileUnitBoundary,"LivingTown.Native.TileUnitBoundary",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownTileUnitBoundary::RunTest(const FString&)
{
    FString Error;TStrongObjectPtr<ULivingTownRenderUnitData> Data(NewObject<ULivingTownRenderUnitData>());
    Data->UnitId=TEXT("owner_one");Data->Qualification=MetadataFixture();
    FLivingTownTileGeometry G;G.EntryId=TEXT("whole_one");G.SourceMeshKey=TEXT("WHOLE_static_000001");
    G.SourcePlacementIds={TEXT("town_04_reserve:node:123")};
    G.Mesh=TSoftObjectPtr<UStaticMesh>(FSoftObjectPath(TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/M_one.M_one")));
    G.NativeMeshReceiptSha256=FString::ChrN(64,'a');G.NativeRenderSha256=FString::ChrN(64,'b');G.NativeCollisionGuid=FString::ChrN(32,'c');
    G.ActualNativeBoundsCm=FBox(FVector(-1),FVector(1));G.Placements={IdentityPlacement()};
    G.Placements[0].SourcePlacementId=TEXT("assembly:frame:WHOLE_static_000001");
    G.QualifiedMaterialPaths={FSoftObjectPath(TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/Mat.Mat"))};
    G.QualifiedMaterialSlotNames={TEXT("Mat")};G.QualifiedMaterialBlendModes={uint8(BLEND_Opaque)};
    Data->Geometry={G};auto Expected=Unit(Data->UnitId);Expected.DeclaredEntryIds={G.EntryId};Expected.ActualNativeBoundsCm=G.ActualNativeBoundsCm;
    TestTrue(TEXT("synthetic unit metadata only; no imported asset exists"),LivingTownTiles::ValidateUnit(*Data,Expected,Data->Qualification,Error));
    Data->Geometry[0].NativeRenderSha256=TEXT("short");
    TestFalse(TEXT("missing full native hash refuses"),LivingTownTiles::ValidateUnit(*Data,Expected,Data->Qualification,Error));Data->Geometry[0]=G;
    Data->Geometry[0].QualifiedMaterialBlendModes[0]=uint8(BLEND_MAX);
    TestFalse(TEXT("invalid material mode refuses"),LivingTownTiles::ValidateUnit(*Data,Expected,Data->Qualification,Error));Data->Geometry[0]=G;
    Data->Geometry[0].Placements[0].SourceWorldMatrixRowMajor[3]=1;
    Data->Geometry[0].Placements[0].QualifiedNativeTransform.SetTranslation(FVector(100,0,0));
    TestFalse(TEXT("baked static cannot apply source translation twice"),LivingTownTiles::ValidateUnit(*Data,Expected,Data->Qualification,Error));Data->Geometry[0]=G;
    Data->Geometry[0].SourcePlacementIds.Add(TEXT("town_10_urban_core:node:8534"));
    TestFalse(TEXT("static provenance cannot include existing cafe"),LivingTownTiles::ValidateUnit(*Data,Expected,Data->Qualification,Error));Data->Geometry[0]=G;
    Expected.ActualNativeBoundsCm.Max.X+=1;
    TestFalse(TEXT("catalog bounds must equal actual unit union"),LivingTownTiles::ValidateUnit(*Data,Expected,Data->Qualification,Error));Expected.ActualNativeBoundsCm=G.ActualNativeBoundsCm;
    Data->Geometry[0].Kind=ELivingTownTileEntryKind::DeferredDoor;
    TestFalse(TEXT("door must remain explicitly declared"),LivingTownTiles::ValidateUnit(*Data,Expected,Data->Qualification,Error));
    Expected.DeclaredDeferredDoorEntryIds={G.EntryId};
    TestTrue(TEXT("one separately addressable deferred door metadata"),LivingTownTiles::ValidateUnit(*Data,Expected,Data->Qualification,Error));
    return true;
}
#endif
