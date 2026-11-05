#include "LivingTownMetaHumanBakeBudget.h"
#include "Editor.h"
#include "MetaHumanCollectionPipeline.h"
#include "MetaHumanDefaultEditorPipelineBase.h"
#include "MetaHumanCharacterEditorSubsystem.h"
#include "Subsystem/MetaHumanCharacterBuild.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "UObject/Package.h"

namespace
{
    using FResMap = TMap<FName, EMetaHumanBuildTextureResolution>;
    const TCHAR* HighClass = TEXT("/MetaHumanCharacter/BuildPipeline/BP_DefaultLegacyPipeline_High.BP_DefaultLegacyPipeline_High_C");
    const TArray<FName> FaceNames{TEXT("T_Head_LOD1_N"), TEXT("T_Head_LOD1_SRMF")};
    const TArray<FName> BodyNames{TEXT("T_Body_BC"), TEXT("T_Body_N"), TEXT("T_Body_SRMF")};

    FString SerializeBudget(const TSharedRef<FJsonObject>& Root)
    {
        FString Result;
        FJsonSerializer::Serialize(Root, TJsonWriterFactory<>::Create(&Result));
        return Result;
    }

    TSharedRef<FJsonObject> Resolutions(const FResMap& Values)
    {
        auto Result = MakeShared<FJsonObject>();
        for (const auto& Pair : Values) Result->SetNumberField(Pair.Key.ToString(), static_cast<int32>(Pair.Value));
        return Result;
    }

    bool Equal(const FResMap& A, const FResMap& B)
    {
        if (A.Num() != B.Num()) return false;
        for (const auto& Pair : A)
        {
            const auto* Other = B.Find(Pair.Key);
            if (!Other || *Other != Pair.Value) return false;
        }
        return true;
    }

    TSharedRef<FJsonObject> BakingOptions(const FMetaHumanMaterialBakingOptions& Options, TSet<FName>& Keys)
    {
        auto Result = MakeShared<FJsonObject>();
        Result->SetStringField(TEXT("settings_reference"), Options.BakingSettings.ToSoftObjectPath().ToString());
        Result->SetObjectField(TEXT("resolution_overrides"), Resolutions(Options.TextureResolutionsOverrides));
        const auto* Settings = Options.BakingSettings.LoadSynchronous();
        Result->SetBoolField(TEXT("settings_loaded"), Settings != nullptr);
        TArray<TSharedPtr<FJsonValue>> Outputs;
        if (Settings)
        {
            Result->SetStringField(TEXT("settings_class"), Settings->GetClass()->GetPathName());
            for (const auto& Graph : Settings->TextureGraphs)
                for (const auto& Output : Graph.OutputTextures)
                {
                    Keys.Add(Output.OutputTextureName);
                    Outputs.Add(MakeShared<FJsonValueString>(Output.OutputTextureName.ToString()));
                }
        }
        Result->SetArrayField(TEXT("named_graph_outputs"), Outputs);
        return Result;
    }

    UMetaHumanDefaultEditorPipelineBase* Inspect(UObject* Object, const TSharedRef<FJsonObject>& Root)
    {
        Root->SetStringField(TEXT("status"), TEXT("REFUSED_EDITOR_CONTEXT"));
        if (!IsInGameThread() || !GIsEditor || !GEditor || GEditor->PlayWorld || IsRunningCommandlet()) return nullptr;
        Root->SetStringField(TEXT("status"), TEXT("REFUSED_OWNED_TRANSIENT_HIGH_PIPELINE"));
        auto* Pipeline = Cast<UMetaHumanCollectionPipeline>(Object);
        if (!Pipeline || Pipeline->IsTemplate() || Pipeline->GetOutermost() != GetTransientPackage() || Pipeline->GetClass()->GetPathName() != HighClass) return nullptr;
        auto* Editor = Cast<UMetaHumanDefaultEditorPipelineBase>(Pipeline->GetMutableEditorPipeline());
        if (!Editor || Editor->IsTemplate() || Editor->GetOuter() != Pipeline) return nullptr;
        Root->SetStringField(TEXT("pipeline"), Pipeline->GetPathName());
        Root->SetStringField(TEXT("pipeline_class"), Pipeline->GetClass()->GetPathName());
        Root->SetStringField(TEXT("editor_pipeline"), Editor->GetPathName());
        Root->SetStringField(TEXT("editor_pipeline_class"), Editor->GetClass()->GetPathName());
        Root->SetBoolField(TEXT("bake_materials"), Editor->bBakeMaterials);
        TSet<FName> Ignored;
        Root->SetObjectField(TEXT("face"), BakingOptions(Editor->MaterialBakingOptions.FaceBakingOptions, Ignored));
        Ignored.Reset();
        Root->SetObjectField(TEXT("body"), BakingOptions(Editor->MaterialBakingOptions.BodyBakingOptions, Ignored));
        Root->SetStringField(TEXT("status"), TEXT("PASS_INSPECTED_OWNED_TRANSIENT_HIGH_PIPELINE"));
        return Editor;
    }
}

FString ULivingTownMetaHumanBakeBudget::InspectPipeline(UObject* Pipeline)
{
    auto Root = MakeShared<FJsonObject>();
    Inspect(Pipeline, Root);
    return SerializeBudget(Root);
}

FString ULivingTownMetaHumanBakeBudget::Configure2KOutputs(UObject* Pipeline)
{
    auto Root = MakeShared<FJsonObject>();
    auto* Editor = Inspect(Pipeline, Root);
    if (!Editor) return SerializeBudget(Root);
    Root->SetStringField(TEXT("status"), TEXT("REFUSED_BAKING_SETTINGS_OR_OUTPUT_NAMES"));
    TSet<FName> FaceKeys, BodyKeys;
    const auto FaceInfo = BakingOptions(Editor->MaterialBakingOptions.FaceBakingOptions, FaceKeys);
    const auto BodyInfo = BakingOptions(Editor->MaterialBakingOptions.BodyBakingOptions, BodyKeys);
    if (!Editor->bBakeMaterials || !FaceInfo->GetBoolField(TEXT("settings_loaded")) || !BodyInfo->GetBoolField(TEXT("settings_loaded"))) return SerializeBudget(Root);
    for (const FName Name : FaceNames) if (!FaceKeys.Contains(Name)) return SerializeBudget(Root);
    for (const FName Name : BodyNames) if (!BodyKeys.Contains(Name)) return SerializeBudget(Root);
    const auto* CDO = Cast<UMetaHumanCollectionPipeline>(Pipeline->GetClass()->GetDefaultObject());
    const auto* DefaultEditor = CDO ? Cast<UMetaHumanDefaultEditorPipelineBase>(CDO->GetEditorPipeline()) : nullptr;
    if (!DefaultEditor || DefaultEditor == Editor) return SerializeBudget(Root);
    const FResMap DefaultFaceBefore = DefaultEditor->MaterialBakingOptions.FaceBakingOptions.TextureResolutionsOverrides;
    const FResMap DefaultBodyBefore = DefaultEditor->MaterialBakingOptions.BodyBakingOptions.TextureResolutionsOverrides;
    FResMap ExpectedFace = Editor->MaterialBakingOptions.FaceBakingOptions.TextureResolutionsOverrides;
    FResMap ExpectedBody = Editor->MaterialBakingOptions.BodyBakingOptions.TextureResolutionsOverrides;
    for (const FName Name : FaceNames) ExpectedFace.Add(Name, EMetaHumanBuildTextureResolution::Res2048);
    for (const FName Name : BodyNames) ExpectedBody.Add(Name, EMetaHumanBuildTextureResolution::Res2048);
    for (const FName Name : FaceNames) Editor->MaterialBakingOptions.FaceBakingOptions.TextureResolutionsOverrides.Add(Name, EMetaHumanBuildTextureResolution::Res2048);
    for (const FName Name : BodyNames) Editor->MaterialBakingOptions.BodyBakingOptions.TextureResolutionsOverrides.Add(Name, EMetaHumanBuildTextureResolution::Res2048);
    const bool InstanceExact = Equal(ExpectedFace, Editor->MaterialBakingOptions.FaceBakingOptions.TextureResolutionsOverrides) && Equal(ExpectedBody, Editor->MaterialBakingOptions.BodyBakingOptions.TextureResolutionsOverrides);
    const bool CDOUnchanged = Equal(DefaultFaceBefore, DefaultEditor->MaterialBakingOptions.FaceBakingOptions.TextureResolutionsOverrides) && Equal(DefaultBodyBefore, DefaultEditor->MaterialBakingOptions.BodyBakingOptions.TextureResolutionsOverrides);
    Root->SetObjectField(TEXT("face_overrides_after"), Resolutions(Editor->MaterialBakingOptions.FaceBakingOptions.TextureResolutionsOverrides));
    Root->SetObjectField(TEXT("body_overrides_after"), Resolutions(Editor->MaterialBakingOptions.BodyBakingOptions.TextureResolutionsOverrides));
    Root->SetBoolField(TEXT("all_other_overrides_preserved"), InstanceExact);
    Root->SetBoolField(TEXT("class_defaults_unchanged"), CDOUnchanged);
    Root->SetBoolField(TEXT("no_source_or_pipeline_asset_saved"), true);
    Root->SetStringField(TEXT("status"), InstanceExact && CDOUnchanged ? TEXT("PASS_CONFIGURED_FIVE_NATIVE_2K_BAKED_OUTPUTS") : TEXT("REFUSED_NATIVE_READBACK"));
    return SerializeBudget(Root);
}

FString ULivingTownMetaHumanBakeBudget::BuildConfiguredHigh(UObject* CharacterObject, UObject* PipelineObject, const FString& AssemblyRoot, const FString& CommonRoot)
{
    auto Root = MakeShared<FJsonObject>();
    auto* Editor = Inspect(PipelineObject, Root);
    if (!Editor) return SerializeBudget(Root);
    Root->SetStringField(TEXT("status"), TEXT("REFUSED_CONFIGURED_ASSEMBLY_INPUT"));
    auto* Character = Cast<UMetaHumanCharacter>(CharacterObject);
    auto* Pipeline = Cast<UMetaHumanCollectionPipeline>(PipelineObject);
    if (!Character || !Character->GetPathName().StartsWith(TEXT("/Game/LivingTown_UEPilot/MetaHumanProductionTrial_v001/")) ||
        !AssemblyRoot.StartsWith(TEXT("/Game/LivingTown_UEPilot/MetaHumanAssembled_v")) ||
        (!CommonRoot.IsEmpty() && !CommonRoot.StartsWith(TEXT("/Game/LivingTown_UEPilot/MetaHumanCommon_v"))) ||
        AssemblyRoot.Contains(TEXT("..")) || CommonRoot.Contains(TEXT(".."))) return SerializeBudget(Root);
    for (const FName Name : FaceNames)
    {
        const auto* Value = Editor->MaterialBakingOptions.FaceBakingOptions.TextureResolutionsOverrides.Find(Name);
        if (!Value || *Value != EMetaHumanBuildTextureResolution::Res2048) return SerializeBudget(Root);
    }
    for (const FName Name : BodyNames)
    {
        const auto* Value = Editor->MaterialBakingOptions.BodyBakingOptions.TextureResolutionsOverrides.Find(Name);
        if (!Value || *Value != EMetaHumanBuildTextureResolution::Res2048) return SerializeBudget(Root);
    }
    auto* Subsystem = GEditor->GetEditorSubsystem<UMetaHumanCharacterEditorSubsystem>();
    if (!Subsystem || !Subsystem->CanBuildMetaHuman(Character, false)) return SerializeBudget(Root);
    FMetaHumanCharacterEditorBuildParameters Params;
    Params.PipelineType = EMetaHumanDefaultPipelineType::Optimized;
    Params.PipelineQuality = EMetaHumanQualityLevel::High;
    Params.PipelineOverride = Pipeline;
    Params.AbsoluteBuildPath = AssemblyRoot;
    Params.CommonFolderPath = CommonRoot;
    Params.NameOverride = TEXT("CafeWorker_Dominic_Trial");
    Params.bEnableWardrobeItemValidation = true;
    Root->SetStringField(TEXT("character"), Character->GetPathName());
    Root->SetStringField(TEXT("assembly_root"), Params.AbsoluteBuildPath);
    Root->SetStringField(TEXT("common_root"), Params.CommonFolderPath);
    Root->SetBoolField(TEXT("shared_dependency_copy_requested"), !Params.CommonFolderPath.IsEmpty());
    Root->SetBoolField(TEXT("native_pipeline_override_bound"), Params.PipelineOverride == Pipeline);
    Root->SetBoolField(TEXT("wardrobe_validation"), Params.bEnableWardrobeItemValidation);
    Subsystem->BuildMetaHuman(Character, Params);
    // The caller must still inspect, save, and cold-load actual generated assets.
    Root->SetStringField(TEXT("status"), TEXT("RETURNED_NATIVE_CONFIGURED_HIGH_ASSEMBLY_CALL"));
    return SerializeBudget(Root);
}
