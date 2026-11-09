using UnrealBuildTool;
public class CapturePilotHost : ModuleRules {
 public CapturePilotHost(ReadOnlyTargetRules Target) : base(Target) {
  PCHUsage=PCHUsageMode.UseExplicitOrSharedPCHs;
  PublicDependencyModuleNames.AddRange(new string[]{"Core"});
 }
}
