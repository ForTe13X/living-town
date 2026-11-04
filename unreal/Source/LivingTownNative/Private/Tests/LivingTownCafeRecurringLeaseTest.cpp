#include "LivingTownCafeWorldV3Subsystem.h"
#include "LivingTownCafeWorldV3Scenario.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownLeaseSubsystem.h"
#include "LivingTownCafePropertyV2Subsystem.h"
#include "../../ThirdParty/CafeWorldV3Envelope.hpp"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Tests/AutomationCommon.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "GameFramework/Character.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Components/CapsuleComponent.h"
#include "Kismet/GameplayStatics.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/Base64.h"
#include "HAL/PlatformTime.h"
#include "HAL/FileManager.h"
#include "InputKeyEventArgs.h"
#include "InputCoreTypes.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
namespace {
namespace R=living_town::cafe_world_v3;
bool RentObject(const FString& Json,TSharedPtr<FJsonObject>& O){return LivingTownCafeJournal::HasUniqueObjectKeys(Json)&&FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),O)&&O.IsValid();}
bool RentEnvelope(const FString& Json,R::CareEnvelope& E){TSharedPtr<FJsonObject> O;FString B;TArray<uint8> Data;if(!RentObject(Json,O)||!O->TryGetStringField(TEXT("payload_base64"),B)||!FBase64::Decode(B,Data)||Data.IsEmpty())return false;const auto Parsed=R::decode_care_envelope_document(std::string(reinterpret_cast<const char*>(Data.GetData()),size_t(Data.Num())));if(!Parsed)return false;E=*Parsed;return true;}
bool RentWorld(const FString& Json,R::Kernel& World){R::CareEnvelope E;return RentEnvelope(Json,E)&&World.restore_bytes(E.world_payload);}
bool RentRehash(TSharedPtr<FJsonObject> O,FString& Json){R::detail::Writer W;for(const TCHAR* Key:{TEXT("format"),TEXT("version"),TEXT("capability"),TEXT("source_sha256"),TEXT("payload_sha256"),TEXT("payload_base64")}){FString V;if(!O->TryGetStringField(Key,V))return false;W.s(std::string(TCHAR_TO_UTF8(Key)));W.s(std::string(TCHAR_TO_UTF8(*V)));}TArray<uint8> Data;Data.Append(reinterpret_cast<const uint8*>(W.bytes.data()),int32(W.bytes.size()));FString H;if(!LivingTownCafeJournal::Sha256(Data,H))return false;O->SetStringField(TEXT("envelope_sha256"),H);return FJsonSerializer::Serialize(O.ToSharedRef(),TJsonWriterFactory<>::Create(&Json));}
// A replayed PUBLIC-API save fixture, not elapsed-time/pose observation. The
// ensuing live interval has no clock setters or shortened agreement terms.
bool NearDue(const FString& Actual,int32 AdditionalPaidPeriods,FString& Result){
 R::CareEnvelope E;TSharedPtr<FJsonObject> O;if(!RentEnvelope(Actual,E)||!RentObject(Actual,O))return false;
 R::Kernel World;R::care::ResidentUse Use("ben");const auto Care=R::decode_care_document(E.care_payload);
 if(!World.restore_bytes(E.world_payload)||!Care||!Use.restore_state(*Care)||Use.active()||!World.recurring_lease())return false;
 for(int32 N=0;N<AdditionalPaidPeriods;++N){const auto Due=World.lease().end;if(!World.reconcile_property_until(Due).ok||!Use.advance_idle_to(Due)||!World.recurring_lease())return false;}
 const auto Tick=World.lease().end-1;if(!Use.advance_idle_to(Tick))return false;
 double Fraction=.25;std::uint64_t Bits=0;FMemory::Memcpy(&Bits,&Fraction,sizeof(Bits));const auto Encoded=R::save_care_envelope(World,Use,E.bindings,{Tick,Bits},"ben");if(!Encoded)return false;
 TArray<uint8> Bytes;Bytes.Append(reinterpret_cast<const uint8*>(Encoded->data()),int32(Encoded->size()));FString Hash;if(!LivingTownCafeJournal::Sha256(Bytes,Hash))return false;
 O->SetStringField(TEXT("payload_base64"),FBase64::Encode(Bytes));O->SetStringField(TEXT("payload_sha256"),Hash);return RentRehash(O,Result);
}
class FRecurringLeaseJourney final:public IAutomationLatentCommand {
 FAutomationTestBase* Test;FLivingTownCafeBinding Binding;TArray<FVector> Route;
 double Deadline=FPlatformTime::Seconds()+180,Since=-1;int32 Stage=0,Waypoint=1;
 FString InitialAgreement,PaidAgreement;int64 FirstDue=0,PausedClock=0;TWeakObjectPtr<UWorld> OwnedWorld;bool bOwnPause=false,bDone=false;
 TWeakObjectPtr<ALivingTownCafeWorldV3Controller> PressedController;FKey Pressed;
 bool Need(bool Value,const TCHAR* Why){if(!Value){Test->AddError(Why);bDone=true;}return Value;}
 void Release(){if(Pressed.IsValid())if(auto* PC=PressedController.Get())PC->InputKey(FInputKeyEventArgs::CreateSimulated(Pressed,IE_Released,0.f));Pressed=FKey();}
 void Press(ALivingTownCafeWorldV3Controller* PC,FKey Key){Release();PressedController=PC;Pressed=Key;PC->InputKey(FInputKeyEventArgs::CreateSimulated(Key,IE_Pressed,1.f));}
 bool Walk(ALivingTownCafeWorldV3Controller* PC,ACharacter* Pawn,ULivingTownCafeWorldV3Subsystem* A){
  const FVector Feet=Pawn->GetActorLocation()-FVector(0,0,Pawn->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());
  if(Waypoint<Route.Num()){FVector Delta=Route[Waypoint]-Feet;Delta.Z=0;if(Delta.Size2D()>2){PC->SetControlRotation(Delta.Rotation());Pawn->AddMovementInput(Delta.GetSafeNormal2D(),1);return false;}Pawn->GetCharacterMovement()->StopMovementImmediately();++Waypoint;return false;}
  Pawn->SetActorRotation(FRotator(0,(Binding.CounterUsePointCm-Pawn->GetActorLocation()).Rotation().Yaw,0));return A->GetPresentation().bReachable;
 }
 bool Read(ULivingTownCafeWorldV3Subsystem* A,FString& Json,R::Kernel& K){FString Error;return A->EncodeJournal(Json,Error)&&RentWorld(Json,K);}
public:
 FRecurringLeaseJourney(FAutomationTestBase* T,const FLivingTownCafeBinding& B,const TArray<FVector>& P):Test(T),Binding(B),Route(P){}
 virtual ~FRecurringLeaseJourney(){Release();if(bOwnPause)if(auto* W=OwnedWorld.Get())UGameplayStatics::SetGamePaused(W,false);}
 virtual bool Update()override {
  if(bDone)return true;if(!Need(FPlatformTime::Seconds()<Deadline,TEXT("Recurring lease native journey timed out")))return true;
  UWorld* W=nullptr;int32 Count=0;for(const auto& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::PIE||C.WorldType==EWorldType::Game)){W=C.World();++Count;}
  if(!Need(Count<=1,TEXT("One actual world required"))||!W||!W->HasBegunPlay())return bDone;
  auto* Mode=W->GetAuthGameMode<ALivingTownCafeWorldV3GameMode>();auto* A=W->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();auto* PC=Cast<ALivingTownCafeWorldV3Controller>(W->GetFirstPlayerController());auto* Pawn=PC?Cast<ACharacter>(PC->GetPawn()):nullptr;
  if(!Mode||!A||!A->IsPrepared()||!PC||!PC->HasNativePersona()||!Pawn||!Pawn->GetCharacterMovement()->IsMovingOnGround())return false;
  if(!Need(W->GetNetMode()==NM_Standalone&&W->GetGameInstance()&&!W->GetGameInstance()->GetSubsystem<ULivingTownLeaseSubsystem>()&&!W->GetSubsystem<ULivingTownCafePropertyV2Subsystem>(),TEXT("Sole actual WorldV3 authority required")))return true;
  OwnedWorld=W;const double Now=FPlatformTime::Seconds();const auto V=A->GetPresentation();FString Error,Json;R::Kernel K;
  if(Stage==0){if(!Need(Mode->SelectPersona(PC,ELivingTownCafeWorldPersona::Aria,Error),TEXT("Actual authored owner possession")))return true;Stage=1;return false;}
  if(Stage==1){if(!Walk(PC,Pawn,A))return false;Press(PC,EKeys::N);Stage=2;return false;}
  if(Stage==2){Release();if(!V.bRecurringOffer)return false;if(!Need(V.AriaCoins==12&&V.BenCoins==12&&V.ListingLabel.Contains(TEXT("4 coins / 12 min")),TEXT("Owner input opens explicit terms without payment")))return true;if(!Need(Mode->SelectPersona(PC,ELivingTownCafeWorldPersona::Ben,Error),TEXT("Actual Ben possession")))return true;Waypoint=1;Stage=3;return false;}
  if(Stage==3){if(!Walk(PC,Pawn,A))return false;Press(PC,EKeys::K);Stage=4;return false;}
  if(Stage==4){Release();if(!V.bRecurringLease)return false;if(!Need(V.AriaCoins==16&&V.BenCoins==8&&V.Operator==TEXT("ben")&&Read(A,InitialAgreement,K)&&K.recurring_lease(),TEXT("Actual K acceptance pays once and grants operation")))return true;FirstDue=V.RentDueTick;FString Near;if(!Need(NearDue(InitialAgreement,0,Near)&&A->LoadJournal(Near,Error),TEXT("Legitimate paired near-due return-to-save")))return true;Since=Now;Stage=5;return false;}
  if(Stage==5){if(V.Clock<FirstDue||Now-Since<1)return false;if(!Need(V.AriaCoins==20&&V.BenCoins==4&&V.Operator==TEXT("ben")&&V.RentDueTick==FirstDue+720&&Read(A,PaidAgreement,K),TEXT("Natural elapsed tick transfers one due rent and extends agreement")))return true;int32 Paid=0;for(const auto& E:K.events())if(E.type=="property_rent_paid")++Paid;if(!Need(Paid==1,TEXT("Exactly one real rent receipt")))return true;if(!Need(A->SaveSlot(Error)&&A->LoadSlot(Error),TEXT("Actual current paired atomic save/readback/load")))return true;PausedClock=A->GetPresentation().Clock;Since=Now;if(!Need(UGameplayStatics::SetGamePaused(W,true),TEXT("Actual pause")))return true;bOwnPause=true;Stage=6;return false;}
  if(Stage==6){if(Now-Since<1)return false;if(!Need(V.Clock==PausedClock&&V.AriaCoins==20&&V.BenCoins==4,TEXT("Pause cannot bill or advance rent")))return true;UGameplayStatics::SetGamePaused(W,false);bOwnPause=false;Since=Now;Stage=7;return false;}
  if(Stage==7){if(Now-Since<1)return false;if(!Need(V.AriaCoins==20&&V.BenCoins==4,TEXT("Paid restore/resume cannot bill twice")))return true;Press(PC,EKeys::R);Stage=8;return false;}
  if(Stage==8){Release();if(V.bRecurringLease)return false;if(!Need(V.Operator==TEXT("aria")&&V.AriaCoins==20&&V.BenCoins==4,TEXT("Actual surrender returns operation without new payment")))return true;FString Near;if(!Need(NearDue(PaidAgreement,1,Near)&&A->LoadJournal(Near,Error),TEXT("Legitimate public-API no-funds near-due branch")))return true;FirstDue=A->GetPresentation().RentDueTick;Since=Now;Stage=9;return false;}
  if(Stage==9){if(V.Clock<FirstDue||Now-Since<1)return false;if(!Need(!V.bRecurringLease&&V.Operator==TEXT("aria")&&V.AriaCoins==24&&V.BenCoins==0&&Read(A,Json,K)&&!K.lease().active,TEXT("Unfunded term ends naturally without invented money")))return true;int32 Paid=0;for(const auto& E:K.events())if(E.type=="property_rent_paid")++Paid;if(!Need(Paid==2&&K.events().back().type=="property_lease_ended"&&K.events().back().note=="rent_unpaid",TEXT("Nonpayment has an end receipt and no third pay")))return true;
   if(!Need(!V.bMealAvailable,TEXT("This journey must not install an eating provider")))return true;FLivingTownCafeMealCommand Meal;Meal.RequestId=TEXT("rent/native/no-provider");Meal.ExpectedRevision=V.Revision;const auto Refused=PC->RequestMeal(Meal);const auto After=A->GetPresentation();if(!Need(!Refused.bAccepted&&After.AriaCoins==24&&After.BenCoins==0&&After.Stock==V.Stock,TEXT("No-provider meal remains refused without charge/stock effect")))return true;
   const FString Dir=FPaths::ProjectSavedDir()/TEXT("CafeWorldV3");IFileManager::Get().MakeDirectory(*Dir,true);auto Receipt=MakeShared<FJsonObject>();Receipt->SetStringField(TEXT("status"),TEXT("PASS_ACTUAL_N_K_R_INPUT_AND_NATURAL_DUE_RETURN_TO_SAVE"));Receipt->SetStringField(TEXT("fixture_scope"),TEXT("Near-due saves generated by public Kernel/care APIs from actual signed native agreement; no elapsed-time claim before reload"));Receipt->SetBoolField(TEXT("OS_keyboard_or_pixels_claimed"),false);Receipt->SetNumberField(TEXT("final_aria_coins"),24);Receipt->SetNumberField(TEXT("final_ben_coins"),0);FString Evidence;FJsonSerializer::Serialize(Receipt,TJsonWriterFactory<>::Create(&Evidence));if(!Need(FFileHelper::SaveStringToFile(Evidence,*(Dir/TEXT("RecurringLeaseJourney.json"))),TEXT("Native journey receipt saved")))return true;bDone=true;return true;
  }
  return false;
 }
};
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafeRecurringLeaseJourney,"LivingTown.WorldV3.RecurringLeaseJourney",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafeRecurringLeaseJourney::RunTest(const FString&){
 if(!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeWorldV3"))||!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeRecurringLeaseJourney"))){AddError(TEXT("Explicit exclusive WorldV3 recurring journey opt-in required"));return false;}
 const FString Folder=FPaths::ProjectContentDir()/TEXT("LivingTown");FLivingTownCafeBinding B;FString Error,Json,Hash;TArray<uint8> Bytes;TSharedPtr<FJsonObject> O;const TArray<TSharedPtr<FJsonValue>>* Points=nullptr;TArray<FVector> Route;
 if(!FLivingTownCafeBinding::ReadQualifiedFile(Folder/TEXT("CafeProjectionBinding.json"),B,Error)||!FFileHelper::LoadFileToArray(Bytes,*(Folder/TEXT("CafeJourneyRoute.json")))||!LivingTownCafeJournal::Sha256(Bytes,Hash)||Hash!=TEXT("38d98ee0c968647be6a1a89eac2abfe7c4b8a65b8732248f62fd3e7f54113846")||!FFileHelper::LoadFileToString(Json,*(Folder/TEXT("CafeJourneyRoute.json")))||!RentObject(Json,O)||!O->TryGetArrayField(TEXT("route_feet_cm"),Points)||Points->Num()!=3){AddError(TEXT("Qualified actual cafe route and binding required"));return false;}
 for(const auto& V:*Points){if(!V||V->Type!=EJson::Array||V->AsArray().Num()!=3){AddError(TEXT("Invalid route"));return false;}const auto& P=V->AsArray();Route.Add(FVector(P[0]->AsNumber(),P[1]->AsNumber(),P[2]->AsNumber()));}
 if(!Route[0].Equals(B.SpawnFeetCm,.1)||!AutomationOpenMap(TEXT("/Engine/Maps/Entry"),true))return false;
 ADD_LATENT_AUTOMATION_COMMAND(FRecurringLeaseJourney(this,B,Route));return true;
}

namespace {
class FLegacyCafeImport final:public IAutomationLatentCommand {
 FAutomationTestBase* Test;double Deadline=FPlatformTime::Seconds()+120;
 bool Need(bool V,const TCHAR* Why){if(!V)Test->AddError(Why);return V;}
public:
 explicit FLegacyCafeImport(FAutomationTestBase* T):Test(T){}
 virtual bool Update()override {
  if(!Need(FPlatformTime::Seconds()<Deadline,TEXT("Legacy native import session timed out")))return true;
  UWorld* World=nullptr;int32 Count=0;for(const auto& C:GEngine->GetWorldContexts())if(C.World()&&(C.WorldType==EWorldType::PIE||C.WorldType==EWorldType::Game)){World=C.World();++Count;}
  if(!Need(Count<=1,TEXT("One actual legacy import consumer world required"))||!World||!World->HasBegunPlay())return Count>1;
  auto* A=World->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();auto* PC=Cast<ALivingTownCafeWorldV3Controller>(World->GetFirstPlayerController());if(!A||!A->IsPrepared()||!PC||!PC->GetPawn())return false;
  const FString Path=FPaths::ProjectSavedDir()/TEXT("CafeWorldV3/CafeWorldMealCareV4.slot.json");FString Old,Error,Before,After;R::CareEnvelope Source;TArray<uint8> OldBytes;
  if(!Need(FFileHelper::LoadFileToString(Old,*Path)&&FFileHelper::LoadFileToArray(OldBytes,*Path)&&RentEnvelope(Old,Source)&&Source.version=="4",TEXT("Actual accepted old V4 native slot must be staged untouched")))return true;
  FString OldSha;if(!Need(LivingTownCafeJournal::Sha256(OldBytes,OldSha)&&A->EncodeJournal(Before,Error),TEXT("Actual old bytes and current state available")))return true;
  const auto Pawn=PC->GetPawn();const FTransform Transform=Pawn->GetActorTransform();const auto Persona=PC->GetNativePersona();
  if(!Need(!A->LoadJournal(Old,Error)&&A->EncodeJournal(After,Error)&&After==Before,TEXT("Ordinary V5 load refuses V4 without fallback or state mutation")))return true;
  R::Kernel Expected;R::care::ResidentUse ExpectedUse("ben");R::ClockMetadata Clock;
  TSharedPtr<FJsonObject> O;FString Encoded;TArray<uint8> Payload;if(!Need(RentObject(Old,O)&&O->TryGetStringField(TEXT("payload_base64"),Encoded)&&FBase64::Decode(Encoded,Payload),TEXT("Read actual old portable bytes")))return true;
  const std::string Raw(reinterpret_cast<const char*>(Payload.GetData()),size_t(Payload.Num()));
  if(!Need(R::import_legacy_care_envelope(Expected,ExpectedUse,Raw,Source.bindings,Clock)&&!Expected.recurring_lease(),TEXT("Old replay computes fixed-only expected outcome")))return true;
  if(!Need(A->ImportLegacyV4Slot(Error),TEXT("Explicit native import must pass exact old source/physical/recipe binding; mismatched old content is not waived")))return true;
  R::Kernel Actual;R::CareEnvelope Imported;if(!Need(A->EncodeJournal(After,Error)&&RentWorld(After,Actual)&&RentEnvelope(After,Imported)&&Actual.save_bytes()==Expected.save_bytes()&&Imported.clock.tick==Clock.tick&&Imported.clock.fraction_bits==Clock.fraction_bits,TEXT("Explicit native import preserves actual old money/title/fixed rights/clock")))return true;
  if(!Need(PC->GetPawn()==Pawn&&PC->GetNativePersona()==Persona&&Pawn->GetActorTransform().Equals(Transform,0),TEXT("Legacy import cannot replace pawn/persona or position")))return true;
  TArray<uint8> ReRead;FString AfterSha;if(!Need(FFileHelper::LoadFileToArray(ReRead,*Path)&&LivingTownCafeJournal::Sha256(ReRead,AfterSha)&&AfterSha==OldSha&&A->SaveSlot(Error),TEXT("Legacy bytes preserved while new slot saves current version")))return true;
  Test->AddInfo(TEXT("Actual old native payload imported; active fixed-contract compatibility is separately covered by the frozen old-public-API fixture. Pixels/hardware input are not claimed."));return true;
 }
};
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafeLegacyV4Import,"LivingTown.WorldV3.LegacyV4Import",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafeLegacyV4Import::RunTest(const FString&){
 if(!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeWorldV3"))||!FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeLegacyV4Import"))){AddError(TEXT("Explicit standalone WorldV3 legacy-import test opt-in required"));return false;}
 if(!AutomationOpenMap(TEXT("/Engine/Maps/Entry"),true))return false;ADD_LATENT_AUTOMATION_COMMAND(FLegacyCafeImport(this));return true;
}
#endif
