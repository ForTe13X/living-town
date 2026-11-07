#include "LivingTownCafeWorldV3Scenario.h"
#include "LivingTownCafeWorldV3Subsystem.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownMetaHumanVisualAssembly.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Tests/AutomationCommon.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Animation/AnimSequence.h"
#include "Components/CapsuleComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/Engine.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/World.h"
#include "HAL/PlatformTime.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "UObject/Package.h"
#include "UObject/SoftObjectPath.h"
#include "UObject/StrongObjectPtrTemplates.h"

namespace
{
UWorld* PersonaGateWorld(int32& Count)
{
    UWorld* World=nullptr;Count=0;
    if(GEngine)for(const auto& C:GEngine->GetWorldContexts())
        if(C.World()&&(C.WorldType==EWorldType::Game||C.WorldType==EWorldType::PIE)){World=C.World();++Count;}
    return World;
}
// Real native lifecycle consumer: requires staged, source-qualified content and
// normal world ticks. No synthetic readiness, manual poses or elapsed-time setters.
class FMetaHumanPersonaGate final:public IAutomationLatentCommand
{
    FAutomationTestBase* Test;
    const double Deadline=FPlatformTime::Seconds()+180.;
    double CancelledAt=0;
    int32 Stage=0;
    uint32 ObservedWorldId=0;
    bool bDone=false;
    TWeakObjectPtr<ALivingTownCafeWorldV3GameMode> Mode;
    TWeakObjectPtr<ALivingTownCafeWorldV3Controller> Controller;
    TWeakObjectPtr<APawn> OriginalAria;
    TWeakObjectPtr<AActor> Blocker;
    TWeakObjectPtr<ALivingTownCafeCharacter> TestedBen;
    TWeakObjectPtr<ALivingTownCafeCharacter> Probe;
    TWeakObjectPtr<ULivingTownMetaHumanVisualAssembly> TestedAssembly;
    TWeakObjectPtr<AActor> TestedVisual;
    TWeakObjectPtr<USkeletalMeshComponent> TestedBody;
    TWeakObjectPtr<UAnimSingleNodeInstance> IdlePlayer;
    TWeakObjectPtr<UAnimationAsset> IdleAsset;
    struct FPoseOwner
    {
        TWeakObjectPtr<USkeletalMeshComponent> Component;
        TWeakObjectPtr<USkinnedMeshComponent> Leader;
        TWeakObjectPtr<UClass> MainClass,PostClass;
        uint8 Mode=0;
    };
    TArray<FPoseOwner> PoseOwners;
    double LastWorldTime=0,IdleElapsed=0,IdleAdvance=0;
    float LastIdleTime=0,IdleLength=0;
    uint32 InitialBoneRevision=0;
    int32 IdleSamples=0;
    bool Need(bool Ok,const TCHAR* Why){if(!Ok){Test->AddError(Why);bDone=true;}return Ok;}
    bool RetainedAria(ULivingTownCafeWorldV3Subsystem* Authority)
    {
        auto* PC=Controller.Get();
        return PC&&OriginalAria.IsValid()&&PC->GetPawn()==OriginalAria.Get()&&PC->GetViewTarget()==OriginalAria.Get()&&
            PC->HasNativePersona()&&PC->GetNativePersona()==ELivingTownCafeWorldPersona::Aria&&
            Authority->GetPresentation().bSessionReady&&Authority->GetPresentation().Persona==TEXT("aria");
    }
public:
    explicit FMetaHumanPersonaGate(FAutomationTestBase* InTest):Test(InTest){}
    virtual ~FMetaHumanPersonaGate()
    {
        int32 Count=0;const auto* LiveWorld=PersonaGateWorld(Count);
        // Cleanup may run after PIE shutdown. Observe the live context by ID;
        // never ask retained actors for the world whose lifetime has ended.
        if(Count!=1||!LiveWorld||LiveWorld->GetUniqueID()!=ObservedWorldId)return;
        if(Blocker.IsValid())Blocker->Destroy();
        if(Probe.IsValid())Probe->Destroy();
        if(Mode.IsValid()&&Controller.IsValid()&&Mode->GetPersonaRequestResult()==ELivingTownCafePersonaRequestResult::Pending)
        {FString Error;Mode->RequestPersona(Controller.Get(),ELivingTownCafeWorldPersona::Aria,Error);}
    }
    virtual bool Update()override
    {
        if(bDone)return true;
        if(!Need(FPlatformTime::Seconds()<Deadline,TEXT("Actual MetaHuman persona gate timed out")))return true;
        int32 Count=0;auto* World=PersonaGateWorld(Count);
        if(ObservedWorldId&&(!World||Count!=1||World->GetUniqueID()!=ObservedWorldId))
        {Need(false,TEXT("The observed actual runtime world ended or changed during the lifecycle test"));return true;}
        if(!Need(Count<=1,TEXT("One actual runtime world required"))||!World||!World->HasBegunPlay())return bDone;
        if(!ObservedWorldId)ObservedWorldId=World->GetUniqueID();
        auto* G=World->GetAuthGameMode<ALivingTownCafeWorldV3GameMode>();
        auto* Authority=World->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();
        auto* PC=Cast<ALivingTownCafeWorldV3Controller>(World->GetFirstPlayerController());
        if(!G||!Authority||!Authority->IsPrepared()||!PC)return false;
        if(!Need(G->GetClass()==ALivingTownCafeWorldV3GameMode::StaticClass()&&World->GetNetMode()==NM_Standalone&&
            Authority->GetBinding().MetaHumanActor.IsSet(),TEXT("Exact standalone WorldV3 with actual prepared MetaHuman opt-in required")))return true;
        Mode=G;Controller=PC;FString Error;
        if(Stage==0)
        {
            if(!PC->GetPawn()||!PC->HasNativePersona())return false;
            if(!Need(PC->GetNativePersona()==ELivingTownCafeWorldPersona::Aria,TEXT("Start from an actual authored Aria session")))return true;
            OriginalAria=PC->GetPawn();FString Before,After;
            if(!Need(Authority->EncodeJournal(Before,Error),TEXT("Capture actual paired authority")))return true;
            if(!Need(!G->FindComponentByClass<ULivingTownMetaHumanVisualPreload>(),TEXT("Aria startup must not create a MetaHuman preload")))return true;
            if(!Need(!G->SelectPersona(PC,ELivingTownCafeWorldPersona::Ben,Error)&&Error==TEXT("metahuman_persona_preload_required"),
                TEXT("Immediate API refuses unprepared Ben without starting async work")))return true;
            if(!Need(RetainedAria(Authority)&&!G->FindComponentByClass<ULivingTownMetaHumanVisualPreload>()&&
                Authority->EncodeJournal(After,Error)&&After==Before,TEXT("Immediate refusal preserves exact pawn/session and paired bytes")))return true;
            if(!Need(G->RequestPersona(PC,ELivingTownCafeWorldPersona::Ben,Error)==ELivingTownCafePersonaRequestResult::Pending&&
                RetainedAria(Authority)&&Authority->EncodeJournal(After,Error)&&After==Before,
                TEXT("Pending is distinct from success/refusal and retains authoritative Aria")))return true;
            TStrongObjectPtr<ALivingTownCafeWorldV3Controller> ForeignController(NewObject<ALivingTownCafeWorldV3Controller>(GetTransientPackage()));
            const auto InvalidPersona=static_cast<ELivingTownCafeWorldPersona>(255);
            if(!Need(G->RequestPersona(ForeignController.Get(),ELivingTownCafeWorldPersona::Aria,Error)==ELivingTownCafePersonaRequestResult::Refused&&
                G->RequestPersona(PC,InvalidPersona,Error)==ELivingTownCafePersonaRequestResult::Refused&&
                !G->SelectPersona(ForeignController.Get(),ELivingTownCafeWorldPersona::Aria,Error)&&!G->SelectPersona(PC,InvalidPersona,Error)&&
                G->GetPersonaRequestResult()==ELivingTownCafePersonaRequestResult::Pending&&RetainedAria(Authority)&&Authority->EncodeJournal(After,Error)&&After==Before,
                TEXT("Unauthorized controller/persona calls cannot cancel legitimate pending Ben or alter Aria's pawn/session/paired bytes")))return true;
            if(!Need(G->RequestPersona(PC,ELivingTownCafeWorldPersona::Ben,Error)==ELivingTownCafePersonaRequestResult::Pending&&RetainedAria(Authority),
                TEXT("Newer Ben request replaces the old pending epoch without a pawn switch")))return true;
            if(!Need(G->RequestPersona(PC,ELivingTownCafeWorldPersona::Aria,Error)==ELivingTownCafePersonaRequestResult::Selected&&RetainedAria(Authority),
                TEXT("Selecting already-current Aria cancels pending Ben")))return true;
            CancelledAt=World->GetTimeSeconds();Stage=1;return false;
        }
        if(Stage==1)
        {
            if(!Need(RetainedAria(Authority)&&G->GetPersonaRequestResult()==ELivingTownCafePersonaRequestResult::Selected,
                TEXT("Cancelled callbacks cannot replace the actual current persona")))return true;
            if(World->GetTimeSeconds()-CancelledAt<.5)return false;
            const auto& B=Authority->GetBinding();const FTransform Spawn(B.SpawnRotation,B.SpawnFeetCm+FVector(0,0,B.CapsuleHalfHeightCm));
            FActorSpawnParameters Params;Params.SpawnCollisionHandlingOverride=ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Obstacle=World->SpawnActor<AActor>(AActor::StaticClass(),Spawn,Params);
            if(!Need(Obstacle!=nullptr,TEXT("Actual temporary collision obstacle")))return true;Blocker=Obstacle;
            auto* Capsule=NewObject<UCapsuleComponent>(Obstacle);Obstacle->AddInstanceComponent(Capsule);Obstacle->SetRootComponent(Capsule);
            Capsule->InitCapsuleSize(B.CapsuleRadiusCm*1.5f,B.CapsuleHalfHeightCm*1.5f);
            Capsule->SetCollisionEnabled(ECollisionEnabled::QueryOnly);Capsule->SetCollisionObjectType(ECC_WorldStatic);
            Capsule->SetCollisionResponseToAllChannels(ECR_Block);Capsule->RegisterComponent();Obstacle->SetActorTransform(Spawn);
            if(!Need(G->RequestPersona(PC,ELivingTownCafeWorldPersona::Ben,Error)==ELivingTownCafePersonaRequestResult::Pending&&RetainedAria(Authority),
                TEXT("Cancelled preload can retry while old persona stays bound")))return true;
            Stage=2;return false;
        }
        if(Stage==2)
        {
            if(!Need(RetainedAria(Authority),TEXT("Pending or blocked candidate must preserve Aria possession and session")))return true;
            if(G->GetPersonaRequestResult()==ELivingTownCafePersonaRequestResult::Pending)return false;
            auto* Preload=G->FindComponentByClass<ULivingTownMetaHumanVisualPreload>();
            if(!Need(G->GetPersonaRequestResult()==ELivingTownCafePersonaRequestResult::Refused&&Preload&&
                Preload->IsReadyFor(Authority->GetBinding().MetaHumanActor.GetValue()),
                TEXT("Actual loaded candidate fails collision without destroying prior authority")))return true;
            Blocker->Destroy();Blocker.Reset();
            if(!Need(G->SelectPersona(PC,ELivingTownCafeWorldPersona::Ben,Error),TEXT("Already-ready complete actor can commit through immediate API")))
            {Test->AddError(Error);return true;}
            auto* Ben=Cast<ALivingTownCafeCharacter>(PC->GetPawn());
            auto* Assembly=Ben?Ben->FindComponentByClass<ULivingTownMetaHumanVisualAssembly>():nullptr;
            auto* Visual=Assembly?Assembly->GetVisualActor():nullptr;auto* Body=Ben?Ben->GetVisualBody():nullptr;
            if(!Need(Ben&&Ben->GetClass()==ALivingTownCafeCharacter::StaticClass()&&Ben->HasQualifiedVisual()&&Ben->HasMetaHumanVisual()&&
                PC->HasNativePersona()&&PC->GetNativePersona()==ELivingTownCafeWorldPersona::Ben&&PC->GetViewTarget()==Ben&&!OriginalAria.IsValid()&&
                Authority->GetPresentation().bSessionReady&&Authority->GetPresentation().Persona==TEXT("ben"),
                TEXT("Commit keeps exact native pawn/controller authority and retires prior pawn only after bind")))return true;
            if(!Need(Assembly&&Visual&&Visual->GetParentActor()==Ben&&Body&&Body->GetOwner()==Visual&&Body!=Ben->GetMesh()&&
                Body->GetCollisionEnabled()==ECollisionEnabled::NoCollision,TEXT("Whole generated actor owns its body; no component transplant or pawn replacement")))return true;
            PC->UnPossess();
            if(!Need(Ben->HasQualifiedVisual()&&Ben->HasMetaHumanVisual()&&Assembly->GetVisualActor()==Visual&&Ben->GetVisualBody()==Body,
                TEXT("Unpossess restores tick policy without destroying complete actor ownership")))return true;
            PC->Possess(Ben);PC->SetViewTarget(Ben);
            if(!Need(Authority->BindNativeSession(PC,Ben,Error),TEXT("Same qualified actor rebinds after normal repossession")))return true;
            FString Saved;
            if(!Need(Authority->EncodeJournal(Saved,Error)&&Authority->LoadJournal(Saved,Error)&&PC->GetPawn()==Ben&&
                PC->GetNativePersona()==ELivingTownCafeWorldPersona::Ben&&Ben->GetVisualBody()==Body&&Assembly->GetVisualActor()==Visual,
                TEXT("Existing paired save/load retains actual persona and complete visual actor")))return true;
            TArray<USkeletalMeshComponent*> Components;Visual->GetComponents(Components);
            if(!Need(Components.Num()==3&&Visual->HasActorBegunPlay()&&Visual->GetOwner()==Ben,
                TEXT("Body, face and outfit remain in the normally begun SDK actor")))return true;
            bool bFace=false,bOutfit=false;
            for(auto* C:Components)
            {
                if(C==Body)continue;
                const FString Path=C->GetSkeletalMeshAsset()?C->GetSkeletalMeshAsset()->GetPathName():FString();
                bFace|=Path==LivingTownMetaHumanVisual::FaceMesh;bOutfit|=Path==Authority->GetBinding().MetaHumanActor.GetValue().ExpectedOutfitMesh();
                if(!Need(C->GetOwner()==Visual&&C->GetAttachParent()==Body&&C->IsRegistered()&&C->GetCollisionEnabled()==ECollisionEnabled::NoCollision&&
                    (C->LeaderPoseComponent.Get()==Body||C->GetAnimInstance()||C->GetPostProcessInstance()),
                    TEXT("Actual face/outfit use the SDK's owned body attachment and live pose sources")))return true;
                FPoseOwner O;O.Component=C;O.Leader=C->LeaderPoseComponent;O.Mode=uint8(C->GetAnimationMode());
                O.MainClass=C->GetAnimInstance()?C->GetAnimInstance()->GetClass():nullptr;
                O.PostClass=C->GetPostProcessInstance()?C->GetPostProcessInstance()->GetClass():nullptr;PoseOwners.Add(O);
            }
            auto* Player=Body->GetSingleNodeInstance();
            if(!Need(bFace&&bOutfit&&Player&&Player->GetCurrentAsset()==Preload->GetIdle(),TEXT("Exact generated face/outfit and compatible native idle are present")))return true;
            if(!Need(Body->GetPostProcessInstance()&&Body->GetPostProcessInstance()->GetClass()->GetPathName()==LivingTownMetaHumanVisual::BodyPostProcessClass&&!Body->GetDisablePostProcessBlueprint(),
                TEXT("Native body retains the exact enabled MetaHuman body postprocess after locomotion setup")))return true;
            TestedBen=Ben;TestedAssembly=Assembly;TestedVisual=Visual;TestedBody=Body;IdlePlayer=Player;IdleAsset=Player->GetCurrentAsset();
            LastWorldTime=World->GetTimeSeconds();LastIdleTime=Player->GetCurrentTime();IdleLength=Preload->GetIdle()->GetPlayLength();InitialBoneRevision=Body->GetBoneTransformRevisionNumber();
            Stage=3;return false;
        }
        if(Stage==3)
        {
            auto* Ben=TestedBen.Get();auto* Assembly=TestedAssembly.Get();auto* Body=TestedBody.Get();auto* Player=IdlePlayer.Get();
            if(!Need(Ben&&Assembly&&Body&&Player&&PC->GetPawn()==Ben&&Ben->HasMetaHumanVisual()&&Ben->HasQualifiedVisual()&&
                Assembly->GetVisualActor()==TestedVisual.Get()&&Ben->GetVisualBody()==Body&&Body->GetSingleNodeInstance()==Player&&
                Player->GetCurrentAsset()==IdleAsset.Get()&&Ben->GetVelocity().Size2D()<2.f,
                TEXT("Unchanged actual idle keeps the exact complete actor/body/player/asset")))return true;
            if(!Need(Body->GetPostProcessInstance()&&Body->GetPostProcessInstance()->GetClass()->GetPathName()==LivingTownMetaHumanVisual::BodyPostProcessClass&&!Body->GetDisablePostProcessBlueprint(),
                TEXT("Normal idle ticks retain the exact enabled MetaHuman body postprocess")))return true;
            for(const auto& O:PoseOwners)
            {
                auto* C=O.Component.Get();
                if(!Need(C&&C->GetOwner()==TestedVisual.Get()&&uint8(C->GetAnimationMode())==O.Mode&&C->LeaderPoseComponent.Get()==O.Leader.Get()&&
                    (C->GetAnimInstance()?C->GetAnimInstance()->GetClass():nullptr)==O.MainClass.Get()&&
                    (C->GetPostProcessInstance()?C->GetPostProcessInstance()->GetClass():nullptr)==O.PostClass.Get(),
                    TEXT("Normal idle ticks preserve SDK face/outfit pose mode, leader and animation classes")))return true;
            }
            const double Now=World->GetTimeSeconds(),Elapsed=Now-LastWorldTime;const float Time=Player->GetCurrentTime();
            if(Elapsed<=0)return false;
            if(!Need(Elapsed<IdleLength&&FMath::IsFinite(Time),TEXT("Actual idle sample interval remains observable within one loop")))return true;
            double Advanced=Time-LastIdleTime;if(Advanced<0)Advanced+=IdleLength;
            IdleElapsed+=Elapsed;IdleAdvance+=Advanced;LastWorldTime=Now;LastIdleTime=Time;++IdleSamples;
            if(IdleElapsed<.35||IdleSamples<3)return false;
            if(!Need(IdleAdvance>.1&&FMath::Abs(IdleAdvance-IdleElapsed)<.08&&Body->GetBoneTransformRevisionNumber()!=InitialBoneRevision,
                TEXT("Real idle time/bones advance across unchanged states; no per-tick animation reset")))return true;
            const auto Before=Authority->GetPresentation();FLivingTownCafeMealCommand Command;
            Command.RequestId=TEXT("native/metahuman/no-contact/")+FGuid::NewGuid().ToString(EGuidFormats::Digits);Command.ExpectedRevision=Before.Revision;
            const auto Receipt=PC->RequestMeal(Command);const auto After=Authority->GetPresentation();
            if(!Need(!Receipt.bAccepted&&Receipt.Reason==TEXT("metahuman_reviewed_eating_contact_recipe_required")&&!After.bMealAvailable&&!After.bMealActive&&
                Before.Stock==After.Stock&&Before.AriaCoins==After.AriaCoins&&Before.BenCoins==After.BenCoins&&Before.Hunger==After.Hunger&&Before.Fun==After.Fun,
                TEXT("Public native command explicitly refuses absent MetaHuman contact recipe without gameplay effects")))return true;
            const auto& B=Authority->GetBinding();FActorSpawnParameters Params;Params.SpawnCollisionHandlingOverride=ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            const FTransform Away(B.SpawnRotation,B.SpawnFeetCm+FVector(1000,0,500));
            auto* EndPlayProbe=World->SpawnActor<ALivingTownCafeCharacter>(ALivingTownCafeCharacter::StaticClass(),Away,Params);Probe=EndPlayProbe;
            if(!Need(EndPlayProbe&&EndPlayProbe->ConfigureQualifiedBen(B,Error),TEXT("Actually begun independent native EndPlay probe configures from the same preload")))return true;
            auto* EndPlayAssembly=EndPlayProbe->FindComponentByClass<ULivingTownMetaHumanVisualAssembly>();
            TWeakObjectPtr<AActor> EndPlayChild=EndPlayAssembly?EndPlayAssembly->GetVisualActor():nullptr;
            if(!Need(EndPlayChild.IsValid(),TEXT("Actual child exists before parent EndPlay")))return true;
            EndPlayProbe->Destroy();Probe.Reset();
            if(!Need(!EndPlayChild.IsValid(),TEXT("Normal native parent EndPlay removes the complete child actor")))return true;
            auto* ResetProbe=World->SpawnActor<ALivingTownCafeCharacter>(ALivingTownCafeCharacter::StaticClass(),Away,Params);Probe=ResetProbe;
            if(!Need(ResetProbe&&ResetProbe->ConfigureQualifiedBen(B,Error),TEXT("Independent reset probe configures")))return true;
            auto* ResetAssembly=ResetProbe->FindComponentByClass<ULivingTownMetaHumanVisualAssembly>();
            TWeakObjectPtr<AActor> ResetChild=ResetAssembly?ResetAssembly->GetVisualActor():nullptr;
            if(!Need(ResetAssembly&&ResetChild.IsValid(),TEXT("Actual child exists before explicit reset")))return true;
            if(B.MetaHumanActor.GetValue().UsesWorkwear())
            {
                TArray<USkeletalMeshComponent*> Parts;ResetChild->GetComponents(Parts);USkeletalMeshComponent* Wardrobe=nullptr;
                for(auto* Part:Parts)
                    if(Part->GetSkeletalMeshAsset()&&Part->GetSkeletalMeshAsset()->GetPathName()==B.MetaHumanActor.GetValue().ExpectedOutfitMesh()) Wardrobe=Part;
                auto* ForeignMaterial=ResetAssembly->GetBody()->GetMaterial(0);
                if(!Need(Wardrobe&&ForeignMaterial&&ForeignMaterial!=Wardrobe->GetMaterial(0),TEXT("Independent probe has distinct body and wardrobe materials")))return true;
                Wardrobe->SetMaterial(0,ForeignMaterial);
                if(!Need(!ResetAssembly->IsConfigured()&&!ResetAssembly->UpdateMotion(0)&&!ResetProbe->HasQualifiedVisual()&&Ben->HasQualifiedVisual(),
                    TEXT("Late outfit material overwrite refuses the independent probe without affecting the possessed actor")))return true;
                Wardrobe->EmptyOverrideMaterials();
                if(!Need(ResetAssembly->IsConfigured(),TEXT("Probe mesh defaults restore the admitted three materials")))return true;
                Wardrobe->SetOverlayMaterial(ForeignMaterial);
                if(!Need(!ResetAssembly->IsConfigured()&&!ResetAssembly->UpdateMotion(0)&&!ResetProbe->HasQualifiedVisual()&&Ben->HasQualifiedVisual(),
                    TEXT("Late global outfit overlay refuses the independent probe without affecting the possessed actor")))return true;
                Wardrobe->SetOverlayMaterial(nullptr);
                if(!Need(ResetAssembly->IsConfigured(),TEXT("Clearing the global overlay restores the admitted wardrobe")))return true;
                Wardrobe->SetOverlayMaterial(ForeignMaterial,true,0);
                if(!Need(!ResetAssembly->IsConfigured()&&!ResetAssembly->UpdateMotion(0)&&!ResetProbe->HasQualifiedVisual()&&Ben->HasQualifiedVisual(),
                    TEXT("Late outfit slot overlay refuses the independent probe without affecting the possessed actor")))return true;
                Wardrobe->EmptyOverrideMaterials();
                if(!Need(ResetAssembly->IsConfigured(),TEXT("Clearing the slot overlay restores the admitted wardrobe")))return true;
                auto* OriginalOutfit=Cast<USkeletalMesh>(FSoftObjectPath(LivingTownMetaHumanVisual::OutfitMesh).ResolveObject());
                if(!Need(OriginalOutfit!=nullptr,TEXT("Original SDK outfit remains loaded independently of the derivative")))return true;
                Wardrobe->SetSkeletalMesh(OriginalOutfit,false);
                if(!Need(!ResetAssembly->IsConfigured()&&!ResetProbe->HasQualifiedVisual()&&Ben->HasQualifiedVisual(),
                    TEXT("Late SDK outfit replacement refuses the independent probe while retaining the actual player")))return true;
            }
            ResetAssembly->Reset();ResetAssembly->Reset();
            if(!Need(!ResetChild.IsValid()&&!ResetAssembly->IsConfigured()&&!ResetAssembly->GetVisualActor()&&!ResetAssembly->GetBody()&&!ResetProbe->HasQualifiedVisual(),
                TEXT("Repeated holder reset removes owned child and clears actual qualification idempotently")))return true;
            ResetProbe->Destroy();Probe.Reset();
            bDone=true;return true;
        }
        return false;
    }
};
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownMetaHumanPersonaGateTest,"LivingTown.MetaHuman.WorldV3PersonaGate",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownMetaHumanPersonaGateTest::RunTest(const FString&)
{
    FString Persona;
    if(!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeWorldV3"))||!FParse::Param(FCommandLine::Get(),TEXT("LivingTownMetaHumanPersonaGateTest"))||
       !FParse::Value(FCommandLine::Get(),TEXT("LivingTownMetaHumanBen="),Persona)||Persona.IsEmpty()||
       !FParse::Value(FCommandLine::Get(),TEXT("CafeWorldPersona="),Persona)||Persona!=TEXT("aria"))
    {AddError(TEXT("Explicit WorldV3, prepared MetaHuman descriptor, persona-gate test flag and CafeWorldPersona=aria required"));return false;}
    int32 Count=0;auto* World=PersonaGateWorld(Count);
    if(Count>1){AddError(TEXT("Multiple actual runtime worlds refused"));return false;}
    if(!World&&!AutomationOpenMap(TEXT("/Engine/Maps/Entry"),true))return false;
    ADD_LATENT_AUTOMATION_COMMAND(FMetaHumanPersonaGate(this));return true;
}
#endif
