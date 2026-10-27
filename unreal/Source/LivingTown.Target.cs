using UnrealBuildTool;
public class LivingTownTarget : TargetRules
{
    public LivingTownTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Game;
        DefaultBuildSettings = BuildSettingsVersion.Latest;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        ExtraModuleNames.Add("LivingTownNative");
    }
}
