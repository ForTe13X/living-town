#include "LivingTownRootCorrectionInspection.h"
#include "LivingTownRootCorrectedSingleNodeInstance.h"
#include "LivingTownAvatarPreparation.h"
#include "Animation/AnimSequence.h"
#include "Animation/AnimInstance.h"
#include "Animation/BlendSpace.h"
#include "AnimationRuntime.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/World.h"
#include "GameFramework/Actor.h"
#include "Rendering/SkeletalMeshRenderData.h"
#include "Rendering/SkeletalMeshLODRenderData.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"

namespace
{
FString Json(const TSharedRef<FJsonObject>& O)
{
    FString Text; const auto Writer = TJsonWriterFactory<>::Create(&Text); FJsonSerializer::Serialize(O, Writer); return Text;
}
TArray<TSharedPtr<FJsonValue>> Vector(const FVector& V)
{
    return {MakeShared<FJsonValueNumber>(V.X), MakeShared<FJsonValueNumber>(V.Y), MakeShared<FJsonValueNumber>(V.Z)};
}
TSharedRef<FJsonObject> Transform(const FTransform& T)
{
    auto O = MakeShared<FJsonObject>(); O->SetArrayField(TEXT("translation"), Vector(T.GetTranslation()));
    O->SetArrayField(TEXT("scale"), Vector(T.GetScale3D())); const FQuat Q = T.GetRotation();
    O->SetArrayField(TEXT("rotation_xyzw"), {MakeShared<FJsonValueNumber>(Q.X), MakeShared<FJsonValueNumber>(Q.Y),
        MakeShared<FJsonValueNumber>(Q.Z), MakeShared<FJsonValueNumber>(Q.W)}); return O;
}
bool Owned(USkeletalMeshComponent* C)
{
    return IsInGameThread() && GIsEditor && !IsRunningCommandlet() && C && C->IsRegistered() &&
        C->GetWorld() && C->GetWorld()->IsEditorWorld() && C->GetOwner() && C->GetOwner()->HasAnyFlags(RF_Transient);
}
TSharedRef<FJsonObject> Diagnostic(const FLivingTownRootCorrectionDiagnostic& D)
{
    auto O = MakeShared<FJsonObject>(); O->SetStringField(TEXT("state"), ULivingTownRootCorrectedSingleNodeInstance::StateName(D.State));
    O->SetNumberField(TEXT("evaluation_serial"), D.EvaluationSerial); O->SetNumberField(TEXT("configuration_generation"), D.ConfigurationGeneration);
    O->SetBoolField(TEXT("correction_enabled"), D.bCorrectionEnabled); O->SetBoolField(TEXT("weight_observed"), D.bWeightObserved);
    O->SetBoolField(TEXT("pose_captured"), D.bPoseCaptured); O->SetBoolField(TEXT("mirror_table_present"), D.bMirrorTablePresent);
    O->SetStringField(TEXT("asset"), D.Asset ? D.Asset->GetPathName() : TEXT("none"));
    O->SetNumberField(TEXT("matching_records"), D.MatchingRecords); O->SetNumberField(TEXT("samples"), D.Samples); O->SetNumberField(TEXT("pose_bones"), D.PoseBones);
    if(D.bWeightObserved) O->SetNumberField(TEXT("actual_idle_weight"), D.IdleWeight);
    else O->SetField(TEXT("actual_idle_weight"), MakeShared<FJsonValueNull>());
    O->SetArrayField(TEXT("requested_delta_cm"), Vector(D.RequestedDelta)); O->SetArrayField(TEXT("applied_delta_cm"), Vector(D.AppliedDelta));
    if(!D.RootBefore.ContainsNaN() && !D.RootAfter.ContainsNaN())
    { O->SetObjectField(TEXT("root_before"), Transform(D.RootBefore)); O->SetObjectField(TEXT("root_after"), Transform(D.RootAfter)); }
    TArray<TSharedPtr<FJsonValue>> Samples, Before, After, Indices;
    for(int32 I = 0; I < FMath::Min(D.Samples, 2); ++I)
    {
        const auto& R = D.SampleRows[I]; auto Row = MakeShared<FJsonObject>();
        Row->SetStringField(TEXT("animation"), R.Animation ? R.Animation->GetPathName() : TEXT("none"));
        Row->SetNumberField(TEXT("sample_index"), R.SampleIndex); Row->SetNumberField(TEXT("time"), R.Time);
        Row->SetNumberField(TEXT("previous_time"), R.PreviousTime); Row->SetNumberField(TEXT("clamped_weight"), R.Weight);
        Row->SetNumberField(TEXT("raw_weight"), R.RawWeight); Samples.Add(MakeShared<FJsonValueObject>(Row));
    }
    for(int32 I : D.MeshBoneIndices) Indices.Add(MakeShared<FJsonValueNumber>(I));
    for(const auto& T : D.LocalBefore) Before.Add(MakeShared<FJsonValueObject>(Transform(T)));
    for(const auto& T : D.LocalAfter) After.Add(MakeShared<FJsonValueObject>(Transform(T)));
    O->SetArrayField(TEXT("actual_sample_cache"), Samples); O->SetArrayField(TEXT("mesh_bone_indices"), Indices);
    O->SetArrayField(TEXT("local_before"), Before); O->SetArrayField(TEXT("local_after"), After); return O;
}
bool ReconstructSkin(USkeletalMeshComponent* C, const FLivingTownRootCorrectionDiagnostic& D,
    const TArray<FTransform>& Captured, TArray<FTransform>& Components, TArray<FVector3f>& Positions)
{
    auto* Mesh = C->GetSkeletalMeshAsset(); if(!Mesh || Captured.Num() != 61 || D.MeshBoneIndices.Num() != 61) return false;
    TArray<FTransform> Local = Mesh->GetRefSkeleton().GetRefBonePose(); if(Local.Num() != 61) return false;
    TArray<bool> Seen; Seen.Init(false, Local.Num());
    for(int32 I = 0; I < Captured.Num(); ++I)
    {
        const int32 Bone = D.MeshBoneIndices[I]; if(!Local.IsValidIndex(Bone) || Seen[Bone] || Captured[I].ContainsNaN()) return false;
        Seen[Bone] = true; Local[Bone] = Captured[I];
    }
    const TArrayView<const FTransform> View(Local);
    FAnimationRuntime::FillUpComponentSpaceTransforms(Mesh->GetRefSkeleton(), View, Components);
    const auto& Inverse = Mesh->GetRefBasesInvMatrix(); if(Inverse.Num() != Components.Num()) return false;
    TArray<FMatrix44f> Matrices; Matrices.SetNum(Components.Num());
    for(int32 I = 0; I < Components.Num(); ++I) Matrices[I] = Inverse[I] * FMatrix44f(Components[I].ToMatrixWithScale());
    const auto* Render = Mesh->GetResourceForRendering(); auto* Skin = C->GetSkinWeightBuffer(0);
    if(!Render || Render->LODRenderData.Num() != 1 || !Skin) return false;
    USkinnedMeshComponent::ComputeSkinnedPositions(C, Positions, Matrices, Render->LODRenderData[0], *Skin);
    return Positions.Num() == 10707;
}
TArray<TSharedPtr<FJsonValue>> Positions(const TArray<FVector3f>& Rows)
{
    TArray<TSharedPtr<FJsonValue>> Values; Values.Reserve(Rows.Num());
    for(const auto& P : Rows) Values.Add(MakeShared<FJsonValueArray>(Vector(FVector(P)))); return Values;
}
TArray<TSharedPtr<FJsonValue>> Transforms(const TArray<FTransform>& Rows)
{
    TArray<TSharedPtr<FJsonValue>> Values; Values.Reserve(Rows.Num());
    for(const auto& T : Rows) Values.Add(MakeShared<FJsonValueObject>(Transform(T))); return Values;
}
}

FString ULivingTownRootCorrectionInspection::ConfigureTemporaryComponent(USkeletalMeshComponent* Component,
    UBlendSpace* Motion, UAnimSequence* Idle, UAnimSequence* Walk, FVector Delta, bool bEnable)
{
    auto O = MakeShared<FJsonObject>(); O->SetStringField(TEXT("status"), TEXT("REFUSED_OWNED_TEMPORARY_COMPONENT"));
    if(!Owned(Component) || !Component->GetSkeletalMeshAsset()) return Json(O);
    const FString Snapshot = ULivingTownAvatarPreparation::ReadAvatarSnapshot(Component->GetSkeletalMeshAsset(), Motion);
    O->SetStringField(TEXT("qualified_source_snapshot_json"), Snapshot);
    TSharedPtr<FJsonObject> Source;
    if(!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Snapshot), Source) || !Source ||
        Source->GetStringField(TEXT("status")) != TEXT("READ_NEW61_REFERENCE_RENDER_SKIN_GEOMETRY"))
    { O->SetStringField(TEXT("status"), TEXT("REFUSED_QUALIFIED_SOURCE_FAMILY_SHAPE")); return Json(O); }
    Component->SetAnimInstanceClass(ULivingTownRootCorrectedSingleNodeInstance::StaticClass());
    auto* Instance = Cast<ULivingTownRootCorrectedSingleNodeInstance>(Component->GetAnimInstance());
    O->SetBoolField(TEXT("custom_instance_created"), Instance != nullptr);
    O->SetBoolField(TEXT("single_node_cast_recognizes_subclass"), Instance && Component->GetSingleNodeInstance() == Instance);
    if(!Instance) return Json(O);
    FString Error; const bool Configured = Instance->ConfigureRootCorrection(Motion, Idle, Walk, Delta, bEnable, true, Error);
    O->SetBoolField(TEXT("configured"), Configured); O->SetStringField(TEXT("configuration_error"), Error);
    O->SetStringField(TEXT("current_asset"), Instance->GetCurrentAsset() ? Instance->GetCurrentAsset()->GetPathName() : TEXT("none"));
    O->SetNumberField(TEXT("animation_mode_integer"), static_cast<int32>(Component->GetAnimationMode()));
    O->SetBoolField(TEXT("PlayAnimation_or_component_teleport_called"), false); O->SetBoolField(TEXT("source_asset_saved"), false);
    O->SetStringField(TEXT("status"), Configured ? TEXT("CONFIGURED_TRANSIENT_NATIVE_STRATEGY_ACTUAL_POSE_PENDING") : TEXT("REFUSED_NATIVE_STRATEGY_CONFIGURATION")); return Json(O);
}

FString ULivingTownRootCorrectionInspection::ReadCorrectionPoseProof(USkeletalMeshComponent* Component)
{
    auto O = MakeShared<FJsonObject>(); O->SetStringField(TEXT("status"), TEXT("REFUSED_OWNED_CONFIGURED_COMPONENT"));
    if(!Owned(Component)) return Json(O);
    auto* Instance = Cast<ULivingTownRootCorrectedSingleNodeInstance>(Component->GetAnimInstance());
    if(!Instance || !Instance->GetCurrentAsset()) return Json(O);
    FLivingTownRootCorrectionDiagnostic Before, After; Instance->CopyRootCorrectionDiagnostic(Before);
    O->SetObjectField(TEXT("diagnostic_before_explicit_evaluation"), Diagnostic(Before));
    const FString ActualNative = ULivingTownAvatarPreparation::ReadAvatarPose(Component);
    O->SetStringField(TEXT("actual_native_pose_json"), ActualNative);
    if(!Instance->CopyRootCorrectionDiagnostic(After)) return Json(O);
    O->SetObjectField(TEXT("same_evaluation_diagnostic"), Diagnostic(After));
    O->SetBoolField(TEXT("evaluation_serial_advanced"), After.EvaluationSerial > Before.EvaluationSerial);
    TSharedPtr<FJsonObject> Native;
    if(!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(ActualNative), Native) || !Native) return Json(O);
    O->SetObjectField(TEXT("native"), Native);
    if(Native->GetStringField(TEXT("status")) != TEXT("READ_ACTUAL_CPU_SKINNED_POSE_EXPLICIT_EVALUATION") ||
        After.EvaluationSerial <= Before.EvaluationSerial || !After.bPoseCaptured ||
        (After.State != ELivingTownRootCorrectionState::Applied && After.State != ELivingTownRootCorrectionState::ReadyDisabled)) return Json(O);
    TArray<FTransform> ComponentBefore, ComponentAfter; TArray<FVector3f> PrePositions, ReconstructedAfter;
    const bool A = ReconstructSkin(Component, After, After.LocalBefore, ComponentBefore, PrePositions);
    const bool B = ReconstructSkin(Component, After, After.LocalAfter, ComponentAfter, ReconstructedAfter);
    O->SetBoolField(TEXT("pre_reconstruction_complete"), A); O->SetBoolField(TEXT("post_reconstruction_complete"), B);
    if(!A || !B) return Json(O);
    O->SetArrayField(TEXT("same_eval_component_before"), Transforms(ComponentBefore));
    O->SetArrayField(TEXT("same_eval_component_after"), Transforms(ComponentAfter));
    O->SetArrayField(TEXT("same_eval_cpu_skinned_before_cm"), Positions(PrePositions));
    O->SetArrayField(TEXT("same_eval_cpu_skinned_after_reconstructed_cm"), Positions(ReconstructedAfter));
    O->SetStringField(TEXT("skin_reconstruction"), TEXT("Public FillUpComponentSpaceTransforms, source inverse reference bases, then ComputeSkinnedPositions; compare reconstructed-after to actual component output before accepting pre/post geometry."));
    O->SetBoolField(TEXT("asset_save_or_recompression"), false); O->SetBoolField(TEXT("old_failed_bake_relabelled"), false);
    O->SetStringField(TEXT("status"), TEXT("READ_ACTUAL_NATIVE_POSTSAMPLE_PAIR_HOST_NUMERIC_GUARDS_PENDING")); return Json(O);
}

FString ULivingTownRootCorrectionInspection::RunCorrectionGuardNegativeControls(UBlendSpace* Motion, UAnimSequence* Idle, UAnimSequence* Walk)
{
    auto O = MakeShared<FJsonObject>(); O->SetStringField(TEXT("status"), TEXT("REFUSED_EDITOR_SOURCE_ROLES"));
    if(!IsInGameThread() || !GIsEditor || IsRunningCommandlet() || !Motion || !Idle || !Walk || Motion->GetBlendSamples().Num() != 2) return Json(O);
    TArray<TSharedPtr<FJsonValue>> Rows; bool Passed = true;
    for(const auto& Result : ULivingTownRootCorrectedSingleNodeInstance::RunGuardNegativeControls(Motion, Idle, Walk))
    {
        auto Row = MakeShared<FJsonObject>(); Row->SetStringField(TEXT("name"), Result.Name.ToString());
        Row->SetStringField(TEXT("actual"), ULivingTownRootCorrectedSingleNodeInstance::StateName(Result.Actual));
        Row->SetStringField(TEXT("expected"), ULivingTownRootCorrectedSingleNodeInstance::StateName(Result.Expected));
        Row->SetBoolField(TEXT("passed"), Result.Actual == Result.Expected); Passed &= Result.Actual == Result.Expected;
        Rows.Add(MakeShared<FJsonValueObject>(Row));
    }
    O->SetArrayField(TEXT("actual_shared_guard_controls"), Rows); O->SetBoolField(TEXT("all_passed"), Passed);
    O->SetBoolField(TEXT("original_asset_mutation"), false); O->SetStringField(TEXT("status"), TEXT("ACTUAL_SHARED_RUNTIME_GUARD_RESULTS_HOST_CHECK_PENDING")); return Json(O);
}

FString ULivingTownRootCorrectionInspection::ReadBaseSingleNodePoseProof(USkeletalMeshComponent* Component, UBlendSpace* ExpectedMotion)
{
    auto O = MakeShared<FJsonObject>(); O->SetStringField(TEXT("status"), TEXT("REFUSED_OWNED_BASE_SINGLE_NODE_COMPONENT"));
    if(!Owned(Component) || !ExpectedMotion) return Json(O);
    auto* Instance = Component->GetSingleNodeInstance();
    if(!Instance || Instance->GetClass() != UAnimSingleNodeInstance::StaticClass() || Instance->GetCurrentAsset() != ExpectedMotion) return Json(O);
    O->SetStringField(TEXT("actual_instance_class"), Instance->GetClass()->GetPathName());
    const FString ActualNative = ULivingTownAvatarPreparation::ReadAvatarPose(Component);
    O->SetStringField(TEXT("actual_native_pose_json"), ActualNative);
    // Public instance getter blocks parallel work and exposes the current read buffer.
    // Read it only after the explicit evaluation, retaining no record/cache pointer.
    const TArray<FAnimTickRecord>& Records = Instance->GetUngroupedActivePlayersRead();
    TArray<TSharedPtr<FJsonValue>> ActualRecords; int32 Matching = 0; bool CacheObserved = false;
    for(const FAnimTickRecord& Record : Records)
    {
        auto R = MakeShared<FJsonObject>(); R->SetStringField(TEXT("source_asset"), Record.SourceAsset ? Record.SourceAsset->GetPathName() : TEXT("none"));
        const bool Match = Record.SourceAsset == ExpectedMotion; R->SetBoolField(TEXT("matches_expected_motion"), Match);
        if(Match)
        {
            ++Matching; const TArray<FBlendSampleData>* Cache = Record.BlendSpace.BlendSampleDataCache;
            R->SetBoolField(TEXT("cache_present"), Cache != nullptr); TArray<TSharedPtr<FJsonValue>> Samples;
            if(Cache)
            {
                CacheObserved = Cache->Num() > 0; R->SetNumberField(TEXT("cache_samples"), Cache->Num());
                for(const FBlendSampleData& Sample : *Cache)
                {
                    auto S = MakeShared<FJsonObject>(); S->SetStringField(TEXT("animation"), Sample.Animation ? Sample.Animation->GetPathName() : TEXT("none"));
                    S->SetNumberField(TEXT("sample_index"), Sample.SampleDataIndex); S->SetNumberField(TEXT("time"), Sample.Time);
                    S->SetNumberField(TEXT("previous_time"), Sample.PreviousTime); S->SetNumberField(TEXT("raw_weight"), Sample.TotalWeight);
                    S->SetNumberField(TEXT("clamped_weight"), Sample.GetClampedWeight()); S->SetNumberField(TEXT("per_bone_weights"), Sample.PerBoneBlendData.Num());
                    S->SetNumberField(TEXT("per_bone_weight_rates"), Sample.PerBoneWeightRate.Num()); Samples.Add(MakeShared<FJsonValueObject>(S));
                }
            }
            R->SetArrayField(TEXT("samples"), Samples);
        }
        ActualRecords.Add(MakeShared<FJsonValueObject>(R));
    }
    O->SetArrayField(TEXT("actual_current_records_before_host_guards"), ActualRecords);
    O->SetNumberField(TEXT("matching_records"), Matching); O->SetBoolField(TEXT("matching_nonempty_cache_observed"), CacheObserved);
    TSharedPtr<FJsonObject> Native;
    if(!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(ActualNative), Native) || !Native) return Json(O);
    O->SetObjectField(TEXT("native"), Native);
    if(Native->GetStringField(TEXT("status")) != TEXT("READ_ACTUAL_CPU_SKINNED_POSE_EXPLICIT_EVALUATION") || Matching != 1 || !CacheObserved) return Json(O);
    O->SetBoolField(TEXT("weights_inferred_from_speed"), false); O->SetBoolField(TEXT("asset_mutation_or_save"), false);
    O->SetStringField(TEXT("status"), TEXT("READ_ACTUAL_BASE_SINGLE_NODE_POSE_AND_CACHE_HOST_GUARDS_PENDING")); return Json(O);
}
