#include "LivingTownFullTownData.h"
#include "LivingTownTileData.h"
#include "Engine/World.h"
#include "Misc/PackageName.h"
#include "UObject/Package.h"
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

const TCHAR* const B749Profile=TEXT("B749_U0131_66_Ground156_ExternalCafe81_v001");
const TCHAR* const B749Root=TEXT("/Game/LivingTown_UEPilot/FullTownIntegrationB749_v001/L_B749_Subset_v001.L_B749_Subset_v001");
// Actual composite and independent cold unit admissions; root/DA cold is externally verified.
// Refuse any stale or foreign pin before admitting this integration profile.
const TCHAR* const B749DispatchSha=TEXT("8a2ef2f60b004896faffd0c817be43b4b40edf6e9779363b93b9ec1f2320f29c");
const TCHAR* const B749LedgerSha=TEXT("504314a4ae3b4e2ee3cc6f2097dac3bcde46137925db6588fe8656a0eb1bff6f");
const TCHAR* const B749ManifestAdmissionSha=TEXT("b6282e9373b85e31b762498aa1cb5ba1c8ed76dce26ed92b28e13257dc1e2930");
const TCHAR* const B749CafeBindingSha=TEXT("acf2a319305f6811be7642302bdfb6ca39212baea69c832cacfddb6d4cb28c3c");
const TCHAR* const B749FinishColdSha=TEXT("f12453a2379cfb09ae4aec2640e757be32628e9727e4201945fbeb7a1ffbbf5b");
struct FB749UnitPin
{
    int32 Index; const TCHAR* Id; const TCHAR* Map; int32 Roles;
    int64 Bytes; const TCHAR* SourceSha; const TCHAR* RootColdSha; const TCHAR* ObservationSha;
};
// The reused U0131 binds its exact retained bytes,
// not a new export or an invented positive receipt. Never substitute old hashes
// for the two new derived maps or their composite source identity.
const FB749UnitPin B749Pins[]={
    {131,TEXT("OWNER_lot_21_belleepoque"),TEXT("/Game/LivingTown_UEPilot/FullTownWorld_v001/Units/L_U0131.L_U0131"),66,
        66210,TEXT("913eadaa79e7d90aa820cff1e08a221f48cf37e5079b39589e3d97672c447339"),TEXT("0981e095aa1e319c109804c6f4f79caa1ce56d2f6a5a18862ae0e347cceb924f"),TEXT("415ae59f884e5add76411ef0e6c2daf76ea954f7ec2ad16baf6a7de3519af06c")},
    {193,TEXT("MILL_COURT_B749"),TEXT("/Game/LivingTown_UEPilot/FullTownIntegrationB749_v001/Units/L_B749_v001.L_B749_v001"),749,
        701402,TEXT("7e0b6bf1f314a0e7fd631ce4cfecc738971f36386a20724b579117bca1d98604"),TEXT("863f0b53135e1445254cc15f3c362498fbb1436c075655add2cfea1602e56ab8"),TEXT("ebb3fcbe2ebeca5cfb13a2e0990e98b2fc4ceab9aae3aefb08c3e0f2091113de")},
    {194,TEXT("PERSISTENT_GROUND"),TEXT("/Game/LivingTown_UEPilot/FullTownIntegrationB749_v001/Units/L_Ground156_v001.L_Ground156_v001"),156,
        145199,TEXT("28301d6a504dfb4edbad6c0bac98b231d5f05a5bf88d52c7e14a29bdd5af6662"),TEXT("63991dce5deec1d4e30b864f9b19fcf3ac7317c86b3a334b204a83b4239b165e"),TEXT("62c991b61f02a54f110e5d159f8aa1e56dd53bb8f01609fefb390f25d6ef3c39")}
};
// Separate uncooked continuous-roof trial; original B749/cooked pins remain unchanged.
const TCHAR* const B749RoofProfile=TEXT("B749_ContinuousRoofRuntime_v001");
const TCHAR* const B749RoofRoot=TEXT("/Game/LivingTown_UEPilot/FullTownIntegrationB749_ContinuousRoofRuntime_v001/L_B749_ContinuousRoofRuntime_v001.L_B749_ContinuousRoofRuntime_v001");
const TCHAR* const B749RoofDispatchSha=TEXT("14c9b4107280b0040e5c815a1a23cf3eba365a9b79851a879dd46763d0320d6c");
const TCHAR* const B749RoofLedgerSha=TEXT("5ef41f374840deb7cc63eb4cd4dfb9f71e309c0d697577fc0e119df011fa6c39");
const TCHAR* const B749RoofManifestAdmissionSha=TEXT("0d21f61d3f92b26b4b4350dd7112791974d72ff051a7022affefd1f03b8e5e4b");
const FB749UnitPin B749RoofUnitPin={193,TEXT("MILL_COURT_B749"),TEXT("/Game/LivingTown_UEPilot/FullTownIntegrationB749_ContinuousRoof_v001/Units/L_B749_ContinuousRoof_v001.L_B749_ContinuousRoof_v001"),749,
    701814,TEXT("1a6c9f9d2bdb3ffa95c41f09118bdbc8afad6189c6bd331c96e21dabe9865049"),TEXT("f7c212dfd290f8e3e15cd72cf65ddfe69d967aec254cc24b40a38ed8910a22a4"),TEXT("953f3ba42f1bcabf47dcc9857b5c59ea41e8951a904007d19a8c834202fd82ee")};
const FB749UnitPin& B749Pin(const ULivingTownFullTownData& D,int32 Index)
{ return D.ProfileId==B749RoofProfile && Index==1 ? B749RoofUnitPin : B749Pins[Index]; }
const TCHAR* B749RoofMesh(int32 Index)
{ return Index==447 ? TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_ContinuousRoof_v003/StaticMeshes/MillCourt_B_ContinuousRoof_Geometry_v001/StaticMeshes/MCB_Continu_47_v001_001.MCB_Continu_47_v001_001") : TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_ContinuousRoof_v003/StaticMeshes/MillCourt_B_ContinuousRoof_Geometry_v001/StaticMeshes/MCB_Continu_48_v001_001.MCB_Continu_48_v001_001"); }
const TCHAR* B749RoofSlot(int32 Index)
{ return Index==447 ? TEXT("-1") : TEXT("-1"); }
const TCHAR* const B749RoofMaterial=TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_ContinuousRoof_v003/Materials/M_MC_ContinuousSlate_v003.M_MC_ContinuousSlate_v003");
struct FB749Finish { const TCHAR* Path; int32 Count; };
const FB749Finish B749Finishes[]={
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_Material176_v001/Materials/M_CutGranite.M_CutGranite"),141},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_StaticFinish_v002/Materials/M_Plaster.M_Plaster"),46},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_Material176_v001/Materials/M_ExteriorPlaster.M_ExteriorPlaster"),22},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_StaticFinish_v002/Materials/M_Brass.M_Brass"),43},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_StaticFinish_v002/Materials/M_OakJoinery.M_OakJoinery"),111},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_StaticFinish_v002/Materials/M_OakFloor.M_OakFloor"),5},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_Material176_v001/Materials/M_HonedWorktop.M_HonedWorktop"),13}
};

// Testable metadata contract, not an admission bypass. Public ValidateManifest
// additionally requires every actual pin below; no asset operation occurs here.
bool B749Shape(const ULivingTownFullTownData& D,FString& Error)
{
    const bool Roof=D.ProfileId==B749RoofProfile;
    if (D.SchemaVersion!=1 || D.Scope!=TEXT("IntegrationSubset") || (!Roof && D.ProfileId!=B749Profile) ||
        D.RootWorld.ToString()!=(Roof?B749RoofRoot:B749Root) || !Asset(D.RootWorld) ||
        !LivingTownTiles::IsSha256(D.SourceDispatchSha256) || !LivingTownTiles::IsSha256(D.SourceWorldLedgerSha256) ||
        !LivingTownTiles::IsSha256(D.ManifestAdmissionSha256) || !LivingTownTiles::IsSha256(D.ExternalCafeBindingSha256) ||
        !Unique(D.ExternalCafePartIds,262) || !Unique(D.ExternalCafeRoleIds,262) || D.Units.Num()!=3)
        return Refuse(Error,TEXT("fulltown_b749_manifest_shape"));
    TSet<FString> Roles; int32 FinishCounts[7]={}; int32 EmptyB=0;
    for (const FString& RoleId:D.ExternalCafeRoleIds)
    {
        if (!RoleId.StartsWith(TEXT("CAFE::"))) return Refuse(Error,TEXT("fulltown_b749_external_cafe_role"));
        Roles.Add(RoleId);
    }
    for (int32 I=0; I<3; ++I)
    {
        const auto& U=D.Units[I]; const auto& Pin=B749Pin(D,I);
        if (U.DispatchIndex!=Pin.Index || U.UnitId!=Pin.Id || U.Map.ToSoftObjectPath().ToString()!=Pin.Map ||
            !Asset(U.Map.ToSoftObjectPath()) || U.Roles.Num()!=Pin.Roles || U.SourceMapBytes<=0 ||
            U.SourceMapBytes>8*1024*1024 || !LivingTownTiles::IsSha256(U.SourceMapSha256) ||
            !LivingTownTiles::IsSha256(U.RootColdAdmissionSha256) || !LivingTownTiles::IsSha256(U.ColdObservationSha256) ||
            !U.ActualBoundsCm.IsValid || U.ActualBoundsCm.Min.ContainsNaN() || U.ActualBoundsCm.Max.ContainsNaN() ||
            U.ActualBoundsCm.Min.X>U.ActualBoundsCm.Max.X || U.ActualBoundsCm.Min.Y>U.ActualBoundsCm.Max.Y ||
            U.ActualBoundsCm.Min.Z>U.ActualBoundsCm.Max.Z || U.bPinnedSupport!=(I==2) ||
            (I==2 ? !U.RequiredUnits.IsEmpty() : (U.RequiredUnits.Num()!=1 || U.RequiredUnits[0]!=TEXT("PERSISTENT_GROUND"))))
            return Refuse(Error,TEXT("fulltown_b749_unit_identity_cold_bounds_dependency"));
        for (int32 J=0; J<U.Roles.Num(); ++J)
        {
            const auto& R=U.Roles[J];
            // New profile collision is explicit cold-bound metadata, never a
            // blanket repair/classification. Runtime compares its actual value.
            const int32 Collision=int32(R.CollisionEnabled.GetValue());
            if (!Id(R.RoleId) || R.RoleId.StartsWith(TEXT("CAFE::")) || Roles.Contains(R.RoleId) ||
                !Asset(R.Mesh) || R.SourceIds.IsEmpty() || R.SourceIds.Num()>6000 || !ValidTransform(R.WorldTransform) ||
                R.Slots.IsEmpty() || R.Slots.Num()>128 || R.CollisionProfile.IsNone() ||
                !Id(R.CollisionProfile.ToString()) || Collision<int32(ECollisionEnabled::NoCollision) ||
                Collision>int32(ECollisionEnabled::QueryAndProbe) ||
                R.Kind!=ELivingTownFullTownComponentKind::StaticMesh || !R.Instances.IsEmpty())
                return Refuse(Error,TEXT("fulltown_b749_static_role_identity_transform_collision"));
            Roles.Add(R.RoleId);
            if (I==1)
            {
                const bool Bedding=J==748;
                const FString Alias=FString::Printf(TEXT("M%04d"),J);
                const FString ExpectedRole=Bedding?TEXT("MCB::Bedding::Accepted_Bedding_ThreeAuthoredLODs"):TEXT("MCB::Building::")+Alias;
                const FString ExpectedMesh=Roof && (J==447 || J==448) ? FString(B749RoofMesh(J)) : Bedding?TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_Bedding_v001/SM_Bedding.SM_Bedding"):
                    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtBAssets_v001/Building/Building_NamesOnly/StaticMeshes/")+Alias+TEXT(".")+Alias;
                if (R.RoleId!=ExpectedRole || R.Mesh.ToString()!=ExpectedMesh || R.Slots.Num()!=(Bedding?3:1))
                    return Refuse(Error,TEXT("fulltown_b749_exact_mesh_role_and_slot_shape"));
                if (Roof && (J==447 || J==448) && (R.Slots[0].SlotName!=FName(B749RoofSlot(J)) ||
                    R.Slots[0].OriginalDefault.ToString()!=B749RoofMaterial || !R.Slots[0].Override.IsNull() ||
                    !R.Slots[0].OverrideColdAdmissionSha256.IsEmpty() || R.Slots[0].BlendMode!=0))
                    return Refuse(Error,TEXT("fulltown_roof_exact_default_slate_slot"));
                if (R.Slots[0].Override.IsNull()) ++EmptyB;
            }
            for (int32 S=0; S<R.Slots.Num(); ++S)
            {
                const auto& Slot=R.Slots[S];
                if (Slot.SlotIndex!=S || !Asset(Slot.OriginalDefault))
                    return Refuse(Error,TEXT("fulltown_b749_exact_ordered_original_slots"));
                if (Slot.Override.IsNull())
                {
                    if (!Slot.OverrideColdAdmissionSha256.IsEmpty())
                        return Refuse(Error,TEXT("fulltown_b749_empty_override_has_admission"));
                    continue;
                }
                if (I!=1 || J==748 || R.Slots.Num()!=1 || Slot.OverrideColdAdmissionSha256!=B749FinishColdSha)
                    return Refuse(Error,TEXT("fulltown_b749_override_scope_or_cold_binding"));
                int32 Finish=INDEX_NONE;
                for (int32 F=0; F<7; ++F) if (Slot.Override.ToString()==B749Finishes[F].Path) { Finish=F; break; }
                if (Finish==INDEX_NONE) return Refuse(Error,TEXT("fulltown_b749_unknown_finish"));
                ++FinishCounts[Finish];
            }
            for (const FString& SourceId:R.SourceIds) if (!Id(SourceId)) return Refuse(Error,TEXT("fulltown_b749_source_id"));
        }
    }
    if (Roles.Num()!=1233 || EmptyB!=368) return Refuse(Error,TEXT("fulltown_b749_union_or_empty_override_count"));
    for (int32 F=0; F<7; ++F) if (FinishCounts[F]!=B749Finishes[F].Count)
        return Refuse(Error,TEXT("fulltown_b749_exact_seven_finish_counts"));
    return true;
}

bool ValidateB749(const ULivingTownFullTownData& D,FString& Error)
{
    if (!B749Shape(D,Error)) return false;
    const bool Roof=D.ProfileId==B749RoofProfile;
    const TCHAR* Dispatch=Roof?B749RoofDispatchSha:B749DispatchSha;
    const TCHAR* Ledger=Roof?B749RoofLedgerSha:B749LedgerSha;
    const TCHAR* Admission=Roof?B749RoofManifestAdmissionSha:B749ManifestAdmissionSha;
    if (Roof && (!LivingTownTiles::IsSha256(Dispatch) || !LivingTownTiles::IsSha256(Ledger) || !LivingTownTiles::IsSha256(Admission)))
        return Refuse(Error,TEXT("fulltown_roof_DRAFT_REFUSE_pending_actual_author_pins"));
    if (!LivingTownTiles::IsSha256(B749DispatchSha) || !LivingTownTiles::IsSha256(B749LedgerSha) ||
        !LivingTownTiles::IsSha256(B749ManifestAdmissionSha) || !LivingTownTiles::IsSha256(B749CafeBindingSha))
        return Refuse(Error,TEXT("fulltown_b749_DRAFT_REFUSE_pending_actual_composite_pins"));
    for (const auto& Pin:B749Pins)
        if (Pin.Bytes<=0 || !LivingTownTiles::IsSha256(Pin.SourceSha) ||
            !LivingTownTiles::IsSha256(Pin.RootColdSha) || !LivingTownTiles::IsSha256(Pin.ObservationSha))
            return Refuse(Error,TEXT("fulltown_b749_DRAFT_REFUSE_pending_actual_unit_pins"));
    if (D.SourceDispatchSha256!=Dispatch || D.SourceWorldLedgerSha256!=Ledger ||
        D.ManifestAdmissionSha256!=Admission || D.ExternalCafeBindingSha256!=B749CafeBindingSha)
        return Refuse(Error,TEXT("fulltown_b749_exact_composite_pins"));
    for (int32 I=0; I<3; ++I)
    {
        const auto& U=D.Units[I]; const auto& Pin=B749Pin(D,I);
        if (U.SourceMapBytes!=Pin.Bytes || U.SourceMapSha256!=Pin.SourceSha ||
            U.RootColdAdmissionSha256!=Pin.RootColdSha || U.ColdObservationSha256!=Pin.ObservationSha)
            return Refuse(Error,TEXT("fulltown_b749_exact_cold_map_pins"));
    }
    return true;
}
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
    if (D.ProfileId==B749Profile || D.ProfileId==B749RoofProfile) return ValidateB749(D,Error);
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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownB749DraftSchemaTest,"LivingTown.FullTown.B749DraftShapeAndRefusals",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownB749DraftSchemaTest::RunTest(const FString&)
{
    // Synthetic METADATA only: exercise the production shape validator while
    // proving the public entrypoint cannot admit unpinned production assets.
    auto* D=NewObject<ULivingTownFullTownData>(); const FString SyntheticSha=FString::ChrN(64,TEXT('a'));
    D->ProfileId=B749Profile; D->RootWorld=FSoftObjectPath(B749Root);
    D->SourceDispatchSha256=SyntheticSha; D->SourceWorldLedgerSha256=SyntheticSha;
    D->ManifestAdmissionSha256=SyntheticSha; D->ExternalCafeBindingSha256=SyntheticSha;
    for (int32 I=0; I<262; ++I)
    {
        D->ExternalCafePartIds.Add(FString::Printf(TEXT("synthetic_part_%d"),I));
        D->ExternalCafeRoleIds.Add(FString::Printf(TEXT("CAFE::synthetic_%d"),I));
    }
    for (int32 I=0; I<3; ++I)
    {
        const auto& Pin=B749Pins[I]; auto& U=D->Units.AddDefaulted_GetRef();
        U.UnitId=Pin.Id; U.DispatchIndex=Pin.Index; U.Map=TSoftObjectPtr<UWorld>(FSoftObjectPath(Pin.Map));
        U.SourceMapBytes=100; U.SourceMapSha256=SyntheticSha;
        U.RootColdAdmissionSha256=SyntheticSha; U.ColdObservationSha256=SyntheticSha;
        U.ActualBoundsCm=FBox(FVector(-1,-1,-1),FVector(1,1,1)); U.bPinnedSupport=I==2;
        if (I!=2) U.RequiredUnits.Add(TEXT("PERSISTENT_GROUND"));
        int32 Finish=0, Used=0;
        for (int32 J=0; J<Pin.Roles; ++J)
        {
            auto& Role=U.Roles.AddDefaulted_GetRef(); const bool Bedding=I==1 && J==748;
            const FString Alias=FString::Printf(TEXT("M%04d"),J);
            Role.RoleId=I==1?(Bedding?FString(TEXT("MCB::Bedding::Accepted_Bedding_ThreeAuthoredLODs")):TEXT("MCB::Building::")+Alias):
                FString::Printf(TEXT("synthetic_role_%d_%d"),I,J);
            Role.Mesh=FSoftObjectPath(I!=1?FString(TEXT("/Game/LivingTown_UEPilot/Tests/SyntheticMesh.SyntheticMesh")):
                Bedding?FString(TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_Bedding_v001/SM_Bedding.SM_Bedding")):
                TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtBAssets_v001/Building/Building_NamesOnly/StaticMeshes/")+Alias+TEXT(".")+Alias);
            Role.SourceIds.Add(Role.RoleId);
            for (int32 S=0; S<(Bedding?3:1); ++S)
            {
                auto& Slot=Role.Slots.AddDefaulted_GetRef(); Slot.SlotIndex=S;
                Slot.OriginalDefault=FSoftObjectPath(TEXT("/Game/LivingTown_UEPilot/Tests/SyntheticMaterial.SyntheticMaterial"));
                if (I==1 && J<381)
                {
                    Slot.Override=FSoftObjectPath(B749Finishes[Finish].Path); Slot.OverrideColdAdmissionSha256=B749FinishColdSha;
                    if (++Used==B749Finishes[Finish].Count) { ++Finish; Used=0; }
                }
            }
        }
    }
    FString Error;
    TestTrue(TEXT("exact971+262 metadata with381 finishes/368 empty shapes"),B749Shape(*D,Error));
    TestFalse(TEXT("correct shape cannot bypass actual composite pins"),LivingTownFullTown::ValidateManifest(*D,Error));
    TestTrue(TEXT("draft or foreign actual pins refuse explicitly"),
        Error.Contains(TEXT("DRAFT_REFUSE")) || Error.StartsWith(TEXT("fulltown_b749_exact_")));
    // Metadata-only admission exercises the installed pins; runtime still
    // verifies package bytes and every streamed component independently.
    D->SourceDispatchSha256=B749DispatchSha; D->SourceWorldLedgerSha256=B749LedgerSha;
    D->ManifestAdmissionSha256=B749ManifestAdmissionSha; D->ExternalCafeBindingSha256=B749CafeBindingSha;
    for (int32 I=0; I<3; ++I)
    {
        const auto& Pin=B749Pins[I]; auto& U=D->Units[I];
        U.SourceMapBytes=Pin.Bytes; U.SourceMapSha256=Pin.SourceSha;
        U.RootColdAdmissionSha256=Pin.RootColdSha; U.ColdObservationSha256=Pin.ObservationSha;
    }
    Error.Empty();
    TestTrue(TEXT("installed exact composite and cold unit pins admit valid metadata"),LivingTownFullTown::ValidateManifest(*D,Error));
    D->Units[1].SourceMapBytes++;
    TestFalse(TEXT("one-byte foreign unit package refuses"),LivingTownFullTown::ValidateManifest(*D,Error));
    D->Units[1].SourceMapBytes--;
    D->Units[1].ColdObservationSha256=SyntheticSha;
    TestFalse(TEXT("foreign unit observation refuses"),LivingTownFullTown::ValidateManifest(*D,Error));
    D->Units[1].ColdObservationSha256=B749Pins[1].ObservationSha;
    D->SourceDispatchSha256=SyntheticSha;
    TestFalse(TEXT("foreign composite dispatch refuses"),LivingTownFullTown::ValidateManifest(*D,Error));
    D->SourceDispatchSha256=B749DispatchSha;
    Error.Empty();
    TestTrue(TEXT("restored installed pins admit again"),LivingTownFullTown::ValidateManifest(*D,Error));
    // Same metadata validator: old profile stays valid and only two roof roles differ.
    auto* RoofD=DuplicateObject<ULivingTownFullTownData>(D,GetTransientPackage());
    RoofD->ProfileId=B749RoofProfile; RoofD->RootWorld=FSoftObjectPath(B749RoofRoot);
    auto& RoofUnit=RoofD->Units[1]; RoofUnit.Map=FSoftObjectPath(B749RoofUnitPin.Map);
    RoofUnit.SourceMapBytes=B749RoofUnitPin.Bytes; RoofUnit.SourceMapSha256=B749RoofUnitPin.SourceSha;
    RoofUnit.RootColdAdmissionSha256=B749RoofUnitPin.RootColdSha; RoofUnit.ColdObservationSha256=B749RoofUnitPin.ObservationSha;
    for (int32 Index:{447,448})
    { auto& R=RoofUnit.Roles[Index]; R.Mesh=FSoftObjectPath(B749RoofMesh(Index)); R.Slots[0].SlotName=FName(B749RoofSlot(Index)); R.Slots[0].OriginalDefault=FSoftObjectPath(B749RoofMaterial); R.Slots[0].Override.Reset(); R.Slots[0].OverrideColdAdmissionSha256.Empty(); R.Slots[0].BlendMode=0; }
    TestTrue(TEXT("roof shape retains original381 finishes and368 empty arrays"),B749Shape(*RoofD,Error));
    TestFalse(TEXT("old global pins cannot admit new roof profile"),LivingTownFullTown::ValidateManifest(*RoofD,Error));
    RoofD->SourceDispatchSha256=B749RoofDispatchSha; RoofD->SourceWorldLedgerSha256=B749RoofLedgerSha;
    RoofD->ManifestAdmissionSha256=B749RoofManifestAdmissionSha;
    const bool RoofPinsReady=LivingTownTiles::IsSha256(B749RoofLedgerSha);
    TestEqual(TEXT("roof metadata admits only after actual producer ledger pin"),LivingTownFullTown::ValidateManifest(*RoofD,Error),RoofPinsReady);
    const FSoftObjectPath Roof447=RoofUnit.Roles[447].Mesh;
    RoofUnit.Roles[447].Mesh=RoofUnit.Roles[448].Mesh;
    TestFalse(TEXT("roof447 cannot use roof448"),B749Shape(*RoofD,Error)); RoofUnit.Roles[447].Mesh=Roof447;
    auto& RoofSlot=RoofUnit.Roles[447].Slots[0];
    const auto AdmittedRoofSlot=RoofSlot;
    auto RefusesRoofSlot=[&](const TCHAR* Label)
    {
        TestFalse(Label,B749Shape(*RoofD,Error));
        TestEqual(TEXT("roof slot refusal identifies the changed slate binding"),Error,FString(TEXT("fulltown_roof_exact_default_slate_slot")));
        RoofSlot=AdmittedRoofSlot;
        TestTrue(TEXT("restored roof slot admits again"),B749Shape(*RoofD,Error));
    };
    RoofSlot.SlotName=FName(TEXT("ForeignRoofSlot"));
    RefusesRoofSlot(TEXT("roof slot name cannot change"));
    RoofSlot.OriginalDefault=FSoftObjectPath(TEXT("/Game/LivingTown_UEPilot/Tests/ForeignFinish.ForeignFinish"));
    RefusesRoofSlot(TEXT("roof default slate material cannot change"));
    RoofSlot.Override=AdmittedRoofSlot.OriginalDefault;
    RefusesRoofSlot(TEXT("roof cannot gain an override even equal to its default"));
    RoofSlot.OverrideColdAdmissionSha256=SyntheticSha;
    RefusesRoofSlot(TEXT("roof cannot gain an unrelated finish admission"));
    RoofSlot.BlendMode=1;
    RefusesRoofSlot(TEXT("roof cannot change its opaque blend mode"));
    RoofUnit.Map=FSoftObjectPath(B749Pins[1].Map);
    TestFalse(TEXT("roof profile cannot reuse old unit map"),B749Shape(*RoofD,Error)); RoofUnit.Map=FSoftObjectPath(B749RoofUnitPin.Map);
    RoofD->ProfileId=B749Profile;
    TestFalse(TEXT("roof assets cannot masquerade as original B749"),B749Shape(*RoofD,Error));
    TestTrue(TEXT("original B749 remains valid after roof probes"),LivingTownFullTown::ValidateManifest(*D,Error));

    auto& Role=D->Units[1].Roles[0]; auto& Slot=Role.Slots[0];
    const FSoftObjectPath Finish=Slot.Override, Original=Slot.OriginalDefault;
    Slot.OriginalDefault=Finish;
    TestTrue(TEXT("explicit override equal to original default still counted"),B749Shape(*D,Error));
    Slot.OriginalDefault=Original; Slot.Override.Reset(); Slot.OverrideColdAdmissionSha256.Empty();
    TestFalse(TEXT("dropping one finish refuses exact counts"),B749Shape(*D,Error));
    Slot.Override=Finish; Slot.OverrideColdAdmissionSha256=B749FinishColdSha;
    Slot.Override=FSoftObjectPath(TEXT("/Game/LivingTown_UEPilot/Tests/ForeignFinish.ForeignFinish"));
    TestFalse(TEXT("unbound eighth material refuses"),B749Shape(*D,Error)); Slot.Override=Finish;
    Slot.SlotIndex=1; TestFalse(TEXT("wrong ordered slot refuses"),B749Shape(*D,Error)); Slot.SlotIndex=0;
    Slot.OverrideColdAdmissionSha256=SyntheticSha;
    TestFalse(TEXT("finish requires exact accepted cold identity"),B749Shape(*D,Error)); Slot.OverrideColdAdmissionSha256=B749FinishColdSha;
    Role.Kind=ELivingTownFullTownComponentKind::HierarchicalInstances;
    TestFalse(TEXT("B profile cannot enable HISM"),B749Shape(*D,Error)); Role.Kind=ELivingTownFullTownComponentKind::StaticMesh;
    D->Units[2].RequiredUnits.Add(D->Units[0].UnitId);
    TestFalse(TEXT("ground cannot depend on a dependent"),B749Shape(*D,Error)); D->Units[2].RequiredUnits.Empty();
    D->Units[1].Roles[748].Slots[0].Override=Finish;
    TestFalse(TEXT("bedding three-default slots cannot receive one-slot finish"),B749Shape(*D,Error));
    D->Units[1].Roles[748].Slots[0].Override.Reset();
    D->ProfileId=TEXT("U0131_U0142_Ground151_ExternalCafe81_v001");
    TestFalse(TEXT("new map identities cannot masquerade as legacy profile"),LivingTownFullTown::ValidateManifest(*D,Error));
    D->ProfileId=TEXT("B749_future_profile");
    TestFalse(TEXT("unknown profile refuses"),LivingTownFullTown::ValidateManifest(*D,Error));
    return true;
}
#endif
