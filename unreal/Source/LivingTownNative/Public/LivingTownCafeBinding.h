#pragma once
#include "CoreMinimal.h"

// A physical projection contract, separate from the unchanged logical lease terms.
// Only the scene/calibration producer supplies this. HUDs submit actions only.
struct FLivingTownCafePartBinding
{
    FString Id;
    FString AssetPath;
    FString RenderSha256;
    FString CollisionGuid;
    FTransform Transform = FTransform::Identity; // source canonical -> UE cm already calibrated
    bool bFloor = false;
    bool bCounter = false;
};

class UBlendSpace;

// V1 stays the default. V2 explicitly selects this reviewed physical appearance/motion family.
enum class ELivingTownCafeMotionStrategy : uint8 { LegacySingleNode, CafeWorker110RootAligned, Current61BakedSingleNode };
namespace LivingTownCafeWorker110
{
    inline constexpr TCHAR Strategy[] = TEXT("cafe_worker61_root_aligned_110_v1");
    inline constexpr TCHAR MeshAsset[] = TEXT("/Game/LivingTown_UEPilot/CafeWorkerBen110_v001/SK_CafeWorkerBen110_v001.SK_CafeWorkerBen110_v001");
    inline constexpr TCHAR MotionAsset[] = TEXT("/Game/LivingTown_UEPilot/CafeWorkerBen110_v001/BS_CafeWorkerIdleWalk110_v001.BS_CafeWorkerIdleWalk110_v001");
    inline constexpr TCHAR IdleAsset[] = TEXT("/Game/LivingTown_UEPilot/CafeWorkerMultiviewV002_IdleOnlyTrial_v002/idle.idle");
    inline constexpr TCHAR WalkAsset[] = TEXT("/Game/LivingTown_UEPilot/CafeWorkerMultiviewV002_WalkTrial_v001/walk.walk");
    inline constexpr TCHAR MaterialAsset[] = TEXT("/Game/LivingTown_UEPilot/CharacterNormalStrength_v001/M_Normal035.M_Normal035");
    inline constexpr TCHAR PalmSocket[] = TEXT("UsePalm_R");
    inline FVector PalmLocalCm() { return FVector(-0.15806712908670584,-0.02671117545105517,3.367123100906613); }
    inline FVector RootDeltaCm() { return FVector(-0.45119449496269226,10.242915153503418,0.0); }
    // Policy only; asset identity, axis bounds, source samples and physical qualification stay separate.
    LIVINGTOWNNATIVE_API bool HasUnfilteredUnscaled1DMotionPolicy(const UBlendSpace* Motion);
}


// V3 is a separate once-baked body family. All calibration values must come from
// its future qualified avatar/contact producer; this source creates no binding.
namespace LivingTownCafeCurrent61Baked
{
    inline constexpr TCHAR Strategy[] = TEXT("current61_baked_v1");
    inline constexpr TCHAR MeshAsset[] = TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedAvatar_v001/SK_Worker110Current61_BakedAvatar_v001.SK_Worker110Current61_BakedAvatar_v001");
    inline constexpr TCHAR MotionAsset[] = TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedAvatar_v001/BS_Worker110Current61_BakedIdleWalk_v001.BS_Worker110Current61_BakedIdleWalk_v001");
    inline constexpr TCHAR IdleAsset[] = TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMotion_v001/A_Worker110_BakedIdle_v001.A_Worker110_BakedIdle_v001");
    inline constexpr TCHAR WalkAsset[] = TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMotion_v001/A_Worker110_BakedWalk_v001.A_Worker110_BakedWalk_v001");
    inline constexpr TCHAR PalmSocket[] = TEXT("UsePalm_Current61_R");
    inline constexpr TCHAR WrapperBone[] = TEXT("LT_Complete_Private_UnchangedTarget61_001");
    LIVINGTOWNNATIVE_API const TArray<FString>& MaterialAssets();
    LIVINGTOWNNATIVE_API bool HasUnfilteredUnscaled1DMotionPolicy(const UBlendSpace* Motion);
}

struct FLivingTownCurrent61BakedCalibration
{
    // Identity is only an inert default. A complete numeric descriptor and hash
    // must be read from an explicitly qualified V3 binding before use.
    FString QualificationSha256;
    FTransform PalmSocketLocalTransform = FTransform::Identity;
    double WalkSpeedCmPerSecond = 0;
    double IdleDurationSeconds = 0;
    double WalkDurationSeconds = 0;
    bool bReadQualifiedDescriptor = false;
    bool IsValidated() const;
};

struct FLivingTownCafeBinding
{
    FString PhysicalSceneSha256;
    FString SourceProjectionSha256;
    FString PhysicalQualificationSha256;
    FString BindingFileSha256;
    FString VisualSha256;
    FString ResidentId;
    FString VisualAssetPath;
    FString IdleWalkBlendSpacePath;
    FString UseSocket;
    ELivingTownCafeMotionStrategy MotionStrategy = ELivingTownCafeMotionStrategy::LegacySingleNode;
    FString IdleAnimationPath;
    FString WalkAnimationPath;
    FVector IdleRootDeltaCm = FVector::ZeroVector;
    FLivingTownCurrent61BakedCalibration Current61BakedCalibration;
    FTransform MeshRelativeTransform = FTransform::Identity;
    TArray<FLivingTownCafePartBinding> Parts;
    // Legacy files retain their exact 289-source-node contract. An explicit,
    // source-qualified private trial declares its complete finite instance set.
    int32 DeclaredPartCount = 0;
    bool bPartRosterValidated = false;
    bool bAuthoredSceneTrial = false;
    FString PartSourceContextSha256;
    TSet<FString> DeclaredPartIds;
    TSet<FString> DeclaredFloorPartIds;
    TSet<FString> DeclaredCounterPartIds;
    TMap<FString,TArray<FString>> DeclaredAssetMaterials;
    FVector SpawnFeetCm = FVector::ZeroVector;
    FRotator SpawnRotation = FRotator::ZeroRotator;
    FVector CounterUsePointCm = FVector::ZeroVector;
    FBox FloorBoundsCm = FBox(ForceInit);
    float CapsuleRadiusCm = 0;
    float CapsuleHalfHeightCm = 0;
    float ReachCm = 0;
    float WalkSpeedCmPerSecond = 0;
    float CameraArmCm = 0;
    static bool ReadQualifiedFile(const FString& Path, FLivingTownCafeBinding& Out, FString& Error);
    bool HasValidatedPartRoster() const;
    bool HasValidatedCurrent61BakedAvatarBinding() const;
};

namespace LivingTownCafeJournal
{
    bool Encode(const FLivingTownCafeBinding& Binding, const FString& LeaseJournal, FString& Out, FString& Error);
    bool Decode(const FString& Json, const FLivingTownCafeBinding& Binding, FString& LeaseJournal, FString& Error);
    bool HasUniqueObjectKeys(const FString& Json);
    bool Sha256(const TArray<uint8>& Bytes, FString& Out);
}
