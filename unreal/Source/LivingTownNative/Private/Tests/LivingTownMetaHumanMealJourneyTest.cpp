#include "LivingTownCafeWorldV3Subsystem.h"
#include "LivingTownCafeWorldV3Scenario.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownMetaHumanVisualAssembly.h"
#include "LivingTownMetaHumanMealProducer.h"
#include "../../ThirdParty/CafeWorldV3Envelope.hpp"
#if WITH_DEV_AUTOMATION_TESTS
#include "LivingTownFullTownDriver.h"
#include "LivingTownFullTownStreamingSubsystem.h"
#include "LivingTownCafeProjectionSubsystem.h"
#include "LivingTownCafePropertyV2Subsystem.h"
#include "LivingTownLeaseSubsystem.h"
#include "LivingTownCafeVenue.h"
#include "Misc/AutomationTest.h"
#include "Tests/AutomationCommon.h"
#include "Engine/Engine.h"
#include "Engine/GameInstance.h"
#include "Engine/World.h"
#include "Engine/StaticMesh.h"
#include "Engine/SkeletalMesh.h"
#include "EngineUtils.h"
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
#include "Misc/PackageName.h"
#include "Misc/FileHelper.h"
#include "Misc/Base64.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "InputCoreTypes.h"
#include "InputKeyEventArgs.h"
#include "UObject/SoftObjectPath.h"
#include "UObject/Package.h"

namespace {
namespace W3=living_town::cafe_world_v3;
namespace Care=living_town::daily_life_use_v1;
constexpr TCHAR TownMealRoot[]=TEXT("/Game/LivingTown_UEPilot/FullTownWorldV3_289_v001/L_FullTownWorldV3_289_v001");
constexpr TCHAR TownMealManifest[]=TEXT("/Game/LivingTown_UEPilot/FullTownWorldV3_289_v001/DA_FullTownWorldV3_289_v001.DA_FullTownWorldV3_289_v001");
constexpr TCHAR TownMealBindingSha[]=TEXT("38171606986ba5086102aeba31927fac698558eebed861dd0f4d8eaf713fad6e");
constexpr TCHAR TownMealRouteSha[]=TEXT("38d98ee0c968647be6a1a89eac2abfe7c4b8a65b8732248f62fd3e7f54113846");
bool ReadTownMealRoute(TArray<FVector>& Route){
    const FString Path=FPaths::ProjectContentDir()/TEXT("LivingTown/CafeJourneyRoute.json");TArray<uint8> Bytes;FString Hash,Text,Format,Version,Status,Binding;TSharedPtr<FJsonObject> Object;
    const TArray<TSharedPtr<FJsonValue>>* Points=nullptr;
    if(!FFileHelper::LoadFileToArray(Bytes,*Path)||!LivingTownCafeJournal::Sha256(Bytes,Hash)||Hash!=TownMealRouteSha||!FFileHelper::LoadFileToString(Text,*Path)||
        !LivingTownCafeJournal::HasUniqueObjectKeys(Text)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),Object)||!Object||
        !Object->TryGetStringField(TEXT("format"),Format)||Format!=TEXT("LivingTown.CafeJourneyRoute")||!Object->TryGetStringField(TEXT("version"),Version)||Version!=TEXT("1")||
        !Object->TryGetStringField(TEXT("status"),Status)||Status!=TEXT("UE_ROUTE_QUALIFIED")||!Object->TryGetStringField(TEXT("physical_binding_sha256"),Binding)||Binding!=TownMealBindingSha||
        !Object->TryGetArrayField(TEXT("route_feet_cm"),Points)||Points->Num()!=3)return false;
    for(const auto& Point:*Points){
        if(!Point||Point->Type!=EJson::Array||Point->AsArray().Num()!=3)return false;
        const auto& Values=Point->AsArray();double XYZ[3];
        for(int32 I=0;I<3;++I)if(!Values[I]||Values[I]->Type!=EJson::Number||!FMath::IsFinite(XYZ[I]=Values[I]->AsNumber()))return false;
        Route.Add(FVector(XYZ[0],XYZ[1],XYZ[2]));
    }
    return true;
}
UWorld* MealWorld(int32& Count){UWorld* W=nullptr;Count=0;if(GEngine)for(const auto& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::PIE||C.WorldType==EWorldType::Game)){W=C.World();++Count;}return W;}
bool Inspect(ULivingTownCafeWorldV3Subsystem* A,W3::CareEnvelope& E,Care::Journal& J){
    FString Text,Error,Encoded;TSharedPtr<FJsonObject> O;TArray<uint8> Data;
    if(!A->EncodeJournal(Text,Error)||!LivingTownCafeJournal::HasUniqueObjectKeys(Text)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),O)||!O||!O->TryGetStringField(TEXT("payload_base64"),Encoded)||!FBase64::Decode(Encoded,Data)||Data.IsEmpty())return false;
    const auto P=W3::decode_care_envelope_document(std::string(reinterpret_cast<const char*>(Data.GetData()),size_t(Data.Num())));if(!P)return false;const auto C=W3::decode_care_document(P->care_payload);if(!C)return false;E=*P;J=*C;return true;
}
class FMetaHumanMealJourney final:public IAutomationLatentCommand {
    FAutomationTestBase* Test;FLivingTownMetaHumanMealRecipeV2 Recipe;
    const bool bTownFixture;
    const double Deadline;
    TArray<FVector> TownRoute,ReachedTownFeet;
    int32 TownWaypoint=1,TownCensusSamples=0,TownRouteSamples=0;
    bool bTownWaypointSettling=false,bTownEpochObserved=false;
    double TownEpoch=0,LastTownCensus=-1,LastRouteTime=-1,TownLegStarted=-1,TownWalkCm=0;
    FVector LastRouteFeet=FVector::ZeroVector;
    TSharedPtr<FJsonObject> LatestTownStatus;
    TWeakObjectPtr<AActor> TownVisual;
    uint32 WorldId=0;int32 Stage=0;uint64 PressFrame=0;FKey Held;
    bool Done=false,Monitoring=false,SawBite=false,SawBitten=false,SawTail=false,LoggedInitialStage=false;
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
    FString Diagnostic()const{
        int32 Count=0;auto* W=MealWorld(Count);const auto* A=W?W->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;
        const auto* C=W?Cast<ALivingTownCafeWorldV3Controller>(W->GetFirstPlayerController()):nullptr;const APawn* P=C?C->GetPawn().Get():nullptr;
        const auto* S=P?P->FindComponentByClass<ULivingTownMetaHumanMealProducer>():nullptr;const auto* Ben=Cast<ALivingTownCafeCharacter>(P);
        return FString::Printf(TEXT("stage=%d worlds=%d pawn=%s position=%s meta_visual=%d source=%s source_active=%d source_failure=%s prepared=%d session=%d available=%d reachable=%d"),
            Stage,Count,*GetNameSafe(P),P?*P->GetActorLocation().ToString():TEXT("none"),Ben&&Ben->HasMetaHumanVisual(),*GetNameSafe(S),S&&S->IsPhysicalUseActive(),S?*S->GetFailure():TEXT("none"),A&&A->IsPrepared(),A&&A->GetPresentation().bSessionReady,A&&A->GetPresentation().bMealAvailable,A&&A->GetPresentation().bReachable);
    }
    bool Need(bool OK,const TCHAR* Why){if(!OK){Release();Test->AddError(FString(Why)+TEXT(" | ")+Diagnostic());Done=true;}return OK;}
    void Transition(int32 Next){if(Stage!=Next){Stage=Next;Test->AddInfo(TEXT("MealJourney transition ")+Diagnostic());}}
    void Release(){if(PC.IsValid()&&Held.IsValid())PC->InputKey(FInputKeyEventArgs::CreateSimulated(Held,IE_Released,0.f));Held=FKey();}
    void Press(FKey Key){Release();Held=Key;PressFrame=GFrameCounter;PC->InputKey(FInputKeyEventArgs::CreateSimulated(Key,IE_Pressed,1.f));}
    bool Released(){if(GFrameCounter<PressFrame+2)return false;Release();return true;}
    bool TownCensus(UWorld* W,const FLivingTownCafeBinding& Binding){
        int32 Venues=0,Drivers=0;TSet<FString> Roles;
        for(TActorIterator<AActor> It(W);It;++It){
            if(auto* Venue=Cast<ALivingTownCafeVenue>(*It)){
                ++Venues;TArray<UStaticMeshComponent*> Parts;Venue->GetComponents(Parts);
                if(!Need(Venue->IsQualified()&&Parts.Num()==289,TEXT("One qualified original289 cafe venue required")))return false;
                TSet<FString> ActualParts;
                for(auto* Part:Parts){
                    if(!Need(Part->IsRegistered()&&Part->GetStaticMesh()&&Part->ComponentTags.Num()==1,TEXT("Actual registered tagged cafe source parts required")))return false;
                    const FString Id=Part->ComponentTags[0].ToString();
                    const auto* Expected=Binding.Parts.FindByPredicate([&Id](const FLivingTownCafePartBinding& Row){return Row.Id==Id;});
                    if(!Need(Expected&&!ActualParts.Contains(Id)&&Part->GetStaticMesh()->GetPathName()==Expected->AssetPath,TEXT("Original289 unique source identities retained")))return false;
                    ActualParts.Add(Id);
                }
            }
            if(auto* Driver=Cast<ALivingTownFullTownDriver>(*It)){
                ++Drivers;if(!Need(Driver->bEnableIntegrationSubset&&Driver->Manifest.ToSoftObjectPath().ToString()==TownMealManifest,TEXT("Sole driver still selects the actual new town manifest")))return false;
            }
            TArray<UStaticMeshComponent*> Parts;It->GetComponents(Parts);
            for(auto* Part:Parts)for(const FName Tag:Part->ComponentTags)if(Tag.ToString().StartsWith(TEXT("LT_FTW_ROLE="))){
                const FString Id=Tag.ToString().Mid(12);
                if(!Need(Part->IsRegistered()&&!Roles.Contains(Id),TEXT("Streamed source roles remain registered and unique")))return false;
                Roles.Add(Id);
            }
        }
        if(!Need(Venues==1&&Drivers==1&&Roles.Num()==971,TEXT("Actual one driver,971 streamed roles and289 external cafe parts required")))return false;
        ++TownCensusSamples;LastTownCensus=W->GetTimeSeconds();return true;
    }
    bool TownReady(UWorld* W,ULivingTownCafeWorldV3Subsystem* A,ALivingTownCafeWorldV3Controller* C){
        auto* Town=W->GetSubsystem<ULivingTownFullTownStreamingSubsystem>();
        if(!Need(UWorld::RemovePIEPrefix(W->GetOutermost()->GetName())==TownMealRoot&&Town&&A&&W->GetAuthGameMode()&&W->GetAuthGameMode()->GetClass()==ALivingTownCafeWorldV3GameMode::StaticClass(),TEXT("Exact saved WorldV3 town root and native owners required")))return false;
        TSharedPtr<FJsonObject> S;FString Status,Profile,Backend;bool Accepted=false,Locked=true;double Streamed=0,External=0,Total=0,Epoch=0,Relocks=0,ReadyFrame=0,ArmedFrame=0;
        if(!Need(FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Town->GetStatusJson()),S)&&S&&S->TryGetStringField(TEXT("status"),Status)&&
            S->TryGetStringField(TEXT("profile_id"),Profile)&&S->TryGetStringField(TEXT("cafe_backend"),Backend)&&S->TryGetBoolField(TEXT("manifest_accepted"),Accepted)&&
            S->TryGetBoolField(TEXT("owned_movement_lock"),Locked)&&S->TryGetNumberField(TEXT("declared_streamed_role_count"),Streamed)&&
            S->TryGetNumberField(TEXT("external_cafe_part_count"),External)&&S->TryGetNumberField(TEXT("declared_total_role_count"),Total)&&S->TryGetNumberField(TEXT("epoch"),Epoch)&&
            S->TryGetNumberField(TEXT("post_possession_owned_relocks"),Relocks)&&S->TryGetNumberField(TEXT("ready_frame"),ReadyFrame)&&S->TryGetNumberField(TEXT("armed_frame"),ArmedFrame),TEXT("Typed actual town status required")))return false;
        if(!Need(Status!=TEXT("FAILED_SUPPORT_RETAINED")&&Status!=TEXT("STOPPED_SUPPORT_RETAINED"),TEXT("Town cannot fail or terminally stop during meal fixture")))return false;
        if(Status!=TEXT("SUBSET_CONTROLLABLE_NOT_FULL_TOWN")){
            if(!Need(Stage==0&&!bTownEpochObserved,TEXT("Ready town must stay controllable throughout the journey")))return false;
            return false; // Initial async preload owns readiness; never test-side unlock or preload.
        }
        if(!Need(Accepted&&!Locked&&Relocks==1&&ReadyFrame>ArmedFrame&&Profile==TEXT("B749_CafeWorldV3_289_v001")&&Backend==TEXT("WorldV3Qualified289")&&Streamed==971&&External==289&&Total==1260&&
            A->IsPrepared()&&A->GetPresentation().bSessionReady&&C&&C->GetPawn()&&C->GetViewTarget()==C->GetPawn().Get()&&C->GetPawn()->GetController()==C&&!C->IsMoveInputIgnored()&&
            C->HasNativePersona()&&C->GetNativePersona()==ELivingTownCafeWorldPersona::Ben&&
            W->GetNetMode()==NM_Standalone&&!W->IsPaused(),TEXT("Actual new town remains ready with sole current controllable player")))return false;
        const auto* Legacy=W->GetSubsystem<ULivingTownCafeProjectionSubsystem>();
        if(!Need((!Legacy||(!Legacy->IsReady()&&!Legacy->IsScenePrepared()))&&!W->GetSubsystem<ULivingTownCafePropertyV2Subsystem>()&&W->GetGameInstance()&&
            !W->GetGameInstance()->GetSubsystem<ULivingTownLeaseSubsystem>(),TEXT("No competing legacy or property authority in the town")))return false;
        const auto& Binding=A->GetBinding();
        if(!Need(Binding.Parts.Num()==289&&Binding.BindingFileSha256==TownMealBindingSha&&Binding.MetaHumanActor.IsSet()&&Binding.MetaHumanActor->UsesWorkwear()&&(!bTownEpochObserved||Epoch==TownEpoch),TEXT("Original289/current workwear binding and one unchanged town epoch required")))return false;
        if(!bTownEpochObserved){TownEpoch=Epoch;bTownEpochObserved=true;}
        LatestTownStatus=S;
        if(LastTownCensus<0||W->GetTimeSeconds()-LastTownCensus>=.5)return TownCensus(W,Binding);
        return true;
    }
    bool WalkTownRoute(UWorld* W){
        auto* Movement=Pawn->GetCharacterMovement();const FVector Feet=Pawn->GetActorLocation()-FVector(0,0,Pawn->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());
        if(!Need(Movement->IsMovingOnGround()&&Movement->CurrentFloor.IsWalkableFloor(),TEXT("Current capsule stays naturally grounded on the indoor source route")))return false;
        const double Now=W->GetTimeSeconds();
        if(TownLegStarted<0)TownLegStarted=Now;
        if(!Need(Now-TownLegStarted<30,TEXT("Finite natural thirty-second indoor waypoint deadline exceeded")))return false;
        if(LastRouteTime>=0&&Now>LastRouteTime){
            const double Distance=FVector::Dist2D(Feet,LastRouteFeet);
            if(!Need(Distance<=Movement->GetMaxSpeed()*(Now-LastRouteTime)+3,TEXT("Observed indoor displacement cannot substitute position or time")))return false;
            TownWalkCm+=Distance;++TownRouteSamples;
        }
        LastRouteFeet=Feet;LastRouteTime=Now;
        if(!Need(TownRoute.IsValidIndex(TownWaypoint),TEXT("Next frozen indoor waypoint exists")))return false;
        const FVector To=TownRoute[TownWaypoint]-Feet;
        if(!bTownWaypointSettling){
            if(To.Size2D()>Recipe.StationRadiusCm*.25){PC->SetControlRotation(FRotator(0,To.Rotation().Yaw,0));if(Held!=EKeys::W)Press(EKeys::W);return false;}
            if(!Need(FMath::Abs(To.Z)<=4,TEXT("Reached source waypoint retains its qualified floor height")))return false;
            Release();ReachedTownFeet.Add(Feet);bTownWaypointSettling=true;
        }
        if(Pawn->GetVelocity().Size2D()>2)return false;
        ++TownWaypoint;bTownWaypointSettling=false;TownLegStarted=Now;
        if(TownWaypoint<TownRoute.Num())return false;
        return Need(ReachedTownFeet.Num()==3&&TownRouteSamples>=12&&TownWalkCm>=480,TEXT("Native held input reached all three source waypoints before eating"));
    }
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
    FMetaHumanMealJourney(FAutomationTestBase* T,bool bTown,TArray<FVector> Route):Test(T),bTownFixture(bTown),Deadline(FPlatformTime::Seconds()+(bTown?420:180)),TownRoute(MoveTemp(Route)){}
    virtual ~FMetaHumanMealJourney(){FWorldDelegates::OnWorldPostActorTick.Remove(Observer);Release();}
    virtual bool Update()override{
        if(!LoggedInitialStage){LoggedInitialStage=true;Test->AddInfo(TEXT("MealJourney initial ")+Diagnostic());}
        if(Done)return true;if(!Need(FPlatformTime::Seconds()<Deadline,TEXT("Finite native eating journey deadline exceeded"))||!Need(Failure.IsEmpty(),*Failure))return true;
        int32 Count=0;auto* W=MealWorld(Count);if(!Need(Count<=1&&(!WorldId||(W&&W->GetUniqueID()==WorldId)),TEXT("One unchanged runtime world required")))return true;if(!W||!W->HasBegunPlay())return false;
        if(!WorldId)WorldId=W->GetUniqueID();auto* A=W->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();auto* C=Cast<ALivingTownCafeWorldV3Controller>(W->GetFirstPlayerController());
        if(bTownFixture&&!TownReady(W,A,C))return Done;
        if(!A||!A->IsPrepared()||!C||!C->GetPawn())return false;
        if(Stage==0){
            auto* P=Cast<ALivingTownCafeCharacter>(C->GetPawn());if(!P||!P->HasMetaHumanVisual()||!P->GetCharacterMovement()->IsMovingOnGround())return false;
            if(!Need(W->GetNetMode()==NM_Standalone&&!W->IsPaused()&&C->HasNativePersona()&&C->GetNativePersona()==ELivingTownCafeWorldPersona::Ben&&A->GetBinding().MetaHumanActor.IsSet()&&A->GetBinding().MetaHumanActor->UsesWorkwear(),TEXT("Qualified naturally selected v2 Ben required")))return true;
            auto* S=P->FindComponentByClass<ULivingTownMetaHumanMealProducer>();auto* V=P->FindComponentByClass<ULivingTownMetaHumanVisualAssembly>();
            if(!S||!A->GetPresentation().bMealAvailable)return false; // Ordinary owner async preload, no test-side asset load.
            if(!Need(V&&V->IsConfigured()&&!A->GetPresentation().bMealActive,TEXT("Actual root-qualified preloaded producer required")))return true;
            Recipe=S->GetRecipe();
            if(bTownFixture){
                const FVector Feet=P->GetActorLocation()-FVector(0,0,P->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());
                if(!Need(TownRoute.Num()==3&&TownRoute[0].Equals(A->GetBinding().SpawnFeetCm,.1)&&Feet.Equals(TownRoute[0],3)&&TownRoute.Last().Equals(Recipe.StationFeetCm,.1),TEXT("Frozen source route must start at natural spawn and end at the original station")))return true;
                ReachedTownFeet.Add(Feet);LastRouteFeet=Feet;LastRouteTime=W->GetTimeSeconds();
            }
            PC=C;Pawn=P;Authority=A;Source=S;Assembly=V;Body=V->GetBody();Face=V->GetFace();Player=Body->GetSingleNodeInstance();FaceMain=Face->GetAnimInstance();FacePost=Face->GetPostProcessInstance();BodyPost=Body->GetPostProcessInstance();
            TArray<USkeletalMeshComponent*> Parts;V->GetVisualActor()->GetComponents(Parts);for(auto* Part:Parts)if(Part!=Body.Get()&&Part!=Face.Get())Outfit=Part;
            if(bTownFixture)TownVisual=V->GetVisualActor();
            Whole=Cast<UStaticMesh>(FSoftObjectPath(Recipe.FindRole(TEXT("bread"))->Asset).ResolveObject());Bitten=Cast<UStaticMesh>(FSoftObjectPath(Recipe.FindRole(TEXT("bread_bitten"))->Asset).ResolveObject());
            if(!Need(Parts.Num()==3&&Outfit.IsValid()&&Whole&&Bitten&&Outfit->LeaderPoseComponent.Get()==Body.Get()&&!IFileManager::Get().FileExists(*(FPaths::ProjectSavedDir()/TEXT("CafeWorldV3/CafeWorldResidentialCareV6.slot.json"))),TEXT("Original assembly and fresh paired native slot required")))return true;
            Opening=A->GetPresentation();if(!Need(Opening.Operator==TEXT("aria")&&Opening.Stock==2,TEXT("Fresh authored two-ration Aria-operated meal fixture required")))return true;
            Observer=FWorldDelegates::OnWorldPostActorTick.AddRaw(this,&FMetaHumanMealJourney::Sample);Transition(1);
        }
        if(!Need(C==PC.Get()&&C->GetPawn()==Pawn.Get()&&Assembly.IsValid()&&Body.IsValid()&&Face.IsValid()&&Outfit.IsValid()&&Player.IsValid()&&Assembly->GetBody()==Body.Get()&&Assembly->GetFace()==Face.Get()&&Body->GetSingleNodeInstance()==Player.Get()&&Face->GetAnimInstance()==FaceMain.Get()&&Face->GetPostProcessInstance()==FacePost.Get()&&Body->GetPostProcessInstance()==BodyPost.Get()&&Outfit->LeaderPoseComponent.Get()==Body.Get(),TEXT("No player, Face ABP/post-process or Outfit leader replacement allowed")))return true;
        if(bTownFixture&&!Need(TownVisual.IsValid()&&Assembly->IsConfigured()&&Assembly->GetVisualActor()==TownVisual.Get()&&Pawn->HasQualifiedVisual()&&Pawn->HasMetaHumanVisual()&&
            BodyPost.IsValid()&&FaceMain.IsValid()&&FacePost.IsValid()&&Face->GetAnimationMode()==EAnimationMode::AnimationBlueprint&&Outfit->GetSkeletalMeshAsset()&&
            Outfit->GetSkeletalMeshAsset()->GetPathName()==A->GetBinding().MetaHumanActor->ExpectedOutfitMesh(),TEXT("Exact original whole MetaHuman actor, BodyPP, FaceABP/PP and current workwear required throughout town meal")))return true;
        if(Stage==1){
            if(bTownFixture){
                if(!WalkTownRoute(W))return Done;
                PC->SetControlRotation(FRotator(0,(Recipe.CounterPointCm-Pawn->GetActorLocation()).Rotation().Yaw,0));Press(EKeys::W);Transition(2);return false;
            }
            const FVector Feet=Pawn->GetActorLocation()-FVector(0,0,Pawn->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());const FVector To=Recipe.StationFeetCm-Feet;
            if(To.Size2D()>Recipe.StationRadiusCm*.25){PC->SetControlRotation(FRotator(0,To.Rotation().Yaw,0));if(Held!=EKeys::W)Press(EKeys::W);return false;}
            Release();PC->SetControlRotation(FRotator(0,(Recipe.CounterPointCm-Pawn->GetActorLocation()).Rotation().Yaw,0));Press(EKeys::W);Transition(2);return false;
        }
        if(Stage==2){
            if(Held==EKeys::W){const FVector To=(Recipe.CounterPointCm-Pawn->GetActorLocation()).GetSafeNormal2D();if(FVector::DotProduct(Pawn->GetActorForwardVector().GetSafeNormal2D(),To)<Recipe.StationFacingDot)return false;Release();}
            if(Pawn->GetVelocity().Size2D()>2)return false;if(!Need(A->GetPresentation().bReachable,TEXT("Actual walked entry must satisfy original floor/hand/eye counter reach")))return true;Transition(3);
        }
        W3::CareEnvelope E;Care::Journal J;
        if(Stage==3){
            if(!Need(Inspect(A,E,J)&&J.requests.empty(),TEXT("Fresh source-bound public journal required before first E")))return true;double Fraction=0;FMemory::Memcpy(&Fraction,&E.clock.fraction_bits,sizeof(Fraction));
            // A fixed 20 ms window can be missed forever by valid 30 Hz frames.
            // Schedule across the observed next two natural frames, not by
            // changing the authority clock, delta or animation playback.
            if(Fraction+2.0*double(W->GetDeltaSeconds())<1)return false;MealOpening=A->GetPresentation();Monitoring=true;Press(EKeys::E);Transition(4);return false;
        }
        if(Stage==4){
            if(!Released())return false;if(!Need(Inspect(A,E,J)&&J.active&&J.active->elapsed==0&&J.requests.size()==1,TEXT("Near-boundary E must reserve a real zero-progress use")))return true;
            bool Wait=false;for(const auto& H:J.history)Wait|=H.op==Care::Op::WaitBeforeFirstProgress;if(!Wait)return false;
            if(!Need(J.needs.hunger<=MealOpening.Hunger&&J.needs.fun==MealOpening.Fun&&A->GetPresentation().BenCoins==Opening.BenCoins-2&&A->GetPresentation().AriaCoins==Opening.AriaCoins+2&&A->GetPresentation().Stock==1,TEXT("Preparation decays normally, gives no benefit and settles exactly once")))return true;
            Press(EKeys::F5);Transition(5);return false;
        }
        if(Stage==5){if(!Released())return false;if(!IFileManager::Get().FileExists(*(FPaths::ProjectSavedDir()/TEXT("CafeWorldV3/CafeWorldResidentialCareV6.slot.json"))))return false;Press(EKeys::X);Transition(6);return false;}
        if(Stage==6){
            if(!Released())return false;if(!Need(Inspect(A,E,J)&&!J.active&&J.requests.size()==1&&J.requests.back().end==Care::End::Cancelled&&J.requests.back().progressed_ticks==0&&!Source->IsPhysicalUseActive()&&!Food.IsValid(),TEXT("Real X cancels active preparation and destroys only owned food/action")))return true;
            Monitoring=false;Press(EKeys::F9);Transition(7);return false;
        }
        if(Stage==7){
            if(!Released())return false;if(!Need(Inspect(A,E,J)&&!J.active&&J.requests.size()==1&&J.requests.back().end==Care::End::AfterLoad&&J.requests.back().progressed_ticks==0&&A->GetPresentation().BenCoins==Opening.BenCoins-2&&A->GetPresentation().Stock==1&&!Source->IsPhysicalUseActive()&&!Food.IsValid(),TEXT("Real F9 retains the paid save, interrupts loaded use and never recreates bread or grants pre-bite progress")))return true;
            MealOpening=A->GetPresentation();SawBite=SawBitten=SawTail=false;BiteWorld=FirstBenefit=-1;Monitoring=true;Press(EKeys::E);Transition(8);return false;
        }
        if(Stage==8){
            if(!Released())return false;if(A->GetPresentation().bMealActive)return false;
            if(!Need(Inspect(A,E,J)&&J.requests.size()==2&&J.requests.back().end==Care::End::Completed&&J.requests.back().progressed_ticks==18,TEXT("Second actual E must earn exactly eighteen ordinary increments")))return true;
            int32 Advances=0;for(const auto& H:J.history)if(H.op==Care::Op::Advance&&H.contact&&H.contact->grant_id==J.requests.back().grant.grant_id)++Advances;
            if(!Need(Advances==18&&SawBite&&SawBitten&&FirstBenefit>=0&&J.needs.fun==MealOpening.Fun+300&&A->GetPresentation().BenCoins==Opening.BenCoins-4&&A->GetPresentation().AriaCoins==Opening.AriaCoins+4&&A->GetPresentation().Stock==0,TEXT("One paid second meal, real bite/mesh change and exact authored +3 fun required")))return true;Transition(9);
        }
        if(Stage==9){
            if(Source->IsPhysicalUseActive())return false;
            if(!Need(Inspect(A,E,J)&&!J.active&&J.requests.back().progressed_ticks==18&&SawTail&&!Food.IsValid()&&!Assembly->IsActionClipActive()&&J.needs.fun==MealOpening.Fun+300,TEXT("Bounded visual tail gives no extra increment and cleans only owned food/action")))return true;
            auto Proof=MakeShared<FJsonObject>();Proof->SetStringField(TEXT("status"),TEXT("PASS_NATIVE_INPUT_STATE_ONLY_NO_ART_ADMISSION"));Proof->SetStringField(TEXT("recipe_sha256"),Recipe.RecipeSha256);Proof->SetStringField(TEXT("certificate_sha256"),Recipe.CertificateSha256);Proof->SetStringField(TEXT("binding_sha256"),Recipe.BindingSha256);Proof->SetNumberField(TEXT("requests"),2);Proof->SetNumberField(TEXT("completed_ordinary_ticks"),18);Proof->SetNumberField(TEXT("bite_observed_world_seconds"),BiteWorld);Proof->SetNumberField(TEXT("first_benefit_observed_world_seconds"),FirstBenefit);Proof->SetNumberField(TEXT("certified_first_progress_delay_seconds"),Recipe.FirstProgressDelay);Proof->SetBoolField(TEXT("qualified_bitten_geometry_observed"),SawBitten);Proof->SetBoolField(TEXT("no_grant_visual_tail_observed"),SawTail);Proof->SetBoolField(TEXT("same_original_body_player_and_face_ownership"),true);Proof->SetBoolField(TEXT("physical_resume_after_load"),false);Proof->SetBoolField(TEXT("pixels_or_hardware_keypress_claimed"),false);
            if(bTownFixture){
                if(!TownCensus(W,A->GetBinding()))return true;
                Proof->SetStringField(TEXT("root_world"),UWorld::RemovePIEPrefix(W->GetOutermost()->GetName()));Proof->SetStringField(TEXT("scope"),TEXT("Combined town/current MetaHuman, frozen indoor cafe route and meal input only"));
                Proof->SetStringField(TEXT("indoor_route_sha256"),TownMealRouteSha);Proof->SetNumberField(TEXT("indoor_walk_distance_cm"),TownWalkCm);Proof->SetNumberField(TEXT("indoor_walk_samples"),TownRouteSamples);Proof->SetNumberField(TEXT("town_census_samples"),TownCensusSamples);
                TArray<TSharedPtr<FJsonValue>> Reached;for(const FVector& Feet:ReachedTownFeet){TArray<TSharedPtr<FJsonValue>> XYZ;for(double Value:{Feet.X,Feet.Y,Feet.Z})XYZ.Add(MakeShared<FJsonValueNumber>(Value));Reached.Add(MakeShared<FJsonValueArray>(XYZ));}
                Proof->SetArrayField(TEXT("observed_source_waypoint_feet_cm"),Reached);Proof->SetObjectField(TEXT("final_town_status"),LatestTownStatus);Proof->SetBoolField(TEXT("entrance_ground_seam_long_route_art_or_FPS_qualified"),false);
            }
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
    const bool bTown=FParse::Param(FCommandLine::Get(),TEXT("LivingTownWorldV3TownMealJourney"));TArray<FVector> Route;
    if(bTown&&(!IFileManager::Get().FileExists(*FPackageName::LongPackageNameToFilename(TownMealRoot,FPackageName::GetMapPackageExtension()))||!ReadTownMealRoute(Route))){AddError(TEXT("Actual new saved town root and exact typed three-point source route required"));return false;}
    if(!AutomationOpenMap(bTown?TownMealRoot:TEXT("/Engine/Maps/Entry"),true))return false;ADD_LATENT_AUTOMATION_COMMAND(FMetaHumanMealJourney(this,bTown,MoveTemp(Route)));return true;
}
#endif
