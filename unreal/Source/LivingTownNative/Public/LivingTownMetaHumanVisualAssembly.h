#pragma once
#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "LivingTownMetaHumanVisualAssembly.generated.h"

class UAnimSequence;
class UChildActorComponent;
class USkeletalMeshComponent;
class USkinnedMeshComponent;
struct FStreamableHandle;
struct FLivingTownCafeBinding;

namespace LivingTownMetaHumanVisual
{
    inline constexpr TCHAR ActorClass[] = TEXT("/Game/LivingTown_UEPilot/MetaHumanAssembled_v009/CafeWorker_Dominic_Trial/BP_CafeWorker_Dominic_Trial.BP_CafeWorker_Dominic_Trial_C");
    inline constexpr TCHAR BodyMesh[] = TEXT("/Game/LivingTown_UEPilot/MetaHumanAssembled_v009/CafeWorker_Dominic_Trial/Body/SKM_CH_CafeWorker_ProductionTrial_BodyMesh.SKM_CH_CafeWorker_ProductionTrial_BodyMesh");
    inline constexpr TCHAR FaceMesh[] = TEXT("/Game/LivingTown_UEPilot/MetaHumanAssembled_v009/CafeWorker_Dominic_Trial/Face/SKM_CH_CafeWorker_ProductionTrial_FaceMesh.SKM_CH_CafeWorker_ProductionTrial_FaceMesh");
    inline constexpr TCHAR OutfitMesh[] = TEXT("/Game/LivingTown_UEPilot/MetaHumanAssembled_v009/CafeWorker_Dominic_Trial/Clothing/CH_CafeWorker_ProductionTrial_Outfits.CH_CafeWorker_ProductionTrial_Outfits");
    inline constexpr TCHAR BodyPostProcessClass[] = TEXT("/MetaHumanCharacter/Body/ABP_Body_PostProcess.ABP_Body_PostProcess_C");
    inline constexpr TCHAR Idle[] = TEXT("/MetaHumanCharacter/Optional/Animation/UEFNAnimPreset/Locomotion/AS_MH_Neutral_Stand_Idle_Loop.AS_MH_Neutral_Stand_Idle_Loop");
    inline constexpr TCHAR Walk[] = TEXT("/MetaHumanCharacter/Optional/Animation/UEFNAnimPreset/Locomotion/AS_MH_Neutral_Walk_Loop_F.AS_MH_Neutral_Walk_Loop_F");
    inline constexpr TCHAR CoreManifestSha256[] = TEXT("2b60d109df4f6a99e0a746b8907fe89f16f5c3aa46aeb1db59f543c23f5b3c5c");
    LIVINGTOWNNATIVE_API bool ApplyCommandLineOptIn(FLivingTownCafeBinding& Binding,FString& Error);
}

// A measured, explicit development opt-in. It grants neither final art nor meal contact.
struct LIVINGTOWNNATIVE_API FLivingTownMetaHumanVisualBinding
{
    FString DescriptorSha256, SourceClosureSha256, CoreManifestSha256;
    FString ActorClassPath, IdleAnimationPath, WalkAnimationPath;
    FTransform ActorRelative = FTransform::Identity;
    FName HandBone = NAME_None;
    double CapsuleRadiusCm=0, CapsuleHalfHeightCm=0, WalkSpeedCmPerSecond=0, CameraArmCm=0;
    double PreloadDeadlineSeconds=0;
    bool bReadPreparedDescriptor=false;
    bool IsValidated() const;
    static bool Read(const FString& Path,FLivingTownMetaHumanVisualBinding& Out,FString& Error);
};

namespace LivingTownMetaHumanVisual
{
    LIVINGTOWNNATIVE_API bool ApplyPreparedBinding(FLivingTownCafeBinding& Binding,const FLivingTownMetaHumanVisualBinding& Prepared,FString& Error);
}

enum class ELivingTownMetaHumanPreloadState : uint8 { Empty, Pending, Ready, Failed };

// Owned by the existing GameMode. Readiness gates pawn creation, not backend authority.
UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ULivingTownMetaHumanVisualPreload final : public UActorComponent
{
    GENERATED_BODY()
public:
    ULivingTownMetaHumanVisualPreload();
    ELivingTownMetaHumanPreloadState Request(const FLivingTownMetaHumanVisualBinding& Binding,FSimpleDelegate Completion,FString& Error);
    bool IsReadyFor(const FLivingTownMetaHumanVisualBinding& Binding) const;
    UClass* GetPreparedActorClass() const { return PreparedActorClass; }
    UAnimSequence* GetIdle() const { return Idle; }
    UAnimSequence* GetWalk() const { return Walk; }
    void Reset();
    virtual void TickComponent(float Delta,ELevelTick TickType,FActorComponentTickFunction* TickFunction) override;
    virtual void EndPlay(const EEndPlayReason::Type Reason) override;
private:
    UPROPERTY() TObjectPtr<UClass> PreparedActorClass;
    UPROPERTY() TObjectPtr<UAnimSequence> Idle;
    UPROPERTY() TObjectPtr<UAnimSequence> Walk;
    TSharedPtr<FStreamableHandle> Handle;
    FSimpleDelegate OnCompletion;
    FLivingTownMetaHumanVisualBinding Requested;
    ELivingTownMetaHumanPreloadState State=ELivingTownMetaHumanPreloadState::Empty;
    uint64 Epoch=0;
    double RequestedAt=0;
    FString Failure;
    void Complete(uint64 ExpectedEpoch);
    void Fail(const TCHAR* Reason);
};

// Holds the complete generated actor. Its face, clothing, SDK components and BeginPlay stay intact.
UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ULivingTownMetaHumanVisualAssembly final : public UActorComponent
{
    GENERATED_BODY()
public:
    ULivingTownMetaHumanVisualAssembly();
    bool Configure(const FLivingTownMetaHumanVisualBinding& Binding,const ULivingTownMetaHumanVisualPreload* Preload,FString& Error);
    bool IsConfigured() const;
    bool UpdateMotion(float ActualSpeedCmPerSecond);
    void SetPossessedPlayer(bool bPossessed);
    void ResetAfterTeleport();
    void Reset();
    USkeletalMeshComponent* GetBody() const { return Body; }
    AActor* GetVisualActor() const;
    FVector InteractionHand() const;
    virtual void EndPlay(const EEndPlayReason::Type Reason) override;
private:
    UPROPERTY() TObjectPtr<UChildActorComponent> VisualChild;
    UPROPERTY() TObjectPtr<USkeletalMeshComponent> Body;
    UPROPERTY() TObjectPtr<USkeletalMeshComponent> Face;
    UPROPERTY() TObjectPtr<USkeletalMeshComponent> Outfit;
    UPROPERTY() TObjectPtr<UAnimSequence> Idle;
    UPROPERTY() TObjectPtr<UAnimSequence> Walk;
    FLivingTownMetaHumanVisualBinding Prepared;
    struct FTickPolicy { TWeakObjectPtr<USkeletalMeshComponent> Component; uint8 Visibility=0; bool bURO=false; };
    TArray<FTickPolicy> SavedPolicies;
    struct FPoseOwnership
    {
        TWeakObjectPtr<USkeletalMeshComponent> Component;
        TWeakObjectPtr<USkinnedMeshComponent> Leader;
        TWeakObjectPtr<UClass> MainClass,PostClass;
        uint8 Mode=0;
    };
    TArray<FPoseOwnership> PoseOwnership;
    bool bConfigured=false, bWalking=false;
    void RestoreTickPolicies();
    bool HasPreservedPoseOwnership() const;
};
