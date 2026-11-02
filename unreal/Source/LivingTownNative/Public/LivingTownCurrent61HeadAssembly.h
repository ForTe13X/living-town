#pragma once
#include "CoreMinimal.h"

class USkeletalMeshComponent;

enum class ELivingTownHeadPartRole : uint8 { HairCards, Underlayer };
// Explicit transient contract: no unspecified or inferred material profile.
enum class ELivingTownHeadShadingModel : uint8 { Unspecified, Hair, DefaultLit };

struct FLivingTownCurrent61HeadPart
{
    ELivingTownHeadPartRole Role=ELivingTownHeadPartRole::HairCards;
    ELivingTownHeadShadingModel ShadingModel=ELivingTownHeadShadingModel::Unspecified;
    FString MeshPath;
    FString MaterialPath;
    int32 RenderTriangles=0; // observed saved intake, never a global legacy hair count
    int32 UVChannels=0;
};

// Supplied only by the explicit closed head-assembly producer, never HUD/input.
// This describes head asset/pose assembly, not whole-avatar art/contact acceptance.
struct FLivingTownCurrent61HeadBinding
{
    FString QualificationSha256;
    TArray<FName> SourceJointNames;
    TArray<FLivingTownCurrent61HeadPart> Parts;
    bool bReadQualifiedDescriptor=false;
    bool IsValidated() const;
};

namespace LivingTownCurrent61HeadAssembly
{
    // Wrong thread, null or aliased inputs refuse before touching components.
    // Later descriptor/material/mesh failures clear only the two distinct followers.
    LIVINGTOWNNATIVE_API bool Configure(USkeletalMeshComponent* Body,USkeletalMeshComponent* Hair,
        USkeletalMeshComponent* Cap,const FLivingTownCurrent61HeadBinding& Binding,FString& Error);
    // Game-thread only; caller supplies follower components, never the body.
    // An off-thread call is a no-op.
    LIVINGTOWNNATIVE_API void Reset(USkeletalMeshComponent* Hair,USkeletalMeshComponent* Cap);
}
