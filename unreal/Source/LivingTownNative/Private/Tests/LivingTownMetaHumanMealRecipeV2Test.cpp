#include "LivingTownCafeWorldV3Types.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Dom/JsonObject.h"
#include "HAL/FileManager.h"
#include "Misc/Paths.h"
#include "Serialization/JsonSerializer.h"

namespace {
using FObject=TSharedPtr<FJsonObject>;
FObject Object(){return MakeShared<FJsonObject>();}
FString Json(const FObject& O){FString S;FJsonSerializer::Serialize(O.ToSharedRef(),TJsonWriterFactory<>::Create(&S));S.TrimEndInline();return S;}
TSharedPtr<FJsonValue> Vector(double X,double Y,double Z){return MakeShared<FJsonValueArray>(TArray<TSharedPtr<FJsonValue>>{MakeShared<FJsonValueNumber>(X),MakeShared<FJsonValueNumber>(Y),MakeShared<FJsonValueNumber>(Z)});}
const FString HashA=FString::ChrN(64,TCHAR('a')),HashB=FString::ChrN(64,TCHAR('b')),HashC=FString::ChrN(64,TCHAR('c'));
FObject Recipe(){
    auto O=Object();O->SetStringField(TEXT("format"),TEXT("LivingTown.CafeWorldV3.MealContact"));O->SetStringField(TEXT("version"),TEXT("2"));
    O->SetStringField(TEXT("binding_sha256"),HashA);O->SetStringField(TEXT("visual_descriptor_sha256"),HashB);O->SetStringField(TEXT("source_closure_sha256"),HashC);
    O->SetStringField(TEXT("certificate_file"),TEXT("ParserOnly/no_physical_certificate.json"));O->SetStringField(TEXT("certificate_sha256"),HashA);O->SetNumberField(TEXT("certificate_bytes"),17);return O;
}
// Synthetic parser data only. There are no packages, calibration, proof files or
// native admission behind these paths/hashes. Parse success is never qualification.
FObject Certificate(){
    auto O=Object();O->SetStringField(TEXT("format"),TEXT("LivingTown.MetaHumanMeal.PhysicalCertificate"));O->SetStringField(TEXT("version"),TEXT("2"));O->SetStringField(TEXT("status"),TEXT("ROOT_ACCEPTED_NATIVE_POSE_CALIBRATION"));
    O->SetStringField(TEXT("binding_sha256"),HashA);O->SetStringField(TEXT("visual_descriptor_sha256"),HashB);O->SetStringField(TEXT("source_closure_sha256"),HashC);
    TArray<TSharedPtr<FJsonValue>> Assets;const auto AddRole=[&](const FString& Role,const FString& Asset){auto R=Object();R->SetStringField(TEXT("role"),Role);R->SetStringField(TEXT("asset"),Asset);R->SetNumberField(TEXT("bytes"),17);R->SetStringField(TEXT("sha256"),HashA);Assets.Add(MakeShared<FJsonValueObject>(R));};
    for(const auto* Role:{TEXT("actor_class"),TEXT("clip"),TEXT("body"),TEXT("face"),TEXT("outfit"),TEXT("body_skeleton"),TEXT("face_skeleton"),TEXT("bread"),TEXT("bread_bitten"),TEXT("body_post"),TEXT("face_main"),TEXT("face_post")}){
        const FString Name=FString(Role).EndsWith(TEXT("skeleton"))?TEXT("shared_skeleton"):FString(Role);AddRole(Role,FString::Printf(TEXT("/Game/ParserOnly/%s.%s"),*Name,*Name));
    }
    const FString M=TEXT("/Game/ParserOnly/material.material"),MB=TEXT("/Game/ParserOnly/bitten_material.bitten_material"),T=TEXT("/Game/ParserOnly/texture.texture"),TB=TEXT("/Game/ParserOnly/bitten_texture.bitten_texture");
    AddRole(TEXT("bread_material/0"),M);AddRole(TEXT("bread_material/1"),M);AddRole(TEXT("bread_bitten_material/0"),MB);AddRole(TEXT("bread_texture/0"),T);AddRole(TEXT("bread_texture/1"),TB);O->SetArrayField(TEXT("assets"),Assets);
    O->SetArrayField(TEXT("bread_materials"),{MakeShared<FJsonValueString>(M),MakeShared<FJsonValueString>(M)});O->SetArrayField(TEXT("bread_bitten_materials"),{MakeShared<FJsonValueString>(MB)});O->SetArrayField(TEXT("bread_textures"),{MakeShared<FJsonValueString>(T),MakeShared<FJsonValueString>(TB)});
    TArray<TSharedPtr<FJsonValue>> Proofs;for(const auto* Kind:{TEXT("jaw"),TEXT("grip"),TEXT("bite")}){auto P=Object();P->SetStringField(TEXT("kind"),Kind);P->SetStringField(TEXT("file"),FString::Printf(TEXT("ParserOnly/%s.json"),Kind));P->SetNumberField(TEXT("bytes"),17);P->SetStringField(TEXT("sha256"),HashA);Proofs.Add(MakeShared<FJsonValueObject>(P));}O->SetArrayField(TEXT("proofs"),Proofs);
    auto A=Object();A->SetStringField(TEXT("hand_body_bone"),TEXT("synthetic_hand"));A->SetStringField(TEXT("mouth_face_bone"),TEXT("synthetic_mouth"));A->SetStringField(TEXT("jaw_face_bone"),TEXT("synthetic_jaw"));A->SetStringField(TEXT("jaw_parent_face_bone"),TEXT("synthetic_parent"));
    auto Grip=Object();Grip->SetField(TEXT("translation_cm"),Vector(0,0,0));Grip->SetArrayField(TEXT("rotation_xyzw"),{MakeShared<FJsonValueNumber>(0),MakeShared<FJsonValueNumber>(0),MakeShared<FJsonValueNumber>(0),MakeShared<FJsonValueNumber>(1)});Grip->SetField(TEXT("scale"),Vector(1,1,1));A->SetObjectField(TEXT("grip_relative"),Grip);
    A->SetField(TEXT("food_bite_point_cm"),Vector(0,0,0));A->SetField(TEXT("mouth_offset_cm"),Vector(0,0,0));A->SetNumberField(TEXT("transform_tolerance"),.0001);A->SetNumberField(TEXT("max_bite_distance_cm"),1);
    TArray<TSharedPtr<FJsonValue>> Probes;for(const auto* Bone:{TEXT("synthetic_finger_a"),TEXT("synthetic_finger_b")}){auto P=Object();P->SetStringField(TEXT("body_bone"),Bone);P->SetField(TEXT("food_point_cm"),Vector(0,0,0));P->SetNumberField(TEXT("max_distance_cm"),1);Probes.Add(MakeShared<FJsonValueObject>(P));}A->SetArrayField(TEXT("holding_probes"),Probes);O->SetObjectField(TEXT("anchors"),A);
    auto Station=Object();Station->SetField(TEXT("feet_cm"),Vector(0,0,0));Station->SetField(TEXT("counter_point_cm"),Vector(0,0,0));Station->SetNumberField(TEXT("radius_cm"),1);Station->SetNumberField(TEXT("height_tolerance_cm"),1);Station->SetNumberField(TEXT("facing_min_dot"),.5);O->SetObjectField(TEXT("station"),Station);
    auto Timing=Object();for(const auto& P:TArray<TPair<FString,double>>{{TEXT("duration"),24.5},{TEXT("bite_start"),2.7},{TEXT("bite_end"),3.3},{TEXT("min_bite_span"),.2},{TEXT("min_bite_samples"),3},{TEXT("chew_start"),3.3},{TEXT("chew_end"),22.5},{TEXT("tail_start"),22.5},{TEXT("first_progress_delay"),1},{TEXT("max_frame_gap"),.1},{TEXT("time_error"),.01}})Timing->SetNumberField(P.Key,P.Value);O->SetObjectField(TEXT("timing"),Timing);
    auto Jaw=Object();Jaw->SetStringField(TEXT("curve"),TEXT("synthetic_curve"));Jaw->SetNumberField(TEXT("min_bite_value"),.1);Jaw->SetNumberField(TEXT("min_chew_curve_delta"),.1);Jaw->SetNumberField(TEXT("min_chew_jaw_degrees"),1);Jaw->SetNumberField(TEXT("max_chew_static_span"),.5);Jaw->SetNumberField(TEXT("curve_tolerance"),.01);O->SetObjectField(TEXT("jaw"),Jaw);return O;
}
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownMetaHumanMealRecipeV2Test,"LivingTown.WorldV3.MetaHumanMealV2Parser",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownMetaHumanMealRecipeV2Test::RunTest(const FString&){
    FLivingTownMetaHumanMealRecipeV2 R,Out;FString Error;
    if(!TestTrue(TEXT("Explicit synthetic recipe parses syntax only"),FLivingTownMetaHumanMealRecipeV2::ParseRecipe(Json(Recipe()),R,Error)))return false;
    if(!TestTrue(TEXT("Explicit synthetic certificate preserves two aliased ordered slots and shared rig roles"),FLivingTownMetaHumanMealRecipeV2::ParseCertificate(Json(Certificate()),R,Out,Error)))return false;
    TestEqual(TEXT("No invented third material"),Out.BreadMaterials.Num(),2);
    TestEqual(TEXT("Bitten variant retains its independent ordered slot count"),Out.BreadBittenMaterials.Num(),1);
    TestTrue(TEXT("Bitten material may differ from Whole"),Out.BreadBittenMaterials[0]!=Out.BreadMaterials[0]);
    TestEqual(TEXT("Texture roster is the unique union of both variants"),Out.BreadTextures.Num(),2);
    TestEqual(TEXT("Body and Face skeleton identity may alias when declared bytes agree"),Out.FindRole(TEXT("body_skeleton"))->Asset,Out.FindRole(TEXT("face_skeleton"))->Asset);
    const auto RejectRecipe=[&](const FObject& O){Out.RecipeSha256=TEXT("unchanged_on_refusal");TestFalse(TEXT("Malformed recipe refused"),FLivingTownMetaHumanMealRecipeV2::ParseRecipe(Json(O),Out,Error));TestEqual(TEXT("No partial output publication"),Out.RecipeSha256,FString(TEXT("unchanged_on_refusal")));TestFalse(TEXT("Refusal explains reason"),Error.IsEmpty());};
    auto O=Recipe();O->SetNumberField(TEXT("version"),2);RejectRecipe(O);
    O=Recipe();O->SetStringField(TEXT("extra"),TEXT("ignored?"));RejectRecipe(O);
    O=Recipe();O->SetStringField(TEXT("certificate_sha256"),FString::ChrN(64,TCHAR('0')));RejectRecipe(O);
    for(const auto* Path:{TEXT("../escape.json"),TEXT("C:/escape.json"),TEXT("/escape.json")}){O=Recipe();O->SetStringField(TEXT("certificate_file"),Path);RejectRecipe(O);}
    const FString Duplicate=Json(Recipe()).LeftChop(1)+TEXT(",\"version\":\"2\"}");TestFalse(TEXT("Duplicate JSON key refused"),FLivingTownMetaHumanMealRecipeV2::ParseRecipe(Duplicate,Out,Error));
    const auto RejectCertificate=[&](const FObject& C){Out.RecipeSha256=TEXT("unchanged_on_refusal");TestFalse(TEXT("Unqualified certificate refused"),FLivingTownMetaHumanMealRecipeV2::ParseCertificate(Json(C),R,Out,Error));TestEqual(TEXT("No partial certificate publication"),Out.RecipeSha256,FString(TEXT("unchanged_on_refusal")));};
    for(const auto* Status:{TEXT("PENDING"),TEXT("ROOT_ACCEPTED_NATIVE"),TEXT("ROOT_ACCEPTED_NATIVE_PHYSICAL_EATING")}){auto C=Certificate();C->SetStringField(TEXT("status"),Status);RejectCertificate(C);}
    auto C=Certificate();C->SetStringField(TEXT("source_closure_sha256"),HashA);RejectCertificate(C);
    C=Certificate();C->GetObjectField(TEXT("timing"))->RemoveField(TEXT("max_frame_gap"));RejectCertificate(C);
    C=Certificate();C->GetObjectField(TEXT("timing"))->SetNumberField(TEXT("min_bite_samples"),2.5);RejectCertificate(C);
    C=Certificate();C->GetObjectField(TEXT("timing"))->SetNumberField(TEXT("first_progress_delay"),0);RejectCertificate(C);
    C=Certificate();C->GetObjectField(TEXT("timing"))->SetNumberField(TEXT("tail_start"),24.5);RejectCertificate(C);
    C=Certificate();C->GetObjectField(TEXT("jaw"))->SetNumberField(TEXT("min_chew_jaw_degrees"),0);RejectCertificate(C);
    C=Certificate();C->GetObjectField(TEXT("jaw"))->RemoveField(TEXT("max_chew_static_span"));RejectCertificate(C);
    C=Certificate();C->GetObjectField(TEXT("anchors"))->RemoveField(TEXT("grip_relative"));RejectCertificate(C);
    C=Certificate();C->GetArrayField(TEXT("assets"))[1]->AsObject()->SetStringField(TEXT("asset"),TEXT("/Game/ParserOnly/clip"));RejectCertificate(C);
    C=Certificate();C->GetArrayField(TEXT("assets"))[6]->AsObject()->SetStringField(TEXT("sha256"),HashB);RejectCertificate(C);
    C=Certificate();C->GetArrayField(TEXT("assets"))[8]->AsObject()->SetStringField(TEXT("asset"),TEXT("/Game/ParserOnly/bread.bread"));RejectCertificate(C);
    C=Certificate();C->RemoveField(TEXT("bread_bitten_materials"));RejectCertificate(C);
    C=Certificate();C->GetArrayField(TEXT("assets"))[14]->AsObject()->SetStringField(TEXT("asset"),TEXT("/Game/ParserOnly/material.material"));RejectCertificate(C);
    C=Certificate();C->SetArrayField(TEXT("bread_textures"),{MakeShared<FJsonValueString>(TEXT("/Game/ParserOnly/texture.texture")),MakeShared<FJsonValueString>(TEXT("/Game/ParserOnly/texture.texture"))});RejectCertificate(C);
    C=Certificate();C->SetArrayField(TEXT("proofs"),{});RejectCertificate(C);
    C=Certificate();C->SetBoolField(TEXT("trust_ui"),true);RejectCertificate(C);
    const FString Missing=TEXT("__livingtown_missing_meal_v2_parser_control__/recipe.json");
    TestFalse(TEXT("Missing-file control must have no donor file"),IFileManager::Get().FileExists(*(FPaths::ProjectContentDir()/Missing)));
    TestFalse(TEXT("SHA-shaped syntax does not qualify without actual certificate/proof/package bytes"),FLivingTownMetaHumanMealRecipeV2::ReadQualified(Missing,Out,Error));
    return true;
}
#endif
