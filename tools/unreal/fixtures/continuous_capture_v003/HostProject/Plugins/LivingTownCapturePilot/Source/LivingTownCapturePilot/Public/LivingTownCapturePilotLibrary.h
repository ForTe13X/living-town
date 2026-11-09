#pragma once
#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownCapturePilotLibrary.generated.h"
class UMovieSceneCapture;
UCLASS()
class LIVINGTOWNCAPTUREPILOT_API ULivingTownCapturePilotLibrary final : public UBlueprintFunctionLibrary {
 GENERATED_BODY()
public:
 UFUNCTION(BlueprintCallable,Category="LivingTown|CapturePilot") static FString ReadActiveEditorViewportExposure();
 UFUNCTION(BlueprintCallable,Category="LivingTown|CapturePilot") static FString ProbeExistingGameViewport();
 UFUNCTION(BlueprintCallable,Category="LivingTown|CapturePilot") static FString StartExistingGameViewportCapture();
 UFUNCTION(BlueprintCallable,Category="LivingTown|CapturePilot") static FString StartConfiguredExistingGameViewportCapture(UMovieSceneCapture* Capture);
 UFUNCTION(BlueprintCallable,Category="LivingTown|DirectReadback") static FString BeginExistingGameViewportReadbackProbe(const FString& OutputDirectory);
 UFUNCTION(BlueprintCallable,Category="LivingTown|DirectReadback") static FString ReadExistingGameViewportReadbackProbe();
 UFUNCTION(BlueprintCallable,Category="LivingTown|DirectReadback") static FString RequestExistingGameViewportReadbackSample(const FString& Label);
 UFUNCTION(BlueprintCallable,Category="LivingTown|DirectReadback") static FString CancelExistingGameViewportReadbackProbe();
  // Continuous003: exact existing viewport, bounded asynchronous source readback.
  UFUNCTION(BlueprintCallable, Category="LivingTown|ContinuousCapture")
  static FString BeginExistingGameViewportContinuousCapture(const FString& OutputDirectory);
  UFUNCTION(BlueprintCallable, Category="LivingTown|ContinuousCapture")
  static FString StartExistingGameViewportContinuousCapture();
  UFUNCTION(BlueprintCallable, Category="LivingTown|ContinuousCapture")
  static FString ReadExistingGameViewportContinuousCapture();
  UFUNCTION(BlueprintCallable, Category="LivingTown|ContinuousCapture")
  static FString StopExistingGameViewportContinuousCapture();
  UFUNCTION(BlueprintCallable, Category="LivingTown|ContinuousCapture")
  static FString CancelExistingGameViewportContinuousCapture();
};
