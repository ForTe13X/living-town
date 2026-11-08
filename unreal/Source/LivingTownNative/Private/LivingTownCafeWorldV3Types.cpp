#include "LivingTownCafeWorldV3Types.h"
#include "LivingTownCafeBinding.h"
#include "Animation/AnimSequence.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Engine/SkeletalMesh.h"
#include "GameFramework/Character.h"
#include "Components/SkeletalMeshComponent.h"
#include "Misc/PackageName.h"
#include "Misc/FileHelper.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "HAL/FileManager.h"
#include "UObject/Package.h"
#include "Misc/Paths.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "UObject/SoftObjectPath.h"
namespace LivingTownCafeNativeBackend {
living_town::cafe_backend_v3::Flags Flags(){
    return {FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafePropertyV2")),
        FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeWorldV3")),
        FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeLegacyV1")),
        FParse::Param(FCommandLine::Get(),TEXT("LivingTownCafeWorker110DevelopmentPreview"))};
}
living_town::cafe_backend_v3::Backend Selected(){return living_town::cafe_backend_v3::select(Flags());}
}
namespace {
bool Sha(const FString& S){if(S.Len()!=64)return false;for(TCHAR C:S)if(!((C>='0'&&C<='9')||(C>='a'&&C<='f')))return false;return true;}
bool RecipeShape(const ULivingTownCafeMealContactComponent* Provider,const ACharacter* Pawn,const FString& BindingSha,FLivingTownCafeMealClipRecipe& R){
    const auto* Mesh=Pawn?Pawn->GetMesh():nullptr;
    return Provider&&Pawn&&Provider->GetOwner()==Pawn&&Provider->IsRegistered()&&Provider->ReviewedRecipe(R)&&Mesh&&
        R.Clip&&R.Mesh&&R.Clip->GetSkeleton()&&Mesh->GetSkeletalMeshAsset()==R.Mesh&&R.Clip->GetSkeleton()==R.Mesh->GetSkeleton()&&
        Sha(R.RecipeFileSha256)&&Sha(R.ClipFileSha256)&&Sha(R.CertificateSha256)&&R.CafeBindingSha256==BindingSha&&Sha(BindingSha)&&
        R.HandSocket!=NAME_None&&R.MouthSocket!=NAME_None&&R.HandSocket!=R.MouthSocket&&
        Mesh->DoesSocketExist(R.HandSocket)&&Mesh->DoesSocketExist(R.MouthSocket)&&
        FMath::IsFinite(R.MaxContactDistanceCm)&&R.MaxContactDistanceCm>0&&R.MaxContactDistanceCm<=15&&
        FMath::IsFinite(R.Clip->GetPlayLength())&&R.Clip->GetPlayLength()>0&&FMath::IsNearlyEqual(R.Clip->RateScale,1.f,.001f);
}
}
bool ULivingTownCafeMealContactComponent::ValidateRecipe(const ACharacter* Pawn,const FString& BindingSha,FString& Error)const{
    Error.Reset();FLivingTownCafeMealClipRecipe R;
    if(!RecipeShape(this,Pawn,BindingSha,R)){Error=TEXT("reviewed_eat_clip_contact_recipe_required");return false;}
    const FString RecipePath=FPaths::ProjectContentDir()/TEXT("LivingTown/CafeWorldV3MealContact.json");
    TArray<uint8> RecipeData;FString RecipeHash,Json;TSharedPtr<FJsonObject> O;const int64 RecipeSize=IFileManager::Get().FileSize(*RecipePath);
    if(RecipeSize<=0||RecipeSize>64*1024||!FFileHelper::LoadFileToArray(RecipeData,*RecipePath)||!LivingTownCafeJournal::Sha256(RecipeData,RecipeHash)||RecipeHash!=R.RecipeFileSha256){Error=TEXT("reviewed_eat_recipe_file_source_mismatch");return false;}
    FFileHelper::BufferToString(Json,RecipeData.GetData(),RecipeData.Num());
    if(!LivingTownCafeJournal::HasUniqueObjectKeys(Json)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),O)||!O){Error=TEXT("reviewed_eat_recipe_invalid");return false;}
    const auto Equal=[&](const TCHAR* Key,const FString& Expected){FString V;return O->TryGetStringField(Key,V)&&V==Expected;};double Distance=0;
    if(!Equal(TEXT("format"),TEXT("LivingTown.CafeWorldV3.MealContact"))||!Equal(TEXT("version"),TEXT("1"))||!Equal(TEXT("binding_sha256"),BindingSha)||!Equal(TEXT("clip_asset"),R.Clip->GetPathName())||!Equal(TEXT("mesh_asset"),R.Mesh->GetPathName())||!Equal(TEXT("clip_sha256"),R.ClipFileSha256)||!Equal(TEXT("contact_certificate_sha256"),R.CertificateSha256)||!Equal(TEXT("hand_socket"),R.HandSocket.ToString())||!Equal(TEXT("mouth_socket"),R.MouthSocket.ToString())||!O->TryGetNumberField(TEXT("max_contact_distance_cm"),Distance)||!FMath::IsNearlyEqual(Distance,double(R.MaxContactDistanceCm),.0001)){Error=TEXT("eat_provider_must_match_authored_recipe");return false;}
    const FString Path=FPackageName::LongPackageNameToFilename(R.Clip->GetOutermost()->GetName(),FPackageName::GetAssetPackageExtension());
    const int64 Size=IFileManager::Get().FileSize(*Path);TArray<uint8> Data;FString Hash;
    if(Size<=0||Size>64*1024*1024||!FFileHelper::LoadFileToArray(Data,*Path)||!LivingTownCafeJournal::Sha256(Data,Hash)||Hash!=R.ClipFileSha256){Error=TEXT("actual_eat_clip_file_source_mismatch");return false;}
    return true;
}
bool ULivingTownCafeMealContactComponent::ObserveContact(const ACharacter* Pawn,const FString& BindingSha,FString& Error)const{
    Error.Reset();FLivingTownCafeMealClipRecipe R;
    if(!RecipeShape(this,Pawn,BindingSha,R)){Error=TEXT("eat_clip_contact_binding_lost");return false;}
    const auto* Mesh=Pawn->GetMesh();auto* Player=Mesh->GetSingleNodeInstance();
    if(!Player||Player->GetCurrentAsset()!=R.Clip||!Player->IsPlaying()||!FMath::IsNearlyEqual(Player->GetPlayRate(),1.f,.001f)||!Mesh->bEnableAnimation||Mesh->bPauseAnims||!FMath::IsNearlyEqual(Mesh->GlobalAnimRateScale,1.f,.001f)){Error=TEXT("actual_eat_clip_not_playing");return false;}
    // Sample the live evaluated pose, never a request, notify boolean or saved ray.
    const FVector Hand=Mesh->GetSocketLocation(R.HandSocket),Mouth=Mesh->GetSocketLocation(R.MouthSocket);
    if(Hand.ContainsNaN()||Mouth.ContainsNaN()||FVector::Dist(Hand,Mouth)>R.MaxContactDistanceCm){Error=TEXT("actual_eating_contact_lost");return false;}
    return true;
}

namespace MealV2 {
bool Fail(FString& E,const TCHAR* Why){E=Why;return false;}
bool Hash(const FString& S){return Sha(S)&&S!=FString::ChrN(64,TCHAR('0'));}
bool Keys(const FJsonObject& O,std::initializer_list<const TCHAR*> Names){if(O.Values.Num()!=int32(Names.size()))return false;for(const auto* N:Names)if(!O.HasField(FStringView(N)))return false;return true;}
bool String(const FJsonObject& O,const TCHAR* K,FString& V){return O.HasTypedField<EJson::String>(K)&&O.TryGetStringField(K,V)&&!V.IsEmpty()&&V.Len()<=2048;}
bool Number(const FJsonObject& O,const TCHAR* K,double& V,double Lo,double Hi){return O.HasTypedField<EJson::Number>(K)&&O.TryGetNumberField(K,V)&&FMath::IsFinite(V)&&V>=Lo&&V<=Hi;}
bool Integer(const FJsonObject& O,const TCHAR* K,int64& V,int64 Lo,int64 Hi){double N=0;if(!Number(O,K,N,double(Lo),double(Hi))||FMath::FloorToDouble(N)!=N)return false;V=int64(N);return true;}
bool Json(const FString& S,TSharedPtr<FJsonObject>& O){return S.Len()<=128*1024&&LivingTownCafeJournal::HasUniqueObjectKeys(S)&&FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(S),O)&&O.IsValid();}
bool Relative(const FString& S){return !S.IsEmpty()&&S.Len()<=240&&FPaths::IsRelative(S)&&!S.Contains(TEXT(".."))&&!S.Contains(TEXT("\\"))&&!S.Contains(TEXT(":"))&&!S.StartsWith(TEXT("/"))&&S.EndsWith(TEXT(".json"));}
bool Asset(const FString& S){const FSoftObjectPath P(S);return(S.StartsWith(TEXT("/Game/"))||S.StartsWith(TEXT("/MetaHumanCharacter/")))&&P.IsValid()&&P.GetSubPathString().IsEmpty()&&FPackageName::IsValidLongPackageName(P.GetLongPackageName())&&FPackageName::IsValidObjectPath(S)&&!P.GetAssetName().IsEmpty()&&S==P.GetLongPackageName()+TEXT(".")+P.GetAssetName();}
bool Vector(const TSharedPtr<FJsonValue>& V,FVector& Out){if(!V||V->Type!=EJson::Array||V->AsArray().Num()!=3)return false;double N[3];for(int32 I=0;I<3;++I){const auto& X=V->AsArray()[I];if(!X||X->Type!=EJson::Number||!FMath::IsFinite(N[I]=X->AsNumber()))return false;}Out=FVector(N[0],N[1],N[2]);return !Out.ContainsNaN();}
bool Transform(const TSharedPtr<FJsonValue>& V,FTransform& Out){
    if(!V||V->Type!=EJson::Object)return false;const auto O=V->AsObject();FVector T,S;
    if(!O||!Keys(*O,{TEXT("translation_cm"),TEXT("rotation_xyzw"),TEXT("scale")})||!Vector(O->TryGetField(TEXT("translation_cm")),T)||!Vector(O->TryGetField(TEXT("scale")),S)||S.GetMin()<=0)return false;
    const auto Q=O->TryGetField(TEXT("rotation_xyzw"));if(!Q||Q->Type!=EJson::Array||Q->AsArray().Num()!=4)return false;double N[4];for(int32 I=0;I<4;++I){const auto& X=Q->AsArray()[I];if(!X||X->Type!=EJson::Number||!FMath::IsFinite(N[I]=X->AsNumber()))return false;}
    const FQuat R(N[0],N[1],N[2],N[3]);if(!R.IsNormalized())return false;Out=FTransform(R,T,S);return Out.IsValid();
}
bool Names(const FJsonObject& O,const TCHAR* K,TArray<FString>& Out,int32 Min,int32 Max,bool Unique){const TArray<TSharedPtr<FJsonValue>>* A=nullptr;if(!O.TryGetArrayField(K,A)||A->Num()<Min||A->Num()>Max)return false;TSet<FString> Seen;for(const auto& V:*A){if(!V||V->Type!=EJson::String||!Asset(V->AsString())||(Unique&&Seen.Contains(V->AsString())))return false;Seen.Add(V->AsString());Out.Add(V->AsString());}return true;}
bool Read(const FString& Path,int64 ExpectedBytes,const FString& ExpectedHash,FString& Text,FString* ObservedHash=nullptr){
    const int64 Size=IFileManager::Get().FileSize(*Path);if(Size<=0||Size>128*1024||(ExpectedBytes&&Size!=ExpectedBytes))return false;TArray<uint8> Data;FString H;
    if(!FFileHelper::LoadFileToArray(Data,*Path)||Data.Num()!=Size||!LivingTownCafeJournal::Sha256(Data,H)||(!ExpectedHash.IsEmpty()&&H!=ExpectedHash))return false;FFileHelper::BufferToString(Text,Data.GetData(),Data.Num());if(ObservedHash)*ObservedHash=H;return true;
}
}

const FLivingTownMealAssetRoleV2* FLivingTownMetaHumanMealRecipeV2::FindRole(const FString& Role)const{return Assets.FindByPredicate([&](const auto& A){return A.Role==Role;});}
bool FLivingTownMetaHumanMealRecipeV2::ParseRecipe(const FString& Text,FLivingTownMetaHumanMealRecipeV2& Out,FString& Error){
    using namespace MealV2;Error.Reset();TSharedPtr<FJsonObject> O;FLivingTownMetaHumanMealRecipeV2 R;FString Format,Version;
    if(!Json(Text,O)||!Keys(*O,{TEXT("format"),TEXT("version"),TEXT("binding_sha256"),TEXT("visual_descriptor_sha256"),TEXT("source_closure_sha256"),TEXT("certificate_file"),TEXT("certificate_sha256"),TEXT("certificate_bytes")})||
       !String(*O,TEXT("format"),Format)||Format!=TEXT("LivingTown.CafeWorldV3.MealContact")||!String(*O,TEXT("version"),Version)||Version!=TEXT("2")||
       !String(*O,TEXT("binding_sha256"),R.BindingSha256)||!Hash(R.BindingSha256)||!String(*O,TEXT("visual_descriptor_sha256"),R.VisualDescriptorSha256)||!Hash(R.VisualDescriptorSha256)||
       !String(*O,TEXT("source_closure_sha256"),R.SourceClosureSha256)||!Hash(R.SourceClosureSha256)||!String(*O,TEXT("certificate_file"),R.CertificateFile)||!Relative(R.CertificateFile)||
       !String(*O,TEXT("certificate_sha256"),R.CertificateSha256)||!Hash(R.CertificateSha256)||!Integer(*O,TEXT("certificate_bytes"),R.CertificateBytes,1,128*1024))return Fail(Error,TEXT("metahuman_meal_v2_explicit_recipe_required"));
    Out=MoveTemp(R);return true;
}
bool FLivingTownMetaHumanMealRecipeV2::ParseCertificate(const FString& Text,const FLivingTownMetaHumanMealRecipeV2& Recipe,FLivingTownMetaHumanMealRecipeV2& Out,FString& Error){
    using namespace MealV2;Error.Reset();auto R=Recipe;TSharedPtr<FJsonObject> O;FString Format,Version,Status,B,V,S;
    if(!Hash(R.BindingSha256)||!Hash(R.VisualDescriptorSha256)||!Hash(R.SourceClosureSha256)||!Json(Text,O)||!Keys(*O,{TEXT("format"),TEXT("version"),TEXT("status"),TEXT("binding_sha256"),TEXT("visual_descriptor_sha256"),TEXT("source_closure_sha256"),TEXT("assets"),TEXT("proofs"),TEXT("bread_materials"),TEXT("bread_bitten_materials"),TEXT("bread_textures"),TEXT("anchors"),TEXT("station"),TEXT("timing"),TEXT("jaw")})||
       !String(*O,TEXT("format"),Format)||Format!=TEXT("LivingTown.MetaHumanMeal.PhysicalCertificate")||!String(*O,TEXT("version"),Version)||Version!=TEXT("2")||!String(*O,TEXT("status"),Status)||Status!=TEXT("ROOT_ACCEPTED_NATIVE_POSE_CALIBRATION")||
       !String(*O,TEXT("binding_sha256"),B)||B!=R.BindingSha256||!String(*O,TEXT("visual_descriptor_sha256"),V)||V!=R.VisualDescriptorSha256||!String(*O,TEXT("source_closure_sha256"),S)||S!=R.SourceClosureSha256)return Fail(Error,TEXT("metahuman_meal_v2_bound_certificate_required"));
    R.Assets.Empty();R.Proofs.Empty();R.GripProbes.Empty();R.BreadMaterials.Empty();R.BreadBittenMaterials.Empty();R.BreadTextures.Empty();
    const TArray<TSharedPtr<FJsonValue>>* A=nullptr;TSet<FString> Roles;
    if(!O->TryGetArrayField(TEXT("assets"),A)||A->Num()<12||A->Num()>64)return Fail(Error,TEXT("meal_v2_asset_roles_required"));
    for(const auto& X:*A){FLivingTownMealAssetRoleV2 F;const auto Q=X&&X->Type==EJson::Object?X->AsObject():nullptr;
        if(!Q||!Keys(*Q,{TEXT("role"),TEXT("asset"),TEXT("bytes"),TEXT("sha256")})||!String(*Q,TEXT("role"),F.Role)||Roles.Contains(F.Role)||!String(*Q,TEXT("asset"),F.Asset)||!Asset(F.Asset)||!Integer(*Q,TEXT("bytes"),F.Bytes,1,512LL*1024*1024)||!String(*Q,TEXT("sha256"),F.Sha256)||!Hash(F.Sha256))return Fail(Error,TEXT("meal_v2_exact_asset_role_closure_required"));for(const auto& Existing:R.Assets)if(Existing.Asset==F.Asset&&(Existing.Bytes!=F.Bytes||Existing.Sha256!=F.Sha256))return Fail(Error,TEXT("meal_v2_aliased_role_bytes_conflict"));Roles.Add(F.Role);R.Assets.Add(F);}
    for(const auto* K:{TEXT("actor_class"),TEXT("clip"),TEXT("body"),TEXT("face"),TEXT("outfit"),TEXT("body_skeleton"),TEXT("face_skeleton"),TEXT("bread"),TEXT("bread_bitten"),TEXT("body_post"),TEXT("face_main"),TEXT("face_post")})if(!Roles.Contains(K))return Fail(Error,TEXT("meal_v2_missing_required_role"));
    if(R.FindRole(TEXT("bread"))->Asset==R.FindRole(TEXT("bread_bitten"))->Asset)return Fail(Error,TEXT("meal_v2_distinct_qualified_bitten_geometry_required"));
    if(!Names(*O,TEXT("bread_materials"),R.BreadMaterials,1,8,false)||!Names(*O,TEXT("bread_bitten_materials"),R.BreadBittenMaterials,1,8,false)||!Names(*O,TEXT("bread_textures"),R.BreadTextures,1,32,true)||Roles.Num()!=12+R.BreadMaterials.Num()+R.BreadBittenMaterials.Num()+R.BreadTextures.Num())return Fail(Error,TEXT("meal_v2_exact_bread_PBR_roster_required"));
    for(int32 I=0;I<R.BreadMaterials.Num();++I){const auto* F=R.FindRole(FString::Printf(TEXT("bread_material/%d"),I));if(!F||F->Asset!=R.BreadMaterials[I])return Fail(Error,TEXT("meal_v2_material_role_mismatch"));}
    for(int32 I=0;I<R.BreadBittenMaterials.Num();++I){const auto* F=R.FindRole(FString::Printf(TEXT("bread_bitten_material/%d"),I));if(!F||F->Asset!=R.BreadBittenMaterials[I])return Fail(Error,TEXT("meal_v2_bitten_material_role_mismatch"));}
    for(int32 I=0;I<R.BreadTextures.Num();++I){const auto* F=R.FindRole(FString::Printf(TEXT("bread_texture/%d"),I));if(!F||F->Asset!=R.BreadTextures[I])return Fail(Error,TEXT("meal_v2_texture_role_mismatch"));}
    if(!O->TryGetArrayField(TEXT("proofs"),A)||A->Num()!=3)return Fail(Error,TEXT("meal_v2_native_proofs_required"));TSet<FString> Kinds,Files;
    for(const auto& X:*A){FLivingTownMealProofV2 F;const auto Q=X&&X->Type==EJson::Object?X->AsObject():nullptr;
        if(!Q||!Keys(*Q,{TEXT("kind"),TEXT("file"),TEXT("bytes"),TEXT("sha256")})||!String(*Q,TEXT("kind"),F.Kind)||(F.Kind!=TEXT("jaw")&&F.Kind!=TEXT("grip")&&F.Kind!=TEXT("bite"))||Kinds.Contains(F.Kind)||!String(*Q,TEXT("file"),F.RelativeFile)||!Relative(F.RelativeFile)||Files.Contains(F.RelativeFile)||!Integer(*Q,TEXT("bytes"),F.Bytes,1,128*1024)||!String(*Q,TEXT("sha256"),F.Sha256)||!Hash(F.Sha256))return Fail(Error,TEXT("meal_v2_exact_native_proof_roles_required"));Kinds.Add(F.Kind);Files.Add(F.RelativeFile);R.Proofs.Add(F);}
    const auto Obj=[&](const TCHAR* K){const auto X=O->TryGetField(K);return X&&X->Type==EJson::Object?X->AsObject():nullptr;};
    const auto Anchors=Obj(TEXT("anchors")),Station=Obj(TEXT("station")),Timing=Obj(TEXT("timing")),Jaw=Obj(TEXT("jaw"));FString H,M,J,JP,C;int64 Count=0;
    if(!Anchors||!Keys(*Anchors,{TEXT("hand_body_bone"),TEXT("mouth_face_bone"),TEXT("jaw_face_bone"),TEXT("jaw_parent_face_bone"),TEXT("grip_relative"),TEXT("food_bite_point_cm"),TEXT("mouth_offset_cm"),TEXT("transform_tolerance"),TEXT("max_bite_distance_cm"),TEXT("holding_probes")})||
       !String(*Anchors,TEXT("hand_body_bone"),H)||!String(*Anchors,TEXT("mouth_face_bone"),M)||!String(*Anchors,TEXT("jaw_face_bone"),J)||!String(*Anchors,TEXT("jaw_parent_face_bone"),JP)||
       !Transform(Anchors->TryGetField(TEXT("grip_relative")),R.GripRelative)||!Vector(Anchors->TryGetField(TEXT("food_bite_point_cm")),R.FoodBitePointCm)||!Vector(Anchors->TryGetField(TEXT("mouth_offset_cm")),R.MouthOffsetCm)||
       !Number(*Anchors,TEXT("transform_tolerance"),R.TransformTolerance,UE_DOUBLE_SMALL_NUMBER,0.01)||!Number(*Anchors,TEXT("max_bite_distance_cm"),R.MaxBiteDistanceCm,UE_DOUBLE_SMALL_NUMBER,15)||!Anchors->TryGetArrayField(TEXT("holding_probes"),A)||A->Num()<2||A->Num()>8)return Fail(Error,TEXT("meal_v2_explicit_measured_anchors_required"));
    R.HandBone=FName(*H);R.MouthBone=FName(*M);R.JawBone=FName(*J);R.JawParentBone=FName(*JP);if(R.HandBone.IsNone()||R.MouthBone.IsNone()||R.JawBone.IsNone()||R.JawParentBone.IsNone()||R.JawBone==R.JawParentBone)return Fail(Error,TEXT("meal_v2_real_bone_roles_required"));
    TSet<FName> Bones;for(const auto& X:*A){FLivingTownMealGripProbeV2 G;const auto Q=X&&X->Type==EJson::Object?X->AsObject():nullptr;FString Bone;
        if(!Q||!Keys(*Q,{TEXT("body_bone"),TEXT("food_point_cm"),TEXT("max_distance_cm")})||!String(*Q,TEXT("body_bone"),Bone)||!Vector(Q->TryGetField(TEXT("food_point_cm")),G.FoodPointCm)||!Number(*Q,TEXT("max_distance_cm"),G.MaxDistanceCm,UE_DOUBLE_SMALL_NUMBER,30))return Fail(Error,TEXT("meal_v2_measured_holding_witness_required"));G.BodyBone=FName(*Bone);if(G.BodyBone.IsNone()||Bones.Contains(G.BodyBone))return Fail(Error,TEXT("meal_v2_distinct_holding_bones_required"));Bones.Add(G.BodyBone);R.GripProbes.Add(G);}
    if(!Station||!Keys(*Station,{TEXT("feet_cm"),TEXT("counter_point_cm"),TEXT("radius_cm"),TEXT("height_tolerance_cm"),TEXT("facing_min_dot")})||!Vector(Station->TryGetField(TEXT("feet_cm")),R.StationFeetCm)||!Vector(Station->TryGetField(TEXT("counter_point_cm")),R.CounterPointCm)||!Number(*Station,TEXT("radius_cm"),R.StationRadiusCm,UE_DOUBLE_SMALL_NUMBER,500)||!Number(*Station,TEXT("height_tolerance_cm"),R.StationHeightToleranceCm,UE_DOUBLE_SMALL_NUMBER,100)||!Number(*Station,TEXT("facing_min_dot"),R.StationFacingDot,0.0,1.0))return Fail(Error,TEXT("meal_v2_measured_station_required"));
    if(!Timing||!Keys(*Timing,{TEXT("duration"),TEXT("bite_start"),TEXT("bite_end"),TEXT("min_bite_span"),TEXT("min_bite_samples"),TEXT("chew_start"),TEXT("chew_end"),TEXT("tail_start"),TEXT("first_progress_delay"),TEXT("max_frame_gap"),TEXT("time_error")})||
       !Number(*Timing,TEXT("duration"),R.Duration,1,120)||!Number(*Timing,TEXT("bite_start"),R.BiteStart,0,R.Duration)||!Number(*Timing,TEXT("bite_end"),R.BiteEnd,R.BiteStart,R.Duration)||R.BiteEnd<=R.BiteStart||
       !Number(*Timing,TEXT("min_bite_span"),R.MinBiteSpan,UE_DOUBLE_SMALL_NUMBER,R.BiteEnd-R.BiteStart)||!Integer(*Timing,TEXT("min_bite_samples"),Count,2,120)||
       !Number(*Timing,TEXT("chew_start"),R.ChewStart,R.BiteEnd,R.Duration)||!Number(*Timing,TEXT("chew_end"),R.ChewEnd,R.ChewStart,R.Duration)||R.ChewEnd<=R.ChewStart||!Number(*Timing,TEXT("tail_start"),R.TailStart,R.ChewEnd,R.Duration)||R.TailStart>=R.Duration||
       !Number(*Timing,TEXT("first_progress_delay"),R.FirstProgressDelay,1,5)||!Number(*Timing,TEXT("max_frame_gap"),R.MaxFrameGap,UE_DOUBLE_SMALL_NUMBER,.25)||!Number(*Timing,TEXT("time_error"),R.TimeError,UE_DOUBLE_SMALL_NUMBER,R.MaxFrameGap))return Fail(Error,TEXT("meal_v2_finite_phase_timing_required"));R.MinBiteSamples=int32(Count);
    if(!Jaw||!Keys(*Jaw,{TEXT("curve"),TEXT("min_bite_value"),TEXT("min_chew_curve_delta"),TEXT("min_chew_jaw_degrees"),TEXT("max_chew_static_span"),TEXT("curve_tolerance")})||!String(*Jaw,TEXT("curve"),C)||!Number(*Jaw,TEXT("min_bite_value"),R.MinBiteJawCurve,UE_DOUBLE_SMALL_NUMBER,10)||!Number(*Jaw,TEXT("min_chew_curve_delta"),R.MinChewCurveDelta,UE_DOUBLE_SMALL_NUMBER,10)||!Number(*Jaw,TEXT("min_chew_jaw_degrees"),R.MinChewJawDegrees,UE_DOUBLE_SMALL_NUMBER,180)||!Number(*Jaw,TEXT("max_chew_static_span"),R.MaxChewStaticSpan,R.MaxFrameGap,FMath::Min(1.0,R.ChewEnd-R.ChewStart))||!Number(*Jaw,TEXT("curve_tolerance"),R.CurveTolerance,UE_DOUBLE_SMALL_NUMBER,1))return Fail(Error,TEXT("meal_v2_measured_curve_and_jaw_required"));R.JawCurve=FName(*C);if(R.JawCurve.IsNone())return Fail(Error,TEXT("meal_v2_named_curve_required"));
    Out=MoveTemp(R);return true;
}
bool FLivingTownMetaHumanMealRecipeV2::ReadQualified(const FString& RelativeRecipe,FLivingTownMetaHumanMealRecipeV2& Out,FString& Error){
    using namespace MealV2;Error.Reset();FString Text;FLivingTownMetaHumanMealRecipeV2 R;
    FString RecipeHash;if(!Relative(RelativeRecipe)||!Read(FPaths::ProjectContentDir()/RelativeRecipe,0,TEXT(""),Text,&RecipeHash)||!ParseRecipe(Text,R,Error))return Fail(Error,TEXT("meal_v2_actual_recipe_file_required"));R.RecipeSha256=RecipeHash;
    if(!Read(FPaths::ProjectContentDir()/R.CertificateFile,R.CertificateBytes,R.CertificateSha256,Text)||!ParseCertificate(Text,R,R,Error))return Fail(Error,TEXT("meal_v2_actual_certificate_bytes_required"));
    TMap<FString,TPair<int64,FString>> CheckedPackages;
    for(const auto& A:R.Assets){
        const FString Package=FSoftObjectPath(A.Asset).GetLongPackageName();
        if(const auto* Seen=CheckedPackages.Find(Package)){if(Seen->Key!=A.Bytes||Seen->Value!=A.Sha256)return Fail(Error,TEXT("meal_v2_aliased_package_bytes_conflict"));continue;}
        FString File;if(!FPackageName::TryConvertLongPackageNameToFilename(Package,File,FPackageName::GetAssetPackageExtension()))return Fail(Error,TEXT("meal_v2_mounted_package_required"));
        TArray<uint8> Bytes;FString H;if(IFileManager::Get().FileSize(*File)!=A.Bytes||!FFileHelper::LoadFileToArray(Bytes,*File)||Bytes.Num()!=A.Bytes||!LivingTownCafeJournal::Sha256(Bytes,H)||H!=A.Sha256)return Fail(Error,TEXT("meal_v2_actual_package_role_bytes_mismatch"));
        CheckedPackages.Add(Package,TPair<int64,FString>(A.Bytes,H));
    }
    for(const auto& P:R.Proofs){TSharedPtr<FJsonObject> O;FString F,V,K,S,B,D,C,Food;int64 Samples=0;
        if(!Read(FPaths::ProjectContentDir()/P.RelativeFile,P.Bytes,P.Sha256,Text)||!Json(Text,O)||!Keys(*O,{TEXT("format"),TEXT("version"),TEXT("kind"),TEXT("status"),TEXT("binding_sha256"),TEXT("visual_descriptor_sha256"),TEXT("clip_sha256"),TEXT("bread_sha256"),TEXT("native_pose_samples")})||
           !String(*O,TEXT("format"),F)||F!=TEXT("LivingTown.MetaHumanMeal.PhysicalProof")||!String(*O,TEXT("version"),V)||V!=TEXT("1")||!String(*O,TEXT("kind"),K)||K!=P.Kind||!String(*O,TEXT("status"),S)||S!=TEXT("ROOT_ACCEPTED_NATIVE_POSE_CALIBRATION")||
           !String(*O,TEXT("binding_sha256"),B)||B!=R.BindingSha256||!String(*O,TEXT("visual_descriptor_sha256"),D)||D!=R.VisualDescriptorSha256||!String(*O,TEXT("clip_sha256"),C)||C!=R.FindRole(TEXT("clip"))->Sha256||!String(*O,TEXT("bread_sha256"),Food)||Food!=R.FindRole(TEXT("bread"))->Sha256||!Integer(*O,TEXT("native_pose_samples"),Samples,2,1000000))return Fail(Error,TEXT("meal_v2_actual_bound_native_proof_required"));}
    Out=MoveTemp(R);return true;
}
