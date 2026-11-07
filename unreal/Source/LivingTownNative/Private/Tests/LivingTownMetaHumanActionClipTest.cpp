#include "LivingTownMetaHumanVisualAssembly.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownCafeWorldV3Scenario.h"
#include "LivingTownCafeWorldV3Subsystem.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Tests/AutomationCommon.h"
#include "Animation/AnimInstance.h"
#include "Animation/AnimSequence.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Components/CapsuleComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Dom/JsonObject.h"
#include "Engine/Engine.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/World.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/PlayerInput.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformTime.h"
#include "InputCoreTypes.h"
#include "InputKeyEventArgs.h"
#include "Misc/CommandLine.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Serialization/JsonSerializer.h"
#include "UObject/StrongObjectPtrTemplates.h"

namespace
{
constexpr TCHAR ActionPath[]=TEXT("/Game/LivingTown_UEPilot/MetaHumanDailyActions_v001/AS_EatBread.AS_EatBread");
constexpr TCHAR ActionPackage[]=TEXT("/Game/LivingTown_UEPilot/MetaHumanDailyActions_v001/AS_EatBread");
constexpr TCHAR ActionSha[]=TEXT("0f88d5bcad7ac8b0f88de9a36b17c3324daa6c4e6f8eeefb291e90310ec560aa");
UWorld* ActionWorld(int32& Count)
{
    UWorld* Result=nullptr;Count=0;
    if(GEngine)for(const auto& Context:GEngine->GetWorldContexts())
        if(Context.World()&&(Context.WorldType==EWorldType::PIE||Context.WorldType==EWorldType::Game))
        {Result=Context.World();++Count;}
    return Result;
}

// One normally ticking, possessed fixture. Only the isolated takeover probe has
// deliberately assigned foreign playback state; that is never motion evidence.
class FMetaHumanActionClip final:public IAutomationLatentCommand
{
    FAutomationTestBase* Test;
    const double Deadline=FPlatformTime::Seconds()+180.;
    int32 Stage=0,Samples=0;
    uint32 WorldId=0,InitialBoneRevision=0;
    bool bDone=false,bPressed=false;
    TWeakObjectPtr<ALivingTownCafeWorldV3Controller> Controller;
    TWeakObjectPtr<ALivingTownCafeCharacter> Ben,Probe;
    TWeakObjectPtr<ULivingTownMetaHumanVisualAssembly> Assembly;
    TWeakObjectPtr<AActor> Visual;
    TWeakObjectPtr<USkeletalMeshComponent> Body,Face,Outfit;
    TWeakObjectPtr<UAnimSingleNodeInstance> Player;
    TWeakObjectPtr<UAnimInstance> BodyPost,FaceMain,FacePost,OutfitMain,OutfitPost;
    TWeakObjectPtr<USkinnedMeshComponent> FaceLeader,OutfitLeader;
    EAnimationMode::Type FaceMode=EAnimationMode::AnimationBlueprint,OutfitMode=EAnimationMode::AnimationBlueprint;
    bool bFacePostDisabled=false,bOutfitPostDisabled=false;
    TStrongObjectPtr<UAnimSequence> Action;
    FLivingTownCafeWorldView Before;
    double LastWorldTime=0,StationaryElapsed=0,ActionAdvance=0,MoveStarted=0;
    float LastClipTime=0,WalkSpeed=0;
    FVector StartLocation=FVector::ZeroVector;
    double WalkDistance=0;
    bool Need(bool Ok,const TCHAR* Why){if(!Ok){Test->AddError(Why);bDone=true;}return Ok;}
    void Release()
    {
        if(bPressed)if(auto* PC=Controller.Get())PC->InputKey(FInputKeyEventArgs::CreateSimulated(EKeys::W,IE_Released,0.f));
        bPressed=false;
    }
    bool SameOwners()const
    {
        auto* PC=Controller.Get();auto* Pawn=Ben.Get();auto* A=Assembly.Get();auto* B=Body.Get();auto* F=Face.Get();auto* O=Outfit.Get();
        return PC&&Pawn&&A&&B&&F&&O&&Player.IsValid()&&Visual.IsValid()&&PC->GetPawn()==Pawn&&PC->GetViewTarget()==Pawn&&Pawn->GetController()==PC&&
            PC->HasNativePersona()&&PC->GetNativePersona()==ELivingTownCafeWorldPersona::Ben&&Pawn->HasQualifiedVisual()&&Pawn->HasMetaHumanVisual()&&
            A->IsConfigured()&&A->GetVisualActor()==Visual.Get()&&A->GetBody()==B&&A->GetFace()==F&&Pawn->GetVisualBody()==B&&
            Visual->GetOwner()==Pawn&&Visual->GetParentActor()==Pawn&&B->GetOwner()==Visual.Get()&&F->GetOwner()==Visual.Get()&&O->GetOwner()==Visual.Get()&&
            B->GetAnimationMode()==EAnimationMode::AnimationSingleNode&&B->GetSingleNodeInstance()==Player.Get()&&B->GetPostProcessInstance()==BodyPost.Get()&&
            !B->GetDisablePostProcessBlueprint()&&F->GetAnimationMode()==FaceMode&&F->GetAnimInstance()==FaceMain.Get()&&F->GetPostProcessInstance()==FacePost.Get()&&
            F->LeaderPoseComponent.Get()==FaceLeader.Get()&&F->GetDisablePostProcessBlueprint()==bFacePostDisabled&&
            O->GetAnimationMode()==OutfitMode&&O->GetAnimInstance()==OutfitMain.Get()&&O->GetPostProcessInstance()==OutfitPost.Get()&&
            O->LeaderPoseComponent.Get()==OutfitLeader.Get()&&O->LeaderPoseComponent.Get()==B&&O->GetDisablePostProcessBlueprint()==bOutfitPostDisabled;
    }
    bool NoGrant(const ULivingTownCafeWorldV3Subsystem* Authority)const
    {
        const auto& After=Authority->GetPresentation();
        // Natural clock/needs decay is allowed; the technical clip grants none.
        return After.bSessionReady&&After.Persona==TEXT("ben")&&!After.bMealActive&&!After.bMealAvailable&&
            After.Owner==Before.Owner&&After.Operator==Before.Operator&&After.AriaCoins==Before.AriaCoins&&After.BenCoins==Before.BenCoins&&
            After.Stock==Before.Stock&&After.Hunger<=Before.Hunger&&After.Fun<=Before.Fun;
    }
public:
    explicit FMetaHumanActionClip(FAutomationTestBase* In):Test(In){}
    virtual ~FMetaHumanActionClip()
    {
        int32 Count=0;const auto* World=ActionWorld(Count);
        if(Count!=1||!World||World->GetUniqueID()!=WorldId)return;
        Release();if(Probe.IsValid())Probe->Destroy();
        if(Assembly.IsValid()&&Assembly->IsActionClipActive())Assembly->EndActionClip();
    }
    virtual bool Update()override
    {
        if(bDone)return true;
        if(!Need(FPlatformTime::Seconds()<Deadline,TEXT("Actual MetaHuman action ownership test timed out")))return true;
        int32 Count=0;auto* World=ActionWorld(Count);
        if(!Need(Count<=1&&(!WorldId||(World&&World->GetUniqueID()==WorldId)),TEXT("One unchanged actual runtime world required")))return true;
        if(!World||!World->HasBegunPlay())return false;
        if(!WorldId)WorldId=World->GetUniqueID();
        auto* Authority=World->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();
        auto* Mode=World->GetAuthGameMode<ALivingTownCafeWorldV3GameMode>();
        auto* PC=Cast<ALivingTownCafeWorldV3Controller>(World->GetFirstPlayerController());
        if(!Authority||!Authority->IsPrepared()||!Mode||!PC)return false;
        if(!Need(World->GetNetMode()==NM_Standalone&&!World->IsPaused()&&Mode->GetClass()==ALivingTownCafeWorldV3GameMode::StaticClass()&&
            Authority->GetBinding().MetaHumanActor.IsSet()&&Authority->GetBinding().MetaHumanActor->UsesWorkwear(),TEXT("Exact standalone WorldV3 with qualified v2 MetaHuman binding required")))return true;
        FString Error;
        if(Stage==0)
        {
            if(!PC->GetPawn()||!PC->HasNativePersona()||!Authority->GetPresentation().bSessionReady)return false;
            auto* Pawn=Cast<ALivingTownCafeCharacter>(PC->GetPawn());
            if(!Need(Pawn&&PC->GetNativePersona()==ELivingTownCafeWorldPersona::Ben,TEXT("Normally selected actual Ben required")))return true;
            if(!Pawn->GetCharacterMovement()->IsMovingOnGround()||Pawn->GetVelocity().Size2D()>=2.f)return false;
            auto* A=Pawn->FindComponentByClass<ULivingTownMetaHumanVisualAssembly>();auto* V=A?A->GetVisualActor():nullptr;
            auto* B=A?A->GetBody():nullptr;auto* F=A?A->GetFace():nullptr;auto* P=B?B->GetSingleNodeInstance():nullptr;
            auto* Preload=Mode->FindComponentByClass<ULivingTownMetaHumanVisualPreload>();
            if(!Need(A&&A->IsConfigured()&&V&&B&&F&&P&&Preload&&Preload->IsReadyFor(Authority->GetBinding().MetaHumanActor.GetValue())&&
                P->GetClass()==UAnimSingleNodeInstance::StaticClass()&&P->GetCurrentAsset()==Preload->GetIdle()&&PC->PlayerInput&&
                F->GetAnimationMode()==EAnimationMode::AnimationBlueprint&&F->GetAnimInstance()&&F->GetPostProcessInstance()&&!F->GetDisablePostProcessBlueprint(),
                TEXT("Existing qualified Body single-node player and original Face ABP/postprocess must be live")))return true;
            TArray<USkeletalMeshComponent*> Parts;V->GetComponents(Parts);USkeletalMeshComponent* O=nullptr;
            for(auto* Part:Parts)if(Part->GetSkeletalMeshAsset()&&Part->GetSkeletalMeshAsset()->GetPathName()==Authority->GetBinding().MetaHumanActor->ExpectedOutfitMesh())O=Part;
            if(!Need(Parts.Num()==3&&O&&O->LeaderPoseComponent.Get()==B,TEXT("Original three-part actor and admitted Outfit body leader required")))return true;
            const FVector Feet=Pawn->GetActorLocation()-FVector(0,0,Pawn->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());
            if(!Need(Feet.Equals(Authority->GetBinding().SpawnFeetCm,2.f)&&!Authority->GetPresentation().bMealAvailable&&!Authority->GetPresentation().bMealActive,
                TEXT("Fresh grounded source spawn without contact provider or inherited meal required")))return true;
            const FString File=FPackageName::LongPackageNameToFilename(ActionPackage,FPackageName::GetAssetPackageExtension());TArray<uint8> Bytes;FString Digest;
            if(!Need(FFileHelper::LoadFileToArray(Bytes,*File)&&Bytes.Num()==2324237&&LivingTownCafeJournal::Sha256(Bytes,Digest)&&Digest==ActionSha,
                TEXT("Exact positive EatBread001 package bytes required; no substitute clip")))return true;
            Action.Reset(LoadObject<UAnimSequence>(nullptr,ActionPath));
            if(!Need(Action.IsValid()&&Action->GetSkeleton()==B->GetSkeletalMeshAsset()->GetSkeleton()&&Action->GetNumberOfSampledKeys()>1&&
                Action->GetPlayLength()>.5f&&Action->RateScale==1.f&&!Action->IsValidAdditive()&&!Action->bEnableRootMotion,
                TEXT("Actual shared-rig nonadditive, rate-one, in-place eating candidate required")))return true;
            Controller=PC;Ben=Pawn;Assembly=A;Visual=V;Body=B;Face=F;Outfit=O;Player=P;
            BodyPost=B->GetPostProcessInstance();FaceMain=F->GetAnimInstance();FacePost=F->GetPostProcessInstance();FaceLeader=F->LeaderPoseComponent;FaceMode=F->GetAnimationMode();bFacePostDisabled=F->GetDisablePostProcessBlueprint();
            OutfitMain=O->GetAnimInstance();OutfitPost=O->GetPostProcessInstance();OutfitLeader=O->LeaderPoseComponent;OutfitMode=O->GetAnimationMode();bOutfitPostDisabled=O->GetDisablePostProcessBlueprint();
            Before=Authority->GetPresentation();StartLocation=Pawn->GetActorLocation();
            if(!Need(A->BeginActionClip(Action.Get(),false,Error)&&A->IsActionClipActive()&&P->GetCurrentAsset()==Action.Get()&&SameOwners(),
                TEXT("BeginActionClip retains exact Body player, Face ABP/postprocess and Outfit leader"))){Test->AddInfo(Error);return true;}
            LastWorldTime=World->GetTimeSeconds();LastClipTime=P->GetCurrentTime();InitialBoneRevision=B->GetBoneTransformRevisionNumber();Stage=1;return false;
        }
        if(!Need(PC==Controller.Get()&&SameOwners()&&NoGrant(Authority),TEXT("Action lifecycle retains original player/pose owners and grants no authority or needs")))return true;
        auto* A=Assembly.Get();auto* P=Player.Get();auto* Pawn=Ben.Get();auto* B=Body.Get();
        auto* Preload=Mode->FindComponentByClass<ULivingTownMetaHumanVisualPreload>();
        if(!Need(Preload&&Preload->IsReadyFor(Authority->GetBinding().MetaHumanActor.GetValue()),TEXT("Original qualified preload remains live")))return true;
        if(Stage==1)
        {
            if(!Need(A->IsActionClipActive()&&P->GetCurrentAsset()==Action.Get()&&P->IsPlaying()&&!P->IsLooping()&&Pawn->GetVelocity().Size2D()<2.f&&
                FVector::Dist2D(Pawn->GetActorLocation(),StartLocation)<1.f,TEXT("Stationary natural ticks retain the owned action asset without locomotion replacement")))return true;
            const double Now=World->GetTimeSeconds(),Delta=Now-LastWorldTime;const float Time=P->GetCurrentTime();
            if(Delta<=0)return false;
            if(!Need(FMath::IsFinite(Time)&&Time>=LastClipTime&&Delta<Action->GetPlayLength(),TEXT("Natural nonlooping action time remains observable")))return true;
            StationaryElapsed+=Delta;ActionAdvance+=Time-LastClipTime;LastWorldTime=Now;LastClipTime=Time;++Samples;
            if(StationaryElapsed<.35||Samples<3)return false;
            if(!Need(ActionAdvance>.1&&FMath::Abs(ActionAdvance-StationaryElapsed)<.1&&B->GetBoneTransformRevisionNumber()!=InitialBoneRevision,
                TEXT("Action time and real bone revisions advance across unchanged stationary ticks")))return true;
            PC->InputKey(FInputKeyEventArgs::CreateSimulated(EKeys::W,IE_Pressed,1.f));bPressed=true;MoveStarted=World->GetTimeSeconds();Stage=2;return false;
        }
        if(Stage==2)
        {
            WalkSpeed=float(Pawn->GetVelocity().Size2D());WalkDistance=FVector::Dist2D(Pawn->GetActorLocation(),StartLocation);
            if(!Need(World->GetTimeSeconds()-MoveStarted<3.,TEXT("Actual W input must produce a bounded walk transition")))return true;
            if(A->IsActionClipActive()||WalkSpeed<4.f||WalkDistance<=.1)return false;
            if(!Need(P->GetCurrentAsset()==Preload->GetWalk()&&P->IsPlaying()&&P->IsLooping()&&P->GetPlayRate()==1.f&&SameOwners(),
                TEXT("Real walking interrupts the action and restores locomotion on the exact existing player")))return true;
            Release();Stage=3;return false;
        }
        if(Stage==3)
        {
            if(Pawn->GetVelocity().Size2D()>=2.f||P->GetCurrentAsset()!=Preload->GetIdle())return false;
            if(!Need(!A->IsActionClipActive()&&SameOwners(),TEXT("Natural stop returns to original idle without replacing player or pose owners")))return true;
            const float PreviousTime=P->GetCurrentTime();
            if(!Need(A->BeginActionClip(Action.Get(),false,Error)&&A->EndActionClip()&&SameOwners()&&P->GetCurrentAsset()==Preload->GetIdle()&&
                P->GetCurrentTime()==PreviousTime&&P->IsPlaying()&&P->IsLooping()&&P->GetPlayRate()==1.f,
                TEXT("Explicit owned end restores the exact prior idle state on the same player")))return true;
            const auto& Binding=Authority->GetBinding();FActorSpawnParameters Params;Params.SpawnCollisionHandlingOverride=ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Q=World->SpawnActor<ALivingTownCafeCharacter>(ALivingTownCafeCharacter::StaticClass(),Binding.SpawnFeetCm+FVector(1000,0,500),Binding.SpawnRotation,Params);Probe=Q;
            if(!Need(Q&&Q->ConfigureQualifiedBen(Binding,Error),TEXT("Independent normally begun takeover probe uses the same admitted preload")))return true;
            auto* QA=Q->FindComponentByClass<ULivingTownMetaHumanVisualAssembly>();auto* QB=QA?QA->GetBody():nullptr;auto* QP=QB?QB->GetSingleNodeInstance():nullptr;
            if(!Need(QA&&QB&&QP&&QA->BeginActionClip(Action.Get(),false,Error),TEXT("Isolated actual Body player begins the same candidate before takeover")))return true;
            // Deliberate foreign ownership, all in one update before a pawn tick.
            // EndActionClip must not restore its remembered idle over this caller.
            QP->SetAnimationAsset(Preload->GetWalk(),true,.5f);QP->SetPosition(.125f,false);QP->SetPlaying(false);
            if(!Need(!QA->EndActionClip()&&!QA->IsActionClipActive()&&QB->GetSingleNodeInstance()==QP&&QP->GetCurrentAsset()==Preload->GetWalk()&&
                QP->GetCurrentTime()==.125f&&QP->GetPlayRate()==.5f&&QP->IsLooping()&&!QP->IsPlaying(),
                TEXT("EndActionClip refuses foreign same-player asset takeover and never overwrites its asset/time/rate/flags")))return true;
            Q->Destroy();Probe.Reset();
            if(!Need(SameOwners()&&NoGrant(Authority),TEXT("Probe cleanup leaves actual possessed character and gameplay authority intact")))return true;
            auto Evidence=MakeShared<FJsonObject>();Evidence->SetStringField(TEXT("status"),TEXT("PASS_ACTUAL_METAHUMAN_ACTION_CLIP_OWNERSHIP_ONLY"));
            Evidence->SetStringField(TEXT("clip"),ActionPath);Evidence->SetStringField(TEXT("clip_file_sha256"),ActionSha);Evidence->SetStringField(TEXT("descriptor_sha256"),Binding.MetaHumanActor->DescriptorSha256);
            Evidence->SetStringField(TEXT("pawn"),Pawn->GetPathName());Evidence->SetStringField(TEXT("visual_actor"),Visual->GetPathName());Evidence->SetStringField(TEXT("body_player"),P->GetPathName());
            Evidence->SetStringField(TEXT("face_main_class"),FaceMain->GetClass()->GetPathName());Evidence->SetStringField(TEXT("face_postprocess_class"),FacePost->GetClass()->GetPathName());Evidence->SetStringField(TEXT("outfit_leader"),OutfitLeader->GetPathName());
            Evidence->SetNumberField(TEXT("stationary_world_seconds"),StationaryElapsed);Evidence->SetNumberField(TEXT("stationary_action_advance_seconds"),ActionAdvance);Evidence->SetNumberField(TEXT("natural_stationary_samples"),Samples);
            Evidence->SetNumberField(TEXT("actual_walk_speed_cm_s"),WalkSpeed);Evidence->SetNumberField(TEXT("actual_walk_displacement_cm"),WalkDistance);
            Evidence->SetBoolField(TEXT("same_player_face_and_outfit_owners"),true);Evidence->SetBoolField(TEXT("real_Controller_InputKey_W_natural_frames"),true);Evidence->SetBoolField(TEXT("foreign_same_player_asset_takeover_refused_unchanged"),true);
            Evidence->SetBoolField(TEXT("authority_or_needs_granted"),false);Evidence->SetBoolField(TEXT("meal_commands_or_save_load_called"),false);Evidence->SetBoolField(TEXT("contact_face_food_art_or_FPS_qualified"),false);
            FString Json;FJsonSerializer::Serialize(Evidence,TJsonWriterFactory<>::Create(&Json));const FString Path=FPaths::ProjectSavedDir()/TEXT("MetaHuman/ActionClipOwnership.json");
            if(!Need(!IFileManager::Get().FileExists(*Path)&&IFileManager::Get().MakeDirectory(*FPaths::GetPath(Path),true)&&
                FFileHelper::SaveStringToFile(Json,*Path,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM),TEXT("Retain fresh actual native action ownership evidence")))return true;
            bDone=true;return true;
        }
        return false;
    }
};
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownMetaHumanActionClipTest,"LivingTown.MetaHuman.ActionClipOwnership",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownMetaHumanActionClipTest::RunTest(const FString&)
{
    FString Descriptor,Persona;
    if(!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeWorldV3"))||!FParse::Param(FCommandLine::Get(),TEXT("LivingTownMetaHumanActionClipTest"))||
        !FParse::Value(FCommandLine::Get(),TEXT("LivingTownMetaHumanBen="),Descriptor)||Descriptor.IsEmpty()||
        !FParse::Value(FCommandLine::Get(),TEXT("CafeWorldPersona="),Persona)||Persona!=TEXT("ben"))
    {AddError(TEXT("Explicit WorldV3, qualified MetaHuman v2 descriptor, action-clip test flag and CafeWorldPersona=ben required"));return false;}
    int32 Count=0;auto* World=ActionWorld(Count);
    if(Count>1){AddError(TEXT("Multiple actual runtime worlds refused"));return false;}
    if(!World&&!AutomationOpenMap(TEXT("/Engine/Maps/Entry"),true))return false;
    ADD_LATENT_AUTOMATION_COMMAND(FMetaHumanActionClip(this));return true;
}
#endif
