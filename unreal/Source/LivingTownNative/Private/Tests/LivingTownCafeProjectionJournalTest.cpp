#include "LivingTownCafeBinding.h"
#include "LivingTownLeaseSubsystem.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Engine/GameInstance.h"
#include "UObject/StrongObjectPtr.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafeProjectionJournalTest,"LivingTown.Native.CafeProjectionJournal",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafeProjectionJournalTest::RunTest(const FString&)
{
    // Envelope codec fixture only. This never installs a spatial resolver and
    // does not certify an asset/character or turn logical hashes into scene proof.
    FLivingTownCafeBinding B;B.PhysicalSceneSha256=FString::ChrN(64,'a');B.BindingFileSha256=FString::ChrN(64,'b');B.VisualSha256=FString::ChrN(64,'c');B.PhysicalQualificationSha256=FString::ChrN(64,'d');
    TStrongObjectPtr<UGameInstance> GI(NewObject<UGameInstance>());TStrongObjectPtr<ULivingTownLeaseSubsystem> S(NewObject<ULivingTownLeaseSubsystem>(GI.Get()));
    FString Inner,Saved,Error,Decoded;TestTrue(TEXT("Actual unchanged strict journal serializes"),S->SaveNewPilotJournal(Inner,Error));TestTrue(TEXT("Versioned physical wrapper encodes"),LivingTownCafeJournal::Encode(B,Inner,Saved,Error));TestTrue(TEXT("Matching physical wrapper decodes"),LivingTownCafeJournal::Decode(Saved,B,Decoded,Error));TestEqual(TEXT("Inner journal bytes untouched"),Decoded,Inner);
    const auto Before=S->GetLeaseView();
    auto Reject=[&](const TCHAR* Name,const FString& Bad)
    {
        FString Candidate;const bool Outer=LivingTownCafeJournal::Decode(Bad,B,Candidate,Error);const bool Applied=Outer&&S->LoadNewPilotJournal(Candidate,Error);TestFalse(Name,Applied);
        const auto After=S->GetLeaseView();TestEqual(TEXT("Rejected outer/inner digest atomic"),After.JournalDigest,Before.JournalDigest);TestEqual(TEXT("Rejected clock atomic"),After.Clock,Before.Clock);TestEqual(TEXT("Rejected money atomic"),After.BenCoins+After.AriaCoins,Before.BenCoins+Before.AriaCoins);TestEqual(TEXT("Rejected events atomic"),After.EventCount,Before.EventCount);
    };
    auto Mutate=[&](TFunctionRef<void(FJsonObject&)> F)
    {
        TSharedPtr<FJsonObject> O;FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Saved),O);F(*O);FString Result;FJsonSerializer::Serialize(O.ToSharedRef(),TJsonWriterFactory<>::Create(&Result));return Result;
    };
    Reject(TEXT("Logical-only v1 cannot masquerade as a physical save"),Inner);Reject(TEXT("Legacy whole-town state rejected"),TEXT("{\"tick\":0,\"people\":[]}"));
    Reject(TEXT("Wrong physical scene rejects atomically"),Mutate([](FJsonObject& O){O.SetStringField(TEXT("physical_scene_sha256"),FString::ChrN(64,'f'));}));
    Reject(TEXT("Wrong binding/calibration rejects"),Mutate([](FJsonObject& O){O.SetStringField(TEXT("physical_binding_sha256"),FString::ChrN(64,'f'));}));
    Reject(TEXT("Wrong qualification rejects"),Mutate([](FJsonObject& O){O.SetStringField(TEXT("physical_qualification_sha256"),FString::ChrN(64,'f'));}));
    Reject(TEXT("Aria cannot replace Ben in a save"),Mutate([](FJsonObject& O){O.SetStringField(TEXT("session_id"),TEXT("aria"));}));
    Reject(TEXT("Wrong visual rejects"),Mutate([](FJsonObject& O){O.SetStringField(TEXT("visual_sha256"),FString::ChrN(64,'f'));}));
    Reject(TEXT("Unsupported version rejects"),Mutate([](FJsonObject& O){O.SetStringField(TEXT("version"),TEXT("2"));}));
    Reject(TEXT("Numeric version cannot coerce"),Mutate([](FJsonObject& O){O.SetNumberField(TEXT("version"),1);}));
    Reject(TEXT("Unknown pose/reach authority rejected"),Mutate([](FJsonObject& O){O.SetBoolField(TEXT("within_reach"),true);}));
    FString Duplicate=Saved.Replace(TEXT("\"version\":\"1\""),TEXT("\"version\":\"1\",\"version\":\"1\""));TestTrue(TEXT("Duplicate fixture changes input"),Duplicate!=Saved);Reject(TEXT("Duplicate keys rejected before map conversion"),Duplicate);
    Reject(TEXT("Unsupported strict inner journal rejects"),Mutate([](FJsonObject& O){O.SetStringField(TEXT("lease_journal"),TEXT("{\"format\":\"legacy\"}"));}));
    return true;
}
#endif
