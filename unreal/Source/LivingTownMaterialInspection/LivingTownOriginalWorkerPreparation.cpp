#include "LivingTownOriginalWorkerPreparation.h"
#include "LivingTownOriginalWorkerAssembly.h"
#include "LivingTownCafeBinding.h"
#include "Animation/AnimSequence.h"
#include "Animation/Skeleton.h"
#include "Animation/AnimBoneCompressionSettings.h"
#include "Animation/AnimBoneCompressionCodec.h"
#include "Animation/AnimData/IAnimationDataController.h"
#include "Animation/AnimData/IAnimationDataModel.h"
#include "Animation/BlendSpace1D.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/SkeletalMeshSocket.h"
#include "AssetCompilingManager.h"
#include "UObject/Package.h"
#include "UObject/SavePackage.h"
#include "UObject/UnrealType.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/BufferArchive.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "HAL/FileManager.h"
#include "Containers/StringConv.h"

namespace
{
FString Json(const TSharedRef<FJsonObject>& O){FString S;FJsonSerializer::Serialize(O,TJsonWriterFactory<>::Create(&S));return S;}
TArray<TSharedPtr<FJsonValue>> Vec(const FVector& P){return {MakeShared<FJsonValueNumber>(P.X),MakeShared<FJsonValueNumber>(P.Y),MakeShared<FJsonValueNumber>(P.Z)};}
TSharedRef<FJsonObject> TransformJson(const FTransform& T)
{
    auto O=MakeShared<FJsonObject>();O->SetArrayField(TEXT("translation_cm"),Vec(T.GetTranslation()));O->SetArrayField(TEXT("scale"),Vec(T.GetScale3D()));const auto Q=T.GetRotation();
    O->SetArrayField(TEXT("rotation_xyzw"),{MakeShared<FJsonValueNumber>(Q.X),MakeShared<FJsonValueNumber>(Q.Y),MakeShared<FJsonValueNumber>(Q.Z),MakeShared<FJsonValueNumber>(Q.W)});return O;
}
bool Vector(const FJsonObject& O,const TCHAR* Key,FVector& V)
{
    const TArray<TSharedPtr<FJsonValue>>* A=nullptr;if(!O.TryGetArrayField(Key,A)||A->Num()!=3)return false;double X[3];
    for(int32 I=0;I<3;++I)if((*A)[I]->Type!=EJson::Number||!FMath::IsFinite(X[I]=(*A)[I]->AsNumber())||FMath::Abs(X[I])>1000.)return false;V=FVector(X[0],X[1],X[2]);return true;
}
bool Write(const FString& Root,const TCHAR* Name,const TSharedRef<FJsonObject>& O){return FFileHelper::SaveStringToFile(Json(O),*(Root/Name),FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);}
bool FileHash(const FString& Path,FString& Out)
{
    TArray<uint8> B;const int64 Size=IFileManager::Get().FileSize(*Path);return Size>0&&Size<256*1024*1024&&FFileHelper::LoadFileToArray(B,*Path)&&LivingTownCafeJournal::Sha256(B,Out);
}
bool Fresh(const TCHAR* ObjectPath)
{
    const FString P=FPackageName::ObjectPathToPackageName(FString(ObjectPath));return !FindPackage(nullptr,*P)&&!FPackageName::DoesPackageExist(P);
}
template<class T>T* Duplicate(T* Source,const TCHAR* Path)
{
    const FString P=FPackageName::ObjectPathToPackageName(FString(Path));return DuplicateObject<T>(Source,CreatePackage(*P),FName(*FPackageName::GetLongPackageAssetName(P)));
}
bool Save(UObject* O)
{
    const FString File=FPackageName::LongPackageNameToFilename(O->GetOutermost()->GetName(),FPackageName::GetAssetPackageExtension());
    if(IFileManager::Get().FileExists(*File)||!FPaths::IsUnderDirectory(FPaths::ConvertRelativePathToFull(File),FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir())))return false;
    IFileManager::Get().MakeDirectory(*FPaths::GetPath(File),true);FSavePackageArgs A;A.TopLevelFlags=RF_Public|RF_Standalone;O->MarkPackageDirty();return UPackage::SavePackage(O->GetOutermost(),O,*File,A);
}
bool Keys(UAnimSequence* Clip,FName Except,FBufferArchive& Out)
{
    auto* Model=Clip->GetDataModel();if(!Model)return false;TArray<FName> Names;Model->GetBoneTrackNames(Names);
    for(FName N:Names)if(N!=Except)
    {
        FString Name=N.ToString();Out<<Name;
        Model->IterateBoneKeys(N,[&](const FVector3f& P,const FQuat4f& Q,const FVector3f S,const FFrameNumber& Frame){int32 F=Frame.Value;Out<<F;auto X=P;auto R=Q;auto Scale=S;Out<<X;Out<<R;Out<<Scale;return true;});
    }
    return true;
}
bool Normalize(UAnimSequence* Source,const TCHAR* Path,const FVector& Offset,const FReferenceSkeleton& Ref,UAnimSequence*& Out,TSharedRef<FJsonObject> Report)
{
    if(!Source||Source->RateScale!=1.f||Source->bEnableRootMotion||Source->bForceRootLock||Source->IsValidAdditive()||Source->GetSamplingFrameRate()!=FFrameRate(30,1)||Source->CompressionErrorThresholdScale!=1.f)return false;
    Source->WaitOnExistingCompression();auto* Model=Source->GetDataModel();if(!Model)return false;const auto GuidBefore=Model->GenerateGuid();
    IAnimationDataModel::FGuidGenerationSettings NonBone;NonBone.bIncludeBoneData=false;const auto CurvesBefore=Model->GenerateGuid(NonBone);
    const FName Wrapper(LivingTownOriginalWorker::Wrapper);FBufferArchive Before;if(!Keys(Source,Wrapper,Before))return false;
    FTransform Root;Source->GetBoneTransform(Root,FSkeletonPoseBoneIndex(0),FAnimExtractContext(0.,false),true);
    // A constant wrapper correction is valid only for an actually constant
    // wrapper. Preserve its complete source T/R/S, including the retained scale.
    const int32 Count=Source->GetNumberOfSampledKeys();for(int32 K=0;K<Count;++K){FTransform T;Source->GetBoneTransform(T,FSkeletonPoseBoneIndex(0),FAnimExtractContext(double(K)/30.,false),true);if(!T.Equals(Root,1.e-8))return false;}
    Out=Duplicate(Source,Path);if(!Out||Out->GetDataModel()==Model||!Out->GetDataModelInterface().GetObject()||Out->GetDataModelInterface().GetObject()->GetOuter()!=Out)return false;
    auto* Settings=Source->BoneCompressionSettings.Get();if(!Settings||Settings->Codecs.Num()!=1)return false;
    auto* Codec=Settings->Codecs[0].Get();const auto* Precision=Codec?FindFProperty<FFloatProperty>(Codec->GetClass(),TEXT("ErrorThreshold")):nullptr;
    if(!Codec||Codec->GetClass()->GetPathName()!=TEXT("/Script/ACLPlugin.AnimBoneCompressionCodec_ACL")||!Precision||Precision->GetPropertyValue_InContainer(Codec)!=1.e-6f)return false;
    Out->BoneCompressionSettings=DuplicateObject<UAnimBoneCompressionSettings>(Settings,Out,TEXT("OwnedCompression"));
    auto* Owned=Out->BoneCompressionSettings.Get();if(!Owned||Owned==Settings||Owned->Codecs.Num()!=1||Owned->Codecs[0]==Codec||!Owned->Codecs[0]->IsIn(Out)||Precision->GetPropertyValue_InContainer(Owned->Codecs[0].Get())!=1.e-6f)return false;
    {
        auto& Controller=Out->GetController();IAnimationDataController::FScopedBracket Bracket(Controller,FText::FromString(TEXT("Original worker constant wrapper anchor")),false);
        TArray<FName> Names;Out->GetDataModel()->GetBoneTrackNames(Names);if(!Names.Contains(Wrapper)&&!Controller.AddBoneCurve(Wrapper,false))return false;
        if(!Controller.SetBoneTrackKeys(Wrapper,TArray<FVector3f>{FVector3f(Root.GetTranslation()+Offset)},TArray<FQuat4f>{FQuat4f(Root.GetRotation())},TArray<FVector3f>{FVector3f(Root.GetScale3D())},false))return false;
    }
    Out->CacheDerivedDataForCurrentPlatform();Out->WaitOnExistingCompression();FBufferArchive After;if(!Keys(Out,Wrapper,After))return false;
    const bool Same=Before.Num()==After.Num()&&FMemory::Memcmp(Before.GetData(),After.GetData(),Before.Num())==0;
    double MaximumTranslation=0.,MaximumRotation=0.,MaximumScale=0.;
    // Keys and half keys: original61 locals stay exact; component-space poses
    // must differ only by the declared rigid translation. No pose flattening.
    for(int32 K=0;K<2*Count-1;++K)
    {
        TArray<FTransform> A,B;A.SetNum(62);B.SetNum(62);const double Time=double(K)/60.;
        for(int32 J=0;J<62;++J)
        {
            Source->GetBoneTransform(A[J],FSkeletonPoseBoneIndex(J),FAnimExtractContext(Time,false),true);Out->GetBoneTransform(B[J],FSkeletonPoseBoneIndex(J),FAnimExtractContext(Time,false),true);
            const int32 Parent=Ref.GetParentIndex(J);if(Parent!=INDEX_NONE){A[J]=A[J]*A[Parent];B[J]=B[J]*B[Parent];}
            MaximumTranslation=FMath::Max(MaximumTranslation,(B[J].GetTranslation()-A[J].GetTranslation()-Offset).GetAbsMax());MaximumRotation=FMath::Max(MaximumRotation,1.-FMath::Abs(A[J].GetRotation()|B[J].GetRotation()));MaximumScale=FMath::Max(MaximumScale,(A[J].GetScale3D()-B[J].GetScale3D()).GetAbsMax());
        }
    }
    Report->SetStringField(TEXT("source"),Source->GetPathName());Report->SetStringField(TEXT("derived"),Out->GetPathName());Report->SetArrayField(TEXT("constant_component_offset_cm"),Vec(Offset));Report->SetObjectField(TEXT("actual_original_wrapper_local"),TransformJson(Root));
    Report->SetBoolField(TEXT("original_nonwrapper_keys_byte_identical"),Same);Report->SetBoolField(TEXT("curves_attributes_timing_identical"),Out->GetDataModel()->GenerateGuid(NonBone)==CurvesBefore);Report->SetBoolField(TEXT("source_data_guid_unchanged"),Model->GenerateGuid()==GuidBefore);
    Report->SetNumberField(TEXT("raw_component_translation_residual_cm"),MaximumTranslation);Report->SetNumberField(TEXT("raw_component_quaternion_dot_residual"),MaximumRotation);Report->SetNumberField(TEXT("raw_component_scale_residual"),MaximumScale);Report->SetNumberField(TEXT("samples_keys_and_halfkeys"),2*Count-1);Report->SetNumberField(TEXT("owned_ACL_error_threshold"),Precision->GetPropertyValue_InContainer(Owned->Codecs[0].Get()));
    Report->SetBoolField(TEXT("compressed100micrometre_fidelity_or_Game_movement_qualified"),false);
    return Same&&Model->GenerateGuid()==GuidBefore&&Out->GetDataModel()->GenerateGuid(NonBone)==CurvesBefore&&Out->GetNumberOfSampledKeys()==Count&&Out->GetPlayLength()==Source->GetPlayLength()&&MaximumTranslation<1.e-4&&MaximumRotation<1.e-10&&MaximumScale<1.e-8;
}
}

FString ULivingTownOriginalWorkerPreparation::PrepareOriginalWorkerBen(const FString& CalibrationPath,const FString& ReportDirectory)
{
    auto Report=MakeShared<FJsonObject>();Report->SetStringField(TEXT("status"),TEXT("REFUSED_ORIGINAL_WORKER_PREPARATION"));FString Stage=TEXT("entry");
    auto Fail=[&](const TCHAR* Why){Report->SetStringField(TEXT("stage"),Stage);Report->SetStringField(TEXT("reason"),Why);if(IFileManager::Get().DirectoryExists(*ReportDirectory))Write(ReportDirectory,TEXT("REPORT.json"),Report);return Json(Report);};
    if(!IsInGameThread()||!FParse::Param(FCommandLine::Get(),TEXT("LivingTownPrepareOriginalWorkerBen"))||ReportDirectory.IsEmpty()||IFileManager::Get().DirectoryExists(*ReportDirectory)||
       !FPaths::IsUnderDirectory(FPaths::ConvertRelativePathToFull(ReportDirectory),FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir())))return Fail(TEXT("explicit_preparation_and_fresh_owned_Saved_directory_required"));
    IFileManager::Get().MakeDirectory(*ReportDirectory,true);FString Text;TSharedPtr<FJsonObject> Input;
    if(IFileManager::Get().FileSize(*CalibrationPath)>128*1024||!FFileHelper::LoadFileToString(Text,*CalibrationPath)||!LivingTownCafeJournal::HasUniqueObjectKeys(Text)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),Input)||!Input)return Fail(TEXT("explicit_measured_calibration_required"));
    FString Format,Closure;double Version=0.,Radius=0.,Half=0.;FVector IdleOffset,WalkOffset,MeshOffset;
    if(!Input->TryGetStringField(TEXT("format"),Format)||Format!=TEXT("LivingTown.OriginalWorkerBenCalibration")||!Input->TryGetNumberField(TEXT("version"),Version)||Version!=1.||
       !Input->TryGetStringField(TEXT("source_closure_sha256"),Closure)||Closure.Len()!=64||!Vector(*Input,TEXT("idle_offset_cm"),IdleOffset)||!Vector(*Input,TEXT("walk_offset_cm"),WalkOffset)||!Vector(*Input,TEXT("mesh_translation_from_capsule_cm"),MeshOffset)||
       !Input->TryGetNumberField(TEXT("capsule_radius_cm"),Radius)||!Input->TryGetNumberField(TEXT("capsule_half_height_cm"),Half)||!FMath::IsFinite(Radius)||!FMath::IsFinite(Half)||Radius<10.||Radius>40.||Half<70.||Half>110.||IdleOffset.Z!=0.||WalkOffset.Z!=0.||IdleOffset.GetAbsMax()>100.||WalkOffset.GetAbsMax()>100.)return Fail(TEXT("measured_horizontal_anchors_and_physical_capsule_required"));
    const TArray<TSharedPtr<FJsonValue>> *Files=nullptr,*PalmRows=nullptr;
    if(!Input->TryGetArrayField(TEXT("source_packages"),Files)||Files->IsEmpty()||Files->Num()>64||!Input->TryGetArrayField(TEXT("palm_REST_component_row_major"),PalmRows)||PalmRows->Num()!=4)return Fail(TEXT("bound_source_packages_and_measured_REST_palm_required"));
    TMap<FString,FString> SourceHashes;TArray<UObject*> ClosureAssets;FString ClosureText=TEXT("LivingTown.OriginalWorkerSourcePackages.v1\n");
    auto Guard=[&](){for(const auto& P:SourceHashes){FString H;if(!FileHash(P.Key,H)||H!=P.Value)return false;}return true;};
    for(const auto& Entry:*Files)
    {
        if(!Entry||Entry->Type!=EJson::Object)return Fail(TEXT("source_package_entry_required"));FString Path,Expected;const auto O=Entry->AsObject();
        if(!O->TryGetStringField(TEXT("object"),Path)||!Path.StartsWith(TEXT("/Game/Worker110Prototype/"))||Path.Contains(TEXT(".."))||!O->TryGetStringField(TEXT("sha256"),Expected)||Expected.Len()!=64)return Fail(TEXT("exact_prototype_source_package_binding_required"));
        const FString File=FPackageName::LongPackageNameToFilename(FPackageName::ObjectPathToPackageName(Path),FPackageName::GetAssetPackageExtension());FString Actual;
        if(SourceHashes.Contains(File)||!FileHash(File,Actual)||Actual!=Expected)return Fail(TEXT("source_package_hash_mismatch"));SourceHashes.Add(File,Expected);UObject* Asset=LoadObject<UObject>(nullptr,*Path);if(!Asset)return Fail(TEXT("bound_source_package_object_missing"));ClosureAssets.Add(Asset);ClosureText+=Path+TEXT("\n")+Expected+TEXT("\n");
    }
    FTCHARToUTF8 Encoded(*ClosureText);TArray<uint8> ClosureBytes;ClosureBytes.Append(reinterpret_cast<const uint8*>(Encoded.Get()),Encoded.Length());FString MeasuredClosure;
    if(!LivingTownCafeJournal::Sha256(ClosureBytes,MeasuredClosure)||MeasuredClosure!=Closure)return Fail(TEXT("actual_source_package_closure_hash_required"));
    for(const TCHAR* Path:{LivingTownOriginalWorker::Body,LivingTownOriginalWorker::Idle,LivingTownOriginalWorker::Walk,LivingTownOriginalWorker::Motion})if(!Fresh(Path))return Fail(TEXT("all_four_owned_derivative_destinations_must_be_fresh"));
    auto* Body=LoadObject<USkeletalMesh>(nullptr,LivingTownOriginalWorker::BodySource);auto* Idle=LoadObject<UAnimSequence>(nullptr,LivingTownOriginalWorker::IdleSource);auto* Walk=LoadObject<UAnimSequence>(nullptr,LivingTownOriginalWorker::WalkSource);
    if(!Body||!Idle||!Walk||!ClosureAssets.Contains(Body)||!ClosureAssets.Contains(Idle)||!ClosureAssets.Contains(Walk)||Body->GetRefSkeleton().GetNum()!=62||Body->GetRefSkeleton().GetBoneName(0)!=FName(LivingTownOriginalWorker::Wrapper)||Idle->GetSkeleton()!=Body->GetSkeleton()||Walk->GetSkeleton()!=Body->GetSkeleton())return Fail(TEXT("closed_original62_body_and_both_source_clips_required"));
    if(!ClosureAssets.Contains(Body->GetSkeleton()))return Fail(TEXT("shared_skeleton_must_belong_to_bound_closure"));
    for(const TCHAR* Path:{LivingTownOriginalWorker::Underlay,LivingTownOriginalWorker::Cloth,LivingTownOriginalWorker::Collision})if(!ClosureAssets.Contains(LoadObject<UObject>(nullptr,Path)))return Fail(TEXT("complete_runtime_support_cloth_collision_source_closure_required"));
    for(const auto& Path:LivingTownOriginalWorker::Materials())if(!ClosureAssets.Contains(LoadObject<UObject>(nullptr,*Path)))return Fail(TEXT("three_saved_materials_in_source_closure_required"));
    FMatrix PalmMatrix=FMatrix::Identity;for(int32 R=0;R<4;++R){const auto& Row=(*PalmRows)[R];if(Row->Type!=EJson::Array||Row->AsArray().Num()!=4)return Fail(TEXT("palm_matrix_requires4x4"));for(int32 C=0;C<4;++C){const auto& V=Row->AsArray()[C];if(V->Type!=EJson::Number||!FMath::IsFinite(PalmMatrix.M[R][C]=V->AsNumber()))return Fail(TEXT("finite_palm_matrix_required"));}}
    FTransform PalmComponent(PalmMatrix);if(!PalmComponent.IsValid()||!PalmComponent.GetScale3D().Equals(FVector::OneVector,1.e-5)||PalmMatrix.M[0][3]!=0.||PalmMatrix.M[1][3]!=0.||PalmMatrix.M[2][3]!=0.||PalmMatrix.M[3][3]!=1.||PalmMatrix.Determinant()<=0.||!PalmComponent.ToMatrixWithScale().Equals(PalmMatrix,1.e-5))return Fail(TEXT("measured_unit_REST_palm_frame_required"));
    auto Reference=Body->GetRefSkeleton().GetRefBonePose();const auto& Ref=Body->GetRefSkeleton();for(int32 J=0;J<Reference.Num();++J){const int32 P=Ref.GetParentIndex(J);if(P!=INDEX_NONE)Reference[J]=Reference[J]*Reference[P];}
    const int32 Hand=Ref.FindBoneIndex(FName(TEXT("hand_r")));if(Hand==INDEX_NONE)return Fail(TEXT("actual_hand_r_required"));const FTransform PalmLocal=FTransform(PalmMatrix*Reference[Hand].ToInverseMatrixWithScale());
    // This is the full actual bone inverse; its retained scale is not discarded.
    if(!(PalmLocal*Reference[Hand]).Equals(PalmComponent,1.e-5))return Fail(TEXT("actual_hand_inverse_palm_roundtrip_failed"));
    Stage=TEXT("owned_derivatives");auto* DerivedBody=Duplicate(Body,LivingTownOriginalWorker::Body);if(!DerivedBody||DerivedBody->FindSocket(FName(LivingTownOriginalWorker::Palm)))return Fail(TEXT("fresh_body_owned_palm_required"));
    auto* Socket=NewObject<USkeletalMeshSocket>(DerivedBody);Socket->SocketName=FName(LivingTownOriginalWorker::Palm);Socket->BoneName=FName(TEXT("hand_r"));Socket->RelativeLocation=PalmLocal.GetTranslation();Socket->RelativeRotation=PalmLocal.Rotator();Socket->RelativeScale=PalmLocal.GetScale3D();DerivedBody->GetMeshOnlySocketList().Add(Socket);
    if(!(Socket->GetSocketLocalTransform()*Reference[Hand]).Equals(PalmComponent,1.e-5))return Fail(TEXT("actual_socket_hand_roundtrip_failed"));
    UAnimSequence *DerivedIdle=nullptr,*DerivedWalk=nullptr;auto IR=MakeShared<FJsonObject>(),WR=MakeShared<FJsonObject>();
    const bool IdleOK=Normalize(Idle,LivingTownOriginalWorker::Idle,IdleOffset,Ref,DerivedIdle,IR);Report->SetObjectField(TEXT("idle"),IR);Write(ReportDirectory,TEXT("REPORT.json"),Report);if(!IdleOK)return Fail(TEXT("idle_wrapper_normalization_or_preservation_refused"));
    const bool WalkOK=Normalize(Walk,LivingTownOriginalWorker::Walk,WalkOffset,Ref,DerivedWalk,WR);Report->SetObjectField(TEXT("walk"),WR);Write(ReportDirectory,TEXT("REPORT.json"),Report);if(!WalkOK)return Fail(TEXT("walk_wrapper_normalization_or_preservation_refused"));
    const FString BP=FPackageName::ObjectPathToPackageName(FString(LivingTownOriginalWorker::Motion));auto* Motion=NewObject<UBlendSpace1D>(CreatePackage(*BP),FName(TEXT("BS_IdleWalk")),RF_Public|RF_Standalone);Motion->SetSkeleton(Body->GetSkeleton());
    auto* Property=FindFProperty<FStructProperty>(UBlendSpace::StaticClass(),TEXT("BlendParameters"));if(!Property||Property->ArrayDim!=3||Property->Struct!=FBlendParameter::StaticStruct()||!Property->HasAnyPropertyFlags(CPF_Edit))return Fail(TEXT("typed_editable_BlendSpace_axis_required"));
    auto* Axis=Property->ContainerPtrToValuePtr<FBlendParameter>(Motion,0);Axis->DisplayName=TEXT("Speed cm/s");Axis->Min=0.f;Axis->Max=float(LivingTownOriginalWorker::WalkSpeedCmS);Axis->GridNum=4;Axis->bSnapToGrid=false;Axis->bWrapInput=false;
    Motion->bScaleAnimation=false;Motion->TargetWeightInterpolationSpeedPerSec=0.f;Motion->InterpolationParam[0].InterpolationTime=0.f;
    if(Motion->AddSample(DerivedIdle,FVector::ZeroVector)==INDEX_NONE||Motion->AddSample(DerivedWalk,FVector(float(LivingTownOriginalWorker::WalkSpeedCmS),0,0))==INDEX_NONE)return Fail(TEXT("two_whole_derived_clip_samples_required"));Motion->ValidateSampleData();Motion->ResampleData();
    TArray<TSharedPtr<FJsonValue>> Probes;for(double F:{0.,.5,1.}){TArray<FBlendSampleData> Weights;int32 Segment=INDEX_NONE;double I=0.,W=0.;if(!Motion->GetSamplesFromBlendInput(FVector(LivingTownOriginalWorker::WalkSpeedCmS*F,0,0),Weights,Segment,true))return Fail(TEXT("built_runtime_sampler_required"));for(const auto& X:Weights){if(X.Animation==DerivedIdle)I+=X.TotalWeight;else if(X.Animation==DerivedWalk)W+=X.TotalWeight;else return Fail(TEXT("unexpected_runtime_sample"));}if(!FMath::IsNearlyEqual(I,1.-F,.001)||!FMath::IsNearlyEqual(W,F,.001))return Fail(TEXT("built_runtime_weights_required"));auto P=MakeShared<FJsonObject>();P->SetNumberField(TEXT("fraction"),F);P->SetNumberField(TEXT("idle_weight"),I);P->SetNumberField(TEXT("walk_weight"),W);Probes.Add(MakeShared<FJsonValueObject>(P));}Report->SetArrayField(TEXT("actual_built_sampler"),Probes);
    TArray<UObject*> Outputs={DerivedBody,DerivedIdle,DerivedWalk,Motion};FAssetCompilingManager::Get().FinishCompilationForObjects(Outputs);
    if(!Guard())return Fail(TEXT("source_package_changed_before_save"));Stage=TEXT("save_owned_only");for(UObject* O:Outputs)if(!Save(O))return Fail(TEXT("owned_derivative_save_failed_partials_preserved"));if(!Guard())return Fail(TEXT("source_package_changed_after_save"));
    auto Descriptor=MakeShared<FJsonObject>();Descriptor->SetStringField(TEXT("format"),TEXT("LivingTown.OriginalWorkerBenPrepared"));Descriptor->SetNumberField(TEXT("version"),1);Descriptor->SetStringField(TEXT("status"),TEXT("CONTROLLED_GAME_TRIAL_PREPARED"));Descriptor->SetStringField(TEXT("source_closure_sha256"),Closure);
    Descriptor->SetObjectField(TEXT("mesh_relative"),TransformJson(FTransform(FQuat::Identity,MeshOffset)));Descriptor->SetObjectField(TEXT("palm_local"),TransformJson(Socket->GetSocketLocalTransform()));Descriptor->SetArrayField(TEXT("idle_offset_cm"),Vec(IdleOffset));Descriptor->SetArrayField(TEXT("walk_offset_cm"),Vec(WalkOffset));Descriptor->SetNumberField(TEXT("capsule_radius_cm"),Radius);Descriptor->SetNumberField(TEXT("capsule_half_height_cm"),Half);
    TArray<TSharedPtr<FJsonValue>> Names,Parents,Local;for(int32 J=0;J<62;++J){Names.Add(MakeShared<FJsonValueString>(Ref.GetBoneName(J).ToString()));Parents.Add(MakeShared<FJsonValueNumber>(Ref.GetParentIndex(J)));Local.Add(MakeShared<FJsonValueObject>(TransformJson(Ref.GetRefBonePose()[J])));}Descriptor->SetArrayField(TEXT("bone_names"),Names);Descriptor->SetArrayField(TEXT("parents"),Parents);Descriptor->SetArrayField(TEXT("reference_local"),Local);
    if(!Write(ReportDirectory,TEXT("PREPARED_BINDING.json"),Descriptor))return Fail(TEXT("prepared_descriptor_write_failed"));FLivingTownOriginalWorkerBinding Verified;FString Error;if(!FLivingTownOriginalWorkerBinding::Read(ReportDirectory/TEXT("PREPARED_BINDING.json"),Verified,Error))return Fail(*Error);
    Report->SetStringField(TEXT("status"),TEXT("PREPARED_CONTROLLED_GAME_TRIAL_ASSETS_ACTUAL_GAME_PENDING"));Report->SetStringField(TEXT("descriptor_sha256"),Verified.DescriptorSha256);Report->SetObjectField(TEXT("actual_REST_palm_component"),TransformJson(PalmComponent));Report->SetObjectField(TEXT("actual_hand_REST_component"),TransformJson(Reference[Hand]));Report->SetObjectField(TEXT("actual_palm_socket_local"),TransformJson(Socket->GetSocketLocalTransform()));Report->SetBoolField(TEXT("source_packages_preserved"),true);Report->SetBoolField(TEXT("explicit_selected_cook_closure_required_for_string_loaded_assets"),true);Report->SetBoolField(TEXT("physical_eating_final_art_cook_or_Game_performance_qualified"),false);Write(ReportDirectory,TEXT("REPORT.json"),Report);return Json(Report);
}
