#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownGroundIntakeInspection.generated.h"

class UTexture2D;

// Editor-only, exact frozen ground-family roster. Never cooks, repairs or saves assets.
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownGroundIntakeInspection final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    UFUNCTION(BlueprintCallable, Category="LivingTown|GroundIntakeInspection")
    static FString ExportGroundCollisionMeshes(const TArray<FString>& AssetPaths,
        const FString& RelativeOutputDirectory);

    // Begin returns a token/PENDING. Poll is nonblocking; a five-second deadline returns HOLD.
    // The render command copies only the held resource's scalar RHI descriptor, never texels.
    UFUNCTION(BlueprintCallable, Category="LivingTown|GroundIntakeInspection")
    static FString BeginGroundTextureRead(UTexture2D* Texture);

    UFUNCTION(BlueprintCallable, Category="LivingTown|GroundIntakeInspection")
    static FString PollGroundTextureRead(const FString& Token);
};
