#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "UObject/SoftObjectPtr.h"
#include "LivingTownTileData.generated.h"

class UStaticMesh;

// These data assets are authored only after native import/readback. The default
// false flags deliberately cannot activate the unimported portable slice.
USTRUCT()
struct FLivingTownTileQualification
{
    GENERATED_BODY()
    UPROPERTY(VisibleAnywhere) FString SourceAssemblySha256;
    UPROPERTY(VisibleAnywhere) FString SourceSliceSha256;
    UPROPERTY(VisibleAnywhere) FString QualifiedDerivativeSha256;
    UPROPERTY(VisibleAnywhere) FString NativeReadbackReceiptSha256;
    UPROPERTY(VisibleAnywhere) bool bAssetsQualified = false;
    UPROPERTY(VisibleAnywhere) bool bCoordinatesQualified = false;
    UPROPERTY(VisibleAnywhere) bool bMaterialsQualified = false;
    UPROPERTY(VisibleAnywhere) bool bCollisionQualified = false;
};

UENUM()
enum class ELivingTownTileEntryKind : uint8
{
    Static,
    Instanced,
    DeferredDoor
};

USTRUCT()
struct FLivingTownTilePlacement
{
    GENERATED_BODY()
    // Instance source identity; static/chunk provenance is separately retained.
    UPROPERTY(VisibleAnywhere) FString SourcePlacementId;
    UPROPERTY(VisibleAnywhere) TArray<double> SourceWorldMatrixRowMajor;
    UPROPERTY(VisibleAnywhere) FTransform QualifiedNativeTransform = FTransform::Identity;
};

USTRUCT()
struct FLivingTownTileGeometry
{
    GENERATED_BODY()
    // Entry identity is globally unique even when one prototype mesh is shared.
    UPROPERTY(VisibleAnywhere) FString EntryId;
    UPROPERTY(VisibleAnywhere) FString SourceMeshKey;
    UPROPERTY(VisibleAnywhere) FString OwnerId;
    UPROPERTY(VisibleAnywhere) FString FloorId;
    UPROPERTY(VisibleAnywhere) FString RoomId;
    UPROPERTY(VisibleAnywhere) TArray<FString> SourcePlacementIds;
    UPROPERTY(VisibleAnywhere) ELivingTownTileEntryKind Kind = ELivingTownTileEntryKind::Static;
    UPROPERTY(VisibleAnywhere, meta=(AssetBundles="TownGeometry")) TSoftObjectPtr<UStaticMesh> Mesh;
    UPROPERTY(VisibleAnywhere) FString NativeMeshReceiptSha256;
    UPROPERTY(VisibleAnywhere) FString NativeRenderSha256;
    UPROPERTY(VisibleAnywhere) FString NativeCollisionGuid;
    UPROPERTY(VisibleAnywhere) TArray<FSoftObjectPath> QualifiedMaterialPaths;
    UPROPERTY(VisibleAnywhere) TArray<FString> QualifiedMaterialSlotNames;
    UPROPERTY(VisibleAnywhere) TArray<uint8> QualifiedMaterialBlendModes;
    UPROPERTY(VisibleAnywhere) FBox ActualNativeBoundsCm = FBox(ForceInit);
    UPROPERTY(VisibleAnywhere) TArray<FLivingTownTilePlacement> Placements;
    // A deliberate qualified no-collision foliage entry is distinct from an
    // unqualified collision asset. No collision policy is inferred from a name.
    UPROPERTY(VisibleAnywhere) bool bBlockingCollision = false;
};

USTRUCT()
struct FLivingTownDeferredFixture
{
    GENERATED_BODY()
    UPROPERTY(VisibleAnywhere) FString SourceGroupId;
    UPROPERTY(VisibleAnywhere) TArray<FString> SourcePlacementIds;
    UPROPERTY(VisibleAnywhere) FString Qualification = TEXT("DEFERRED_NO_BEHAVIOR");
    // Canonical source-group metadata is preserved opaquely in the cooked UE
    // package. Runtime never parses this authoring/provenance JSON payload.
    UPROPERTY(VisibleAnywhere) TArray<uint8> SourceMetadataCanonicalUtf8;
    UPROPERTY(VisibleAnywhere) FString SourceMetadataSha256;
};

UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ULivingTownRenderUnitData final : public UPrimaryDataAsset
{
    GENERATED_BODY()
public:
    UPROPERTY(VisibleAnywhere) int32 SchemaVersion = 1;
    UPROPERTY(VisibleAnywhere) FString UnitId;
    UPROPERTY(VisibleAnywhere) FLivingTownTileQualification Qualification;
    UPROPERTY(VisibleAnywhere) TArray<FLivingTownTileGeometry> Geometry;
    UPROPERTY(VisibleAnywhere) TArray<FLivingTownDeferredFixture> DeferredFixtures;
};

USTRUCT()
struct FLivingTownTileUnitRef
{
    GENERATED_BODY()
    UPROPERTY(VisibleAnywhere) FString UnitId;
    UPROPERTY(VisibleAnywhere) TSoftObjectPtr<ULivingTownRenderUnitData> Asset;
    UPROPERTY(VisibleAnywhere) FBox ActualNativeBoundsCm = FBox(ForceInit);
    UPROPERTY(VisibleAnywhere) TArray<FString> Dependencies;
    UPROPERTY(VisibleAnywhere) TArray<FString> DeclaredEntryIds;
    UPROPERTY(VisibleAnywhere) TArray<FString> DeclaredInstanceEntryIds;
    UPROPERTY(VisibleAnywhere) TArray<FString> DeclaredPrototypeMeshKeys;
    UPROPERTY(VisibleAnywhere) TArray<FString> DeclaredInstanceSourceIds;
    UPROPERTY(VisibleAnywhere) TArray<FString> DeclaredDeferredDoorEntryIds;
};

USTRUCT()
struct FLivingTownTileSupport
{
    GENERATED_BODY()
    UPROPERTY(VisibleAnywhere) FString SupportId;
    UPROPERTY(VisibleAnywhere) bool bRequestedCell = false;
    // Qualified engine-native XY, cm. Vertical room/terrain scope remains in
    // each mesh's actual 3D bounds. Whole owners load as indivisible units.
    UPROPERTY(VisibleAnywhere) FVector2D MinNativeXYCm = FVector2D::ZeroVector;
    UPROPERTY(VisibleAnywhere) FVector2D MaxNativeXYCm = FVector2D::ZeroVector;
    UPROPERTY(VisibleAnywhere) TArray<FString> Units;
};

UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ULivingTownTileRootData final : public UPrimaryDataAsset
{
    GENERATED_BODY()
public:
    UPROPERTY(VisibleAnywhere) int32 SchemaVersion = 1;
    UPROPERTY(VisibleAnywhere) FLivingTownTileQualification Qualification;
    UPROPERTY(VisibleAnywhere) FString ExistingCafeBindingSha256;
    UPROPERTY(VisibleAnywhere) TArray<FLivingTownTileUnitRef> Units;
    UPROPERTY(VisibleAnywhere) TArray<FLivingTownTileSupport> Supports;
    UPROPERTY(VisibleAnywhere) TArray<FString> PersistentUnits;
    // Entire source fixture inventory is retained as metadata, including the
    // already-external cafe; this array never creates an object or behavior.
    UPROPERTY(VisibleAnywhere) TArray<FLivingTownDeferredFixture> SourceFixtureInventory;
    UPROPERTY(VisibleAnywhere) int32 SourceMeshDefinitions = 1488;
    UPROPERTY(VisibleAnywhere) int32 SourcePlacedNodes = 2023;
    UPROPERTY(VisibleAnywhere) int32 SourceRepeatedPlacements = 587;
    UPROPERTY(VisibleAnywhere) int32 SourcePrototypeMeshes = 52;
    UPROPERTY(VisibleAnywhere) int32 SourceDeferredDoorBatches = 150;
    UPROPERTY(VisibleAnywhere) int32 SourceFixtureGroups = 385;
};

namespace LivingTownTiles
{
    // Exported read-only bridge to the unchanged, already-tested native SHA
    // implementation. Editor readback can hash bytes without an engine hook.
    LIVINGTOWNNATIVE_API bool HashBytes(const TArray<uint8>& Bytes, FString& Out);
    LIVINGTOWNNATIVE_API bool IsSha256(const FString& Value);
    LIVINGTOWNNATIVE_API bool IsPilotAssetPath(const FSoftObjectPath& Path);
    LIVINGTOWNNATIVE_API bool IsReservedCafeSourceId(const FString& Id);
    LIVINGTOWNNATIVE_API bool ValidateQualification(const FLivingTownTileQualification& Value, FString& Error);
    LIVINGTOWNNATIVE_API bool ValidatePlacement(const FLivingTownTilePlacement& Value, FString& Error);
    LIVINGTOWNNATIVE_API bool ValidateRoot(const ULivingTownTileRootData& Root, FString& Error);
    LIVINGTOWNNATIVE_API bool ValidateUnit(const ULivingTownRenderUnitData& Unit, const FLivingTownTileUnitRef& Expected,
        const FLivingTownTileQualification& RootQualification, FString& Error);
}
