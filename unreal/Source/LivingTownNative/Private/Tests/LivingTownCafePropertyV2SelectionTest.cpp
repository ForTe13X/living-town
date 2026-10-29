#include "../../ThirdParty/CafePropertyBackend.hpp"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownCafePropertyV2SelectionTest,"LivingTown.PropertyV2.ExclusiveBackendSelection",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownCafePropertyV2SelectionTest::RunTest(const FString&){
    namespace B=living_town::cafe_property_backend;
    for(bool Requested:{false,true}){
        const bool V1=B::Select(Requested)==B::Backend::LegacyV1,V2=B::Select(Requested)==B::Backend::PropertyV2;
        TestEqual(TEXT("Exactly one backend selected before world activation"),int32(V1)+int32(V2),1);
        TestTrue(TEXT("Default v1 selection is preserved without new flag"),Requested?V2:V1);
    }
    TestTrue(TEXT("Explicit v2 standalone exact scenario activates"),B::CanActivateV2(true,true,true,false,false));
    TestFalse(TEXT("Default scenario cannot silently activate v2"),B::CanActivateV2(false,true,true,false,false));
    TestFalse(TEXT("Legacy or arbitrary GameMode cannot activate v2"),B::CanActivateV2(true,false,true,false,false));
    TestFalse(TEXT("Network session cannot activate local two-persona authority"),B::CanActivateV2(true,true,false,false,false));
    TestFalse(TEXT("Worker diagnostic flag cannot mix with production property effects"),B::CanActivateV2(true,true,true,true,false));
    TestFalse(TEXT("Explicit legacy request conflicts with v2 activation"),B::CanActivateV2(true,true,true,false,true));
    TestTrue(TEXT("A conflicting request still selects exactly one inactive-until-validated backend"),B::Select(true)==B::Backend::PropertyV2);
    return !HasAnyErrors();
}
#endif
