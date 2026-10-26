using UnrealBuildTool;
public class LivingTownEditorTarget : TargetRules
{
    public LivingTownEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.Latest;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        ExtraModuleNames.Add("LivingTownNative");
        ExtraModuleNames.Add("LivingTownMaterialInspection");
    }
}
