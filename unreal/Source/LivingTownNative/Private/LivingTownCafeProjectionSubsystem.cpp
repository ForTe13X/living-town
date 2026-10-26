#include "LivingTownCafeProjectionSubsystem.h"
#include "LivingTownCafeVenue.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownCafeSlot.h"
#include "Engine/GameInstance.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Components/CapsuleComponent.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "HAL/FileManager.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Misc/ScopeExit.h"
#include "HAL/PlatformTime.h"

bool ULivingTownCafeProjectionSubsystem::DoesSupportWorldType(EWorldType::Type T)const{return T==EWorldType::Game||T==EWorldType::PIE;}
void ULivingTownCafeProjectionSubsystem::Initialize(FSubsystemCollectionBase& C){Super::Initialize(C);RefreshPresentation(true);}
TStatId ULivingTownCafeProjectionSubsystem::GetStatId()const{RETURN_QUICK_DECLARE_CYCLE_STAT(ULivingTownCafeProjectionSubsystem,STATGROUP_Tickables);}
ULivingTownLeaseSubsystem* ULivingTownCafeProjectionSubsystem::Lease()const{return GetWorld()&&GetWorld()->GetGameInstance()?GetWorld()->GetGameInstance()->GetSubsystem<ULivingTownLeaseSubsystem>():nullptr;}
void ULivingTownCafeProjectionSubsystem::Deinitialize()
{
    if(Lease())Lease()->InstallTrustedInteractionResolver(nullptr);bReady=false;bScenePrepared=false;Player.Reset();Venue=nullptr;Super::Deinitialize();
}
bool ULivingTownCafeProjectionSubsystem::PrepareQualifiedScene(const FString& Path,FString& Error)
{
    const double Started=FPlatformTime::Seconds();ON_SCOPE_EXIT{RefreshPresentation(true);UE_LOG(LogTemp,Display,TEXT("Cafe startup binding/geometry/spawn check seconds=%.6f prepared=%d"),FPlatformTime::Seconds()-Started,bScenePrepared?1:0);};
    Error.Reset(); if(bScenePrepared||!IsInGameThread()||!GetWorld()||GetWorld()->GetNetMode()!=NM_Standalone||!Lease()){Error=TEXT("single_standalone_authority_scene_required");Status=Error;return false;}
    FLivingTownCafeBinding Candidate;if(!FLivingTownCafeBinding::ReadQualifiedFile(Path,Candidate,Error)){Status=TEXT("Café unavailable: ")+Error;return false;}
    // Read-only display quote comes from the exact frozen core fixture, never a widget.
    TArray<uint8> TermsBytes;FString TermsHash,TermsJson;
    if(!FFileHelper::LoadFileToArray(TermsBytes,*FPaths::Combine(FPaths::ProjectContentDir(),TEXT("LivingTown/PILOT_CASES.json")))||!LivingTownCafeJournal::Sha256(TermsBytes,TermsHash)||TermsHash!=TEXT("b5a0df51f0bb7fd1a04196d8fe1118df75b9de275b881faad71ac014c00ecf4c")){Error=TEXT("frozen_offer_source_missing_or_changed");Status=Error;return false;}
    FFileHelper::BufferToString(TermsJson,TermsBytes.GetData(),TermsBytes.Num());TSharedPtr<FJsonObject> TermsObject;
    if(!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(TermsJson),TermsObject)||!TermsObject||!TermsObject->HasTypedField<EJson::Object>(TEXT("source_terms"))){Error=TEXT("frozen_offer_source_invalid");Status=Error;return false;}
    const auto SourceTerms=TermsObject->GetObjectField(TEXT("source_terms"));OfferFee=int64(SourceTerms->GetNumberField(TEXT("fee")));OfferDuration=int64(SourceTerms->GetNumberField(TEXT("duration")));
    ALivingTownCafeVenue* NewVenue=GetWorld()->SpawnActor<ALivingTownCafeVenue>();
    if(!NewVenue||!NewVenue->BuildQualified(Candidate,Error)){if(NewVenue)NewVenue->Destroy();Status=TEXT("Café source binding refused: ")+Error;return false;}
    FHitResult Floor;FCollisionQueryParams Q(SCENE_QUERY_STAT(CafeSpawnClearance),true);const FVector Center=Candidate.SpawnFeetCm+FVector(0,0,Candidate.CapsuleHalfHeightCm);
    if(!Candidate.FloorBoundsCm.IsInsideXY(Candidate.SpawnFeetCm)||!NewVenue->FloorAt(Candidate.SpawnFeetCm,Floor)||GetWorld()->OverlapBlockingTestByChannel(Center,FQuat::Identity,ECC_Pawn,FCollisionShape::MakeCapsule(Candidate.CapsuleRadiusCm,Candidate.CapsuleHalfHeightCm),Q))
    {NewVenue->Destroy();Error=TEXT("actual_calibrated_spawn_floor_or_capsule_clearance_failed");Status=Error;return false;}
    Binding=MoveTemp(Candidate);Venue=NewVenue;bScenePrepared=true;Status=TEXT("Café geometry qualified; waiting for the qualified Ben character.");return true;
}
bool ULivingTownCafeProjectionSubsystem::AttachQualifiedPlayer(ALivingTownCafeCharacter* In,FString& Error)
{
    ON_SCOPE_EXIT{RefreshPresentation(true);};
    Error.Reset();if(!bScenePrepared||!IsValid(Venue)||!Venue->IsQualified()||!IsValid(In)||In->GetWorld()!=GetWorld()||!In->HasQualifiedVisual()||In->GetController()!=GetWorld()->GetFirstPlayerController())
    {Error=TEXT("actual_possessed_Ben_and_source_venue_required");Status=Error;return false;}
    if(!FMath::IsNearlyEqual(In->GetCapsuleComponent()->GetScaledCapsuleRadius(),Binding.CapsuleRadiusCm,.01f)||!FMath::IsNearlyEqual(In->GetCapsuleComponent()->GetScaledCapsuleHalfHeight(),Binding.CapsuleHalfHeightCm,.01f))
    {Error=TEXT("character_capsule_calibration_mismatch");Status=Error;return false;}
    Player=In;bReady=true;TickRemainder=0;TWeakObjectPtr<ULivingTownCafeProjectionSubsystem> Weak(this);
    Lease()->InstallTrustedInteractionResolver([Weak](FLivingTownTrustedInteraction& Out){FString Why;return Weak.IsValid()&&Weak->ObserveCounter(Out,Why);});
    Status=TEXT("Walk to the café counter. E: lease / R: end lease.");return true;
}
FLivingTownLeaseView ULivingTownCafeProjectionSubsystem::GetLeaseView()const{return Lease()?Lease()->GetLeaseView():FLivingTownLeaseView();}
bool ULivingTownCafeProjectionSubsystem::ObserveCounter(FLivingTownTrustedInteraction& Out,FString& Why)const
{
    Out={};Why.Reset();const ALivingTownCafeCharacter* P=Player.Get();
    if(!bReady||!IsValid(Venue)||!Venue->IsQualified()||!P||!P->HasQualifiedVisual()||P->GetController()!=GetWorld()->GetFirstPlayerController()) {Why=TEXT("spatial_binding_unqualified");return false;}
    const FVector Feet=P->GetActorLocation()-FVector(0,0,P->GetCapsuleComponent()->GetScaledCapsuleHalfHeight());FHitResult Floor;
    Out.SpaceId=TEXT("cafe");Out.FloorId=TEXT("1f");Out.InteractionId=TEXT("cafe1f_counter");
    if(!P->GetCharacterMovement()->IsMovingOnGround()||!Binding.FloorBoundsCm.IsInsideXY(Feet)||!Venue->FloorAt(Feet,Floor,P)) {Why=TEXT("stand_on_the_actual_cafe_floor");return true;}
    const FVector Hand=P->InteractionHand(),Target=Binding.CounterUsePointCm;
    if(Hand.ContainsNaN()||FVector::Dist(Hand,Target)>Binding.ReachCm) {Why=TEXT("walk_closer_to_the_counter");return true;}
    if(FVector::DotProduct(P->GetActorForwardVector().GetSafeNormal2D(),(Target-P->GetActorLocation()).GetSafeNormal2D())<.15) {Why=TEXT("face_the_counter");return true;}
    FCollisionQueryParams Q(SCENE_QUERY_STAT(CafeCounterReach),true);Q.AddIgnoredActor(P);FHitResult HandHit,ViewHit;FVector View;FRotator Rotation;P->GetActorEyesViewPoint(View,Rotation);
    const bool HandClear=GetWorld()->LineTraceSingleByChannel(HandHit,Hand,Target,ECC_Visibility,Q)&&Venue->IsCounterComponent(HandHit.GetComponent());
    const bool ViewClear=GetWorld()->LineTraceSingleByChannel(ViewHit,View,Target,ECC_Visibility,Q)&&Venue->IsCounterComponent(ViewHit.GetComponent());
    if(!HandClear||!ViewClear){Why=TEXT("counter_line_of_sight_blocked");return true;}
    Out.bWithinReach=true;Why=TEXT("counter_reachable");return true;
}
FLivingTownLeaseReceipt ULivingTownCafeProjectionSubsystem::RequestAction(ELivingTownLeaseAction Action)
{
    FLivingTownLeaseReceipt R;if(!bReady||!Lease()){R.Reason=TEXT("spatial_binding_unqualified");Status=R.Reason;return R;}
    FLivingTownLeaseCommand C;C.RequestId=FLivingTownStableId(TEXT("native-cafe/")+FGuid::NewGuid().ToString(EGuidFormats::Digits));C.PropertyId=FLivingTownStableId(TEXT("cafe_ground_commercial_v1"));C.Action=Action;
    R=Lease()->SubmitCommand(C);Status=R.bAccepted?(Action==ELivingTownLeaseAction::Lease?TEXT("Lease granted. Ben operates the café."):TEXT("Lease ended. Aria operates the café; no refund.")):TEXT("Action refused: ")+R.Reason;RefreshPresentation(true);return R;
}
void ULivingTownCafeProjectionSubsystem::Tick(float Delta)
{
    Super::Tick(Delta);if(!bReady||!Lease())return;
    if(!Player.IsValid()||!IsValid(Venue)||!Venue->IsQualified()){bReady=false;Lease()->InstallTrustedInteractionResolver(nullptr);Status=TEXT("Physical café binding was lost.");RefreshPresentation(true);return;}
    if(!FMath::IsFinite(Delta)||Delta<0||Delta>3600){bReady=false;Lease()->InstallTrustedInteractionResolver(nullptr);Status=TEXT("Authority clock paused: invalid world delta.");RefreshPresentation(true);return;}
    AffordanceAccumulator+=Delta;if(AffordanceAccumulator>=.1f){AffordanceAccumulator=FMath::Fmod(AffordanceAccumulator,.1f);RefreshPresentation();}
    TickRemainder+=double(Delta);const int64 Whole=int64(FMath::FloorToDouble(TickRemainder));if(Whole<=0)return;
    const int64 Current=Lease()->GetLeaseView().Clock;FString Error;
    if(Current>MAX_int64-Whole||!Lease()->AdvanceTrustedClockTo(Current+Whole,Error)){bReady=false;Lease()->InstallTrustedInteractionResolver(nullptr);Status=TEXT("Authority clock refused: ")+Error;RefreshPresentation(true);return;}TickRemainder-=double(Whole);RefreshPresentation();
}
void ULivingTownCafeProjectionSubsystem::RefreshPresentation(bool Force)
{
    FLivingTownTrustedInteraction At;FString Why;const bool Reach=bReady&&ObserveCounter(At,Why)&&At.bWithinReach;const auto V=bReady?GetLeaseView():FLivingTownLeaseView();
    const bool Changed=Force||bCachedReady!=bReady||bCachedReach!=Reach||CachedStatus!=Status||CachedLease.Clock!=V.Clock||CachedLease.EventCount!=V.EventCount||CachedLease.BenCoins!=V.BenCoins||CachedLease.AriaCoins!=V.AriaCoins||CachedLease.OperatorId.Value!=V.OperatorId.Value;
    if(!Changed)return;bCachedReady=bReady;bCachedReach=Reach;CachedStatus=Status;CachedLease=V;PresentationLines.Reset();
    Presentation={};Presentation.bReady=bReady;Presentation.bReachable=Reach;
    if(bReady)
    {
        const FString Owner=V.OwnerId.Value==TEXT("aria")?TEXT("Aria"):V.OwnerId.Value;
        const FString Operator=V.OperatorId.Value==TEXT("ben")?TEXT("Ben"):(V.OperatorId.Value==TEXT("aria")?TEXT("Aria"):V.OperatorId.Value);
        Presentation.Resident=FString::Printf(TEXT("Ben  |  %lld coins"),(long long)V.BenCoins);
        Presentation.Stewardship=FString::Printf(TEXT("Owner %s  |  Run by %s"),*Owner,*Operator);
        // The native clock advances once per elapsed game second. Quote the
        // unchanged authority duration without exposing internal clock ticks.
        const int64 Minutes=OfferDuration/60,Seconds=OfferDuration%60;
        const FString Duration=Seconds==0?FString::Printf(TEXT("%lld min"),(long long)Minutes):FString::Printf(TEXT("%lld min %lld sec"),(long long)Minutes,(long long)Seconds);
        Presentation.Offer=FString::Printf(TEXT("Lease: %lld coins for %s"),(long long)OfferFee,*Duration);
        Presentation.Prompt=Reach?TEXT("E  Lease cafe     R  End lease"):TEXT("Approach the counter and face it");
    }
    else Presentation.Prompt=TEXT("Cafe journey unavailable");
    // Wrap feedback only when source content changes, never during DrawHUD.
    TArray<FString> FeedbackWords;if(!bReady||Status!=TEXT("Walk to the café counter. E: lease / R: end lease."))Status.ParseIntoArray(FeedbackWords,TEXT(" "),true);FString FeedbackRow;
    for(const FString& Word:FeedbackWords){if(!FeedbackRow.IsEmpty()&&FeedbackRow.Len()+Word.Len()>68){Presentation.Feedback.Add(FeedbackRow);FeedbackRow.Reset();}if(!FeedbackRow.IsEmpty())FeedbackRow+=TEXT(" ");FeedbackRow+=Word;}if(!FeedbackRow.IsEmpty())Presentation.Feedback.Add(FeedbackRow);

    auto Add=[this](const FString& Text)
    {
        TArray<FString> Words;Text.ParseIntoArray(Words,TEXT(" "),true);FString Row;
        for(const FString& Word:Words){if(!Row.IsEmpty()&&Row.Len()+Word.Len()>51){PresentationLines.Add(Row);Row.Reset();}if(!Row.IsEmpty())Row+=TEXT(" ");Row+=Word;}if(!Row.IsEmpty())PresentationLines.Add(Row);
    };
    Add(TEXT("LIVING TOWN / CAFÉ"));if(!bReady){Add(TEXT("Journey unavailable"));Add(TEXT("The café scene or Ben's visual and movement are not ready yet."));return;}
    Add(FString::Printf(TEXT("Playing: %s | Owner: %s"),*V.SessionId.Value,*V.OwnerId.Value));Add(FString::Printf(TEXT("Ben: %lld coins     Aria: %lld coins"),(long long)V.BenCoins,(long long)V.AriaCoins));
    Add(FString::Printf(TEXT("Operator: %s | Clock: %lld ticks"),*V.OperatorId.Value,(long long)V.Clock));Add(FString::Printf(TEXT("Lease: %lld coins / %lld ticks"),(long long)OfferFee,(long long)OfferDuration));Add(Reach?TEXT("Counter reachable: E Lease | R End lease"):TEXT("Walk to the counter and face it."));Add(TEXT("WASD move | Mouse look"));Add(TEXT("F5 save café ledger | F9 load café ledger"));Add(Status);
}
bool ULivingTownCafeProjectionSubsystem::SaveProjection(FString& Out,FString& Error)const
{
    Out.Reset();if(!bReady||!Lease()){Error=TEXT("physical_projection_not_ready");return false;}FString Inner;if(!Lease()->SaveNewPilotJournal(Inner,Error))return false;return LivingTownCafeJournal::Encode(Binding,Inner,Out,Error);
}
bool ULivingTownCafeProjectionSubsystem::LoadProjection(const FString& Json,FString& Error)
{
    ON_SCOPE_EXIT{RefreshPresentation(true);};
    if(!bReady||!Lease()){Error=TEXT("physical_projection_not_ready");return false;}FString Inner;
    if(!LivingTownCafeJournal::Decode(Json,Binding,Inner,Error))return false;
    // No live clock/pose/lease write occurs before both strict envelopes validate.
    // The unchanged loader folds into a candidate and swaps its state atomically.
    if(!Lease()->LoadNewPilotJournal(Inner,Error))return false;
    TickRemainder=0;Status=TEXT("Matching café journal loaded. Current physical position is unchanged.");return true;
}
FString ULivingTownCafeProjectionSubsystem::SlotPath()const{return FPaths::Combine(FPaths::ProjectSavedDir(),TEXT("CafePilot"),TEXT("CafeProjection.slot.json"));}
bool ULivingTownCafeProjectionSubsystem::SaveSlot(FString& Error)const
{
    FString Json;if(!SaveProjection(Json,Error))return false;return LivingTownCafeSlot::WriteAtomic(SlotPath(),Json,Error);
}
bool ULivingTownCafeProjectionSubsystem::LoadSlot(FString& Error)
{
    const FString Path=SlotPath();const int64 Size=IFileManager::Get().FileSize(*Path);if(Size<=0||Size>6*1024*1024){Error=TEXT("projection_slot_missing_or_oversize");return false;}FString Json;if(!FFileHelper::LoadFileToString(Json,*Path)){Error=TEXT("projection_slot_read_failed");return false;}return LoadProjection(Json,Error);
}
