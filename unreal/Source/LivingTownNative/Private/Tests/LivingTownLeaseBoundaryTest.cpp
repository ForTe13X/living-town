#if WITH_DEV_AUTOMATION_TESTS
#include "LivingTownLeaseSubsystem.h"
#include "Engine/GameInstance.h"
#include "Misc/AutomationTest.h"
#include "UObject/StrongObjectPtr.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

namespace
{
void BindNativeCounter(ULivingTownLeaseSubsystem& S)
{
    S.InstallTrustedInteractionResolver([](FLivingTownTrustedInteraction& At)
    {
        At.SpaceId = TEXT("cafe"); At.FloorId = TEXT("1f");
        At.InteractionId = TEXT("cafe1f_counter"); At.bWithinReach = true;
        return true;
    });
}
FLivingTownLeaseCommand LeaseCommand(const TCHAR* Request = TEXT("ue-boundary/1"))
{
    FLivingTownLeaseCommand C;
    C.RequestId.Value = Request;
    C.PropertyId.Value = TEXT("cafe_ground_commercial_v1");
    return C;
}
FString Mutated(const FString& Json, TFunctionRef<void(FJsonObject&)> Change)
{
    TSharedPtr<FJsonObject> O;
    if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json), O) || !O) return TEXT("{}");
    Change(*O);
    FString Result;
    FJsonSerializer::Serialize(O.ToSharedRef(), TJsonWriterFactory<>::Create(&Result));
    return Result;
}
}

// Justified engine-level boundary: UObjects, reflected command shapes, actual
// UE JSON types and subsystem ownership are absent from the standalone test.
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownLeaseBoundaryTest,
    "LivingTown.Native.CafeLeaseBoundary",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
bool FLivingTownLeaseBoundaryTest::RunTest(const FString& Parameters)
{
    (void)Parameters;
    TStrongObjectPtr<UGameInstance> Game(NewObject<UGameInstance>());
    TStrongObjectPtr<ULivingTownLeaseSubsystem> S(NewObject<ULivingTownLeaseSubsystem>(Game.Get()));
    auto C = LeaseCommand();
    TestEqual(TEXT("Unbound world refuses interaction"), S->SubmitCommand(C).Reason, FString(TEXT("spatial_binding_unqualified")));
    TestEqual(TEXT("Unbound refusal creates no events"), S->GetLeaseView().EventCount, int64(0));
    BindNativeCounter(*S);
    const auto Granted = S->SubmitCommand(C);
    TestTrue(TEXT("Native fixture context grants"), Granted.bAccepted);
    TestEqual(TEXT("Paired receipt id"), Granted.EventId, int64(2));
    TestEqual(TEXT("Ben pays4"), S->GetLeaseView().BenCoins, int64(8));
    TestEqual(TEXT("Aria receives4"), S->GetLeaseView().AriaCoins, int64(16));
    TestEqual(TEXT("Scope operator"), S->GetLeaseView().OperatorId.Value, FString(TEXT("ben")));
    S->InstallTrustedInteractionResolver([](FLivingTownTrustedInteraction& At)
    { At.SpaceId = TEXT("town"); At.FloorId = TEXT("outdoor"); return true; });
    TestTrue(TEXT("Retry remains idempotent after leaving"), S->SubmitCommand(C).bAlreadyApplied);
    TestEqual(TEXT("Retry creates no second payment"), S->GetLeaseView().EventCount, int64(2));
    auto Conflict = C; Conflict.Action = ELivingTownLeaseAction::EndLease;
    TestEqual(TEXT("ID reuse cannot change action"), S->SubmitCommand(Conflict).Reason, FString(TEXT("request_id_conflict")));
    FString Saved, Error;
    if (!TestTrue(TEXT("Save new journal"), S->SaveNewPilotJournal(Saved, Error))) return false;
    TStrongObjectPtr<ULivingTownLeaseSubsystem> Loaded(NewObject<ULivingTownLeaseSubsystem>(Game.Get()));
    if (!TestTrue(TEXT("Replay actual UE JSON"), Loaded->LoadNewPilotJournal(Saved, Error))) return false;
    TestEqual(TEXT("Replay money"), Loaded->GetLeaseView().BenCoins, int64(8));
    TestEqual(TEXT("Replay digest"), Loaded->GetLeaseView().JournalDigest, S->GetLeaseView().JournalDigest);
    FString Resaved;
    TestTrue(TEXT("Resave replay"), Loaded->SaveNewPilotJournal(Resaved, Error));
    TestEqual(TEXT("Exact canonical journal roundtrip"), Resaved, Saved);
    const auto Before = Loaded->GetLeaseView();
    auto Reject = [&](const TCHAR* Name, const FString& Bad)
    {
        TestFalse(Name, Loaded->LoadNewPilotJournal(Bad, Error));
        const auto After = Loaded->GetLeaseView();
        TestEqual(TEXT("Failed load leaves digest exact"), After.JournalDigest, Before.JournalDigest);
        TestEqual(TEXT("Failed load leaves Ben cash exact"), After.BenCoins, Before.BenCoins);
        TestEqual(TEXT("Failed load leaves Aria cash exact"), After.AriaCoins, Before.AriaCoins);
        TestEqual(TEXT("Failed load leaves event count exact"), After.EventCount, Before.EventCount);
        TestEqual(TEXT("Failed load leaves clock exact"), After.Clock, Before.Clock);
    };
    Reject(TEXT("Legacy full-world save rejected"), TEXT("{\"tick\":0,\"people\":[]}"));
    Reject(TEXT("Unknown envelope fields rejected"), Mutated(Saved, [](FJsonObject& O) { O.SetStringField(TEXT("legacy_world"), TEXT("unsupported")); }));
    Reject(TEXT("Version rejected"), Mutated(Saved, [](FJsonObject& O) { O.SetStringField(TEXT("version"), TEXT("2")); }));
    Reject(TEXT("Numeric version cannot coerce to string"), Mutated(Saved, [](FJsonObject& O) { O.SetNumberField(TEXT("version"), 1); }));
    Reject(TEXT("World provenance rejected"), Mutated(Saved, [](FJsonObject& O) { O.SetStringField(TEXT("world_binding_sha256"), TEXT("different_world")); }));
    Reject(TEXT("Session identity rejected"), Mutated(Saved, [](FJsonObject& O) { O.SetStringField(TEXT("session_id"), TEXT("aria")); }));
    Reject(TEXT("Numeric clock instead of exact decimal rejected"), Mutated(Saved, [](FJsonObject& O) { O.SetNumberField(TEXT("clock"), 0); }));
    Reject(TEXT("Active lease clock at expiry requires its expiry event"), Mutated(Saved, [](FJsonObject& O) { O.SetStringField(TEXT("clock"), TEXT("720")); }));
    Reject(TEXT("Active lease clock past expiry requires its expiry event"), Mutated(Saved, [](FJsonObject& O) { O.SetStringField(TEXT("clock"), TEXT("721")); }));
    Reject(TEXT("Active lease cannot hide expiry at maximum clock"), Mutated(Saved, [](FJsonObject& O) { O.SetStringField(TEXT("clock"), TEXT("9007199254740991")); }));
    Reject(TEXT("Corrupt payment refused by refold"), Mutated(Saved, [](FJsonObject& O) { O.GetArrayField(TEXT("journal"))[0]->AsObject()->SetStringField(TEXT("amt"), TEXT("3")); }));
    Reject(TEXT("Orphan pay rejected"), Mutated(Saved, [](FJsonObject& O) { auto E = O.GetArrayField(TEXT("journal")); E.RemoveAt(1); O.SetArrayField(TEXT("journal"), E); }));
    Reject(TEXT("Unknown event field rejected"), Mutated(Saved, [](FJsonObject& O) { O.GetArrayField(TEXT("journal"))[1]->AsObject()->SetBoolField(TEXT("secret_right"), true); }));
    Reject(TEXT("Accepted flag cannot coerce from number"), Mutated(Saved, [](FJsonObject& O) { O.GetArrayField(TEXT("journal"))[1]->AsObject()->SetNumberField(TEXT("accepted"), 1); }));
    const FString Duplicate = Saved.Replace(TEXT("\"version\":\"1\""), TEXT("\"version\":\"1\",\"version\":\"1\""));
    TestTrue(TEXT("Duplicate-key fixture actually changes input"), Duplicate != Saved);
    Reject(TEXT("Duplicate keys rejected before map conversion"), Duplicate);
    BindNativeCounter(*Loaded);
    auto End = LeaseCommand(TEXT("ue-boundary/2")); End.Action = ELivingTownLeaseAction::EndLease;
    TestTrue(TEXT("End existing lease"), Loaded->SubmitCommand(End).bAccepted);
    TestEqual(TEXT("End restores owner operator"), Loaded->GetLeaseView().OperatorId.Value, FString(TEXT("aria")));
    TestEqual(TEXT("End gives no refund"), Loaded->GetLeaseView().BenCoins, int64(8));
    TestTrue(TEXT("Clock719"), S->AdvanceTrustedClockTo(719, Error));
    TestEqual(TEXT("Lease active before end"), S->GetLeaseView().OperatorId.Value, FString(TEXT("ben")));
    FString BeforeExpirySaved;
    TestTrue(TEXT("Save genuine clock719 active snapshot"), S->SaveNewPilotJournal(BeforeExpirySaved, Error));
    TestTrue(TEXT("Genuine clock719 active snapshot still loads"), Loaded->LoadNewPilotJournal(BeforeExpirySaved, Error));
    TestEqual(TEXT("Loaded genuine pre-expiry clock"), Loaded->GetLeaseView().Clock, int64(719));
    TestEqual(TEXT("Loaded genuine pre-expiry operator"), Loaded->GetLeaseView().OperatorId.Value, FString(TEXT("ben")));
    TestTrue(TEXT("Clock720 expires"), S->AdvanceTrustedClockTo(720, Error));
    TestEqual(TEXT("Half-open expiry restores owner"), S->GetLeaseView().OperatorId.Value, FString(TEXT("aria")));
    TestEqual(TEXT("Expiry preserves total money"), S->GetLeaseView().AriaCoins + S->GetLeaseView().BenCoins, int64(24));
    TestEqual(TEXT("Expiry records one additional receipt"), S->GetLeaseView().EventCount, int64(3));
    FString ExpiredSaved;
    TestTrue(TEXT("Save genuine clock720 expiry snapshot"), S->SaveNewPilotJournal(ExpiredSaved, Error));
    TestTrue(TEXT("Genuine expiry event makes clock720 replayable"), Loaded->LoadNewPilotJournal(ExpiredSaved, Error));
    TestEqual(TEXT("Loaded genuine expiry clock"), Loaded->GetLeaseView().Clock, int64(720));
    TestEqual(TEXT("Loaded genuine expiry operator"), Loaded->GetLeaseView().OperatorId.Value, FString(TEXT("aria")));
    TestEqual(TEXT("Loaded genuine expiry digest exact"), Loaded->GetLeaseView().JournalDigest, S->GetLeaseView().JournalDigest);
    TestEqual(TEXT("Loaded genuine expiry conserves money"), Loaded->GetLeaseView().AriaCoins + Loaded->GetLeaseView().BenCoins, int64(24));
    TestFalse(TEXT("Authority clock cannot reverse"), S->AdvanceTrustedClockTo(719, Error));
    auto Invalid = LeaseCommand(TEXT("ue-boundary/invalid")); Invalid.Action = static_cast<ELivingTownLeaseAction>(255);
    TestEqual(TEXT("Unsupported UI action refused"), S->SubmitCommand(Invalid).Reason, FString(TEXT("unsupported_action")));
    TStrongObjectPtr<ULivingTownLeaseSubsystem> Full(NewObject<ULivingTownLeaseSubsystem>(Game.Get()));
    Full->InstallTrustedInteractionResolver([](FLivingTownTrustedInteraction&) { return true; });
    for (int32 I = 0; I < 1024; ++I)
    {
        const FString Id = FString::Printf(TEXT("capacity/%d"), I);
        Full->SubmitCommand(LeaseCommand(*Id));
    }
    TestEqual(TEXT("Bounded journal fills exactly"), Full->GetLeaseView().EventCount, int64(1024));
    TestEqual(TEXT("Overflow command is atomic"), Full->SubmitCommand(LeaseCommand(TEXT("capacity/overflow"))).Reason, FString(TEXT("journal_capacity")));
    FString FullSave;
    TestTrue(TEXT("Bounded journal remains saveable"), Full->SaveNewPilotJournal(FullSave, Error));
    TestTrue(TEXT("Bounded journal remains replayable"), Full->LoadNewPilotJournal(FullSave, Error));
    return true;
}
#endif
