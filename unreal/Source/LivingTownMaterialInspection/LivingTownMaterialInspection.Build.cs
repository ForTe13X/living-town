using UnrealBuildTool;
public class LivingTownMaterialInspection : ModuleRules {
 public LivingTownMaterialInspection(ReadOnlyTargetRules Target) : base(Target) {
  PCHUsage=PCHUsageMode.NoPCHs; bUseUnity=false;
  PublicDependencyModuleNames.AddRange(new string[]{"Core","CoreUObject","Engine"});
  PrivateDependencyModuleNames.Add("Json");
  PrivateDependencyModuleNames.AddRange(new string[]{"MeshDescription","StaticMeshDescription","PhysicsCore","Chaos","AssetRegistry"});

 PrivateDependencyModuleNames.Add("RHI");
  PrivateDependencyModuleNames.Add("UnrealEd");
  PrivateDependencyModuleNames.Add("Landscape");
  PrivateDependencyModuleNames.Add("Foliage");
  PrivateDependencyModuleNames.Add("LivingTownNative");
 }
}
