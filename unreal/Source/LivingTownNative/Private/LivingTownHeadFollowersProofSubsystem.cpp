#include "LivingTownHeadFollowersProofSubsystem.h"
#include "LivingTownCurrent61HeadAssembly.h"
#include "LivingTownCafeBinding.h"
#include "UObject/Package.h"
#include "LivingTownTileData.h"
#include "Animation/AnimSequence.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Camera/CameraComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/ExternalMorphSet.h"
#include "Components/DirectionalLightComponent.h"
#include "Components/ExponentialHeightFogComponent.h"
#include "Engine/Engine.h"
#include "Engine/GameViewportClient.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/World.h"
#include "Materials/Material.h"
#include "RHIShaderPlatform.h"
#include "GameFramework/Actor.h"
#include "GameFramework/PlayerController.h"
#include "Rendering/SkeletalMeshRenderData.h"
#include "Rendering/SkinWeightVertexBuffer.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformMisc.h"
#include "UnrealClient.h"
#include <initializer_list>

namespace HeadFollowersProof
{
constexpr const TCHAR* BodyPath=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedDefault_v001/SK_Worker110Current61_BakedREST_v001.SK_Worker110Current61_BakedREST_v001");
constexpr const TCHAR* IdlePath=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMotion_v001/A_Worker110_BakedIdle_v001.A_Worker110_BakedIdle_v001");
constexpr const TCHAR* WalkPath=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMotion_v001/A_Worker110_BakedWalk_v001.A_Worker110_BakedWalk_v001");
constexpr const TCHAR* HairMesh=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/HairFineTwoMap_v001/SK_Worker110HairFineTwoMap_v001.SK_Worker110HairFineTwoMap_v001");
constexpr const TCHAR* HairMaterial=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/HairFineTwoMap_v001/M_Worker110HairFineTwoMap_DefaultLit_v001.M_Worker110HairFineTwoMap_DefaultLit_v001");
constexpr const TCHAR* CapMesh=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/HairUnderlayer_v002/SK_Worker110HairUnderlayer_v002.SK_Worker110HairUnderlayer_v002");
constexpr const TCHAR* CapMaterial=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/HairUnderlayer_v002/M_Worker110HairUnderlayerEdge_v002.M_Worker110HairUnderlayerEdge_v002");
bool Hash(const FString& H)
{
    if(H.Len()!=64||H==FString::ChrN(64,'0'))return false;
    for(TCHAR C:H)if(!((C>='0'&&C<='9')||(C>='a'&&C<='f')))return false;
    return true;
}
const TArray<FName>& BodyImportedSlots()
{
    static const TArray<FName> Names={FName(TEXT("LT_Complete_ApprovedHM08Skin_NoScan_001_1")),FName(TEXT("LT_Complete_ApprovedHM08Skin_NoScan_001_2")),FName(TEXT("LT_Complete_brows_001_0")),FName(TEXT("LT_Complete_eyes_001_0")),FName(TEXT("LT_Complete_garment_001_0")),FName(TEXT("LT_Complete_pants_001_0")),FName(TEXT("LT_Complete_shoes_001_0")),FName(TEXT("LT_Private_CrossbackDrapeApron_REST_0"))};return Names;
}
TSharedRef<FJsonObject> BodyMaterialBindings(const USkeletalMeshComponent* C)
{
    auto J=MakeShared<FJsonObject>();const USkeletalMesh* Mesh=C?C->GetSkeletalMeshAsset():nullptr;
    J->SetStringField(TEXT("mesh"),Mesh?Mesh->GetPathName():TEXT("NONE"));J->SetBoolField(TEXT("mesh_package_dirty"),Mesh?Mesh->GetOutermost()->IsDirty():true);
    J->SetNumberField(TEXT("component_material_count"),C?C->GetNumMaterials():0);TArray<TSharedPtr<FJsonValue>> Rows;
    if(Mesh&&C)for(int32 I=0;I<Mesh->GetMaterials().Num();++I)
    {
        const auto& Slot=Mesh->GetMaterials()[I];auto* Actual=C->GetMaterial(I);auto* Material=Cast<UMaterial>(Actual);auto Row=MakeShared<FJsonObject>();
        Row->SetNumberField(TEXT("index"),I);Row->SetStringField(TEXT("imported_slot_name"),Slot.ImportedMaterialSlotName.ToString());Row->SetBoolField(TEXT("serialized_material_none"),Slot.MaterialInterface==nullptr);
        Row->SetStringField(TEXT("material"),Actual?Actual->GetPathName():TEXT("NONE"));Row->SetStringField(TEXT("class"),Actual?Actual->GetClass()->GetPathName():TEXT("NONE"));
        Row->SetBoolField(TEXT("component_material_null"),Actual==nullptr);Row->SetBoolField(TEXT("engine_material_path"),Actual&&Actual->GetPathName().StartsWith(TEXT("/Engine/")));
        Row->SetBoolField(TEXT("skeletal_usage"),Material&&Material->GetUsageByFlag(MATUSAGE_SkeletalMesh));Rows.Add(MakeShared<FJsonValueObject>(Row));
    }
    J->SetArrayField(TEXT("slots"),Rows);return J;
}
void LogBodyMaterialBindings(const USkeletalMeshComponent* C,const TCHAR* Stage)
{
    FString Text;FJsonSerializer::Serialize(BodyMaterialBindings(C),TJsonWriterFactory<>::Create(&Text));
    UE_LOG(LogTemp,Display,TEXT("LIVING_TOWN_HEAD_FOLLOWERS_BODY_BINDINGS stage=%s actual=%s"),Stage,*Text);
}
TSharedRef<FJsonObject> TRS(const FTransform& T)
{
    auto O=MakeShared<FJsonObject>();const FVector P=T.GetTranslation(),S=T.GetScale3D();const FQuat Q=T.GetRotation();
    auto A=[](std::initializer_list<double> V){TArray<TSharedPtr<FJsonValue>> R;for(double X:V)R.Add(MakeShared<FJsonValueNumber>(X));return R;};
    O->SetArrayField(TEXT("translation_cm"),A({P.X,P.Y,P.Z}));O->SetArrayField(TEXT("rotation_xyzw"),A({Q.X,Q.Y,Q.Z,Q.W}));O->SetArrayField(TEXT("scale"),A({S.X,S.Y,S.Z}));return O;
}
TArray<TSharedPtr<FJsonValue>> Vec(const FVector3f& P)
{
    return {MakeShared<FJsonValueNumber>(P.X),MakeShared<FJsonValueNumber>(P.Y),MakeShared<FJsonValueNumber>(P.Z)};
}
TArray<TSharedPtr<FJsonValue>> Mat(const FMatrix44f& M)
{
    TArray<TSharedPtr<FJsonValue>> V;for(int32 I=0;I<4;++I)for(int32 J=0;J<4;++J)V.Add(MakeShared<FJsonValueNumber>(M.M[I][J]));return V;
}
bool Vertices(const TSharedPtr<FJsonObject>& J,const TCHAR* Key,TArray<int32>& Out)
{
    const TArray<TSharedPtr<FJsonValue>>* A=nullptr;if(!J->TryGetArrayField(Key,A)||A->Num()<1||A->Num()>32)return false;
    for(const auto& V:*A){double N=V->AsNumber();if(!FMath::IsFinite(N)||N<0||N>250000||N!=FMath::FloorToDouble(N)||Out.Contains(int32(N)))return false;Out.Add(int32(N));}return true;
}
bool MorphsEmpty(const USkeletalMeshComponent* C)
{
    if(!C->ActiveMorphTargets.IsEmpty()||!C->GetMorphTargetCurves().IsEmpty())return false;
    for(float W:C->MorphTargetWeights)if(!FMath::IsFinite(W)||W!=0.f)return false;
    for(const auto& M:C->ExternalMorphSets)if(!M.IsEmpty())return false;
    for(const auto& M:C->ExternalMorphWeightData)if(!M.MorphSets.IsEmpty()||M.NumActiveMorphTargets)return false;
    return true;
}
}

bool ULivingTownHeadFollowersProofSubsystem::DoesSupportWorldType(EWorldType::Type Type) const{return Type==EWorldType::Game;}
bool ULivingTownHeadFollowersProofSubsystem::ShouldCreateSubsystem(UObject* Outer) const
{
#if UE_BUILD_SHIPPING || UE_BUILD_TEST
    return false;
#else
    return !IsRunningCommandlet()&&FParse::Param(FCommandLine::Get(),TEXT("LivingTownHeadFollowersProof"))&&Super::ShouldCreateSubsystem(Outer);
#endif
}
void ULivingTownHeadFollowersProofSubsystem::OnWorldBeginPlay(UWorld& World)
{
    Super::OnWorldBeginPlay(World);
    UE_LOG(LogTemp,Display,TEXT("LIVING_TOWN_HEAD_FOLLOWERS_STAGE stage=OnWorldBeginPlay game_thread=%d editor=%d commandlet=%d world_type=%d world=%s"),IsInGameThread()?1:0,GIsEditor?1:0,IsRunningCommandlet()?1:0,int32(World.WorldType),*World.GetPathName());
    if(!IsInGameThread()||GIsEditor||IsRunningCommandlet()||World.WorldType!=EWorldType::Game){Finish(TEXT("game_context_refused"),false);return;}
    Started=FPlatformTime::Seconds();
    PostTick=FWorldDelegates::OnWorldPostActorTick.AddUObject(this,&ThisClass::Observe);
    ShotComplete=FScreenshotRequest::OnScreenshotRequestProcessed().AddUObject(this,&ThisClass::ShotProcessed);
}
bool ULivingTownHeadFollowersProofSubsystem::Setup()
{
    using namespace HeadFollowersProof;
    const auto Refuse=[this](const TCHAR* Stage){UE_LOG(LogTemp,Error,TEXT("LIVING_TOWN_HEAD_FOLLOWERS_REFUSED stage=%s root=%s owned_output=%d"),Stage,*Root,bOwnedOutput?1:0);return false;};
    Root=FPlatformMisc::GetEnvironmentVariable(TEXT("LT_HEAD_FOLLOWERS_PROOF_ROOT"));FPaths::NormalizeDirectoryName(Root);
    // IsDrive accepts a bare drive (D:), not a drive plus separator (D:/).
    if(Root.Len()<3||Root[2]!=TEXT('/')||!FPaths::IsDrive(Root.Left(2)))return Refuse(TEXT("Setup.absolute_drive_root"));
    FString Sha;if(!FParse::Value(FCommandLine::Get(),TEXT("LivingTownHeadFollowersProofSHA="),Sha)||!Hash(Sha))return Refuse(TEXT("Setup.manifest_SHA_argument"));
    FString Project=FPaths::ConvertRelativePathToFull(FPaths::ProjectDir());
    FString ExpectedProject=FPaths::ConvertRelativePathToFull(FPaths::Combine(Root,TEXT("Project")));
    FPaths::NormalizeDirectoryName(Project);FPaths::NormalizeDirectoryName(ExpectedProject);
    UE_LOG(LogTemp,Display,TEXT("LIVING_TOWN_HEAD_FOLLOWERS_STAGE stage=Setup.project_directory actual=%s expected=%s root=%s"),*Project,*ExpectedProject,*Root);
    if(!FPaths::IsSamePath(Project,ExpectedProject))return Refuse(TEXT("Setup.exact_project_directory"));
    bOwnedOutput=IFileManager::Get().DirectoryExists(*Root);for(const TCHAR* Leaf:{TEXT("HEAD_FOLLOWERS_CAPTURE.json"),TEXT("Idle.png"),TEXT("Walk.png")})bOwnedOutput&=!IFileManager::Get().FileExists(*FPaths::Combine(Root,Leaf));if(!bOwnedOutput)return Refuse(TEXT("Setup.owned_output_fresh"));
    FString Text;TArray<uint8> Bytes;const FString File=FPaths::Combine(Root,TEXT("Input/HeadFollowers.json"));
    if(!FFileHelper::LoadFileToArray(Bytes,*File)||Bytes.IsEmpty()||Bytes.Num()>65536||!LivingTownTiles::HashBytes(Bytes,ManifestHash)||ManifestHash!=Sha||!FFileHelper::LoadFileToString(Text,*File))return Refuse(TEXT("Setup.manifest_bytes_hash"));
    if(!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),Config)||!Config.IsValid()||Config->GetStringField(TEXT("schema"))!=TEXT("LivingTown.HeadFollowersOwnedGameProof.v1")||Config->GetBoolField(TEXT("bound_actual_Fine009_independent_cold"))!=true||!Hash(Config->GetStringField(TEXT("head_qualification_sha256"))))return Refuse(TEXT("Setup.manifest_schema_FineCold"));
    bDiagnosticArtPreview=FParse::Param(FCommandLine::Get(),TEXT("LivingTownHeadFollowersArtPreview"));
    bCapColdBound=Config->GetBoolField(TEXT("bound_actual_cap_author_and_independent_cold"));
    FString ProofMode;Config->TryGetStringField(TEXT("proof_mode"),ProofMode);
    if(bDiagnosticArtPreview)
    {
        bool bCapAuthorBound=false;Config->TryGetBoolField(TEXT("bound_actual_cap_author_data"),bCapAuthorBound);
        // An author-only preview never asserts independent raw Cold completion.
        if(bCapColdBound||!bCapAuthorBound||ProofMode!=TEXT("DIAGNOSTIC_ART_PREVIEW"))return Refuse(TEXT("Setup.preview_author_mode"));
    }
    else if(!bCapColdBound||ProofMode==TEXT("DIAGNOSTIC_ART_PREVIEW"))return Refuse(TEXT("Setup.qualified_Cold_mode"));
    if(!Vertices(Config,TEXT("hair_render_vertices"),HairVertices)||!Vertices(Config,TEXT("cap_render_vertices"),CapVertices))return Refuse(TEXT("Setup.render_vertex_witnesses"));
    FLivingTownCurrent61HeadBinding Binding;Binding.QualificationSha256=Config->GetStringField(TEXT("head_qualification_sha256"));Binding.bReadQualifiedDescriptor=true;
    const auto& Names=Config->GetArrayField(TEXT("source_joint_names"));if(Names.Num()!=61)return Refuse(TEXT("Setup.source_joint_names_61"));for(const auto& N:Names)Binding.SourceJointNames.Add(FName(N->AsString()));
    const auto& Parts=Config->GetArrayField(TEXT("parts"));if(Parts.Num()!=2)return Refuse(TEXT("Setup.parts_count_2"));
    for(int32 I=0;I<2;++I){const auto J=Parts[I]->AsObject();if(!J)return Refuse(TEXT("Setup.part_object"));FLivingTownCurrent61HeadPart P;P.Role=I==0?ELivingTownHeadPartRole::HairCards:ELivingTownHeadPartRole::Underlayer;P.ShadingModel=ELivingTownHeadShadingModel::DefaultLit;P.MeshPath=J->GetStringField(TEXT("mesh"));P.MaterialPath=J->GetStringField(TEXT("material"));P.RenderTriangles=J->GetIntegerField(TEXT("triangles"));P.UVChannels=J->GetIntegerField(TEXT("UV_channels"));Binding.Parts.Add(P);}
    if(!Binding.IsValidated()||Binding.Parts[0].MeshPath!=HairMesh||Binding.Parts[0].MaterialPath!=HairMaterial||Binding.Parts[1].MeshPath!=CapMesh||Binding.Parts[1].MaterialPath!=CapMaterial)return Refuse(TEXT("Setup.validated_exact_head_binding"));
    USkeletalMesh* M=LoadObject<USkeletalMesh>(nullptr,BodyPath);Idle=LoadObject<UAnimSequence>(nullptr,IdlePath);Walk=LoadObject<UAnimSequence>(nullptr,WalkPath);
    if(!M||!Idle||!Walk||Idle->GetSkeleton()!=M->GetSkeleton()||Walk->GetSkeleton()!=M->GetSkeleton()||Idle->GetPlayLength()<=0||Walk->GetPlayLength()<=0)return Refuse(TEXT("Setup.body_clips_skeleton"));
    const auto& BodyPaths=LivingTownCafeCurrent61Baked::MaterialAssets();const auto& BodySlots=BodyImportedSlots();
    const TArray<TSharedPtr<FJsonValue>>* DeclaredBodyPaths=nullptr;
    if(BodyPaths.Num()!=8||M->GetMaterials().Num()!=8||!Config->TryGetArrayField(TEXT("body_materials"),DeclaredBodyPaths)||DeclaredBodyPaths->Num()!=8)return Refuse(TEXT("Setup.exact_body8_scope"));
    TArray<UMaterial*> BodyMaterials;
    for(int32 I=0;I<8;++I)
    {
        const auto& Slot=M->GetMaterials()[I];
        if(Slot.MaterialInterface||Slot.ImportedMaterialSlotName!=BodySlots[I]||Slot.MaterialSlotName!=BodySlots[I]||(*DeclaredBodyPaths)[I]->AsString()!=BodyPaths[I])return Refuse(TEXT("Setup.body8_readonly_defaults_and_order"));
        auto* Material=LoadObject<UMaterial>(nullptr,*BodyPaths[I]);
        if(!Material||Material->GetClass()!=UMaterial::StaticClass()||Material->GetPathName()!=BodyPaths[I]||!Material->GetUsageByFlag(MATUSAGE_SkeletalMesh))return Refuse(TEXT("Setup.body8_saved_skeletal_material"));
        BodyMaterials.Add(Material);
    }
    FActorSpawnParameters Spawn;Spawn.ObjectFlags=RF_Transient;Owner=GetWorld()->SpawnActor<AActor>(AActor::StaticClass(),FTransform::Identity,Spawn);if(!Owner)return Refuse(TEXT("Setup.owned_actor_spawn"));
    auto Make=[&](const TCHAR* Name){auto* C=NewObject<USkeletalMeshComponent>(Owner,Name,RF_Transient);Owner->AddInstanceComponent(C);C->SetCollisionEnabled(ECollisionEnabled::NoCollision);C->SetGenerateOverlapEvents(false);C->VisibilityBasedAnimTickOption=EVisibilityBasedAnimTickOption::AlwaysTickPoseAndRefreshBones;return C;};
    Body=Make(TEXT("ProofBody"));Hair=Make(TEXT("ProofHair"));Cap=Make(TEXT("ProofCap"));Owner->SetRootComponent(Body);Body->SetSkeletalMeshAsset(M);Body->RegisterComponent();Hair->RegisterComponent();Cap->RegisterComponent();FString Error;
    LogBodyMaterialBindings(Body,TEXT("BEFORE_COMPONENT_OVERRIDES"));
    for(int32 I=0;I<8;++I)Body->SetMaterial(I,BodyMaterials[I]);
    LogBodyMaterialBindings(Body,TEXT("AFTER_COMPONENT_OVERRIDES"));
    for(int32 I=0;I<8;++I)if(Body->GetMaterial(I)!=BodyMaterials[I]||M->GetMaterials()[I].MaterialInterface||M->GetOutermost()->IsDirty())return Refuse(TEXT("Setup.body8_actual_component_binding"));
    if(!LivingTownCurrent61HeadAssembly::Configure(Body,Hair,Cap,Binding,Error))return Refuse(TEXT("Setup.production_Configure"));bConfigured=true;
    Camera=NewObject<UCameraComponent>(Owner,TEXT("ProofCamera"),RF_Transient);Owner->AddInstanceComponent(Camera);Camera->RegisterComponent();Camera->SetWorldLocation(FVector(230,-310,175));Camera->SetWorldRotation((FVector(0,0,150)-Camera->GetComponentLocation()).Rotation());Camera->SetFieldOfView(35.f);
    auto& PP=Camera->PostProcessSettings;Camera->PostProcessBlendWeight=1.f;PP.bOverride_AutoExposureMethod=true;PP.AutoExposureMethod=AEM_Manual;PP.bOverride_AutoExposureApplyPhysicalCameraExposure=true;PP.AutoExposureApplyPhysicalCameraExposure=true;PP.bOverride_CameraISO=true;PP.CameraISO=100.f;PP.bOverride_CameraShutterSpeed=true;PP.CameraShutterSpeed=4.f;PP.bOverride_DepthOfFieldFstop=true;PP.DepthOfFieldFstop=8.f;PP.bOverride_AutoExposureBias=true;PP.AutoExposureBias=0.f;PP.bOverride_AutoExposureBiasCurve=true;PP.AutoExposureBiasCurve=nullptr;PP.bOverride_MotionBlurAmount=true;PP.MotionBlurAmount=0.f;
    if(!GEngine||!GEngine->GameViewport)return Refuse(TEXT("Setup.game_viewport"));GEngine->GameViewport->EngineShowFlags.SetDepthOfField(false);GEngine->GameViewport->EngineShowFlags.SetMotionBlur(false);
    auto* Light=NewObject<UDirectionalLightComponent>(Owner,TEXT("ProofKey"),RF_Transient);Owner->AddInstanceComponent(Light);Light->SetMobility(EComponentMobility::Movable);Light->RegisterComponent();Light->SetWorldRotation(FRotator(-35,-35,0));Light->SetIntensity(1000.f);Light->SetLightColor(FLinearColor::White);
    auto* Fill=NewObject<UDirectionalLightComponent>(Owner,TEXT("ProofFill"),RF_Transient);Owner->AddInstanceComponent(Fill);Fill->SetMobility(EComponentMobility::Movable);Fill->RegisterComponent();Fill->SetWorldRotation(FRotator(-15,145,0));Fill->SetIntensity(250.f);Fill->SetLightColor(FLinearColor::White);Fill->SetCastShadows(false);
    auto* Fog=NewObject<UExponentialHeightFogComponent>(Owner,TEXT("ProofNeutralBackdrop"),RF_Transient);Owner->AddInstanceComponent(Fog);Fog->RegisterComponent();Fog->SetFogDensity(.02f);Fog->SetFogHeightFalloff(.001f);Fog->SetFogMaxOpacity(1.f);Fog->SetStartDistance(1000.f);Fog->SetFogInscatteringColor(FLinearColor(64.f,64.f,64.f,1.f));
    if(auto* PC=GetWorld()->GetFirstPlayerController())PC->SetViewTarget(Owner);else return Refuse(TEXT("Setup.first_player_controller"));
    Body->SetAnimationMode(EAnimationMode::AnimationSingleNode);return true;
}
bool ULivingTownHeadFollowersProofSubsystem::OwnScreenMaterialsReady() const
{
    // Public nonblocking screen prerequisite, not a substitute for the separate
    // native117 saved-material complete/resolved Cold qualification. IsComplete
    // alone permits absent resources, so also reject the absent current map.
    for(const auto* C:{Body.Get(),Hair.Get(),Cap.Get()})
    {
        if(!C)return false;
        for(int32 I=0;I<C->GetNumMaterials();++I)
        {
            auto* M=Cast<UMaterial>(C->GetMaterial(I));
            if(!M||M->GetClass()!=UMaterial::StaticClass()||M->IsCompilingOrHadCompileError(GMaxRHIShaderPlatform)||M->IsCompiling()||!M->IsComplete())return false;
        }
    }
    return true;
}
TSharedPtr<FJsonObject> ULivingTownHeadFollowersProofSubsystem::Sample()
{
    using namespace HeadFollowersProof;
    if(!Body||!Hair||!Cap||Body->IsRunningParallelEvaluation()||Hair->IsRunningParallelEvaluation()||Cap->IsRunningParallelEvaluation())return nullptr;
    auto* Player=Body->GetSingleNodeInstance();if(!Player||Body->GetAnimationMode()!=EAnimationMode::AnimationSingleNode||Player->GetCurrentAsset()!=(Phase==0?Idle.Get():Walk.Get())||Player->GetPlayRate()!=1.f||!Player->IsPlaying()||!Player->IsLooping()||Hair->GetAnimInstance()||Cap->GetAnimInstance())return nullptr;
    const uint32 Revision=Body->GetBoneTransformRevisionNumber();const float ClipTime=Player->GetCurrentTime();const auto& LeaderRef=Body->GetSkeletalMeshAsset()->GetRefSkeleton();const auto& BonePose=Body->GetComponentSpaceTransforms();if(BonePose.Num()!=LeaderRef.GetNum())return nullptr;
    auto O=MakeShared<FJsonObject>();O->SetObjectField(TEXT("body_material_bindings"),BodyMaterialBindings(Body));O->SetNumberField(TEXT("frame"),double(GFrameCounter));O->SetNumberField(TEXT("world_seconds"),GetWorld()->GetTimeSeconds());O->SetNumberField(TEXT("clip_time"),Player->GetCurrentTime());O->SetNumberField(TEXT("clip_length"),Player->GetCurrentAsset()->GetPlayLength());O->SetNumberField(TEXT("play_rate"),Player->GetPlayRate());O->SetBoolField(TEXT("playing"),Player->IsPlaying());O->SetBoolField(TEXT("looping"),Player->IsLooping());O->SetNumberField(TEXT("body_revision"),Body->GetBoneTransformRevisionNumber());O->SetStringField(TEXT("clip"),Player->GetCurrentAsset()->GetPathName());O->SetObjectField(TEXT("body_world"),TRS(Body->GetComponentTransform()));O->SetObjectField(TEXT("camera_world"),TRS(Camera->GetComponentTransform()));O->SetNumberField(TEXT("camera_manual_EV100"),FMath::Log2(FMath::Square(Camera->PostProcessSettings.DepthOfFieldFstop)*Camera->PostProcessSettings.CameraShutterSpeed*100.f/Camera->PostProcessSettings.CameraISO));O->SetBoolField(TEXT("camera_manual_physical_exposure"),Camera->PostProcessSettings.AutoExposureMethod==AEM_Manual&&Camera->PostProcessSettings.AutoExposureApplyPhysicalCameraExposure);O->SetNumberField(TEXT("camera_exposure_bias"),Camera->PostProcessSettings.AutoExposureBias);TArray<TSharedPtr<FJsonValue>> Followers;
    for(int32 Part=0;Part<2;++Part)
    {
        auto* C=Part==0?Hair.Get():Cap.Get();const auto& Selected=Part==0?HairVertices:CapVertices;auto* M=C->GetSkeletalMeshAsset();
#if WITH_EDITOR
        if(M&&M->IsCompiling())return nullptr;
#endif
        const auto* Render=M?M->GetResourceForRendering():nullptr;
        if(!C->IsRegistered()||!C->IsVisible()||C->GetAttachParent()!=Body||!C->GetRelativeTransform().Equals(FTransform::Identity,0)||C->LeaderPoseComponent.Get()!=Body||C->GetRefPoseOverride().IsValid()||C->IsSimulatingPhysics()||C->GetCollisionEnabled()!=ECollisionEnabled::NoCollision||!MorphsEmpty(C)||!Render||Render->LODRenderData.Num()!=1)return nullptr;
        const auto& Ref=M->GetRefSkeleton();const auto& Map=C->GetLeaderBoneMap();const auto& LOD=Render->LODRenderData[0];auto* Skin=C->GetSkinWeightBuffer(0);if(!Skin||Skin!=&LOD.SkinWeightVertexBuffer||Map.Num()!=Ref.GetNum()||M->GetRefBasesInvMatrix().Num()!=Ref.GetNum()||!LOD.StaticVertexBuffers.PositionVertexBuffer.GetVertexData()||Skin->GetMaxBoneInfluences()>12||Skin->GetNumVertices()!=LOD.GetNumVertices())return nullptr;
        const auto* Data=Skin->GetDataVertexBuffer();const auto* Lookup=Skin->GetLookupVertexBuffer();if(!Data||!Lookup||!Data->GetWeightData()||Data->GetVertexDataSize()==0||(!Lookup->GetLookupData()&&Lookup->GetVertexDataSize())||(Skin->GetVariableBonesPerVertex()&&(!Lookup->GetLookupData()||Lookup->GetNumVertices()!=LOD.GetNumVertices())))return nullptr;
        auto P=MakeShared<FJsonObject>();P->SetStringField(TEXT("role"),Part==0?TEXT("hair"):TEXT("cap"));P->SetStringField(TEXT("mesh"),M->GetPathName());P->SetObjectField(TEXT("world"),TRS(C->GetComponentTransform()));P->SetNumberField(TEXT("revision"),C->GetBoneTransformRevisionNumber());TArray<TSharedPtr<FJsonValue>> Bones,Points;
        for(int32 B=0;B<Map.Num();++B){if(!BonePose.IsValidIndex(Map[B])||LeaderRef.GetBoneName(Map[B])!=Ref.GetBoneName(B)||!BonePose[Map[B]].IsValid())return nullptr;auto J=MakeShared<FJsonObject>();J->SetStringField(TEXT("name"),Ref.GetBoneName(B).ToString());J->SetNumberField(TEXT("part_index"),B);J->SetNumberField(TEXT("leader_index"),Map[B]);J->SetObjectField(TEXT("body_component_pose"),TRS(BonePose[Map[B]]));J->SetObjectField(TEXT("follower_world_pose"),TRS(C->GetBoneTransform(B)));J->SetObjectField(TEXT("body_world_pose"),TRS(Body->GetBoneTransform(Map[B])));Bones.Add(MakeShared<FJsonValueObject>(J));}
        for(int32 V:Selected)
        {
            if(V<0||V>=int32(LOD.GetNumVertices()))return nullptr;uint32 Offset=0,InfluencesCount=0;Skin->GetVertexInfluenceOffsetCount(V,Offset,InfluencesCount);if(InfluencesCount>12||uint64(Offset)+uint64(InfluencesCount)*Skin->GetBoneIndexAndWeightByteSize()>Data->GetVertexDataSize())return nullptr;int32 Section=INDEX_NONE,Local=INDEX_NONE;LOD.GetSectionFromVertexIndex(V,Section,Local);if(!LOD.RenderSections.IsValidIndex(Section))return nullptr;const auto& Sec=LOD.RenderSections[Section];const FVector3f Position=LOD.StaticVertexBuffers.PositionVertexBuffer.VertexPosition(V);const FVector3f Skinned=USkinnedMeshComponent::GetSkinnedVertexPosition(C,V,LOD,*Skin);if(Position.ContainsNaN()||Skinned.ContainsNaN())return nullptr;
            auto J=MakeShared<FJsonObject>();J->SetNumberField(TEXT("render_vertex"),V);J->SetArrayField(TEXT("bind_position_cm"),Vec(Position));J->SetArrayField(TEXT("observed_component_skinned_cm"),Vec(Skinned));TArray<TSharedPtr<FJsonValue>> Influences;
            for(uint32 K=0;K<InfluencesCount;++K){const uint16 Weight=Skin->GetBoneWeight(V,K);if(!Weight)continue;const uint32 Slot=Skin->GetBoneIndex(V,K);if(!Sec.BoneMap.IsValidIndex(Slot))return nullptr;const int32 B=Sec.BoneMap[Slot];if(!Map.IsValidIndex(B)||!BonePose.IsValidIndex(Map[B]))return nullptr;auto I=MakeShared<FJsonObject>();I->SetNumberField(TEXT("weight_u16"),Weight);I->SetNumberField(TEXT("part_bone"),B);I->SetNumberField(TEXT("leader_bone"),Map[B]);I->SetArrayField(TEXT("part_inverse_bind_f32"),Mat(M->GetRefBasesInvMatrix()[B]));I->SetArrayField(TEXT("body_component_matrix_f32"),Mat(FMatrix44f(BonePose[Map[B]].ToMatrixWithScale())));Influences.Add(MakeShared<FJsonValueObject>(I));}
            J->SetArrayField(TEXT("influences"),Influences);Points.Add(MakeShared<FJsonValueObject>(J));
        }
        P->SetArrayField(TEXT("all_name_resolved_bones"),Bones);P->SetArrayField(TEXT("selected_skin"),Points);Followers.Add(MakeShared<FJsonValueObject>(P));
    }
    if(!MorphsEmpty(Body)||Body->GetBoneTransformRevisionNumber()!=Revision||Player->GetCurrentTime()!=ClipTime||Body->IsRunningParallelEvaluation())return nullptr;O->SetArrayField(TEXT("followers"),Followers);O->SetBoolField(TEXT("parallel_evaluation_idle_and_readonly_getter"),true);O->SetBoolField(TEXT("body_revision_and_time_unchanged_during_observation"),true);return O;
}
void ULivingTownHeadFollowersProofSubsystem::Observe(UWorld* World,ELevelTick,float)
{
    if(bTerminal||World!=GetWorld())return;
    if(!bConfigured)
    {
        if(FPlatformTime::Seconds()-Started>900){Finish(TEXT("finite900s_initial_world_readiness"),false);return;}
        if(!World->HasBegunPlay()||!World->GetFirstPlayerController()||!GEngine||!GEngine->GameViewport)return;
        // Subsystem OnWorldBeginPlay precedes GameMode::StartPlay. Configure the
        // camera/actor once after the first complete natural actor tick instead.
        if(!Setup()){Finish(TEXT("setup_refused"),false);return;}
        Started=FPlatformTime::Seconds();return;
    }
    if(!bAnimationStarted)
    {
        if(FPlatformTime::Seconds()-Started>900){Finish(TEXT("finite900s_own_screen_material_prerequisite"),false);return;}
        if(!OwnScreenMaterialsReady())return;
        Body->PlayAnimation(Idle,true);bAnimationStarted=true;Started=FPlatformTime::Seconds();UE_LOG(LogTemp,Display,TEXT("LIVING_TOWN_HEAD_FOLLOWERS_NATURAL_GAME_READY"));return;
    }
    if(FPlatformTime::Seconds()-Started>120){Finish(TEXT("finite120s_animation_deadline"),false);return;}
    if(Phase>=2){++WaitFrames;if(Phase==2&&bShotProcessed&&WaitFrames>=4&&IFileManager::Get().FileSize(*FPaths::Combine(Root,TEXT("Idle.png")))>8){Phase=1;WaitFrames=0;Body->PlayAnimation(Walk,true);}else if(Phase==3&&bShotProcessed&&WaitFrames>=4&&IFileManager::Get().FileSize(*FPaths::Combine(Root,TEXT("Idle.png")))>8&&IFileManager::Get().FileSize(*FPaths::Combine(Root,TEXT("Walk.png")))>8)Finish(TEXT("captured_data_requires_CPU_and_visibleframe_review"),true);return;}
    if(GetWorld()->GetTimeSeconds()-LastSample<.1)return;auto O=Sample();if(!O)return;LastSample=GetWorld()->GetTimeSeconds();Samples.Add(MakeShared<FJsonValueObject>(O));if(++PhaseSamples<16)return;
    if(FScreenshotRequest::IsScreenshotRequested()){Finish(TEXT("unexpected_existing_screenshot_request"),false);return;}
    PendingShot=Phase;bShotProcessed=false;PendingShotRecord=MakeShared<FJsonObject>();PendingShotRecord->SetStringField(TEXT("file"),Phase==0?TEXT("Idle.png"):TEXT("Walk.png"));PendingShotRecord->SetStringField(TEXT("requested_clip"),Body->GetSingleNodeInstance()->GetCurrentAsset()->GetPathName());PendingShotRecord->SetNumberField(TEXT("request_frame"),double(GFrameCounter));PendingShotRecord->SetNumberField(TEXT("request_clip_time"),Body->GetSingleNodeInstance()->GetCurrentTime());
    FScreenshotRequest::RequestScreenshot(FPaths::Combine(Root,Phase==0?TEXT("Idle.png"):TEXT("Walk.png")),false,false,false,FIntRect(),true);
    PhaseSamples=0;Phase=Phase==0?2:3;WaitFrames=0;
}
void ULivingTownHeadFollowersProofSubsystem::ShotProcessed()
{
    if(bTerminal||PendingShot==INDEX_NONE)return;auto* Player=Body?Body->GetSingleNodeInstance():nullptr;
    if(!IsInGameThread()||!Player||!PendingShotRecord||Player->GetCurrentAsset()!=(PendingShot==0?Idle.Get():Walk.Get())){Finish(TEXT("screenshot_processed_with_wrong_actual_clip"),false);return;}
    PendingShotRecord->SetStringField(TEXT("processed_clip"),Player->GetCurrentAsset()->GetPathName());PendingShotRecord->SetNumberField(TEXT("processed_frame"),double(GFrameCounter));PendingShotRecord->SetNumberField(TEXT("processed_clip_time"),Player->GetCurrentTime());PendingShotRecord->SetBoolField(TEXT("stock_processed_callback_not_pixel_delegate"),true);Screenshots.Add(MakeShared<FJsonValueObject>(PendingShotRecord.ToSharedRef()));PendingShotRecord.Reset();PendingShot=INDEX_NONE;bShotProcessed=true;
}
void ULivingTownHeadFollowersProofSubsystem::Finish(const FString& Reason,bool bCaptured)
{
    if(bTerminal)return;bTerminal=true;
    // Always visible, including refusals before the owned output directory is admitted.
    UE_LOG(LogTemp,Display,TEXT("LIVING_TOWN_HEAD_FOLLOWERS_FINISH reason=%s captured=%d owned_output=%d configured=%d game_thread=%d editor=%d commandlet=%d root=%s"),*Reason,bCaptured?1:0,bOwnedOutput?1:0,bConfigured?1:0,IsInGameThread()?1:0,GIsEditor?1:0,IsRunningCommandlet()?1:0,*Root);
    auto J=MakeShared<FJsonObject>();J->SetObjectField(TEXT("body_material_bindings"),HeadFollowersProof::BodyMaterialBindings(Body));J->SetStringField(TEXT("schema"),TEXT("LivingTown.HeadFollowersOwnedGameCapture.v1"));J->SetStringField(TEXT("status"),bCaptured?(bDiagnosticArtPreview?TEXT("CAPTURED_DIAGNOSTIC_ART_PREVIEW_CAP_RAW_COLD_UNOBSERVED_IMAGES_REVIEW_PENDING"):TEXT("CAPTURED_NATURAL_TWO_FOLLOWER_DATA_CPU_IMAGES_REVIEW_PENDING")):TEXT("FAILED_PROBE_RETAINED"));J->SetBoolField(TEXT("diagnostic_art_preview"),bDiagnosticArtPreview);J->SetBoolField(TEXT("cap_independent_raw_cold_observed"),bCapColdBound);J->SetStringField(TEXT("cap_raw_cold_status"),bCapColdBound?TEXT("BOUND_INDEPENDENT_COLD_DATA"):TEXT("UNOBSERVED"));J->SetStringField(TEXT("reason"),Reason);J->SetStringField(TEXT("manifest_sha256"),ManifestHash);J->SetArrayField(TEXT("samples"),Samples);J->SetArrayField(TEXT("screenshots"),Screenshots);J->SetBoolField(TEXT("production_Configure_used"),bConfigured);J->SetBoolField(TEXT("forced_pose_tick_refresh_or_GetCPUSkinnedVertices_called"),false);FString Text;FJsonSerializer::Serialize(J,TJsonWriterFactory<>::Create(&Text));if(bOwnedOutput&&Text.Len()<(8<<20))FFileHelper::SaveStringToFile(Text,*FPaths::Combine(Root,TEXT("HEAD_FOLLOWERS_CAPTURE.json")));Cleanup();FPlatformMisc::RequestExitWithStatus(false,bCaptured?0:1,TEXT("LivingTownHeadFollowersOwnedProof"));
}
void ULivingTownHeadFollowersProofSubsystem::Cleanup()
{
    if(PostTick.IsValid()){FWorldDelegates::OnWorldPostActorTick.Remove(PostTick);PostTick.Reset();}if(ShotComplete.IsValid()){FScreenshotRequest::OnScreenshotRequestProcessed().Remove(ShotComplete);ShotComplete.Reset();}if(Owner){Owner->Destroy();Owner=nullptr;}
}
void ULivingTownHeadFollowersProofSubsystem::OnWorldEndPlay(UWorld& World){Cleanup();Super::OnWorldEndPlay(World);}
void ULivingTownHeadFollowersProofSubsystem::Deinitialize(){Cleanup();Super::Deinitialize();}
