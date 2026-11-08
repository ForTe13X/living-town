#include "LivingTownFullTownData.h"
#include "LivingTownFullTownDriver.h"
#include "LivingTownFullTownStreamingSubsystem.h"
#include "LivingTownCafeWorldV3Scenario.h"
#include "LivingTownCafeWorldV3Subsystem.h"
#include "LivingTownCafeProjectionSubsystem.h"
#include "LivingTownCafePropertyV2Subsystem.h"
#include "LivingTownLeaseSubsystem.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownCafeVenue.h"
#include "LivingTownMetaHumanVisualAssembly.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Tests/AutomationCommon.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Components/CapsuleComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/Engine.h"
#include "Engine/GameInstance.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformTime.h"
#include "InputCoreTypes.h"
#include "InputKeyEventArgs.h"
#include "Misc/CommandLine.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "UObject/StrongObjectPtrTemplates.h"
#include "UObject/Package.h"

namespace
{
constexpr TCHAR Root[]=TEXT("/Game/LivingTown_UEPilot/FullTownWorldV3_289_v001/L_FullTownWorldV3_289_v001");
constexpr TCHAR Manifest[]=TEXT("/Game/LivingTown_UEPilot/FullTownWorldV3_289_v001/DA_FullTownWorldV3_289_v001.DA_FullTownWorldV3_289_v001");
UWorld* TownWorld(int32& Count)
{
    Count=0;UWorld* Result=nullptr;
    if(GEngine)for(const auto& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::PIE||C.WorldType==EWorldType::Game)){++Count;Result=C.World();}
    return Result;
}
bool Object(const FString& Text,TSharedPtr<FJsonObject>& O)
{return FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),O)&&O.IsValid();}

// Real native input, naturally ticking actors, and a deliberately terminal safe
// stop. This is not a seam/long-route, eating, art or capture qualification.
class FWorldV3TownBridge final:public IAutomationLatentCommand
{
    FAutomationTestBase* Test;
    double Deadline=FPlatformTime::Seconds()+420,StageTime=0;
    int32 Stage=0,BootSamples=0;bool Done=false,Pressed=false,BootFeetSet=false;
    FVector BootFeet=FVector::ZeroVector,Start=FVector::ZeroVector,Stopped=FVector::ZeroVector;
    double WalkDistance=0;uint32 BodyRevision=0,ControllerId=0,BootPawnId=0;
    TWeakObjectPtr<UWorld> World;
    TWeakObjectPtr<ALivingTownCafeWorldV3Controller> PC;
    TWeakObjectPtr<ALivingTownCafeCharacter> Pawn;
    TWeakObjectPtr<ULivingTownMetaHumanVisualAssembly> Assembly;
    TWeakObjectPtr<AActor> Visual;
    TWeakObjectPtr<USkeletalMeshComponent> Body,Face,Outfit;
    TWeakObjectPtr<UAnimSingleNodeInstance> Player;
    TWeakObjectPtr<UAnimInstance> BodyPost,FaceMain,FacePost;
    void Key(bool Down){if(auto* C=PC.Get())C->InputKey(FInputKeyEventArgs::CreateSimulated(EKeys::W,Down?IE_Pressed:IE_Released,Down?1.f:0.f));Pressed=Down;}
    bool Need(bool Ok,const TCHAR* Why)
    {
        if(!Ok){Key(false);Test->AddError(FString::Printf(TEXT("Town bridge stage=%d: %s"),Stage,Why));Done=true;}return Ok;
    }
    bool Owners()const
    {
        auto* C=PC.Get();auto* P=Pawn.Get();auto* A=Assembly.Get();auto* B=Body.Get();auto* F=Face.Get();auto* O=Outfit.Get();
        return C&&P&&A&&B&&F&&O&&Visual.IsValid()&&Player.IsValid()&&C->GetPawn()==P&&P->GetController()==C&&C->GetViewTarget()==P&&
            C->HasNativePersona()&&C->GetNativePersona()==ELivingTownCafeWorldPersona::Ben&&P->HasQualifiedVisual()&&P->HasMetaHumanVisual()&&
            A->IsConfigured()&&A->GetVisualActor()==Visual.Get()&&A->GetBody()==B&&A->GetFace()==F&&B->GetSingleNodeInstance()==Player.Get()&&
            B->GetPostProcessInstance()==BodyPost.Get()&&F->GetAnimationMode()==EAnimationMode::AnimationBlueprint&&F->GetAnimInstance()==FaceMain.Get()&&
            F->GetPostProcessInstance()==FacePost.Get()&&O->LeaderPoseComponent.Get()==B;
    }
public:
    explicit FWorldV3TownBridge(FAutomationTestBase* T):Test(T){}
    ~FWorldV3TownBridge(){if(Pressed)Key(false);}
    bool Update()override
    {
        if(Done)return true;
        if(!Need(FPlatformTime::Seconds()<Deadline,TEXT("Finite420s fresh-fixture deadline")))return true;
        int32 Count=0;auto* W=TownWorld(Count);if(!Need(Count<=1,TEXT("Exactly one native world")))return true;if(!W)return false;
        if(!World.IsValid())World=W;
        if(!Need(World.Get()==W&&UWorld::RemovePIEPrefix(W->GetOutermost()->GetName())==Root,TEXT("Exact new saved root; never Entry or old262 map")))return true;
        auto* Town=W->GetSubsystem<ULivingTownFullTownStreamingSubsystem>();auto* Authority=W->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();
        if(!Need(Town&&Authority&&W->GetAuthGameMode()&&W->GetAuthGameMode()->GetClass()==ALivingTownCafeWorldV3GameMode::StaticClass(),TEXT("Exact WorldV3 and FullTown owners")))return true;
        TSharedPtr<FJsonObject> S;if(!Need(Object(Town->GetStatusJson(),S),TEXT("Actual native status")))return true;
        const FString Status=S->GetStringField(TEXT("status"));
        if(!Need(Status!=TEXT("FAILED_SUPPORT_RETAINED"),TEXT("No draft, source, session or geometry refusal")))return true;
        if(Stage==0)
        {
            auto* C=Cast<ALivingTownCafeWorldV3Controller>(W->GetFirstPlayerController());
            if(C&&ControllerId==0){PC=C;ControllerId=C->GetUniqueID();}
            if(!Need(ControllerId==0||(C&&PC.Get()==C&&C->GetUniqueID()==ControllerId),TEXT("Controller stays identical across asynchronous preload")))return true;
            if(Status!=TEXT("SUBSET_CONTROLLABLE_NOT_FULL_TOWN"))
            {
                if(C&&!Pressed)Key(true);
                if(auto* P=C?Cast<ALivingTownCafeCharacter>(C->GetPawn()):nullptr)
                {
                    if(!BootFeetSet){BootFeet=P->GetActorLocation();BootFeetSet=true;BootPawnId=P->GetUniqueID();}
                    if(!Need(P->GetUniqueID()==BootPawnId&&C->IsMoveInputIgnored()&&FVector::Dist2D(BootFeet,P->GetActorLocation())<1,TEXT("Observed boot input cannot replace or move current pawn")))return true;
                    ++BootSamples;
                }
                return false;
            }
            Key(false);auto* P=C?Cast<ALivingTownCafeCharacter>(C->GetPawn()):nullptr;
            if(!Need(C&&P&&(!BootPawnId||P->GetUniqueID()==BootPawnId)&&Authority->IsPrepared()&&Authority->GetPresentation().bSessionReady&&!C->IsMoveInputIgnored()&&
                !S->GetBoolField(TEXT("owned_movement_lock"))&&S->GetNumberField(TEXT("post_possession_owned_relocks"))==1&&
                S->GetNumberField(TEXT("ready_frame"))>S->GetNumberField(TEXT("armed_frame"))&&
                S->GetNumberField(TEXT("external_cafe_part_count"))==289&&S->GetNumberField(TEXT("declared_total_role_count"))==1260,TEXT("Qualified289/1260 and balanced initial possession lock")))return true;
            const auto* Legacy=W->GetSubsystem<ULivingTownCafeProjectionSubsystem>();
            if(!Need((!Legacy||(!Legacy->IsReady()&&!Legacy->IsScenePrepared()))&&!W->GetSubsystem<ULivingTownCafePropertyV2Subsystem>()&&
                W->GetGameInstance()&&!W->GetGameInstance()->GetSubsystem<ULivingTownLeaseSubsystem>(),TEXT("No parallel legacy/property authority")))return true;
            const auto& Binding=Authority->GetBinding();
            if(!Need(Binding.Parts.Num()==289&&Binding.MetaHumanActor.IsSet()&&Binding.BindingFileSha256==TEXT("38171606986ba5086102aeba31927fac698558eebed861dd0f4d8eaf713fad6e"),TEXT("Accepted289 scene and current descriptor preserved")))return true;
            Pawn=P;Assembly=P->FindComponentByClass<ULivingTownMetaHumanVisualAssembly>();auto* A=Assembly.Get();
            if(!Need(A&&A->IsConfigured(),TEXT("Original complete MetaHuman assembly")))return true;
            Visual=A->GetVisualActor();Body=A->GetBody();Face=A->GetFace();TArray<USkeletalMeshComponent*> Parts;
            if(Visual.IsValid())Visual->GetComponents(Parts);
            for(auto* Part:Parts)if(Part->GetSkeletalMeshAsset()&&Part->GetSkeletalMeshAsset()->GetPathName()==Binding.MetaHumanActor->ExpectedOutfitMesh())Outfit=Part;
            if(!Need(Body.IsValid()&&Face.IsValid()&&Outfit.IsValid()&&Parts.Num()==3,TEXT("Original Body/Face/current Outfit only")))return true;
            Player=Body->GetSingleNodeInstance();BodyPost=Body->GetPostProcessInstance();FaceMain=Face->GetAnimInstance();FacePost=Face->GetPostProcessInstance();
            if(!Need(BodyPost.IsValid()&&FaceMain.IsValid()&&FacePost.IsValid()&&Owners(),TEXT("Exact player, BodyPP, FaceABP/PP and Outfit leader")))return true;
            int32 Venues=0,Drivers=0;TSet<FString> Roles;
            for(TActorIterator<AActor> It(W);It;++It)
            {
                if(auto* V=Cast<ALivingTownCafeVenue>(*It)){++Venues;TArray<UStaticMeshComponent*> Cmp;V->GetComponents(Cmp);if(!Need(V->IsQualified()&&Cmp.Num()==289,TEXT("One original289 venue")))return true;}
                if(auto* D=Cast<ALivingTownFullTownDriver>(*It))if(D->bEnableIntegrationSubset)++Drivers;
                TArray<UStaticMeshComponent*> Cmp;It->GetComponents(Cmp);
                for(auto* Component:Cmp)for(const FName Tag:Component->ComponentTags)if(Tag.ToString().StartsWith(TEXT("LT_FTW_ROLE=")))
                {const FString Id=Tag.ToString().Mid(12);if(!Need(!Roles.Contains(Id),TEXT("No duplicated streamed role")))return true;Roles.Add(Id);}
            }
            if(!Need(Venues==1&&Drivers==1&&Roles.Num()==971,TEXT("One driver,971 streamed and289 external; no duplicated262 cafe")))return true;
            Stage=1;StageTime=W->GetTimeSeconds();return false;
        }
        if(!Need(Owners()&&Authority->GetPresentation().bSessionReady&&!Authority->GetPresentation().bMealActive,TEXT("Same live native owners throughout input; no meal is started")))return true;
        if(Stage==1)
        {
            if(W->GetTimeSeconds()-StageTime<.5||!Authority->GetPresentation().bMealAvailable)return false;
            if(!Need(Pawn->GetCharacterMovement()->CurrentFloor.IsWalkableFloor(),TEXT("Actual grounded current capsule before input")))return true;
            Start=Pawn->GetActorLocation();BodyRevision=Body->GetBoneTransformRevisionNumber();Key(true);Stage=2;StageTime=W->GetTimeSeconds();return false;
        }
        if(Stage==2)
        {
            if(!Need(Pawn->GetCharacterMovement()->IsMovingOnGround()&&Pawn->GetCharacterMovement()->CurrentFloor.IsWalkableFloor(),TEXT("Natural walking stays grounded")))return true;
            if(W->GetTimeSeconds()-StageTime<.75)return false;
            Key(false);WalkDistance=FVector::Dist2D(Start,Pawn->GetActorLocation());
            if(!Need(WalkDistance>15&&Body->GetBoneTransformRevisionNumber()!=BodyRevision,TEXT("Actual W advances pawn and naturally evaluated Body")))return true;
            Stage=3;StageTime=W->GetTimeSeconds();return false;
        }
        if(Stage==3)
        {
            if(!Need(W->GetTimeSeconds()-StageTime<5,TEXT("Finite natural input-release settling")))return true;
            if(Pawn->GetVelocity().Size2D()>.1)return false;
            Stopped=Pawn->GetActorLocation();Town->RequestSafeStop();Key(true);Stage=4;StageTime=W->GetTimeSeconds();return false;
        }
        if(!Need(Status==TEXT("STOPPED_SUPPORT_RETAINED")&&PC->IsMoveInputIgnored()&&S->GetBoolField(TEXT("owned_movement_lock"))&&
            FVector::Dist2D(Stopped,Pawn->GetActorLocation())<2&&Pawn->GetCharacterMovement()->CurrentFloor.IsWalkableFloor(),TEXT("Actual held W cannot move after owned support-retaining stop")))return true;
        if(W->GetTimeSeconds()-StageTime<.75)return false;
        Key(false);const auto Proof=MakeShared<FJsonObject>();Proof->SetStringField(TEXT("scope"),TEXT("Native WorldV3/current MetaHuman289 + streamed971, short input walk and terminal safe-stop only"));
        Proof->SetNumberField(TEXT("boot_locked_pawn_samples_observed"),BootSamples);Proof->SetNumberField(TEXT("walk_distance_cm"),WalkDistance);
        Proof->SetBoolField(TEXT("meal_long_route_art_capture_qualified"),false);Proof->SetObjectField(TEXT("final_native_status"),S);
        FString Text;const FString Directory=FPaths::ProjectSavedDir()/TEXT("WorldV3TownBridge");IFileManager::Get().MakeDirectory(*Directory,true);
        if(!Need(FJsonSerializer::Serialize(Proof,TJsonWriterFactory<>::Create(&Text))&&FFileHelper::SaveStringToFile(Text,*(Directory/TEXT("NATIVE_BRIDGE_PROOF.json"))),TEXT("Native proof publication")))return true;
        Done=true;return true;
    }
};
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownWorldV3TownBridgeTest,"LivingTown.FullTown.WorldV3TownBridgeInput",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownWorldV3TownBridgeTest::RunTest(const FString&)
{
    FString Descriptor,Persona;
    if(!FParse::Param(FCommandLine::Get(),TEXT("LivingTownWorldV3TownJourney"))||!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeWorldV3"))||
        !FParse::Value(FCommandLine::Get(),TEXT("LivingTownMetaHumanBen="),Descriptor)||Descriptor.IsEmpty()||
        !FParse::Value(FCommandLine::Get(),TEXT("CafeWorldPersona="),Persona)||Persona!=TEXT("ben")){AddError(TEXT("Explicit current Ben/WorldV3/town journey fixture required"));return false;}
    int32 Count=0;TownWorld(Count);if(Count){AddError(TEXT("Fresh isolated native fixture required"));return false;}
    if(!IFileManager::Get().FileExists(*FPackageName::LongPackageNameToFilename(Root,FPackageName::GetMapPackageExtension()))){AddError(TEXT("Actual new root absent; no skipped or synthetic pass"));return false;}
    TStrongObjectPtr<ULivingTownFullTownData> Data(LoadObject<ULivingTownFullTownData>(nullptr,Manifest));FString Error;
    if(!Data.IsValid()||!LivingTownFullTown::ValidateManifest(*Data.Get(),Error)){AddError(TEXT("Actual final pinned descriptor required: ")+Error);return false;}
    TStrongObjectPtr<ULivingTownFullTownData> Probe(DuplicateObject<ULivingTownFullTownData>(Data.Get(),GetTransientPackage()));
    Probe->CafeBackend=static_cast<ELivingTownFullTownCafeBackend>(255);
    TestFalse(TEXT("Unknown typed backend cannot admit real descriptor"),LivingTownFullTown::ValidateManifest(*Probe.Get(),Error));
    TestEqual(TEXT("Unknown backend refusal"),Error,FString(TEXT("fulltown_unknown_cafe_backend")));
    Probe->CafeBackend=ELivingTownFullTownCafeBackend::LegacyProjection262;
    TestFalse(TEXT("289 profile cannot use legacy backend"),LivingTownFullTown::ValidateManifest(*Probe.Get(),Error));
    Probe->CafeBackend=ELivingTownFullTownCafeBackend::WorldV3Qualified289;Probe->ProfileId=TEXT("B749_ContinuousRoofRuntime_v001");
    TestFalse(TEXT("WorldV3 backend cannot repurpose legacy root profile"),LivingTownFullTown::ValidateManifest(*Probe.Get(),Error));
    Probe->ProfileId=Data->ProfileId;Probe->ExternalCafePartIds.Pop();
    TestFalse(TEXT("Missing cafe role cannot admit whole-town fixture"),LivingTownFullTown::ValidateManifest(*Probe.Get(),Error));
    FLivingTownMetaHumanMealRecipeV2 Recipe;
    if(!FLivingTownMetaHumanMealRecipeV2::ReadQualified(TEXT("LivingTown/MetaHumanMealContactV2.json"),Recipe,Error)){AddError(TEXT("Original source-qualified meal inputs required: ")+Error);return false;}
    if(HasAnyErrors())return false;
    if(!AutomationOpenMap(Root,true))return false;ADD_LATENT_AUTOMATION_COMMAND(FWorldV3TownBridge(this));return true;
}
#endif
