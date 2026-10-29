#pragma once
#include "CoreMinimal.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Containers/StaticArray.h"
#include "LivingTownRootCorrectedSingleNodeInstance.generated.h"

class UAnimSequence;
class UBlendSpace;
class USkeletalMesh;
struct FLivingTownRootCorrectedSingleNodeProxy;

enum class ELivingTownRootCorrectionState : uint8
{
    NotEvaluated, Unconfigured, UnexpectedAsset, MissingRecord, AmbiguousRecord,
    EmptyCache, InvalidSample, UnknownClip, PerBoneWeights, InvalidWeightSum, MirroredEvaluation,
    InvalidRoot, ReadyDisabled, Applied
};

struct FLivingTownRootCorrectionSample
{
    const UAnimSequence* Animation = nullptr;
    int32 SampleIndex = INDEX_NONE;
    float Time = 0, PreviousTime = 0, Weight = 0, RawWeight = 0;
};

/** Fixed-size production observations; pose arrays are filled only by explicit diagnostic opt-in. */
struct FLivingTownRootCorrectionDiagnostic
{
    ELivingTownRootCorrectionState State = ELivingTownRootCorrectionState::NotEvaluated;
    uint64 EvaluationSerial = 0, ConfigurationGeneration = 0;
    bool bCorrectionEnabled = false, bWeightObserved = false, bPoseCaptured = false, bMirrorTablePresent = false;
    const UAnimationAsset* Asset = nullptr;
    int32 MatchingRecords = 0, Samples = 0, PoseBones = 0;
    double IdleWeight = 0;
    FVector RequestedDelta = FVector::ZeroVector, AppliedDelta = FVector::ZeroVector;
    FTransform RootBefore = FTransform::Identity, RootAfter = FTransform::Identity;
    TStaticArray<FLivingTownRootCorrectionSample, 2> SampleRows;
    TArray<int32> MeshBoneIndices;
    TArray<FTransform> LocalBefore, LocalAfter;
};

struct FLivingTownRootCorrectionNegativeResult
{
    FName Name;
    ELivingTownRootCorrectionState Actual, Expected;
};

/** Opt-in output-pose correction. It never edits clips, assets, actor transforms or qualification flags. */
UCLASS(Transient, NotBlueprintable)
class LIVINGTOWNNATIVE_API ULivingTownRootCorrectedSingleNodeInstance final : public UAnimSingleNodeInstance
{
    GENERATED_BODY()
public:
    ULivingTownRootCorrectedSingleNodeInstance(const FObjectInitializer& ObjectInitializer = FObjectInitializer::Get());
    UFUNCTION(BlueprintCallable, Category="LivingTown|RootCorrection")
    bool ConfigureRootCorrection(UBlendSpace* Motion, UAnimSequence* Idle, UAnimSequence* Walk,
        FVector ComponentDeltaCm, bool bEnableCorrection, bool bCaptureDiagnosticPose, FString& Error);
    virtual void NativeInitializeAnimation() override;
    /** Game-thread read blocks any worker evaluation. It does not tick, serialize or allocate on the worker. */
    bool CopyRootCorrectionDiagnostic(FLivingTownRootCorrectionDiagnostic& Out) const;
    static const TCHAR* StateName(ELivingTownRootCorrectionState State);
#if WITH_EDITOR
    static TArray<FLivingTownRootCorrectionNegativeResult> RunGuardNegativeControls(
        UBlendSpace* Motion, UAnimSequence* Idle, UAnimSequence* Walk);
#endif
protected:
    virtual FAnimInstanceProxy* CreateAnimInstanceProxy() override;
private:
    friend struct FLivingTownRootCorrectedSingleNodeProxy;
    UPROPERTY() TObjectPtr<UBlendSpace> ConfiguredMotion = nullptr;
    UPROPERTY() TObjectPtr<UAnimSequence> ConfiguredIdle = nullptr;
    UPROPERTY() TObjectPtr<UAnimSequence> ConfiguredWalk = nullptr;
    UPROPERTY() TObjectPtr<USkeletalMesh> ConfiguredMesh = nullptr;
    FVector ConfiguredDelta = FVector::ZeroVector;
    uint64 ConfigurationGeneration = 0;
    bool bConfigured = false, bEnableCorrection = false, bCaptureDiagnosticPose = false;
};
