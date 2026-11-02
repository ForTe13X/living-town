#include "LivingTownCafeBinding.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "CafeSHA256KnownAnswers.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/ScopeExit.h"
#include "HAL/FileManager.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "Containers/StringConv.h"

namespace
{
TSharedRef<FJsonValue> Vec(double X,double Y,double Z){return MakeShared<FJsonValueArray>(TArray<TSharedPtr<FJsonValue>>{MakeShared<FJsonValueNumber>(X),MakeShared<FJsonValueNumber>(Y),MakeShared<FJsonValueNumber>(Z)});}
TSharedRef<FJsonObject> Transform()
{
    auto O=MakeShared<FJsonObject>();O->SetField(TEXT("translation_cm"),Vec(0,0,0));O->SetField(TEXT("scale"),Vec(1,1,1));O->SetArrayField(TEXT("rotation_quat_xyzw"),{MakeShared<FJsonValueNumber>(0),MakeShared<FJsonValueNumber>(0),MakeShared<FJsonValueNumber>(0),MakeShared<FJsonValueNumber>(1)});return O;
}
TSharedRef<FJsonObject> Fixture()
{
    // Parser fixture only: paths/hashes are intentionally synthetic and cannot
    // satisfy the actual asset/geometry/visual/native world qualification gate.
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("format"),TEXT("LivingTown.CafeProjectionBinding"));O->SetStringField(TEXT("version"),TEXT("1"));O->SetStringField(TEXT("status"),TEXT("UE_PHYSICAL_QUALIFIED"));
    for(const TCHAR* K:{TEXT("physical_scene_sha256"),TEXT("source_projection_sha256"),TEXT("physical_qualification_sha256"),TEXT("visual_sha256")})O->SetStringField(K,FString::ChrN(64,'a'));
    auto Identity=MakeShared<FJsonObject>();Identity->SetStringField(TEXT("space_id"),TEXT("cafe"));Identity->SetStringField(TEXT("floor_id"),TEXT("1f"));Identity->SetStringField(TEXT("interaction_id"),TEXT("cafe1f_counter"));Identity->SetStringField(TEXT("property_id"),TEXT("cafe_ground_commercial_v1"));Identity->SetStringField(TEXT("model_asset_id"),TEXT("Main_cafe_L00_Public_Room_A00_cafe_counter"));O->SetObjectField(TEXT("logical_identity"),Identity);
    auto Resident=MakeShared<FJsonObject>();Resident->SetStringField(TEXT("id"),TEXT("ben"));Resident->SetStringField(TEXT("skeletal_mesh"),TEXT("/Game/ParserFixture/Ben.Ben"));Resident->SetStringField(TEXT("idle_walk_blendspace"),TEXT("/Game/ParserFixture/Motion.Motion"));Resident->SetStringField(TEXT("use_socket"),TEXT("hand_r"));Resident->SetObjectField(TEXT("mesh_transform"),Transform());O->SetObjectField(TEXT("resident"),Resident);
    auto Move=MakeShared<FJsonObject>();Move->SetNumberField(TEXT("capsule_radius_cm"),22);Move->SetNumberField(TEXT("capsule_half_height_cm"),85);Move->SetNumberField(TEXT("reach_cm"),100);Move->SetNumberField(TEXT("walk_speed_cm_s"),180);Move->SetNumberField(TEXT("camera_arm_cm"),250);O->SetObjectField(TEXT("movement"),Move);
    auto Spawn=MakeShared<FJsonObject>();Spawn->SetField(TEXT("feet_cm"),Vec(762.5,-12.5,77.2028112411499));Spawn->SetField(TEXT("rotation_degrees"),Vec(0,0,0));O->SetObjectField(TEXT("spawn"),Spawn);O->SetField(TEXT("counter_use_point_cm"),Vec(1140,-180,150));O->SetArrayField(TEXT("floor_bounds_cm"),{Vec(731,-469,73),Vec(1569,461,75)});
    const TSet<int32> Floors={8559,8562,8615,8649,8673,8684},Counters={8564,8565,8566,8570,8571,8572};TArray<TSharedPtr<FJsonValue>> Parts;
    for(int32 N=8534;N<=8822;++N){auto P=MakeShared<FJsonObject>();P->SetStringField(TEXT("id"),FString::Printf(TEXT("town_10_urban_core:node:%d"),N));P->SetStringField(TEXT("asset"),FString::Printf(TEXT("/Game/ParserFixture/SM_%d.SM_%d"),N,N));P->SetStringField(TEXT("render_sha256"),FString::ChrN(64,'b'));P->SetStringField(TEXT("collision_guid"),FString::ChrN(32,'c'));P->SetObjectField(TEXT("transform"),Transform());P->SetBoolField(TEXT("floor"),Floors.Contains(N));P->SetBoolField(TEXT("counter"),Counters.Contains(N));Parts.Add(MakeShared<FJsonValueObject>(P));}O->SetArrayField(TEXT("parts"),Parts);return O;
}
TSharedRef<FJsonObject> Current61Fixture()
{
    // Synthetic parser metadata only. Even the required family paths are not
    // loaded here; the fake qualification hash is no avatar/contact evidence.
    auto O=Fixture();O->SetStringField(TEXT("version"),TEXT("3"));
    auto R=O->GetObjectField(TEXT("resident"));
    R->SetStringField(TEXT("skeletal_mesh"),LivingTownCafeCurrent61Baked::MeshAsset);
    R->SetStringField(TEXT("idle_walk_blendspace"),LivingTownCafeCurrent61Baked::MotionAsset);
    R->SetStringField(TEXT("use_socket"),LivingTownCafeCurrent61Baked::PalmSocket);
    R->SetStringField(TEXT("motion_strategy"),LivingTownCafeCurrent61Baked::Strategy);
    R->SetStringField(TEXT("idle_animation"),LivingTownCafeCurrent61Baked::IdleAsset);
    R->SetStringField(TEXT("walk_animation"),LivingTownCafeCurrent61Baked::WalkAsset);
    auto C=MakeShared<FJsonObject>();C->SetStringField(TEXT("format"),TEXT("LivingTown.Current61BakedAvatarCalibration"));
    C->SetStringField(TEXT("version"),TEXT("1"));C->SetStringField(TEXT("status"),TEXT("UE_AVATAR_CONTACT_QUALIFIED"));
    C->SetStringField(TEXT("qualification_sha256"),FString::ChrN(64,'d'));
    auto Palm=Transform();Palm->SetField(TEXT("translation_cm"),Vec(1,2,3));C->SetObjectField(TEXT("palm_socket_transform"),Palm);
    C->SetNumberField(TEXT("walk_speed_cm_s"),137.5);
    C->SetNumberField(TEXT("idle_duration_seconds"),15.333332821726799);
    C->SetNumberField(TEXT("walk_duration_seconds"),2.333333139618238);
    R->SetObjectField(TEXT("avatar_calibration"),C);O->GetObjectField(TEXT("movement"))->SetNumberField(TEXT("walk_speed_cm_s"),137.5);
    return O;
}
FString Encode(TSharedRef<FJsonObject> O){FString S;FJsonSerializer::Serialize(O,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&S));return S;}
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafeBindingTest,"LivingTown.Native.CafeBindingRefusals",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafeBindingTest::RunTest(const FString&)
{
    if(!RunCafeSHA256KnownAnswers(*this))return false;
    const FString Path=FPaths::Combine(FPaths::ProjectSavedDir(),TEXT("CafePilotTests"),FGuid::NewGuid().ToString(EGuidFormats::Digits)+TEXT(".json"));IFileManager::Get().MakeDirectory(*FPaths::GetPath(Path),true);ON_SCOPE_EXIT{IFileManager::Get().Delete(*Path);};
    FLivingTownCafeBinding B;FString Error;TestFalse(TEXT("Missing physical source file refuses"),FLivingTownCafeBinding::ReadQualifiedFile(Path,B,Error));const FString Valid=Encode(Fixture());FFileHelper::SaveStringToFile(Valid,*Path);if(!TestTrue(TEXT("Exact parser fixture validates metadata only"),FLivingTownCafeBinding::ReadQualifiedFile(Path,B,Error)))return false;TestEqual(TEXT("Exact source census"),B.Parts.Num(),289);const FString Before=B.BindingFileSha256;
    auto Reject=[&](const TCHAR* Name,const FString& S){FFileHelper::SaveStringToFile(S,*Path);TestFalse(Name,FLivingTownCafeBinding::ReadQualifiedFile(Path,B,Error));TestEqual(TEXT("Refused binding leaves accepted output unchanged"),B.BindingFileSha256,Before);TestEqual(TEXT("Refused binding preserves complete census"),B.Parts.Num(),289);};
    auto Change=[&](TFunctionRef<void(FJsonObject&)> C){auto O=Fixture();C(*O);return Encode(O);};
    Reject(TEXT("Source-only calibration cannot start"),Change([](FJsonObject& O){O.SetStringField(TEXT("status"),TEXT("SOURCE_MATCHED_ENGINE_CALIBRATION_PENDING"));}));
    Reject(TEXT("Wrong resident cannot replace Ben"),Change([](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetStringField(TEXT("id"),TEXT("aria"));}));
    Reject(TEXT("Engine cube cannot substitute for visual"),Change([](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetStringField(TEXT("skeletal_mesh"),TEXT("/Engine/BasicShapes/Cube.Cube"));}));
    Reject(TEXT("Unrelated source node refuses despite correct count"),Change([](FJsonObject& O){O.GetArrayField(TEXT("parts"))[0]->AsObject()->SetStringField(TEXT("id"),TEXT("town_10_urban_core:node:9999"));}));
    Reject(TEXT("Noncanonical node id refuses"),Change([](FJsonObject& O){O.GetArrayField(TEXT("parts"))[0]->AsObject()->SetStringField(TEXT("id"),TEXT("town_10_urban_core:node:bogus"));}));
    Reject(TEXT("Correct count cannot hide moved floor role"),Change([](FJsonObject& O){const auto& P=O.GetArrayField(TEXT("parts"));P[8559-8534]->AsObject()->SetBoolField(TEXT("floor"),false);P[0]->AsObject()->SetBoolField(TEXT("floor"),true);}));
    Reject(TEXT("Correct count cannot hide moved counter role"),Change([](FJsonObject& O){const auto& P=O.GetArrayField(TEXT("parts"));P[8566-8534]->AsObject()->SetBoolField(TEXT("counter"),false);P[0]->AsObject()->SetBoolField(TEXT("counter"),true);}));
    Reject(TEXT("Duplicate imported path refuses source aliasing"),Change([](FJsonObject& O){const auto& P=O.GetArrayField(TEXT("parts"));P[1]->AsObject()->SetStringField(TEXT("asset"),P[0]->AsObject()->GetStringField(TEXT("asset")));}));
    Reject(TEXT("UI reach authority cannot be inserted"),Change([](FJsonObject& O){O.SetBoolField(TEXT("within_reach"),true);}));
    Reject(TEXT("Boolean capsule dimension cannot coerce"),Change([](FJsonObject& O){O.GetObjectField(TEXT("movement"))->SetBoolField(TEXT("capsule_radius_cm"),true);}));
    Reject(TEXT("Unknown version rejected"),Change([](FJsonObject& O){O.SetStringField(TEXT("version"),TEXT("4"));}));
    Reject(TEXT("Duplicate keys rejected before conversion"),Valid.Replace(TEXT("\"version\":\"1\""),TEXT("\"version\":\"1\",\"version\":\"1\"")));
    Reject(TEXT("Logical-only legacy binding refuses"),TEXT("{\"schema\":\"LivingTown.LogicalCafeBinding\",\"version\":1}"));

    FFileHelper::SaveStringToFile(Encode(Current61Fixture()),*Path);
    if(!TestTrue(TEXT("Complete synthetic V3 validates parser metadata only"),FLivingTownCafeBinding::ReadQualifiedFile(Path,B,Error)))return false;
    TestTrue(TEXT("V3 explicitly selects once-baked plain-player strategy"),B.MotionStrategy==ELivingTownCafeMotionStrategy::Current61BakedSingleNode);
    TestTrue(TEXT("V3 complete metadata predicate holds without loading assets"),B.HasValidatedCurrent61BakedAvatarBinding());
    TestEqual(TEXT("V3 retains all legacy room source parts"),B.Parts.Num(),289);
    TestEqual(TEXT("V3 reads declared speed rather than candidate100 or legacy180"),B.Current61BakedCalibration.WalkSpeedCmPerSecond,137.5);
    TestTrue(TEXT("V3 reads declared nonidentity palm transform"),B.Current61BakedCalibration.PalmSocketLocalTransform.GetTranslation()==FVector(1,2,3));
    const FString BeforeV3=B.BindingFileSha256;
    auto RejectV3=[&](const TCHAR* Name,TFunctionRef<void(FJsonObject&)> C)
    {
        auto O=Current61Fixture();C(*O);FFileHelper::SaveStringToFile(Encode(O),*Path);
        TestFalse(Name,FLivingTownCafeBinding::ReadQualifiedFile(Path,B,Error));
        TestEqual(TEXT("Refused V3 preserves accepted file identity"),B.BindingFileSha256,BeforeV3);
        TestTrue(TEXT("Refused V3 preserves accepted descriptor and roster"),B.HasValidatedCurrent61BakedAvatarBinding()&&B.Parts.Num()==289&&B.Current61BakedCalibration.WalkSpeedCmPerSecond==137.5&&B.Current61BakedCalibration.PalmSocketLocalTransform.GetTranslation()==FVector(1,2,3));
    };
    RejectV3(TEXT("V3 requires complete avatar descriptor"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->RemoveField(TEXT("avatar_calibration"));});
    RejectV3(TEXT("V3 rejects unqualified avatar status"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->GetObjectField(TEXT("avatar_calibration"))->SetStringField(TEXT("status"),TEXT("SOURCE_ONLY"));});
    RejectV3(TEXT("V3 rejects zero qualification hash"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->GetObjectField(TEXT("avatar_calibration"))->SetStringField(TEXT("qualification_sha256"),FString::ChrN(64,'0'));});
    RejectV3(TEXT("V3 rejects noncanonical qualification hash"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->GetObjectField(TEXT("avatar_calibration"))->SetStringField(TEXT("qualification_sha256"),FString::ChrN(64,'D'));});
    RejectV3(TEXT("V3 rejects injected descriptor authority"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->GetObjectField(TEXT("avatar_calibration"))->SetBoolField(TEXT("within_reach"),true);});
    RejectV3(TEXT("V3 rejects old root-aligned strategy"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetStringField(TEXT("motion_strategy"),LivingTownCafeWorker110::Strategy);});
    RejectV3(TEXT("V3 rejects another body family"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetStringField(TEXT("skeletal_mesh"),LivingTownCafeWorker110::MeshAsset);});
    RejectV3(TEXT("V3 rejects another motion family"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetStringField(TEXT("idle_walk_blendspace"),LivingTownCafeWorker110::MotionAsset);});
    RejectV3(TEXT("V3 rejects another idle clip"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetStringField(TEXT("idle_animation"),LivingTownCafeWorker110::IdleAsset);});
    RejectV3(TEXT("V3 rejects another walk clip"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetStringField(TEXT("walk_animation"),LivingTownCafeWorker110::WalkAsset);});
    RejectV3(TEXT("V3 rejects old palm socket"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetStringField(TEXT("use_socket"),LivingTownCafeWorker110::PalmSocket);});
    RejectV3(TEXT("V3 rejects double-applied mesh scale"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->GetObjectField(TEXT("mesh_transform"))->SetField(TEXT("scale"),Vec(.01,.01,.01));});
    RejectV3(TEXT("V3 rejects nonunit palm scale"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->GetObjectField(TEXT("avatar_calibration"))->GetObjectField(TEXT("palm_socket_transform"))->SetField(TEXT("scale"),Vec(2,1,1));});
    RejectV3(TEXT("V3 rejects invalid palm quaternion"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->GetObjectField(TEXT("avatar_calibration"))->GetObjectField(TEXT("palm_socket_transform"))->SetArrayField(TEXT("rotation_quat_xyzw"),{MakeShared<FJsonValueNumber>(0),MakeShared<FJsonValueNumber>(0),MakeShared<FJsonValueNumber>(0),MakeShared<FJsonValueNumber>(0)});});
    RejectV3(TEXT("V3 movement must match declared gait speed"),[](FJsonObject& O){O.GetObjectField(TEXT("movement"))->SetNumberField(TEXT("walk_speed_cm_s"),100);});
    RejectV3(TEXT("V3 rejects Boolean descriptor speed"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->GetObjectField(TEXT("avatar_calibration"))->SetBoolField(TEXT("walk_speed_cm_s"),true);});
    RejectV3(TEXT("V3 rejects out-of-range descriptor speed"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->GetObjectField(TEXT("avatar_calibration"))->SetNumberField(TEXT("walk_speed_cm_s"),59);});
    RejectV3(TEXT("V3 rejects truncated idle duration"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->GetObjectField(TEXT("avatar_calibration"))->SetNumberField(TEXT("idle_duration_seconds"),1);});
    RejectV3(TEXT("V3 rejects truncated walk duration"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->GetObjectField(TEXT("avatar_calibration"))->SetNumberField(TEXT("walk_duration_seconds"),1);});
    RejectV3(TEXT("V3 rejects legacy root correction field"),[](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetField(TEXT("idle_root_delta_cm"),Vec(0,0,0));});
    return true;
}

namespace
{
TSharedRef<FJsonObject> AuthoredFixture(bool bSmall=false)
{
    // Metadata-only fixtures. Synthetic meshes/materials cannot qualify assets,
    // body geometry, room movement or the new native runtime image.
    auto O=Fixture();O->SetStringField(TEXT("status"),TEXT("UE_ASSET_QUALIFIED_TRIAL"));
    const TSet<int32> RoleNodes={8559,8562,8615,8649,8673,8684,8564,8565,8566,8570,8571,8572};
    TArray<TSharedPtr<FJsonValue>> Parts;
    for(const auto& V:O->GetArrayField(TEXT("parts")))
    {
        auto P=V->AsObject();const int32 N=FCString::Atoi(*P->GetStringField(TEXT("id")).Mid(24));
        if(N>=8573&&N<=8606)continue;if(bSmall&&!RoleNodes.Contains(N))continue;
        if(N>=8564&&N<=8572)P->GetObjectField(TEXT("transform"))->SetField(TEXT("translation_cm"),Vec(-100,0,0));
        Parts.Add(V);
    }
    for(int32 I=0;I<(bSmall?1:6);++I)
    {
        auto P=MakeShared<FJsonObject>();P->SetStringField(TEXT("id"),FString::Printf(TEXT("authored_cafe:instance:Fixture_%d"),I));
        const FString Asset=I%3==0?TEXT("/Game/ParserFixture/Table.Table"):TEXT("/Game/ParserFixture/Chair.Chair");
        P->SetStringField(TEXT("asset"),Asset);P->SetStringField(TEXT("render_sha256"),FString::ChrN(64,'b'));P->SetStringField(TEXT("collision_guid"),FString::ChrN(32,'c'));
        P->SetObjectField(TEXT("transform"),Transform());P->SetBoolField(TEXT("floor"),false);P->SetBoolField(TEXT("counter"),false);Parts.Add(MakeShared<FJsonValueObject>(P));
    }
    O->SetArrayField(TEXT("parts"),Parts);auto C=MakeShared<FJsonObject>();C->SetStringField(TEXT("format"),TEXT("LivingTown.CafePartContract"));C->SetStringField(TEXT("version"),TEXT("1"));C->SetStringField(TEXT("scope"),TEXT("private_authored_cafe_scene.v1"));C->SetNumberField(TEXT("declared_count"),Parts.Num());
    TArray<TSharedPtr<FJsonValue>> Ids,Floors,Counters,Materials;TSet<FString> Assets;
    for(const auto& V:Parts)
    {
        const auto P=V->AsObject();auto Id=MakeShared<FJsonValueString>(P->GetStringField(TEXT("id")));Ids.Add(Id);
        if(P->GetBoolField(TEXT("floor")))Floors.Add(Id);if(P->GetBoolField(TEXT("counter")))Counters.Add(Id);
        const FString Asset=P->GetStringField(TEXT("asset"));if(Assets.Contains(Asset))continue;Assets.Add(Asset);
        auto M=MakeShared<FJsonObject>();M->SetStringField(TEXT("asset"),Asset);M->SetArrayField(TEXT("materials"),{MakeShared<FJsonValueString>(TEXT("/Game/ParserFixture/Material.Material"))});Materials.Add(MakeShared<FJsonValueObject>(M));
    }
    C->SetArrayField(TEXT("part_ids"),Ids);C->SetArrayField(TEXT("floor_ids"),Floors);C->SetArrayField(TEXT("counter_ids"),Counters);C->SetArrayField(TEXT("asset_materials"),Materials);
    auto Context=MakeShared<FJsonObject>();FString Tagged=TEXT("LivingTown.CafePartContext.v1\n");
    for(const TCHAR* K:{TEXT("parent_binding_sha256"),TEXT("layout_plan_sha256"),TEXT("asset_cold_proof_sha256"),TEXT("source_geometry_manifest_sha256")})
    {const FString H=FString::ChrN(64,'a');Context->SetStringField(K,H);Tagged+=H+TEXT("\n");}
    FTCHARToUTF8 Encoded(*Tagged);TArray<uint8> Bytes;Bytes.Append(reinterpret_cast<const uint8*>(Encoded.Get()),Encoded.Length());FString Digest;LivingTownCafeJournal::Sha256(Bytes,Digest);
    Context->SetStringField(TEXT("context_sha256"),Digest);O->SetStringField(TEXT("physical_qualification_sha256"),Digest);C->SetObjectField(TEXT("source_context"),Context);O->SetObjectField(TEXT("part_contract"),C);return O;
}
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafeAuthoredBindingTest,"LivingTown.Native.CafeAuthoredPartContractRefusals",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafeAuthoredBindingTest::RunTest(const FString&)
{
    TestEqual(TEXT("Domain-tagged source-context ASCII known answer"),AuthoredFixture()->GetObjectField(TEXT("part_contract"))->GetObjectField(TEXT("source_context"))->GetStringField(TEXT("context_sha256")),FString(TEXT("0b49c3e274c9d7d05bee9207fd6081f1fa827e9f599829b2ff7cbbe2316419d4")));
    const FString Path=FPaths::Combine(FPaths::ProjectSavedDir(),TEXT("CafePilotTests"),FGuid::NewGuid().ToString(EGuidFormats::Digits)+TEXT(".json"));IFileManager::Get().MakeDirectory(*FPaths::GetPath(Path),true);ON_SCOPE_EXIT{IFileManager::Get().Delete(*Path);};
    FLivingTownCafeBinding B;FString Error;
    FFileHelper::SaveStringToFile(Encode(AuthoredFixture(true)),*Path);if(!TestTrue(TEXT("A declared13-part metadata fixture demonstrates data-driven count"),FLivingTownCafeBinding::ReadQualifiedFile(Path,B,Error)))return false;TestEqual(TEXT("Declared13 parts"),B.Parts.Num(),13);
    FFileHelper::SaveStringToFile(Encode(AuthoredFixture()),*Path);if(!TestTrue(TEXT("Declared261 with two shared prototypes validates metadata only"),FLivingTownCafeBinding::ReadQualifiedFile(Path,B,Error)))return false;TestEqual(TEXT("Declared261 parts"),B.Parts.Num(),261);TestTrue(TEXT("Truthful trial contract"),B.bAuthoredSceneTrial&&B.HasValidatedPartRoster());const FString Before=B.BindingFileSha256;
    auto Reject=[&](const TCHAR* Name,TFunctionRef<void(FJsonObject&)> Change){auto O=AuthoredFixture();Change(*O);FFileHelper::SaveStringToFile(Encode(O),*Path);TestFalse(Name,FLivingTownCafeBinding::ReadQualifiedFile(Path,B,Error));TestEqual(TEXT("Refused trial preserves complete accepted output"),B.BindingFileSha256,Before);TestEqual(TEXT("Refused trial preserves261"),B.Parts.Num(),261);};
    Reject(TEXT("Count mismatch"),[](FJsonObject& O){O.GetObjectField(TEXT("part_contract"))->SetNumberField(TEXT("declared_count"),260);});
    Reject(TEXT("Empty declaration"),[](FJsonObject& O){O.GetObjectField(TEXT("part_contract"))->SetNumberField(TEXT("declared_count"),0);});
    Reject(TEXT("Bounded declaration"),[](FJsonObject& O){O.GetObjectField(TEXT("part_contract"))->SetNumberField(TEXT("declared_count"),513);});
    Reject(TEXT("Fractional declaration"),[](FJsonObject& O){O.GetObjectField(TEXT("part_contract"))->SetNumberField(TEXT("declared_count"),261.5);});
    Reject(TEXT("Truthful nonfinal status required"),[](FJsonObject& O){O.SetStringField(TEXT("status"),TEXT("UE_PHYSICAL_QUALIFIED"));});
    Reject(TEXT("Wrong scope"),[](FJsonObject& O){O.GetObjectField(TEXT("part_contract"))->SetStringField(TEXT("scope"),TEXT("unbounded"));});
    Reject(TEXT("Missing source context"),[](FJsonObject& O){O.GetObjectField(TEXT("part_contract"))->RemoveField(TEXT("source_context"));});
    Reject(TEXT("Wrong context digest"),[](FJsonObject& O){O.GetObjectField(TEXT("part_contract"))->GetObjectField(TEXT("source_context"))->SetStringField(TEXT("context_sha256"),FString::ChrN(64,'f'));});
    Reject(TEXT("Undeclared instance"),[](FJsonObject& O){O.GetArrayField(TEXT("parts")).Last()->AsObject()->SetStringField(TEXT("id"),TEXT("authored_cafe:instance:Undeclared"));});
    Reject(TEXT("Wrong role"),[](FJsonObject& O){O.GetArrayField(TEXT("parts")).Last()->AsObject()->SetBoolField(TEXT("floor"),true);});
    Reject(TEXT("Negative trial scale"),[](FJsonObject& O){O.GetArrayField(TEXT("parts")).Last()->AsObject()->GetObjectField(TEXT("transform"))->SetField(TEXT("scale"),Vec(-1,1,1));});
    Reject(TEXT("Shared prototype cannot have conflicting GUID"),[](FJsonObject& O){O.GetArrayField(TEXT("parts")).Last()->AsObject()->SetStringField(TEXT("collision_guid"),FString::ChrN(32,'d'));});
    Reject(TEXT("Material roster must cover actual unique assets"),[](FJsonObject& O){auto C=O.GetObjectField(TEXT("part_contract"));auto A=C->GetArrayField(TEXT("asset_materials"));A.Pop();C->SetArrayField(TEXT("asset_materials"),A);});
    Reject(TEXT("Empty material slots"),[](FJsonObject& O){O.GetObjectField(TEXT("part_contract"))->GetArrayField(TEXT("asset_materials"))[0]->AsObject()->SetArrayField(TEXT("materials"),{});});
    Reject(TEXT("Context cannot inject authority"),[](FJsonObject& O){O.GetObjectField(TEXT("part_contract"))->SetBoolField(TEXT("within_reach"),true);});
    const auto Saved=B.Parts.Last();B.Parts.Pop();TestFalse(TEXT("Venue roster cannot retain stale validation after cardinality mutation"),B.HasValidatedPartRoster());B.Parts.Add(Saved);TestTrue(TEXT("Complete original roster restored in test memory"),B.HasValidatedPartRoster());return true;
}

#endif
