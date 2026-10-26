#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownCafeGeometryLibrary.generated.h"
class UStaticMesh;

UCLASS()
class LIVINGTOWNNATIVE_API ULivingTownCafeGeometryLibrary final : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    // Read-only native consumer for the import/calibration producer. Includes all
    // LOD0 positions, packed-basis decoded XYZW, every UV/color/index and sections.
    UFUNCTION(BlueprintCallable, Category="Living Town|Cafe Calibration")
    static bool InspectCafeMesh(UStaticMesh* Mesh, FString& RenderSha256, FString& CollisionGuid, FString& Error);
};
