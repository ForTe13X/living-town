#pragma once
#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "../ThirdParty/CafeBackendV3.hpp"
#include "LivingTownCafeWorldV3Types.generated.h"
class ACharacter;
class UAnimSequence;
class USkeletalMesh;

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
    FString Persona,Owner,Operator,ResidentLabel,PropertyLabel,ListingLabel,MealLabel,Prompt,Notice,Diagnostic;
    int64 AriaCoins=0,BenCoins=0,Clock=0,Revision=0,Stock=0;
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
