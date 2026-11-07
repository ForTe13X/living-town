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
        // native V2 adapter. Byte binding does not qualify a native meal journey.
        string[,] MealCareSources = {
            { "DailyLifeUseV1.hpp", "3968a82beab862fdd56054d1fe6cfe08aca3c7be41003a1fdc82abae56841d06" },
            { "CafeWorldV3.hpp", "9c31b82a263b389457a8d3ea00344f90e24b81f646f66a6b8377ccb4b85be46d" },
            { "CafeWorldV3Envelope.hpp", "f003c16885a0fb8213f492114d1b9aa108791385f45a6c23f4e12e67d17b7616" },
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
