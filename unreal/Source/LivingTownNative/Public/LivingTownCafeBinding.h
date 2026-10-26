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
    FTransform MeshRelativeTransform = FTransform::Identity;
    TArray<FLivingTownCafePartBinding> Parts;
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
};

namespace LivingTownCafeJournal
{
    bool Encode(const FLivingTownCafeBinding& Binding, const FString& LeaseJournal, FString& Out, FString& Error);
    bool Decode(const FString& Json, const FLivingTownCafeBinding& Binding, FString& LeaseJournal, FString& Error);
    bool HasUniqueObjectKeys(const FString& Json);
    bool Sha256(const TArray<uint8>& Bytes, FString& Out);
}
