#include "LivingTownCafeWorldV3Scenario.h"
#include "LivingTownCafeWorldV3Subsystem.h"
#include "LivingTownCafePropertyV2Scenario.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownFullTownStreamingSubsystem.h"
#include "LivingTownMetaHumanVisualAssembly.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Tests/AutomationCommon.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
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
#include "UObject/SoftObjectPath.h"

namespace
{
constexpr TCHAR PersonaBootRoot[]=TEXT("/Game/LivingTown_UEPilot/FullTownWorldV3_289_v001/L_FullTownWorldV3_289_v001");
UWorld* PersonaBootWorld(int32& Count)
{
    Count=0;UWorld* W=nullptr;
    if(GEngine)for(const auto& C:GEngine->GetWorldContexts())
        if(C.World()&&(C.WorldType==EWorldType::Game||C.WorldType==EWorldType::PIE)){W=C.World();++Count;}
    return W;
}
void PersonaKey(ALivingTownCafeWorldV3Controller* PC,FKey Key)
{
    PC->InputKey(FInputKeyEventArgs::CreateSimulated(Key,IE_Pressed,1.f));
    PC->InputKey(FInputKeyEventArgs::CreateSimulated(Key,IE_Released,0.f));
}

// Every variant opens the actual pinned root and lets the engine load/tick.
// No readiness setters, fake callbacks, manual ticks or pawn placement changes.
class FWorldV3PersonaBoot final:public IAutomationLatentCommand
{
    FAutomationTestBase* Test;
    FString Case;
    const double Deadline=FPlatformTime::Seconds()+420.;
    uint32 WorldId=0,ControllerId=0;
    int32 Stage=0,BenBootSamples=0;
    double StageTime=0;
    bool Done=false,SentEarlyF1=false,SentLatestF2=false,CheckedImmediateRefusal=false;
    TWeakObjectPtr<ULivingTownMetaHumanVisualPreload> InitialPreload;
    TWeakObjectPtr<APawn> StablePawn;
    bool Need(bool Ok,const TCHAR* Why)
    {
        if(!Ok){Test->AddError(FString::Printf(TEXT("Persona boot %s stage=%d: %s"),*Case,Stage,Why));Done=true;}
        return Ok;
    }
    bool PersonaIs(ALivingTownCafeWorldV3Controller* PC,ULivingTownCafeWorldV3Subsystem* Authority,ELivingTownCafeWorldPersona Persona)const
    {
        auto* Pawn=PC->GetPawn();const auto* Ben=Cast<ALivingTownCafeCharacter>(Pawn);
        const auto* Aria=Cast<ALivingTownCafePropertyOwnerProxy>(Pawn);
        return Pawn&&Pawn->GetController()==PC&&PC->GetViewTarget()==Pawn&&PC->HasNativePersona()&&PC->GetNativePersona()==Persona&&
            Authority->GetPresentation().bSessionReady&&(Persona==ELivingTownCafeWorldPersona::Ben?
                Ben&&Ben->HasQualifiedVisual()&&Ben->HasMetaHumanVisual()&&Authority->GetPresentation().Persona==TEXT("ben"):
                Aria&&Aria->IsFunctionalOwnerConfigured()&&Authority->GetPresentation().Persona==TEXT("aria"));
    }
    bool Publish(const TSharedPtr<FJsonObject>& Status)
    {
        auto Proof=MakeShared<FJsonObject>();Proof->SetStringField(TEXT("case"),Case);
        Proof->SetStringField(TEXT("scope"),TEXT("Actual WorldV3 persona boot/deferred intent only; no art, meal, long route or performance qualification"));
        Proof->SetNumberField(TEXT("observed_locked_ben_samples"),BenBootSamples);
        Proof->SetBoolField(TEXT("observed_pending_preload_f1"),SentEarlyF1);Proof->SetBoolField(TEXT("last_selection_f2"),SentLatestF2);
        Proof->SetObjectField(TEXT("final_native_status"),Status);
        FString Text;const FString Directory=FPaths::ProjectSavedDir()/TEXT("WorldV3PersonaBoot")/Case;
        IFileManager::Get().MakeDirectory(*Directory,true);
        if(!Need(FJsonSerializer::Serialize(Proof,TJsonWriterFactory<>::Create(&Text))&&
            FFileHelper::SaveStringToFile(Text,*(Directory/TEXT("NATIVE_PERSONA_BOOT_PROOF.json"))),TEXT("Native proof publication")))return true;
        Done=true;return true;
    }
public:
    FWorldV3PersonaBoot(FAutomationTestBase* InTest,const FString& InCase):Test(InTest),Case(InCase){}
    bool Update()override
    {
        if(Done)return true;
        if(!Need(FPlatformTime::Seconds()<Deadline,TEXT("Finite420s natural-world deadline")))return true;
        int32 Count=0;auto* W=PersonaBootWorld(Count);
        if(!Need(Count<=1&&(!WorldId||W),TEXT("One native runtime world survives the test")))return true;if(!W)return false;
        if(!WorldId)WorldId=W->GetUniqueID();
        if(!Need(W->GetUniqueID()==WorldId&&UWorld::RemovePIEPrefix(W->GetOutermost()->GetName())==PersonaBootRoot,
            TEXT("Same exact pinned WorldV3 root")))return true;
        if(!W->HasBegunPlay())return false;
        auto* G=W->GetAuthGameMode<ALivingTownCafeWorldV3GameMode>();
        auto* Town=W->GetSubsystem<ULivingTownFullTownStreamingSubsystem>();auto* Authority=W->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();
        auto* PC=Cast<ALivingTownCafeWorldV3Controller>(W->GetFirstPlayerController());
        if(!Need(G&&G->GetClass()==ALivingTownCafeWorldV3GameMode::StaticClass()&&Town&&Authority&&PC&&W->GetNetMode()==NM_Standalone,
            TEXT("Exact standalone native owners")))return true;
        if(!ControllerId)ControllerId=PC->GetUniqueID();
        if(!Need(PC->GetUniqueID()==ControllerId&&Authority->IsPrepared()&&Authority->GetBinding().Parts.Num()==289&&
            Authority->GetBinding().MetaHumanActor.IsSet(),TEXT("Stable controller and real prepared289/current MetaHuman binding")))return true;
        TSharedPtr<FJsonObject> S;
        if(!Need(FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Town->GetStatusJson()),S)&&S.IsValid(),TEXT("Native status JSON")))return true;
        const auto Boot=Town->GetWorldV3PersonaBootState();const FString Status=S->GetStringField(TEXT("status"));
        FString Error;
        if(Case==TEXT("failed_load"))
        {
            if(!Need(!PC->GetPawn()&&!PC->HasNativePersona()&&!Authority->GetPresentation().bSessionReady&&PC->IsMoveInputIgnored()&&
                S->GetBoolField(TEXT("owned_movement_lock"))&&S->GetNumberField(TEXT("post_possession_owned_relocks"))==0&&
                Boot!=ELivingTownWorldV3PersonaBootState::Ready,TEXT("Missing Ben asset never falls back to Aria or grants control")))return true;
            if(Stage==0)
            {
                if(G->GetPersonaRequestResult()==ELivingTownCafePersonaRequestResult::Pending)return false;
                if(!Need(G->GetPersonaRequestResult()==ELivingTownCafePersonaRequestResult::Refused&&
                    G->FindComponentByClass<ULivingTownMetaHumanVisualPreload>()&&
                    !G->FindComponentByClass<ULivingTownMetaHumanVisualPreload>()->IsReadyFor(Authority->GetBinding().MetaHumanActor.GetValue()),
                    TEXT("Actual preload failure clears deferred CLI Aria")))return true;
                Stage=1;StageTime=W->GetTimeSeconds();return false;
            }
            if(W->GetTimeSeconds()-StageTime<.5)return false;
            if(Stage==1)
            {
                Town->RequestSafeStop();
                if(!Need(G->RequestPersona(PC,ELivingTownCafeWorldPersona::Aria,Error)==ELivingTownCafePersonaRequestResult::Refused&&
                    Error==TEXT("town_persona_boot_unavailable")&&!G->SelectPersona(PC,ELivingTownCafeWorldPersona::Aria,Error),
                    TEXT("Stopped failed-load boot refuses later Aria without another preload")))return true;
                Stage=2;StageTime=W->GetTimeSeconds();return false;
            }
            if(!Need(Boot==ELivingTownWorldV3PersonaBootState::Refused&&Status==TEXT("STOPPED_SUPPORT_RETAINED")&&
                G->GetPersonaRequestResult()==ELivingTownCafePersonaRequestResult::Refused,TEXT("Stable refusal after natural callback settling")))return true;
            return Publish(S);
        }
        if(!Need(Boot!=ELivingTownWorldV3PersonaBootState::Inactive&&Boot!=ELivingTownWorldV3PersonaBootState::Refused&&
            Status!=TEXT("FAILED_SUPPORT_RETAINED"),TEXT("Valid persona intent never fails or stops town startup")))return true;
        if(Stage==0)
        {
            if(Boot==ELivingTownWorldV3PersonaBootState::Waiting)
            {
                if(!Need(PC->IsMoveInputIgnored()&&S->GetBoolField(TEXT("owned_movement_lock")),TEXT("Boot retains owned movement lock")))return true;
                if(PC->GetPawn())
                {
                    if(!Need(PersonaIs(PC,Authority,ELivingTownCafeWorldPersona::Ben),TEXT("Only qualified Ben is possessed before town ready")))return true;
                    ++BenBootSamples;
                }
                if(!CheckedImmediateRefusal)
                {
                    auto* PawnBefore=PC->GetPawn();
                    if(!Need(!G->SelectPersona(PC,ELivingTownCafeWorldPersona::Aria,Error)&&Error==TEXT("town_boot_immediate_persona_selection_unavailable")&&
                        G->RequestPersona(PC,static_cast<ELivingTownCafeWorldPersona>(255),Error)==ELivingTownCafePersonaRequestResult::Refused&&
                        PC->GetPawn()==PawnBefore&&G->GetPersonaRequestResult()==ELivingTownCafePersonaRequestResult::Pending,
                        TEXT("Immediate API refuses without cancelling required Ben or queued intent")))return true;
                    CheckedImmediateRefusal=true;
                }
                if((Case==TEXT("early_f1")||Case==TEXT("latest_ben"))&&!SentEarlyF1)
                {
                    auto* Preload=G->FindComponentByClass<ULivingTownMetaHumanVisualPreload>();
                    if(!Need(!PC->GetPawn()&&G->GetPersonaRequestResult()==ELivingTownCafePersonaRequestResult::Pending&&Preload&&
                        !Preload->IsReadyFor(Authority->GetBinding().MetaHumanActor.GetValue()),TEXT("Observe actual pending Ben preload before F1; no skipped coverage")))return true;
                    InitialPreload=Preload;PersonaKey(PC,EKeys::F1);SentEarlyF1=true;
                    if(Case==TEXT("latest_ben")){PersonaKey(PC,EKeys::F2);SentLatestF2=true;}
                    return false;
                }
                return false;
            }
            if(!Need((Case!=TEXT("early_f1")||SentEarlyF1)&&(Case!=TEXT("latest_ben")||(SentEarlyF1&&SentLatestF2)),
                TEXT("Required early input was delivered before readiness")))return true;
            if(G->GetPersonaRequestResult()==ELivingTownCafePersonaRequestResult::Pending)return false;
            const auto Expected=(Case==TEXT("cli_aria")||Case==TEXT("early_f1"))?ELivingTownCafeWorldPersona::Aria:ELivingTownCafeWorldPersona::Ben;
            if(!Need(G->GetPersonaRequestResult()==ELivingTownCafePersonaRequestResult::Selected&&PersonaIs(PC,Authority,Expected)&&
                Status==TEXT("SUBSET_CONTROLLABLE_NOT_FULL_TOWN")&&!PC->IsMoveInputIgnored()&&!S->GetBoolField(TEXT("owned_movement_lock"))&&
                S->GetNumberField(TEXT("post_possession_owned_relocks"))==1&&S->GetNumberField(TEXT("ready_frame"))>S->GetNumberField(TEXT("armed_frame")),
                TEXT("Latest intent commits only after qualified Ben boot with balanced initial relock")))return true;
            if(SentEarlyF1&&!Need(InitialPreload.IsValid()&&G->FindComponentByClass<ULivingTownMetaHumanVisualPreload>()==InitialPreload.Get(),
                TEXT("Required Ben preload component remains the same")))return true;
            StablePawn=PC->GetPawn();Stage=1;StageTime=W->GetTimeSeconds();return false;
        }
        if(!Need(Boot==ELivingTownWorldV3PersonaBootState::Ready&&Status==TEXT("SUBSET_CONTROLLABLE_NOT_FULL_TOWN")&&
            !PC->IsMoveInputIgnored()&&!S->GetBoolField(TEXT("owned_movement_lock"))&&S->GetNumberField(TEXT("post_possession_owned_relocks"))==1,
            TEXT("Ready persona changes preserve streaming and balanced lock")))return true;
        if(Stage==1||Stage==4)
        {
            const auto Expected=(Case==TEXT("cli_aria")||Case==TEXT("early_f1"))?ELivingTownCafeWorldPersona::Aria:ELivingTownCafeWorldPersona::Ben;
            if(!Need(StablePawn.IsValid()&&PC->GetPawn()==StablePawn.Get()&&PersonaIs(PC,Authority,Expected)&&
                G->GetPersonaRequestResult()==ELivingTownCafePersonaRequestResult::Selected,TEXT("Final persona/pawn/session stays stable across ordinary ticks")))return true;
            if(W->GetTimeSeconds()-StageTime<.5)return false;
            if(Case!=TEXT("after_ready")||Stage==4)return Publish(S);
            PersonaKey(PC,EKeys::F1);Stage=2;return false;
        }
        if(Stage==2)
        {
            if(!Need(G->GetPersonaRequestResult()!=ELivingTownCafePersonaRequestResult::Refused,TEXT("After-ready F1 was not refused")))return true;
            if(G->GetPersonaRequestResult()==ELivingTownCafePersonaRequestResult::Pending||!PersonaIs(PC,Authority,ELivingTownCafeWorldPersona::Aria))return false;
            if(!Need(G->GetPersonaRequestResult()==ELivingTownCafePersonaRequestResult::Selected&&!StablePawn.IsValid(),TEXT("After-ready F1 retires prior Ben only after Aria binds")))return true;
            StablePawn=PC->GetPawn();PersonaKey(PC,EKeys::F2);Stage=3;return false;
        }
        if(!Need(G->GetPersonaRequestResult()!=ELivingTownCafePersonaRequestResult::Refused,TEXT("After-ready F2 was not refused")))return true;
        if(G->GetPersonaRequestResult()==ELivingTownCafePersonaRequestResult::Pending||!PersonaIs(PC,Authority,ELivingTownCafeWorldPersona::Ben))return false;
        if(!Need(G->GetPersonaRequestResult()==ELivingTownCafePersonaRequestResult::Selected&&!StablePawn.IsValid(),TEXT("After-ready F2 restores qualified Ben and retires Aria")))return true;
        StablePawn=PC->GetPawn();Stage=4;StageTime=W->GetTimeSeconds();return false;
    }
};
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownWorldV3PersonaBootTest,"LivingTown.FullTown.WorldV3PersonaBoot",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownWorldV3PersonaBootTest::RunTest(const FString&)
{
    FString Case,Descriptor,Persona;
    const bool HasPersona=FParse::Value(FCommandLine::Get(),TEXT("CafeWorldPersona="),Persona);
    if(!FParse::Param(FCommandLine::Get(),TEXT("LivingTownWorldV3TownJourney"))||!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeWorldV3"))||
        !FParse::Value(FCommandLine::Get(),TEXT("LivingTownMetaHumanBen="),Descriptor)||Descriptor.IsEmpty()||
        !FParse::Value(FCommandLine::Get(),TEXT("LivingTownWorldV3PersonaBootCase="),Case)||
        (Case!=TEXT("cli_aria")&&Case!=TEXT("early_f1")&&Case!=TEXT("latest_ben")&&Case!=TEXT("default_ben")&&Case!=TEXT("after_ready")&&Case!=TEXT("failed_load")))
    {AddError(TEXT("Explicit current WorldV3 town/persona-boot case required"));return false;}
    const FString Expected=(Case==TEXT("cli_aria")||Case==TEXT("latest_ben")||Case==TEXT("failed_load"))?TEXT("aria"):TEXT("ben");
    if((Case==TEXT("default_ben")&&HasPersona)||(Case!=TEXT("default_ben")&&(!HasPersona||Persona!=Expected)))
    {AddError(TEXT("Case must use its actual CLI persona; default_ben must omit CafeWorldPersona"));return false;}
    int32 Count=0;PersonaBootWorld(Count);if(Count){AddError(TEXT("Fresh isolated native fixture required"));return false;}
    if(!IFileManager::Get().FileExists(*FPackageName::LongPackageNameToFilename(PersonaBootRoot,FPackageName::GetMapPackageExtension())))
    {AddError(TEXT("Actual pinned new root absent; no skipped or synthetic pass"));return false;}
    FString Error;FLivingTownMetaHumanVisualBinding Prepared;
    if(!FLivingTownMetaHumanVisualBinding::Read(Descriptor,Prepared,Error)||!Prepared.UsesWorkwear())
    {AddError(TEXT("Current source-qualified v2 workwear descriptor required: ")+Error);return false;}
    const FSoftObjectPath WorkwearPath(Prepared.OutfitMeshPath);const FString WorkwearPackage=WorkwearPath.GetLongPackageName();
    const bool HasWorkwear=IFileManager::Get().FileExists(*FPackageName::LongPackageNameToFilename(WorkwearPackage,FPackageName::GetAssetPackageExtension()));
    if((Case==TEXT("failed_load"))==HasWorkwear||(Case==TEXT("failed_load")&&WorkwearPath.ResolveObject()))
    {AddError(TEXT("Positive cases require current workwear; failed_load requires it absent and not already loaded in a disposable fixture"));return false;}
    // Only diagnostics naming the deliberately absent exact workwear are expected.
    // The observed refusal/no-authority assertions, not log matching, qualify it.
    if(Case==TEXT("failed_load"))AddExpectedError(WorkwearPackage,EAutomationExpectedErrorFlags::Contains,0);
    if(!AutomationOpenMap(PersonaBootRoot,true))return false;
    ADD_LATENT_AUTOMATION_COMMAND(FWorldV3PersonaBoot(this,Case));return true;
}
#endif
