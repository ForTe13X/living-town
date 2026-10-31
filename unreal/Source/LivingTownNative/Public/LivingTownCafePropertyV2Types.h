#pragma once
#include "CoreMinimal.h"

enum class ELivingTownCafePropertyPersona : uint8 { Aria, Ben };
enum class ELivingTownCafePropertyAction : uint8 { OfferLease, OfferSale, Buy, Lease, EndLease };
struct FLivingTownCafePropertyCommand {
    FString RequestId;
    FString PropertyId=TEXT("cafe_ground_commercial_v1");
    ELivingTownCafePropertyAction Action=ELivingTownCafePropertyAction::Lease;
};
struct FLivingTownCafePropertyReceipt {bool bAccepted=false,bAlreadyApplied=false;FString Reason;int64 EventId=-1;};
struct FLivingTownCafePropertyView {
    bool bPrepared=false,bSessionReady=false,bReachable=false,bOwnerVisualArtQualified=false;
    FString Persona,Owner,Operator,Offer,Prompt,Notice;
    int64 AriaCoins=0,BenCoins=0,Clock=0,EventCount=0,LeaseEnd=-1;
    // Derived UI labels only; raw fields/Lines remain available in details.
    bool bShowCounterHint=false,bPresentationWarning=false;
    FString ResidentLabel,PropertyLabel,ListingLabel,InteractionLabel,ActionHint;
    TArray<FString> Lines;
};
