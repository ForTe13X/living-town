using UnrealBuildTool;
public class LivingTownCapturePilot : ModuleRules {
 public LivingTownCapturePilot(ReadOnlyTargetRules Target) : base(Target) {
  PCHUsage=PCHUsageMode.UseExplicitOrSharedPCHs;
  PublicDependencyModuleNames.AddRange(new string[]{"Core","CoreUObject","Engine"});
  PrivateDependencyModuleNames.AddRange(new string[]{"UnrealEd","Slate","SlateCore","MovieSceneCapture","Json","RHI","RenderCore","ImageCore","ImageWrapper"});
 }
}
