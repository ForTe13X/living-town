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
    Reject(TEXT("Unknown version rejected"),Change([](FJsonObject& O){O.SetStringField(TEXT("version"),TEXT("2"));}));
    Reject(TEXT("Duplicate keys rejected before conversion"),Valid.Replace(TEXT("\"version\":\"1\""),TEXT("\"version\":\"1\",\"version\":\"1\"")));
    Reject(TEXT("Logical-only legacy binding refuses"),TEXT("{\"schema\":\"LivingTown.LogicalCafeBinding\",\"version\":1}"));return true;
}
#endif
