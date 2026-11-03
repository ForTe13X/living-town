#include "LivingTownFullTownData.h"
#include "LivingTownTileData.h"
#include "Engine/World.h"
#include "Misc/PackageName.h"
#include <limits>

namespace
{
bool Refuse(FString& Error, const TCHAR* Why) { Error = Why; return false; }
bool Id(const FString& Value)
{
    if (Value.IsEmpty() || Value.Len() > 512) return false;
    for (TCHAR C : Value) if (C < 32 || C > 126) return false;
    return true;
}
bool Asset(const FSoftObjectPath& Value)
{
    const FString Path = Value.ToString();
    return Path.StartsWith(TEXT("/Game/LivingTown_UEPilot/")) &&
        Value.GetSubPathString().IsEmpty() && FPackageName::IsValidObjectPath(Path) &&
        Value.GetAssetName() == FPackageName::GetShortName(Value.GetLongPackageName());
}
bool Unique(const TArray<FString>& Values, int32 Count)
{
    TSet<FString> Seen;
    if (Values.Num() != Count) return false;
    for (const FString& Value : Values) if (!Id(Value) || Seen.Contains(Value)) return false; else Seen.Add(Value);
    return true;
}
bool ValidTransform(const FTransform& T)
{
    return !T.ContainsNaN() && T.GetRotation().IsNormalized() &&
        T.GetScale3D().X > 0 && T.GetScale3D().Y > 0 && T.GetScale3D().Z > 0;
}
bool Close(double A, double B)
{
    return FMath::IsFinite(A) && FMath::IsFinite(B) &&
        FMath::Abs(A-B) <= 64.0 * std::numeric_limits<double>::epsilon() * FMath::Max(1.0, FMath::Max(FMath::Abs(A), FMath::Abs(B)));
}
bool Vec(const FVector& A, const FVector& B) { return Close(A.X,B.X) && Close(A.Y,B.Y) && Close(A.Z,B.Z); }
}

bool LivingTownFullTown::SameQualifiedTransform(const FTransform& A, const FTransform& B)
{
    const FQuat X = A.GetRotation(), Y = B.GetRotation();
    const bool Q = (Close(X.X,Y.X) && Close(X.Y,Y.Y) && Close(X.Z,Y.Z) && Close(X.W,Y.W)) ||
        (Close(X.X,-Y.X) && Close(X.Y,-Y.Y) && Close(X.Z,-Y.Z) && Close(X.W,-Y.W));
    return ValidTransform(A) && ValidTransform(B) && Vec(A.GetTranslation(),B.GetTranslation()) && Vec(A.GetScale3D(),B.GetScale3D()) && Q;
}

double LivingTownFullTown::DistanceToBoundsXY(const FVector& P, const FBox& B)
{
    const double X = FMath::Max3(B.Min.X-P.X, 0.0, P.X-B.Max.X);
    const double Y = FMath::Max3(B.Min.Y-P.Y, 0.0, P.Y-B.Max.Y);
    return FMath::Sqrt(X*X+Y*Y);
}

bool LivingTownFullTown::ValidateManifest(const ULivingTownFullTownData& D, FString& Error)
{
    if (D.SchemaVersion != 1 || D.Scope != TEXT("IntegrationSubset") ||
        D.ProfileId != TEXT("U0131_U0142_Ground151_ExternalCafe81_v001") || !Asset(D.RootWorld) ||
        D.SourceDispatchSha256 != TEXT("63a0f2acb3899f0eecab2542a38b6f87e6a74f2266ca035ee97a6e12573f5b1a") ||
        D.SourceWorldLedgerSha256 != TEXT("89c1bdaf5e93f0bc6a6bf2afe7b7e8e48aadeb7ffcb8ace1b96f92836eaf2b0e") ||
        !LivingTownTiles::IsSha256(D.ManifestAdmissionSha256) || !LivingTownTiles::IsSha256(D.ExternalCafeBindingSha256) ||
        !Unique(D.ExternalCafePartIds,262) || !Unique(D.ExternalCafeRoleIds,262) || D.Units.Num() != 3)
        return Refuse(Error,TEXT("fulltown_subset_manifest_identity_or_external_cafe"));
    TSet<FString> UnitIds, Roles; TSet<int32> Indices;
    for (const FString& R : D.ExternalCafeRoleIds)
    {
        if (!R.StartsWith(TEXT("CAFE::"))) return Refuse(Error,TEXT("fulltown_external_cafe_role"));
        Roles.Add(R);
    }
    FString Ground;
    for (const auto& U : D.Units)
    {
        const int32 Expected = U.DispatchIndex == 131 ? 66 : U.DispatchIndex == 142 ? 80 : U.DispatchIndex == 151 ? 155 : 0;
        const FString Package = FString::Printf(TEXT("/Game/LivingTown_UEPilot/FullTownWorld_v001/Units/L_U%04d"),U.DispatchIndex);
        if (!Expected || !Id(U.UnitId) || UnitIds.Contains(U.UnitId) || Indices.Contains(U.DispatchIndex) ||
            U.Map.GetLongPackageName() != Package || !Asset(U.Map.ToSoftObjectPath()) ||
            U.SourceMapBytes <= 0 || U.SourceMapBytes > 8*1024*1024 || !LivingTownTiles::IsSha256(U.SourceMapSha256) ||
            !LivingTownTiles::IsSha256(U.RootColdAdmissionSha256) || !LivingTownTiles::IsSha256(U.ColdObservationSha256) ||
            !U.ActualBoundsCm.IsValid || U.ActualBoundsCm.Min.ContainsNaN() || U.ActualBoundsCm.Max.ContainsNaN() ||
            U.ActualBoundsCm.Min.X > U.ActualBoundsCm.Max.X || U.ActualBoundsCm.Min.Y > U.ActualBoundsCm.Max.Y ||
            U.ActualBoundsCm.Min.Z > U.ActualBoundsCm.Max.Z || U.Roles.Num() != Expected ||
            U.bPinnedSupport != (U.DispatchIndex == 151) || U.RequiredUnits.Num() > 2)
            return Refuse(Error,TEXT("fulltown_subset_unit_identity_cold_or_bounds"));
        UnitIds.Add(U.UnitId); Indices.Add(U.DispatchIndex);
        if (U.DispatchIndex == 151) Ground = U.UnitId;
        for (const auto& R : U.Roles)
        {
            if (!Id(R.RoleId) || R.RoleId.StartsWith(TEXT("CAFE::")) || Roles.Contains(R.RoleId) || !Asset(R.Mesh) ||
                R.SourceIds.IsEmpty() || R.SourceIds.Num() > 6000 || !ValidTransform(R.WorldTransform) ||
                R.Slots.IsEmpty() || R.Slots.Num() > 128 || R.CollisionProfile != TEXT("BlockAll") ||
                R.CollisionEnabled != ECollisionEnabled::QueryAndPhysics)
                return Refuse(Error,TEXT("fulltown_role_identity_transform_collision"));
            Roles.Add(R.RoleId);
            // First profile is three static-only maps. A future HISM profile must
            // get its own explicit map/derivative Cold admission, not bypass this.
            if (R.Kind != ELivingTownFullTownComponentKind::StaticMesh || !R.Instances.IsEmpty())
                return Refuse(Error,TEXT("fulltown_initial_subset_is_static_only"));
            for (int32 I=0; I<R.Slots.Num(); ++I)
            {
                const auto& S=R.Slots[I];
                if (S.SlotIndex != I || !Asset(S.OriginalDefault) || !S.Override.IsNull() || !S.OverrideColdAdmissionSha256.IsEmpty())
                    return Refuse(Error,TEXT("fulltown_exact_ordered_static_default_slots"));
            }
            for (const FString& SourceId : R.SourceIds) if (!Id(SourceId)) return Refuse(Error,TEXT("fulltown_source_id"));
        }
    }
    if (Ground.IsEmpty() || Roles.Num() != 563) return Refuse(Error,TEXT("fulltown_subset_union"));
    for (const auto& U : D.Units)
    {
        if (U.DispatchIndex == 151 ? !U.RequiredUnits.IsEmpty() : (U.RequiredUnits.Num()!=1 || U.RequiredUnits[0]!=Ground))
            return Refuse(Error,TEXT("fulltown_subset_pinned_ground_dependency"));
    }
    return true;
}

#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownFullTownTransformTest,"LivingTown.FullTown.TransformAndDistance",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownFullTownTransformTest::RunTest(const FString&)
{
    const FTransform T(FQuat::Identity,FVector(1,2,3),FVector(1,1,1));
    TestTrue(TEXT("same qualified transform"),LivingTownFullTown::SameQualifiedTransform(T,T));
    TestFalse(TEXT("real displacement refused"),LivingTownFullTown::SameQualifiedTransform(T,FTransform(FVector(1,2,3.01))));
    TestEqual(TEXT("XY distance ignores elevation"),LivingTownFullTown::DistanceToBoundsXY(FVector(3,4,100),FBox(FVector(0,0,0),FVector(1,1,1))),FMath::Sqrt(13.0));
    auto* Empty=NewObject<ULivingTownFullTownData>(); FString Error;
    TestFalse(TEXT("empty/future descriptor never accepted"),LivingTownFullTown::ValidateManifest(*Empty,Error));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownFullTownSchemaTest,"LivingTown.FullTown.SubsetSchemaRefusals",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownFullTownSchemaTest::RunTest(const FString&)
{
    // Synthetic metadata only. No package is loaded/saved and no value here is a
    // production admission. Exercise the actual validator, not a shadow model.
    auto* D=NewObject<ULivingTownFullTownData>();
    D->RootWorld=FSoftObjectPath(TEXT("/Game/LivingTown_UEPilot/Tests/SyntheticRoot.SyntheticRoot"));
    D->SourceDispatchSha256=TEXT("63a0f2acb3899f0eecab2542a38b6f87e6a74f2266ca035ee97a6e12573f5b1a");
    D->SourceWorldLedgerSha256=TEXT("89c1bdaf5e93f0bc6a6bf2afe7b7e8e48aadeb7ffcb8ace1b96f92836eaf2b0e");
    const FString SyntheticSha=FString::ChrN(64,TEXT('a'));
    D->ManifestAdmissionSha256=SyntheticSha; D->ExternalCafeBindingSha256=SyntheticSha;
    for (int32 I=0; I<262; ++I)
    { D->ExternalCafePartIds.Add(FString::Printf(TEXT("synthetic_part_%d"),I)); D->ExternalCafeRoleIds.Add(FString::Printf(TEXT("CAFE::synthetic_%d"),I)); }
    for (int32 Index : {131,142,151})
    {
        auto& U=D->Units.AddDefaulted_GetRef(); U.DispatchIndex=Index; U.UnitId=FString::Printf(TEXT("synthetic_unit_%d"),Index);
        const FString Package=FString::Printf(TEXT("/Game/LivingTown_UEPilot/FullTownWorld_v001/Units/L_U%04d"),Index);
        U.Map=TSoftObjectPtr<UWorld>(FSoftObjectPath(Package+TEXT(".")+FPackageName::GetShortName(Package)));
        U.SourceMapBytes=100; U.SourceMapSha256=SyntheticSha; U.RootColdAdmissionSha256=SyntheticSha; U.ColdObservationSha256=SyntheticSha;
        U.ActualBoundsCm=FBox(FVector(-1,-1,-1),FVector(1,1,1)); U.bPinnedSupport=Index==151;
        if (Index!=151) U.RequiredUnits.Add(TEXT("synthetic_unit_151"));
        const int32 Count=Index==131?66:Index==142?80:155;
        for (int32 I=0; I<Count; ++I)
        {
            auto& R=U.Roles.AddDefaulted_GetRef(); R.RoleId=FString::Printf(TEXT("synthetic_role_%d_%d"),Index,I);
            R.Mesh=FSoftObjectPath(TEXT("/Game/LivingTown_UEPilot/Tests/SyntheticMesh.SyntheticMesh")); R.SourceIds.Add(R.RoleId);
            for (int32 S=0; S<2; ++S)
            { auto& Slot=R.Slots.AddDefaulted_GetRef(); Slot.SlotIndex=S; Slot.OriginalDefault=FSoftObjectPath(TEXT("/Game/LivingTown_UEPilot/Tests/SyntheticMaterial.SyntheticMaterial")); }
        }
    }
    FString Error;
    TestTrue(TEXT("complete synthetic metadata shape accepted without asset operations"),LivingTownFullTown::ValidateManifest(*D,Error));
    auto& Role=D->Units[0].Roles[0]; const FString OriginalRole=Role.RoleId;
    Role.RoleId=D->ExternalCafeRoleIds[0]; TestFalse(TEXT("external cafe cannot become streamed geometry"),LivingTownFullTown::ValidateManifest(*D,Error)); Role.RoleId=OriginalRole;
    Swap(Role.Slots[0].SlotIndex,Role.Slots[1].SlotIndex); TestFalse(TEXT("alphabetical/permuted slots refused"),LivingTownFullTown::ValidateManifest(*D,Error)); Swap(Role.Slots[0].SlotIndex,Role.Slots[1].SlotIndex);
    D->Units[2].RequiredUnits.Add(D->Units[0].UnitId); TestFalse(TEXT("pinned support cycle refused"),LivingTownFullTown::ValidateManifest(*D,Error)); D->Units[2].RequiredUnits.Empty();
    D->Scope=TEXT("FullTown"); TestFalse(TEXT("subset cannot claim full town"),LivingTownFullTown::ValidateManifest(*D,Error)); D->Scope=TEXT("IntegrationSubset");
    D->Units[0].SourceMapSha256.Empty(); TestFalse(TEXT("missing future Cold binding refused"),LivingTownFullTown::ValidateManifest(*D,Error));
    return true;
}
#endif
