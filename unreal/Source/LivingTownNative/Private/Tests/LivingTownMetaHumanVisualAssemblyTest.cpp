#include "LivingTownMetaHumanVisualAssembly.h"
#include "LivingTownCafeBinding.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Async/Async.h"
#include "Animation/Skeleton.h"
#include "Components/SkeletalMeshComponent.h"
#include "Dom/JsonObject.h"
#include "Engine/SkeletalMesh.h"
#include "GameFramework/Actor.h"
#include "HAL/FileManager.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Misc/ScopeExit.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "Serialization/JsonSerializer.h"
#include "UObject/StrongObjectPtrTemplates.h"
#include "UObject/Package.h"

namespace
{
// Syntax fixtures never load/qualify content. The separate persona lifecycle
// consumer requires the real saved Blueprint and a normally ticking game world.
FLivingTownMetaHumanVisualBinding SyntaxOnlyMetaHuman(TCHAR Identity)
{
    FLivingTownMetaHumanVisualBinding D;D.bReadPreparedDescriptor=true;
    D.DescriptorSha256=FString::ChrN(64,Identity);D.SourceClosureSha256=FString::ChrN(64,TCHAR('c'));
    D.CoreManifestSha256=LivingTownMetaHumanVisual::CoreManifestSha256;
    D.ActorClassPath=LivingTownMetaHumanVisual::ActorClass;D.IdleAnimationPath=LivingTownMetaHumanVisual::Idle;D.WalkAnimationPath=LivingTownMetaHumanVisual::Walk;
    D.HandBone=FName(TEXT("hand_r"));D.ActorRelative=FTransform(FRotator(0,-90,0),FVector(0,0,-90),FVector::OneVector);
    D.CapsuleRadiusCm=20;D.CapsuleHalfHeightCm=90;D.WalkSpeedCmPerSecond=110;D.CameraArmCm=300;D.PreloadDeadlineSeconds=120;return D;
}
FString SyntaxOnlyMetaHumanJson(int32 Version=1)
{
    const auto D=SyntaxOnlyMetaHuman('a');auto O=MakeShared<FJsonObject>();
    O->SetStringField(TEXT("format"),TEXT("LivingTown.MetaHumanBenActorPrepared"));O->SetNumberField(TEXT("version"),Version);
    if(Version==2)
    {
        O->SetStringField(TEXT("outfit_mesh"),LivingTownMetaHumanVisual::WorkwearMesh);
        O->SetStringField(TEXT("outfit_manifest_sha256"),LivingTownMetaHumanVisual::WorkwearManifestSha256);
    }
    O->SetStringField(TEXT("status"),TEXT("CONTROLLED_GAME_TRIAL_PREPARED"));O->SetStringField(TEXT("source_closure_sha256"),D.SourceClosureSha256);
    O->SetStringField(TEXT("core_manifest_sha256"),D.CoreManifestSha256);O->SetStringField(TEXT("actor_class"),D.ActorClassPath);
    O->SetStringField(TEXT("idle_animation"),D.IdleAnimationPath);O->SetStringField(TEXT("walk_animation"),D.WalkAnimationPath);
    auto T=MakeShared<FJsonObject>();
    const auto Array=[](std::initializer_list<double> Values){TArray<TSharedPtr<FJsonValue>> Result;for(double V:Values)Result.Add(MakeShared<FJsonValueNumber>(V));return Result;};
    T->SetArrayField(TEXT("translation_cm"),Array({0,0,-90}));T->SetArrayField(TEXT("rotation_xyzw"),Array({0,0,0,1}));T->SetArrayField(TEXT("scale"),Array({1,1,1}));
    O->SetObjectField(TEXT("relative_transform"),T);O->SetNumberField(TEXT("capsule_radius_cm"),D.CapsuleRadiusCm);O->SetNumberField(TEXT("capsule_half_height_cm"),D.CapsuleHalfHeightCm);
    O->SetNumberField(TEXT("walk_speed_cm_s"),D.WalkSpeedCmPerSecond);O->SetNumberField(TEXT("camera_arm_cm"),D.CameraArmCm);
    O->SetStringField(TEXT("hand_bone"),TEXT("hand_r"));O->SetNumberField(TEXT("preload_deadline_seconds"),D.PreloadDeadlineSeconds);
    FString Json;FJsonSerializer::Serialize(O,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Json));return Json;
}
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownMetaHumanDescriptorTest,"LivingTown.MetaHuman.PreparedDescriptorStrictness",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownMetaHumanDescriptorTest::RunTest(const FString&)
{
    const FString Path=FPaths::CreateTempFilename(*FPaths::ProjectSavedDir(),TEXT("MetaHumanDescriptor_"),TEXT(".json"));
    ON_SCOPE_EXIT{IFileManager::Get().Delete(*Path,false,true);};
    FString Error;FLivingTownMetaHumanVisualBinding Out;
    const FString Json=SyntaxOnlyMetaHumanJson();
    if(!TestTrue(TEXT("Write finite syntax fixture"),FFileHelper::SaveStringToFile(Json,*Path,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM)))return false;
    if(!TestTrue(TEXT("Complete strict descriptor parses"),FLivingTownMetaHumanVisualBinding::Read(Path,Out,Error)))return false;
    TArray<uint8> Bytes;FString Sha;TestTrue(TEXT("Identity is the exact prepared file bytes"),FFileHelper::LoadFileToArray(Bytes,*Path)&&LivingTownCafeJournal::Sha256(Bytes,Sha)&&Sha==Out.DescriptorSha256);
    const auto Sentinel=Out;
    const auto Refuses=[&](const TCHAR* Label,const FString& Bad)
    {
        Out=Sentinel;
        const bool Written=FFileHelper::SaveStringToFile(Bad,*Path,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
        TestTrue(Label,Written&&!FLivingTownMetaHumanVisualBinding::Read(Path,Out,Error));
        TestTrue(TEXT("Refusal never publishes a partial descriptor"),Out.DescriptorSha256==Sentinel.DescriptorSha256&&Out.ActorClassPath==Sentinel.ActorClassPath&&Out.ActorRelative.Equals(Sentinel.ActorRelative));
    };
    Refuses(TEXT("Duplicate keys refused before map overwrite"),TEXT("{\"version\":1,")+Json.Mid(1));
    Refuses(TEXT("Unknown root fields refused"),TEXT("{\"unexpected\":true,")+Json.Mid(1));
    Refuses(TEXT("Fractional descriptor versions refused"),Json.Replace(TEXT("\"version\":1"),TEXT("\"version\":1.5")));
    Refuses(TEXT("Unknown descriptor versions refused"),Json.Replace(TEXT("\"version\":1"),TEXT("\"version\":3")));
    Refuses(TEXT("Version2 requires its two outfit fields"),Json.Replace(TEXT("\"version\":1"),TEXT("\"version\":2")));
    Refuses(TEXT("Arbitrary classes and native Pawn/Controller paths cannot opt in"),Json.Replace(LivingTownMetaHumanVisual::ActorClass,TEXT("/Script/Engine.Pawn")));
    Refuses(TEXT("Alternate locomotion asset cannot smuggle a new clip"),Json.Replace(LivingTownMetaHumanVisual::Walk,LivingTownMetaHumanVisual::Idle));
    Refuses(TEXT("Unqualified source core refused"),Json.Replace(LivingTownMetaHumanVisual::CoreManifestSha256,*FString::ChrN(64,TCHAR('d'))));
    Refuses(TEXT("Zero closure identity refused"),Json.Replace(*FString::ChrN(64,TCHAR('c')),*FString::ChrN(64,TCHAR('0'))));
    Refuses(TEXT("Unbounded preload cannot hang startup"),Json.Replace(TEXT("\"preload_deadline_seconds\":120"),TEXT("\"preload_deadline_seconds\":121")));
    Refuses(TEXT("Transform nested unknown fields refused"),Json.Replace(TEXT("\"relative_transform\":{"),TEXT("\"relative_transform\":{\"unexpected\":0,")));
    Refuses(TEXT("Oversize descriptor refused"),Json+FString::ChrN(16*1024,TCHAR(' ')));
    const FString WorkwearJson=SyntaxOnlyMetaHumanJson(2);
    if(!TestTrue(TEXT("Write qualified workwear syntax fixture"),FFileHelper::SaveStringToFile(WorkwearJson,*Path,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM)))return false;
    if(!TestTrue(TEXT("Version2 parses the admitted outfit and manifest"),FLivingTownMetaHumanVisualBinding::Read(Path,Out,Error)))return false;
    TestTrue(TEXT("Version2 selects the outfit without replacing the original actor"),Out.UsesWorkwear()&&Out.ActorClassPath==Sentinel.ActorClassPath&&FString(Out.ExpectedOutfitMesh())==LivingTownMetaHumanVisual::WorkwearMesh&&Out.DescriptorSha256!=Sentinel.DescriptorSha256);
    Refuses(TEXT("Workwear cannot select an arbitrary outfit"),WorkwearJson.Replace(LivingTownMetaHumanVisual::WorkwearMesh,LivingTownMetaHumanVisual::OutfitMesh));
    Refuses(TEXT("Wrong workwear manifest refused"),WorkwearJson.Replace(LivingTownMetaHumanVisual::WorkwearManifestSha256,*FString::ChrN(64,TCHAR('e'))));
    Refuses(TEXT("Version1 cannot contain version2 outfit fields"),WorkwearJson.Replace(TEXT("\"version\":2"),TEXT("\"version\":1")));
    auto D=SyntaxOnlyMetaHuman('a');D.ActorRelative.SetScale3D(FVector(2));TestFalse(TEXT("Unit scale is mandatory"),D.IsValidated());
    D=SyntaxOnlyMetaHuman('a');D.ActorRelative.SetRotation(FRotator(10,0,0).Quaternion());TestFalse(TEXT("Capsule orientation cannot be tilted"),D.IsValidated());
    D=SyntaxOnlyMetaHuman('a');D.HandBone=FName(TEXT("pelvis"));TestFalse(TEXT("Hand role cannot be reassigned"),D.IsValidated());
    D=SyntaxOnlyMetaHuman('a');D.CapsuleHalfHeightCm=1;TestFalse(TEXT("Measured human capsule bounds required"),D.IsValidated());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownMetaHumanIdentityTest,"LivingTown.MetaHuman.PreparedVisualSaveIdentity",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownMetaHumanIdentityTest::RunTest(const FString&)
{
    FLivingTownCafeBinding Base;Base.ResidentId=TEXT("ben");Base.PhysicalSceneSha256=FString::ChrN(64,TCHAR('d'));Base.PhysicalQualificationSha256=FString::ChrN(64,TCHAR('e'));Base.BindingFileSha256=FString::ChrN(64,TCHAR('f'));Base.VisualSha256=FString::ChrN(64,TCHAR('1'));
    auto A=Base,B=Base;FString Error;const auto First=SyntaxOnlyMetaHuman('a'),Second=SyntaxOnlyMetaHuman('b');
    TestTrue(TEXT("Explicit Ben whole-actor syntax binding"),LivingTownMetaHumanVisual::ApplyPreparedBinding(A,First,Error));
    TestTrue(TEXT("Distinct measured descriptor syntax binding"),LivingTownMetaHumanVisual::ApplyPreparedBinding(B,Second,Error));
    TestTrue(TEXT("Internal whole actor role does not alias a V1-V3 mesh"),A.MotionStrategy==ELivingTownCafeMotionStrategy::MetaHumanWholeActor&&A.MetaHumanActor.IsSet()&&A.IdleWalkBlendSpacePath.IsEmpty()&&A.VisualAssetPath==LivingTownMetaHumanVisual::ActorClass);
    TestEqual(TEXT("Original physical binding identity retained"),A.BindingFileSha256,Base.BindingFileSha256);TestEqual(TEXT("Visual identity is descriptor-bound"),A.VisualSha256,First.DescriptorSha256);
    FString Save,Inner;TestTrue(TEXT("Existing source-bound envelope encodes"),LivingTownCafeJournal::Encode(A,TEXT("opaque-unchanged-authority-journal"),Save,Error));
    TestTrue(TEXT("Exact prepared visual decodes"),LivingTownCafeJournal::Decode(Save,A,Inner,Error));TestFalse(TEXT("Different prepared visual refuses same save"),LivingTownCafeJournal::Decode(Save,B,Inner,Error));
    auto Unchanged=Base;FLivingTownMetaHumanVisualBinding Missing;
    TestFalse(TEXT("Incomplete descriptor cannot publish opt-in"),LivingTownMetaHumanVisual::ApplyPreparedBinding(Unchanged,Missing,Error));TestTrue(TEXT("Refusal retains original family and identity"),!Unchanged.MetaHumanActor.IsSet()&&Unchanged.VisualSha256==Base.VisualSha256&&Unchanged.VisualAssetPath==Base.VisualAssetPath);
    auto Aria=Base;Aria.ResidentId=TEXT("aria");TestFalse(TEXT("Aria is never replaced by Ben actor"),LivingTownMetaHumanVisual::ApplyPreparedBinding(Aria,First,Error));
    auto Mixed=Base;Mixed.OriginalWorker=FLivingTownOriginalWorkerBinding();TestFalse(TEXT("Original worker opt-in is mutually exclusive"),LivingTownMetaHumanVisual::ApplyPreparedBinding(Mixed,First,Error));TestFalse(TEXT("No partial MetaHuman option on mixed refusal"),Mixed.MetaHumanActor.IsSet());
    Mixed=Base;Mixed.Current61Head=FLivingTownCurrent61HeadBinding();TestFalse(TEXT("Head transplant opt-in is mutually exclusive"),LivingTownMetaHumanVisual::ApplyPreparedBinding(Mixed,First,Error));
    TestFalse(TEXT("Already opted-in binding cannot be overwritten"),LivingTownMetaHumanVisual::ApplyPreparedBinding(A,Second,Error));TestEqual(TEXT("Rejected replacement preserves save identity"),A.VisualSha256,First.DescriptorSha256);return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownMetaHumanRefusalTest,"LivingTown.MetaHuman.SafeRefusal",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownMetaHumanRefusalTest::RunTest(const FString&)
{
    const auto D=SyntaxOnlyMetaHuman('a');FString Error;int32 Completed=0;
    TStrongObjectPtr<ULivingTownMetaHumanVisualPreload> Preload(NewObject<ULivingTownMetaHumanVisualPreload>(GetTransientPackage()));
    const auto State=Preload->Request(D,FSimpleDelegate::CreateLambda([&Completed](){++Completed;}),Error);
    TestTrue(TEXT("Unowned non-game preload refuses before loading"),State==ELivingTownMetaHumanPreloadState::Failed&&!Preload->IsReadyFor(D)&&Completed==0);
    TestNull(TEXT("Refused preload holds no generated class"),Preload->GetPreparedActorClass());TestNull(TEXT("Refused preload holds no idle clip"),Preload->GetIdle());TestNull(TEXT("Refused preload holds no walk clip"),Preload->GetWalk());
    TStrongObjectPtr<AActor> Owner(NewObject<AActor>(GetTransientPackage(),TEXT("MetaHumanRefusalOwner")));
    TStrongObjectPtr<USkeletalMeshComponent> Foreign(NewObject<USkeletalMeshComponent>(Owner.Get()));
    TStrongObjectPtr<USkeletalMesh> Sentinel(NewObject<USkeletalMesh>(GetTransientPackage()));
    TStrongObjectPtr<USkeleton> Skeleton(NewObject<USkeleton>(GetTransientPackage()));Sentinel->SetSkeleton(Skeleton.Get());
    const FTransform Before(FRotator(0,30,0),FVector(1,2,3));Foreign->SetSkeletalMeshAsset(Sentinel.Get());Foreign->SetRelativeTransform(Before);Foreign->SetCollisionEnabled(ECollisionEnabled::QueryOnly);Foreign->SetVisibility(true);
    TStrongObjectPtr<ULivingTownMetaHumanVisualAssembly> Assembly(NewObject<ULivingTownMetaHumanVisualAssembly>(Owner.Get()));
    TestFalse(TEXT("Wrong owner/readiness cannot spawn or transplant anything"),Assembly->Configure(D,Preload.Get(),Error));
    Assembly->SetPossessedPlayer(true);Assembly->ResetAfterTeleport();Assembly->Reset();Assembly->Reset();Preload->Reset();Preload->Reset();
    TestTrue(TEXT("Refusal and idempotent cleanup preserve another owner's visual"),Foreign->GetSkeletalMeshAsset()==Sentinel.Get()&&Foreign->GetRelativeTransform().Equals(Before)&&Foreign->GetCollisionEnabled()==ECollisionEnabled::QueryOnly&&Foreign->IsVisible());
    TestFalse(TEXT("Refusal never becomes a qualified visual"),Assembly->IsConfigured());TestNull(TEXT("No complete actor created"),Assembly->GetVisualActor());TestNull(TEXT("No foreign body adopted"),Assembly->GetBody());TestFalse(TEXT("Empty/reset holder cannot drive motion"),Assembly->UpdateMotion(110));
    auto Future=Async(EAsyncExecution::ThreadPool,[P=Preload.Get(),A=Assembly.Get(),D]()
    {
        FString Why;int32 Calls=0;const auto S=P->Request(D,FSimpleDelegate::CreateLambda([&Calls](){++Calls;}),Why);
        const bool Refused=S==ELivingTownMetaHumanPreloadState::Failed&&Calls==0&&!A->Configure(D,P,Why)&&Why==TEXT("metahuman_visual_game_thread_required");P->Reset();A->Reset();return Refused;
    });
    TestTrue(TEXT("Off-thread preload/configure/reset refuses before UObject mutation; future joined"),Future.Get());
    TestTrue(TEXT("No asynchronous readiness or actor survives refused work"),Completed==0&&!Preload->IsReadyFor(D)&&!Assembly->GetVisualActor()&&Foreign->GetSkeletalMeshAsset()==Sentinel.Get());return true;
}
#endif
