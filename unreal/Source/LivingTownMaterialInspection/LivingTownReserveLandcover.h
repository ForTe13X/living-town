#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownReserveLandcover.generated.h"

// Editor-only, fixed Pond126 source family. No runtime painting, caller paths or asset saves.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownReserveLandcover final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|Reserve Landcover")
    static FString ApplyReserveLandcoverPreview();

    UFUNCTION(BlueprintCallable, Category="LivingTown|Reserve Landcover")
    static FString ReadReserveLandcoverPreview();
};
