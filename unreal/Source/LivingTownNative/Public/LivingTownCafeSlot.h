#pragma once
#include "CoreMinimal.h"
namespace LivingTownCafeSlot
{
    // Windows local NTFS/ReFS first-journey implementation. Does not delete an
    // existing slot before replacement; other backends refuse explicitly.
    bool WriteAtomic(const FString& Path,const FString& Json,FString& Error);
}
