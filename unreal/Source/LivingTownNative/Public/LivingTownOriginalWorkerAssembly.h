#pragma once
#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "LivingTownOriginalWorkerAssembly.generated.h"

class USkeletalMeshComponent;
class USkeletalMesh;
class UBlendSpace1D;
class UChaosClothComponent;
struct FLivingTownCafeBinding;
struct FLivingTownOriginalWorkerBinding;

namespace LivingTownOriginalWorker
{
    inline constexpr TCHAR BodySource[] = TEXT("/Game/Worker110Prototype/Imported/LT_RuntimeCharacter001_Body.LT_RuntimeCharacter001_Body");
    inline constexpr TCHAR Body[] = TEXT("/Game/LivingTown_UEPilot/OriginalWorkerBen_v001/SK_Ben.SK_Ben");
    inline constexpr TCHAR Underlay[] = TEXT("/Game/Worker110Prototype/InnerSupport/LT_RuntimeCharacter001_Underlay.LT_RuntimeCharacter001_Underlay");
    inline constexpr TCHAR Cloth[] = TEXT("/Game/Worker110Prototype/CA_SeparateApron.CA_SeparateApron");
    inline constexpr TCHAR Collision[] = TEXT("/Game/Worker110Prototype/PA_MeasuredSix.PA_MeasuredSix");
    inline constexpr TCHAR IdleSource[] = TEXT("/Game/Worker110Prototype/Imported/idle.idle");
    inline constexpr TCHAR WalkSource[] = TEXT("/Game/Worker110Prototype/Imported/walk.walk");
    inline constexpr TCHAR Idle[] = TEXT("/Game/LivingTown_UEPilot/OriginalWorkerBen_v001/A_Idle.A_Idle");
    inline constexpr TCHAR Walk[] = TEXT("/Game/LivingTown_UEPilot/OriginalWorkerBen_v001/A_Walk.A_Walk");
    inline constexpr TCHAR Motion[] = TEXT("/Game/LivingTown_UEPilot/OriginalWorkerBen_v001/BS_IdleWalk.BS_IdleWalk");
    inline constexpr TCHAR Wrapper[] = TEXT("LT_RuntimeCharacter001_Rig");
    inline constexpr TCHAR Palm[] = TEXT("UsePalm_Original_R");
    inline constexpr double WalkSpeedCmS = 106.13712295889874;
    LIVINGTOWNNATIVE_API const TArray<FString>& Materials(); // Body, apron, inner support
    LIVINGTOWNNATIVE_API bool ApplyCommandLineOptIn(FLivingTownCafeBinding& Binding,FString& Error);
    LIVINGTOWNNATIVE_API bool ApplyPreparedBinding(FLivingTownCafeBinding& Binding,const FLivingTownOriginalWorkerBinding& Prepared,FString& Error);
}

// Prepared by the Editor producer from explicit measurements. This is a
// controlled Game trial descriptor, never a meal/contact or final-art grant.
struct LIVINGTOWNNATIVE_API FLivingTownOriginalWorkerBinding
{
    FString DescriptorSha256;
    FString SourceClosureSha256;
    FTransform MeshRelative = FTransform::Identity;
    FTransform PalmLocal = FTransform::Identity;
    FVector IdleOffsetCm = FVector::ZeroVector;
    FVector WalkOffsetCm = FVector::ZeroVector;
    TArray<FName> BoneNames;
    TArray<int32> Parents;
    TArray<FTransform> ReferenceLocal;
    double CapsuleRadiusCm=0, CapsuleHalfHeightCm=0;
    bool bReadPreparedDescriptor=false;
    bool IsValidated() const;
    static bool Read(const FString& Path,FLivingTownOriginalWorkerBinding& Out,FString& Error);
};

// Owns only two newly created followers and the previously empty Ben body.
// The pawn retains movement, input, camera and authoritative interaction logic.
UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ULivingTownOriginalWorkerAssembly final : public UActorComponent
{
    GENERATED_BODY()
public:
    ULivingTownOriginalWorkerAssembly();
    bool Configure(USkeletalMeshComponent* Body,const FLivingTownOriginalWorkerBinding& Binding,FString& Error);
    void Reset();
    void ResetAfterTeleport();
    bool IsConfigured() const { return bConfigured; }
    USkeletalMeshComponent* GetUnderlay() const { return Support; }
    UChaosClothComponent* GetApron() const { return Apron; }
    UBlendSpace1D* GetMotion() const { return Motion; }
    virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;
private:
    UPROPERTY() TObjectPtr<USkeletalMeshComponent> Leader;
    UPROPERTY() TObjectPtr<USkeletalMeshComponent> Support;
    UPROPERTY() TObjectPtr<UChaosClothComponent> Apron;
    UPROPERTY() TObjectPtr<USkeletalMesh> OwnedBody;
    UPROPERTY() TObjectPtr<UBlendSpace1D> Motion;
    FTransform PreviousRelative;
    uint8 PreviousAnimationMode=0, PreviousBonePolicy=0, PreviousCollisionMode=0;
    bool PreviousVisible=false, PreviousUpdateRateOptimization=false, bConfigured=false;
};
