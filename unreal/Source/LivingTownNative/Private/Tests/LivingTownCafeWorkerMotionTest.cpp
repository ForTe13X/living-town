#include "LivingTownCafeBinding.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Animation/BlendSpace.h"
#include "Animation/BlendSpace1D.h"
#include "UObject/UObjectGlobals.h"
#include "UObject/UnrealType.h"
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

namespace
{
TSharedRef<FJsonObject> Worker110Fixture()
{
    auto O=Fixture();O->SetStringField(TEXT("version"),TEXT("2"));
    const auto R=O->GetObjectField(TEXT("resident"));
    R->SetStringField(TEXT("skeletal_mesh"),LivingTownCafeWorker110::MeshAsset);
    R->SetStringField(TEXT("idle_walk_blendspace"),LivingTownCafeWorker110::MotionAsset);
    R->SetStringField(TEXT("use_socket"),LivingTownCafeWorker110::PalmSocket);
    R->SetStringField(TEXT("motion_strategy"),LivingTownCafeWorker110::Strategy);
    R->SetStringField(TEXT("idle_animation"),LivingTownCafeWorker110::IdleAsset);
    R->SetStringField(TEXT("walk_animation"),LivingTownCafeWorker110::WalkAsset);
    const FVector D=LivingTownCafeWorker110::RootDeltaCm();R->SetField(TEXT("idle_root_delta_cm"),Vec(D.X,D.Y,D.Z));
    O->GetObjectField(TEXT("movement"))->SetNumberField(TEXT("walk_speed_cm_s"),110);
    // Synthetic dimensions and source-part metadata are parser inputs only.
    // No asset, calibration, contact or Game qualification is inferred here.
    return O;
}
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafeWorker110BindingTest,"LivingTown.Native.CafeWorker110BindingRefusals",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafeWorker110BindingTest::RunTest(const FString&)
{
    // Plain owned transient objects test the exact production policy predicate.
    // They have no skeleton/samples and cannot establish qualified assets or playback.
    auto* PolicyMotion=NewObject<UBlendSpace1D>();
    if(!TestNotNull(TEXT("Owned default BlendSpace1D policy fixture"),PolicyMotion))return false;
    auto AxisProperty=FindFProperty<FStructProperty>(UBlendSpace::StaticClass(),TEXT("BlendParameters"));
    if(!TestTrue(TEXT("Owned fixture exposes typed editable three-axis property"),AxisProperty&&AxisProperty->ArrayDim==3&&AxisProperty->Struct==FBlendParameter::StaticStruct()&&AxisProperty->HasAnyPropertyFlags(CPF_Edit)))return false;
    auto Axis=AxisProperty->ContainerPtrToValuePtr<FBlendParameter>(PolicyMotion,0);
    // Explicitly set the declared candidate policy; constructor/CDO defaults are not evidence.
    PolicyMotion->bScaleAnimation=false;PolicyMotion->TargetWeightInterpolationSpeedPerSec=0.f;
    PolicyMotion->InterpolationParam[0].InterpolationTime=0.f;Axis->bSnapToGrid=false;Axis->bWrapInput=false;
    TestTrue(TEXT("Declared public no-filter/no-scale policy accepted independently of asset qualification"),LivingTownCafeWorker110::HasUnfilteredUnscaled1DMotionPolicy(PolicyMotion));
    TestFalse(TEXT("Null motion policy refuses"),LivingTownCafeWorker110::HasUnfilteredUnscaled1DMotionPolicy(nullptr));
    TestFalse(TEXT("Base BlendSpace wrong class refuses"),LivingTownCafeWorker110::HasUnfilteredUnscaled1DMotionPolicy(NewObject<UBlendSpace>()));
    PolicyMotion->bScaleAnimation=true;
    TestFalse(TEXT("Effective1D animation scaling refuses"),LivingTownCafeWorker110::HasUnfilteredUnscaled1DMotionPolicy(PolicyMotion));PolicyMotion->bScaleAnimation=false;
    PolicyMotion->TargetWeightInterpolationSpeedPerSec=1.f;
    TestFalse(TEXT("Target sample-weight smoothing refuses"),LivingTownCafeWorker110::HasUnfilteredUnscaled1DMotionPolicy(PolicyMotion));PolicyMotion->TargetWeightInterpolationSpeedPerSec=0.f;
    PolicyMotion->InterpolationParam[0].InterpolationTime=.25f;
    TestFalse(TEXT("Axis0 input interpolation refuses"),LivingTownCafeWorker110::HasUnfilteredUnscaled1DMotionPolicy(PolicyMotion));PolicyMotion->InterpolationParam[0].InterpolationTime=0.f;
    // Mutate only this owned fixture's typed EditAnywhere axis flags. No const_cast,
    // protected getter/setter, package conversion, asset load or save is used.
    Axis->bSnapToGrid=true;
    TestFalse(TEXT("Axis0 snap-to-grid refuses"),LivingTownCafeWorker110::HasUnfilteredUnscaled1DMotionPolicy(PolicyMotion));Axis->bSnapToGrid=false;
    Axis->bWrapInput=true;
    TestFalse(TEXT("Axis0 wrapped input refuses"),LivingTownCafeWorker110::HasUnfilteredUnscaled1DMotionPolicy(PolicyMotion));Axis->bWrapInput=false;
    TestTrue(TEXT("Restored fixture no-filter/no-scale policy accepted"),LivingTownCafeWorker110::HasUnfilteredUnscaled1DMotionPolicy(PolicyMotion));
    const FString Path=FPaths::Combine(FPaths::ProjectSavedDir(),TEXT("CafePilotTests"),FGuid::NewGuid().ToString(EGuidFormats::Digits)+TEXT("_worker110.json"));
    IFileManager::Get().MakeDirectory(*FPaths::GetPath(Path),true);ON_SCOPE_EXIT{IFileManager::Get().Delete(*Path);};
    FLivingTownCafeBinding B;FString Error;
    auto ReadText=[&](const FString& Text)
    {
        if(!TestTrue(TEXT("Owned parser fixture writes successfully"),FFileHelper::SaveStringToFile(Text,*Path)))return false;
        return FLivingTownCafeBinding::ReadQualifiedFile(Path,B,Error);
    };
    if(!TestTrue(TEXT("V1 metadata remains accepted"),ReadText(Encode(Fixture()))))return false;
    TestTrue(TEXT("V1 default strategy remains legacy"),B.MotionStrategy==ELivingTownCafeMotionStrategy::LegacySingleNode);
    TestTrue(TEXT("V1 root correction metadata stays empty"),B.IdleAnimationPath.IsEmpty()&&B.WalkAnimationPath.IsEmpty()&&B.IdleRootDeltaCm==FVector::ZeroVector);
    TestEqual(TEXT("V1 movement remains180"),B.WalkSpeedCmPerSecond,180.f);
    const FString Valid=Encode(Worker110Fixture());
    if(!TestTrue(TEXT("V2 known family metadata parses only"),ReadText(Valid)))return false;
    TestTrue(TEXT("V2 explicit strategy selected"),B.MotionStrategy==ELivingTownCafeMotionStrategy::CafeWorker110RootAligned);
    TestEqual(TEXT("V2 fresh mesh path"),B.VisualAssetPath,FString(LivingTownCafeWorker110::MeshAsset));
    TestEqual(TEXT("V2 original idle path"),B.IdleAnimationPath,FString(LivingTownCafeWorker110::IdleAsset));
    TestEqual(TEXT("V2 original walk path"),B.WalkAnimationPath,FString(LivingTownCafeWorker110::WalkAsset));
    TestTrue(TEXT("V2 exact reviewed post-sample delta"),B.IdleRootDeltaCm==LivingTownCafeWorker110::RootDeltaCm());
    TestEqual(TEXT("V2 speed matches110 axis"),B.WalkSpeedCmPerSecond,110.f);
    const FString Before=B.BindingFileSha256;
    auto Reject=[&](const TCHAR* Label,const FString& Text)
    {
        TestFalse(Label,ReadText(Text));
        TestEqual(TEXT("Rejection leaves accepted binding hash unchanged"),B.BindingFileSha256,Before);
        TestTrue(TEXT("Rejection retains accepted strategy and exact root delta"),B.MotionStrategy==ELivingTownCafeMotionStrategy::CafeWorker110RootAligned&&B.IdleRootDeltaCm==LivingTownCafeWorker110::RootDeltaCm());
        TestEqual(TEXT("Rejection retains complete289 source-part census"),B.Parts.Num(),289);
    };
    auto Change=[&](TFunctionRef<void(FJsonObject&)> Mutation){auto O=Worker110Fixture();Mutation(*O);return Encode(O);};
    Reject(TEXT("Unknown future version refuses"),Change([](FJsonObject& O){O.SetStringField(TEXT("version"),TEXT("3"));}));
    Reject(TEXT("V2 without strategy refuses"),Change([](FJsonObject& O){O.GetObjectField(TEXT("resident"))->RemoveField(TEXT("motion_strategy"));}));
    Reject(TEXT("Unknown strategy refuses"),Change([](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetStringField(TEXT("motion_strategy"),TEXT("unreviewed"));}));
    Reject(TEXT("V2 fields cannot leak into V1"),Change([](FJsonObject& O){O.SetStringField(TEXT("version"),TEXT("1"));}));
    Reject(TEXT("Old180 speed cannot drive110 family"),Change([](FJsonObject& O){O.GetObjectField(TEXT("movement"))->SetNumberField(TEXT("walk_speed_cm_s"),180);}));
    Reject(TEXT("Near110 is still a different contract"),Change([](FJsonObject& O){O.GetObjectField(TEXT("movement"))->SetNumberField(TEXT("walk_speed_cm_s"),110.01);}));
    Reject(TEXT("Boolean speed cannot coerce"),Change([](FJsonObject& O){O.GetObjectField(TEXT("movement"))->SetBoolField(TEXT("walk_speed_cm_s"),true);}));
    Reject(TEXT("Missing original idle refuses"),Change([](FJsonObject& O){O.GetObjectField(TEXT("resident"))->RemoveField(TEXT("idle_animation"));}));
    Reject(TEXT("Reauthored idle cannot replace original clip"),Change([](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetStringField(TEXT("idle_animation"),TEXT("/Game/Other/Centered.Centered"));}));
    Reject(TEXT("Swapped original clips refuse"),Change([](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetStringField(TEXT("walk_animation"),LivingTownCafeWorker110::IdleAsset);}));
    Reject(TEXT("Source mesh cannot replace fresh110 mesh"),Change([](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetStringField(TEXT("skeletal_mesh"),TEXT("/Game/LivingTown_UEPilot/CafeWorkerBen_v001/SK_CafeWorkerBen_v001.SK_CafeWorkerBen_v001"));}));
    Reject(TEXT("Old180 motion cannot substitute"),Change([](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetStringField(TEXT("idle_walk_blendspace"),TEXT("/Game/LivingTown_UEPilot/CafeWorkerBen_v001/BS_CafeWorkerIdleWalk_v001.BS_CafeWorkerIdleWalk_v001"));}));
    Reject(TEXT("Wrong hand socket refuses"),Change([](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetStringField(TEXT("use_socket"),TEXT("hand_r"));}));
    Reject(TEXT("Changed delta refuses"),Change([](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetField(TEXT("idle_root_delta_cm"),Vec(0,0,0));}));
    Reject(TEXT("New root-motion/rate policy cannot be smuggled"),Change([](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetNumberField(TEXT("walk_rate_scale"),2);}));
    Reject(TEXT("Material override cannot be smuggled"),Change([](FJsonObject& O){O.GetObjectField(TEXT("resident"))->SetStringField(TEXT("material"),TEXT("/Engine/EngineMaterials/DefaultMaterial.DefaultMaterial"));}));
    Reject(TEXT("Pending physical profile cannot be ready"),Change([](FJsonObject& O){O.SetStringField(TEXT("status"),TEXT("PHYSICAL_CALIBRATION_PENDING"));}));
    Reject(TEXT("Duplicate V2 version key refuses"),Valid.Replace(TEXT("\"version\":\"2\""),TEXT("\"version\":\"2\",\"version\":\"2\"")));
    auto Legacy=Fixture();Legacy->GetObjectField(TEXT("resident"))->SetStringField(TEXT("motion_strategy"),LivingTownCafeWorker110::Strategy);
    Reject(TEXT("V1 rejects extra strategy key"),Encode(Legacy));
    if(!TestTrue(TEXT("Fresh V1 parse after V2 still accepts legacy"),ReadText(Encode(Fixture()))))return false;
    TestTrue(TEXT("V1 parse clears all V2 output metadata"),B.MotionStrategy==ELivingTownCafeMotionStrategy::LegacySingleNode&&B.IdleAnimationPath.IsEmpty()&&B.WalkAnimationPath.IsEmpty()&&B.IdleRootDeltaCm==FVector::ZeroVector);
    return true;
}
#endif
