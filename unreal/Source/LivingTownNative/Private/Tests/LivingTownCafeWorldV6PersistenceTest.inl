// Included only by the native persistence implementation under its DEV flag.
// Exercises those exact private helpers without exposing an authority/test API.
// Synthetic observations and source-rebound legacy fixture: no world or asset
// contact is qualified here. Root must stage the unchanged fixture at
// Content/LivingTown/Tests/active_meal_v5.paired before running this test.
#include "Misc/AutomationTest.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafeWorldV6Persistence,
    "LivingTown.WorldV6.NativePersistenceSchemaAndMigration",
    EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafeWorldV6Persistence::RunTest(const FString&){
    FString Error,RegistrySha;TArray<uint8> Registry;
    if(!TestTrue(TEXT("Exact actual residential source bytes required"),SourceFile(
        FPaths::ProjectContentDir()/TEXT("LivingTown/ResidentialRegistryV1.json"),
        UTF8_TO_TCHAR(P::residential_registry_sha256),Registry,&RegistrySha)))return false;
    auto Sources=CareSources(FLivingTownCafeBinding{});Sources.residential_sha256=Utf8(RegistrySha);
    TestTrue(TEXT("Cached actual registry SHA is bound"),Sources.residential_sha256==P::residential_registry_sha256);
    const FString Source=NativeSourceHash(Sources);auto Changed=Sources;
    Changed.residential_sha256=std::string(64,'0');
    TestTrue(TEXT("Registry field changes native v6 source hash"),NativeSourceHash(Changed)!=Source);
    Changed=Sources;Changed.sleep_recipe_sha256=std::string(64,'1');
    TestTrue(TEXT("Sleep recipe field changes native v6 source hash"),NativeSourceHash(Changed)!=Source);
    TestTrue(TEXT("Legacy hash shape remains exact for explicit import only"),LegacyNativeSourceHash(Changed)==LegacyNativeSourceHash(Sources));
    TestEqual(TEXT("Current slot never aliases v5"),FString(CurrentSlot),FString(TEXT("CafeWorldV3/CafeWorldResidentialCareV6.slot.json")));

    P::Kernel Producer;Care::ResidentUse ProducerUse("ben");
    if(!TestTrue(TEXT("Meal authority activation"),Producer.activate_care({0,true}).ok)||
       !TestTrue(TEXT("Natural logical idle interval"),ProducerUse.advance_idle_to(100)))return false;
    const P::MealCommand Command{"v6/meal",P::meal_site,P::MealKind::PurchaseMeal,Producer.revision()};
    if(!TestTrue(TEXT("Current paid meal starts"),P::begin_meal_use(Producer,ProducerUse,Command,{"ben","ben",100,true,true,true,true,true}).ok))return false;
    for(P::Int Tick=101;Tick<=103;++Tick){const auto G=ProducerUse.active()->grant;
        if(!TestTrue(TEXT("One observed logical meal tick"),P::advance_meal_use(Producer,ProducerUse,Tick,{G.resident_id,G.site_id,G.grant_id,true,true,true,true,true}).ok))return false;}
    const auto Needs=ProducerUse.needs();
    const auto Payload=P::save_care_envelope(Producer,ProducerUse,Sources,{103,0});
    FString Json;if(!TestTrue(TEXT("Current paired v6 payload"),bool(Payload))||!TestTrue(TEXT("Current native v6 wrapper"),NativePayloadDocument(*Payload,Sources,6,Json,Error)))return false;
    P::Kernel Restored;Care::ResidentUse Use("ben");P::ClockMetadata Clock;
    if(!TestTrue(TEXT("Same runtime decoder accepts native/paired v6"),ReadNativeJournal(Json,6,Sources,Restored,Use,Clock,Error)))return false;
    TestTrue(TEXT("Coins, rations and earned needs retained"),Restored.coin("ben")==10&&Restored.coin("aria")==14&&Restored.rations()==1&&Care::same_need_values(Use.needs(),Needs));
    TestTrue(TEXT("Load stops historical use and preserves progress"),Clock.tick==103&&!Use.active()&&!Restored.care_grants().back().active&&Use.requests().back().progressed_ticks==3&&Use.requests().back().end==Care::End::AfterLoad);
    TestTrue(TEXT("Loading never activates residential rights"),!Restored.residential_right().active&&Restored.residential_right().activation_event_id==-1);

    const auto UnchangedWorld=Restored.save_bytes(),UnchangedUse=P::encode_care_document(Use.export_state());
    const auto UnchangedClock=Clock;
    const auto Refuse=[&](const FString& TextJson,const TCHAR* Label){
        const bool Rejected=!ReadNativeJournal(TextJson,6,Sources,Restored,Use,Clock,Error);
        return TestTrue(Label,Rejected&&Restored.save_bytes()==UnchangedWorld&&P::encode_care_document(Use.export_state())==UnchangedUse&&Clock.tick==UnchangedClock.tick&&Clock.fraction_bits==UnchangedClock.fraction_bits);
    };
    const auto Alter=[&](const TCHAR* Field,const TSharedPtr<FJsonValue>& Value,bool Resign){
        TSharedPtr<FJsonObject> O;FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),O);O->SetField(Field,Value);
        FString Hash;if(Resign&&NativeEnvelopeHash(*O,Hash))O->SetStringField(TEXT("envelope_sha256"),Hash);
        FString Out;FJsonSerializer::Serialize(O,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Out));return Out;
    };
    Refuse(Alter(TEXT("version"),MakeShared<FJsonValueNumber>(6),false),TEXT("Numeric version refused before publication"));
    Refuse(Alter(TEXT("version"),MakeShared<FJsonValueString>(TEXT("5")),true),TEXT("Rehashed wrong string version cannot fall back"));
    Refuse(Alter(TEXT("source_sha256"),MakeShared<FJsonValueString>(FString::ChrN(64,TEXT('0'))),true),TEXT("Rehashed wrong source refused"));
    Refuse(Alter(TEXT("payload_base64"),MakeShared<FJsonValueString>(TEXT("%%%")),true),TEXT("Rehashed invalid payload refused"));
    Refuse(Alter(TEXT("unexpected"),MakeShared<FJsonValueString>(TEXT("extra")),false),TEXT("Unknown native field refused"));
    Refuse(FString(TEXT("{\"version\":\"6\","))+Json.Mid(1),TEXT("Duplicate JSON key refused"));

    TArray<uint8> Fixture;if(!TestTrue(TEXT("Exact preserved baseline v5 fixture required"),SourceFile(
        FPaths::ProjectContentDir()/TEXT("LivingTown/Tests/active_meal_v5.paired"),
        TEXT("6ad091423a6feb6dda7895cf8977135f9d9082c744eea39431996f55d5f59bd6"),Fixture)))return false;
    const std::string LegacyRaw(reinterpret_cast<const char*>(Fixture.GetData()),size_t(Fixture.Num()));
    auto Legacy=P::decode_care_envelope_document(LegacyRaw);
    if(!TestTrue(TEXT("Immutable fixture is paired v5"),bool(Legacy)&&Legacy->version=="5"))return false;
    const auto OriginalWorld=P::decode(Legacy->world_payload);const auto OriginalUse=P::decode_care_document(Legacy->care_payload,true);
    if(!TestTrue(TEXT("Baseline fixture replays old world/care"),bool(OriginalWorld)&&bool(OriginalUse)))return false;
    // Only test source metadata is rebound to the exact compiled OLD family.
    // The original fixture file, financial events and care history stay intact.
    const auto OldSources=LegacyV5Sources(Sources);Legacy->bindings=OldSources;
    FString OldJson;if(!TestTrue(TEXT("Synthetic old native wrapper"),NativePayloadDocument(P::encode_care_envelope_document(*Legacy),OldSources,5,OldJson,Error)))return false;
    Refuse(OldJson,TEXT("Ordinary v6 load refuses complete v5 wrapper"));
    P::Kernel Imported;Care::ResidentUse ImportedUse("ben");P::ClockMetadata ImportedClock;
    if(!TestTrue(TEXT("Explicit old-family v5 import"),ReadNativeJournal(OldJson,5,Sources,Imported,ImportedUse,ImportedClock,Error)))return false;
    TestTrue(TEXT("Imported paid meal ledger and needs preserved"),Imported.coin("aria")==14&&Imported.coin("ben")==10&&Imported.rations()==1&&ImportedClock.tick==103&&Care::same_need_values(ImportedUse.needs(),OriginalUse->needs));
    TestTrue(TEXT("Import keeps progress and stops use without rights"),!ImportedUse.active()&&!Imported.residential_right().active&&Imported.residential_right().activation_event_id==-1&&ImportedUse.requests().back().progressed_ticks==3&&ImportedUse.requests().back().end==Care::End::AfterLoad);
    for(size_t N=0;N<OriginalWorld->events.size();++N)TestTrue(TEXT("Original financial and meal event bytes preserved"),P::detail::same_event(OriginalWorld->events[N],Imported.events()[N]));
    TestTrue(TEXT("V5 importer pins actual old core family"),OldSources.world.core_sha256==Utf8(LegacyV5CoreHash)&&OldSources.care_core_sha256==Utf8(LegacyCareHash)&&OldSources.world.core_sha256!=Sources.world.core_sha256);
    const auto V4=LegacyV4Sources(Sources);TestTrue(TEXT("V4 remains a separately pinned legacy family"),V4.world.core_sha256!=""&&V4.world.core_sha256!=OldSources.world.core_sha256&&V4.care_core_sha256==Utf8(LegacyCareHash));
    Legacy->bindings=Sources;
    FString WrongOld;if(!TestTrue(TEXT("Forge v5 wrapper with new source family"),NativePayloadDocument(P::encode_care_envelope_document(*Legacy),Sources,5,WrongOld,Error)))return false;
    const auto ImportedBefore=Imported.save_bytes();TestTrue(TEXT("Explicit v5 import never adopts header-provided new pins"),!ReadNativeJournal(WrongOld,5,Sources,Imported,ImportedUse,ImportedClock,Error)&&Imported.save_bytes()==ImportedBefore);

    P::Kernel NoSleep;Care::ResidentUse NoSleepUse("ben");
    if(!TestTrue(TEXT("Synthetic portable assignment only"),NoSleep.activate_residential({0,true,P::residential_registry_sha256}).ok))return false;
    const auto WithRight=P::save_care_envelope(NoSleep,NoSleepUse,Sources,{0,0});FString RightJson;
    if(!TestTrue(TEXT("Portable right history is independently valid"),bool(WithRight))||!TestTrue(TEXT("Native wrapper for negative right-history control"),NativePayloadDocument(*WithRight,Sources,6,RightJson,Error)))return false;
    Refuse(RightJson,TEXT("Meal-only native consumer cannot enable unimplemented residential authority via load"));
    return !HasAnyErrors();
}
