#include "LivingTownRootCorrectedSingleNodeInstance.h"
#include "Animation/AnimSingleNodeInstanceProxy.h"
#include "Animation/AnimSequence.h"
#include "Animation/BlendSpace.h"
#include "Animation/Skeleton.h"
#include "BonePose.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/SkeletalMesh.h"

namespace
{
using EState = ELivingTownRootCorrectionState;
bool ParentlessRoot(int32 PoseBones, int32 MeshIndex, int32 ParentIndex)
{
    return PoseBones > 0 && MeshIndex == 0 && ParentIndex == INDEX_NONE;
}

EState ReadActualIdleWeight(const UAnimationAsset* Current, const UBlendSpace* Motion,
    const UAnimSequence* Idle, const UAnimSequence* Walk, const TArray<FAnimTickRecord>& Records,
    FLivingTownRootCorrectionDiagnostic& Result)
{
    if(Current != Motion) return EState::UnexpectedAsset;
    const FAnimTickRecord* Match = nullptr;
    for(const FAnimTickRecord& Record : Records)
    {
        if(Record.SourceAsset == Motion) { ++Result.MatchingRecords; Match = &Record; }
    }
    if(Result.MatchingRecords == 0) return EState::MissingRecord;
    if(Result.MatchingRecords != 1) return EState::AmbiguousRecord;
    // The public record references the exact current array consumed by the base player.
    // Never retain this pointer after the current evaluation.
    const TArray<FBlendSampleData>* Cache = Match->BlendSpace.BlendSampleDataCache;
    if(!Cache || Cache->Num() == 0) return EState::EmptyCache;
    if(Cache->Num() > 2) return EState::InvalidSample;
    double Sum = 0, IdleWeight = 0;
    Result.Samples = Cache->Num();
    for(int32 Index = 0; Index < Cache->Num(); ++Index)
    {
        const FBlendSampleData& Sample = (*Cache)[Index];
        if(!FMath::IsFinite(Sample.TotalWeight) || Sample.TotalWeight < 0 || Sample.TotalWeight > 1.f + 1e-6f ||
            !FMath::IsFinite(Sample.Time) || !FMath::IsFinite(Sample.PreviousTime)) return EState::InvalidSample;
        if(Sample.Animation != Idle && Sample.Animation != Walk) return EState::UnknownClip;
        if(Sample.PerBoneBlendData.Num() != 0 || Sample.PerBoneWeightRate.Num() != 0) return EState::PerBoneWeights;
        const auto& Authored = Motion->GetBlendSamples();
        if(!Authored.IsValidIndex(Sample.SampleDataIndex) || Authored[Sample.SampleDataIndex].Animation != Sample.Animation)
            return EState::InvalidSample;
        const double Weight = Sample.GetClampedWeight();
        Sum += Weight;
        if(Sample.Animation == Idle) IdleWeight += Weight;
        auto& Row = Result.SampleRows[Index];
        Row.Animation = Sample.Animation; Row.SampleIndex = Sample.SampleDataIndex;
        Row.Time = Sample.Time; Row.PreviousTime = Sample.PreviousTime;
        Row.Weight = static_cast<float>(Weight); Row.RawWeight = Sample.TotalWeight;
    }
    if(!FMath::IsNearlyEqual(Sum, 1.0, 1e-6) || !FMath::IsFinite(IdleWeight) || IdleWeight < 0 || IdleWeight > 1)
        return EState::InvalidWeightSum;
    Result.IdleWeight = IdleWeight; Result.bWeightObserved = true;
    return EState::Applied;
}
}

struct FLivingTownRootCorrectedSingleNodeProxy final : FAnimSingleNodeInstanceProxy
{
    explicit FLivingTownRootCorrectedSingleNodeProxy(UAnimInstance* Instance)
        : FAnimSingleNodeInstanceProxy(Instance) {} // Required: initializes SingleNode.Proxy.

    const UBlendSpace* Motion = nullptr;
    const UAnimSequence* Idle = nullptr;
    const UAnimSequence* Walk = nullptr;
    FVector Delta = FVector::ZeroVector;
    uint64 Generation = 0;
    bool bReady = false, bEnabled = false, bCapture = false;
    FLivingTownRootCorrectionDiagnostic Last;

    virtual void PreUpdate(UAnimInstance* Instance, float DeltaSeconds) override
    {
        FAnimSingleNodeInstanceProxy::PreUpdate(Instance, DeltaSeconds);
        const auto* Typed = Cast<ULivingTownRootCorrectedSingleNodeInstance>(Instance);
        bReady = Typed && Typed->bConfigured && Typed->GetSkelMeshComponent() &&
            Typed->GetSkelMeshComponent()->GetSkeletalMeshAsset() == Typed->ConfiguredMesh;
        Motion = Typed ? Typed->ConfiguredMotion.Get() : nullptr;
        Idle = Typed ? Typed->ConfiguredIdle.Get() : nullptr;
        Walk = Typed ? Typed->ConfiguredWalk.Get() : nullptr;
        Delta = Typed ? Typed->ConfiguredDelta : FVector::ZeroVector;
        Generation = Typed ? Typed->ConfigurationGeneration : 0;
        bEnabled = Typed && Typed->bEnableCorrection;
        bCapture = Typed && Typed->bCaptureDiagnosticPose;
    }

    virtual bool Evaluate(FPoseContext& Output) override
    {
        const bool Evaluated = FAnimSingleNodeInstanceProxy::Evaluate(Output); // Exactly once.
        ++Last.EvaluationSerial; Last.ConfigurationGeneration = Generation;
        Last.State = EState::Unconfigured; Last.bCorrectionEnabled = bEnabled;
        Last.bWeightObserved = Last.bPoseCaptured = false; Last.bMirrorTablePresent = MirrorDataTable != nullptr; Last.Asset = CurrentAsset;
        Last.MatchingRecords = Last.Samples = 0; Last.PoseBones = Output.Pose.GetNumBones();
        Last.IdleWeight = 0; Last.RequestedDelta = Delta; Last.AppliedDelta = FVector::ZeroVector;
        Last.RootBefore = Last.RootAfter = FTransform::Identity;
        Last.MeshBoneIndices.Reset(); Last.LocalBefore.Reset(); Last.LocalAfter.Reset();
        for(auto& Row : Last.SampleRows) Row = FLivingTownRootCorrectionSample{};
        if(!bReady) return Evaluated;
        if(Last.bMirrorTablePresent) { Last.State = EState::MirroredEvaluation; return Evaluated; }
        Last.State = ReadActualIdleWeight(CurrentAsset, Motion, Idle, Walk, GetUngroupedActivePlayersRead(), Last);
        if(Last.State != EState::Applied) return Evaluated;
        const FCompactPoseBoneIndex Root(0);
        if(Output.Pose.GetNumBones() == 0 || !ParentlessRoot(Output.Pose.GetNumBones(),
            Output.Pose.GetBoneContainer().MakeMeshPoseIndex(Root).GetInt(), Output.Pose.GetParentBoneIndex(Root).GetInt()))
        { Last.State = EState::InvalidRoot; return Evaluated; }
        Last.RootBefore = Output.Pose[Root];
        if(Last.RootBefore.ContainsNaN()) { Last.State = EState::InvalidRoot; return Evaluated; }
        if(bCapture)
        {
            for(FCompactPoseBoneIndex Index : Output.Pose.ForEachBoneIndex())
            {
                Last.MeshBoneIndices.Add(Output.Pose.GetBoneContainer().MakeMeshPoseIndex(Index).GetInt());
                Last.LocalBefore.Add(Output.Pose[Index]);
            }
        }
        if(bEnabled)
        {
            Last.AppliedDelta = Delta * Last.IdleWeight;
            Output.Pose[Root].AddToTranslation(Last.AppliedDelta);
        }
        else Last.State = EState::ReadyDisabled;
        Last.RootAfter = Output.Pose[Root];
        if(bCapture)
        {
            for(FCompactPoseBoneIndex Index : Output.Pose.ForEachBoneIndex()) Last.LocalAfter.Add(Output.Pose[Index]);
            Last.bPoseCaptured = true;
        }
        return Evaluated;
    }
};

ULivingTownRootCorrectedSingleNodeInstance::ULivingTownRootCorrectedSingleNodeInstance(const FObjectInitializer& ObjectInitializer)
    : Super(ObjectInitializer) {}

bool ULivingTownRootCorrectedSingleNodeInstance::ConfigureRootCorrection(UBlendSpace* Motion,
    UAnimSequence* Idle, UAnimSequence* Walk, FVector ComponentDeltaCm, bool bEnable, bool bCapture, FString& Error)
{
    Error.Reset();
    if(!IsInGameThread()) { Error = TEXT("game_thread_configuration_required"); return false; }
    bConfigured = false; ++ConfigurationGeneration;
    auto& Proxy = GetProxyOnGameThread<FLivingTownRootCorrectedSingleNodeProxy>();
    Proxy.bReady = false; Proxy.Last = FLivingTownRootCorrectionDiagnostic{};
    const auto* Component = GetSkelMeshComponent();
    USkeletalMesh* Mesh = Component ? Component->GetSkeletalMeshAsset() : nullptr;
    if(!Mesh || !Mesh->GetSkeleton() || Mesh->GetRefSkeleton().GetNum() == 0 ||
        Mesh->GetRefSkeleton().GetBoneName(0) != FName(TEXT("root")) || Mesh->GetRefSkeleton().GetParentIndex(0) != INDEX_NONE ||
        !Motion || !Idle || !Walk || Idle == Walk || ComponentDeltaCm.ContainsNaN() ||
        Motion->GetSkeleton() != Mesh->GetSkeleton() || Idle->GetSkeleton() != Mesh->GetSkeleton() || Walk->GetSkeleton() != Mesh->GetSkeleton())
    { Error = TEXT("matching_mesh_clips_parentless_root_and_finite_delta_required"); return false; }
    if(Motion->IsValidAdditive() || Idle->IsValidAdditive() || Walk->IsValidAdditive() ||
        Idle->bEnableRootMotion || Walk->bEnableRootMotion || !FMath::IsFinite(Idle->GetPlayLength()) ||
        !FMath::IsFinite(Walk->GetPlayLength()) || Idle->GetPlayLength() <= 0 || Walk->GetPlayLength() <= 0)
    { Error = TEXT("nonadditive_non_root_motion_source_clips_required"); return false; }
    const auto& Samples = Motion->GetBlendSamples();
    if(Samples.Num() != 2) { Error = TEXT("exact_idle_walk_samples_required"); return false; }
    int32 IdleCount = 0, WalkCount = 0;
    for(const FBlendSample& Sample : Samples)
    {
        if(Sample.Animation == Idle) ++IdleCount;
        else if(Sample.Animation == Walk) ++WalkCount;
        else { Error = TEXT("unknown_source_clip_refused"); return false; }
        if(Sample.bMirror || Sample.bUseSingleFrameForBlending || !FMath::IsFinite(Sample.RateScale) || Sample.RateScale <= 0)
        { Error = TEXT("unmirrored_full_positive_rate_samples_required"); return false; }
    }
    if(IdleCount != 1 || WalkCount != 1) { Error = TEXT("distinct_idle_walk_roles_required"); return false; }
    ConfiguredMotion = Motion; ConfiguredIdle = Idle; ConfiguredWalk = Walk; ConfiguredMesh = Mesh;
    ConfiguredDelta = ComponentDeltaCm; bEnableCorrection = bEnable; bCaptureDiagnosticPose = bCapture;
    bConfigured = true;
    SetAnimationAsset(Motion, true, 1.f); SetLooping(true); SetPlaying(true);
    return true;
}

void ULivingTownRootCorrectedSingleNodeInstance::NativeInitializeAnimation()
{
    Super::NativeInitializeAnimation();
    // Initialization may reload AnimationData. Reapply the explicitly configured source only afterward.
    if(bConfigured)
    {
        SetAnimationAsset(ConfiguredMotion, true, 1.f); SetLooping(true); SetPlaying(true);
        auto& Proxy = GetProxyOnGameThread<FLivingTownRootCorrectedSingleNodeProxy>();
        Proxy.bReady = false; Proxy.Last = FLivingTownRootCorrectionDiagnostic{};
    }
}

FAnimInstanceProxy* ULivingTownRootCorrectedSingleNodeInstance::CreateAnimInstanceProxy()
{
    return new FLivingTownRootCorrectedSingleNodeProxy(this);
}

bool ULivingTownRootCorrectedSingleNodeInstance::CopyRootCorrectionDiagnostic(FLivingTownRootCorrectionDiagnostic& Out) const
{
    if(!IsInGameThread()) return false;
    Out = GetProxyOnGameThread<FLivingTownRootCorrectedSingleNodeProxy>().Last;
    return true;
}

const TCHAR* ULivingTownRootCorrectedSingleNodeInstance::StateName(EState State)
{
    switch(State)
    {
    case EState::NotEvaluated:return TEXT("NOT_EVALUATED"); case EState::Unconfigured:return TEXT("UNCONFIGURED");
    case EState::UnexpectedAsset:return TEXT("UNEXPECTED_ASSET"); case EState::MissingRecord:return TEXT("MISSING_CURRENT_RECORD");
    case EState::AmbiguousRecord:return TEXT("AMBIGUOUS_CURRENT_RECORD"); case EState::EmptyCache:return TEXT("EMPTY_CURRENT_CACHE");
    case EState::InvalidSample:return TEXT("INVALID_CURRENT_SAMPLE"); case EState::UnknownClip:return TEXT("UNKNOWN_CLIP");
    case EState::PerBoneWeights:return TEXT("PER_BONE_WEIGHTS_UNSUPPORTED"); case EState::InvalidWeightSum:return TEXT("INVALID_WEIGHT_SUM");
    case EState::MirroredEvaluation:return TEXT("MIRRORED_EVALUATION_UNSUPPORTED");
    case EState::InvalidRoot:return TEXT("INVALID_PARENTLESS_ROOT"); case EState::ReadyDisabled:return TEXT("READY_CORRECTION_DISABLED");
    case EState::Applied:return TEXT("APPLIED_WEIGHTED_ROOT_TRANSLATION");
    }
    return TEXT("UNKNOWN_STATE");
}

#if WITH_EDITOR
TArray<FLivingTownRootCorrectionNegativeResult> ULivingTownRootCorrectedSingleNodeInstance::RunGuardNegativeControls(
    UBlendSpace* Motion, UAnimSequence* Idle, UAnimSequence* Walk)
{
    TArray<FLivingTownRootCorrectionNegativeResult> Results;
    TArray<FBlendSampleData> Cache;
    const auto& Authored = Motion->GetBlendSamples();
    for(int32 Index = 0; Index < Authored.Num(); ++Index)
    {
        auto& Row = Cache.AddDefaulted_GetRef(); Row.SampleDataIndex = Index;
        Row.Animation = Authored[Index].Animation; Row.TotalWeight = .5f;
    }
    FAnimTickRecord Record; Record.SourceAsset = Motion; Record.BlendSpace.BlendSampleDataCache = &Cache;
    auto Check = [&](const TCHAR* Name, const TArray<FAnimTickRecord>& Records, EState Expected)
    {
        FLivingTownRootCorrectionDiagnostic D;
        Results.Add({FName(Name), ReadActualIdleWeight(Motion, Motion, Idle, Walk, Records, D), Expected});
    };
    Check(TEXT("positive_two_source_weights"), {Record}, EState::Applied);
    Check(TEXT("missing_current_record"), {}, EState::MissingRecord);
    Check(TEXT("ambiguous_current_record"), {Record, Record}, EState::AmbiguousRecord);
    auto* Unknown = NewObject<UAnimSequence>();
    auto Saved = Cache[0].Animation; Cache[0].Animation = Unknown;
    Check(TEXT("unknown_clip"), {Record}, EState::UnknownClip); Cache[0].Animation = Saved;
    Cache[0].PerBoneBlendData.Add(.5f); Check(TEXT("per_bone_weights"), {Record}, EState::PerBoneWeights); Cache[0].PerBoneBlendData.Reset();
    Results.Add({FName(TEXT("parented_root")), ParentlessRoot(61, 0, 0) ? EState::Applied : EState::InvalidRoot, EState::InvalidRoot});
    Results.Add({FName(TEXT("non_root_mesh_index")), ParentlessRoot(61, 1, INDEX_NONE) ? EState::Applied : EState::InvalidRoot, EState::InvalidRoot});
    return Results;
}
#endif
