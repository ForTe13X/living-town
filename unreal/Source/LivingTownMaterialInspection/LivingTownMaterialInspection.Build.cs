using UnrealBuildTool;
public class LivingTownMaterialInspection : ModuleRules {
 public LivingTownMaterialInspection(ReadOnlyTargetRules Target) : base(Target) {
  PCHUsage=PCHUsageMode.NoPCHs; bUseUnity=false;
  PublicDependencyModuleNames.AddRange(new string[]{"Core","CoreUObject","Engine"});
  PrivateDependencyModuleNames.Add("Json");
 }
}
