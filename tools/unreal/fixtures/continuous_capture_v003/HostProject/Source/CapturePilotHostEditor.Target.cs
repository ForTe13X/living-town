using UnrealBuildTool;
public class CapturePilotHostEditorTarget : TargetRules {
 public CapturePilotHostEditorTarget(TargetInfo Target) : base(Target) {
  Type=TargetType.Editor;
  DefaultBuildSettings=BuildSettingsVersion.Latest;
  IncludeOrderVersion=EngineIncludeOrderVersion.Latest;
  ExtraModuleNames.Add("CapturePilotHost");
 }
}
