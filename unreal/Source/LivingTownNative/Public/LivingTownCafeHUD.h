#pragma once
#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "LivingTownCafeHUD.generated.h"
class UFont;
UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownCafeHUD final : public AHUD
{
    GENERATED_BODY()
public:
    virtual void DrawHUD()override;
    bool IsCounterContextVisible()const;
    // Live feedback stays independent from the last controller operation.
    TArray<FString> GetFeedbackRows()const;
private:
    TArray<FString> CachedFeedbackRows,CachedWrappedFeedback;
    TWeakObjectPtr<UFont> CachedFeedbackFont;
    float CachedFeedbackWidth=-1.f,CachedFeedbackTextScale=-1.f;
    bool bFeedbackLayoutCached=false;
};
