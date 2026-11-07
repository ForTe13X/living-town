#include "LivingTownCookedStartup.h"
#include "CoreGlobals.h"
#include "LivingTownTileData.h"
#include "LivingTownCafeBinding.h"
#include "Engine/World.h"
#include "UObject/Package.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformProperties.h"
#include "HAL/PlatformTime.h"
#include "HAL/PlatformFileManager.h"
#include "IPlatformFilePak.h"
#include "IO/IoDispatcher.h"
#include "IO/IoChunkId.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Containers/UnrealString.h"
#include "Serialization/JsonSerializer.h"
#include "Dom/JsonObject.h"
#include "Dom/JsonValue.h"

namespace
{
const TCHAR* Root=TEXT("/Game/LivingTown_UEPilot/FullTownIntegrationB749_v001/L_B749_Subset_v001");
struct FPin { const TCHAR* Package; int64 Bytes; const TCHAR* Sha; bool Map; };
const FPin Pins[]={
 {TEXT("/Game/LivingTown_UEPilot/FullTownIntegrationB749_v001/L_B749_Subset_v001"),17716,TEXT("d405332877c3757aad55557313bba6693cfbf6b5be2f13584b4d992dbc0f0642"),true},
 {TEXT("/Game/LivingTown_UEPilot/FullTownIntegrationB749_v001/DA_B749_Subset_v001"),1315578,TEXT("910a95cf5d083a30d0401ced33083c66ce1f7d1092c5b22ee47e4594cc598926"),false},
 {TEXT("/Game/LivingTown_UEPilot/FullTownWorld_v001/Units/L_U0131"),66210,TEXT("913eadaa79e7d90aa820cff1e08a221f48cf37e5079b39589e3d97672c447339"),true},
 {TEXT("/Game/LivingTown_UEPilot/FullTownIntegrationB749_v001/Units/L_B749_v001"),701402,TEXT("7e0b6bf1f314a0e7fd631ce4cfecc738971f36386a20724b579117bca1d98604"),true},
 {TEXT("/Game/LivingTown_UEPilot/FullTownIntegrationB749_v001/Units/L_Ground156_v001"),145199,TEXT("28301d6a504dfb4edbad6c0bac98b231d5f05a5bf88d52c7e14a29bdd5af6662"),true}
};
struct FReadyViewState
{
    TWeakObjectPtr<const UWorld> World;
    bool Verified=false,Controllable=false,ViewLogged=false;
    bool IsFor(const UWorld* Candidate) const { return Candidate&&World.Get()==Candidate; }
    void Arm(const UWorld* Candidate) { World=Candidate;Verified=Controllable=ViewLogged=false; }
    void Invalidate(const UWorld* Candidate) { if(IsFor(Candidate))Verified=Controllable=false; }
    bool Consume(const UWorld* Candidate)
    {
        if(!IsFor(Candidate)||!Verified||!Controllable||ViewLogged)return false;
        ViewLogged=true;return true;
    }
};
FReadyViewState ReadyView;
bool Fail(FString& Error,const TCHAR* Reason){Error=Reason;return false;}
bool Keys(const FJsonObject& O,std::initializer_list<const TCHAR*> Names)
{
    if(O.Values.Num()!=int32(Names.size()))return false;
    for(const TCHAR* N:Names)if(!O.Values.Contains(N))return false;
    return true;
}
bool Size(const FJsonObject& O,int64& N)
{
    FString S;if(!O.TryGetStringField(TEXT("bytes"),S)||!LexTryParseString(N,*S))return false;
    return N>0&&N<=64*1024*1024&&LexToString(N)==S;
}
bool BarePak(const FString& S)
{
    return S.Len()>4&&S.Len()<=128&&S.EndsWith(TEXT(".pak"))&&FPaths::GetCleanFilename(S)==S&&!S.Contains(TEXT(":"))&&!S.Contains(TEXT(".."));
}
bool HashFile(const FString& Path,int64 Size,const FString& Sha)
{
    TArray<uint8> Bytes;FString Actual;
    return IFileManager::Get().FileSize(*Path)==Size&&FFileHelper::LoadFileToArray(Bytes,*Path)&&Bytes.Num()==Size&&
        LivingTownTiles::HashBytes(Bytes,Actual)&&Actual==Sha;
}
bool MountedNames(FPakPlatformFile& Pak,TSet<FString>& Names)
{
    TArray<FString> Paths;Pak.GetMountedPakFilenames(Paths);
    if(Paths.IsEmpty()||Paths.Num()>8)return false;
    for(const FString& Path:Paths)
    {
        const FString Name=FPaths::GetCleanFilename(Path).ToLower();
        if(!BarePak(Name)||Names.Contains(Name))return false;
        Names.Add(Name);
    }
    return true;
}
}

bool LivingTownCookedStartup::IsRequested()
{
#if LIVINGTOWN_COOKED_STARTUP_DIAGNOSTIC
    FString Map;
    return FPlatformProperties::RequiresCookedData()&&FParse::Param(FCommandLine::Get(),TEXT("LivingTownCookedB749Startup"))&&
        FParse::Param(FCommandLine::Get(),TEXT("LivingTownViewportCsv"))&&
        FParse::Value(FCommandLine::Get(),TEXT("LivingTownViewportCsvMap="),Map)&&Map==Root;
#else
    return false;
#endif
}

void LivingTownCookedStartup::ArmWorld(const UWorld* World)
{
    if(!IsRequested()||!World||World->GetOutermost()->GetName()!=Root)return;
    ReadyView.Arm(World);
}

void LivingTownCookedStartup::InvalidateWorld(const UWorld* World)
{
    if(!IsRequested())return;
    ReadyView.Invalidate(World);
}

bool LivingTownCookedStartup::VerifyPackage(const FString& Package,int64 SourceBytes,const FString& SourceSha,FString& Error)
{
    ReadyView.Verified=false;
    if(!IsInGameThread()||!IsRequested())return Fail(Error,TEXT("cook_smoke_not_explicit_development_game"));
    const FPin* Requested=nullptr;
    for(const FPin& P:Pins)if(Package==P.Package)Requested=&P;
    if(!Requested||Requested->Bytes!=SourceBytes||SourceSha!=Requested->Sha)return Fail(Error,TEXT("cook_smoke_original_source_pin_changed"));
    if(FParse::Param(FCommandLine::Get(),TEXT("UseIoStore"))||FParse::Param(FCommandLine::Get(),TEXT("LookLooseFirst"))||
       (FIoDispatcher::IsInitialized()&&FIoDispatcher::Get().DoesChunkExist(CreateIoChunkId(0,0,EIoChunkType::ScriptObjects))))
        return Fail(Error,TEXT("cook_smoke_standard_pak_only_no_iostore_or_loose_preference"));
    auto* Pak=static_cast<FPakPlatformFile*>(FPlatformFileManager::Get().FindPlatformFile(FPakPlatformFile::GetTypeName()));
    if(!Pak)return Fail(Error,TEXT("cook_smoke_active_pak_layer_missing"));
    FString Expected;FParse::Value(FCommandLine::Get(),TEXT("LivingTownCookedLedgerSha256="),Expected);
    if(!LivingTownTiles::IsSha256(Expected))return Fail(Error,TEXT("cook_smoke_root_frozen_fixture_digest_missing"));
    // This fixed loose NonUFS fixture is outside all hashed/cooked Paks. Its digest is
    // selected by the separately frozen diagnostic host, not a production admission.
    const FString Fixture=FPaths::Combine(FPaths::ProjectDir(),TEXT("CookedStartup/B749Fixture.json"));
    if(Pak->FindFileInPakFiles(*Fixture))return Fail(Error,TEXT("cook_smoke_fixture_must_be_loose_NonUFS"));
    const int64 FixtureSize=IFileManager::Get().FileSize(*Fixture);TArray<uint8> Raw;FString Digest,Text;
    if(FixtureSize<=0||FixtureSize>65536||!FFileHelper::LoadFileToArray(Raw,*Fixture)||Raw.Num()!=FixtureSize||
       !LivingTownTiles::HashBytes(Raw,Digest)||Digest!=Expected)return Fail(Error,TEXT("cook_smoke_fixture_bytes_changed"));
    FFileHelper::BufferToString(Text,Raw.GetData(),Raw.Num());TSharedPtr<FJsonObject> O;
    if(!LivingTownCafeJournal::HasUniqueObjectKeys(Text)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),O)||!O||
       !Keys(*O,{TEXT("schema"),TEXT("scope"),TEXT("source_basis_sha256"),TEXT("pak_files"),TEXT("packages")}))return Fail(Error,TEXT("cook_smoke_fixture_schema"));
    FString Schema,Scope,Basis;
    if(!O->TryGetStringField(TEXT("schema"),Schema)||Schema!=TEXT("LivingTown.B749CookedStartupFixture.v1")||
       !O->TryGetStringField(TEXT("scope"),Scope)||Scope!=TEXT("DevelopmentCookedB749StartupOnly")||
       !O->TryGetStringField(TEXT("source_basis_sha256"),Basis)||Basis!=TEXT("3c6a03a71c736750273329625ce2c9c5bfcbf6d2bf7132b0b7fe6dd70d949a6f"))return Fail(Error,TEXT("cook_smoke_fixture_source_scope"));
    const TArray<TSharedPtr<FJsonValue>> *PakRows=nullptr,*Packages=nullptr;
    if(!O->TryGetArrayField(TEXT("pak_files"),PakRows)||!O->TryGetArrayField(TEXT("packages"),Packages)||PakRows->Num()<1||PakRows->Num()>8||Packages->Num()!=UE_ARRAY_COUNT(Pins))return Fail(Error,TEXT("cook_smoke_fixture_exact_counts"));
    TSet<FString> ExpectedPaks,Mounted,SeenPackages;
    for(const auto& Row:*PakRows)
    {
        FString Name;if(!Row.IsValid()||!Row->TryGetString(Name)||!BarePak(Name)||ExpectedPaks.Contains(Name.ToLower()))return Fail(Error,TEXT("cook_smoke_pak_names"));
        ExpectedPaks.Add(Name.ToLower());
    }
    if(!MountedNames(*Pak,Mounted)||Mounted.Num()!=ExpectedPaks.Num())return Fail(Error,TEXT("cook_smoke_mounted_pak_set"));
    for(const FString& Name:Mounted)if(!ExpectedPaks.Contains(Name.ToLower()))return Fail(Error,TEXT("cook_smoke_extra_or_wrong_pak"));
    // Validate all five critical packages on every gate. No metadata-only cache
    // substitutes for cooked member hashes. Whole-stage/Pak hashes remain host guards.
    for(const auto& Row:*Packages)
    {
        auto P=Row.IsValid()&&Row->Type==EJson::Object?Row->AsObject():nullptr;FString Name,SourceSize,Sha;
        if(!P||!Keys(*P,{TEXT("package"),TEXT("source_bytes"),TEXT("source_sha256"),TEXT("files")})||
           !P->TryGetStringField(TEXT("package"),Name)||SeenPackages.Contains(Name)||
           !P->TryGetStringField(TEXT("source_bytes"),SourceSize)||!P->TryGetStringField(TEXT("source_sha256"),Sha))return Fail(Error,TEXT("cook_smoke_package_row"));
        const FPin* Pin=nullptr;for(const FPin& Candidate:Pins)if(Name==Candidate.Package)Pin=&Candidate;
        if(!Pin||SourceSize!=LexToString(Pin->Bytes)||Sha!=Pin->Sha)return Fail(Error,TEXT("cook_smoke_provenance_changed"));
        SeenPackages.Add(Name);const TArray<TSharedPtr<FJsonValue>>* Files=nullptr;
        if(!P->TryGetArrayField(TEXT("files"),Files)||Files->Num()<1||Files->Num()>4)return Fail(Error,TEXT("cook_smoke_piece_count"));
        TSet<FString> Suffixes;
        for(const auto& File:*Files)
        {
            auto F=File.IsValid()&&File->Type==EJson::Object?File->AsObject():nullptr;FString Suffix,FileSha,Owner;int64 Bytes=0;
            if(!F||!Keys(*F,{TEXT("suffix"),TEXT("bytes"),TEXT("sha256"),TEXT("pak_file")})||!F->TryGetStringField(TEXT("suffix"),Suffix)||
               !F->TryGetStringField(TEXT("sha256"),FileSha)||!LivingTownTiles::IsSha256(FileSha)||!F->TryGetStringField(TEXT("pak_file"),Owner)||
               !ExpectedPaks.Contains(Owner.ToLower())||!Size(*F,Bytes)||Suffixes.Contains(Suffix)||
               !(Suffix==TEXT("header")||Suffix==TEXT(".uexp")||Suffix==TEXT(".ubulk")||Suffix==TEXT(".uptnl")))return Fail(Error,TEXT("cook_smoke_piece_row"));
            Suffixes.Add(Suffix);const FString Ext=Suffix==TEXT("header")?(Pin->Map?TEXT(".umap"):TEXT(".uasset")):Suffix;
            const FString FileName=FPackageName::LongPackageNameToFilename(Name,Ext);TRefCountPtr<FPakFile> FoundPak;
            if(!Pak->FindFileInPakFiles(*FileName,&FoundPak)||!FoundPak||!FPaths::GetCleanFilename(FoundPak->GetFilename()).Equals(Owner,ESearchCase::IgnoreCase)||!HashFile(FileName,Bytes,FileSha))return Fail(Error,TEXT("cook_smoke_cooked_member_identity"));
        }
        if(!Suffixes.Contains(TEXT("header")))return Fail(Error,TEXT("cook_smoke_header_missing"));
        for(const TCHAR* Extra:{TEXT(".uexp"),TEXT(".ubulk"),TEXT(".uptnl")})
            if(IFileManager::Get().FileExists(*FPackageName::LongPackageNameToFilename(Name,Extra))&&!Suffixes.Contains(Extra))return Fail(Error,TEXT("cook_smoke_unlisted_piece"));
    }
    TSet<FString> After;if(!MountedNames(*Pak,After)||After.Num()!=Mounted.Num())return Fail(Error,TEXT("cook_smoke_mounts_changed_during_check"));
    for(const FString& Name:After)if(!Mounted.Contains(Name))return Fail(Error,TEXT("cook_smoke_mounts_changed_during_check"));
    ReadyView.Verified=true;Error.Reset();return true;
}

void LivingTownCookedStartup::Mark(const TCHAR* Event,const UWorld* World)
{
    if(!IsRequested()||(World&&World->GetOutermost()->GetName()!=Root))return;
    if(FCString::Strcmp(Event,TEXT("Controllable"))==0)
    {
        if(!ReadyView.IsFor(World))return;
        ReadyView.Controllable=true;
    }
    UE_LOG(LogTemp,Display,TEXT("LT_COOKED_STARTUP_DIAGNOSTIC event=%s qpc=%llu seconds_per_cycle=%.17g frame=%llu critical_identity_verified=%d production_cooked_admitted=0"),Event,FPlatformTime::Cycles64(),FPlatformTime::GetSecondsPerCycle64(),GFrameCounter,ReadyView.Verified?1:0);
}
void LivingTownCookedStartup::ObserveReadyPlayerView(const UWorld* World)
{
    if(IsRequested()&&World&&World->GetOutermost()->GetName()==Root&&ReadyView.Consume(World))Mark(TEXT("FirstReadyPlayerViewSample"),World);
}

#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "UObject/StrongObjectPtr.h"
#include "UObject/UObjectGlobals.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCookedStartupMarkerLifecycle,
    "LivingTown.FullTown.CookedStartupMarkerLifecycle",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FLivingTownCookedStartupMarkerLifecycle::RunTest(const FString& Parameters)
{
    // Exercise local marker state only: no package verification or cooked admission.
    TStrongObjectPtr<UWorld> First(NewObject<UWorld>(GetTransientPackage()));
    TStrongObjectPtr<UWorld> Second(NewObject<UWorld>(GetTransientPackage()));
    FReadyViewState State;
    State.Arm(First.Get());State.Verified=State.Controllable=true;
    State.Invalidate(First.Get());
    TestFalse(TEXT("Stop before camera sample invalidates readiness"),State.Consume(First.Get()));
    State.Arm(Second.Get());
    TestFalse(TEXT("New world clears previous identity"),State.Verified);
    TestFalse(TEXT("New world clears previous controllability"),State.Controllable);
    TestFalse(TEXT("New world clears previous view sample"),State.ViewLogged);
    State.Verified=State.Controllable=true;
    TestFalse(TEXT("Another world in the same package cannot inherit readiness"),State.Consume(First.Get()));
    TestTrue(TEXT("Fresh ready world emits its first sample"),State.Consume(Second.Get()));
    TestFalse(TEXT("Ready view is emitted only once"),State.Consume(Second.Get()));
    return true;
}
#endif
