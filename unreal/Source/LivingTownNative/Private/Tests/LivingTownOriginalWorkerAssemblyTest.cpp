#include "LivingTownOriginalWorkerAssembly.h"
#include "LivingTownCafeBinding.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownCafeWorldV3Subsystem.h"
#include "LivingTownCafeWorldV3Scenario.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Tests/AutomationCommon.h"
#include "HAL/PlatformTime.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "Animation/Skeleton.h"
#include "GameFramework/Actor.h"
#include "Materials/Material.h"
#include "ChaosClothAsset/ClothComponent.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "Misc/ScopeExit.h"
#include "UObject/StrongObjectPtrTemplates.h"
#include "Async/Async.h"

namespace
{
FLivingTownOriginalWorkerBinding SyntaxOnlyDescriptor(TCHAR Identity)
{
    // Parser/binding fixture only: no content paths are loaded, no physical
    // character, contact or asset acceptance is manufactured by this test.
    FLivingTownOriginalWorkerBinding B;B.bReadPreparedDescriptor=true;B.DescriptorSha256=FString::ChrN(64,Identity);B.SourceClosureSha256=FString::ChrN(64,TCHAR('c'));
    B.CapsuleRadiusCm=20.;B.CapsuleHalfHeightCm=90.;B.PalmLocal.SetScale3D(FVector(.0056));
    B.BoneNames={FName(LivingTownOriginalWorker::Wrapper),FName(TEXT("root")),FName(TEXT("pelvis")),FName(TEXT("hand_r")),FName(TEXT("foot_l")),FName(TEXT("foot_r"))};
    for(int32 I=6;I<62;++I)B.BoneNames.Add(FName(*FString::Printf(TEXT("SyntaxOnly_%d"),I)));
    for(int32 I=0;I<62;++I){B.Parents.Add(I-1);B.ReferenceLocal.Add(FTransform::Identity);}return B;
}
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownOriginalWorkerRefusal,"LivingTown.OriginalWorker.SafeRefusal",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownOriginalWorkerRefusal::RunTest(const FString&)
{
    TStrongObjectPtr<USkeletalMeshComponent> Body(NewObject<USkeletalMeshComponent>(GetTransientPackage()));
    TStrongObjectPtr<USkeletalMesh> Sentinel(NewObject<USkeletalMesh>(GetTransientPackage()));
    TStrongObjectPtr<USkeleton> Skeleton(NewObject<USkeleton>(GetTransientPackage()));
    Sentinel->SetSkeleton(Skeleton.Get());
    TestTrue(TEXT("Transient fixture retains its Skeleton"),Sentinel->GetSkeleton()==Skeleton.Get());
    TStrongObjectPtr<ULivingTownOriginalWorkerAssembly> Assembly(NewObject<ULivingTownOriginalWorkerAssembly>(GetTransientPackage()));
    Body->SetSkeletalMeshAsset(Sentinel.Get());Body->SetVisibility(true);const FTransform Before(FQuat::Identity,FVector(1,2,3));Body->SetRelativeTransform(Before);
    FString Error;FLivingTownOriginalWorkerBinding Missing;
    TestFalse(TEXT("Missing descriptor/owner cannot replace a body"),Assembly->Configure(Body.Get(),Missing,Error));
    TestTrue(TEXT("Existing body remains unchanged"),Body->GetSkeletalMeshAsset()==Sentinel.Get()&&Body->IsVisible()&&Body->GetRelativeTransform().Equals(Before));
    auto Future=Async(EAsyncExecution::ThreadPool,[A=Assembly.Get(),B=Body.Get()](){FString Why;const FLivingTownOriginalWorkerBinding MissingDescriptor;const bool R=A->Configure(B,MissingDescriptor,Why);A->Reset();return !R&&Why==TEXT("original_worker_game_thread_required");});
    TestTrue(TEXT("Off-thread refusal precedes UObject mutation; future joined"),Future.Get());
    TestTrue(TEXT("Body survives refused off-thread Configure/Reset"),Body->GetSkeletalMeshAsset()==Sentinel.Get()&&Body->IsVisible()&&Body->GetRelativeTransform().Equals(Before));
    TestFalse(TEXT("No follower or player created on refusal"),Assembly->IsConfigured());TestNull(TEXT("No support"),Assembly->GetUnderlay());TestNull(TEXT("No apron"),Assembly->GetApron());
    // A correctly owned, empty body with an existing material override must
    // refuse before any asset load; Reset must not remove another owner's state.
    TStrongObjectPtr<AActor> Owner(NewObject<AActor>(GetTransientPackage(),TEXT("OriginalWorkerRefusalOwner")));
    TStrongObjectPtr<ULivingTownOriginalWorkerAssembly> OwnedAssembly(NewObject<ULivingTownOriginalWorkerAssembly>(Owner.Get()));
    TStrongObjectPtr<USkeletalMeshComponent> EmptyBody(NewObject<USkeletalMeshComponent>(Owner.Get()));
    TStrongObjectPtr<UMaterial> Override(NewObject<UMaterial>(GetTransientPackage()));
    EmptyBody->SetMaterial(0,Override.Get());EmptyBody->SetCollisionEnabled(ECollisionEnabled::QueryOnly);EmptyBody->SetVisibility(true);EmptyBody->SetRelativeTransform(Before);
    const auto Prepared=SyntaxOnlyDescriptor('a');
    TestFalse(TEXT("Preexisting material override refuses before saved asset loads"),OwnedAssembly->Configure(EmptyBody.Get(),Prepared,Error));OwnedAssembly->Reset();OwnedAssembly->ResetAfterTeleport();OwnedAssembly->Reset();
    TestTrue(TEXT("Refusal and repeated reset preserve foreign override/collision/transform"),EmptyBody->GetMaterial(0)==Override.Get()&&EmptyBody->GetCollisionEnabled()==ECollisionEnabled::QueryOnly&&EmptyBody->IsVisible()&&EmptyBody->GetRelativeTransform().Equals(Before));
    EmptyBody->EmptyOverrideMaterials();EmptyBody->bEnableAnimation=false;
    TestFalse(TEXT("Disabled actual animation refuses before any start"),OwnedAssembly->Configure(EmptyBody.Get(),Prepared,Error));
    auto D=SyntaxOnlyDescriptor('a');TestTrue(TEXT("Complete syntax fixture"),D.IsValidated());D.BoneNames[0]=FName(TEXT("Legacy61"));TestFalse(TEXT("Old root hierarchy refused"),D.IsValidated());
    D=SyntaxOnlyDescriptor('a');D.Parents[20]=20;TestFalse(TEXT("Cyclic/forward hierarchy refused"),D.IsValidated());D=SyntaxOnlyDescriptor('a');D.IdleOffsetCm.Z=1.;TestFalse(TEXT("Perclip vertical gait change refused"),D.IsValidated());
    return true;
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownOriginalWorkerSaveIdentity,"LivingTown.OriginalWorker.PreparedVisualSaveIdentity",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownOriginalWorkerSaveIdentity::RunTest(const FString&)
{
    FLivingTownCafeBinding Base;Base.ResidentId=TEXT("ben");Base.PhysicalSceneSha256=FString::ChrN(64,TCHAR('d'));Base.PhysicalQualificationSha256=FString::ChrN(64,TCHAR('e'));Base.BindingFileSha256=FString::ChrN(64,TCHAR('f'));Base.VisualSha256=FString::ChrN(64,TCHAR('1'));
    FString Error;auto First=Base,Second=Base;const auto A=SyntaxOnlyDescriptor('a'),B=SyntaxOnlyDescriptor('b');
    TestTrue(TEXT("Explicit prepared binding A"),LivingTownOriginalWorker::ApplyPreparedBinding(First,A,Error));TestTrue(TEXT("Explicit prepared binding B"),LivingTownOriginalWorker::ApplyPreparedBinding(Second,B,Error));
    TestEqual(TEXT("Original scene calibration identity retained"),First.BindingFileSha256,Base.BindingFileSha256);TestEqual(TEXT("Visual save identity is descriptor bound"),First.VisualSha256,A.DescriptorSha256);
    FString Save,Inner;TestTrue(TEXT("Existing source-bound envelope encodes"),LivingTownCafeJournal::Encode(First,TEXT("unchanged-opaque-authority-journal"),Save,Error));
    TestTrue(TEXT("Same prepared visual decodes"),LivingTownCafeJournal::Decode(Save,First,Inner,Error));TestFalse(TEXT("Distinct prepared visual cannot replay same scene save"),LivingTownCafeJournal::Decode(Save,Second,Inner,Error));
    auto Unchanged=Base;const FLivingTownOriginalWorkerBinding Missing;TestFalse(TEXT("Missing prepared descriptor refuses"),LivingTownOriginalWorker::ApplyPreparedBinding(Unchanged,Missing,Error));TestEqual(TEXT("Refusal publishes no partial visual"),Unchanged.VisualSha256,Base.VisualSha256);
    auto Aria=Base;Aria.ResidentId=TEXT("aria");TestFalse(TEXT("Ben opt-in cannot replace another persona"),LivingTownOriginalWorker::ApplyPreparedBinding(Aria,A,Error));return true;
}
namespace
{
UWorld* FindOriginalWorkerLifecycleWorld(int32& Count)
{
    UWorld* World=nullptr;Count=0;
    if(GEngine)for(const auto& Context:GEngine->GetWorldContexts())if(Context.World()&&(Context.WorldType==EWorldType::Game||Context.WorldType==EWorldType::PIE)){World=Context.World();++Count;}
    return World;
}
bool RunOriginalWorkerLifecycleAssertions(FAutomationTestBase& Test,UWorld* World)
{
    if(!Test.TestTrue(TEXT("Actually begun standalone WorldV3 lifecycle world required"),World&&World->HasBegunPlay()&&World->GetNetMode()==NM_Standalone&&World->GetAuthGameMode()&&World->GetAuthGameMode()->GetClass()==ALivingTownCafeWorldV3GameMode::StaticClass()))return false;
    auto* Authority=World->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();auto* PC=World->GetFirstPlayerController();
    if(!Test.TestTrue(TEXT("Actual prepared original-worker binding and player required"),Authority&&PC&&Authority->GetBinding().OriginalWorker.IsSet()))return false;
    const auto B=Authority->GetBinding();TWeakObjectPtr<APawn> PreviousPawn=PC->GetPawn();TWeakObjectPtr<AActor> PreviousView=PC->GetViewTarget();
    auto* Pawn=World->SpawnActor<ALivingTownCafeCharacter>(ALivingTownCafeCharacter::StaticClass(),B.SpawnFeetCm+FVector(0,0,500),B.SpawnRotation);
    if(!Test.TestNotNull(TEXT("Actual owned character"),Pawn))return false;
    ON_SCOPE_EXIT{if(PC->GetPawn()==Pawn)PC->UnPossess();Pawn->Destroy();if(PreviousPawn.IsValid())PC->Possess(PreviousPawn.Get());if(PreviousView.IsValid())PC->SetViewTarget(PreviousView.Get());};
    const auto BeforeTransform=Pawn->GetMesh()->GetRelativeTransform();const auto BeforeCollision=Pawn->GetMesh()->GetCollisionEnabled();FString Error;
    if(!Test.TestTrue(TEXT("Actual saved assembly configures"),Pawn->ConfigureQualifiedBen(B,Error))){Test.AddError(Error);return false;}
    auto* Assembly=Pawn->FindComponentByClass<ULivingTownOriginalWorkerAssembly>();if(!Test.TestNotNull(TEXT("Owned real assembly"),Assembly))return false;
    auto* Mesh=Pawn->GetMesh();Mesh->VisibilityBasedAnimTickOption=EVisibilityBasedAnimTickOption::OnlyTickPoseWhenRendered;Mesh->bEnableUpdateRateOptimizations=true;
    PC->Possess(Pawn);Test.TestTrue(TEXT("Controlled original player refreshes actual bones"),Mesh->VisibilityBasedAnimTickOption==EVisibilityBasedAnimTickOption::AlwaysTickPoseAndRefreshBones&&!Mesh->bEnableUpdateRateOptimizations);
    PC->UnPossess();Test.TestTrue(TEXT("UnPossess restores the exact previous tick/URO policy"),Mesh->VisibilityBasedAnimTickOption==EVisibilityBasedAnimTickOption::OnlyTickPoseWhenRendered&&Mesh->bEnableUpdateRateOptimizations);
    PC->Possess(Pawn);const bool Teleported=Pawn->TeleportTo(Pawn->GetActorLocation()+FVector(0,0,20),Pawn->GetActorRotation(),false,true);
    Test.TestTrue(TEXT("Actual teleport requests supported cloth reset"),Teleported&&Assembly->GetApron()&&Assembly->GetApron()->NeedsReset());PC->UnPossess();Assembly->Reset();Assembly->Reset();
    Test.TestTrue(TEXT("Owned reset restores empty body/collision/transform"),!Mesh->GetSkeletalMeshAsset()&&Mesh->GetCollisionEnabled()==BeforeCollision&&Mesh->GetRelativeTransform().Equals(BeforeTransform));
    Test.TestFalse(TEXT("Released assembly cannot remain a qualified visual"),Pawn->HasQualifiedVisual());Test.TestNull(TEXT("Support released"),Assembly->GetUnderlay());Test.TestNull(TEXT("Apron released"),Assembly->GetApron());
    Test.AddInfo(TEXT("Actual prepared pawn possession/UnPossess/teleport/reset checked; no movement, render, meal or Game-performance acceptance."));return true;
}
class FOriginalWorkerLifecycleAfterPIE final:public IAutomationLatentCommand
{
    FAutomationTestBase* Test;
    double Deadline=FPlatformTime::Seconds()+120.;
public:
    explicit FOriginalWorkerLifecycleAfterPIE(FAutomationTestBase* InTest):Test(InTest){}
    virtual bool Update()override
    {
        if(FPlatformTime::Seconds()>Deadline){Test->AddError(TEXT("Actual prepared WorldV3 lifecycle PIE startup timed out"));return true;}
        int32 Count=0;UWorld* World=FindOriginalWorkerLifecycleWorld(Count);
        if(Count>1){Test->AddError(TEXT("Exactly one actual lifecycle PIE/Game world required"));return true;}
        if(!World||!World->HasBegunPlay()||!World->GetFirstPlayerController()||!World->GetFirstPlayerController()->GetPawn())return false;
        RunOriginalWorkerLifecycleAssertions(*Test,World);return true;
    }
};
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownOriginalWorkerPawnLifecycle,"LivingTown.Development.OriginalWorkerPreparedPawnLifecycle",EAutomationTestFlags::EditorContext|EAutomationTestFlags::ClientContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownOriginalWorkerPawnLifecycle::RunTest(const FString&)
{
    // The console automation wrapper stops any prior PIE before running tests.
    // Own this Editor lifecycle world, as the existing WorldV3 boundary tests do;
    // ordinary gameplay/movement evidence belongs to its separate earlier phase.
#if WITH_EDITOR
    if(GIsEditor)
    {
        if(!AutomationOpenMap(TEXT("/Engine/Maps/Entry"),true))return false;
        ADD_LATENT_AUTOMATION_COMMAND(FOriginalWorkerLifecycleAfterPIE(this));return true;
    }
#endif
    // Client context consumes its actually playing standalone world; it cannot
    // create an Editor PIE world or substitute assets/authority with a fixture.
    int32 Count=0;UWorld* World=FindOriginalWorkerLifecycleWorld(Count);
    if(!TestTrue(TEXT("One actually playing prepared WorldV3 world required"),Count==1&&World&&World->HasBegunPlay()))return false;
    return RunOriginalWorkerLifecycleAssertions(*this,World);
}
#endif
