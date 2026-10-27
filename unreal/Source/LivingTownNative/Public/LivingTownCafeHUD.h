#pragma once
#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "LivingTownCafeHUD.generated.h"
UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ALivingTownCafeHUD final : public AHUD
{
    GENERATED_BODY()
public:virtual void DrawHUD()override;
};
