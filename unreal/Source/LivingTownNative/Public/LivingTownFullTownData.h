#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "Engine/EngineTypes.h"
#include "LivingTownFullTownData.generated.h"

class UWorld;

UENUM(BlueprintType)
enum class ELivingTownFullTownComponentKind : uint8 { StaticMesh, HierarchicalInstances };

// Zero preserves the interpretation of existing serialized descriptors.
UENUM(BlueprintType)
enum class ELivingTownFullTownCafeBackend : uint8 { LegacyProjection262, WorldV3Qualified289 };

USTRUCT(BlueprintType)
struct FLivingTownFullTownMaterialSlot
{
    GENERATED_BODY()
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") int32 SlotIndex = INDEX_NONE;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FName SlotName;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FSoftObjectPath OriginalDefault;
    // Empty for a qualified empty-override static component, explicit for HISM.
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FSoftObjectPath Override;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") uint8 BlendMode = 0;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FString OverrideColdAdmissionSha256;
};

USTRUCT(BlueprintType)
struct FLivingTownFullTownInstance
{
    GENERATED_BODY()
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FString SourceId;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") int32 SourceMatrixIndex = INDEX_NONE;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FTransform WorldTransform = FTransform::Identity;
};

USTRUCT(BlueprintType)
struct FLivingTownFullTownRole
{
    GENERATED_BODY()
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FString RoleId;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") ELivingTownFullTownComponentKind Kind = ELivingTownFullTownComponentKind::StaticMesh;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FSoftObjectPath Mesh;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") TArray<FString> SourceIds;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FTransform WorldTransform = FTransform::Identity;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") TArray<FLivingTownFullTownMaterialSlot> Slots;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") TArray<FLivingTownFullTownInstance> Instances;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FName CollisionProfile = TEXT("BlockAll");
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") TEnumAsByte<ECollisionEnabled::Type> CollisionEnabled = ECollisionEnabled::QueryAndPhysics;
};

USTRUCT(BlueprintType)
struct FLivingTownFullTownUnit
{
    GENERATED_BODY()
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FString UnitId;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") int32 DispatchIndex = INDEX_NONE;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") TSoftObjectPtr<UWorld> Map;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") int64 SourceMapBytes = 0;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FString SourceMapSha256;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FString RootColdAdmissionSha256;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FString ColdObservationSha256;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FBox ActualBoundsCm = FBox(ForceInit);
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") bool bPinnedSupport = false;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") TArray<FString> RequiredUnits;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") TArray<FLivingTownFullTownRole> Roles;
};

// A new presentation identity. The original lease/save and pilot types are unchanged.
UCLASS(BlueprintType,NotBlueprintable)
class LIVINGTOWNNATIVE_API ULivingTownFullTownData final : public UPrimaryDataAsset
{
    GENERATED_BODY()
public:
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") int32 SchemaVersion = 1;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FString Scope = TEXT("IntegrationSubset");
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FString ProfileId = TEXT("U0131_U0142_Ground151_ExternalCafe81_v001");
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") ELivingTownFullTownCafeBackend CafeBackend = ELivingTownFullTownCafeBackend::LegacyProjection262;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FSoftObjectPath RootWorld;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FString SourceDispatchSha256;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FString SourceWorldLedgerSha256;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FString ManifestAdmissionSha256;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") FString ExternalCafeBindingSha256;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") TArray<FString> ExternalCafePartIds;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") TArray<FString> ExternalCafeRoleIds;
    UPROPERTY(EditAnywhere,BlueprintReadWrite,Category="FullTown manifest") TArray<FLivingTownFullTownUnit> Units;
};

namespace LivingTownFullTown
{
    LIVINGTOWNNATIVE_API bool ValidateManifest(const ULivingTownFullTownData& Data, FString& Error);
    LIVINGTOWNNATIVE_API bool IsWorldV3CafeProfile(const ULivingTownFullTownData& Data);
    LIVINGTOWNNATIVE_API bool SameQualifiedTransform(const FTransform& Actual, const FTransform& Expected);
    LIVINGTOWNNATIVE_API double DistanceToBoundsXY(const FVector& Point, const FBox& Bounds);
}
