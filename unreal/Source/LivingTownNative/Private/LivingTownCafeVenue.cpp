#include "LivingTownCafeVenue.h"
#include "LivingTownCafeGeometryLibrary.h"
#include "Components/SceneComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/StaticMesh.h"
#include "Materials/MaterialInterface.h"
#include "Engine/World.h"
#include "HAL/PlatformTime.h"
#include "UObject/StrongObjectPtr.h"
#if WITH_EDITOR
#include "StaticMeshCompiler.h"
#endif

ALivingTownCafeVenue::ALivingTownCafeVenue()
{
    PrimaryActorTick.bCanEverTick=false;
    SetRootComponent(CreateDefaultSubobject<USceneComponent>(TEXT("QualifiedSourceRoot")));GetRootComponent()->SetMobility(EComponentMobility::Static);
}
bool ALivingTownCafeVenue::BuildQualified(const FLivingTownCafeBinding& B,FString& Error)
{
    Error.Reset(); if(bQualified||!Parts.IsEmpty()||!GetActorTransform().Equals(FTransform::Identity)||!B.HasValidatedPartRoster()) { Error=TEXT("fresh_identity_venue_and_exact_source_parts_required"); return false; }
    auto Fail=[this,&Error](const FString& Why){Error=Why;for(auto P:Parts)if(P)P->DestroyComponent();Parts.Reset();FloorParts.Reset();CounterParts.Reset();return false;};
    double LoadSeconds=0,ReadinessSeconds=0,HashSeconds=0,RegisterSeconds=0;const double Start=FPlatformTime::Seconds();
    TArray<TStrongObjectPtr<UStaticMesh>> LoadedMeshes;LoadedMeshes.Reserve(B.Parts.Num());
#if WITH_EDITOR
    TArray<UStaticMesh*> CompilationInputs;CompilationInputs.Reserve(B.Parts.Num());
#endif
    // Queue the exact bounded asset set before the inspector can force an
    // individual RenderData/BodySetup compilation barrier. Strong references
    // retain every loaded UObject through subsequent loads and compilation.
    for(const auto& Row:B.Parts)
    {
        const double Phase=FPlatformTime::Seconds();UStaticMesh* Mesh=LoadObject<UStaticMesh>(nullptr,*Row.AssetPath);LoadSeconds+=FPlatformTime::Seconds()-Phase;
        if(!IsValid(Mesh))
        {
            FString Hash,Guid,Why;ULivingTownCafeGeometryLibrary::InspectCafeMesh(Mesh,Hash,Guid,Why);
            return Fail(TEXT("source_mesh_binding_mismatch: ")+Row.Id+TEXT(" / ")+Why);
        }
        LoadedMeshes.Emplace(Mesh);
#if WITH_EDITOR
        CompilationInputs.Add(Mesh);
#endif
    }
    int32 CompilingBefore=0,CompilingAfter=0;
#if WITH_EDITOR
    const double ReadinessStart=FPlatformTime::Seconds();
    for(const UStaticMesh* Mesh:CompilationInputs)if(Mesh->IsCompiling())++CompilingBefore;
    FStaticMeshCompilingManager::Get().FinishCompilation(CompilationInputs);
    for(const UStaticMesh* Mesh:CompilationInputs)if(Mesh->IsCompiling())++CompilingAfter;
    ReadinessSeconds=FPlatformTime::Seconds()-ReadinessStart;
#endif
    for(int32 Index=0;Index<B.Parts.Num();++Index)
    {
        const auto& Row=B.Parts[Index];UStaticMesh* Mesh=LoadedMeshes[Index].Get();FString Hash,Guid,Why;double Phase=FPlatformTime::Seconds();
        if(!ULivingTownCafeGeometryLibrary::InspectCafeMesh(Mesh,Hash,Guid,Why)||Hash!=Row.RenderSha256||Guid!=Row.CollisionGuid) return Fail(TEXT("source_mesh_binding_mismatch: ")+Row.Id+TEXT(" / ")+Why);
        if(B.bAuthoredSceneTrial)
        {
            if(!Mesh->GetPathName().Equals(Row.AssetPath,ESearchCase::CaseSensitive))return Fail(TEXT("declared_source_mesh_identity_mismatch: ")+Row.Id);
            const TArray<FString>* Expected=B.DeclaredAssetMaterials.Find(Row.AssetPath);const auto& Slots=Mesh->GetStaticMaterials();
            if(!Expected||Slots.Num()!=Expected->Num())return Fail(TEXT("declared_source_material_slot_count_mismatch: ")+Row.Id);
            for(int32 Slot=0;Slot<Slots.Num();++Slot)
            { const UMaterialInterface* Material=Slots[Slot].MaterialInterface.Get();if(!IsValid(Material)||!Material->GetPathName().Equals((*Expected)[Slot],ESearchCase::CaseSensitive))return Fail(TEXT("declared_source_material_identity_mismatch: ")+Row.Id); }
        }
        HashSeconds+=FPlatformTime::Seconds()-Phase;Phase=FPlatformTime::Seconds();
        UStaticMeshComponent* Part=NewObject<UStaticMeshComponent>(this); AddInstanceComponent(Part); Part->SetupAttachment(GetRootComponent()); Part->SetMobility(EComponentMobility::Static); Part->SetStaticMesh(Mesh); Part->SetRelativeTransform(Row.Transform);
        Part->SetCollisionProfileName(TEXT("BlockAll")); Part->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics); Part->SetGenerateOverlapEvents(false); Part->ComponentTags.Add(FName(*Row.Id)); Part->RegisterComponent(); Parts.Add(Part);
        if(!Part->IsRegistered()||!Part->IsCollisionEnabled()||Part->GetCollisionResponseToChannel(ECC_Pawn)!=ECR_Block||Part->GetCollisionResponseToChannel(ECC_Visibility)!=ECR_Block) return Fail(TEXT("source_collision_not_active: ")+Row.Id);
        if(Row.bFloor)FloorParts.Add(Part); if(Row.bCounter)CounterParts.Add(Part);
        RegisterSeconds+=FPlatformTime::Seconds()-Phase;
    }
    if(FloorParts.IsEmpty()||CounterParts.IsEmpty()) return Fail(TEXT("actual_floor_and_counter_binding_missing"));
    bQualified=true;UE_LOG(LogTemp,Display,TEXT("Cafe startup part_contract authored_trial=%d declared_parts=%d actual_parts=%d material_assets=%d context=%s"),B.bAuthoredSceneTrial?1:0,B.DeclaredPartCount,Parts.Num(),B.DeclaredAssetMaterials.Num(),*B.PartSourceContextSha256);
    UE_LOG(LogTemp,Display,TEXT("Cafe startup parts=%d total=%.6f load=%.6f hash=%.6f register=%.6f seconds"),Parts.Num(),FPlatformTime::Seconds()-Start,LoadSeconds,HashSeconds,RegisterSeconds);
    UE_LOG(LogTemp,Display,TEXT("Cafe startup readiness_wait=%.6f full_validation_hash=%.6f pending_before=%d pending_after=%d bounded_meshes=%d seconds"),ReadinessSeconds,HashSeconds,CompilingBefore,CompilingAfter,LoadedMeshes.Num());return true;
}
bool ALivingTownCafeVenue::IsFloorComponent(const UPrimitiveComponent* C)const{return bQualified&&FloorParts.Contains(C);}
bool ALivingTownCafeVenue::IsCounterComponent(const UPrimitiveComponent* C)const{return bQualified&&CounterParts.Contains(C);}
bool ALivingTownCafeVenue::FloorAt(const FVector& Feet,FHitResult& Hit,const AActor* Ignore)const
{
    if(!bQualified||!GetWorld())return false; FCollisionQueryParams Q(SCENE_QUERY_STAT(CafeActualFloor),true);if(Ignore)Q.AddIgnoredActor(Ignore);
    if(!GetWorld()->LineTraceSingleByChannel(Hit,Feet+FVector(0,0,10),Feet-FVector(0,0,40),ECC_Visibility,Q))return false;
    return IsFloorComponent(Hit.GetComponent())&&Hit.ImpactNormal.Z>=.7&&FMath::Abs(Feet.Z-Hit.ImpactPoint.Z)<=4.;
}
