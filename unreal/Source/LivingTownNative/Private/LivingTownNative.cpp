#include "Modules/ModuleManager.h"
#include "LivingTownCookedStartup.h"
#include "Misc/CoreDelegates.h"
#include "UObject/UObjectGlobals.h"
class FLivingTownNativeModule final : public FDefaultGameModuleImpl
{
    FDelegateHandle EngineInit,MapLoaded;
public:
    virtual void StartupModule() override
    {
        FDefaultGameModuleImpl::StartupModule();
        if(!LivingTownCookedStartup::IsRequested())return;
        LivingTownCookedStartup::Mark(TEXT("ModuleStartup"));
        EngineInit=FCoreDelegates::OnFEngineLoopInitComplete.AddLambda([](){LivingTownCookedStartup::Mark(TEXT("EngineInitComplete"));});
        MapLoaded=FCoreUObjectDelegates::PostLoadMapWithWorld.AddLambda([](UWorld* W){if(W)LivingTownCookedStartup::Mark(TEXT("RootMapLoaded"),W);});
    }
    virtual void ShutdownModule() override
    {
        if(EngineInit.IsValid())FCoreDelegates::OnFEngineLoopInitComplete.Remove(EngineInit);
        if(MapLoaded.IsValid())FCoreUObjectDelegates::PostLoadMapWithWorld.Remove(MapLoaded);
        FDefaultGameModuleImpl::ShutdownModule();
    }
};
IMPLEMENT_PRIMARY_GAME_MODULE(FLivingTownNativeModule,LivingTownNative,"LivingTownNative");
