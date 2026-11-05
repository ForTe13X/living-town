#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownBMaterialInspection.generated.h"

class UTexture2D;

// Editor-only saved Mill Court B finish-family observation. Never imports,
// recompiles, forces streaming, edits source/platform data, or saves packages.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownBMaterialInspection final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    // Already-loaded exact-nine Texture2D roster and exact saved B editor world.
    // One pending token, once per asset in this Editor process; no synchronous wait.
    UFUNCTION(BlueprintCallable, Category="LivingTown|BMaterialInspection")
    static FString BeginBTextureRead(UTexture2D* Texture);

    // Poll on subsequent Editor game-thread ticks. Five-second RT deadline;
    // timeout retains the strong UObject owner until its queued read completes.
    UFUNCTION(BlueprintCallable, Category="LivingTown|BMaterialInspection")
    static FString PollBTextureRead(const FString& Token);
};
