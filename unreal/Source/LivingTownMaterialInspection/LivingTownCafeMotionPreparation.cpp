#include "LivingTownCafeMotionPreparation.h"
#include "Animation/BlendSpace.h"
#include "Animation/BlendSpace1D.h"
#include "Animation/AnimSequence.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "HAL/FileManager.h"
#include "UObject/Package.h"
#include "UObject/SavePackage.h"
#include "UObject/UObjectGlobals.h"

namespace
{
static const TCHAR* SourcePath=TEXT("/Game/LivingTown_UEPilot/BenMotion/BenIdleWalk_v001.BenIdleWalk_v001");
static const TCHAR* DestinationPackage=TEXT("/Game/LivingTown_UEPilot/BenMotion/BenIdleWalk_v002");
FString SerializeCafeMotionJson(const TSharedRef<FJsonObject>& Object)
{
    FString Text;const auto Writer=TJsonWriterFactory<>::Create(&Text);FJsonSerializer::Serialize(Object,Writer);return Text;
}
TSharedRef<FJsonObject> Snapshot(UBlendSpace* Motion)
{
    auto Result=MakeShared<FJsonObject>();Result->SetStringField(TEXT("status"),TEXT("REFUSED_TYPE_THREAD_OR_BOUNDS"));
    if(!IsInGameThread()||!GIsEditor||!Motion||!Motion->IsA<UBlendSpace1D>()||Motion->GetBlendSamples().Num()>8)return Result;
    Result->SetStringField(TEXT("asset"),Motion->GetPathName());Result->SetNumberField(TEXT("raw_sample_count"),Motion->GetBlendSamples().Num());Result->SetNumberField(TEXT("runtime_segments"),Motion->GetBlendSpaceData().Segments.Num());Result->SetNumberField(TEXT("runtime_triangles"),Motion->GetBlendSpaceData().Triangles.Num());Result->SetNumberField(TEXT("runtime_grid_samples"),Motion->GetGridSamples().Num());Result->SetBoolField(TEXT("package_dirty"),Motion->GetOutermost()->IsDirty());
    TArray<TSharedPtr<FJsonValue>> Raw,Probes;bool Valid=Motion->GetBlendSamples().Num()==2;
    const UAnimSequence* Idle=nullptr;const UAnimSequence* Walk=nullptr;
    for(const FBlendSample& Sample:Motion->GetBlendSamples())
    {
        auto Row=MakeShared<FJsonObject>();Row->SetStringField(TEXT("animation"),Sample.Animation?Sample.Animation->GetPathName():TEXT("missing"));Row->SetNumberField(TEXT("speed_cm_s"),Sample.SampleValue.X);Row->SetNumberField(TEXT("rate_scale"),Sample.RateScale);Row->SetBoolField(TEXT("single_frame"),Sample.bUseSingleFrameForBlending);Raw.Add(MakeShared<FJsonValueObject>(Row));
        Valid&=Sample.Animation&&Sample.Animation->GetSkeleton()==Motion->GetSkeleton()&&Sample.Animation->GetPlayLength()>0&&Sample.RateScale>0&&!Sample.bUseSingleFrameForBlending;
        if(FMath::IsNearlyZero(Sample.SampleValue.X,.001))Idle=Sample.Animation;if(FMath::IsNearlyEqual(Sample.SampleValue.X,180.,.001))Walk=Sample.Animation;
    }
    Valid&=Idle&&Walk&&Idle!=Walk&&FMath::IsNearlyZero(Motion->GetBlendParameter(0).Min,.001f)&&FMath::IsNearlyEqual(Motion->GetBlendParameter(0).Max,180.f,.001f);
    for(const double Fraction:{0.0,0.5,1.0})
    {
        TArray<FBlendSampleData> Weights;int32 CachedSegment=INDEX_NONE;const bool Got=Motion->GetSamplesFromBlendInput(FVector(180.*Fraction,0,0),Weights,CachedSegment,true);
        auto Probe=MakeShared<FJsonObject>();Probe->SetNumberField(TEXT("speed_cm_s"),180.*Fraction);Probe->SetBoolField(TEXT("sampler_returned_data"),Got);TArray<TSharedPtr<FJsonValue>> Rows;double IdleWeight=0,WalkWeight=0;bool Good=Got&&Weights.Num()>=1&&Weights.Num()<=2;
        for(const auto& Weight:Weights)
        {
            auto Row=MakeShared<FJsonObject>();Row->SetStringField(TEXT("animation"),Weight.Animation?Weight.Animation->GetPathName():TEXT("missing"));Row->SetNumberField(TEXT("weight"),Weight.TotalWeight);Row->SetNumberField(TEXT("source_index"),Weight.SampleDataIndex);Rows.Add(MakeShared<FJsonValueObject>(Row));
            Good&=FMath::IsFinite(Weight.TotalWeight)&&Weight.TotalWeight>0&&(Weight.Animation==Idle||Weight.Animation==Walk);if(Weight.Animation==Idle)IdleWeight+=Weight.TotalWeight;if(Weight.Animation==Walk)WalkWeight+=Weight.TotalWeight;
        }
        Good&=FMath::IsNearlyEqual(IdleWeight,1.-Fraction,.001)&&FMath::IsNearlyEqual(WalkWeight,Fraction,.001);Probe->SetBoolField(TEXT("correct_two_clip_weights"),Good);Probe->SetArrayField(TEXT("weights"),Rows);Probes.Add(MakeShared<FJsonValueObject>(Probe));Valid&=Good;
    }
    Result->SetArrayField(TEXT("raw_samples"),Raw);Result->SetArrayField(TEXT("speed_probes"),Probes);Result->SetBoolField(TEXT("runtime_interpolation_qualified"),Valid);Result->SetStringField(TEXT("status"),Valid?TEXT("PASS_STATIC_RUNTIME_INTERPOLATION_NO_PLAYBACK_CLAIM"):TEXT("FAIL_RUNTIME_INTERPOLATION"));return Result;
}
}
FString ULivingTownCafeMotionPreparation::ReadCafeMotionInterpolation(UBlendSpace* Motion)
{
    return SerializeCafeMotionJson(Snapshot(Motion));
}
FString ULivingTownCafeMotionPreparation::BuildCafeMotionInterpolationDerivative(UBlendSpace* Source)
{
    auto Result=MakeShared<FJsonObject>();Result->SetStringField(TEXT("status"),TEXT("REFUSED_SOURCE_DESTINATION_OR_EDITOR_CONTEXT"));
    if(!IsInGameThread()||!GIsEditor||!Source||Source->GetPathName()!=SourcePath||!Source->IsA<UBlendSpace1D>()||Source->GetOutermost()->HasAnyPackageFlags(PKG_PlayInEditor)||Source->GetBlendSamples().Num()!=2)return SerializeCafeMotionJson(Result);
    const FString Filename=FPackageName::LongPackageNameToFilename(DestinationPackage,FPackageName::GetAssetPackageExtension());const FString Root=FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir());const FString Absolute=FPaths::ConvertRelativePathToFull(Filename);
    if(!FPaths::IsUnderDirectory(Absolute,Root)||IFileManager::Get().FileExists(*Absolute)||FindPackage(nullptr,DestinationPackage))return SerializeCafeMotionJson(Result);
    const auto Before=Snapshot(Source);Result->SetObjectField(TEXT("original_before"),Before);
    UPackage* Package=CreatePackage(DestinationPackage);UBlendSpace* Candidate=DuplicateObject<UBlendSpace>(Source,Package,TEXT("BenIdleWalk_v002"));
    if(!Candidate){Result->SetStringField(TEXT("status"),TEXT("FAIL_DUPLICATE"));return SerializeCafeMotionJson(Result);}
    Candidate->ClearFlags(RF_Transient);Candidate->SetFlags(RF_Public|RF_Standalone);Candidate->ResampleData();const auto After=Snapshot(Candidate);Result->SetObjectField(TEXT("derivative_after_resample"),After);
    if(!After->GetBoolField(TEXT("runtime_interpolation_qualified"))){Result->SetStringField(TEXT("status"),TEXT("FAIL_DERIVATIVE_INTERPOLATION_NOT_SAVED"));return SerializeCafeMotionJson(Result);}
    Candidate->MarkPackageDirty();FSavePackageArgs Args;Args.TopLevelFlags=RF_Public|RF_Standalone;Args.SaveFlags=SAVE_None;Args.bSlowTask=false;
    if(!UPackage::SavePackage(Package,Candidate,*Absolute,Args)){Result->SetStringField(TEXT("status"),TEXT("FAIL_NEW_DERIVATIVE_SAVE"));return SerializeCafeMotionJson(Result);}
    Result->SetObjectField(TEXT("original_after"),Snapshot(Source));Result->SetStringField(TEXT("derivative_asset"),Candidate->GetPathName());Result->SetStringField(TEXT("derivative_filename"),Absolute);Result->SetStringField(TEXT("status"),TEXT("PASS_NEW_RESAMPLED_DERIVATIVE_REOPEN_AND_ACTUAL_PLAYBACK_PENDING"));Result->SetBoolField(TEXT("original_asset_saved_or_resampled"),false);Result->SetBoolField(TEXT("actual_walk_animation_art_or_FPS_qualified"),false);return SerializeCafeMotionJson(Result);
}
