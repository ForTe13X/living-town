#include "LivingTownCafePropertyV2Subsystem.h"
#include "LivingTownCafePropertyV2Scenario.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownCafeVenue.h"
#include "LivingTownCafeProjectionSubsystem.h"
#include "LivingTownLeaseSubsystem.h"
#include "LivingTownCafeSlot.h"
#include "../ThirdParty/CafePropertyV2.hpp"
#include "../ThirdParty/CafePropertyBackend.hpp"
#include "Engine/GameInstance.h"
#include "Engine/World.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Components/CapsuleComponent.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/Base64.h"
#include "HAL/FileManager.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Policies/CondensedJsonPrintPolicy.h"

namespace {
namespace P=living_town::cafe_property_v2;
namespace Backend=living_town::cafe_property_backend;
constexpr const TCHAR* CoreHash=TEXT("50adb86b5333436ff6af330ed02ca3b21b9aae0cc7f92c32d833dcdb61ec76ab");
constexpr const TCHAR* RosterHash=TEXT("fda4596387cffd0eec0cab7fb021e7950afc4c6e878467712949924a630f0d8b");
constexpr const TCHAR* ConfigHash=TEXT("d45f1b001e0177088757be4e45ee3a4910c5cd6b09b18128693058886f40637f");
constexpr int64 MaxEnvelopeBytes=8*1024*1024;
bool Requested(){return FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafePropertyV2"));}
FString Text(const std::string& S){return FString(UTF8_TO_TCHAR(S.c_str()));}
std::string Utf8(const FString& S){return std::string(TCHAR_TO_UTF8(*S));}
FString PersonaId(ELivingTownCafePropertyPersona Pn){return Pn==ELivingTownCafePropertyPersona::Aria?TEXT("aria"):TEXT("ben");}
bool ValidPersona(ELivingTownCafePropertyPersona Pn){return Pn==ELivingTownCafePropertyPersona::Aria||Pn==ELivingTownCafePropertyPersona::Ben;}
bool Keys(const FJsonObject& O,std::initializer_list<const TCHAR*> K){if(O.Values.Num()!=static_cast<int32>(K.size()))return false;for(const auto* S:K)if(!O.HasField(FStringView(S)))return false;return true;}
bool String(const FJsonObject& O,const TCHAR* Key,FString& Value){return O.HasTypedField<EJson::String>(Key)&&O.TryGetStringField(Key,Value);}
bool IntString(const FJsonObject& O,const TCHAR* Key,int64& Value){FString S;return String(O,Key,S)&&LexTryParseString(Value,*S)&&S==LexToString(Value);}
bool UIntString(const FJsonObject& O,const TCHAR* Key,uint64& Value){FString S;return String(O,Key,S)&&LexTryParseString(Value,*S)&&S==LexToString(Value);}
TArray<uint8> Bytes(const std::string& S){TArray<uint8> Out;Out.Append(reinterpret_cast<const uint8*>(S.data()),static_cast<int32>(S.size()));return Out;}
bool EnvelopeHash(const FJsonObject& O,FString& Hash){
    // Fixed field order and length prefixes bind the whole metadata+payload envelope,
    // independently of JSON object ordering. SHA256 is custody, not authentication.
    P::detail::Writer W;for(const TCHAR* K:{TEXT("format"),TEXT("version"),TEXT("capability"),TEXT("core_sha256"),TEXT("roster_sha256"),TEXT("config_sha256"),TEXT("binding_sha256"),TEXT("physical_scene_sha256"),TEXT("physical_qualification_sha256"),TEXT("ben_visual_sha256"),TEXT("owner_proxy_policy"),TEXT("clock"),TEXT("clock_remainder_double_bits"),TEXT("saved_persona_metadata"),TEXT("session_policy"),TEXT("payload_sha256"),TEXT("payload_base64")}){FString V;if(!String(O,K,V))return false;W.s(Utf8(FString(K)));W.s(Utf8(V));}return LivingTownCafeJournal::Sha256(Bytes(W.bytes),Hash);
}
bool SourceFile(const FString& Path,const TCHAR* Expected,TArray<uint8>& Data){FString H;const int64 Size=IFileManager::Get().FileSize(*Path);return Size>0&&Size<=2*1024*1024&&FFileHelper::LoadFileToArray(Data,*Path)&&LivingTownCafeJournal::Sha256(Data,H)&&H==Expected;}
bool AuthoredSources(FString& Error){
    const FString Folder=FPaths::ProjectContentDir()/TEXT("LivingTown");TArray<uint8> Data;
    if(!SourceFile(Folder/TEXT("PropertyV2PropertyRegistry.json"),ConfigHash,Data)){Error=TEXT("property_v2_exact_authored_property_source_required");return false;}
    if(!SourceFile(Folder/TEXT("PropertyV2AuthoredAgents.json"),RosterHash,Data)){Error=TEXT("property_v2_exact_authored_roster_source_required");return false;}
    FString Json;FFileHelper::BufferToString(Json,Data.GetData(),Data.Num());TSharedPtr<FJsonObject> O;const TArray<TSharedPtr<FJsonValue>>* Agents=nullptr;
    if(!LivingTownCafeJournal::HasUniqueObjectKeys(Json)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),O)||!O||!O->TryGetArrayField(TEXT("agents"),Agents)){Error=TEXT("authored_roster_invalid");return false;}
    int32 Aria=0,Ben=0;for(const auto& V:*Agents){if(!V||V->Type!=EJson::Object||!V->AsObject())continue;FString Id,Persona;const auto A=V->AsObject();if(!A->TryGetStringField(TEXT("id"),Id))continue;if(Id==TEXT("aria")||Id==TEXT("ben")){if(!A->TryGetStringField(TEXT("persona"),Persona)||Persona!=Id){Error=TEXT("authored_persona_identity_mismatch");return false;}if(Id==TEXT("aria"))++Aria;else ++Ben;}}
    if(Aria!=1||Ben!=1){Error=TEXT("two_unique_authored_personas_required");return false;}return true;
}
FLivingTownCafePropertyReceipt Refused(const FString& Why){FLivingTownCafePropertyReceipt R;R.Reason=Why;return R;}
P::Action Action(ELivingTownCafePropertyAction A){switch(A){case ELivingTownCafePropertyAction::OfferLease:return P::Action::offer_lease;case ELivingTownCafePropertyAction::OfferSale:return P::Action::offer_sale;case ELivingTownCafePropertyAction::Buy:return P::Action::buy;case ELivingTownCafePropertyAction::Lease:return P::Action::lease;case ELivingTownCafePropertyAction::EndLease:return P::Action::end_lease;}throw std::invalid_argument("unsupported_action");}
}

struct ULivingTownCafePropertyV2Subsystem::FState {P::Kernel Kernel;int64 Clock=0;};
void ULivingTownCafePropertyV2Subsystem::FStateDeleter::operator()(FState* Pn)const{delete Pn;}
ULivingTownCafePropertyV2Subsystem::ULivingTownCafePropertyV2Subsystem()=default;
ULivingTownCafePropertyV2Subsystem::~ULivingTownCafePropertyV2Subsystem()=default;
bool ULivingTownCafePropertyV2Subsystem::ShouldCreateSubsystem(UObject* Outer)const{return Super::ShouldCreateSubsystem(Outer)&&Backend::Select(Requested())==Backend::Backend::PropertyV2;}
bool ULivingTownCafePropertyV2Subsystem::DoesSupportWorldType(EWorldType::Type T)const{return T==EWorldType::Game||T==EWorldType::PIE;}
TStatId ULivingTownCafePropertyV2Subsystem::GetStatId()const{RETURN_QUICK_DECLARE_CYCLE_STAT(ULivingTownCafePropertyV2Subsystem,STATGROUP_Tickables);}
void ULivingTownCafePropertyV2Subsystem::Deinitialize(){DetachNativeSession();State.Reset();if(IsValid(Venue))Venue->Destroy();Venue=nullptr;bPrepared=false;Super::Deinitialize();}
bool ULivingTownCafePropertyV2Subsystem::PrepareScenario(FString& Error){
    Error.Reset();auto Fail=[&](const TCHAR* Why){Error=Why;Notice=Error;RefreshPresentation();return false;};
    UWorld* W=GetWorld();if(!IsInGameThread()||bPrepared||!W)return Fail(TEXT("single_game_thread_property_scenario_required"));
    if(!Backend::CanActivateV2(Requested(),W->GetAuthGameMode()&&W->GetAuthGameMode()->GetClass()==ALivingTownCafePropertyV2GameMode::StaticClass(),W->GetNetMode()==NM_Standalone,FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeWorker110DevelopmentPreview")),FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeLegacyV1"))))return Fail(TEXT("explicit_exclusive_property_v2_standalone_scenario_required"));
    if(!W->GetGameInstance()||W->GetGameInstance()->GetSubsystem<ULivingTownLeaseSubsystem>())return Fail(TEXT("legacy_v1_authority_must_not_exist_in_property_v2"));
    if(const auto* Old=W->GetSubsystem<ULivingTownCafeProjectionSubsystem>())if(Old->IsReady()||Old->IsScenePrepared())return Fail(TEXT("legacy_v1_projection_must_remain_unprepared"));
    if(!AuthoredSources(Error)){Notice=Error;RefreshPresentation();return false;}
    FLivingTownCafeBinding B;if(!FLivingTownCafeBinding::ReadQualifiedFile(FPaths::ProjectContentDir()/TEXT("LivingTown/CafeProjectionBinding.json"),B,Error)){Notice=Error;RefreshPresentation();return false;}
    auto* V=W->SpawnActor<ALivingTownCafeVenue>();if(!V||!V->BuildQualified(B,Error)){if(V)V->Destroy();Notice=Error;RefreshPresentation();return false;}
    FHitResult Floor;FCollisionQueryParams Q(SCENE_QUERY_STAT(PropertyV2ScenarioSpawn),true);const FVector Center=B.SpawnFeetCm+FVector(0,0,B.CapsuleHalfHeightCm);
    if(!B.FloorBoundsCm.IsInsideXY(B.SpawnFeetCm)||!V->FloorAt(B.SpawnFeetCm,Floor)||W->OverlapBlockingTestByChannel(Center,FQuat::Identity,ECC_Pawn,FCollisionShape::MakeCapsule(B.CapsuleRadiusCm,B.CapsuleHalfHeightCm),Q)){V->Destroy();return Fail(TEXT("qualified_property_scenario_spawn_refused"));}
    // Construct the sole book only after source, scenario, geometry and v1 absence checks.
    State.Reset(new FState());Binding=MoveTemp(B);Venue=V;bPrepared=true;ClockRemainder=0;Notice=TEXT("New-world property v2: select Aria or Ben, then walk to the counter.");RefreshPresentation();return true;
}
void ULivingTownCafePropertyV2Subsystem::DetachNativeSession(){SessionController.Reset();SessionPawn.Reset();RefreshPresentation();}
bool ULivingTownCafePropertyV2Subsystem::BindNativeSession(ALivingTownCafePropertyV2Controller* PC,ACharacter* Pawn,FString& Error){
    Error.Reset();if(!IsInGameThread()||!bPrepared||!State||!PC||!Pawn||PC!=GetWorld()->GetFirstPlayerController()||PC->GetWorld()!=GetWorld()||Pawn->GetWorld()!=GetWorld()||PC->GetPawn()!=Pawn||Pawn->GetController()!=PC||!PC->HasNativePersona()||!ValidPersona(PC->GetNativePersona())){Error=TEXT("native_persona_possession_required");return false;}
    const auto* Ben=Cast<ALivingTownCafeCharacter>(Pawn);const auto* Owner=Cast<ALivingTownCafePropertyOwnerProxy>(Pawn);
    if((PC->GetNativePersona()==ELivingTownCafePropertyPersona::Ben&&(!Ben||!Ben->HasQualifiedVisual()))||(PC->GetNativePersona()==ELivingTownCafePropertyPersona::Aria&&(!Owner||!Owner->IsFunctionalOwnerConfigured()))){Error=TEXT("persona_and_native_pawn_class_must_match");return false;}
    if(!FMath::IsNearlyEqual(Pawn->GetCapsuleComponent()->GetScaledCapsuleRadius(),Binding.CapsuleRadiusCm,.01f)||!FMath::IsNearlyEqual(Pawn->GetCapsuleComponent()->GetScaledCapsuleHalfHeight(),Binding.CapsuleHalfHeightCm,.01f)){Error=TEXT("persona_capsule_binding_mismatch");return false;}
    SessionController=PC;SessionPawn=Pawn;Notice=PC->GetNativePersona()==ELivingTownCafePropertyPersona::Aria?TEXT("Aria owner role selected. Functional proxy only; final Aria art unqualified."):TEXT("Ben buyer role selected. Walk to the physical counter.");RefreshPresentation();return true;
}
bool ULivingTownCafePropertyV2Subsystem::ObserveCounter(bool& Reach,FString& Why)const{
    Reach=false;Why.Reset();const auto* PC=SessionController.Get();const auto* Pawn=SessionPawn.Get();UWorld* W=GetWorld();
    if(!bPrepared||!State||!W||!PC||!Pawn||!PC->HasNativePersona()||PC!=W->GetFirstPlayerController()||PC->GetPawn()!=Pawn||Pawn->GetController()!=PC||PC->GetViewTarget()!=Pawn||!IsValid(Venue)||!Venue->IsQualified()){Why=TEXT("native_persona_scene_binding_lost");return false;}
    const FVector Feet=Pawn->GetActorLocation()-FVector(0,0,Pawn->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());FHitResult Floor;
    if(!Pawn->GetCharacterMovement()->IsMovingOnGround()||!Binding.FloorBoundsCm.IsInsideXY(Feet)||!Venue->FloorAt(Feet,Floor,Pawn)){Why=TEXT("stand_on_the_actual_cafe_floor");return true;}
    const FVector Target=Binding.CounterUsePointCm;FVector Origin;const auto* Ben=Cast<ALivingTownCafeCharacter>(Pawn);
    if(PC->GetNativePersona()==ELivingTownCafePropertyPersona::Ben){if(!Ben||!Ben->HasQualifiedVisual()){Why=TEXT("qualified_Ben_visual_lost");return false;}Origin=Ben->InteractionHand();}
    else {const auto* Owner=Cast<ALivingTownCafePropertyOwnerProxy>(Pawn);if(!Owner||!Owner->IsFunctionalOwnerConfigured()){Why=TEXT("functional_owner_proxy_lost");return false;}const float Distance=Owner->GetCapsuleComponent()->GetClosestPointOnCollision(Target,Origin);if(!FMath::IsFinite(Distance)||Distance<0){Why=TEXT("actual_owner_capsule_query_unavailable");return true;}}
    if(Origin.ContainsNaN()||FVector::Dist(Origin,Target)>Binding.ReachCm){Why=TEXT("walk_closer_to_the_counter");return true;}
    if(FVector::DotProduct(Pawn->GetActorForwardVector().GetSafeNormal2D(),(Target-Pawn->GetActorLocation()).GetSafeNormal2D())<.15){Why=TEXT("face_the_counter");return true;}
    FCollisionQueryParams Q(SCENE_QUERY_STAT(PropertyV2ActualCounter),true);Q.AddIgnoredActor(Pawn);FVector Eyes;FRotator Rotation;Pawn->GetActorEyesViewPoint(Eyes,Rotation);FHitResult NearHit,EyeHit;
    if(!W->LineTraceSingleByChannel(NearHit,Origin,Target,ECC_Visibility,Q)||!Venue->IsCounterComponent(NearHit.GetComponent())||!W->LineTraceSingleByChannel(EyeHit,Eyes,Target,ECC_Visibility,Q)||!Venue->IsCounterComponent(EyeHit.GetComponent())){Why=TEXT("counter_line_of_sight_blocked");return true;}
    Reach=true;Why=TEXT("counter_reachable");return true;
}
FLivingTownCafePropertyReceipt ULivingTownCafePropertyV2Subsystem::SubmitCommand(const FLivingTownCafePropertyCommand& C){
    if(!IsInGameThread()||!bPrepared||!State)return Refused(TEXT("property_v2_not_prepared"));bool Reach=false;FString Why;if(!ObserveCounter(Reach,Why))return Refused(Why);
    try{P::Kernel Candidate=State->Kernel;const std::string Actor=Utf8(PersonaId(SessionController->GetNativePersona()));const P::Context At{Actor,Actor,"cafe","1f","cafe1f_counter",State->Clock,Reach};const auto R=Candidate.execute({Utf8(C.RequestId),Utf8(C.PropertyId),Action(C.Action)},At);
        if(Candidate.events().size()+(Candidate.lease().active?1U:0U)>P::max_events)return Refused(TEXT("journal_capacity_reserving_expiry"));
        State->Kernel=std::move(Candidate);FLivingTownCafePropertyReceipt Out;Out.bAccepted=R.ok;Out.bAlreadyApplied=R.already_applied;Out.Reason=Text(R.reason);Out.EventId=R.event_id;Notice=R.ok?TEXT("Property action recorded; balances and rights updated."):TEXT("Property action refused: ")+Out.Reason;if(!Reach)Notice+=TEXT(" / ")+Why;RefreshPresentation();return Out;
    }catch(const std::exception&){return Refused(TEXT("property_v2_authority_exception"));}
}
bool ULivingTownCafePropertyV2Subsystem::AdvanceNaturalClockTo(int64 Tick,FString& Error){
    Error.Reset();if(!State||Tick<State->Clock||Tick>P::max_tick){Error=TEXT("invalid_natural_clock");return false;}
    P::Kernel Candidate=State->Kernel;const auto Due=Candidate.expiry_request(Tick);if(Due&&!Candidate.execute(*Due,{"town","town","","","",Tick,false}).ok){Error=TEXT("natural_expiry_refused");return false;}
    State->Kernel=std::move(Candidate);State->Clock=Tick;return true;
}
void ULivingTownCafePropertyV2Subsystem::Tick(float Delta){
    Super::Tick(Delta);if(!bPrepared||!State||!GetWorld()||GetWorld()->IsPaused())return;
    if(!FMath::IsFinite(Delta)||Delta<0||Delta>3600){Notice=TEXT("Natural clock refused invalid world delta.");bPrepared=false;RefreshPresentation();return;}
    ClockRemainder+=double(Delta);const int64 Whole=int64(FMath::FloorToDouble(ClockRemainder));FString Error;
    if(Whole>0){if(State->Clock>P::max_tick-Whole||!AdvanceNaturalClockTo(State->Clock+Whole,Error)){Notice=TEXT("Natural property clock refused: ")+Error;bPrepared=false;RefreshPresentation();return;}ClockRemainder-=double(Whole);}
    PresentationElapsed+=Delta;if(PresentationElapsed>=.1f){PresentationElapsed=FMath::Fmod(PresentationElapsed,.1f);RefreshPresentation();}
}
void ULivingTownCafePropertyV2Subsystem::RefreshPresentation(){
    Presentation={};Presentation.bPrepared=bPrepared;Presentation.Notice=Notice;Presentation.Prompt=TEXT("Property v2 unavailable: exact scenario/source binding required.");
    if(!bPrepared||!State)return;Presentation.bSessionReady=SessionController.IsValid()&&SessionController->HasNativePersona()&&SessionPawn.IsValid();
    Presentation.Persona=Presentation.bSessionReady?PersonaId(SessionController->GetNativePersona()):TEXT("choose persona");Presentation.Owner=Text(State->Kernel.title().owner);Presentation.Operator=Text(State->Kernel.operator_at(State->Clock));Presentation.AriaCoins=State->Kernel.coin("aria");Presentation.BenCoins=State->Kernel.coin("ben");Presentation.Clock=State->Clock;Presentation.EventCount=int64(State->Kernel.events().size());Presentation.LeaseEnd=State->Kernel.lease().active?State->Kernel.lease().end:-1;
    const auto& O=State->Kernel.offer();Presentation.Offer=O.present?Text(O.kind):TEXT("no owner listing");FString Why;ObserveCounter(Presentation.bReachable,Why);Presentation.Prompt=Presentation.bReachable?TEXT("Counter: O sell offer | L rent offer | B buy | E lease | R end"):Why;
    Presentation.Lines={TEXT("Native cafe property v2 / one exclusive new-world ledger"),TEXT("Playing: ")+Presentation.Persona+TEXT(" | Owner: ")+Presentation.Owner+TEXT(" | Operator: ")+Presentation.Operator,FString::Printf(TEXT("Aria %lld coins / Ben %lld coins / tick %lld / events %lld"),(long long)Presentation.AriaCoins,(long long)Presentation.BenCoins,(long long)Presentation.Clock,(long long)Presentation.EventCount),TEXT("Owner listing: ")+Presentation.Offer,TEXT("Ground-floor commercial unit only; upstairs permissions unchanged."),TEXT("Aria functional proxy: final avatar/contact art remains unqualified.")};
}
FString ULivingTownCafePropertyV2Subsystem::SlotPath()const{return FPaths::ProjectSavedDir()/TEXT("CafePropertyV2/CafePropertyTitleV2.slot.json");}
bool ULivingTownCafePropertyV2Subsystem::EncodeJournal(FString& Json,FString& Error)const{
    Json.Reset();Error.Reset();if(!IsInGameThread()||!bPrepared||!State||!SessionController.IsValid()||!SessionController->HasNativePersona()){Error=TEXT("source_bound_native_property_session_required");return false;}bool Reach=false;FString Why;if(!ObserveCounter(Reach,Why)){Error=Why;return false;}
    const auto Payload=Bytes(State->Kernel.save_bytes());FString Hash;if(Payload.Num()>int32(P::max_journal_bytes)||!LivingTownCafeJournal::Sha256(Payload,Hash)){Error=TEXT("property_payload_hash_failed");return false;}
    uint64 FractionBits=0;static_assert(sizeof(FractionBits)==sizeof(ClockRemainder));FMemory::Memcpy(&FractionBits,&ClockRemainder,sizeof(FractionBits));
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("format"),TEXT("LivingTown.CafePropertyTitleJournal"));O->SetStringField(TEXT("version"),TEXT("2"));O->SetStringField(TEXT("capability"),TEXT("cafe.property_title.v2"));O->SetStringField(TEXT("core_sha256"),CoreHash);O->SetStringField(TEXT("roster_sha256"),RosterHash);O->SetStringField(TEXT("config_sha256"),ConfigHash);
    O->SetStringField(TEXT("binding_sha256"),Binding.BindingFileSha256);O->SetStringField(TEXT("physical_scene_sha256"),Binding.PhysicalSceneSha256);O->SetStringField(TEXT("physical_qualification_sha256"),Binding.PhysicalQualificationSha256);O->SetStringField(TEXT("ben_visual_sha256"),Binding.VisualSha256);O->SetStringField(TEXT("owner_proxy_policy"),TEXT("functional_capsule_query_v1_art_unqualified"));O->SetStringField(TEXT("clock"),LexToString(State->Clock));O->SetStringField(TEXT("clock_remainder_double_bits"),LexToString(FractionBits));O->SetStringField(TEXT("saved_persona_metadata"),PersonaId(SessionController->GetNativePersona()));O->SetStringField(TEXT("session_policy"),TEXT("live_native_controller_identity_and_position_unchanged"));O->SetStringField(TEXT("payload_sha256"),Hash);O->SetStringField(TEXT("payload_base64"),FBase64::Encode(Payload));
    FString EnvelopeSha;if(!EnvelopeHash(*O,EnvelopeSha)){Error=TEXT("property_envelope_sha_failed");return false;}O->SetStringField(TEXT("envelope_sha256"),EnvelopeSha);
    if(!FJsonSerializer::Serialize(O,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Json))||Json.Len()>MaxEnvelopeBytes){Error=TEXT("property_envelope_encoding_failed");return false;}return true;
}
bool ULivingTownCafePropertyV2Subsystem::LoadJournal(const FString& Json,FString& Error){
    Error.Reset();auto Fail=[&](const TCHAR* Why){Error=Why;return false;};if(!IsInGameThread()||!bPrepared||!State||!SessionController.IsValid()||!SessionController->HasNativePersona())return Fail(TEXT("source_bound_native_property_session_required"));bool Reach=false;FString Why;if(!ObserveCounter(Reach,Why)){Error=Why;return false;}
    if(Json.Len()>MaxEnvelopeBytes||!LivingTownCafeJournal::HasUniqueObjectKeys(Json))return Fail(TEXT("invalid_or_duplicate_property_envelope"));TSharedPtr<FJsonObject> O;if(!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),O)||!O)return Fail(TEXT("invalid_property_json"));
    if(!Keys(*O,{TEXT("format"),TEXT("version"),TEXT("capability"),TEXT("core_sha256"),TEXT("roster_sha256"),TEXT("config_sha256"),TEXT("binding_sha256"),TEXT("physical_scene_sha256"),TEXT("physical_qualification_sha256"),TEXT("ben_visual_sha256"),TEXT("owner_proxy_policy"),TEXT("clock"),TEXT("clock_remainder_double_bits"),TEXT("saved_persona_metadata"),TEXT("session_policy"),TEXT("payload_sha256"),TEXT("payload_base64"),TEXT("envelope_sha256")}))return Fail(TEXT("unsupported_property_envelope_fields"));
    FString RecordedEnvelopeSha,ActualEnvelopeSha;if(!String(*O,TEXT("envelope_sha256"),RecordedEnvelopeSha)||!EnvelopeHash(*O,ActualEnvelopeSha)||RecordedEnvelopeSha!=ActualEnvelopeSha)return Fail(TEXT("property_envelope_sha_mismatch"));
    auto Equal=[&](const TCHAR* K,const FString& Expected){FString V;return String(*O,K,V)&&V==Expected;};
    if(!Equal(TEXT("format"),TEXT("LivingTown.CafePropertyTitleJournal"))||!Equal(TEXT("version"),TEXT("2"))||!Equal(TEXT("capability"),TEXT("cafe.property_title.v2"))||!Equal(TEXT("core_sha256"),CoreHash)||!Equal(TEXT("roster_sha256"),RosterHash)||!Equal(TEXT("config_sha256"),ConfigHash)||!Equal(TEXT("binding_sha256"),Binding.BindingFileSha256)||!Equal(TEXT("physical_scene_sha256"),Binding.PhysicalSceneSha256)||!Equal(TEXT("physical_qualification_sha256"),Binding.PhysicalQualificationSha256)||!Equal(TEXT("ben_visual_sha256"),Binding.VisualSha256)||!Equal(TEXT("owner_proxy_policy"),TEXT("functional_capsule_query_v1_art_unqualified"))||!Equal(TEXT("session_policy"),TEXT("live_native_controller_identity_and_position_unchanged")))return Fail(TEXT("unsupported_property_version_or_provenance"));
    FString Persona,Encoded,ExpectedHash;if(!String(*O,TEXT("saved_persona_metadata"),Persona)||(Persona!=TEXT("aria")&&Persona!=TEXT("ben"))||!String(*O,TEXT("payload_base64"),Encoded)||!String(*O,TEXT("payload_sha256"),ExpectedHash))return Fail(TEXT("invalid_persona_or_payload_fields"));
    TArray<uint8> Payload;FString ActualHash;if(!FBase64::Decode(Encoded,Payload)||Payload.IsEmpty()||Payload.Num()>int32(P::max_journal_bytes)||FBase64::Encode(Payload)!=Encoded||!LivingTownCafeJournal::Sha256(Payload,ActualHash)||ActualHash!=ExpectedHash)return Fail(TEXT("property_payload_bytes_or_sha_mismatch"));
    int64 Clock=0;uint64 FractionBits=0;double Fraction=0;if(!IntString(*O,TEXT("clock"),Clock)||Clock<0||Clock>P::max_tick||!UIntString(*O,TEXT("clock_remainder_double_bits"),FractionBits))return Fail(TEXT("invalid_saved_clock"));FMemory::Memcpy(&Fraction,&FractionBits,sizeof(Fraction));if(!FMath::IsFinite(Fraction)||Fraction<0||Fraction>=1)return Fail(TEXT("invalid_saved_fraction"));
    P::Kernel Candidate;const std::string Raw(reinterpret_cast<const char*>(Payload.GetData()),static_cast<size_t>(Payload.Num()));if(!Candidate.restore_bytes(Raw)||Clock<Candidate.last_tick()||(Candidate.lease().active&&Clock>=Candidate.lease().end)||Candidate.events().size()+(Candidate.lease().active?1U:0U)>P::max_events)return Fail(TEXT("strict_property_replay_or_clock_mismatch"));
    // Actor identity/position are live native state. Save metadata never authorizes or moves a pawn.
    State->Kernel=std::move(Candidate);State->Clock=Clock;ClockRemainder=Fraction;Notice=TEXT("Validated property journal loaded; current persona and position unchanged.");RefreshPresentation();return true;
}
bool ULivingTownCafePropertyV2Subsystem::SaveSlot(FString& Error,FString* SavedSha)const{
    FString Json;if(!EncodeJournal(Json,Error)||!LivingTownCafeSlot::WriteAtomic(SlotPath(),Json,Error))return false;TArray<uint8> Written;FString Hash,Readback;if(!FFileHelper::LoadFileToArray(Written,*SlotPath())||!FFileHelper::LoadFileToString(Readback,*SlotPath())||Readback!=Json||!LivingTownCafeJournal::Sha256(Written,Hash)){Error=TEXT("atomic_property_slot_final_readback_or_sha_failed");return false;}if(SavedSha)*SavedSha=Hash;return true;
}
bool ULivingTownCafePropertyV2Subsystem::LoadSlot(FString& Error){if(!IsInGameThread()){Error=TEXT("wrong_thread");return false;}const FString Path=SlotPath();const int64 Size=IFileManager::Get().FileSize(*Path);if(Size<=0||Size>MaxEnvelopeBytes){Error=TEXT("property_slot_missing_or_oversize");return false;}FString Json;if(!FFileHelper::LoadFileToString(Json,*Path)){Error=TEXT("property_slot_read_failed");return false;}return LoadJournal(Json,Error);}
