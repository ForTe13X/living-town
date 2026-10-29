#include "LivingTownLeaseSubsystem.h"
#include "../ThirdParty/LeaseKernel.hpp"
#include "../ThirdParty/CafePropertyBackend.hpp"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "Policies/CondensedJsonPrintPolicy.h"

namespace
{
namespace Pilot = living_town::lease_pilot;
constexpr const TCHAR* CoreHash = TEXT("942eb43c7b822da17c4949b08aa890d65324cd6d0e31bafa5d5104440641a8ac");
constexpr const TCHAR* ContractHash = TEXT("b5a0df51f0bb7fd1a04196d8fe1118df75b9de275b881faad71ac014c00ecf4c");
constexpr const TCHAR* BindingHash = TEXT("9b7866e037be2bf9f2757c1201a572b466402eb4c0f3dc5b510c0166301bbcfc");
constexpr const TCHAR* Capability = TEXT("cafe.prepaid_lease.v1");
constexpr size_t MaximumJournalEvents = 1024;
std::string Utf8(const FString& S) { return std::string(TCHAR_TO_UTF8(*S)); }
FString Text(const std::string& S) { return FString(UTF8_TO_TCHAR(S.c_str())); }
Pilot::Terms Terms() { return {"cafe_ground_commercial_v1", "aria", "cafe", "1f", "cafe1f_counter", 4, 720}; }
Pilot::Kernel Opening() { return Pilot::Kernel(Terms(), {{"aria", 12, 12}, {"ben", 12, 12}}); }

bool Keys(const FJsonObject& O, std::initializer_list<const TCHAR*> Expected)
{
    if (O.Values.Num() != static_cast<int32>(Expected.size())) return false;
    for (const TCHAR* Key : Expected) if (!O.HasField(FStringView(Key))) return false;
    return true;
}

// FJsonObject is a map. Detect duplicate object keys before map deserialization
// so a second version/provenance/amount cannot silently overwrite the first.
bool UniqueKeys(const FString& Json)
{
    struct FFrame { bool bObject; TSet<FString> Seen; explicit FFrame(bool B) : bObject(B) {} };
    TArray<FFrame> Stack;
    const TSharedRef<TJsonReader<>> Reader = TJsonReaderFactory<>::Create(Json);
    EJsonNotation N;
    while (Reader->ReadNext(N))
    {
        if (N == EJsonNotation::ObjectEnd || N == EJsonNotation::ArrayEnd)
        {
            if (Stack.IsEmpty()) return false;
            Stack.Pop(EAllowShrinking::No);
            continue;
        }
        if (!Stack.IsEmpty() && Stack.Last().bObject)
        {
            const FString Key = Reader->GetIdentifier();
            if (Key.IsEmpty() || Stack.Last().Seen.Contains(Key)) return false;
            Stack.Last().Seen.Add(Key);
        }
        if (N == EJsonNotation::ObjectStart) Stack.Emplace(true);
        else if (N == EJsonNotation::ArrayStart) Stack.Emplace(false);
        else if (N == EJsonNotation::Error) return false;
    }
    return Stack.IsEmpty() && Reader->GetErrorMessage().IsEmpty();
}

bool String(const FJsonObject& O, const TCHAR* Key, FString& Out, int32 Limit = 512)
{
    const TSharedPtr<FJsonValue> V = O.TryGetField(Key);
    if (!V.IsValid() || V->Type != EJson::String) return false;
    Out = V->AsString();
    return Out.Len() <= Limit;
}
bool Boolean(const FJsonObject& O, const TCHAR* Key, bool& Out)
{
    const TSharedPtr<FJsonValue> V = O.TryGetField(Key);
    if (!V.IsValid() || V->Type != EJson::Boolean) return false;
    Out = V->AsBool();
    return true;
}
bool IntegerValue(const TSharedPtr<FJsonValue>& V, int64& Out)
{
    if (!V.IsValid() || V->Type != EJson::String) return false;
    const FString S = V->AsString();
    if (S.IsEmpty() || S.Len() > 20 || !LexTryParseString(Out, *S)) return false;
    return LexToString(Out) == S; // canonical decimal; no floats, signs or rounded doubles
}
bool Integer(const FJsonObject& O, const TCHAR* Key, int64& Out)
{
    return IntegerValue(O.TryGetField(Key), Out);
}
void OptionalInteger(FJsonObject& O, const TCHAR* Key, const std::optional<std::int64_t>& Value)
{
    if (Value) O.SetStringField(Key, LexToString(static_cast<int64>(*Value)));
    else O.SetField(Key, MakeShared<FJsonValueNull>());
}
bool OptionalInteger(const FJsonObject& O, const TCHAR* Key, std::optional<std::int64_t>& Out)
{
    const TSharedPtr<FJsonValue> V = O.TryGetField(Key);
    if (!V.IsValid()) return false;
    if (V->Type == EJson::Null) { Out.reset(); return true; }
    int64 N = 0;
    if (!IntegerValue(V, N)) return false;
    Out = N;
    return true;
}

TSharedRef<FJsonObject> EncodeContext(const Pilot::Context& C)
{
    const TSharedRef<FJsonObject> O = MakeShared<FJsonObject>();
    O->SetStringField(TEXT("actor"), Text(C.actor));
    O->SetStringField(TEXT("space_id"), Text(C.space_id));
    O->SetStringField(TEXT("floor_id"), Text(C.floor_id));
    O->SetStringField(TEXT("interaction_id"), Text(C.interaction_id));
    O->SetStringField(TEXT("tick"), LexToString(static_cast<int64>(C.tick)));
    O->SetBoolField(TEXT("within_reach"), C.within_reach);
    return O;
}
bool DecodeContext(const FJsonObject& O, Pilot::Context& C)
{
    if (!Keys(O, {TEXT("actor"), TEXT("space_id"), TEXT("floor_id"), TEXT("interaction_id"), TEXT("tick"), TEXT("within_reach")})) return false;
    FString Actor, Space, Floor, Interaction;
    int64 Tick = 0;
    bool Reach = false;
    if (!String(O, TEXT("actor"), Actor, 128) || !String(O, TEXT("space_id"), Space, 128) ||
        !String(O, TEXT("floor_id"), Floor, 128) || !String(O, TEXT("interaction_id"), Interaction, 128) ||
        !Integer(O, TEXT("tick"), Tick) || !Boolean(O, TEXT("within_reach"), Reach)) return false;
    C = {Utf8(Actor), Utf8(Space), Utf8(Floor), Utf8(Interaction), Tick, Reach};
    return true;
}
TSharedRef<FJsonObject> EncodeEvent(const Pilot::Event& E)
{
    const TSharedRef<FJsonObject> O = MakeShared<FJsonObject>();
    O->SetStringField(TEXT("id"), LexToString(static_cast<int64>(E.id)));
    O->SetStringField(TEXT("tick"), LexToString(static_cast<int64>(E.tick)));
    O->SetStringField(TEXT("type"), Text(E.type));
    O->SetStringField(TEXT("actor"), Text(E.actor));
    O->SetStringField(TEXT("target"), Text(E.target));
    O->SetStringField(TEXT("subject"), Text(E.subject));
    O->SetStringField(TEXT("note"), Text(E.note));
    O->SetStringField(TEXT("txid"), Text(E.txid));
    O->SetBoolField(TEXT("accepted"), E.accepted);
    OptionalInteger(*O, TEXT("amt"), E.amt);
    OptionalInteger(*O, TEXT("amount"), E.amount);
    OptionalInteger(*O, TEXT("end_tick"), E.end_tick);
    OptionalInteger(*O, TEXT("pay_event_id"), E.pay_event_id);
    OptionalInteger(*O, TEXT("lease_event_id"), E.lease_event_id);
    OptionalInteger(*O, TEXT("title_revision"), E.title_revision);
    OptionalInteger(*O, TEXT("offer_revision"), E.offer_revision);
    O->SetStringField(TEXT("request_id"), Text(E.request_id));
    O->SetStringField(TEXT("action"), Text(E.action));
    O->SetStringField(TEXT("owner_before"), Text(E.owner_before));
    if (E.context) O->SetObjectField(TEXT("context"), EncodeContext(*E.context));
    else O->SetField(TEXT("context"), MakeShared<FJsonValueNull>());
    return O;
}
bool DecodeEvent(const FJsonObject& O, Pilot::Event& E)
{
    if (!Keys(O, {TEXT("id"), TEXT("tick"), TEXT("type"), TEXT("actor"), TEXT("target"), TEXT("subject"), TEXT("note"), TEXT("txid"), TEXT("accepted"), TEXT("amt"), TEXT("amount"), TEXT("end_tick"), TEXT("pay_event_id"), TEXT("lease_event_id"), TEXT("title_revision"), TEXT("offer_revision"), TEXT("request_id"), TEXT("action"), TEXT("owner_before"), TEXT("context")})) return false;
    int64 Id = 0, Tick = 0;
    FString Type, Actor, Target, Subject, Note, Txid, Request, Action, Owner;
    if (!Integer(O, TEXT("id"), Id) || !Integer(O, TEXT("tick"), Tick) ||
        !String(O, TEXT("type"), Type) || !String(O, TEXT("actor"), Actor) ||
        !String(O, TEXT("target"), Target) || !String(O, TEXT("subject"), Subject) ||
        !String(O, TEXT("note"), Note) || !String(O, TEXT("txid"), Txid) ||
        !String(O, TEXT("request_id"), Request) || !String(O, TEXT("action"), Action) ||
        !String(O, TEXT("owner_before"), Owner) || !Boolean(O, TEXT("accepted"), E.accepted) ||
        !OptionalInteger(O, TEXT("amt"), E.amt) || !OptionalInteger(O, TEXT("amount"), E.amount) ||
        !OptionalInteger(O, TEXT("end_tick"), E.end_tick) || !OptionalInteger(O, TEXT("pay_event_id"), E.pay_event_id) ||
        !OptionalInteger(O, TEXT("lease_event_id"), E.lease_event_id) ||
        !OptionalInteger(O, TEXT("title_revision"), E.title_revision) || !OptionalInteger(O, TEXT("offer_revision"), E.offer_revision)) return false;
    E.id = Id; E.tick = Tick; E.type = Utf8(Type); E.actor = Utf8(Actor); E.target = Utf8(Target);
    E.subject = Utf8(Subject); E.note = Utf8(Note); E.txid = Utf8(Txid); E.request_id = Utf8(Request);
    E.action = Utf8(Action); E.owner_before = Utf8(Owner);
    const TSharedPtr<FJsonValue> Context = O.TryGetField(TEXT("context"));
    if (!Context.IsValid()) return false;
    if (Context->Type == EJson::Null) { E.context.reset(); return true; }
    if (Context->Type != EJson::Object || !Context->AsObject().IsValid()) return false;
    Pilot::Context C;
    if (!DecodeContext(*Context->AsObject(), C)) return false;
    E.context = C;
    return true;
}
FLivingTownLeaseReceipt Receipt(const Pilot::Receipt& R)
{
    FLivingTownLeaseReceipt Out;
    Out.bAccepted = R.ok; Out.bAlreadyApplied = R.already_applied;
    Out.Reason = Text(R.reason); Out.EventId = R.event_id;
    return Out;
}
FLivingTownLeaseReceipt Refused(const TCHAR* Reason)
{
    FLivingTownLeaseReceipt Out; Out.Reason = Reason; return Out;
}
}

struct ULivingTownLeaseSubsystem::FState
{
    Pilot::Kernel Kernel = Opening();
    int64 Clock = 0;
    FString Session = TEXT("ben");
};

void ULivingTownLeaseSubsystem::FStateDeleter::operator()(FState* Pointer) const { delete Pointer; }
ULivingTownLeaseSubsystem::ULivingTownLeaseSubsystem() : State(new FState()) {}
ULivingTownLeaseSubsystem::~ULivingTownLeaseSubsystem() = default;
bool ULivingTownLeaseSubsystem::ShouldCreateSubsystem(UObject* Outer) const
{
    return Super::ShouldCreateSubsystem(Outer) && living_town::cafe_property_backend::Select(
        FParse::Param(FCommandLine::Get(), TEXT("LivingTownCafePropertyV2"))) == living_town::cafe_property_backend::Backend::LegacyV1;
}
void ULivingTownLeaseSubsystem::Deinitialize()
{
    InteractionResolver = nullptr;
    State.Reset();
    Super::Deinitialize();
}
void ULivingTownLeaseSubsystem::InstallTrustedInteractionResolver(FInteractionResolver Resolver)
{
    check(IsInGameThread());
    InteractionResolver = MoveTemp(Resolver);
}
FLivingTownLeaseReceipt ULivingTownLeaseSubsystem::SubmitCommand(const FLivingTownLeaseCommand& Command)
{
    if (!IsInGameThread()) return Refused(TEXT("wrong_thread"));
    if (!State) return Refused(TEXT("pilot_not_initialized"));
    Pilot::Action Action;
    switch (Command.Action)
    {
    case ELivingTownLeaseAction::Lease: Action = Pilot::Action::lease; break;
    case ELivingTownLeaseAction::EndLease: Action = Pilot::Action::end_lease; break;
    default: return Refused(TEXT("unsupported_action"));
    }
    FLivingTownTrustedInteraction At;
    if (!InteractionResolver || !InteractionResolver(At)) return Refused(TEXT("spatial_binding_unqualified"));
    try
    {
        const Pilot::Intent Intent{Utf8(Command.RequestId.Value), Utf8(Command.PropertyId.Value), Action};
        const Pilot::Context Context{Utf8(State->Session), Utf8(At.SpaceId), Utf8(At.FloorId), Utf8(At.InteractionId), State->Clock, At.bWithinReach};
        Pilot::Kernel Candidate = State->Kernel;
        const Pilot::Receipt Result = Candidate.execute(Intent, Context);
        // Always reserve one event for automatic expiry of an active lease.
        if (Candidate.events().size() + (Candidate.lease().active ? 1U : 0U) > MaximumJournalEvents)
            return Refused(TEXT("journal_capacity"));
        State->Kernel = std::move(Candidate);
        return Receipt(Result);
    }
    catch (const std::exception&) { return Refused(TEXT("kernel_exception")); }
}
FLivingTownLeaseView ULivingTownLeaseSubsystem::GetLeaseView() const
{
    FLivingTownLeaseView Out;
    if (!IsInGameThread() || !State) return Out;
    Out.OwnerId = FLivingTownStableId(TEXT("aria"));
    Out.OperatorId = FLivingTownStableId(Text(State->Kernel.operator_at(State->Clock)));
    Out.SessionId = FLivingTownStableId(State->Session);
    Out.Clock = State->Clock;
    Out.EventCount = static_cast<int64>(State->Kernel.events().size());
    Out.JournalDigest = LexToString(static_cast<uint64>(State->Kernel.digest()));
    for (const auto& Account : State->Kernel.accounts())
    {
        if (Account.id == "aria") Out.AriaCoins = Account.coin;
        if (Account.id == "ben") Out.BenCoins = Account.coin;
    }
    return Out;
}
bool ULivingTownLeaseSubsystem::AdvanceTrustedClockTo(int64 NewTick, FString& OutError)
{
    OutError.Reset();
    if (!IsInGameThread() || !State || NewTick < State->Clock || NewTick > Pilot::max_tick)
    { OutError = TEXT("invalid_authority_clock"); return false; }
    try
    {
        const auto Lease = State->Kernel.lease();
        if (Lease.active && NewTick >= Lease.end)
        {
            const Pilot::Intent Intent{"expire/cafe_ground_commercial_v1/" + std::to_string(Lease.event_id), Terms().property_id, Pilot::Action::expire};
            const Pilot::Context Context{"town", "", "", "", NewTick, false};
            Pilot::Kernel Candidate = State->Kernel;
            if (!Candidate.execute(Intent, Context).ok || Candidate.events().size() > MaximumJournalEvents)
            { OutError = TEXT("expiry_refused"); return false; }
            State->Kernel = std::move(Candidate);
        }
        State->Clock = NewTick;
        return true;
    }
    catch (const std::exception&) { OutError = TEXT("clock_exception"); return false; }
}
bool ULivingTownLeaseSubsystem::SaveNewPilotJournal(FString& OutJson, FString& OutError) const
{
    OutJson.Reset(); OutError.Reset();
    if (!IsInGameThread() || !State) { OutError = TEXT("pilot_not_initialized"); return false; }
    const TSharedRef<FJsonObject> O = MakeShared<FJsonObject>();
    O->SetStringField(TEXT("format"), TEXT("LivingTown.CafeLeaseJournal"));
    O->SetStringField(TEXT("version"), TEXT("1"));
    O->SetStringField(TEXT("core_sha256"), CoreHash);
    O->SetStringField(TEXT("contract_sha256"), ContractHash);
    O->SetStringField(TEXT("world_binding_sha256"), BindingHash);
    O->SetArrayField(TEXT("capabilities"), {MakeShared<FJsonValueString>(Capability)});
    O->SetStringField(TEXT("clock"), LexToString(State->Clock));
    O->SetStringField(TEXT("session_id"), State->Session);
    O->SetStringField(TEXT("digest"), LexToString(static_cast<uint64>(State->Kernel.digest())));
    TArray<TSharedPtr<FJsonValue>> Journal;
    for (const auto& E : State->Kernel.events()) Journal.Add(MakeShared<FJsonValueObject>(EncodeEvent(E)));
    O->SetArrayField(TEXT("journal"), Journal);
    const bool Ok = FJsonSerializer::Serialize(O, TJsonWriterFactory<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>::Create(&OutJson)) && OutJson.Len() <= 2 * 1024 * 1024;
    if (!Ok) OutError = TEXT("journal_encoding_failed");
    return Ok;
}
bool ULivingTownLeaseSubsystem::LoadNewPilotJournal(const FString& Json, FString& OutError)
{
    OutError.Reset();
    auto Fail = [&OutError](const TCHAR* Why) { OutError = Why; return false; };
    if (!IsInGameThread() || !State) return Fail(TEXT("pilot_not_initialized"));
    if (Json.Len() > 2 * 1024 * 1024 || !UniqueKeys(Json)) return Fail(TEXT("invalid_json_or_duplicate_key"));
    TSharedPtr<FJsonObject> O;
    if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json), O) || !O.IsValid()) return Fail(TEXT("invalid_json"));
    if (!Keys(*O, {TEXT("format"), TEXT("version"), TEXT("core_sha256"), TEXT("contract_sha256"), TEXT("world_binding_sha256"), TEXT("capabilities"), TEXT("clock"), TEXT("session_id"), TEXT("digest"), TEXT("journal")})) return Fail(TEXT("unsupported_envelope_fields"));
    FString Format, Version, Core, Contract, Binding, Session;
    if (!String(*O, TEXT("format"), Format) || Format != TEXT("LivingTown.CafeLeaseJournal") ||
        !String(*O, TEXT("version"), Version) || Version != TEXT("1") ||
        !String(*O, TEXT("core_sha256"), Core) || Core != CoreHash ||
        !String(*O, TEXT("contract_sha256"), Contract) || Contract != ContractHash ||
        !String(*O, TEXT("world_binding_sha256"), Binding) || Binding != BindingHash ||
        !String(*O, TEXT("session_id"), Session) || Session != State->Session) return Fail(TEXT("unsupported_format_version_or_provenance"));
    const TArray<TSharedPtr<FJsonValue>>* Capabilities = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* Journal = nullptr;
    int64 Clock = 0, Digest = 0;
    if (!O->TryGetArrayField(TEXT("capabilities"), Capabilities) || Capabilities->Num() != 1 ||
        (*Capabilities)[0]->Type != EJson::String || (*Capabilities)[0]->AsString() != Capability ||
        !O->TryGetArrayField(TEXT("journal"), Journal) || static_cast<size_t>(Journal->Num()) > MaximumJournalEvents ||
        !Integer(*O, TEXT("clock"), Clock) || Clock < 0 || Clock > Pilot::max_tick ||
        !Integer(*O, TEXT("digest"), Digest) || Digest < 0) return Fail(TEXT("unsupported_capability_clock_or_journal"));
    try
    {
        std::vector<Pilot::Event> Events;
        Events.reserve(Journal->Num());
        for (const TSharedPtr<FJsonValue>& Value : *Journal)
        {
            if (!Value.IsValid() || Value->Type != EJson::Object || !Value->AsObject().IsValid()) return Fail(TEXT("invalid_event_type"));
            Pilot::Event E;
            if (!DecodeEvent(*Value->AsObject(), E)) return Fail(TEXT("unsupported_event_fields"));
            Events.push_back(std::move(E));
        }
        TUniquePtr<FState, FStateDeleter> Candidate(new FState());
        if (!Candidate->Kernel.restore_events(Events) || Candidate->Kernel.digest() != static_cast<uint64>(Digest) ||
            (!Events.empty() && Clock < Events.back().tick) ||
            Candidate->Kernel.events().size() + (Candidate->Kernel.lease().active ? 1U : 0U) > MaximumJournalEvents)
            return Fail(TEXT("journal_replay_mismatch"));
        // The native clock writer records expiry before committing a clock at
        // or beyond the lease end. A changed clock must not restore an active
        // kernel lease while its public operator has already reverted to owner.
        const auto RestoredLease = Candidate->Kernel.lease();
        if (RestoredLease.active && Clock >= RestoredLease.end)
            return Fail(TEXT("journal_expired_active_lease_clock"));
        Candidate->Clock = Clock;
        Candidate->Session = Session;
        State = MoveTemp(Candidate); // one atomic writer; no live fields changed before complete validation
        return true;
    }
    catch (const std::exception&) { return Fail(TEXT("journal_replay_exception")); }
}
