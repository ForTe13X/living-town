#include "LivingTownTileStreamingSubsystem.h"
#include "../LivingTownMaterialUsage.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "Materials/MaterialInstanceConstant.h"
#include "PhysicsEngine/BodySetup.h"
#include "UObject/Package.h"
#include "UObject/StrongObjectPtr.h"

// Synthetic transient objects only; fake cached render receipts cannot qualify
// production geometry. No component registration or shader compile is needed.
struct FLivingTownTileMaterialUsageTestAccess
{
    static bool Run(FAutomationTestBase& Test)
    {
        TStrongObjectPtr<UWorld> World(NewObject<UWorld>(GetTransientPackage()));
        auto* S=NewObject<ULivingTownTileStreamingSubsystem>(World.Get());
        auto* Material=NewObject<UMaterial>(World.Get());
        auto* Mesh=NewObject<UStaticMesh>(World.Get());
        Mesh->bAllowCPUAccess=true;Mesh->CreateBodySetup();
        if(!Test.TestNotNull(TEXT("synthetic body setup"),Mesh->GetBodySetup()))return false;
        Material->SetUsageByFlag(MATUSAGE_InstancedStaticMeshes,false);
        Material->bUsedAsSpecialEngineMaterial=false;
        Mesh->GetStaticMaterials().Add(FStaticMaterial(Material,TEXT("leaf")));
        FLivingTownTileGeometry G;G.EntryId=TEXT("synthetic_leaf_batch");G.Mesh=Mesh;
        G.NativeCollisionGuid=Mesh->GetBodySetup()->BodySetupGuid.ToString(EGuidFormats::Digits).ToLower();
        G.NativeRenderSha256=FString::ChrN(64,'a');
        G.QualifiedMaterialPaths={FSoftObjectPath(Material)};G.QualifiedMaterialSlotNames={TEXT("leaf")};
        G.QualifiedMaterialBlendModes={uint8(Material->GetBlendMode())};
        ULivingTownTileStreamingSubsystem::FVerifiedMesh Cached;
        Cached.Mesh=Mesh;Cached.LightingGuid=Mesh->GetLightingGuid();Cached.RenderSha256=G.NativeRenderSha256;
        Cached.CollisionGuid=G.NativeCollisionGuid;Cached.MaterialPaths=G.QualifiedMaterialPaths;
        Cached.MaterialSlotNames=G.QualifiedMaterialSlotNames;Cached.MaterialBlendModes=G.QualifiedMaterialBlendModes;
        S->VerifiedMeshes.Add(G.Mesh.ToSoftObjectPath().ToString(),Cached);
        bool Waiting=false;FString Error;
        for(auto Kind:{ELivingTownTileEntryKind::Static,ELivingTownTileEntryKind::DeferredDoor})
        {
            G.Kind=Kind;Error.Empty();
            Test.TestTrue(TEXT("noninstanced policy does not require ISM usage"),S->ValidateLoadedGeometry(G,Mesh,Waiting,Error));
            Test.TestFalse(TEXT("cached qualification does not wait"),Waiting);
        }
        G.Kind=ELivingTownTileEntryKind::Instanced;Error.Empty();
        const auto FlagsBefore=Material->GetUsageFlags();
        Test.TestFalse(TEXT("static-first cache cannot bypass instanced usage refusal"),S->ValidateLoadedGeometry(G,Mesh,Waiting,Error));
        Test.TestTrue(TEXT("actionable material identity"),Error.Contains(Material->GetPathName())&&Error.Contains(G.EntryId)&&Error.Contains(TEXT("slot=0"))&&Error.Contains(TEXT("MATUSAGE_InstancedStaticMeshes")));
        Test.TestEqual(TEXT("refusal never enables material usage"),Material->GetUsageFlags(),FlagsBefore);
        Test.TestFalse(TEXT("refusal does not schedule verification wait"),Waiting);
        Material->SetUsageByFlag(MATUSAGE_InstancedStaticMeshes,true);Error.Empty();
        Test.TestTrue(TEXT("prepared material passes existing cached identity"),S->ValidateLoadedGeometry(G,Mesh,Waiting,Error));
        Material->SetUsageByFlag(MATUSAGE_InstancedStaticMeshes,false);Error.Empty();
        Test.TestFalse(TEXT("usage is rechecked after a previous pass"),S->ValidateLoadedGeometry(G,Mesh,Waiting,Error));

        auto* Instance=NewObject<UMaterialInstanceConstant>(World.Get());Instance->Parent=Material;
        const uint32 Bit=1u<<MATUSAGE_InstancedStaticMeshes;
        Instance->BasePropertyOverrides.bOverride_UsageFlags=Bit;
        Instance->BasePropertyOverrides.UsageFlags=Bit;Instance->UpdateOverridableBaseProperties();
        Error.Empty();
        Test.TestTrue(TEXT("effective instance usage true works with base false"),LivingTownMaterials::ValidateInstancedUsage(Instance,G.EntryId,Mesh->GetPathName(),0,Error));
        Material->SetUsageByFlag(MATUSAGE_InstancedStaticMeshes,true);
        Instance->BasePropertyOverrides.UsageFlags=0;Instance->UpdateOverridableBaseProperties();
        Error.Empty();const auto InstanceFlagsBefore=Instance->GetUsageFlags();
        Test.TestFalse(TEXT("effective instance usage false refuses with base true"),LivingTownMaterials::ValidateInstancedUsage(Instance,G.EntryId,Mesh->GetPathName(),0,Error));
        Test.TestEqual(TEXT("instance refusal never changes effective usage"),Instance->GetUsageFlags(),InstanceFlagsBefore);
        Test.TestTrue(TEXT("instance and base paths are both actionable"),Error.Contains(Instance->GetPathName())&&Error.Contains(Material->GetPathName()));
        Material->SetUsageByFlag(MATUSAGE_InstancedStaticMeshes,false);Material->bUsedAsSpecialEngineMaterial=true;
        Error.Empty();
        Test.TestTrue(TEXT("existing UE special-engine-material exemption"),LivingTownMaterials::ValidateInstancedUsage(Material,G.EntryId,Mesh->GetPathName(),0,Error));
        Error.Empty();
        Test.TestFalse(TEXT("missing material is not an implicit fallback"),LivingTownMaterials::ValidateInstancedUsage(nullptr,G.EntryId,Mesh->GetPathName(),0,Error));
        Test.AddInfo(TEXT("Synthetic gate/cache/policy/instance regression only; no production asset, shader completeness, or rendered-image acceptance implied."));
        return true;
    }
};

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FLivingTownTileMaterialUsage,"LivingTown.Native.TileMaterialUsage",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FLivingTownTileMaterialUsage::RunTest(const FString&)
{return FLivingTownTileMaterialUsageTestAccess::Run(*this);}
#endif
