#pragma once
#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "../ThirdParty/CafeBackendV3.hpp"
#include "LivingTownCafeWorldV3Types.generated.h"
class ACharacter;
class UAnimSequence;
class USkeletalMesh;
class UObject;

// One shared command-line selection for every native cafe authority.
namespace LivingTownCafeNativeBackend {
    LIVINGTOWNNATIVE_API living_town::cafe_backend_v3::Flags Flags();
    LIVINGTOWNNATIVE_API living_town::cafe_backend_v3::Backend Selected();
}
enum class ELivingTownCafeWorldPersona : uint8 { Aria, Ben };
enum class ELivingTownCafeMealKind : uint8 { PurchaseMeal, PublicMeal };
// These are the entire client meal intent. Identity, price, payee, needs and
// observation/qualification are supplied exclusively by the native authority.
struct FLivingTownCafeMealCommand {
    FString RequestId;
    FString SiteId=TEXT("cafe1f_dining_slot_pilot");
    ELivingTownCafeMealKind Kind=ELivingTownCafeMealKind::PurchaseMeal;
    int64 ExpectedRevision=0;
};
struct FLivingTownCafeWorldReceipt {
    bool bAccepted=false,bAlreadyApplied=false;
    FString Reason,Message;
    int64 EventId=-1;
};
struct FLivingTownCafeWorldView {
    bool bPrepared=false,bSessionReady=false,bReachable=false,bMealActive=false,bMealAvailable=false;
    bool bRecurringOffer=false,bRecurringLease=false;
    FString Persona,Owner,Operator,ResidentLabel,PropertyLabel,ListingLabel,MealLabel,Prompt,Notice,Diagnostic;
    int64 AriaCoins=0,BenCoins=0,Clock=0,Revision=0,Stock=0;
    int64 OfferRevision=-1,OfferTitleRevision=-1,RentDueTick=-1,RentAmount=0;
    int32 Hunger=0,Fun=0,ProgressTicks=0;
};

// Producer-owned reviewed asset/contact recipe, never a request or saved
// observation. No provider/recipe is shipped by this lane. Future native asset
// integration must supply a measured clip file digest and a reviewed contact
// certificate bound to the exact cafe binding; idle/walk cannot qualify eating.
struct FLivingTownCafeMealClipRecipe {
    UAnimSequence* Clip=nullptr;
    USkeletalMesh* Mesh=nullptr;
    FString RecipeFileSha256,ClipFileSha256,CertificateSha256,CafeBindingSha256;
    FName HandSocket,MouthSocket;
    float MaxContactDistanceCm=0;
};
UCLASS(Abstract, NotBlueprintable)
class LIVINGTOWNNATIVE_API ULivingTownCafeMealContactComponent : public UActorComponent {
    GENERATED_BODY()
public:
    // Override only in a reviewed native asset integration. The default refuses.
    virtual bool ReviewedRecipe(FLivingTownCafeMealClipRecipe& Out)const{return false;}
    // The adapter independently validates the actual asset and live pose. A
    // provider cannot grant money/stock/needs or submit a qualified boolean.
    bool ValidateRecipe(const ACharacter* Pawn,const FString& BindingSha,FString& Error)const;
    bool ObserveContact(const ACharacter* Pawn,const FString& BindingSha,FString& Error)const;
};

// V2 is a separate, explicit source contract. Legacy V1 and its default refusal
// are unchanged. No instance of this struct is a gameplay grant or UI command.
struct FLivingTownMealAssetRoleV2 {
    FString Role,Asset,Sha256;int64 Bytes=0;
};
struct FLivingTownMealProofV2 {
    FString Kind,RelativeFile,Sha256;int64 Bytes=0;
};
struct FLivingTownMealGripProbeV2 {
    FName BodyBone=NAME_None;FVector FoodPointCm=FVector::ZeroVector;double MaxDistanceCm=0;
};
struct LIVINGTOWNNATIVE_API FLivingTownMetaHumanMealRecipeV2 {
    FString BindingSha256,VisualDescriptorSha256,SourceClosureSha256;
    FString CertificateFile,CertificateSha256,RecipeSha256;int64 CertificateBytes=0;
    TArray<FLivingTownMealAssetRoleV2> Assets;TArray<FLivingTownMealProofV2> Proofs;
    TArray<FString> BreadMaterials,BreadTextures;
    FName HandBone=NAME_None,MouthBone=NAME_None,JawBone=NAME_None,JawParentBone=NAME_None,JawCurve=NAME_None;
    FTransform GripRelative=FTransform::Identity;
    FVector FoodBitePointCm=FVector::ZeroVector,MouthOffsetCm=FVector::ZeroVector,StationFeetCm=FVector::ZeroVector,CounterPointCm=FVector::ZeroVector;
    TArray<FLivingTownMealGripProbeV2> GripProbes;
    double StationRadiusCm=0,StationHeightToleranceCm=0,StationFacingDot=0,TransformTolerance=0,MaxBiteDistanceCm=0;
    double Duration=0,BiteStart=0,BiteEnd=0,MinBiteSpan=0,ChewStart=0,ChewEnd=0,TailStart=0,FirstProgressDelay=0,MaxFrameGap=0,TimeError=0;
    double MinBiteJawCurve=0,MinChewCurveDelta=0,MinChewJawDegrees=0,MaxChewStaticSpan=0,CurveTolerance=0;
    int32 MinBiteSamples=0;
    const FLivingTownMealAssetRoleV2* FindRole(const FString& Role)const;
    // Parse functions prove syntax only. ReadQualified verifies actual certificate,
    // proof and package bytes; the producer still verifies loaded/live identity.
    static bool ParseRecipe(const FString& Json,FLivingTownMetaHumanMealRecipeV2& Out,FString& Error);
    static bool ParseCertificate(const FString& Json,const FLivingTownMetaHumanMealRecipeV2& Recipe,FLivingTownMetaHumanMealRecipeV2& Out,FString& Error);
    static bool ReadQualified(const FString& ContentRelativeRecipe,FLivingTownMetaHumanMealRecipeV2& Out,FString& Error);
};
