#include "LivingTownCafePropertyV2Subsystem.h"
#include "LivingTownCafePropertyV2Scenario.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownCafeProjectionSubsystem.h"
#include "LivingTownLeaseSubsystem.h"
#include "../../ThirdParty/CafePropertyV2.hpp"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Tests/AutomationCommon.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "UObject/Package.h"
#include "Components/CapsuleComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "HAL/PlatformTime.h"
#include "HAL/FileManager.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/Base64.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Policies/CondensedJsonPrintPolicy.h"

namespace {
namespace P=living_town::cafe_property_v2;
constexpr const TCHAR* BindingHash=TEXT("38171606986ba5086102aeba31927fac698558eebed861dd0f4d8eaf713fad6e");
constexpr const TCHAR* RouteHash=TEXT("38d98ee0c968647be6a1a89eac2abfe7c4b8a65b8732248f62fd3e7f54113846");
TArray<TSharedPtr<FJsonValue>> XYZ(const FVector& V){return {MakeShared<FJsonValueNumber>(V.X),MakeShared<FJsonValueNumber>(V.Y),MakeShared<FJsonValueNumber>(V.Z)};}
std::string Utf8(const FString& S){return std::string(TCHAR_TO_UTF8(*S));}
TArray<uint8> Bytes(const std::string& S){TArray<uint8> B;B.Append(reinterpret_cast<const uint8*>(S.data()),int32(S.size()));return B;}
bool HashFile(const FString& Path,FString& Hash){TArray<uint8> B;return FFileHelper::LoadFileToArray(B,*Path)&&LivingTownCafeJournal::Sha256(B,Hash);}
bool Object(const FString& Json,TSharedPtr<FJsonObject>& O){return LivingTownCafeJournal::HasUniqueObjectKeys(Json)&&FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),O)&&O.IsValid();}
bool RehashEnvelope(const TSharedPtr<FJsonObject>& O,FString& Json){
    P::detail::Writer W;for(const TCHAR* K:{TEXT("format"),TEXT("version"),TEXT("capability"),TEXT("core_sha256"),TEXT("roster_sha256"),TEXT("config_sha256"),TEXT("binding_sha256"),TEXT("physical_scene_sha256"),TEXT("physical_qualification_sha256"),TEXT("ben_visual_sha256"),TEXT("owner_proxy_policy"),TEXT("clock"),TEXT("clock_remainder_double_bits"),TEXT("saved_persona_metadata"),TEXT("session_policy"),TEXT("payload_sha256"),TEXT("payload_base64")}){FString V;if(!O->TryGetStringField(K,V))return false;W.s(Utf8(FString(K)));W.s(Utf8(V));}
    FString Hash;if(!LivingTownCafeJournal::Sha256(Bytes(W.bytes),Hash))return false;O->SetStringField(TEXT("envelope_sha256"),Hash);return FJsonSerializer::Serialize(O.ToSharedRef(),TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Json));
}
bool Payload(const FString& Json,P::Journal& J){TSharedPtr<FJsonObject> O;FString Encoded;TArray<uint8> B;if(!Object(Json,O)||!O->TryGetStringField(TEXT("payload_base64"),Encoded)||!FBase64::Decode(Encoded,B)||B.IsEmpty())return false;const auto Parsed=P::decode(std::string(reinterpret_cast<const char*>(B.GetData()),size_t(B.Num())));if(!Parsed)return false;J=*Parsed;return true;}
bool ReplacePayload(const FString& Original,const P::Journal& J,FString& Bad){TSharedPtr<FJsonObject> O;if(!Object(Original,O))return false;const auto B=Bytes(P::encode(J));FString H;if(!LivingTownCafeJournal::Sha256(B,H))return false;O->SetStringField(TEXT("payload_base64"),FBase64::Encode(B));O->SetStringField(TEXT("payload_sha256"),H);return RehashEnvelope(O,Bad);}

struct FWalk {
    int32 MovingSamples=0,AnimationTimeChanges=0;double DistanceCm=0;float LastAnimationTime=0;bool bHaveAnimation=false,bHaveFootBaseline=false;FVector FootBaseline[2];double FootSpan[2]={0,0};
};
class FPropertyActualJourney final:public IAutomationLatentCommand {
    FAutomationTestBase* Test;const FLivingTownCafeBinding Binding;const TArray<FVector> Route;
    TWeakObjectPtr<UWorld> World;TWeakObjectPtr<ALivingTownCafePropertyV2Controller> Controller;TWeakObjectPtr<ACharacter> Pawn;
    TSharedRef<FJsonObject> Evidence=MakeShared<FJsonObject>();TArray<TSharedPtr<FJsonValue>> Samples,Receipts;
    double Deadline=FPlatformTime::Seconds()+180,RoleStart=0,LastSampleTime=-1,FaceSince=-1;FVector LastPosition=FVector::ZeroVector;int32 Stage=0,Role=0,Waypoint=1;bool bDone=false,bComplete=false;
    FWalk Walks[3];FString Saved;
    bool Fail(const FString& Why){Test->AddError(Why);Evidence->SetStringField(TEXT("failure"),Why);bDone=true;return false;}
    bool Need(bool Yes,const TCHAR* Why){return Yes||Fail(Why);}
    bool Session(UWorld*& W,ALivingTownCafePropertyV2Controller*& PC,ULivingTownCafePropertyV2Subsystem*& Authority,ACharacter*& Actor){
        W=nullptr;int32 Count=0;for(const auto& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::PIE||C.WorldType==EWorldType::Game)){W=C.World();++Count;}
        if(Count>1)return Fail(TEXT("Ambiguous property journey game world"));if(!W||!W->HasBegunPlay())return false;
        if(!Need(UWorld::RemovePIEPrefix(W->GetOutermost()->GetName())==TEXT("/Engine/Maps/Entry")&&W->GetNetMode()==NM_Standalone&&W->GetAuthGameMode()&&W->GetAuthGameMode()->GetClass()==ALivingTownCafePropertyV2GameMode::StaticClass(),TEXT("Actual Entry standalone property GameMode required; configure only the private test host")))return false;
        if(!Need(W->GetGameInstance()&&!W->GetGameInstance()->GetSubsystem<ULivingTownLeaseSubsystem>(),TEXT("V1 money authority must be absent in actual v2 scenario")))return false;
        if(const auto* Old=W->GetSubsystem<ULivingTownCafeProjectionSubsystem>())if(!Need(!Old->IsReady()&&!Old->IsScenePrepared(),TEXT("V1 projection must remain unprepared")))return false;
        PC=Cast<ALivingTownCafePropertyV2Controller>(W->GetFirstPlayerController());Authority=W->GetSubsystem<ULivingTownCafePropertyV2Subsystem>();Actor=PC?Cast<ACharacter>(PC->GetPawn()):nullptr;
        if(!PC||!Authority||!Authority->IsPrepared()||!PC->HasNativePersona()||!Actor)return false;
        if(!Need(PC->GetViewTarget()==Actor&&Actor->GetController()==PC&&!W->IsPaused()&&Authority->GetBinding().BindingFileSha256==Binding.BindingFileSha256,TEXT("Actual source-bound current persona/controller/scene required")))return false;
        if(World.IsValid()&&!Need(World.Get()==W&&Controller.Get()==PC,TEXT("Journey world/controller identity changed")))return false;
        World=W;Controller=PC;return true;
    }
    bool StartRole(UWorld* W,ALivingTownCafePropertyV2Controller* PC,ACharacter* Actor,int32 NewRole){
        if(!Need(Actor&&PC->GetPawn()==Actor&&Actor->GetController()==PC,TEXT("Selected role must have a real possessed character")))return false;
        const auto Expected=NewRole==1?ELivingTownCafePropertyPersona::Ben:ELivingTownCafePropertyPersona::Aria;
        if(!Need(PC->GetNativePersona()==Expected,TEXT("Real GameMode-selected authored role required")))return false;
        const FVector Feet=Actor->GetActorLocation()-FVector(0,0,Binding.CapsuleHalfHeightCm);
        if(!Need(Feet.Equals(Route[0],2)&&FMath::IsNearlyEqual(Actor->GetCapsuleComponent()->GetScaledCapsuleRadius(),Binding.CapsuleRadiusCm,.01f)&&FMath::IsNearlyEqual(Actor->GetCapsuleComponent()->GetScaledCapsuleHalfHeight(),Binding.CapsuleHalfHeightCm,.01f),TEXT("Each legitimately selected pawn starts at the exact source spawn/capsule")))return false;
        if(NewRole==1){const auto* Ben=Cast<ALivingTownCafeCharacter>(Actor);if(!Need(Ben&&Ben->HasQualifiedVisual(),TEXT("Buyer must use actual qualified legacy Ben, not new-worker physical qualification")))return false;}
        else {const auto* Aria=Cast<ALivingTownCafePropertyOwnerProxy>(Actor);if(!Need(Aria&&Aria->IsFunctionalOwnerConfigured(),TEXT("Owner must be the real possessed functional Aria role")))return false;}
        Pawn=Actor;Role=NewRole;RoleStart=W->GetTimeSeconds();LastSampleTime=-1;LastPosition=Actor->GetActorLocation();Waypoint=1;FaceSince=-1;return true;
    }
    bool Sample(UWorld* W,ALivingTownCafePropertyV2Controller* PC,ULivingTownCafePropertyV2Subsystem* Authority,ACharacter* Actor){
        const double Time=W->GetTimeSeconds();if(LastSampleTime>=0&&Time-LastSampleTime<.05)return true;
        if(!Need(Samples.Num()<512&&Pawn.Get()==Actor,TEXT("Finite sample count and same pawn during one role walk required")))return false;
        if(LastSampleTime>=0){const double Delta=Time-LastSampleTime;const double Distance=FVector::Dist2D(LastPosition,Actor->GetActorLocation());if(!Need(Delta>0&&Distance<=Binding.WalkSpeedCmPerSecond*Delta+2,TEXT("Natural CharacterMovement speed/world delta violated; no teleport allowed")))return false;Walks[Role].DistanceCm+=Distance;}
        const bool Moving=Actor->GetCharacterMovement()->IsMovingOnGround()&&Actor->GetVelocity().Size2D()>33;if(Moving)++Walks[Role].MovingSamples;
        auto J=MakeShared<FJsonObject>();J->SetNumberField(TEXT("stage"),Stage);J->SetNumberField(TEXT("role_walk"),Role);J->SetNumberField(TEXT("world_seconds"),Time);J->SetArrayField(TEXT("actor_cm"),XYZ(Actor->GetActorLocation()));J->SetArrayField(TEXT("velocity_cm_s"),XYZ(Actor->GetVelocity()));J->SetStringField(TEXT("pawn"),Actor->GetPathName());J->SetStringField(TEXT("native_persona"),PC->GetNativePersona()==ELivingTownCafePropertyPersona::Aria?TEXT("aria"):TEXT("ben"));J->SetBoolField(TEXT("moving_on_actual_floor"),Actor->GetCharacterMovement()->IsMovingOnGround());J->SetBoolField(TEXT("cached_actual_counter_reach"),Authority->GetPresentation().bReachable);
        if(Role==1&&Moving){const auto* Ben=Cast<ALivingTownCafeCharacter>(Actor);auto* Mesh=Ben?Ben->GetMesh():nullptr;auto* Anim=Mesh?Mesh->GetSingleNodeInstance():nullptr;if(!Need(Anim&&Anim->IsPlaying(),TEXT("Naturally playing qualified Ben animation required")))return false;const float TimeNow=Anim->GetCurrentTime();if(Walks[1].bHaveAnimation&&FMath::Abs(TimeNow-Walks[1].LastAnimationTime)>1e-4)++Walks[1].AnimationTimeChanges;Walks[1].bHaveAnimation=true;Walks[1].LastAnimationTime=TimeNow;J->SetNumberField(TEXT("ben_natural_animation_time"),TimeNow);
            const auto& Pose=Mesh->GetComponentSpaceTransforms();const int32 Pelvis=Mesh->GetBoneIndex(TEXT("Skin_PelvisRoot"));if(!Need(Pose.IsValidIndex(Pelvis),TEXT("Source Ben pelvis missing")))return false;const FName Feet[]={TEXT("Skin_Foot_L"),TEXT("Skin_Foot_R")};for(int32 I=0;I<2;++I){const int32 Index=Mesh->GetBoneIndex(Feet[I]);if(!Need(Pose.IsValidIndex(Index)&&!Pose[Index].ContainsNaN(),TEXT("Source Ben evaluated foot missing/nonfinite")))return false;const FVector Relative=Pose[Index].GetTranslation()-Pose[Pelvis].GetTranslation();if(!Walks[1].bHaveFootBaseline)Walks[1].FootBaseline[I]=Relative;Walks[1].FootSpan[I]=FMath::Max(Walks[1].FootSpan[I],FVector::Dist(Relative,Walks[1].FootBaseline[I]));}Walks[1].bHaveFootBaseline=true;
        }
        Samples.Add(MakeShared<FJsonValueObject>(J));LastPosition=Actor->GetActorLocation();LastSampleTime=Time;return true;
    }
    bool AtCounter(UWorld* W,ALivingTownCafePropertyV2Controller* PC,ULivingTownCafePropertyV2Subsystem* Authority,ACharacter* Actor){
        if(!Sample(W,PC,Authority,Actor))return false;const FVector Feet=Actor->GetActorLocation()-FVector(0,0,Binding.CapsuleHalfHeightCm);
        if(Waypoint<Route.Num()){FVector Delta=Route[Waypoint]-Feet;Delta.Z=0;if(Delta.Size2D()>2){PC->SetControlRotation(Delta.Rotation());Actor->AddMovementInput(Delta.GetSafeNormal2D(),1);return false;}Actor->GetCharacterMovement()->StopMovementImmediately();++Waypoint;return false;}
        if(FaceSince<0){if(!Need(Walks[Role].MovingSamples>=12&&Walks[Role].DistanceCm>=480,TEXT("Each selected role must walk the full frozen510cm route naturally")))return false;const FVector Position=Actor->GetActorLocation();const FVector Aim=Binding.CounterUsePointCm-Position;Actor->SetActorRotation(FRotator(0,Aim.Rotation().Yaw,0));if(!Need(Actor->GetActorLocation().Equals(Position,0),TEXT("Declared physical in-place facing cannot translate the pawn")))return false;FaceSince=W->GetTimeSeconds();return false;}
        if(W->GetTimeSeconds()-FaceSince<.25)return false;if(!Authority->GetPresentation().bReachable){if(W->GetTimeSeconds()-FaceSince>3)Fail(TEXT("Real current floor/proximity/facing/first-counter rays refuse after the walked route"));return false;}return true;
    }
    bool Wallets(ULivingTownCafePropertyV2Subsystem* A,int64 Aria,int64 Ben,const TCHAR* Owner,const TCHAR* Operator){const auto& V=A->GetPresentation();return Need(V.AriaCoins==Aria&&V.BenCoins==Ben&&V.AriaCoins+V.BenCoins==24&&V.Owner==Owner&&V.Operator==Operator,TEXT("Actual authority wallets/title/operator/conserved24 mismatch"));}
    FLivingTownCafePropertyReceipt Submit(ULivingTownCafePropertyV2Subsystem* A,const TCHAR* Id,ELivingTownCafePropertyAction Action){FLivingTownCafePropertyCommand C;C.RequestId=Id;C.Action=Action;const auto R=A->SubmitCommand(C);auto J=MakeShared<FJsonObject>();J->SetStringField(TEXT("request_id"),Id);J->SetBoolField(TEXT("accepted"),R.bAccepted);J->SetBoolField(TEXT("already_applied"),R.bAlreadyApplied);J->SetStringField(TEXT("reason"),R.Reason);J->SetNumberField(TEXT("event_id"),R.EventId);Receipts.Add(MakeShared<FJsonValueObject>(J));Test->AddInfo(FString::Printf(TEXT("Actual PropertyV2 typed request %s accepted=%d replay=%d event=%lld reason=%s"),Id,R.bAccepted?1:0,R.bAlreadyApplied?1:0,(long long)R.EventId,*R.Reason));return R;}
    bool RejectUnchanged(ULivingTownCafePropertyV2Subsystem* A,const FString& Bad,const TCHAR* Label){FString Before,After,Error;if(!Need(A->EncodeJournal(Before,Error),TEXT("Snapshot before negative load required")))return false;auto* PC=Controller.Get();const auto* Actor=Pawn.Get();const auto Transform=Actor->GetActorTransform();const auto Persona=PC->GetNativePersona();if(!Need(!A->LoadJournal(Bad,Error),Label))return false;if(!Need(A->EncodeJournal(After,Error)&&Before==After&&Actor->GetActorTransform().Equals(Transform,0)&&PC->GetPawn()==Actor&&PC->GetNativePersona()==Persona,TEXT("Rejected native load must preserve exact authority/persona/position")))return false;return true;}
    bool ArchiveProof(ULivingTownCafePropertyV2Subsystem* A){
        FString Error;if(!Need(A->EncodeJournal(Saved,Error),TEXT("Actual v2 envelope encoding failed")))return false;P::Journal J;if(!Need(Payload(Saved,J),TEXT("Actual native payload must decode")))return false;
        if(!Need(J.events.size()==7&&J.title.owner=="ben"&&J.title.revision==1&&J.lease.active&&J.lease.tenant=="aria"&&J.lease.owner=="ben"&&J.lease.end-J.lease.start==720,TEXT("Exact event-derived paid deed and prepaid term required")))return false;
        const auto& SalePay=J.events[2];const auto& Deed=J.events[3];const auto& LeasePay=J.events[5];const auto& Grant=J.events[6];if(!Need(SalePay.type=="pay"&&SalePay.actor=="ben"&&SalePay.target=="aria"&&SalePay.amt==12&&Deed.type=="property_deed_transferred"&&Deed.pay_event_id==SalePay.id&&LeasePay.type=="pay"&&LeasePay.actor=="aria"&&LeasePay.target=="ben"&&LeasePay.amt==4&&Grant.pay_event_id==LeasePay.id,TEXT("Real pay receipts must link exact sale and lease, not invented balances")))return false;
        auto* PC=Controller.Get();const auto Transform=Pawn->GetActorTransform();const auto Persona=PC->GetNativePersona();if(!Need(Submit(A,TEXT("journey/end_for_replay"),ELivingTownCafePropertyAction::EndLease).bAccepted&&Wallets(A,20,4,TEXT("ben"),TEXT("ben")),TEXT("Actual end before replay failed")))return false;
        if(!Need(A->LoadJournal(Saved,Error)&&Wallets(A,20,4,TEXT("ben"),TEXT("aria"))&&Pawn->GetActorTransform().Equals(Transform,0)&&PC->GetNativePersona()==Persona,TEXT("Actual envelope replay restores lease while keeping live persona and position")))return false;FString Restored;if(!Need(A->EncodeJournal(Restored,Error)&&Restored==Saved,TEXT("Round-trip envelope and complete state exact")))return false;
        FString SlotSha;if(!Need(A->SaveSlot(Error,&SlotSha)&&A->LoadSlot(Error),TEXT("Actual native atomic slot write/readback failed")))return false;TArray<uint8> File;FString ActualSha;const FString Slot=FPaths::ProjectSavedDir()/TEXT("CafePropertyV2/CafePropertyTitleV2.slot.json");if(!Need(FFileHelper::LoadFileToArray(File,*Slot)&&LivingTownCafeJournal::Sha256(File,ActualSha)&&ActualSha==SlotSha,TEXT("Actual saved slot bytes SHA must match the wrapper receipt")))return false;Evidence->SetStringField(TEXT("actual_slot"),Slot);Evidence->SetStringField(TEXT("actual_slot_sha256"),SlotSha);
        FString Bad;TSharedPtr<FJsonObject> O;if(!Need(Object(Saved,O),TEXT("Read valid envelope for controlled negative fixtures")))return false;O->SetStringField(TEXT("version"),TEXT("1"));if(!Need(RehashEnvelope(O,Bad),TEXT("Rehash cross-version fixture"))||!RejectUnchanged(A,Bad,TEXT("Checksum-valid cross-version native save must refuse")))return false;
        auto Broken=J;Broken.accounts[0].coin+=1;if(!Need(ReplacePayload(Saved,Broken,Bad),TEXT("Rehash counterfeit cash fixture"))||!RejectUnchanged(A,Bad,TEXT("Checksum-valid counterfeit wallet must fail ledger replay")))return false;
        Broken=J;Broken.events[3].pay_event_id=99;if(!Need(ReplacePayload(Saved,Broken,Bad),TEXT("Rehash forged payment link fixture"))||!RejectUnchanged(A,Bad,TEXT("Checksum-valid forged property pay link must refuse")))return false;
        Broken=J;Broken.document_schema="cafe.prepaid_lease.v1";if(!Need(ReplacePayload(Saved,Broken,Bad),TEXT("Rehash old core schema fixture"))||!RejectUnchanged(A,Bad,TEXT("Old lease core journal cannot enter the property v2 authority")))return false;
        if(!Need(Object(Saved,O),TEXT("Read valid envelope for clock fixture")))return false;O->SetStringField(TEXT("clock"),LexToString(J.lease.end));if(!Need(RehashEnvelope(O,Bad),TEXT("Rehash expired-active clock fixture"))||!RejectUnchanged(A,Bad,TEXT("Checksum-valid expired-active lease clock must refuse")))return false;
        Bad=Saved.Replace(TEXT("\"version\":\"2\""),TEXT("\"version\":\"invalid\""));if(!Need(Bad!=Saved,TEXT("Negative checksum fixture must change bytes"))||!RejectUnchanged(A,Bad,TEXT("Changed envelope without new SHA must refuse")))return false;return true;
    }
    void Persist(){Evidence->SetStringField(TEXT("format"),TEXT("LivingTown.CafePropertyV2ActualPublicBoundaryJourney"));Evidence->SetStringField(TEXT("status"),bComplete&&!Test->HasAnyErrors()?TEXT("PASS_SAME_PROCESS_ACTUAL_PUBLIC_BOUNDARY_JOURNEY_ONLY"):TEXT("FAIL_PRESERVED_ACTUAL_PUBLIC_BOUNDARY_JOURNEY"));Evidence->SetStringField(TEXT("binding_sha256"),BindingHash);Evidence->SetStringField(TEXT("route_sha256"),RouteHash);Evidence->SetArrayField(TEXT("natural_samples"),Samples);Evidence->SetArrayField(TEXT("public_typed_receipts"),Receipts);Evidence->SetBoolField(TEXT("UI_keypress_journey_claimed"),false);Evidence->SetBoolField(TEXT("actual_separate_process_cold_reopen_qualified"),false);Evidence->SetBoolField(TEXT("Aria_final_visual_or_hand_contact_qualified"),false);Evidence->SetBoolField(TEXT("manual_animation_tick_pose_time_position_clock_or_reach_substitution"),false);Evidence->SetBoolField(TEXT("declared_physical_in_place_facing_after_frozen_route"),true);FString Json;FJsonSerializer::Serialize(Evidence,TJsonWriterFactory<>::Create(&Json));const FString Dir=FPaths::ProjectSavedDir()/TEXT("CafePropertyV2Journey"),Path=Dir/TEXT("ACTUAL_PUBLIC_BOUNDARY_EVIDENCE.json");IFileManager::Get().MakeDirectory(*Dir,true);if(IFileManager::Get().FileExists(*Path)||!FFileHelper::SaveStringToFile(Json,*Path,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM))Test->AddError(TEXT("Property journey evidence write refused or failed; existing evidence preserved"));}
public:
    FPropertyActualJourney(FAutomationTestBase* T,const FLivingTownCafeBinding& B,const TArray<FVector>& R):Test(T),Binding(B),Route(R){}
    virtual bool Update()override{
        if(FPlatformTime::Seconds()>Deadline)Fail(TEXT("Actual property journey timed out; observations retained"));
        if(!bDone){UWorld* W=nullptr;ALivingTownCafePropertyV2Controller* PC=nullptr;ULivingTownCafePropertyV2Subsystem* A=nullptr;ACharacter* Actor=nullptr;if(Session(W,PC,A,Actor)){
            if(Stage==0){if(StartRole(W,PC,Actor,0))Stage=1;}
            else if(Stage==1){if(W->GetTimeSeconds()-RoleStart>=.25&&Actor->GetCharacterMovement()->IsMovingOnGround()){if(Need(!A->GetPresentation().bReachable,TEXT("Source spawn must be offsite"))){const auto R=Submit(A,TEXT("journey/owner_offsite"),ELivingTownCafePropertyAction::OfferSale);if(Need(!R.bAccepted&&R.Reason==TEXT("not_at_commercial_counter"),TEXT("Real offsite owner request must refuse"))&&Wallets(A,12,12,TEXT("aria"),TEXT("aria")))Stage=2;}}}
            else if(Stage==2){if(AtCounter(W,PC,A,Actor)&&Need(Submit(A,TEXT("journey/owner_sale"),ELivingTownCafePropertyAction::OfferSale).bAccepted,TEXT("Actually walked Aria owner sale listing failed")))Stage=3;}
            else if(Stage==3){FString Error;auto* G=Cast<ALivingTownCafePropertyV2GameMode>(W->GetAuthGameMode());if(Need(G->SelectPersona(PC,ELivingTownCafePropertyPersona::Ben,Error),TEXT("Legitimate native buyer persona selection failed"))&&StartRole(W,PC,Cast<ACharacter>(PC->GetPawn()),1))Stage=4;}
            else if(Stage==4){if(AtCounter(W,PC,A,Actor)){if(!Need(Walks[1].AnimationTimeChanges>=3&&Walks[1].FootSpan[0]>=2&&Walks[1].FootSpan[1]>=2,TEXT("Buyer walk needs natural playback and bilateral foot articulation"))){}else{const auto R=Submit(A,TEXT("journey/buy"),ELivingTownCafePropertyAction::Buy);if(Need(R.bAccepted,TEXT("Actually walked Ben purchase failed"))&&Wallets(A,24,0,TEXT("ben"),TEXT("ben"))){const int64 Events=A->GetPresentation().EventCount;const auto Retry=Submit(A,TEXT("journey/buy"),ELivingTownCafePropertyAction::Buy);if(Need(Retry.bAccepted&&Retry.bAlreadyApplied&&Retry.EventId==R.EventId&&A->GetPresentation().EventCount==Events,TEXT("Real public fixed-ID retry must not pay twice"))&&Need(Submit(A,TEXT("journey/new_owner_lease_offer"),ELivingTownCafePropertyAction::OfferLease).bAccepted,TEXT("New owner must explicitly open lease listing")))Stage=5;}}}}
            else if(Stage==5){FString Error;auto* G=Cast<ALivingTownCafePropertyV2GameMode>(W->GetAuthGameMode());if(Need(G->SelectPersona(PC,ELivingTownCafePropertyPersona::Aria,Error),TEXT("Legitimate native owner/tenant persona reselection failed"))&&StartRole(W,PC,Cast<ACharacter>(PC->GetPawn()),2))Stage=6;}
            else if(Stage==6){if(AtCounter(W,PC,A,Actor)&&Need(Submit(A,TEXT("journey/aria_lease"),ELivingTownCafePropertyAction::Lease).bAccepted,TEXT("Actually walked Aria tenant lease failed"))&&Wallets(A,20,4,TEXT("ben"),TEXT("aria"))&&ArchiveProof(A)){bComplete=true;bDone=true;}}
        }}
        if(bDone){if(Pawn.IsValid())Pawn->GetCharacterMovement()->StopMovementImmediately();Persist();return true;}return false;
    }
};
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafePropertyV2WorldJourneyTest,"LivingTown.PropertyV2.ActualPublicBoundaryJourney",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafePropertyV2WorldJourneyTest::RunTest(const FString&){
    if(!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafePropertyV2"))||!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafePropertyJourney"))||FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeLegacyV1"))||FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeWorker110DevelopmentPreview"))){AddError(TEXT("Exact isolated property v2 journey flags, no legacy/worker diagnostic conflict, required"));return false;}
    if(IFileManager::Get().FileExists(*(FPaths::ProjectSavedDir()/TEXT("CafePropertyV2/CafePropertyTitleV2.slot.json")))||IFileManager::Get().FileExists(*(FPaths::ProjectSavedDir()/TEXT("CafePropertyV2Journey/ACTUAL_PUBLIC_BOUNDARY_EVIDENCE.json")))){AddError(TEXT("Fresh owned property journey Saved paths required; prior saves/evidence preserved"));return false;}
    const FString Folder=FPaths::ProjectContentDir()/TEXT("LivingTown"),BindingPath=Folder/TEXT("CafeProjectionBinding.json"),RoutePath=Folder/TEXT("CafeJourneyRoute.json");FString ActualHash,Error;FLivingTownCafeBinding B;
    if(!HashFile(BindingPath,ActualHash)||ActualHash!=BindingHash||!FLivingTownCafeBinding::ReadQualifiedFile(BindingPath,B,Error)||B.MotionStrategy!=ELivingTownCafeMotionStrategy::LegacySingleNode||!HashFile(RoutePath,ActualHash)||ActualHash!=RouteHash){AddError(TEXT("Exact old actual qualified405-package Ben/cafe binding and route required; not a new-worker physical claim: ")+Error);return false;}
    FString Json;TSharedPtr<FJsonObject> O;const TArray<TSharedPtr<FJsonValue>>* Raw=nullptr;TArray<FVector> Route;if(!FFileHelper::LoadFileToString(Json,*RoutePath)||!Object(Json,O)||!O->TryGetArrayField(TEXT("route_feet_cm"),Raw)||Raw->Num()!=3){AddError(TEXT("Exact frozen3-point source route required"));return false;}
    for(const auto& V:*Raw){if(!V||V->Type!=EJson::Array||V->AsArray().Num()!=3){AddError(TEXT("Source route point invalid"));return false;}double C[3];for(int32 I=0;I<3;++I){const auto X=V->AsArray()[I];if(!X||X->Type!=EJson::Number||!FMath::IsFinite(C[I]=X->AsNumber())){AddError(TEXT("Source route coordinate invalid"));return false;}}Route.Add(FVector(C[0],C[1],C[2]));}
    if(!Route[0].Equals(B.SpawnFeetCm,.1)||B.CapsuleRadiusCm!=28||B.CapsuleHalfHeightCm!=95){AddError(TEXT("Actual source spawn/capsule binding mismatch"));return false;}
    // The private host selects the production property GameMode in its own config.
    // Passing a URL as MapName to editor AutomationLoadMap would be a package-load error.
    if(!AutomationOpenMap(TEXT("/Engine/Maps/Entry"),true)){AddError(TEXT("Owned Entry PIE map open failed"));return false;}ADD_LATENT_AUTOMATION_COMMAND(FPropertyActualJourney(this,B,Route));return true;
}

// Separate process restore proof. The previous journey implementation above is unchanged.
#include "HAL/PlatformProcess.h"
namespace {
constexpr const TCHAR* ColdReceiptHash=TEXT("53dcdc980c5ba78245f6cef41161594aced572ee04d7ca20a0dfe536cafaf99c");
class FColdPropertyRestore final:public IAutomationLatentCommand {
    FAutomationTestBase* Test;TSharedPtr<FJsonObject> Expected;
    TSharedRef<FJsonObject> Evidence=MakeShared<FJsonObject>();
    double Deadline=FPlatformTime::Seconds()+120,ReadySince=-1;bool bDone=false,bComplete=false;
    bool Need(bool Yes,const TCHAR* Why){if(Yes)return true;Test->AddError(Why);Evidence->SetStringField(TEXT("failure"),Why);bDone=true;return false;}
    bool Restore(UWorld* W,ALivingTownCafePropertyV2Controller* PC,ULivingTownCafePropertyV2Subsystem* A,ALivingTownCafePropertyOwnerProxy* Aria){
        FString ProducerId;uint32 Producer=0;
        if(!Need(Expected->TryGetStringField(TEXT("producer_process_id"),ProducerId)&&LexTryParseString(Producer,*ProducerId)&&Producer!=FPlatformProcess::GetCurrentProcessId(),TEXT("Cold fixture must come from the distinct terminal producer process")))return false;
        const auto Before=A->GetPresentation();const FTransform Transform=Aria->GetActorTransform();const auto Persona=PC->GetNativePersona();const FVector Feet=Aria->GetActorLocation()-FVector(0,0,Aria->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());
        FString Seed,Error;if(!Need(A->EncodeJournal(Seed,Error),TEXT("Fresh source-bound property authority must encode before loading")))return false;P::Journal SeedJ;
        if(!Need(Before.Owner==TEXT("aria")&&Before.Operator==TEXT("aria")&&Before.AriaCoins==12&&Before.BenCoins==12&&Before.EventCount==0&&!Before.bReachable&&Feet.Equals(A->GetBinding().SpawnFeetCm,2)&&Payload(Seed,SeedJ)&&SeedJ.events.empty()&&SeedJ.title.owner=="aria"&&!SeedJ.lease.active,TEXT("A fresh actual possessed Aria at source spawn must prove12+12/event0/initial title, without inherited state")))return false;
        auto S=MakeShared<FJsonObject>();S->SetStringField(TEXT("owner"),Before.Owner);S->SetStringField(TEXT("operator"),Before.Operator);S->SetNumberField(TEXT("aria_coins"),Before.AriaCoins);S->SetNumberField(TEXT("ben_coins"),Before.BenCoins);S->SetNumberField(TEXT("event_count"),Before.EventCount);S->SetArrayField(TEXT("actor_cm"),XYZ(Aria->GetActorLocation()));S->SetBoolField(TEXT("at_source_spawn_offsite"),true);Evidence->SetObjectField(TEXT("fresh_seed_before_public_load"),S);
        const FString Slot=FPaths::ProjectSavedDir()/TEXT("CafePropertyV2/CafePropertyTitleV2.slot.json");FString Incoming,IncomingSha,WantSha,WantBytes;TArray<uint8> SlotBytes;
        if(!Need(Expected->TryGetStringField(TEXT("slot_sha256"),WantSha)&&Expected->TryGetStringField(TEXT("slot_bytes"),WantBytes)&&FFileHelper::LoadFileToArray(SlotBytes,*Slot)&&LexToString(SlotBytes.Num())==WantBytes&&LivingTownCafeJournal::Sha256(SlotBytes,IncomingSha)&&IncomingSha==WantSha&&FFileHelper::LoadFileToString(Incoming,*Slot),TEXT("Only the exact previous actual3599-byte saved slot may be loaded at the fixed new Saved path")))return false;
        if(!Need(A->LoadSlot(Error),TEXT("Public native LoadSlot must restore the previous process authority")))return false;
        const auto After=A->GetPresentation();FString Restored;if(!Need(A->EncodeJournal(Restored,Error)&&Restored==Incoming,TEXT("Cold restored complete envelope including clock/fraction/payload must be byte-exact")))return false;
        P::Journal RestoredJ,IncomingJ;if(!Need(Payload(Restored,RestoredJ)&&Payload(Incoming,IncomingJ)&&P::encode(RestoredJ)==P::encode(IncomingJ)&&RestoredJ.events.size()==7&&RestoredJ.title.owner=="ben"&&RestoredJ.title.revision==1&&RestoredJ.title.event_id==4&&RestoredJ.lease.active&&RestoredJ.lease.tenant=="aria"&&RestoredJ.lease.owner=="ben"&&RestoredJ.lease.start==10&&RestoredJ.lease.end==730&&RestoredJ.lease.pay_event_id==6&&RestoredJ.lease.event_id==7,TEXT("Complete actual paid title, active lease and all seven receipts must survive a real new-process load")))return false;
        if(!Need(After.Owner==TEXT("ben")&&After.Operator==TEXT("aria")&&After.AriaCoins==20&&After.BenCoins==4&&After.EventCount==7&&After.Clock==10&&PC->GetPawn()==Aria&&PC->GetNativePersona()==Persona&&Aria->GetActorTransform().Equals(Transform,0)&&!After.bReachable,TEXT("Restore changes only authority, retaining current actual pawn/persona/transform/offsite reach")))return false;
        const auto& Sale=RestoredJ.events[2];const auto& Deed=RestoredJ.events[3];const auto& Rent=RestoredJ.events[5];const auto& Grant=RestoredJ.events[6];if(!Need(Sale.type=="pay"&&Sale.amt==12&&Sale.actor=="ben"&&Sale.target=="aria"&&Deed.pay_event_id==Sale.id&&Rent.type=="pay"&&Rent.amt==4&&Rent.actor=="aria"&&Rent.target=="ben"&&Grant.pay_event_id==Rent.id,TEXT("Cold restoration requires conserved actual12/4 linked payments, not cache-only balances")))return false;
        TSharedPtr<FJsonObject> Envelope;if(!Need(Object(Restored,Envelope),TEXT("Read the real restored envelope")))return false;for(const TCHAR* Key:{TEXT("payload_sha256"),TEXT("envelope_sha256"),TEXT("clock"),TEXT("clock_remainder_double_bits")}){FString Actual,Want;if(!Need(Envelope->TryGetStringField(Key,Actual)&&Expected->TryGetStringField(Key,Want)&&Actual==Want,TEXT("Exact producer payload/envelope/clock/fraction metadata must match")))return false;}
        FString AfterFileSha;if(!Need(HashFile(Slot,AfterFileSha)&&AfterFileSha==IncomingSha,TEXT("Public restore must not rewrite the incoming actual source slot")))return false;
        auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("owner"),After.Owner);R->SetStringField(TEXT("operator"),After.Operator);R->SetNumberField(TEXT("aria_coins"),After.AriaCoins);R->SetNumberField(TEXT("ben_coins"),After.BenCoins);R->SetNumberField(TEXT("event_count"),After.EventCount);R->SetNumberField(TEXT("clock"),After.Clock);R->SetArrayField(TEXT("actor_cm_after"),XYZ(Aria->GetActorLocation()));R->SetBoolField(TEXT("persona_pawn_transform_unchanged"),true);R->SetBoolField(TEXT("complete_payload_and_fraction_exact"),true);R->SetBoolField(TEXT("offsite_counter_reach_unchanged_false"),true);Evidence->SetObjectField(TEXT("after_public_load_slot"),R);Evidence->SetStringField(TEXT("slot"),Slot);Evidence->SetStringField(TEXT("slot_sha256"),IncomingSha);Evidence->SetNumberField(TEXT("slot_bytes"),SlotBytes.Num());Evidence->SetNumberField(TEXT("producer_process_id"),Producer);Evidence->SetNumberField(TEXT("current_process_id"),FPlatformProcess::GetCurrentProcessId());Evidence->SetStringField(TEXT("world"),W->GetPathName());Evidence->SetStringField(TEXT("pawn"),Aria->GetPathName());return true;
    }
    void Persist(){Evidence->SetStringField(TEXT("format"),TEXT("LivingTown.CafePropertyV2ColdPublicBoundaryRestore"));Evidence->SetStringField(TEXT("status"),bComplete&&!Test->HasAnyErrors()?TEXT("PASS_NEW_PROCESS_PUBLIC_LOAD_SLOT_RESTORE_ONLY"):TEXT("FAIL_PRESERVED_COLD_PUBLIC_LOAD_SLOT_RESTORE"));Evidence->SetStringField(TEXT("fixed_content_receipt_sha256"),ColdReceiptHash);Evidence->SetBoolField(TEXT("host_must_verify_separate_process_and_fixed_saved_custody"),true);Evidence->SetBoolField(TEXT("manual_position_persona_clock_reach_or_pose_substitution"),false);Evidence->SetBoolField(TEXT("UI_keypress_final_avatar_art_or_FPS_qualified"),false);FString Json;FJsonSerializer::Serialize(Evidence,TJsonWriterFactory<>::Create(&Json));const FString Dir=FPaths::ProjectSavedDir()/TEXT("CafePropertyV2ColdRestore"),Path=Dir/TEXT("ACTUAL_COLD_RESTORE_EVIDENCE.json");IFileManager::Get().MakeDirectory(*Dir,true);if(IFileManager::Get().FileExists(*Path)||!FFileHelper::SaveStringToFile(Json,*Path,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM))Test->AddError(TEXT("Cold restore evidence write refused or failed; prior evidence preserved"));}
public:
    FColdPropertyRestore(FAutomationTestBase* T,const TSharedPtr<FJsonObject>& E):Test(T),Expected(E){}
    virtual bool Update()override{
        if(FPlatformTime::Seconds()>Deadline){Need(false,TEXT("Cold public restore timed out before actual source-bound seed became ready"));}
        if(!bDone){UWorld* W=nullptr;int32 Count=0;for(const auto& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::PIE||C.WorldType==EWorldType::Game)){W=C.World();++Count;}
            if(Count>1)Need(false,TEXT("Ambiguous cold restore game world"));else if(W&&W->HasBegunPlay()){
                if(!Need(UWorld::RemovePIEPrefix(W->GetOutermost()->GetName())==TEXT("/Engine/Maps/Entry")&&W->GetNetMode()==NM_Standalone&&W->GetAuthGameMode()&&W->GetAuthGameMode()->GetClass()==ALivingTownCafePropertyV2GameMode::StaticClass()&&W->GetGameInstance()&&!W->GetGameInstance()->GetSubsystem<ULivingTownLeaseSubsystem>()&&!W->IsPaused(),TEXT("A real new standalone property GameMode with no v1 authority is required"))){}
                else {auto* PC=Cast<ALivingTownCafePropertyV2Controller>(W->GetFirstPlayerController());auto* A=W->GetSubsystem<ULivingTownCafePropertyV2Subsystem>();auto* Aria=PC?Cast<ALivingTownCafePropertyOwnerProxy>(PC->GetPawn()):nullptr;if(PC&&A&&A->IsPrepared()&&PC->HasNativePersona()&&PC->GetNativePersona()==ELivingTownCafePropertyPersona::Aria&&Aria&&Aria->IsFunctionalOwnerConfigured()&&Aria->GetController()==PC&&PC->GetViewTarget()==Aria&&Aria->GetCharacterMovement()->IsMovingOnGround()){
                    if(ReadySince<0)ReadySince=W->GetTimeSeconds();if(W->GetTimeSeconds()-ReadySince>=.25){bComplete=Restore(W,PC,A,Aria);bDone=true;}
                }}
            }
        }
        if(bDone){Persist();return true;}return false;
    }
};
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafePropertyV2ColdRestoreTest,"LivingTown.PropertyV2.ColdPublicBoundaryRestore",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafePropertyV2ColdRestoreTest::RunTest(const FString&){
    if(!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafePropertyV2"))||!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafePropertyColdRestore"))||FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafePropertyJourney"))||FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeLegacyV1"))||FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeWorker110DevelopmentPreview"))){AddError(TEXT("Exact separate cold property flags required; never run the old journey in this process"));return false;}
    if(IFileManager::Get().FileExists(*(FPaths::ProjectSavedDir()/TEXT("CafePropertyV2ColdRestore/ACTUAL_COLD_RESTORE_EVIDENCE.json")))){AddError(TEXT("Fresh owned cold restore evidence required"));return false;}
    const FString Path=FPaths::ProjectContentDir()/TEXT("LivingTown/PropertyV2ColdRestoreReceipt.json");FString Hash,Json;TSharedPtr<FJsonObject> Expected;
    if(!HashFile(Path,Hash)||Hash!=ColdReceiptHash||!FFileHelper::LoadFileToString(Json,*Path)||!Object(Json,Expected)||Expected->GetStringField(TEXT("format"))!=TEXT("LivingTown.CafePropertyV2ColdRestoreExpectation")||Expected->GetStringField(TEXT("version"))!=TEXT("1")||Expected->GetStringField(TEXT("slot_relative"))!=TEXT("CafePropertyV2/CafePropertyTitleV2.slot.json")){AddError(TEXT("Exact fixed Content receipt bound to the prior terminal actual slot is required"));return false;}
    if(!AutomationOpenMap(TEXT("/Engine/Maps/Entry"),true)){AddError(TEXT("Owned cold Entry PIE map open failed"));return false;}ADD_LATENT_AUTOMATION_COMMAND(FColdPropertyRestore(this,Expected));return true;
}

#endif
