using UnrealBuildTool;
using System;
using System.IO;
using System.Security.Cryptography;

public class LivingTownNative : ModuleRules
{
    public LivingTownNative(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.NoPCHs;
        bUseUnity = false;
        bEnableExceptions = true;
        CppStandard = CppStandardVersion.Cpp20;
        PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine", "InputCore" });
        PrivateDependencyModuleNames.Add("Json");
        AddEngineThirdPartyPrivateStaticDependencies(Target, "OpenSSL");
        string CoreFile = Path.Combine(ModuleDirectory, "ThirdParty", "LeaseKernel.hpp");
        string Actual = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(CoreFile))).ToLowerInvariant();
        if (Actual != "942eb43c7b822da17c4949b08aa890d65324cd6d0e31bafa5d5104440641a8ac")
            throw new BuildException("Frozen lease core byte binding changed: " + Actual);
        ExternalDependencies.Add(CoreFile);
        string PropertyCoreFile = Path.Combine(ModuleDirectory, "ThirdParty", "CafePropertyV2.hpp");
        string PropertyActual = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(PropertyCoreFile))).ToLowerInvariant();
        if (PropertyActual != "50adb86b5333436ff6af330ed02ca3b21b9aae0cc7f92c32d833dcdb61ec76ab")
            throw new BuildException("Frozen property v2 core byte binding changed: " + PropertyActual);
        ExternalDependencies.Add(PropertyCoreFile);
        // Portable meal/care inputs are versioned separately from the current
        // native V2 adapter. Byte binding does not qualify a native meal journey.
        string[,] MealCareSources = {
            { "DailyLifeUseV1.hpp", "3968a82beab862fdd56054d1fe6cfe08aca3c7be41003a1fdc82abae56841d06" },
            { "CafeWorldV3.hpp", "4856df21feca1d51d357454cee2047e4de19e4ffa7c16aa57d459f6f0793e903" },
            { "CafeWorldV3Envelope.hpp", "0cf5fca9a0f91fbaedfa83ab8e786f5022733aa33a56ea8f954d244bb9bd2690" },
            { "CafeBackendV3.hpp", "f311599b6bb10f4ac60281c9bb2bbaf904b62bf8fec68b1ac46d7ae7e932994d" }
        };
        for (int Index = 0; Index < MealCareSources.GetLength(0); ++Index)
        {
            string MealCareFile = Path.Combine(ModuleDirectory, "ThirdParty", MealCareSources[Index, 0]);
            string MealCareActual = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(MealCareFile))).ToLowerInvariant();
            if (MealCareActual != MealCareSources[Index, 1])
                throw new BuildException("Frozen portable meal/care source changed: " + MealCareSources[Index, 0] + ": " + MealCareActual);
            ExternalDependencies.Add(MealCareFile);
        }
    }
}
