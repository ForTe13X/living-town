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
