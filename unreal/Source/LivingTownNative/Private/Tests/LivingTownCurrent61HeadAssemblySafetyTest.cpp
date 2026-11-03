#include "LivingTownCurrent61HeadAssembly.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Async/Async.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "Animation/Skeleton.h"
#include "Materials/Material.h"
#include "UObject/UObjectGlobals.h"
#include "UObject/Package.h"
#include "UObject/StrongObjectPtrTemplates.h"

namespace
{
struct FComponentState
{
    USkeletalMesh* Mesh=nullptr;
    USkinnedMeshComponent* Leader=nullptr;
    bool Visible=false;
    TArray<UMaterialInterface*> Overrides;
    FTransform Relative;
};
FComponentState Capture(const USkeletalMeshComponent* C)
{
    check(IsInGameThread());
    FComponentState S;
    S.Mesh=C->GetSkeletalMeshAsset();S.Leader=C->LeaderPoseComponent.Get();S.Visible=C->IsVisible();
    for(const auto& Material:C->OverrideMaterials)S.Overrides.Add(Material.Get());
    S.Relative=C->GetRelativeTransform();return S;
}
bool Same(const USkeletalMeshComponent* C,const FComponentState& Before)
{
    const auto After=Capture(C);
    return After.Mesh==Before.Mesh&&After.Leader==Before.Leader&&After.Visible==Before.Visible&&
        After.Overrides==Before.Overrides&&After.Relative.GetTranslation()==Before.Relative.GetTranslation()&&
        After.Relative.GetRotation()==Before.Relative.GetRotation()&&After.Relative.GetScale3D()==Before.Relative.GetScale3D();
}
FLivingTownCurrent61HeadBinding SyntaxOnlyBinding()
{
    // Pure validation fixture: never passed to Configure, loaded, saved or
    // emitted as a qualified asset descriptor. These assets do not exist.
    FLivingTownCurrent61HeadBinding B;
    B.bReadQualifiedDescriptor=true;B.QualificationSha256=FString::ChrN(64,TCHAR('a'));
    B.SourceJointNames={FName(TEXT("root")),FName(TEXT("neck_01")),FName(TEXT("head"))};
    for(int32 I=3;I<61;++I)B.SourceJointNames.Add(FName(*FString::Printf(TEXT("SyntaxBone_%d"),I)));
    FLivingTownCurrent61HeadPart Hair;
    Hair.Role=ELivingTownHeadPartRole::HairCards;Hair.ShadingModel=ELivingTownHeadShadingModel::Hair;
    Hair.MeshPath=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/SyntaxOnly/Hair.Hair");
    Hair.MaterialPath=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/SyntaxOnly/MHair.MHair");
    Hair.RenderTriangles=1;Hair.UVChannels=1;
    FLivingTownCurrent61HeadPart Cap;
    Cap.Role=ELivingTownHeadPartRole::Underlayer;Cap.ShadingModel=ELivingTownHeadShadingModel::DefaultLit;
    Cap.MeshPath=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/SyntaxOnly/Cap.Cap");
    Cap.MaterialPath=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/SyntaxOnly/MCap.MCap");
    Cap.RenderTriangles=1;Cap.UVChannels=1;B.Parts={Hair,Cap};return B;
}
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCurrent61HeadSafeRefusal,
    "LivingTown.Current61.HeadAssembly.SafeRefusal",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCurrent61HeadSafeRefusal::RunTest(const FString&)
{
    if(!TestTrue(TEXT("Fixture starts on game thread"),IsInGameThread()))return false;
    // Unregistered, isolated transient components/empty mesh/material sentinels.
    // No content load, asset assembly, render, world, animation or physics proof.
    TStrongObjectPtr<USkeletalMeshComponent> Body(NewObject<USkeletalMeshComponent>(GetTransientPackage()));
    TStrongObjectPtr<USkeletalMeshComponent> Hair(NewObject<USkeletalMeshComponent>(GetTransientPackage()));
    TStrongObjectPtr<USkeletalMeshComponent> Cap(NewObject<USkeletalMeshComponent>(GetTransientPackage()));
    TStrongObjectPtr<USkeletalMesh> Mesh(NewObject<USkeletalMesh>(GetTransientPackage()));
    TStrongObjectPtr<USkeleton> Skeleton(NewObject<USkeleton>(GetTransientPackage()));
    Mesh->SetSkeleton(Skeleton.Get());
    TestTrue(TEXT("Transient fixture mesh retains its Skeleton"),Mesh->GetSkeleton()==Skeleton.Get());
    TStrongObjectPtr<UMaterial> Material(NewObject<UMaterial>(GetTransientPackage()));
    for(auto* C:{Body.Get(),Hair.Get(),Cap.Get()})
    {
        C->SetSkeletalMeshAsset(Mesh.Get());C->SetMaterial(0,Material.Get());C->SetVisibility(true);
        C->SetRelativeTransform(FTransform(FQuat::Identity,FVector(1,2,3),FVector(1,1,1)));
    }
    Hair->SetLeaderPoseComponent(Body.Get(),true,false);Cap->SetLeaderPoseComponent(Body.Get(),true,false);
    const auto BodyBefore=Capture(Body.Get()),HairBefore=Capture(Hair.Get()),CapBefore=Capture(Cap.Get());
    const FLivingTownCurrent61HeadBinding Unqualified;
    struct FArguments{const TCHAR* Name;USkeletalMeshComponent* Body;USkeletalMeshComponent* Hair;USkeletalMeshComponent* Cap;};
    const FArguments Cases[]={
        {TEXT("BodyHairAlias"),Body.Get(),Body.Get(),Cap.Get()},
        {TEXT("BodyCapAlias"),Body.Get(),Hair.Get(),Body.Get()},
        {TEXT("HairCapAlias"),Body.Get(),Hair.Get(),Hair.Get()},
        {TEXT("AllAlias"),Body.Get(),Body.Get(),Body.Get()},
        {TEXT("NullBody"),nullptr,Hair.Get(),Cap.Get()},
        {TEXT("NullHair"),Body.Get(),nullptr,Cap.Get()},
        {TEXT("NullCap"),Body.Get(),Hair.Get(),nullptr},
        {TEXT("AllNull"),nullptr,nullptr,nullptr},
        {TEXT("NullBodyHairUsesBody"),nullptr,Body.Get(),Cap.Get()},
        {TEXT("NullBodyCapUsesBody"),nullptr,Hair.Get(),Body.Get()}};
    for(const auto& Inputs:Cases)
    {
        FString Error;
        TestFalse(Inputs.Name,LivingTownCurrent61HeadAssembly::Configure(Inputs.Body,Inputs.Hair,Inputs.Cap,Unqualified,Error));
        TestEqual(TEXT("Exact preflight refusal"),Error,FString(TEXT("distinct_nonnull_body_and_head_followers_required")));
        TestTrue(TEXT("Body state preserved"),Same(Body.Get(),BodyBefore));
        TestTrue(TEXT("Hair state preserved"),Same(Hair.Get(),HairBefore));
        TestTrue(TEXT("Cap state preserved"),Same(Cap.Get(),CapBefore));
    }
    // All captures/assertions remain on GT. The worker only calls the public
    // entrypoints with retained pointers; refusal must precede any UObject work.
    auto Future=Async(EAsyncExecution::ThreadPool,[B=Body.Get(),H=Hair.Get(),C=Cap.Get()]()
    {
        FString Error;const FLivingTownCurrent61HeadBinding Binding;
        const bool Configured=LivingTownCurrent61HeadAssembly::Configure(B,H,C,Binding,Error);
        LivingTownCurrent61HeadAssembly::Reset(H,C);
        return !Configured&&Error==TEXT("head_assembly_game_thread_required");
    });
    TestTrue(TEXT("Off-thread Configure refuses and Reset returns; future joined on GT"),Future.Get());
    TestTrue(TEXT("Body preserved after worker join"),Same(Body.Get(),BodyBefore));
    TestTrue(TEXT("Hair preserved after worker join"),Same(Hair.Get(),HairBefore));
    TestTrue(TEXT("Cap preserved after worker join"),Same(Cap.Get(),CapBefore));
    FString Error;
    TestFalse(TEXT("Safe distinct invalid-descriptor call refuses"),LivingTownCurrent61HeadAssembly::Configure(Body.Get(),Hair.Get(),Cap.Get(),Unqualified,Error));
    TestTrue(TEXT("Body preserved by safe follower cleanup"),Same(Body.Get(),BodyBefore));
    for(auto* C:{Hair.Get(),Cap.Get()})
    {
        TestFalse(TEXT("Follower hidden"),C->IsVisible());
        TestTrue(TEXT("Follower mesh cleared"),C->GetSkeletalMeshAsset()==nullptr);
        TestTrue(TEXT("Follower leader cleared"),C->LeaderPoseComponent.Get()==nullptr);
        TestEqual(TEXT("Follower overrides cleared"),C->GetNumOverrideMaterials(),0);
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCurrent61HeadProfiles,
    "LivingTown.Current61.HeadAssembly.DeclaredShadingProfiles",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCurrent61HeadProfiles::RunTest(const FString&)
{
    const FLivingTownCurrent61HeadPart DefaultPart;
    TestTrue(TEXT("Producer must explicitly declare profile"),DefaultPart.ShadingModel==ELivingTownHeadShadingModel::Unspecified);
    auto B=SyntaxOnlyBinding();TestTrue(TEXT("Hair shader+DefaultLit cap syntax"),B.IsValidated());
    B.Parts[0].ShadingModel=ELivingTownHeadShadingModel::DefaultLit;
    TestTrue(TEXT("DefaultLit surface cards+DefaultLit cap syntax"),B.IsValidated());
    for(const auto Model:{ELivingTownHeadShadingModel::Unspecified,static_cast<ELivingTownHeadShadingModel>(255)})
    {
        B=SyntaxOnlyBinding();B.Parts[0].ShadingModel=Model;TestFalse(TEXT("Unspecified/unknown hair profile refused"),B.IsValidated());
    }
    for(const auto Model:{ELivingTownHeadShadingModel::Unspecified,ELivingTownHeadShadingModel::Hair,static_cast<ELivingTownHeadShadingModel>(255)})
    {
        B=SyntaxOnlyBinding();B.Parts[1].ShadingModel=Model;TestFalse(TEXT("Underlayer requires exact DefaultLit"),B.IsValidated());
    }
    B=SyntaxOnlyBinding();B.Parts[1].Role=static_cast<ELivingTownHeadPartRole>(255);TestFalse(TEXT("Unknown role refused"),B.IsValidated());
    return true;
}
#endif
