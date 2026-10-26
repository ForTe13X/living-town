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
    }
}
