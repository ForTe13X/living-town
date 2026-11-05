#pragma once

#include "Kismet/BlueprintFunctionLibrary.h"
#include "LivingTownMetaHumanAuth.generated.h"

/** Editor-only launcher. Authentication input remains in Epic's official browser flow. */
UCLASS()
class LIVINGTOWNMATERIALINSPECTION_API ULivingTownMetaHumanAuth : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()
public:
    // Module startup only, before EditorConfig has loaded user JSON settings.
    static void RegisterPrivateEditorConfig();

    UFUNCTION(BlueprintCallable, Category="LivingTown|MetaHuman")
    static FString OpenSignInLauncher();

    UFUNCTION(BlueprintCallable, Category="LivingTown|MetaHuman")
    static FString ReadSignInState();

    UFUNCTION(BlueprintCallable, Category="LivingTown|MetaHuman")
    static FString CloseSignInLauncher();
};
