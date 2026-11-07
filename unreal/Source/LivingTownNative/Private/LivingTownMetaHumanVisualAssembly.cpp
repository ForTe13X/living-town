#include "LivingTownMetaHumanVisualAssembly.h"
#include "LivingTownCafeBinding.h"
#include "LivingTownCafeCharacter.h"
#include "Animation/AnimSequence.h"
#include "Animation/AnimInstance.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Components/ChildActorComponent.h"
#include "Components/PrimitiveComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/AssetManager.h"
#include "Engine/BlueprintGeneratedClass.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/StreamableManager.h"
#include "Engine/World.h"
#include "GameFramework/Controller.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/Pawn.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformTime.h"
#include "Misc/CommandLine.h"
#include "Misc/FileHelper.h"
#include "Misc/Parse.h"
#include "Materials/MaterialInterface.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

namespace
{
bool Hash(const FString& S)
{
    if(S.Len()!=64 || S==FString::ChrN(64,TCHAR('0'))) return false;
    for(TCHAR C:S) if(!((C>='0'&&C<='9')||(C>='a'&&C<='f'))) return false;
    return true;
}
bool Number(const FJsonObject& O,const TCHAR* Key,double& V,double Min,double Max)
{
    const auto P=O.TryGetField(Key);
    return P&&P->Type==EJson::Number&&FMath::IsFinite(V=P->AsNumber())&&V>=Min&&V<=Max;
}
bool Vector(const TSharedPtr<FJsonValue>& P,FVector& V)
{
    if(!P||P->Type!=EJson::Array||P->AsArray().Num()!=3) return false;
    double N[3];
    for(int32 I=0;I<3;++I)
    { const auto& X=P->AsArray()[I];if(!X||X->Type!=EJson::Number||!FMath::IsFinite(N[I]=X->AsNumber())) return false; }
    V=FVector(N[0],N[1],N[2]);return true;
}
bool Transform(const TSharedPtr<FJsonValue>& P,FTransform& T)
{
    if(!P||P->Type!=EJson::Object) return false;
    const auto O=P->AsObject();if(!O||O->Values.Num()!=3) return false;
    FVector V,S;const auto Q=O->TryGetField(TEXT("rotation_xyzw"));
    if(!Vector(O->TryGetField(TEXT("translation_cm")),V)||!Vector(O->TryGetField(TEXT("scale")),S)||
       !Q||Q->Type!=EJson::Array||Q->AsArray().Num()!=4) return false;
    double N[4];
    for(int32 I=0;I<4;++I)
    { const auto& X=Q->AsArray()[I];if(!X||X->Type!=EJson::Number||!FMath::IsFinite(N[I]=X->AsNumber())) return false; }
    const FQuat R(N[0],N[1],N[2],N[3]);if(!FMath::IsNearlyEqual(R.SizeSquared(),1.,1.e-6)) return false;
    T=FTransform(R,V,S);return T.IsValid();
}
bool PreparedClass(const UClass* C)
{
    return C && C->GetPathName()==LivingTownMetaHumanVisual::ActorClass &&
        Cast<UBlueprintGeneratedClass>(C)!=nullptr && C->IsChildOf(AActor::StaticClass()) &&
        !C->IsChildOf(APawn::StaticClass()) && !C->IsChildOf(AController::StaticClass()) &&
        !C->HasAnyClassFlags(CLASS_Abstract|CLASS_Deprecated|CLASS_NewerVersionExists);
}
bool Clip(const UAnimSequence* A,const TCHAR* Path)
{
    return A && A->GetPathName()==Path && A->GetSkeleton() && A->GetPlayLength()>.5f &&
        A->GetNumberOfSampledKeys()>1 && A->RateScale==1.f && !A->IsValidAdditive() && !A->bEnableRootMotion;
}
bool Mesh(const USkeletalMeshComponent* C,const AActor* Owner,const TCHAR* Path)
{
    return IsValid(C)&&C->GetOwner()==Owner&&C->GetSkeletalMeshAsset()&&
        C->GetSkeletalMeshAsset()->GetPathName()==Path&&C->GetCollisionEnabled()==ECollisionEnabled::NoCollision&&C->IsVisible()&&!C->bHiddenInGame;
}
bool BodyPostProcess(const USkeletalMeshComponent* Body)
{
    const auto* Post=Body?Body->GetPostProcessInstance():nullptr;
    return IsValid(Post)&&Post->GetClass()->GetPathName()==LivingTownMetaHumanVisual::BodyPostProcessClass&&!Body->GetDisablePostProcessBlueprint();
}
bool WorkwearAsset(const USkeletalMesh* M,const UAnimSequence* Idle)
{
    if(!M||M->GetPathName()!=LivingTownMetaHumanVisual::WorkwearMesh||!Idle||M->GetSkeleton()!=Idle->GetSkeleton()||M->GetMaterials().Num()!=3) return false;
    static const TCHAR* Materials[]={
        TEXT("/Game/LivingTown_UEPilot/MetaHumanCasualWorkwear_v002/Materials/M_CottonTee.M_CottonTee"),
        TEXT("/Game/LivingTown_UEPilot/MetaHumanCasualWorkwear_v002/Materials/M_Jeans_Belt.M_Jeans_Belt"),
        TEXT("/Game/LivingTown_UEPilot/MetaHumanCasualWorkwear_v002/Materials/M_Shoes.M_Shoes")};
    for(int32 I=0;I<UE_ARRAY_COUNT(Materials);++I)
        if(!IsValid(M->GetMaterials()[I].MaterialInterface)||M->GetMaterials()[I].MaterialInterface->GetPathName()!=Materials[I]) return false;
    return true;
}
}

bool FLivingTownMetaHumanVisualBinding::IsValidated() const
{
    const FRotator R=ActorRelative.Rotator();const FVector T=ActorRelative.GetTranslation();
    const bool Outfit=(DescriptorVersion==1&&OutfitMeshPath.IsEmpty()&&OutfitManifestSha256.IsEmpty())||
        (DescriptorVersion==2&&OutfitMeshPath==LivingTownMetaHumanVisual::WorkwearMesh&&Hash(LivingTownMetaHumanVisual::WorkwearManifestSha256)&&
         OutfitManifestSha256==LivingTownMetaHumanVisual::WorkwearManifestSha256);
    return Outfit&&bReadPreparedDescriptor&&Hash(DescriptorSha256)&&Hash(SourceClosureSha256)&&
        CoreManifestSha256==LivingTownMetaHumanVisual::CoreManifestSha256&&
        ActorClassPath==LivingTownMetaHumanVisual::ActorClass&&IdleAnimationPath==LivingTownMetaHumanVisual::Idle&&
        WalkAnimationPath==LivingTownMetaHumanVisual::Walk&&HandBone==FName(TEXT("hand_r"))&&
        ActorRelative.IsValid()&&ActorRelative.GetScale3D()==FVector::OneVector&&
        FMath::Abs(R.Pitch)<1.e-6&&FMath::Abs(R.Roll)<1.e-6&&FMath::Abs(T.X)<=50&&FMath::Abs(T.Y)<=50&&T.Z>=-140&&T.Z<=20&&
        FMath::IsFinite(CapsuleRadiusCm)&&CapsuleRadiusCm>=10&&CapsuleRadiusCm<=40&&
        FMath::IsFinite(CapsuleHalfHeightCm)&&CapsuleHalfHeightCm>=70&&CapsuleHalfHeightCm<=110&&
        FMath::IsFinite(WalkSpeedCmPerSecond)&&WalkSpeedCmPerSecond>0&&WalkSpeedCmPerSecond<=250&&
        FMath::IsFinite(CameraArmCm)&&CameraArmCm>=100&&CameraArmCm<=600&&
        FMath::IsFinite(PreloadDeadlineSeconds)&&PreloadDeadlineSeconds>=1&&PreloadDeadlineSeconds<=120;
}
bool FLivingTownMetaHumanVisualBinding::Read(const FString& Path,FLivingTownMetaHumanVisualBinding& Out,FString& Error)
{
    Error.Reset();auto Fail=[&](const TCHAR* E){Error=E;return false;};
    const int64 Size=IFileManager::Get().FileSize(*Path);TArray<uint8> Bytes;
    if(Size<=0||Size>16*1024||!FFileHelper::LoadFileToArray(Bytes,*Path)) return Fail(TEXT("metahuman_prepared_descriptor_missing_or_oversize"));
    FString Text;FFileHelper::BufferToString(Text,Bytes.GetData(),Bytes.Num());TSharedPtr<FJsonObject> O;
    if(!LivingTownCafeJournal::HasUniqueObjectKeys(Text)||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),O)||!O)
        return Fail(TEXT("metahuman_prepared_descriptor_schema_required"));
    FLivingTownMetaHumanVisualBinding B;FString Format,Status,Hand;double Version=0;
    if(!Number(*O,TEXT("version"),Version,1,2)||(Version!=1&&Version!=2)||O->Values.Num()!=(Version==1?15:17))
        return Fail(TEXT("metahuman_prepared_descriptor_schema_required"));
    B.DescriptorVersion=int32(Version);
    if(B.UsesWorkwear()&&(!O->TryGetStringField(TEXT("outfit_mesh"),B.OutfitMeshPath)||!O->TryGetStringField(TEXT("outfit_manifest_sha256"),B.OutfitManifestSha256)))
        return Fail(TEXT("metahuman_prepared_workwear_descriptor_required"));
    if(!O->TryGetStringField(TEXT("format"),Format)||Format!=TEXT("LivingTown.MetaHumanBenActorPrepared")||
       !O->TryGetStringField(TEXT("status"),Status)||Status!=TEXT("CONTROLLED_GAME_TRIAL_PREPARED")||
       !O->TryGetStringField(TEXT("source_closure_sha256"),B.SourceClosureSha256)||!O->TryGetStringField(TEXT("core_manifest_sha256"),B.CoreManifestSha256)||
       !O->TryGetStringField(TEXT("actor_class"),B.ActorClassPath)||!O->TryGetStringField(TEXT("idle_animation"),B.IdleAnimationPath)||
       !O->TryGetStringField(TEXT("walk_animation"),B.WalkAnimationPath)||!O->TryGetStringField(TEXT("hand_bone"),Hand)||Hand.Len()>64||
       !Transform(O->TryGetField(TEXT("relative_transform")),B.ActorRelative)||
       !Number(*O,TEXT("capsule_radius_cm"),B.CapsuleRadiusCm,10,40)||!Number(*O,TEXT("capsule_half_height_cm"),B.CapsuleHalfHeightCm,70,110)||
       !Number(*O,TEXT("walk_speed_cm_s"),B.WalkSpeedCmPerSecond,.001,250)||!Number(*O,TEXT("camera_arm_cm"),B.CameraArmCm,100,600)||
       !Number(*O,TEXT("preload_deadline_seconds"),B.PreloadDeadlineSeconds,1,120)||!LivingTownCafeJournal::Sha256(Bytes,B.DescriptorSha256))
        return Fail(TEXT("metahuman_measured_prepared_actor_descriptor_required"));
    B.HandBone=FName(*Hand);B.bReadPreparedDescriptor=true;
    if(!B.IsValidated()) return Fail(TEXT("metahuman_prepared_actor_descriptor_invalid"));
    Out=MoveTemp(B);return true;
}
bool LivingTownMetaHumanVisual::ApplyCommandLineOptIn(FLivingTownCafeBinding& B,FString& Error)
{
    const TCHAR* Cursor=FCommandLine::Get();FString Token;int32 Count=0,OriginalCount=0;
    while(FParse::Token(Cursor,Token,false))
    {
        if(Token.Equals(TEXT("-LivingTownMetaHumanBen"),ESearchCase::IgnoreCase)||Token.StartsWith(TEXT("-LivingTownMetaHumanBen="),ESearchCase::IgnoreCase)) ++Count;
        if(Token.Equals(TEXT("-LivingTownOriginalWorkerBen"),ESearchCase::IgnoreCase)||Token.StartsWith(TEXT("-LivingTownOriginalWorkerBen="),ESearchCase::IgnoreCase)) ++OriginalCount;
    }
    if(!Count) return true;
    FString Path;
    if(Count!=1||OriginalCount||!FParse::Value(FCommandLine::Get(),TEXT("LivingTownMetaHumanBen="),Path)||Path.IsEmpty())
    {Error=TEXT("one_exclusive_metahuman_Ben_prepared_descriptor_required");return false;}
    FLivingTownMetaHumanVisualBinding Prepared;
    return FLivingTownMetaHumanVisualBinding::Read(Path,Prepared,Error)&&ApplyPreparedBinding(B,Prepared,Error);
}
bool LivingTownMetaHumanVisual::ApplyPreparedBinding(FLivingTownCafeBinding& B,const FLivingTownMetaHumanVisualBinding& D,FString& Error)
{
    Error.Reset();
    if(!D.IsValidated()||B.ResidentId!=TEXT("ben")||B.Current61Head.IsSet()||B.OriginalWorker.IsSet()||B.MetaHumanActor.IsSet())
    {Error=TEXT("exclusive_Ben_whole_actor_prepared_visual_required");return false;}
    B.MetaHumanActor=D;B.MotionStrategy=ELivingTownCafeMotionStrategy::MetaHumanWholeActor;
    B.VisualAssetPath=D.ActorClassPath;B.IdleWalkBlendSpacePath.Empty();B.IdleAnimationPath=D.IdleAnimationPath;B.WalkAnimationPath=D.WalkAnimationPath;
    B.UseSocket=D.HandBone.ToString();B.MeshRelativeTransform=D.ActorRelative;B.IdleRootDeltaCm=FVector::ZeroVector;
    B.CapsuleRadiusCm=float(D.CapsuleRadiusCm);B.CapsuleHalfHeightCm=float(D.CapsuleHalfHeightCm);B.WalkSpeedCmPerSecond=float(D.WalkSpeedCmPerSecond);B.CameraArmCm=float(D.CameraArmCm);
    B.VisualSha256=D.DescriptorSha256;return true;
}

ULivingTownMetaHumanVisualPreload::ULivingTownMetaHumanVisualPreload()
{ PrimaryComponentTick.bCanEverTick=true;PrimaryComponentTick.bStartWithTickEnabled=false;PrimaryComponentTick.bTickEvenWhenPaused=true; }
ELivingTownMetaHumanPreloadState ULivingTownMetaHumanVisualPreload::Request(const FLivingTownMetaHumanVisualBinding& B,FSimpleDelegate Completion,FString& Error)
{
    Error.Reset();
    if(!IsInGameThread()||!B.IsValidated()||!GetOwner()||!GetOwner()->IsA<AGameModeBase>()||!GetWorld()||!GetWorld()->IsGameWorld()||GetWorld()->bIsTearingDown||GetWorld()->GetNetMode()!=NM_Standalone)
    {Error=TEXT("metahuman_owned_standalone_preload_required");return ELivingTownMetaHumanPreloadState::Failed;}
    if(State!=ELivingTownMetaHumanPreloadState::Empty)
    {
        if(Requested.DescriptorSha256!=B.DescriptorSha256) {Error=TEXT("metahuman_preload_identity_changed_requires_explicit_reset");return ELivingTownMetaHumanPreloadState::Failed;}
        if(State==ELivingTownMetaHumanPreloadState::Failed) Error=Failure;
        return State;
    }
    Requested=B;OnCompletion=MoveTemp(Completion);RequestedAt=FPlatformTime::Seconds();State=ELivingTownMetaHumanPreloadState::Pending;
    SetComponentTickEnabled(true);const uint64 E=++Epoch;TWeakObjectPtr<ULivingTownMetaHumanVisualPreload> Weak(this);
    TArray<FSoftObjectPath> Paths{FSoftObjectPath(B.ActorClassPath),FSoftObjectPath(B.IdleAnimationPath),FSoftObjectPath(B.WalkAnimationPath)};
    if(B.UsesWorkwear()) Paths.Add(FSoftObjectPath(B.OutfitMeshPath));
    auto NewHandle=UAssetManager::GetStreamableManager().RequestAsyncLoad(Paths,FStreamableDelegate::CreateLambda([Weak,E]()
    {if(auto* Self=Weak.Get();Self&&Self->Epoch==E&&Self->State==ELivingTownMetaHumanPreloadState::Pending) Self->Complete(E);}));
    if(Epoch==E&&(State==ELivingTownMetaHumanPreloadState::Pending||State==ELivingTownMetaHumanPreloadState::Ready))
    {
        Handle=MoveTemp(NewHandle);
        if(!Handle.IsValid()) {Fail(TEXT("metahuman_async_preload_request_refused"));Error=Failure;}
    }
    else if(NewHandle)NewHandle->CancelHandle(); // a completion may have cancelled/replaced this request
    return State;
}
void ULivingTownMetaHumanVisualPreload::Complete(uint64 E)
{
    if(!IsInGameThread()||E!=Epoch||State!=ELivingTownMetaHumanPreloadState::Pending||!GetWorld()||GetWorld()->bIsTearingDown||!IsValid(GetOwner())) return;
    PreparedActorClass=Cast<UClass>(FSoftObjectPath(Requested.ActorClassPath).ResolveObject());
    Idle=Cast<UAnimSequence>(FSoftObjectPath(Requested.IdleAnimationPath).ResolveObject());Walk=Cast<UAnimSequence>(FSoftObjectPath(Requested.WalkAnimationPath).ResolveObject());
    Workwear=Requested.UsesWorkwear()?Cast<USkeletalMesh>(FSoftObjectPath(Requested.OutfitMeshPath).ResolveObject()):nullptr;
    if(!PreparedClass(PreparedActorClass)||!Clip(Idle,LivingTownMetaHumanVisual::Idle)||!Clip(Walk,LivingTownMetaHumanVisual::Walk)||Idle->GetSkeleton()!=Walk->GetSkeleton())
    {Fail(TEXT("metahuman_preloaded_exact_actor_and_compatible_clips_required"));return;}
    if(Requested.UsesWorkwear()&&!WorkwearAsset(Workwear,Idle))
    {Fail(TEXT("metahuman_preloaded_workwear_and_shared_skeleton_required"));return;}
    State=ELivingTownMetaHumanPreloadState::Ready;SetComponentTickEnabled(false);
    FSimpleDelegate CompleteCallback=MoveTemp(OnCompletion);CompleteCallback.ExecuteIfBound();
}
bool ULivingTownMetaHumanVisualPreload::IsReadyFor(const FLivingTownMetaHumanVisualBinding& B) const
{
    return IsInGameThread()&&IsValid(GetOwner())&&GetWorld()&&!GetWorld()->bIsTearingDown&&State==ELivingTownMetaHumanPreloadState::Ready&&B.IsValidated()&&Requested.DescriptorSha256==B.DescriptorSha256&&
        PreparedClass(PreparedActorClass)&&Clip(Idle,LivingTownMetaHumanVisual::Idle)&&Clip(Walk,LivingTownMetaHumanVisual::Walk)&&Idle->GetSkeleton()==Walk->GetSkeleton()&&
        (!B.UsesWorkwear()||WorkwearAsset(Workwear,Idle));
}
void ULivingTownMetaHumanVisualPreload::Fail(const TCHAR* Reason)
{
    ++Epoch;Failure=Reason;State=ELivingTownMetaHumanPreloadState::Failed;SetComponentTickEnabled(false);
    if(Handle) {Handle->CancelHandle();Handle.Reset();}
    PreparedActorClass=nullptr;Idle=nullptr;Walk=nullptr;Workwear=nullptr;
    FSimpleDelegate CompleteCallback=MoveTemp(OnCompletion);CompleteCallback.ExecuteIfBound();
}
void ULivingTownMetaHumanVisualPreload::TickComponent(float Delta,ELevelTick Type,FActorComponentTickFunction* Tick)
{
    Super::TickComponent(Delta,Type,Tick);
    if(State==ELivingTownMetaHumanPreloadState::Pending&&FPlatformTime::Seconds()-RequestedAt>Requested.PreloadDeadlineSeconds) Fail(TEXT("metahuman_async_preload_deadline"));
}
void ULivingTownMetaHumanVisualPreload::Reset()
{
    if(!IsInGameThread()) return;
    ++Epoch;OnCompletion.Unbind();SetComponentTickEnabled(false);
    if(Handle) {Handle->CancelHandle();Handle.Reset();}
    PreparedActorClass=nullptr;Idle=nullptr;Walk=nullptr;Workwear=nullptr;Requested={};State=ELivingTownMetaHumanPreloadState::Empty;Failure.Empty();
}
void ULivingTownMetaHumanVisualPreload::EndPlay(const EEndPlayReason::Type Reason)
{Reset();Super::EndPlay(Reason);}

ULivingTownMetaHumanVisualAssembly::ULivingTownMetaHumanVisualAssembly(){PrimaryComponentTick.bCanEverTick=false;}
bool ULivingTownMetaHumanVisualAssembly::Configure(const FLivingTownMetaHumanVisualBinding& B,const ULivingTownMetaHumanVisualPreload* Preload,FString& Error)
{
    Error.Reset();auto Fail=[&](const TCHAR* E){Error=E;return false;};
    if(!IsInGameThread()) return Fail(TEXT("metahuman_visual_game_thread_required"));
    if(bConfigured||VisualChild||!GetOwner()||GetOwner()->GetClass()!=ALivingTownCafeCharacter::StaticClass()||
       !GetWorld()||!GetWorld()->IsGameWorld()||GetWorld()->GetNetMode()!=NM_Standalone||!B.IsValidated()||
       !Preload||Preload->GetWorld()!=GetWorld()||!Preload->IsReadyFor(B)) return Fail(TEXT("metahuman_owned_preloaded_complete_actor_required"));
    auto* Pawn=CastChecked<ALivingTownCafeCharacter>(GetOwner());
    if(!Pawn->HasActorBegunPlay()) return Fail(TEXT("metahuman_native_parent_begin_play_required"));
    if(Pawn->GetMesh()->GetSkeletalMeshAsset()||Pawn->GetMesh()->GetAnimInstance()) return Fail(TEXT("metahuman_requires_empty_native_pawn_visual"));
    Prepared=B;Idle=Preload->GetIdle();Walk=Preload->GetWalk();
    VisualChild=NewObject<UChildActorComponent>(Pawn,TEXT("MetaHumanWholeActorVisual"));
    if(!VisualChild) return Fail(TEXT("metahuman_child_component_creation_failed"));
    Pawn->AddInstanceComponent(VisualChild);VisualChild->SetupAttachment(Pawn->GetRootComponent());VisualChild->SetRelativeTransform(B.ActorRelative);
    VisualChild->SetChildActorOwnerOnCreation(true);VisualChild->SetChildActorClass(Preload->GetPreparedActorClass());VisualChild->RegisterComponent();
    auto Rollback=[&](const TCHAR* E){Reset();return Fail(E);};
    AActor* Actor=GetVisualActor();
    if(!Actor||!Actor->HasActorBegunPlay()||Actor->GetWorld()!=GetWorld()||Actor->GetParentActor()!=Pawn||Actor->GetOwner()!=Pawn||Actor->GetClass()!=Preload->GetPreparedActorClass()) return Rollback(TEXT("metahuman_actual_begun_owned_child_actor_required"));
    Actor->SetActorEnableCollision(false);
    TArray<UPrimitiveComponent*> Primitive;Actor->GetComponents(Primitive);
    for(auto* C:Primitive) C->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    TArray<USkeletalMeshComponent*> Components;Actor->GetComponents(Components);
    if(Components.Num()!=3) return Rollback(TEXT("metahuman_complete_three_skeletal_components_required"));
    for(auto* C:Components)
    {
        if(Mesh(C,Actor,LivingTownMetaHumanVisual::BodyMesh)) Body=C;
        else if(Mesh(C,Actor,LivingTownMetaHumanVisual::FaceMesh)) Face=C;
        else if(Mesh(C,Actor,LivingTownMetaHumanVisual::OutfitMesh)) Outfit=C;
        else return Rollback(TEXT("metahuman_unexpected_skeletal_component"));
    }
    if(!Body||!Face||!Outfit||Body->LeaderPoseComponent.IsValid()||Face->GetAttachParent()!=Body||Outfit->GetAttachParent()!=Body||
       Body->GetSkeletalMeshAsset()->GetSkeleton()!=Idle->GetSkeleton()||!Body->DoesSocketExist(B.HandBone)||
       !(Face->LeaderPoseComponent.Get()==Body||Face->GetAnimInstance()||Face->GetPostProcessInstance())||
       !(Outfit->LeaderPoseComponent.Get()==Body||Outfit->GetAnimInstance()||Outfit->GetPostProcessInstance()))
        return Rollback(TEXT("metahuman_body_face_outfit_and_live_hand_binding_required"));
    for(auto* C:{Face.Get(),Outfit.Get()})
    {
        FPoseOwnership P;P.Component=C;P.Mode=uint8(C->GetAnimationMode());P.Leader=C->LeaderPoseComponent;
        P.MainClass=C->GetAnimInstance()?C->GetAnimInstance()->GetClass():nullptr;
        P.PostClass=C->GetPostProcessInstance()?C->GetPostProcessInstance()->GetClass():nullptr;PoseOwnership.Add(P);
    }
    if(B.UsesWorkwear())
    {
        ExpectedWorkwear=Preload->GetWorkwear();
        if(!WorkwearAsset(ExpectedWorkwear,Idle)) return Rollback(TEXT("metahuman_workwear_not_preloaded"));
        for(const auto& Material:ExpectedWorkwear->GetMaterials()) ExpectedWorkwearMaterials.Add(Material.MaterialInterface);
        Outfit->SetSkeletalMesh(ExpectedWorkwear,false);
        Outfit->EmptyOverrideMaterials();
        Outfit->SetOverlayMaterial(nullptr);
        if(!HasPreservedPoseOwnership()||!HasExpectedOutfit()) return Rollback(TEXT("metahuman_workwear_swap_changed_pose_or_material_ownership"));
    }
    Body->PlayAnimation(Idle,true);Body->SetPlayRate(1.f);bWalking=false;bConfigured=true;
    if(!IsConfigured()) return Rollback(TEXT("metahuman_owned_native_idle_player_required"));
    return true;
}
AActor* ULivingTownMetaHumanVisualAssembly::GetVisualActor() const{return VisualChild?VisualChild->GetChildActor():nullptr;}
bool ULivingTownMetaHumanVisualAssembly::IsConfigured() const
{
    const AActor* A=GetVisualActor();auto* Player=Body?Body->GetSingleNodeInstance():nullptr;
    return bConfigured&&Prepared.IsValidated()&&IsValid(GetOwner())&&IsValid(VisualChild)&&IsValid(A)&&A->HasActorBegunPlay()&&A->GetParentActor()==GetOwner()&&A->GetOwner()==GetOwner()&&A->GetWorld()==GetWorld()&&PreparedClass(A->GetClass())&&
        VisualChild->GetAttachParent()==GetOwner()->GetRootComponent()&&VisualChild->GetRelativeTransform().Equals(Prepared.ActorRelative,1.e-6)&&
        Mesh(Body,A,LivingTownMetaHumanVisual::BodyMesh)&&Mesh(Face,A,LivingTownMetaHumanVisual::FaceMesh)&&HasExpectedOutfit()&&
        Face->GetAttachParent()==Body&&Outfit->GetAttachParent()==Body&&!Body->LeaderPoseComponent.IsValid()&&Body->GetAnimationMode()==EAnimationMode::AnimationSingleNode&&
        Player&&Player->GetClass()==UAnimSingleNodeInstance::StaticClass()&&Player->GetCurrentAsset()==(bWalking?Walk.Get():Idle.Get())&&
        Body->DoesSocketExist(Prepared.HandBone)&&Body->bEnableAnimation&&!Body->bPauseAnims&&Body->GlobalAnimRateScale==1.f&&BodyPostProcess(Body)&&
        Player->IsPlaying()&&Player->IsLooping()&&Player->GetPlayRate()==1.f&&HasPreservedPoseOwnership()&&!A->GetActorEnableCollision()&&!A->IsHidden();
}
bool ULivingTownMetaHumanVisualAssembly::HasExpectedOutfit() const
{
    if(!Mesh(Outfit,GetVisualActor(),Prepared.ExpectedOutfitMesh())) return false;
    if(!Prepared.UsesWorkwear()) return true;
    if(!ExpectedWorkwear||Outfit->GetSkeletalMeshAsset()!=ExpectedWorkwear||ExpectedWorkwearMaterials.Num()!=3||Outfit->GetNumMaterials()!=3||Outfit->GetOverlayMaterial()) return false;
    for(int32 I=0;I<ExpectedWorkwearMaterials.Num();++I)
        if(Outfit->GetMaterial(I)!=ExpectedWorkwearMaterials[I]||Outfit->GetOverlayMaterial(true,I)) return false;
    return true;
}
bool ULivingTownMetaHumanVisualAssembly::HasPreservedPoseOwnership() const
{
    if(PoseOwnership.Num()!=2)return false;
    for(const auto& P:PoseOwnership)
    {
        auto* C=P.Component.Get();if(!C||C->GetOwner()!=GetVisualActor()||uint8(C->GetAnimationMode())!=P.Mode||C->LeaderPoseComponent.Get()!=P.Leader.Get())return false;
        const UClass* Main=C->GetAnimInstance()?C->GetAnimInstance()->GetClass():nullptr;
        const UClass* Post=C->GetPostProcessInstance()?C->GetPostProcessInstance()->GetClass():nullptr;
        if(Main!=P.MainClass.Get()||Post!=P.PostClass.Get())return false;
    }
    return true;
}
bool ULivingTownMetaHumanVisualAssembly::UpdateMotion(float Speed)
{
    if(!IsInGameThread()||!IsConfigured()||!FMath::IsFinite(Speed)||Speed<0) return false;
    const bool WantWalk=bWalking?Speed>2.f:Speed>=4.f;
    if(WantWalk!=bWalking)
    { bWalking=WantWalk;Body->PlayAnimation(bWalking?Walk:Idle,true);Body->SetPlayRate(1.f); }
    return IsConfigured();
}
void ULivingTownMetaHumanVisualAssembly::RestoreTickPolicies()
{
    for(const auto& P:SavedPolicies) if(auto* C=P.Component.Get())
    {C->VisibilityBasedAnimTickOption=static_cast<EVisibilityBasedAnimTickOption>(P.Visibility);C->bEnableUpdateRateOptimizations=P.bURO;}
    SavedPolicies.Empty();
}
void ULivingTownMetaHumanVisualAssembly::SetPossessedPlayer(bool bPossessed)
{
    if(!IsInGameThread()) return;
    RestoreTickPolicies();if(!bPossessed||!IsConfigured()) return;
    for(auto* C:{Body.Get(),Face.Get(),Outfit.Get()})
    {
        FTickPolicy P;P.Component=C;P.Visibility=uint8(C->VisibilityBasedAnimTickOption);P.bURO=C->bEnableUpdateRateOptimizations;SavedPolicies.Add(P);
        C->VisibilityBasedAnimTickOption=EVisibilityBasedAnimTickOption::AlwaysTickPoseAndRefreshBones;C->bEnableUpdateRateOptimizations=false;
    }
}
FVector ULivingTownMetaHumanVisualAssembly::InteractionHand() const
{return IsConfigured()?Body->GetSocketLocation(Prepared.HandBone):FVector::ZeroVector;}
void ULivingTownMetaHumanVisualAssembly::ResetAfterTeleport()
{
    if(!IsInGameThread()||!IsConfigured()) return;
    for(auto* C:{Body.Get(),Face.Get(),Outfit.Get()}) C->ForceClothNextUpdateTeleportAndReset();
}
void ULivingTownMetaHumanVisualAssembly::Reset()
{
    if(!IsInGameThread()) return;
    RestoreTickPolicies();bConfigured=false;
    if(VisualChild) {VisualChild->DestroyComponent();VisualChild=nullptr;}
    Body=nullptr;Face=nullptr;Outfit=nullptr;Idle=nullptr;Walk=nullptr;ExpectedWorkwear=nullptr;ExpectedWorkwearMaterials.Empty();Prepared={};PoseOwnership.Empty();bWalking=false;
}
void ULivingTownMetaHumanVisualAssembly::EndPlay(const EEndPlayReason::Type Reason)
{Reset();Super::EndPlay(Reason);}
