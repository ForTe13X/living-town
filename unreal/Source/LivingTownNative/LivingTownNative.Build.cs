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
        PrivateDependencyModuleNames.Add("PakFile");
        PrivateDefinitions.Add("LIVINGTOWN_COOKED_STARTUP_DIAGNOSTIC=" +
            ((Target.Type == TargetType.Game && Target.Configuration == UnrealTargetConfiguration.Development) ? "1" : "0"));
        PrivateDependencyModuleNames.Add("RHI");
        PrivateDependencyModuleNames.AddRange(new string[] { "ChaosClothAssetEngine", "PhysicsCore" });
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
        // native V6 adapter. Byte binding does not qualify a native meal journey.
        string[,] MealCareSources = {
            { "DailyLifeUseV1.hpp", "4125cb255d220dfb41c7a72953c2a90623c7f5f7b3fbc2418d633955b8cb23e6" },
            { "CafeWorldV3.hpp", "93dc3e8ec181ce3de1071d36335257ee8d6a2c57fce61f56c2282dffb05f9724" },
            { "CafeWorldV3Envelope.hpp", "562b39067b5b78ec24456dc56ac83dab772adf6c476a7a56074041ca1d6640ce" },
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
