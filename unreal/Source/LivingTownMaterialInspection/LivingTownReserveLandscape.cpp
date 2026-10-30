#include "LivingTownReserveLandscape.h"
#include "LivingTownTileData.h"
#include "Editor.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "Landscape.h"
#include "LandscapeInfo.h"
#include "LandscapeComponent.h"
#include "LandscapeHeightfieldCollisionComponent.h"
#include "LandscapeEdit.h"
#include "LandscapeEditLayer.h"
#include "LandscapeDataAccess.h"
#include "Materials/Material.h"
#include "MaterialDomain.h"
#include "Materials/MaterialInterface.h"
#include "Materials/MaterialInstance.h"
#include "Engine/Texture2D.h"
#include "PhysicsEngine/BodyInstance.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/App.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/AutomationTest.h"
#include "HAL/FileManager.h"
#include "UObject/Package.h"
#include "UObject/UObjectGlobals.h"
#include "CoreGlobals.h"
#include "Components/HierarchicalInstancedStaticMeshComponent.h"
#include "GameFramework/Actor.h"
#include "ComponentInstanceDataCache.h"
#include "UObject/UnrealType.h"
#include <initializer_list>

namespace
{
constexpr int32 Side=505, Quads=63, Subsections=2, ComponentsPerAxis=4, SourceBytes=Side*Side*2;
constexpr const TCHAR* ConfigRelative=TEXT("Config/ReserveLandscape_v001.json");
constexpr const TCHAR* HeightRelative=TEXT("Content/ReserveLandscapeSource_v001/Height505.r16");
constexpr const TCHAR* MapPath=TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/ReserveLandscape_v001/L_ReserveLandscape_v001");
constexpr const TCHAR* MaterialPath=TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/ReserveLandscape_v001/M_ReserveLandscape_v001.M_ReserveLandscape_v001");
constexpr const TCHAR* Label=TEXT("LT_RESERVE_LANDSCAPE_v001");
const FVector RequiredOrigin(-60000.,-22400.,4000.),RequiredScale(100.,100.,25.);
struct FSource { TArray<uint16> Heights; FString HeightSha,ConfigSha; TArray<uint8> ConfigBytes,HeightBytes; };
struct FReserveLandscapeReplayContext
{
    bool bExplicitSource=false;
    FString ConfigPath,HeightPath,Map,Material,ActorLabel,DumpRoot,ExpectedConfigHash;
    FVector Origin,Scale;
};
bool ReserveLandscapeConnectorAppliedInThisProcess=false;
FReserveLandscapeReplayContext ReserveLandscapeLegacyContext()
{
    FReserveLandscapeReplayContext Ctx;Ctx.ConfigPath=ConfigRelative;Ctx.HeightPath=HeightRelative;Ctx.Map=MapPath;Ctx.Material=MaterialPath;Ctx.ActorLabel=Label;Ctx.Origin=RequiredOrigin;Ctx.Scale=RequiredScale;Ctx.DumpRoot=TEXT("Saved/ReserveLandscape_v001");return Ctx;
}
FReserveLandscapeReplayContext ReserveLandscapeConnectorContext()
{
    FReserveLandscapeReplayContext Ctx=ReserveLandscapeLegacyContext();Ctx.bExplicitSource=true;Ctx.ConfigPath=TEXT("Config/ReserveLandscapeConnectorA_v001.json");Ctx.HeightPath=TEXT("Content/ReserveConnectorA_v001/Height505_connectorA_v001.r16");Ctx.Map=TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/ReserveConnectorA_v001/L_ReserveConnectorA_v001");Ctx.ActorLabel=TEXT("LT_RESERVE_CONNECTOR_A_LANDSCAPE_v001");Ctx.DumpRoot=TEXT("Saved/ReserveLandscapeConnectorA_v001");return Ctx;
}
bool Fail(FString& Error,const TCHAR* Why){Error=Why;return false;}
TArray<TSharedPtr<FJsonValue>> Vector(const FVector& V)
{return {MakeShared<FJsonValueNumber>(V.X),MakeShared<FJsonValueNumber>(V.Y),MakeShared<FJsonValueNumber>(V.Z)};}
FString Json(const TSharedRef<FJsonObject>& O)
{FString Result;FJsonSerializer::Serialize(O,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Result));return Result;}
FString ErrorReply(const FString& Why)
{auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("ERROR"));O->SetStringField(TEXT("error"),Why);return Json(O);}
bool TextEquals(const FJsonObject& O,const TCHAR* Key,const TCHAR* Value)
{FString S;return O.TryGetStringField(Key,S)&&S==Value;}
bool NumberEquals(const FJsonObject& O,const TCHAR* Key,double Expected)
{double N=0;return O.TryGetNumberField(Key,N)&&FMath::IsFinite(N)&&N==Expected;}
bool ArrayEquals(const FJsonObject& O,const TCHAR* Key,std::initializer_list<double> Expected)
{
    const TArray<TSharedPtr<FJsonValue>>* A=nullptr;
    if(!O.TryGetArrayField(Key,A)||!A||A->Num()!=int32(Expected.size()))return false;
    int32 I=0;for(double N:Expected){double Actual=0;if(!(*A)[I++].IsValid()||!(*A)[I-1]->TryGetNumber(Actual)||!FMath::IsFinite(Actual)||Actual!=N)return false;}return true;
}
bool ReserveLandscapeUniqueConfigFlag(const TCHAR* CommandLine,const TCHAR* Name,FString& Value)
{
    const FString Prefix=FString(TEXT("-"))+Name+TEXT("="),NamePrefix=FString(TEXT("-"))+Name;const TCHAR* Cursor=CommandLine;FString Token;int32 Matches=0;
    while(FParse::Token(Cursor,Token,false))if(Token.StartsWith(NamePrefix,ESearchCase::IgnoreCase)){if(!Token.StartsWith(Prefix,ESearchCase::CaseSensitive)||++Matches!=1)return false;Value=Token.Mid(Prefix.Len());}
    return Matches==1&&LivingTownTiles::IsSha256(Value)&&Value==Value.ToLower();
}
bool ReserveLandscapeConnectorAuthorIntent(const FReserveLandscapeReplayContext& Ctx,const TCHAR* CommandLine,const FString& Project,bool AlreadyApplied)
{
    FString Config,Author;return Ctx.bExplicitSource&&!AlreadyApplied&&Project.EndsWith(TEXT("/Author/Project"))&&ReserveLandscapeUniqueConfigFlag(CommandLine,TEXT("LivingTownReserveConnectorConfigSHA256"),Config)&&Config==Ctx.ExpectedConfigHash&&ReserveLandscapeUniqueConfigFlag(CommandLine,TEXT("LivingTownReserveConnectorAuthor"),Author)&&Author==Ctx.ExpectedConfigHash;
}
bool ReserveLandscapeDecodeHeights(const TArray<uint8>& Raw,const FString& Expected,FSource& Out,FString& Error)
{
    if(Raw.Num()!=SourceBytes||!LivingTownTiles::HashBytes(Raw,Out.HeightSha)||Out.HeightSha!=Expected)return Fail(Error,TEXT("height_source_sha256_mismatch"));
    Out.Heights.SetNumUninitialized(Side*Side);for(int32 I=0;I<Out.Heights.Num();++I)Out.Heights[I]=uint16(Raw[I*2])|(uint16(Raw[I*2+1])<<8);return true;
}
bool ReserveLandscapeSourceCustody(const FReserveLandscapeReplayContext& Ctx,const FSource& Source,FString& Error)
{
    if(!Ctx.bExplicitSource)return true;const FString Root=FPaths::ProjectDir(),Config=FPaths::Combine(Root,Ctx.ConfigPath),Height=FPaths::Combine(Root,Ctx.HeightPath);TArray<uint8> ConfigBytes,Raw;FString ConfigHash,HeightHash;
    if(IFileManager::Get().FileSize(*Config)!=Source.ConfigBytes.Num()||IFileManager::Get().FileSize(*Height)!=SourceBytes||!FFileHelper::LoadFileToArray(ConfigBytes,*Config)||ConfigBytes!=Source.ConfigBytes||!LivingTownTiles::HashBytes(ConfigBytes,ConfigHash)||ConfigHash!=Ctx.ExpectedConfigHash||!FFileHelper::LoadFileToArray(Raw,*Height)||Raw!=Source.HeightBytes||!LivingTownTiles::HashBytes(Raw,HeightHash)||HeightHash!=Source.HeightSha)return Fail(Error,TEXT("explicit_config_or_RAW_source_custody_changed"));return true;
}
bool LoadSource(const FReserveLandscapeReplayContext& Ctx,FSource& Out,FString& Error)
{
    const FString Root=FPaths::ConvertRelativePathToFull(FPaths::ProjectDir());
    const FString Config=FPaths::Combine(Root,Ctx.ConfigPath),Height=FPaths::Combine(Root,Ctx.HeightPath);
    if(!FPaths::IsUnderDirectory(Config,Root)||!FPaths::IsUnderDirectory(Height,Root))return Fail(Error,TEXT("source_path_escaped_project"));
    const int64 ConfigSize=IFileManager::Get().FileSize(*Config);
    if(ConfigSize<=0||ConfigSize>16384||IFileManager::Get().FileSize(*Height)!=SourceBytes)return Fail(Error,TEXT("fixed_source_file_size"));
    TArray<uint8> ConfigBytes,Raw;
    if(!FFileHelper::LoadFileToArray(ConfigBytes,*Config)||ConfigBytes.Num()!=ConfigSize||!LivingTownTiles::HashBytes(ConfigBytes,Out.ConfigSha))return Fail(Error,TEXT("config_read_or_sha256"));
    if(Ctx.bExplicitSource&&Out.ConfigSha!=Ctx.ExpectedConfigHash)return Fail(Error,TEXT("explicit_raw_config_SHA_mismatch"));
    FString Text;FFileHelper::BufferToString(Text,ConfigBytes.GetData(),ConfigBytes.Num());TSharedPtr<FJsonObject> O;
    if(!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),O)||!O.IsValid())return Fail(Error,TEXT("config_json"));
    const TCHAR* Keys[]={TEXT("schema"),TEXT("map_path"),TEXT("material_path"),TEXT("height_relative_path"),TEXT("height_sha256"),TEXT("height_bytes"),TEXT("width"),TEXT("height"),TEXT("height_encoding"),TEXT("row0"),TEXT("origin_cm"),TEXT("scale_xyz"),TEXT("subsection_size_quads"),TEXT("num_subsections"),TEXT("component_count_xy")};
    if(O->Values.Num()!=UE_ARRAY_COUNT(Keys))return Fail(Error,TEXT("closed_config_keys"));
    for(const TCHAR* Key:Keys)if(!O->HasField(Key))return Fail(Error,TEXT("missing_config_key"));
    if(!TextEquals(*O,TEXT("schema"),TEXT("LivingTown.ReserveLandscapeSource.v1"))||!TextEquals(*O,TEXT("map_path"),*Ctx.Map)||!TextEquals(*O,TEXT("material_path"),*Ctx.Material)||!TextEquals(*O,TEXT("height_relative_path"),*Ctx.HeightPath)||!TextEquals(*O,TEXT("height_encoding"),TEXT("uint16_le"))||!TextEquals(*O,TEXT("row0"),TEXT("minimum_UE_Y")))return Fail(Error,TEXT("fixed_source_identity"));
    if(!NumberEquals(*O,TEXT("height_bytes"),SourceBytes)||!NumberEquals(*O,TEXT("width"),Side)||!NumberEquals(*O,TEXT("height"),Side)||!NumberEquals(*O,TEXT("subsection_size_quads"),Quads)||!NumberEquals(*O,TEXT("num_subsections"),Subsections)||!ArrayEquals(*O,TEXT("component_count_xy"),{4.,4.})||!ArrayEquals(*O,TEXT("origin_cm"),{Ctx.Origin.X,Ctx.Origin.Y,Ctx.Origin.Z})||!ArrayEquals(*O,TEXT("scale_xyz"),{Ctx.Scale.X,Ctx.Scale.Y,Ctx.Scale.Z}))return Fail(Error,TEXT("fixed_layout_transform_encoding"));
    FString Expected;if(!O->TryGetStringField(TEXT("height_sha256"),Expected)||!LivingTownTiles::IsSha256(Expected)||Expected!=Expected.ToLower())return Fail(Error,TEXT("pinned_source_sha256_required"));
    if(!FFileHelper::LoadFileToArray(Raw,*Height)||!ReserveLandscapeDecodeHeights(Raw,Expected,Out,Error))return Fail(Error,TEXT("height_source_sha256_mismatch"));
    if(Ctx.bExplicitSource){Out.ConfigBytes=MoveTemp(ConfigBytes);Out.HeightBytes=MoveTemp(Raw);}
    return true;
}
bool OwnedWorld(const FReserveLandscapeReplayContext& Ctx,UWorld*& World,FString& Error)
{
    if(!IsInGameThread()||!GEditor||!FApp::CanEverRender()||(Ctx.bExplicitSource&&GEditor->PlayWorld))return Fail(Error,TEXT("editor_game_thread_render_capable_context_required"));
    World=GEditor->GetEditorWorldContext().World();
    if(!World||World->WorldType!=EWorldType::Editor||World->IsGameWorld()||World->GetOutermost()->GetName()!=Ctx.Map)return Fail(Error,TEXT("exact_fresh_owned_landscape_map_required"));
    return true;
}
TSharedRef<FJsonObject> Receipt(const FReserveLandscapeReplayContext& Ctx,const FSource& Source,ALandscape* L)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("schema"),TEXT("LivingTown.ReserveLandscapeNative.v1"));O->SetStringField(TEXT("source_height_sha256"),Source.HeightSha);O->SetStringField(TEXT("source_config_sha256"),Source.ConfigSha);O->SetStringField(TEXT("map"),Ctx.Map);O->SetStringField(TEXT("actor"),L->GetPathName());O->SetStringField(TEXT("actor_label"),L->GetActorLabel());O->SetStringField(TEXT("guid"),L->GetLandscapeGuid().ToString());O->SetArrayField(TEXT("location_cm"),Vector(L->GetActorLocation()));O->SetArrayField(TEXT("scale_xyz"),Vector(L->GetActorScale3D()));const FRotator R=L->GetActorRotation();O->SetArrayField(TEXT("rotation_pitch_yaw_roll"),{MakeShared<FJsonValueNumber>(R.Pitch),MakeShared<FJsonValueNumber>(R.Yaw),MakeShared<FJsonValueNumber>(R.Roll)});O->SetStringField(TEXT("material"),L->LandscapeMaterial?L->LandscapeMaterial->GetPathName():TEXT(""));O->SetNumberField(TEXT("component_count"),L->LandscapeComponents.Num());O->SetNumberField(TEXT("collision_component_count"),L->CollisionComponents.Num());O->SetNumberField(TEXT("collision_mip"),L->CollisionMipLevel);O->SetNumberField(TEXT("simple_collision_mip"),L->SimpleCollisionMipLevel);O->SetBoolField(TEXT("nanite"),L->IsNaniteEnabled());O->SetBoolField(TEXT("native_layers_up_to_date"),L->IsUpToDate());O->SetNumberField(TEXT("edit_layer_count"),L->GetEditLayersConst().Num());O->SetBoolField(TEXT("render_available"),FApp::CanEverRender());O->SetNumberField(TEXT("native_frame"),double(GFrameCounter));O->SetBoolField(TEXT("asset_or_map_saved_by_native_operation"),false);O->SetBoolField(TEXT("art_gameplay_or_FPS_qualified"),false);O->SetNumberField(TEXT("width"),Side);O->SetNumberField(TEXT("height"),Side);O->SetNumberField(TEXT("subsection_size_quads"),L->SubsectionSizeQuads);O->SetNumberField(TEXT("num_subsections"),L->NumSubsections);O->SetNumberField(TEXT("component_size_quads"),L->ComponentSizeQuads);
    TArray<TSharedPtr<FJsonValue>> Layers;for(const ULandscapeEditLayerBase* Layer:L->GetEditLayersConst()){auto E=MakeShared<FJsonObject>();if(Layer){E->SetStringField(TEXT("class"),Layer->GetClass()->GetPathName());E->SetStringField(TEXT("object_name"),Layer->GetFName().ToString());E->SetStringField(TEXT("guid"),Layer->GetGuid().ToString());}Layers.Add(MakeShared<FJsonValueObject>(E));}O->SetArrayField(TEXT("edit_layers"),Layers);if(Ctx.bExplicitSource){O->SetStringField(TEXT("source_context"),TEXT("explicit_ConnectorA_v001"));O->SetStringField(TEXT("source_config_relative_path"),Ctx.ConfigPath);O->SetStringField(TEXT("source_height_relative_path"),Ctx.HeightPath);O->SetStringField(TEXT("caller_expected_config_sha256"),Ctx.ExpectedConfigHash);}return O;
}

TSharedRef<FJsonObject> TextureReference(UTexture* Texture)
{
    auto O=MakeShared<FJsonObject>();O->SetBoolField(TEXT("valid"),IsValid(Texture));
    if(!IsValid(Texture))return O;
    O->SetStringField(TEXT("path"),Texture->GetPathName());O->SetStringField(TEXT("class"),Texture->GetClass()->GetPathName());O->SetStringField(TEXT("package"),Texture->GetOutermost()->GetName());
    UTexture2D* T=Cast<UTexture2D>(Texture);O->SetBoolField(TEXT("texture2d"),T!=nullptr);
    if(T)
    {
        // Editor source metadata, not a platform/RHI/resident-mip observation.
        const bool HasSource=T->Source.IsValid();O->SetBoolField(TEXT("source_valid"),HasSource);
        if(HasSource){O->SetNumberField(TEXT("source_width"),T->Source.GetSizeX());O->SetNumberField(TEXT("source_height"),T->Source.GetSizeY());O->SetNumberField(TEXT("source_mips"),T->Source.GetNumMips());O->SetNumberField(TEXT("source_format"),int32(T->Source.GetFormat()));}
        O->SetBoolField(TEXT("srgb"),T->SRGB);O->SetBoolField(TEXT("compression_none"),T->CompressionNone);O->SetNumberField(TEXT("compression_settings"),int32(T->CompressionSettings));O->SetNumberField(TEXT("lod_bias"),T->LODBias);O->SetBoolField(TEXT("virtual_texture_streaming"),T->VirtualTextureStreaming);O->SetBoolField(TEXT("never_stream"),T->NeverStream);O->SetNumberField(TEXT("address_x"),int32(T->AddressX));O->SetNumberField(TEXT("address_y"),int32(T->AddressY));O->SetNumberField(TEXT("mip_gen_settings"),int32(T->MipGenSettings));
    }
    return O;
}
TSharedRef<FJsonObject> RendererTextureReferences(ALandscape* L)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("schema"),TEXT("LivingTown.ReserveLandscapeRendererTextures.v1"));
    O->SetStringField(TEXT("API_scope"),TEXT("Final VF GetHeightmap(false); exported desktop GetMaterialInstanceCount/GetMaterialInstance(true); same current-quality GetUsedTextures overload as MaterialEditingLibrary. References, not per-pixel sampling or platform residency."));
    const auto Quality=GetCurrentMaterialQualityLevelChecked();O->SetNumberField(TEXT("quality_level"),int32(Quality));O->SetNumberField(TEXT("feature_level"),int32(L->GetWorld()->GetFeatureLevel()));O->SetBoolField(TEXT("dynamic_material_instances_enabled"),L->bUseDynamicMaterialInstance);
    const bool Desktop=L->GetWorld()->GetFeatureLevel()>ERHIFeatureLevel::ES3_1;O->SetBoolField(TEXT("desktop_material_instances"),Desktop);
    bool Complete=Desktop;TMap<FString,UTexture*> Unique;TArray<TSharedPtr<FJsonValue>> Components;
    for(ULandscapeComponent* C:L->LandscapeComponents)
    {
        auto Row=MakeShared<FJsonObject>();if(!C){Complete=false;Row->SetBoolField(TEXT("valid"),false);Components.Add(MakeShared<FJsonValueObject>(Row));continue;}
        Row->SetBoolField(TEXT("valid"),true);Row->SetStringField(TEXT("component"),C->GetPathName());
        UTexture2D* Height=C->GetHeightmap(false);Row->SetObjectField(TEXT("final_heightmap"),TextureReference(Height));if(Height)Unique.Add(Height->GetPathName(),Height);else Complete=false;
        // On the qualified desktop SM6 world this selects the same arrays as
        // GetCurrentRuntimeMaterialInterface, without calling its non-exported symbol.
        const int32 Count=C->GetMaterialInstanceCount(true);Row->SetNumberField(TEXT("material_interface_count"),Count);TArray<TSharedPtr<FJsonValue>> Materials;
        if(Count<=0||Count>64)Complete=false;
        else for(int32 Index=0;Index<Count;++Index)
        {
            auto M=MakeShared<FJsonObject>();M->SetNumberField(TEXT("index"),Index);UMaterialInstance* Interface=C->GetMaterialInstance(Index,true);M->SetBoolField(TEXT("valid"),IsValid(Interface));
            TArray<TSharedPtr<FJsonValue>> Paths;
            if(IsValid(Interface))
            {
                M->SetStringField(TEXT("path"),Interface->GetPathName());M->SetStringField(TEXT("class"),Interface->GetClass()->GetPathName());M->SetStringField(TEXT("package"),Interface->GetOutermost()->GetName());UMaterial* BaseMaterial=Interface->GetMaterial();M->SetStringField(TEXT("base_material"),BaseMaterial?BaseMaterial->GetPathName():TEXT(""));TArray<UTexture*> Textures;
                // Do not use the deprecated five-argument overload: in5.8 it is an empty final stub.
                Interface->GetUsedTextures(Textures,Quality);TArray<FString> Names;
                for(UTexture* Texture:Textures){if(!IsValid(Texture)){Complete=false;continue;}Names.AddUnique(Texture->GetPathName());Unique.Add(Texture->GetPathName(),Texture);}Names.Sort();for(const FString& Name:Names)Paths.Add(MakeShared<FJsonValueString>(Name));
            }
            else Complete=false;
            M->SetArrayField(TEXT("used_texture_paths"),Paths);Materials.Add(MakeShared<FJsonValueObject>(M));
        }
        Row->SetArrayField(TEXT("material_interfaces"),Materials);Components.Add(MakeShared<FJsonValueObject>(Row));
    }
    TArray<FString> Names;Unique.GetKeys(Names);Names.Sort();TArray<TSharedPtr<FJsonValue>> Paths,Textures;
    for(const FString& Name:Names){Paths.Add(MakeShared<FJsonValueString>(Name));Textures.Add(MakeShared<FJsonValueObject>(TextureReference(Unique.FindChecked(Name))));}
    O->SetArrayField(TEXT("components"),Components);O->SetArrayField(TEXT("textures"),Textures);O->SetArrayField(TEXT("renderer_texture_paths"),Paths);O->SetBoolField(TEXT("complete"),Complete&&Components.Num()==16);O->SetBoolField(TEXT("platform_or_resident_mip_readiness_claimed"),false);return O;
}

FString ReserveLandscapeCreateContext(const FReserveLandscapeReplayContext& Ctx,UWorld* World,const FSource& Source)
{
    for(TActorIterator<ALandscapeProxy> It(World);It;++It)return ErrorReply(TEXT("existing_landscape_refused_no_overwrite"));
    UMaterial* Material=LoadObject<UMaterial>(nullptr,*Ctx.Material);
    if(!Material||Material->GetPathName()!=Ctx.Material||Material->MaterialDomain!=MD_Surface||Material->GetBlendMode()!=BLEND_Opaque)return ErrorReply(TEXT("owned_new_opaque_photo_material_required"));
    if(GetDefault<ALandscape>()->IsNaniteEnabled())return ErrorReply(TEXT("native_landscape_default_nanite_must_be_off"));
    if(Ctx.bExplicitSource){FString Error;if(ReserveLandscapeConnectorAppliedInThisProcess||!ReserveLandscapeSourceCustody(Ctx,Source,Error))return ErrorReply(Error.IsEmpty()?TEXT("explicit_connector_create_once_required"):Error);ReserveLandscapeConnectorAppliedInThisProcess=true;}
    ALandscape* L=World->SpawnActor<ALandscape>(Ctx.Origin,FRotator::ZeroRotator);
    if(!L)return ErrorReply(TEXT("fresh_landscape_spawn_failed"));
    L->SetActorLabel(Ctx.ActorLabel);L->SetActorScale3D(Ctx.Scale);L->LandscapeMaterial=Material;L->CollisionMipLevel=0;L->SimpleCollisionMipLevel=0;L->BodyInstance.SetCollisionProfileName(FName(TEXT("BlockAll")));
    TMap<FGuid,TArray<uint16>> HeightPerLayer;HeightPerLayer.Add(FGuid(),Source.Heights);
    TMap<FGuid,TArray<FLandscapeImportLayerInfo>> WeightPerLayer;WeightPerLayer.Add(FGuid(),TArray<FLandscapeImportLayerInfo>());
    // This is the installed5.8 stock import shape. It creates the default edit
    // layer after components register; no obsolete non-edit-layer toggle.
    const FString HeightPath=FPaths::Combine(FPaths::ProjectDir(),Ctx.HeightPath);
    L->Import(FGuid::NewGuid(),0,0,Side-1,Side-1,Subsections,Quads,HeightPerLayer,*HeightPath,WeightPerLayer,ELandscapeImportAlphamapType::Additive,TArrayView<const FLandscapeLayer>());
    auto O=Receipt(Ctx,Source,L);O->SetStringField(TEXT("status"),TEXT("IMPORTED_PENDING_NATIVE_MERGED_HEIGHT_READBACK"));return Json(O);
}

FString ReserveLandscapeReadContext(const FReserveLandscapeReplayContext& Ctx,UWorld* World,const FSource& Source)
{
    ALandscape* L=nullptr;int32 Count=0;
    for(TActorIterator<ALandscapeProxy> It(World);It;++It){++Count;L=Cast<ALandscape>(*It);}
    if(Count!=1||!L||L->GetActorLabel()!=Ctx.ActorLabel)return ErrorReply(TEXT("exact_one_owned_landscape_required"));
    auto O=Receipt(Ctx,Source,L);
    auto Reject=[&](const TCHAR* Why){O->SetStringField(TEXT("status"),TEXT("ERROR"));O->SetStringField(TEXT("error"),Why);return Json(O);};
    if(!L->GetActorLocation().Equals(Ctx.Origin,0.)||!L->GetActorScale3D().Equals(Ctx.Scale,0.)||!L->GetActorRotation().Equals(FRotator::ZeroRotator,0.)||!L->LandscapeMaterial||L->LandscapeMaterial->GetPathName()!=Ctx.Material||L->IsNaniteEnabled()||L->CollisionMipLevel!=0||L->SimpleCollisionMipLevel!=0)return Reject(TEXT("owned_transform_material_or_policy_changed"));
    ULandscapeInfo* Info=L->GetLandscapeInfo();
    if(!Info||!L->IsUpToDate()){O->SetStringField(TEXT("status"),TEXT("PENDING_NATIVE_EDIT_LAYER_MERGE"));return Json(O);}
    int32 X1=0,Y1=0,X2=0,Y2=0;if(!Info->GetLandscapeExtent(X1,Y1,X2,Y2)||X1!=0||Y1!=0||X2!=Side-1||Y2!=Side-1)return Reject(TEXT("exact_native_sample_extent"));
    O->SetArrayField(TEXT("sample_extent_xy_inclusive"),{MakeShared<FJsonValueNumber>(X1),MakeShared<FJsonValueNumber>(Y1),MakeShared<FJsonValueNumber>(X2),MakeShared<FJsonValueNumber>(Y2)});
    TArray<TSharedPtr<FJsonValue>> Components;TSet<FIntPoint> Bases;bool Registered=true;
    for(ULandscapeComponent* C:L->LandscapeComponents)
    {
        if(!C)return Reject(TEXT("missing_landscape_component"));const FIntPoint Base=C->GetSectionBase();
        if(Bases.Contains(Base)||Base.X<0||Base.Y<0||Base.X>=504||Base.Y>=504||Base.X%126||Base.Y%126||C->ComponentSizeQuads!=126||C->SubsectionSizeQuads!=63||C->NumSubsections!=2)return Reject(TEXT("exact_native_component_grid"));
        Bases.Add(Base);Registered&=C->IsRegistered();auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("path"),C->GetPathName());R->SetNumberField(TEXT("base_x"),Base.X);R->SetNumberField(TEXT("base_y"),Base.Y);R->SetBoolField(TEXT("registered"),C->IsRegistered());Components.Add(MakeShared<FJsonValueObject>(R));
    }
    FBox RenderBounds(ForceInit);for(ULandscapeComponent* C:L->LandscapeComponents)RenderBounds+=C->Bounds.GetBox();O->SetArrayField(TEXT("render_bounds_min_cm"),Vector(RenderBounds.Min));O->SetArrayField(TEXT("render_bounds_max_cm"),Vector(RenderBounds.Max));O->SetArrayField(TEXT("components"),Components);
    TArray<TSharedPtr<FJsonValue>> Collisions;bool PhysicsReady=true;
    for(ULandscapeHeightfieldCollisionComponent* C:L->CollisionComponents)
    {
        if(!C)return Reject(TEXT("missing_collision_component"));auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("path"),C->GetPathName());R->SetBoolField(TEXT("registered"),C->IsRegistered());R->SetBoolField(TEXT("physics_state_created"),C->IsPhysicsStateCreated());R->SetNumberField(TEXT("collision_enabled"),int32(C->GetCollisionEnabled()));PhysicsReady&=C->IsRegistered()&&C->IsPhysicsStateCreated()&&C->GetCollisionEnabled()==ECollisionEnabled::QueryAndPhysics;Collisions.Add(MakeShared<FJsonValueObject>(R));
    }
    O->SetArrayField(TEXT("collisions"),Collisions);
    if(Bases.Num()!=16||L->CollisionComponents.Num()!=16||!Registered||!PhysicsReady||L->GetEditLayersConst().IsEmpty()){O->SetStringField(TEXT("status"),TEXT("PENDING_COMPONENT_OR_COLLISION_READINESS"));return Json(O);}
    const bool DirtyBefore=L->GetOutermost()->IsDirty();TArray<uint16> Merged;Merged.SetNumZeroed(Side*Side);
    {FLandscapeEditDataInterface Data(Info,FGuid(),false);Data.SetShouldDirtyPackage(false);Data.GetHeightDataFast(0,0,Side-1,Side-1,Merged.GetData(),0);}
    TArray<uint8> Encoded;Encoded.SetNumUninitialized(SourceBytes);int32 Mismatches=0,First=-1;uint16 Min=65535,Max=0;
    for(int32 I=0;I<Merged.Num();++I){const uint16 V=Merged[I];Encoded[I*2]=uint8(V&255);Encoded[I*2+1]=uint8(V>>8);Min=FMath::Min(Min,V);Max=FMath::Max(Max,V);if(V!=Source.Heights[I]){if(First<0)First=I;++Mismatches;}}
    FString MergedSha;if(!LivingTownTiles::HashBytes(Encoded,MergedSha))return Reject(TEXT("merged_height_sha256_unavailable"));
    O->SetStringField(TEXT("merged_height_sha256"),MergedSha);O->SetNumberField(TEXT("height_mismatch_count"),Mismatches);O->SetNumberField(TEXT("first_height_mismatch_index"),First);O->SetNumberField(TEXT("height_uint16_min"),Min);O->SetNumberField(TEXT("height_uint16_max"),Max);O->SetBoolField(TEXT("package_dirty_before_read"),DirtyBefore);O->SetBoolField(TEXT("package_dirty_after_read"),L->GetOutermost()->IsDirty());
    if(L->GetOutermost()->IsDirty()!=DirtyBefore)return Reject(TEXT("readback_changed_package_dirty_state"));
    if(Mismatches||MergedSha!=Source.HeightSha)return Reject(TEXT("merged_height_source_encoding_differs"));
    O->SetObjectField(TEXT("renderer_texture_provenance"),RendererTextureReferences(L));
    if(L->GetOutermost()->IsDirty()!=DirtyBefore)return Reject(TEXT("renderer_reference_read_changed_package_dirty_state"));
    const FString Relative=FString::Printf(TEXT("%s/MergedHeight505_frame%llu.r16"),*Ctx.DumpRoot,static_cast<unsigned long long>(GFrameCounter));
    const FString Destination=FPaths::Combine(FPaths::ProjectDir(),Relative);IFileManager::Get().MakeDirectory(*FPaths::GetPath(Destination),true);
    if(IFileManager::Get().FileExists(*Destination)){TArray<uint8> Previous;if(!FFileHelper::LoadFileToArray(Previous,*Destination)||Previous!=Encoded)return Reject(TEXT("no_readback_overwrite"));}
    else if(!FFileHelper::SaveArrayToFile(Encoded,*Destination,&IFileManager::Get(),FILEWRITE_NoReplaceExisting))return Reject(TEXT("merged_readback_file_write"));
    auto File=MakeShared<FJsonObject>();File->SetStringField(TEXT("project_relative_path"),Relative);File->SetStringField(TEXT("encoding"),TEXT("uint16_le"));File->SetNumberField(TEXT("bytes"),SourceBytes);File->SetStringField(TEXT("sha256"),MergedSha);O->SetObjectField(TEXT("merged_height_file"),File);O->SetBoolField(TEXT("all_source_uint16_samples_exact"),true);O->SetStringField(TEXT("status"),TEXT("READY_NATIVE_LANDSCAPE_SOURCE_HEIGHT_COMPONENTS_AND_COLLISION"));return Json(O);
}

FString ReserveLandscapeRunContext(const FReserveLandscapeReplayContext& Ctx,bool Create)
{
    UWorld* World=nullptr;FString Error;FSource Source;if(!OwnedWorld(Ctx,World,Error)||!LoadSource(Ctx,Source,Error))return ErrorReply(Error);
    const FString Reply=Create?ReserveLandscapeCreateContext(Ctx,World,Source):ReserveLandscapeReadContext(Ctx,World,Source);
    if(Ctx.bExplicitSource&&!ReserveLandscapeSourceCustody(Ctx,Source,Error)){auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("ERROR"));O->SetStringField(TEXT("error"),TEXT("explicit_source_changed_during_operation_partial_state_retained"));O->SetStringField(TEXT("source_config_sha256"),Source.ConfigSha);O->SetStringField(TEXT("prior_operation_reply"),Reply);return Json(O);}return Reply;
}
FString ReserveLandscapeInvokeConnector(bool Create)
{
    FReserveLandscapeReplayContext Ctx=ReserveLandscapeConnectorContext();if(!ReserveLandscapeUniqueConfigFlag(FCommandLine::Get(),TEXT("LivingTownReserveConnectorConfigSHA256"),Ctx.ExpectedConfigHash))return ErrorReply(TEXT("one_explicit_raw_config_SHA_flag_required_no_legacy_fallback"));
    FString Project=FPaths::ConvertRelativePathToFull(FPaths::ProjectDir());FPaths::NormalizeDirectoryName(Project);
    if(Create?!ReserveLandscapeConnectorAuthorIntent(Ctx,FCommandLine::Get(),Project,ReserveLandscapeConnectorAppliedInThisProcess):!(Project.EndsWith(TEXT("/Author/Project"))||Project.EndsWith(TEXT("/Review/Project"))))return ErrorReply(TEXT("explicit_connector_SHA_Author_intent_owned_project_once_required"));
    Ctx.DumpRoot+=TEXT("/");Ctx.DumpRoot+=Ctx.ExpectedConfigHash;return ReserveLandscapeRunContext(Ctx,Create);
}
}
FString ULivingTownReserveLandscape::CreateReserveLandscapePreview(){return ReserveLandscapeRunContext(ReserveLandscapeLegacyContext(),true);}
FString ULivingTownReserveLandscape::ReadReserveLandscapePreview(){return ReserveLandscapeRunContext(ReserveLandscapeLegacyContext(),false);}
FString ULivingTownReserveLandscape::CreateReserveConnectorLandscapePreview(){return ReserveLandscapeInvokeConnector(true);}
FString ULivingTownReserveLandscape::ReadReserveConnectorLandscapePreview(){return ReserveLandscapeInvokeConnector(false);}

FString ULivingTownReserveLandscape::ReadReserveHismComponent(UHierarchicalInstancedStaticMeshComponent* Component)
{
    if(!IsInGameThread()||!GEditor||GEditor->PlayWorld)return ErrorReply(TEXT("hism_read_requires_game_thread_editor_no_PIE"));
    if(!Component||Component->GetClass()!=UHierarchicalInstancedStaticMeshComponent::StaticClass())return ErrorReply(TEXT("hism_read_requires_exact_native_component_class"));
    const UHierarchicalInstancedStaticMeshComponent* C=Component;
    const bool CDO=C->HasAnyFlags(RF_ClassDefaultObject);
    UWorld* World=GEditor->GetEditorWorldContext().World();
    if(!World||World->WorldType!=EWorldType::Editor)return ErrorReply(TEXT("hism_read_requires_current_editor_world"));
    const AActor* Owner=C->GetOwner();
    if(!CDO)
    {
        bool OwnedLabel=false;
        if(Owner)for(int32 Index=0;Index<12;++Index)OwnedLabel|=Owner->GetActorLabel(false)==FString::Printf(TEXT("LT_RESERVE_DENSITY500_%02d"),Index);
        if(World->GetOutermost()->GetName()!=MapPath||!Owner||Owner->GetClass()!=AActor::StaticClass()||!OwnedLabel||Owner->GetWorld()!=World||C->GetWorld()!=World||Owner->GetLevel()!=World->GetCurrentLevel()||C->GetOuter()!=Owner||Owner->GetRootComponent()!=C)return ErrorReply(TEXT("hism_read_requires_fixed_map_owned_actor_root"));
    }
    const FIntProperty* Built=FindFProperty<FIntProperty>(C->GetClass(),TEXT("NumBuiltInstances"));
    const FIntProperty* RenderCount=FindFProperty<FIntProperty>(C->GetClass(),TEXT("InstanceCountToRender"));
    const FArrayProperty* Sorted=FindFProperty<FArrayProperty>(C->GetClass(),TEXT("SortedInstances"));
    const FIntProperty* SortedItem=Sorted?CastField<FIntProperty>(Sorted->Inner):nullptr;
    const FBoolProperty* Density=FindFProperty<FBoolProperty>(C->GetClass(),TEXT("bEnableDensityScaling"));
    const FBoolProperty* Translated=FindFProperty<FBoolProperty>(C->GetClass(),TEXT("bUseTranslatedInstanceSpace"));
    if(!Built||!RenderCount||!Sorted||!SortedItem||!Density||!Translated)return ErrorReply(TEXT("hism_read_exact_reflected_property_types_missing"));
    UPackage* Package=C->GetOutermost();UPackage* MapPackage=World->GetOutermost();
    if(!Package||!MapPackage)return ErrorReply(TEXT("hism_read_missing_package"));
    const bool DirtyBefore=Package->IsDirty(),MapDirtyBefore=MapPackage->IsDirty();
    FScriptArrayHelper Array(Sorted,Sorted->ContainerPtrToValuePtr<void>(C));
    if(Array.Num()<0||Array.Num()>500||C->GetInstanceCount()<0||C->GetInstanceCount()>500)return ErrorReply(TEXT("hism_read_bounded_component_instance_count"));
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("schema"),TEXT("LivingTown.ReserveHismComponentRead.v1"));
    O->SetStringField(TEXT("API_scope"),TEXT("GT Editor native public hierarchy/ownership getters and explicit typed read-only protected UPROPERTY snapshot; no rebuild/register/tick/flush/save; render buffer count is not visible leaf or GPU timing evidence"));
    O->SetStringField(TEXT("component"),C->GetPathName());O->SetStringField(TEXT("class"),C->GetClass()->GetPathName());O->SetBoolField(TEXT("class_default_object"),CDO);O->SetStringField(TEXT("world"),World->GetPathName());O->SetNumberField(TEXT("engine_frame"),double(GFrameCounter));
    O->SetNumberField(TEXT("NumBuiltInstances"),Built->GetPropertyValue_InContainer(C));O->SetNumberField(TEXT("InstanceCountToRender"),RenderCount->GetPropertyValue_InContainer(C));
    O->SetBoolField(TEXT("bEnableDensityScaling"),Density->GetPropertyValue_InContainer(C));O->SetBoolField(TEXT("bUseTranslatedInstanceSpace"),Translated->GetPropertyValue_InContainer(C));
    TArray<TSharedPtr<FJsonValue>> Values;for(int32 Index=0;Index<Array.Num();++Index)Values.Add(MakeShared<FJsonValueNumber>(SortedItem->GetPropertyValue(Array.GetRawPtr(Index))));O->SetArrayField(TEXT("SortedInstances"),Values);
    O->SetNumberField(TEXT("instance_count"),C->GetInstanceCount());O->SetNumberField(TEXT("render_instance_count"),C->GetNumRenderInstances());O->SetBoolField(TEXT("registered"),C->IsRegistered());O->SetBoolField(TEXT("async_building"),C->IsAsyncBuilding());O->SetBoolField(TEXT("tree_fully_built"),C->IsTreeFullyBuilt());
    O->SetNumberField(TEXT("creation_method_value"),int32(C->CreationMethod));O->SetStringField(TEXT("creation_method_name"),StaticEnum<EComponentCreationMethod>()->GetNameStringByValue(int64(C->CreationMethod)));
    O->SetStringField(TEXT("owner"),Owner?Owner->GetPathName():FString());O->SetStringField(TEXT("outer"),C->GetOuter()?C->GetOuter()->GetPathName():FString());O->SetBoolField(TEXT("owner_root_is_component"),Owner&&Owner->GetRootComponent()==C);
    TArray<TSharedPtr<FJsonValue>> Membership;bool ExactMember=false;
    if(Owner){const TArray<UActorComponent*>& Components=Owner->GetInstanceComponents();ExactMember=Components.Num()==1&&Components[0]==C;for(const UActorComponent* Entry:Components)Membership.Add(MakeShared<FJsonValueString>(Entry?Entry->GetPathName():FString()));}
    O->SetArrayField(TEXT("owner_instance_components"),Membership);O->SetBoolField(TEXT("exact_single_actor_instance_member"),ExactMember);O->SetBoolField(TEXT("creation_method_is_instance"),C->CreationMethod==EComponentCreationMethod::Instance);
    O->SetStringField(TEXT("package"),Package->GetPathName());O->SetBoolField(TEXT("package_dirty_before"),DirtyBefore);O->SetBoolField(TEXT("package_dirty_after"),Package->IsDirty());O->SetBoolField(TEXT("map_package_dirty_before"),MapDirtyBefore);O->SetBoolField(TEXT("map_package_dirty_after"),MapPackage->IsDirty());
    if(Package->IsDirty()!=DirtyBefore||MapPackage->IsDirty()!=MapDirtyBefore)return ErrorReply(TEXT("hism_read_changed_package_dirty_state"));
    O->SetStringField(TEXT("status"),TEXT("READ_ONLY_NATIVE_HISM_COMPONENT_SNAPSHOT"));return Json(O);
}

#if WITH_DEV_AUTOMATION_TESTS
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FReserveLandscapeSourceContextBoundary,"LivingTown.ReserveLandscape.SourceContextBoundary",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FReserveLandscapeSourceContextBoundary::RunTest(const FString&)
{
    const FReserveLandscapeReplayContext Legacy=ReserveLandscapeLegacyContext();FSource Old,New;FString Error;
    if(!TestTrue(TEXT("Legacy loader still reads exact original staged source"),LoadSource(Legacy,Old,Error))){AddError(Error);return false;}
    TestTrue(TEXT("Legacy factory retains all original fixed paths identities transform dump and no explicit flag"),!Legacy.bExplicitSource&&Legacy.ConfigPath==ConfigRelative&&Legacy.HeightPath==HeightRelative&&Legacy.Map==MapPath&&Legacy.Material==MaterialPath&&Legacy.ActorLabel==Label&&Legacy.Origin.Equals(RequiredOrigin,0.)&&Legacy.Scale.Equals(RequiredScale,0.)&&Legacy.DumpRoot==TEXT("Saved/ReserveLandscape_v001"));
    TestEqual(TEXT("Legacy original2b SHA remains exact"),Old.HeightSha,FString(TEXT("2b5839619c03277cc4e73bb97e0d250661e9aec1efe5efe61850e5c16170b5cb")));
    FReserveLandscapeReplayContext Ctx=ReserveLandscapeConnectorContext();TArray<uint8> ConfigRaw;
    if(!TestTrue(TEXT("Actual new fixed config file exists"),FFileHelper::LoadFileToArray(ConfigRaw,*FPaths::Combine(FPaths::ProjectDir(),Ctx.ConfigPath)))||!TestTrue(TEXT("Actual raw config has SHA"),LivingTownTiles::HashBytes(ConfigRaw,Ctx.ExpectedConfigHash)))return false;
    if(!TestTrue(TEXT("Same shared loader reads explicit9184 source and config SHA"),LoadSource(Ctx,New,Error))){AddError(Error);return false;}
    TestEqual(TEXT("Connector actual9184 SHA"),New.HeightSha,FString(TEXT("9184ca30385056c1c7b551a5e05a7c1c75daa82a10e19662ce3787a0b51ea145")));
    TestTrue(TEXT("Context changes only explicit namespace identity keeps same material origin and scale"),Ctx.bExplicitSource&&Ctx.Map!=Legacy.Map&&Ctx.HeightPath!=Legacy.HeightPath&&Ctx.ConfigPath!=Legacy.ConfigPath&&Ctx.ActorLabel!=Legacy.ActorLabel&&Ctx.Material==Legacy.Material&&Ctx.Origin.Equals(Legacy.Origin,0.)&&Ctx.Scale.Equals(Legacy.Scale,0.));
    TestEqual(TEXT("Original full505 source samples"),Old.Heights.Num(),255025);TestEqual(TEXT("New full505 source samples"),New.Heights.Num(),255025);int32 Changed=0;
    if(Old.Heights.Num()==New.Heights.Num())for(int32 I=0;I<Old.Heights.Num();++I)Changed+=Old.Heights[I]!=New.Heights[I]?1:0;
    TestEqual(TEXT("Only actual59 source samples differ"),Changed,59);TestTrue(TEXT("Explicit source raw bytes held for custody"),New.HeightBytes.Num()==SourceBytes&&New.ConfigBytes==ConfigRaw);TestTrue(TEXT("Actual explicit source custody passes without mutation"),ReserveLandscapeSourceCustody(Ctx,New,Error));
    FSource Refused;FReserveLandscapeReplayContext Bad=Ctx;Bad.ExpectedConfigHash=FString::ChrN(64,TEXT('0'));TestFalse(TEXT("Wrong raw config SHA refused before authority"),LoadSource(Bad,Refused,Error));
    Bad=Ctx;Bad.Map=Legacy.Map;TestFalse(TEXT("Foreign map context refused by same config parser"),LoadSource(Bad,Refused,Error));Bad=Ctx;Bad.Origin.X+=1.;TestFalse(TEXT("Wrong origin context refused"),LoadSource(Bad,Refused,Error));Bad=Ctx;Bad.Material=TEXT("/Game/Foreign/M.M");TestFalse(TEXT("Foreign material context refused"),LoadSource(Bad,Refused,Error));Bad=Ctx;Bad.HeightPath=Legacy.HeightPath;TestFalse(TEXT("Old RAW path cannot satisfy new context config"),LoadSource(Bad,Refused,Error));
    TArray<uint8> Altered=New.HeightBytes;Altered[0]^=1;TestFalse(TEXT("Actual RAW one-bit tamper cannot retain9184 SHA"),ReserveLandscapeDecodeHeights(Altered,New.HeightSha,Refused,Error));Altered=New.HeightBytes;Altered.Pop(EAllowShrinking::No);TestFalse(TEXT("Truncated RAW refused before decode"),ReserveLandscapeDecodeHeights(Altered,New.HeightSha,Refused,Error));TestFalse(TEXT("New RAW cannot claim old2b digest"),ReserveLandscapeDecodeHeights(New.HeightBytes,Old.HeightSha,Refused,Error));
    FSource ChangedCustody=New;ChangedCustody.HeightBytes[0]^=1;TestFalse(TEXT("Held RAW change refused without writing source"),ReserveLandscapeSourceCustody(Ctx,ChangedCustody,Error));ChangedCustody=New;ChangedCustody.ConfigBytes[0]^=1;TestFalse(TEXT("Held config change refused without writing source"),ReserveLandscapeSourceCustody(Ctx,ChangedCustody,Error));
    const FString ConfigFlag=FString(TEXT("-LivingTownReserveConnectorConfigSHA256="))+Ctx.ExpectedConfigHash,AuthorFlag=FString(TEXT(" -LivingTownReserveConnectorAuthor="))+Ctx.ExpectedConfigHash,Owned=TEXT("/Owned/Author/Project");
    TestTrue(TEXT("Exact config and Author flags authorize actual shared predicate"),ReserveLandscapeConnectorAuthorIntent(Ctx,*(ConfigFlag+AuthorFlag),Owned,false));TestFalse(TEXT("Missing Author intent refused"),ReserveLandscapeConnectorAuthorIntent(Ctx,*ConfigFlag,Owned,false));TestFalse(TEXT("Different RAW SHA is not config Author intent"),ReserveLandscapeConnectorAuthorIntent(Ctx,*(ConfigFlag+TEXT(" -LivingTownReserveConnectorAuthor=")+New.HeightSha),Owned,false));TestFalse(TEXT("Already applied cannot mutate twice"),ReserveLandscapeConnectorAuthorIntent(Ctx,*(ConfigFlag+AuthorFlag),Owned,true));TestFalse(TEXT("Foreign project cannot mutate"),ReserveLandscapeConnectorAuthorIntent(Ctx,*(ConfigFlag+AuthorFlag),TEXT("/Ordinary/Project"),false));TestFalse(TEXT("Source-only phase cannot mutate Author assets"),ReserveLandscapeConnectorAuthorIntent(Ctx,*(ConfigFlag+AuthorFlag),TEXT("/Owned/Source/Project"),false));TestFalse(TEXT("Duplicate config flags refused"),ReserveLandscapeConnectorAuthorIntent(Ctx,*(ConfigFlag+TEXT(" ")+ConfigFlag+AuthorFlag),Owned,false));TestFalse(TEXT("Duplicate Author flags refused"),ReserveLandscapeConnectorAuthorIntent(Ctx,*(ConfigFlag+AuthorFlag+AuthorFlag),Owned,false));TestFalse(TEXT("Legacy context cannot opt into new Source intent"),ReserveLandscapeConnectorAuthorIntent(Legacy,*(ConfigFlag+AuthorFlag),Owned,false));
    FString Parsed;TestFalse(TEXT("Malformed prefix flag refused"),ReserveLandscapeUniqueConfigFlag(*(FString(TEXT("-LivingTownReserveConnectorConfigSHA256Extra="))+Ctx.ExpectedConfigHash),TEXT("LivingTownReserveConnectorConfigSHA256"),Parsed));TestFalse(TEXT("Malformed SHA refused"),ReserveLandscapeUniqueConfigFlag(TEXT("-LivingTownReserveConnectorConfigSHA256=wrong"),TEXT("LivingTownReserveConnectorConfigSHA256"),Parsed));
    return true;
}
#endif
