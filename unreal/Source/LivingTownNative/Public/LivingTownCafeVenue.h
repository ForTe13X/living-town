#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "LivingTownCafeBinding.h"
#include "LivingTownCafeVenue.generated.h"
class UStaticMeshComponent;

UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownCafeVenue final : public AActor
{
    GENERATED_BODY()
public:
    ALivingTownCafeVenue();
    bool BuildQualified(const FLivingTownCafeBinding& Binding,FString& Error);
    bool IsQualified() const { return bQualified; }
    bool IsFloorComponent(const UPrimitiveComponent* Component) const;
    bool IsCounterComponent(const UPrimitiveComponent* Component) const;
    bool FloorAt(const FVector& Feet,FHitResult& Hit,const AActor* Ignore=nullptr) const;
private:
    UPROPERTY() TArray<TObjectPtr<UStaticMeshComponent>> Parts;
    TSet<const UPrimitiveComponent*> FloorParts;
    TSet<const UPrimitiveComponent*> CounterParts;
    bool bQualified=false;
};
