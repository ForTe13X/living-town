#include "LivingTownCafeWorldV3Subsystem.h"
#include "LivingTownCafeWorldV3Scenario.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownMetaHumanVisualAssembly.h"
#include "LivingTownMetaHumanMealProducer.h"
#include "../../ThirdParty/CafeWorldV3Envelope.hpp"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Tests/AutomationCommon.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/StaticMesh.h"
#include "Components/CapsuleComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/StaticMeshComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformTime.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/Base64.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "InputCoreTypes.h"
#include "InputKeyEventArgs.h"
#include "UObject/SoftObjectPath.h"

namespace {
namespace W3=living_town::cafe_world_v3;
namespace Care=living_town::daily_life_use_v1;
UWorld* MealWorld(int32& Count){UWorld* W=nullptr;Count=0;if(GEngine)for(const auto& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::PIE||C.WorldType==EWorldType::Game)){W=C.World();++Count;}return W;}
bool Inspect(ULivingTownCafeWorldV3Subsystem* A,W3::CareEnvelope& E,Care::Journal& J){
    FString Text,Error,Encoded;TSharedPtr<FJsonObject> O;TArray<uint8> Data;
    if(!A->EncodeJournal(Text,Error)||!LivingTownCafeJournal::HasUniqueObjectKeys(Text)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),O)||!O||!O->TryGetStringField(TEXT("payload_base64"),Encoded)||!FBase64::Decode(Encoded,Data)||Data.IsEmpty())return false;
    const auto P=W3::decode_care_envelope_document(std::string(reinterpret_cast<const char*>(Data.GetData()),size_t(Data.Num())));if(!P)return false;const auto C=W3::decode_care_document(P->care_payload);if(!C)return false;E=*P;J=*C;return true;
}
class FMetaHumanMealJourney final:public IAutomationLatentCommand {
    FAutomationTestBase* Test;FLivingTownMetaHumanMealRecipeV2 Recipe;
    const double Deadline=FPlatformTime::Seconds()+180;
    uint32 WorldId=0;int32 Stage=0;uint64 PressFrame=0;FKey Held;
    bool Done=false,Monitoring=false,SawBite=false,SawBitten=false,SawTail=false;
    double BiteWorld=-1,FirstBenefit=-1;FString Failure;
    FDelegateHandle Observer;
    TWeakObjectPtr<ALivingTownCafeWorldV3Controller> PC;
    TWeakObjectPtr<ALivingTownCafeCharacter> Pawn;
    TWeakObjectPtr<ULivingTownCafeWorldV3Subsystem> Authority;
    TWeakObjectPtr<ULivingTownMetaHumanMealProducer> Source;
    TWeakObjectPtr<ULivingTownMetaHumanVisualAssembly> Assembly;
    TWeakObjectPtr<USkeletalMeshComponent> Body,Face,Outfit;
    TWeakObjectPtr<UAnimSingleNodeInstance> Player;
    TWeakObjectPtr<UAnimInstance> FaceMain,FacePost,BodyPost;
    TWeakObjectPtr<UStaticMeshComponent> Food;
    FLivingTownCafeWorldView Opening,MealOpening;
    UStaticMesh* Whole=nullptr;UStaticMesh* Bitten=nullptr;
    bool Need(bool OK,const TCHAR* Why){if(!OK){Test->AddError(Why);Done=true;}return OK;}
    void Release(){if(PC.IsValid()&&Held.IsValid())PC->InputKey(FInputKeyEventArgs::CreateSimulated(Held,IE_Released,0.f));Held=FKey();}
    void Press(FKey Key){Release();Held=Key;PressFrame=GFrameCounter;PC->InputKey(FInputKeyEventArgs::CreateSimulated(Key,IE_Pressed,1.f));}
    bool Released(){if(GFrameCounter<PressFrame+2)return false;Release();return true;}
    void Sample(UWorld* W,ELevelTick,float){
        if(!Monitoring||!W||W->GetUniqueID()!=WorldId||!Source.IsValid()||!Authority.IsValid())return;
        FLivingTownMealPhysicalObservation O;FString Error;if(!Source->ReadLatest(O,Error))return;
        const auto& V=Authority->GetPresentation();
        if(!O.bBiteObserved&&(V.ProgressTicks>0||V.Fun>MealOpening.Fun||V.Hunger>MealOpening.Hunger))Failure=TEXT("Positive meal effect observed before the first actual bite");
        if(O.bBiteObserved&&!SawBite){SawBite=true;BiteWorld=O.WorldSeconds;}
        if(V.ProgressTicks>0&&FirstBenefit<0){FirstBenefit=O.WorldSeconds;if(!SawBite||FirstBenefit-BiteWorld+Recipe.TimeError<Recipe.FirstProgressDelay)Failure=TEXT("First progress preceded measured bite plus certified real-time delay");}
        if(!Food.IsValid()&&Source->IsPhysicalUseActive()){
            TArray<UStaticMeshComponent*> Parts;Pawn->GetComponents(Parts);int32 Count=0;for(auto* C:Parts)if(C->GetStaticMesh()==Whole||C->GetStaticMesh()==Bitten){Food=C;++Count;}if(Count!=1)Failure=TEXT("Exactly one actual owned bread component required");
        }
        if(Food.IsValid()){
            if(O.ClipSeconds<=Recipe.BiteEnd&&Food->GetStaticMesh()!=Whole)Failure=TEXT("Bitten geometry appeared before the actual bite window ended");
            if(O.ClipSeconds>Recipe.BiteEnd&&O.bBiteObserved){if(Food->GetStaticMesh()!=Bitten)Failure=TEXT("Actual bite did not select the qualified bitten mesh");else SawBitten=true;}
        }
        if(!V.bMealActive&&FirstBenefit>=0&&Source->IsPhysicalUseActive())SawTail=true;
    }
public:
    FMetaHumanMealJourney(FAutomationTestBase* T):Test(T){}
    virtual ~FMetaHumanMealJourney(){FWorldDelegates::OnWorldPostActorTick.Remove(Observer);Release();}
    virtual bool Update()override{
        if(Done)return true;if(!Need(FPlatformTime::Seconds()<Deadline,TEXT("Finite native eating journey deadline exceeded"))||!Need(Failure.IsEmpty(),*Failure))return true;
        int32 Count=0;auto* W=MealWorld(Count);if(!Need(Count<=1&&(!WorldId||(W&&W->GetUniqueID()==WorldId)),TEXT("One unchanged runtime world required")))return true;if(!W||!W->HasBegunPlay())return false;
        if(!WorldId)WorldId=W->GetUniqueID();auto* A=W->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();auto* C=Cast<ALivingTownCafeWorldV3Controller>(W->GetFirstPlayerController());
        if(!A||!A->IsPrepared()||!C||!C->GetPawn())return false;
        if(Stage==0){
            auto* P=Cast<ALivingTownCafeCharacter>(C->GetPawn());if(!P||!P->HasMetaHumanVisual()||!P->GetCharacterMovement()->IsMovingOnGround())return false;
            if(!Need(W->GetNetMode()==NM_Standalone&&!W->IsPaused()&&C->HasNativePersona()&&C->GetNativePersona()==ELivingTownCafeWorldPersona::Ben&&A->GetBinding().MetaHumanActor.IsSet()&&A->GetBinding().MetaHumanActor->UsesWorkwear(),TEXT("Qualified naturally selected v2 Ben required")))return true;
            auto* S=P->FindComponentByClass<ULivingTownMetaHumanMealProducer>();auto* V=P->FindComponentByClass<ULivingTownMetaHumanVisualAssembly>();
            if(!S||!A->GetPresentation().bMealAvailable)return false; // Ordinary owner async preload, no test-side asset load.
            if(!Need(V&&V->IsConfigured()&&!A->GetPresentation().bMealActive,TEXT("Actual root-qualified preloaded producer required")))return true;
            Recipe=S->GetRecipe();
            PC=C;Pawn=P;Authority=A;Source=S;Assembly=V;Body=V->GetBody();Face=V->GetFace();Player=Body->GetSingleNodeInstance();FaceMain=Face->GetAnimInstance();FacePost=Face->GetPostProcessInstance();BodyPost=Body->GetPostProcessInstance();
            TArray<USkeletalMeshComponent*> Parts;V->GetVisualActor()->GetComponents(Parts);for(auto* Part:Parts)if(Part!=Body.Get()&&Part!=Face.Get())Outfit=Part;
            Whole=Cast<UStaticMesh>(FSoftObjectPath(Recipe.FindRole(TEXT("bread"))->Asset).ResolveObject());Bitten=Cast<UStaticMesh>(FSoftObjectPath(Recipe.FindRole(TEXT("bread_bitten"))->Asset).ResolveObject());
            if(!Need(Parts.Num()==3&&Outfit.IsValid()&&Whole&&Bitten&&Outfit->LeaderPoseComponent.Get()==Body.Get()&&!IFileManager::Get().FileExists(*(FPaths::ProjectSavedDir()/TEXT("CafeWorldV3/CafeWorldRentCareV5.slot.json"))),TEXT("Original assembly and fresh paired native slot required")))return true;
            Opening=A->GetPresentation();if(!Need(Opening.Operator==TEXT("aria")&&Opening.Stock==2,TEXT("Fresh authored two-ration Aria-operated meal fixture required")))return true;
            Observer=FWorldDelegates::OnWorldPostActorTick.AddRaw(this,&FMetaHumanMealJourney::Sample);Stage=1;
        }
        if(!Need(C==PC.Get()&&C->GetPawn()==Pawn.Get()&&Assembly.IsValid()&&Body.IsValid()&&Face.IsValid()&&Outfit.IsValid()&&Player.IsValid()&&Assembly->GetBody()==Body.Get()&&Assembly->GetFace()==Face.Get()&&Body->GetSingleNodeInstance()==Player.Get()&&Face->GetAnimInstance()==FaceMain.Get()&&Face->GetPostProcessInstance()==FacePost.Get()&&Body->GetPostProcessInstance()==BodyPost.Get()&&Outfit->LeaderPoseComponent.Get()==Body.Get(),TEXT("No player, Face ABP/post-process or Outfit leader replacement allowed")))return true;
        if(Stage==1){
            const FVector Feet=Pawn->GetActorLocation()-FVector(0,0,Pawn->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());const FVector To=Recipe.StationFeetCm-Feet;
            if(To.Size2D()>Recipe.StationRadiusCm*.25){PC->SetControlRotation(FRotator(0,To.Rotation().Yaw,0));if(Held!=EKeys::W)Press(EKeys::W);return false;}
            Release();PC->SetControlRotation(FRotator(0,(Recipe.CounterPointCm-Pawn->GetActorLocation()).Rotation().Yaw,0));Press(EKeys::W);Stage=2;return false;
        }
        if(Stage==2){
            if(Held==EKeys::W){const FVector To=(Recipe.CounterPointCm-Pawn->GetActorLocation()).GetSafeNormal2D();if(FVector::DotProduct(Pawn->GetActorForwardVector().GetSafeNormal2D(),To)<Recipe.StationFacingDot)return false;Release();}
            if(Pawn->GetVelocity().Size2D()>2)return false;if(!Need(A->GetPresentation().bReachable,TEXT("Actual walked entry must satisfy original floor/hand/eye counter reach")))return true;Stage=3;
        }
        W3::CareEnvelope E;Care::Journal J;
        if(Stage==3){
            if(!Need(Inspect(A,E,J)&&J.requests.empty(),TEXT("Fresh source-bound public journal required before first E")))return true;double Fraction=0;FMemory::Memcpy(&Fraction,&E.clock.fraction_bits,sizeof(Fraction));
            // A fixed 20 ms window can be missed forever by valid 30 Hz frames.
            // Schedule across the observed next two natural frames, not by
            // changing the authority clock, delta or animation playback.
            if(Fraction+2.0*double(W->GetDeltaSeconds())<1)return false;MealOpening=A->GetPresentation();Monitoring=true;Press(EKeys::E);Stage=4;return false;
        }
        if(Stage==4){
            if(!Released())return false;if(!Need(Inspect(A,E,J)&&J.active&&J.active->elapsed==0&&J.requests.size()==1,TEXT("Near-boundary E must reserve a real zero-progress use")))return true;
            bool Wait=false;for(const auto& H:J.history)Wait|=H.op==Care::Op::WaitBeforeFirstProgress;if(!Wait)return false;
            if(!Need(J.needs.hunger<=MealOpening.Hunger&&J.needs.fun==MealOpening.Fun&&A->GetPresentation().BenCoins==Opening.BenCoins-2&&A->GetPresentation().AriaCoins==Opening.AriaCoins+2&&A->GetPresentation().Stock==1,TEXT("Preparation decays normally, gives no benefit and settles exactly once")))return true;
            Press(EKeys::F5);Stage=5;return false;
        }
        if(Stage==5){if(!Released())return false;if(!IFileManager::Get().FileExists(*(FPaths::ProjectSavedDir()/TEXT("CafeWorldV3/CafeWorldRentCareV5.slot.json"))))return false;Press(EKeys::X);Stage=6;return false;}
        if(Stage==6){
            if(!Released())return false;if(!Need(Inspect(A,E,J)&&!J.active&&J.requests.size()==1&&J.requests.back().end==Care::End::Cancelled&&J.requests.back().progressed_ticks==0&&!Source->IsPhysicalUseActive()&&!Food.IsValid(),TEXT("Real X cancels active preparation and destroys only owned food/action")))return true;
            Monitoring=false;Press(EKeys::F9);Stage=7;return false;
        }
        if(Stage==7){
            if(!Released())return false;if(!Need(Inspect(A,E,J)&&!J.active&&J.requests.size()==1&&J.requests.back().end==Care::End::AfterLoad&&J.requests.back().progressed_ticks==0&&A->GetPresentation().BenCoins==Opening.BenCoins-2&&A->GetPresentation().Stock==1&&!Source->IsPhysicalUseActive()&&!Food.IsValid(),TEXT("Real F9 retains the paid save, interrupts loaded use and never recreates bread or grants pre-bite progress")))return true;
            MealOpening=A->GetPresentation();SawBite=SawBitten=SawTail=false;BiteWorld=FirstBenefit=-1;Monitoring=true;Press(EKeys::E);Stage=8;return false;
        }
        if(Stage==8){
            if(!Released())return false;if(A->GetPresentation().bMealActive)return false;
            if(!Need(Inspect(A,E,J)&&J.requests.size()==2&&J.requests.back().end==Care::End::Completed&&J.requests.back().progressed_ticks==18,TEXT("Second actual E must earn exactly eighteen ordinary increments")))return true;
            int32 Advances=0;for(const auto& H:J.history)if(H.op==Care::Op::Advance&&H.contact&&H.contact->grant_id==J.requests.back().grant.grant_id)++Advances;
            if(!Need(Advances==18&&SawBite&&SawBitten&&FirstBenefit>=0&&J.needs.fun==MealOpening.Fun+300&&A->GetPresentation().BenCoins==Opening.BenCoins-4&&A->GetPresentation().AriaCoins==Opening.AriaCoins+4&&A->GetPresentation().Stock==0,TEXT("One paid second meal, real bite/mesh change and exact authored +3 fun required")))return true;Stage=9;
        }
        if(Stage==9){
            if(Source->IsPhysicalUseActive())return false;
            if(!Need(Inspect(A,E,J)&&!J.active&&J.requests.back().progressed_ticks==18&&SawTail&&!Food.IsValid()&&!Assembly->IsActionClipActive()&&J.needs.fun==MealOpening.Fun+300,TEXT("Bounded visual tail gives no extra increment and cleans only owned food/action")))return true;
            auto Proof=MakeShared<FJsonObject>();Proof->SetStringField(TEXT("status"),TEXT("PASS_NATIVE_INPUT_STATE_ONLY_NO_ART_ADMISSION"));Proof->SetStringField(TEXT("recipe_sha256"),Recipe.RecipeSha256);Proof->SetStringField(TEXT("certificate_sha256"),Recipe.CertificateSha256);Proof->SetStringField(TEXT("binding_sha256"),Recipe.BindingSha256);Proof->SetNumberField(TEXT("requests"),2);Proof->SetNumberField(TEXT("completed_ordinary_ticks"),18);Proof->SetNumberField(TEXT("bite_observed_world_seconds"),BiteWorld);Proof->SetNumberField(TEXT("first_benefit_observed_world_seconds"),FirstBenefit);Proof->SetNumberField(TEXT("certified_first_progress_delay_seconds"),Recipe.FirstProgressDelay);Proof->SetBoolField(TEXT("qualified_bitten_geometry_observed"),SawBitten);Proof->SetBoolField(TEXT("no_grant_visual_tail_observed"),SawTail);Proof->SetBoolField(TEXT("same_original_body_player_and_face_ownership"),true);Proof->SetBoolField(TEXT("physical_resume_after_load"),false);Proof->SetBoolField(TEXT("pixels_or_hardware_keypress_claimed"),false);
            FString Text;FJsonSerializer::Serialize(Proof,TJsonWriterFactory<>::Create(&Text));const FString Path=FPaths::ProjectSavedDir()/TEXT("CafeWorldV3/MetaHumanMealJourney.json");if(!Need(!IFileManager::Get().FileExists(*Path)&&FFileHelper::SaveStringToFile(Text,*Path,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM),TEXT("Fresh native journey observation receipt required")))return true;
            Test->AddInfo(TEXT("Actual real-input meal journey: near-boundary zero-benefit wait, active F5/X cancel/F9 no-resume, second E bite/chew/18 increments/qualified bitten mesh/no-grant tail. No pixels or hardware input claimed."));Done=true;return true;
        }
        return false;
    }
};
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownMetaHumanMealJourneyTest,"LivingTown.WorldV3.MetaHumanMealJourneyInput",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownMetaHumanMealJourneyTest::RunTest(const FString&){
    FString Descriptor,Persona;if(!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeWorldV3"))||!FParse::Param(FCommandLine::Get(),TEXT("LivingTownMetaHumanMealJourney"))||!FParse::Value(FCommandLine::Get(),TEXT("LivingTownMetaHumanBen="),Descriptor)||Descriptor.IsEmpty()||!FParse::Value(FCommandLine::Get(),TEXT("CafeWorldPersona="),Persona)||Persona!=TEXT("ben")){AddError(TEXT("Explicit qualified WorldV3/v2 Ben/meal journey opt-in required"));return false;}
    int32 Count=0;MealWorld(Count);if(Count){AddError(TEXT("Fresh isolated native PIE world required"));return false;}
    if(!IFileManager::Get().FileExists(*(FPaths::ProjectContentDir()/TEXT("LivingTown/MetaHumanMealContactV2.json")))){AddError(TEXT("Actual root-reviewed v2 recipe and proof files must be staged; missing inputs cannot skip to success"));return false;}
    if(!AutomationOpenMap(TEXT("/Engine/Maps/Entry"),true))return false;ADD_LATENT_AUTOMATION_COMMAND(FMetaHumanMealJourney(this));return true;
}
#endif
