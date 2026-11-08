#pragma once
#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "LivingTownCafeWorldV3Types.h"
#include "LivingTownMetaHumanMealProducer.generated.h"
class ALivingTownCafeCharacter;
class ALivingTownCafeVenue;
class ULivingTownCafeWorldV3Subsystem;
class ULivingTownMetaHumanVisualAssembly;
class UAnimSingleNodeInstance;
class UAnimInstance;
class UAnimSequence;
class UStaticMesh;
class UStaticMeshComponent;
class USkeletalMeshComponent;
class USkinnedMeshComponent;

enum class ELivingTownMealPhysicalPhase : uint8 { Inactive,Entry,Bite,Chew,Exit,Finished };
struct FLivingTownMealPhysicalObservation {
    uint64 Frame=0;double WorldSeconds=0,ClipSeconds=0;
    ELivingTownMealPhysicalPhase Phase=ELivingTownMealPhysicalPhase::Inactive;
    FVector FoodBiteWorld=FVector::ZeroVector,MouthWorld=FVector::ZeroVector;
    bool bFresh=false,bHolding=false,bBiteObserved=false,bFirstProgressEligible=false,bConsumptionPhase=false;
};

// No automatic registration, capability admission, E hook, needs or ledger API.
// A future trusted WorldV3 owner must configure/start/consume this physical source.
UCLASS(NotBlueprintable)
class LIVINGTOWNNATIVE_API ULivingTownMetaHumanMealProducer final : public UActorComponent {
    GENERATED_BODY()
public:
    ULivingTownMetaHumanMealProducer();
    bool Configure(const FString& ContentRelativeRecipe,FString& Error);
    bool BeginPhysicalUse(FString& Error);
    bool ReadLatest(FLivingTownMealPhysicalObservation& Out,FString& Error)const;
    void StopPhysicalUse();
    bool IsPhysicalUseActive()const{return bActive;}
    const FString& GetFailure()const{return Failure;}
    const FLivingTownMetaHumanMealRecipeV2& GetRecipe()const{return Recipe;}
    virtual void TickComponent(float Delta,ELevelTick TickType,FActorComponentTickFunction* TickFunction)override;
    virtual void EndPlay(const EEndPlayReason::Type Reason)override;
private:
    friend class ULivingTownCafeWorldV3Subsystem;
    // Only the authority owner can bind its actual private session/grant check.
    // Deliberately unwired in this source slice; presentation booleans do not qualify.
    bool BindTrustedSessionObserver(ULivingTownCafeWorldV3Subsystem* Owner,TFunction<bool(const ALivingTownCafeCharacter*)>&& Observer);
    TFunction<bool(const ALivingTownCafeCharacter*)> TrustedSessionObserver;
    FLivingTownMetaHumanMealRecipeV2 Recipe;
    UPROPERTY(Transient) TMap<FString,TObjectPtr<UObject>> SourceObjects;
    UPROPERTY(Transient) TObjectPtr<UAnimSequence> Clip;
    UPROPERTY(Transient) TObjectPtr<UStaticMesh> BreadMesh;
    UPROPERTY(Transient) TObjectPtr<UStaticMeshComponent> OwnedBread;
    TWeakObjectPtr<ALivingTownCafeCharacter> Pawn;
    TWeakObjectPtr<ALivingTownCafeVenue> Venue;
    TWeakObjectPtr<ULivingTownCafeWorldV3Subsystem> Authority;
    TWeakObjectPtr<ULivingTownMetaHumanVisualAssembly> Assembly;
    TWeakObjectPtr<AActor> Visual;
    TWeakObjectPtr<USkeletalMeshComponent> Body,Face,Outfit;
    TWeakObjectPtr<UAnimSingleNodeInstance> Player;
    TWeakObjectPtr<UAnimInstance> BodyPost,FaceMain,FacePost,OutfitMain,OutfitPost;
    TWeakObjectPtr<USkinnedMeshComponent> FaceLeader,OutfitLeader;
    uint8 FaceMode=0,OutfitMode=0;bool bFacePostDisabled=false,bOutfitPostDisabled=false;
    bool bConfigured=false,bActive=false,bBiteObserved=false,bChewObserved=false,bMayRestoreAction=false,bAwaitingFirstPose=false;
    FString Failure;
    FDelegateHandle BodyFinalizedHandle,FaceFinalizedHandle;
    uint64 BodyFinalizedFrame=0,FaceFinalizedFrame=0;
    uint64 StartedFrame=0;double StartedWorld=0;
    uint32 LastBodyRevision=0,LastFaceRevision=0;
    double LastWorld=0,LastClip=0,BiteSpanStart=0,BiteObservedAt=0;
    int32 BiteSamples=0;
    float MinBodyCurve=0,MaxBodyCurve=0,MinFaceCurve=0,MaxFaceCurve=0;
    FQuat FirstChewJaw=FQuat::Identity;double MaxChewJawDegrees=0;
    float MotionBodyCurve=0,MotionFaceCurve=0;
    FQuat MotionJaw=FQuat::Identity;double LastCurveMotionWorld=0,LastJawMotionWorld=0;
    FLivingTownMealPhysicalObservation Latest;
    UObject* RoleObject(const FString& Role)const;
    bool LiveIdentity(FString& Error)const;
    bool LiveBread(FString& Error)const;
    bool ObserveStation(FString& Error)const;
    bool ObserveFrame(FString& Error);
    void BodyFinalized();void FaceFinalized();
};
