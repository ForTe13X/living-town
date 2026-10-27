#include "LivingTownCafeSlot.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/ScopeExit.h"
#include "HAL/FileManager.h"
#if PLATFORM_WINDOWS
#include "Windows/WindowsHWrapper.h"
#endif
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafeAtomicSlotTest,"LivingTown.Native.CafeAtomicSlot",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafeAtomicSlotTest::RunTest(const FString&)
{
#if PLATFORM_WINDOWS
    const FString Path=FPaths::Combine(FPaths::ProjectSavedDir(),TEXT("CafePilotTests"),FGuid::NewGuid().ToString(EGuidFormats::Digits)+TEXT(".json"));FString Error,Read;
    ON_SCOPE_EXIT{IFileManager::Get().Delete(*Path);};
    if(!TestTrue(TEXT("Fresh real slot creation"),LivingTownCafeSlot::WriteAtomic(Path,TEXT("{\"generation\":\"old\"}"),Error)))return false;
    const FString Full=FPaths::ConvertRelativePathToFull(Path);HANDLE Locked=CreateFileW(*Full,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(!TestTrue(TEXT("Actual destination opened without delete sharing"),Locked!=INVALID_HANDLE_VALUE))return false;
    const bool Replaced=LivingTownCafeSlot::WriteAtomic(Path,TEXT("{\"generation\":\"new\"}"),Error);CloseHandle(Locked);
    TestFalse(TEXT("Locked destination replacement fails"),Replaced);TestTrue(TEXT("Old slot remains readable after failed replacement"),FFileHelper::LoadFileToString(Read,*Path));TestEqual(TEXT("Failed replacement preserves old bytes"),Read,FString(TEXT("{\"generation\":\"old\"}")));
    TestTrue(TEXT("Unlocked same-directory replacement succeeds"),LivingTownCafeSlot::WriteAtomic(Path,TEXT("{\"generation\":\"new\"}"),Error));TestTrue(TEXT("New committed slot readable"),FFileHelper::LoadFileToString(Read,*Path));TestEqual(TEXT("New generation exact"),Read,FString(TEXT("{\"generation\":\"new\"}")));return true;
#else
    AddError(TEXT("Atomic slot backend is deliberately unqualified outside the bounded Windows native pilot."));return false;
#endif
}
#endif
