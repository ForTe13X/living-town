#include "LivingTownCafeWorldV3Scenario.h"
#include "LivingTownCafeWorldV3Subsystem.h"
#include "LivingTownCafePropertyV2Scenario.h"
#include "LivingTownCafeCharacter.h"
#include "LivingTownMetaHumanVisualAssembly.h"
#include "LivingTownFullTownStreamingSubsystem.h"
#include "Engine/World.h"
#include "Engine/Engine.h"
#include "Engine/Canvas.h"
#include "Engine/Font.h"
#include "Components/InputComponent.h"
#include "Components/CapsuleComponent.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "InputCoreTypes.h"
#include "GameFramework/PlayerInput.h"
#include "Camera/PlayerCameraManager.h"

ALivingTownCafeWorldV3GameMode::ALivingTownCafeWorldV3GameMode(){DefaultPawnClass=nullptr;SpectatorClass=nullptr;PlayerControllerClass=ALivingTownCafeWorldV3Controller::StaticClass();HUDClass=ALivingTownCafeWorldV3HUD::StaticClass();bUseSeamlessTravel=false;}
APawn* ALivingTownCafeWorldV3GameMode::SpawnDefaultPawnAtTransform_Implementation(AController*,const FTransform&){return nullptr;}
void ALivingTownCafeWorldV3GameMode::StartPlay(){Super::StartPlay();FString Error;auto* P=GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();if(!P||!P->PrepareScenario(Error)){UE_LOG(LogTemp,Error,TEXT("World v3 scenario refused: %s"),*Error);return;}for(FConstPlayerControllerIterator It=GetWorld()->GetPlayerControllerIterator();It;++It)StartScenarioPlayer(It->Get());}
void ALivingTownCafeWorldV3GameMode::HandleStartingNewPlayer_Implementation(APlayerController* PC){Super::HandleStartingNewPlayer_Implementation(PC);StartScenarioPlayer(PC);}
void ALivingTownCafeWorldV3GameMode::EndPlay(const EEndPlayReason::Type Reason)
{
    bEndingPlay=true;CancelPendingPersonaRequest(true);Super::EndPlay(Reason);
}
void ALivingTownCafeWorldV3GameMode::StartScenarioPlayer(APlayerController* PC)
{
    auto* P=GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();auto* C=Cast<ALivingTownCafeWorldV3Controller>(PC);
    if(!C||C->GetPawn()||!P||!P->IsPrepared()||(PersonaRequestResult==ELivingTownCafePersonaRequestResult::Pending&&PendingController.Get()==C))return;
    FString Choice=TEXT("ben"),Error;FParse::Value(FCommandLine::Get(),TEXT("CafeWorldPersona="),Choice);
    if(Choice!=TEXT("aria")&&Choice!=TEXT("ben")){UE_LOG(LogTemp,Error,TEXT("Exact authored cafe persona aria or ben required"));return;}
    if(RequestPersona(C,Choice==TEXT("aria")?ELivingTownCafeWorldPersona::Aria:ELivingTownCafeWorldPersona::Ben,Error)==ELivingTownCafePersonaRequestResult::Refused)
        UE_LOG(LogTemp,Error,TEXT("World v3 persona start refused: %s"),*Error);
}
bool ALivingTownCafeWorldV3GameMode::ValidatePersonaSelection(ALivingTownCafeWorldV3Controller* PC,ELivingTownCafeWorldPersona Persona,FString& Error)const
{
    Error.Reset();auto* W=GetWorld();auto* P=W?W->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;
    if(!IsInGameThread()||bEndingPlay||!W||!IsValid(PC)||PC!=W->GetFirstPlayerController()||W->GetNetMode()!=NM_Standalone||!P||!P->IsPrepared()||
       (Persona!=ELivingTownCafeWorldPersona::Aria&&Persona!=ELivingTownCafeWorldPersona::Ben))
    {Error=TEXT("owned_standalone_authored_persona_selection_required");return false;}
    return true;
}
void ALivingTownCafeWorldV3GameMode::CancelPendingPersonaRequest(bool bReleaseReadyPreload)
{
    const bool bWasPending=PersonaRequestResult==ELivingTownCafePersonaRequestResult::Pending;
    ++PersonaSelectionEpoch;PendingController.Reset();PendingDescriptorSha256.Empty();PersonaRequestResult=ELivingTownCafePersonaRequestResult::Refused;
    if(MetaHumanPreload&&(bWasPending||bReleaseReadyPreload))MetaHumanPreload->Reset();
}
ELivingTownCafePersonaRequestResult ALivingTownCafeWorldV3GameMode::RequestPersona(ALivingTownCafeWorldV3Controller* PC,ELivingTownCafeWorldPersona Persona,FString& Error)
{
    // Invalidate an earlier completion even when selecting the already-current Aria.
    if(!IsInGameThread()){Error=TEXT("owned_standalone_authored_persona_selection_required");return ELivingTownCafePersonaRequestResult::Refused;}
    if(!ValidatePersonaSelection(PC,Persona,Error))return ELivingTownCafePersonaRequestResult::Refused;
    CancelPendingPersonaRequest(Persona!=ELivingTownCafeWorldPersona::Ben);
    const auto& B=GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>()->GetBinding();
    if((PC->bAuthorized&&PC->Persona==Persona&&IsValid(PC->GetPawn()))||Persona!=ELivingTownCafeWorldPersona::Ben||!B.MetaHumanActor.IsSet())
    {
        PersonaRequestResult=SelectPersonaImmediate(PC,Persona,Error)?ELivingTownCafePersonaRequestResult::Selected:ELivingTownCafePersonaRequestResult::Refused;
        return PersonaRequestResult;
    }
    if(!MetaHumanPreload)
    {
        MetaHumanPreload=NewObject<ULivingTownMetaHumanVisualPreload>(this);
        AddInstanceComponent(MetaHumanPreload);MetaHumanPreload->RegisterComponent();
    }
    if(!MetaHumanPreload->IsRegistered()||MetaHumanPreload->GetOwner()!=this)
    {Error=TEXT("metahuman_owned_preload_component_required");return PersonaRequestResult;}
    if(MetaHumanPreload->IsReadyFor(B.MetaHumanActor.GetValue()))
    {
        PersonaRequestResult=SelectPersonaImmediate(PC,Persona,Error)?ELivingTownCafePersonaRequestResult::Selected:ELivingTownCafePersonaRequestResult::Refused;
        return PersonaRequestResult;
    }
    // Failed loads are explicitly retryable; an older pending handle was already
    // cancelled above. A ready identity is never discarded on a Ben retry.
    MetaHumanPreload->Reset();
    PendingController=PC;PendingDescriptorSha256=B.MetaHumanActor->DescriptorSha256;PersonaRequestResult=ELivingTownCafePersonaRequestResult::Pending;
    PC->OperationNotice=TEXT("Loading Ben's complete character. Your current resident remains active.");
    const uint64 E=PersonaSelectionEpoch;TWeakObjectPtr<ALivingTownCafeWorldV3GameMode> Weak(this);
    const auto State=MetaHumanPreload->Request(B.MetaHumanActor.GetValue(),FSimpleDelegate::CreateLambda([Weak,E]()
    {if(auto* Self=Weak.Get())Self->CompletePersonaRequest(E);}),Error);
    // Also handles immediate failure or already-loaded completion without committing twice.
    if(State!=ELivingTownMetaHumanPreloadState::Pending&&PersonaRequestResult==ELivingTownCafePersonaRequestResult::Pending)CompletePersonaRequest(E);
    if(PersonaRequestResult==ELivingTownCafePersonaRequestResult::Refused&&Error.IsEmpty())Error=TEXT("metahuman_persona_preload_or_selection_refused");
    return PersonaRequestResult;
}
void ALivingTownCafeWorldV3GameMode::CompletePersonaRequest(uint64 ExpectedEpoch)
{
    if(!IsInGameThread()||bEndingPlay||ExpectedEpoch!=PersonaSelectionEpoch||PersonaRequestResult!=ELivingTownCafePersonaRequestResult::Pending)return;
    auto* PC=PendingController.Get();FString Error;
    auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;
    if(!ValidatePersonaSelection(PC,ELivingTownCafeWorldPersona::Ben,Error)||!P->GetBinding().MetaHumanActor.IsSet()||
       P->GetBinding().MetaHumanActor->DescriptorSha256!=PendingDescriptorSha256||!MetaHumanPreload||!MetaHumanPreload->IsReadyFor(P->GetBinding().MetaHumanActor.GetValue()))
    {
        PersonaRequestResult=ELivingTownCafePersonaRequestResult::Refused;PendingController.Reset();PendingDescriptorSha256.Empty();
        if(PC)PC->OperationNotice=TEXT("Unable to load Ben. Your current resident remains active.");return;
    }
    PendingController.Reset();PendingDescriptorSha256.Empty();
    const bool bSelected=SelectPersonaImmediate(PC,ELivingTownCafeWorldPersona::Ben,Error);
    PersonaRequestResult=bSelected?ELivingTownCafePersonaRequestResult::Selected:ELivingTownCafePersonaRequestResult::Refused;
    PC->OperationNotice=bSelected?TEXT("Playing Ben."):TEXT("Unable to select Ben. Your current resident remains active.");
    if(!bSelected)UE_LOG(LogTemp,Warning,TEXT("World v3 prepared persona refused: %s"),*Error);
}
bool ALivingTownCafeWorldV3GameMode::SelectPersona(ALivingTownCafeWorldV3Controller* PC,ELivingTownCafeWorldPersona Persona,FString& Error)
{
    if(!IsInGameThread()){Error=TEXT("owned_standalone_authored_persona_selection_required");return false;}
    if(!ValidatePersonaSelection(PC,Persona,Error))return false;
    CancelPendingPersonaRequest(Persona!=ELivingTownCafeWorldPersona::Ben);
    const bool bSelected=SelectPersonaImmediate(PC,Persona,Error);
    PersonaRequestResult=bSelected?ELivingTownCafePersonaRequestResult::Selected:ELivingTownCafePersonaRequestResult::Refused;return bSelected;
}
bool ALivingTownCafeWorldV3GameMode::SelectPersonaImmediate(ALivingTownCafeWorldV3Controller* PC,ELivingTownCafeWorldPersona Persona,FString& Error)
{
    if(!ValidatePersonaSelection(PC,Persona,Error))return false;
    auto* P=GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();const auto& B=P->GetBinding();
    if(PC->bAuthorized&&PC->Persona==Persona&&IsValid(PC->GetPawn()))
    {
        if(B.MetaHumanActor.IsSet()&&Persona==ELivingTownCafeWorldPersona::Ben)
        {
            const auto* Current=Cast<ALivingTownCafeCharacter>(PC->GetPawn());
            if(!Current||!Current->HasQualifiedVisual()||!Current->HasMetaHumanVisual())
            {Error=TEXT("current_metahuman_persona_visual_lost");return false;}
        }
        return true;
    }
    if(Persona==ELivingTownCafeWorldPersona::Ben&&B.MetaHumanActor.IsSet()&&(!MetaHumanPreload||!MetaHumanPreload->IsReadyFor(B.MetaHumanActor.GetValue())))
    {Error=TEXT("metahuman_persona_preload_required");return false;}
    // Ordinary families keep their existing synchronous lifecycle. The opt-in
    // complete actor validates a candidate while the previous authority stays live.
    const bool bTransactional=B.MetaHumanActor.IsSet();
    if(bTransactional&&P->GetPresentation().bMealActive)
    {Error=TEXT("metahuman_persona_switch_requires_no_active_meal");return false;}
    TWeakObjectPtr<APawn> OldPawn=PC->GetPawn();TWeakObjectPtr<AActor> OldView=PC->GetViewTarget();
    const bool bOldAuthorized=PC->bAuthorized;const auto OldPersona=PC->Persona;const FRotator OldControl=PC->GetControlRotation();
    if(!bTransactional)
    {P->DetachNativeSession();PC->bAuthorized=false;if(OldPawn.IsValid()){PC->UnPossess();OldPawn->Destroy();}}
    const FTransform Spawn(B.SpawnRotation,B.SpawnFeetCm+FVector(0,0,B.CapsuleHalfHeightCm));ACharacter* Pawn=nullptr;bool bFinishedSpawning=false;
    if(Persona==ELivingTownCafeWorldPersona::Ben)
    {
        auto* Ben=GetWorld()->SpawnActorDeferred<ALivingTownCafeCharacter>(ALivingTownCafeCharacter::StaticClass(),Spawn,nullptr,nullptr,ESpawnActorCollisionHandlingMethod::AlwaysSpawn);
        // A complete child actor may BeginPlay only after its native parent.
        // The SDK's normal component setup must precede holder validation.
        if(Ben&&B.MetaHumanActor.IsSet()){Ben->FinishSpawning(Spawn);bFinishedSpawning=true;}
        if(!Ben||!Ben->ConfigureQualifiedBen(B,Error)){if(Ben)Ben->Destroy();return false;}Pawn=Ben;
    }
    else
    {
        auto* OwnerPawn=GetWorld()->SpawnActorDeferred<ALivingTownCafePropertyOwnerProxy>(ALivingTownCafePropertyOwnerProxy::StaticClass(),Spawn,nullptr,nullptr,ESpawnActorCollisionHandlingMethod::AlwaysSpawn);
        if(!OwnerPawn||!OwnerPawn->ConfigureFunctionalOwner(B,Error)){if(OwnerPawn)OwnerPawn->Destroy();return false;}Pawn=OwnerPawn;
    }
    if(!bFinishedSpawning)Pawn->FinishSpawning(Spawn);
    const auto* Ben=Cast<ALivingTownCafeCharacter>(Pawn);const auto* OwnerCandidate=Cast<ALivingTownCafePropertyOwnerProxy>(Pawn);
    if(bTransactional&&(!IsValid(Pawn)||(Persona==ELivingTownCafeWorldPersona::Ben?(!Ben||!Ben->HasQualifiedVisual()||!Ben->HasMetaHumanVisual()):(!OwnerCandidate||!OwnerCandidate->IsFunctionalOwnerConfigured()))))
    {if(IsValid(Pawn))Pawn->Destroy();Error=TEXT("finished_persona_candidate_visual_required");return false;}
    FCollisionQueryParams Q(SCENE_QUERY_STAT(WorldV3PersonaSpawn),true);Q.AddIgnoredActor(Pawn);
    if(bTransactional&&OldPawn.IsValid())Q.AddIgnoredActor(OldPawn.Get());
    if(GetWorld()->OverlapBlockingTestByChannel(Pawn->GetActorLocation(),FQuat::Identity,ECC_Pawn,FCollisionShape::MakeCapsule(B.CapsuleRadiusCm,B.CapsuleHalfHeightCm),Q))
    {Pawn->Destroy();Error=TEXT("actual_persona_spawn_capsule_overlap");return false;}
    // Do not cancel paired authority to attempt a visual switch: Bind publishes
    // only after validation, with any current physical meal already excluded.
    if(bTransactional&&P->GetPresentation().bMealActive)
    {Pawn->Destroy();Error=TEXT("metahuman_persona_switch_requires_no_active_meal");return false;}
    auto* FullTown=GetWorld()->GetSubsystem<ULivingTownFullTownStreamingSubsystem>();
    const bool bTownBoot=FullTown&&FullTown->IsBootPossessionPending();
    if(FullTown&&!FullTown->BeforeQualifiedPossess(PC,Error)){Pawn->Destroy();return false;}
    PC->Possess(Pawn);
    const bool bTownPossessed=!FullTown||FullTown->AfterQualifiedPossess(PC,Pawn,Error);
    PC->SetViewTarget(Pawn);PC->SetControlRotation(B.SpawnRotation);PC->Persona=Persona;PC->bAuthorized=PC->GetPawn()==Pawn;
    if(!bTownPossessed||!PC->bAuthorized||!P->BindNativeSession(PC,Pawn,Error))
    {
        const FString SelectionError=Error.IsEmpty()?TEXT("actual_persona_possession_required"):Error;
        PC->bAuthorized=false;if(PC->GetPawn()==Pawn)PC->UnPossess();Pawn->Destroy();
        if(bTransactional)
        {
            PC->Persona=OldPersona;PC->SetControlRotation(OldControl);
            if(OldPawn.IsValid())
            {
                PC->Possess(OldPawn.Get());PC->bAuthorized=bOldAuthorized&&PC->GetPawn()==OldPawn.Get();
                PC->SetViewTarget(OldView.IsValid()?OldView.Get():OldPawn.Get());
                FString RestoreError;auto* Previous=Cast<ACharacter>(OldPawn.Get());
                if(PC->bAuthorized&&(!Previous||!P->BindNativeSession(PC,Previous,RestoreError)))
                {PC->bAuthorized=false;UE_LOG(LogTemp,Error,TEXT("World v3 old persona session restore refused: %s"),*RestoreError);}
            }
            else if(OldView.IsValid())PC->SetViewTarget(OldView.Get());
        }
        if(bTownBoot)FullTown->RequestSafeStop();
        Error=SelectionError;return false;
    }
    if(bTransactional&&OldPawn.IsValid())OldPawn->Destroy();return true;
}
ALivingTownCafeWorldV3Controller::ALivingTownCafeWorldV3Controller(){bAutoManageActiveCameraTarget=false;}
void ALivingTownCafeWorldV3Controller::BeginPlay(){Super::BeginPlay();bShowMouseCursor=false;SetInputMode(FInputModeGameOnly());if(PlayerCameraManager){PlayerCameraManager->ViewPitchMin=-55;PlayerCameraManager->ViewPitchMax=25;}}
void ALivingTownCafeWorldV3Controller::SetupInputComponent(){
    Super::SetupInputComponent();check(InputComponent);
    // Disable only stock debug commands that conflict with this controller's
    // advertised keys, on this live PlayerInput object (never config/CDOs).
    if(PlayerInput&&PlayerInput->GetOuter()==this)for(FKeyBind& Bind:PlayerInput->DebugExecBindings){
        const bool Modifiers=!Bind.Control&&!Bind.Shift&&!Bind.Alt&&!Bind.Cmd&&!Bind.bIgnoreCtrl&&!Bind.bIgnoreAlt&&!Bind.bIgnoreCmd;
        const bool F1=Bind.Key==EKeys::F1&&Bind.bIgnoreShift&&Bind.Command==TEXT("viewmode wireframe");
        const bool Other=!Bind.bIgnoreShift&&((Bind.Key==EKeys::F2&&Bind.Command==TEXT("viewmode unlit"))||(Bind.Key==EKeys::F5&&Bind.Command==TEXT("viewmode shadercomplexity"))||(Bind.Key==EKeys::F9&&Bind.Command==TEXT("shot showui")));
        if(Modifiers&&(F1||Other))Bind.bDisabled=true;
    }
    InputComponent->BindKey(EKeys::F1,IE_Pressed,this,&ALivingTownCafeWorldV3Controller::SelectAria);InputComponent->BindKey(EKeys::F2,IE_Pressed,this,&ALivingTownCafeWorldV3Controller::SelectBen);
    InputComponent->BindKey(EKeys::E,IE_Pressed,this,&ALivingTownCafeWorldV3Controller::Eat);InputComponent->BindKey(EKeys::X,IE_Pressed,this,&ALivingTownCafeWorldV3Controller::Cancel);
    InputComponent->BindKey(EKeys::O,IE_Pressed,this,&ALivingTownCafeWorldV3Controller::OfferSale);InputComponent->BindKey(EKeys::L,IE_Pressed,this,&ALivingTownCafeWorldV3Controller::OfferLease);InputComponent->BindKey(EKeys::B,IE_Pressed,this,&ALivingTownCafeWorldV3Controller::Buy);InputComponent->BindKey(EKeys::K,IE_Pressed,this,&ALivingTownCafeWorldV3Controller::Lease);InputComponent->BindKey(EKeys::R,IE_Pressed,this,&ALivingTownCafeWorldV3Controller::EndLease);
    InputComponent->BindKey(EKeys::N,IE_Pressed,this,&ALivingTownCafeWorldV3Controller::OfferRecurringLease);
    InputComponent->BindKey(EKeys::F5,IE_Pressed,this,&ALivingTownCafeWorldV3Controller::Save);InputComponent->BindKey(EKeys::F9,IE_Pressed,this,&ALivingTownCafeWorldV3Controller::Load);
    InputComponent->BindKey(EKeys::I,IE_Pressed,this,&ALivingTownCafeWorldV3Controller::ImportOlderSave);
    InputComponent->BindKey(EKeys::H,IE_Pressed,this,&ALivingTownCafeWorldV3Controller::ToggleControls);
}
void ALivingTownCafeWorldV3Controller::ToggleControls(){SetControlsVisible(!AreControlsVisible());}
void ALivingTownCafeWorldV3Controller::SelectAria(){FString Error;auto* G=GetWorld()?GetWorld()->GetAuthGameMode<ALivingTownCafeWorldV3GameMode>():nullptr;const auto R=G?G->RequestPersona(this,ELivingTownCafeWorldPersona::Aria,Error):ELivingTownCafePersonaRequestResult::Refused;OperationNotice=R==ELivingTownCafePersonaRequestResult::Selected?TEXT("Playing Aria."):R==ELivingTownCafePersonaRequestResult::Pending?TEXT("Loading Aria. Your current resident remains active."):TEXT("Unable to select Aria.");}
void ALivingTownCafeWorldV3Controller::SelectBen(){FString Error;auto* G=GetWorld()?GetWorld()->GetAuthGameMode<ALivingTownCafeWorldV3GameMode>():nullptr;const auto R=G?G->RequestPersona(this,ELivingTownCafeWorldPersona::Ben,Error):ELivingTownCafePersonaRequestResult::Refused;OperationNotice=R==ELivingTownCafePersonaRequestResult::Selected?TEXT("Playing Ben."):R==ELivingTownCafePersonaRequestResult::Pending?TEXT("Loading Ben's complete character. Your current resident remains active."):TEXT("Unable to select Ben.");}
FLivingTownCafeWorldReceipt ALivingTownCafeWorldV3Controller::RequestMeal(const FLivingTownCafeMealCommand& C){
    auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;FLivingTownCafeWorldReceipt R;
    if(P&&GetWorld()->GetFirstPlayerController()==this)R=P->SubmitMeal(C);else {R.Reason=TEXT("native_world_controller_required");R.Message=TEXT("The cafe is unavailable.");}OperationNotice=P&&P->GetPresentation().Notice==R.Message?FString():R.Message;return R;
}
FLivingTownCafeWorldReceipt ALivingTownCafeWorldV3Controller::RequestCancelMeal(){auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;FLivingTownCafeWorldReceipt R;if(P&&GetWorld()->GetFirstPlayerController()==this)R=P->CancelMeal();else R.Message=TEXT("The cafe is unavailable.");OperationNotice=P&&P->GetPresentation().Notice==R.Message?FString():R.Message;return R;}
void ALivingTownCafeWorldV3Controller::Eat(){auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;if(!P)return;FLivingTownCafeMealCommand C;C.RequestId=TEXT("ui/meal/")+FGuid::NewGuid().ToString(EGuidFormats::Digits);C.ExpectedRevision=P->GetPresentation().Revision;RequestMeal(C);}
void ALivingTownCafeWorldV3Controller::Cancel(){RequestCancelMeal();}
void ALivingTownCafeWorldV3Controller::Save(){FString Error;auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;OperationNotice=P&&P->SaveSlot(Error)?TEXT("Cafe saved."):TEXT("Unable to save the cafe.");}
void ALivingTownCafeWorldV3Controller::Load(){FString Error;auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;OperationNotice=P&&P->LoadSlot(Error)?TEXT("Cafe restored. Previous meals stay stopped; earned progress is kept."):TEXT("Unable to restore this cafe save.");}
void ALivingTownCafeWorldV3Controller::ImportOlderSave(){FString Error;auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;OperationNotice=P&&P->ImportLegacyV5Slot(Error)?TEXT("Previous cafe save imported."):TEXT("Unable to import this previous cafe save. Your current cafe is unchanged.");}
FLivingTownCafeWorldReceipt ALivingTownCafeWorldV3Controller::RequestRecurringLeaseOffer(const FString& RequestId){
    auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;FLivingTownCafeWorldReceipt R;
    if(P&&GetWorld()->GetFirstPlayerController()==this)R=P->SubmitRecurringLeaseOffer(RequestId);else R.Message=TEXT("The cafe is unavailable.");
    OperationNotice=P&&P->GetPresentation().Notice==R.Message?FString():R.Message;return R;
}
FLivingTownCafeWorldReceipt ALivingTownCafeWorldV3Controller::RequestLeaseAgreement(const FString& RequestId,bool bRecurring,int64 ObservedOfferRevision,int64 ObservedTitleRevision){
    auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;FLivingTownCafeWorldReceipt R;
    if(P&&GetWorld()->GetFirstPlayerController()==this)R=P->SubmitLeaseAgreement(RequestId,bRecurring,ObservedOfferRevision,ObservedTitleRevision);else R.Message=TEXT("The cafe is unavailable.");
    OperationNotice=P&&P->GetPresentation().Notice==R.Message?FString():R.Message;return R;
}
void ALivingTownCafeWorldV3Controller::SendProperty(ELivingTownCafePropertyAction A){auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;if(!P){OperationNotice=TEXT("The cafe is unavailable.");return;}FLivingTownCafePropertyCommand C;C.Action=A;C.RequestId=TEXT("ui/property/")+FGuid::NewGuid().ToString(EGuidFormats::Digits);const auto R=P->SubmitProperty(C);OperationNotice=P->GetPresentation().Notice==R.Message?FString():R.Message;}
void ALivingTownCafeWorldV3Controller::OfferSale(){SendProperty(ELivingTownCafePropertyAction::OfferSale);}void ALivingTownCafeWorldV3Controller::OfferLease(){SendProperty(ELivingTownCafePropertyAction::OfferLease);}
void ALivingTownCafeWorldV3Controller::OfferRecurringLease(){RequestRecurringLeaseOffer(TEXT("ui/recurring-offer/")+FGuid::NewGuid().ToString(EGuidFormats::Digits));}
void ALivingTownCafeWorldV3Controller::Buy(){SendProperty(ELivingTownCafePropertyAction::Buy);}
void ALivingTownCafeWorldV3Controller::Lease(){auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;if(!P)return;const auto View=P->GetPresentation();RequestLeaseAgreement(TEXT("ui/lease/")+FGuid::NewGuid().ToString(EGuidFormats::Digits),View.bRecurringOffer,View.bRecurringOffer?View.OfferRevision:-1,View.bRecurringOffer?View.OfferTitleRevision:-1);}
void ALivingTownCafeWorldV3Controller::EndLease(){SendProperty(ELivingTownCafePropertyAction::EndLease);}
TArray<FString> ALivingTownCafeWorldV3HUD::GetFeedbackRows()const{
    TArray<FString> Rows;const auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;
    if(!P)return Rows;
    const FString& AuthorityNotice=P->GetPresentation().Notice;Rows.Add(AuthorityNotice);
    const auto* PC=Cast<ALivingTownCafeWorldV3Controller>(PlayerOwner);
    if(PC&&!PC->GetOperationNotice().IsEmpty()&&PC->GetOperationNotice()!=AuthorityNotice)Rows.Add(TEXT("Last action: ")+PC->GetOperationNotice());
    return Rows;
}
bool ALivingTownCafeWorldV3HUD::IsCounterContextVisible()const{
    const auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;
    if(!P||!P->IsPrepared())return false;
    const auto& V=P->GetPresentation();
    return !V.bSessionReady||V.bMealActive||V.bReachable||V.Diagnostic==TEXT("face_the_counter")||V.Diagnostic==TEXT("counter_line_of_sight_blocked");
}
TArray<FString> ALivingTownCafeWorldV3HUD::GetControlRows()const{
    const auto* PC=Cast<ALivingTownCafeWorldV3Controller>(PlayerOwner);
    const bool Expanded=PC&&PC->AreControlsVisible();
    TArray<FString> Rows={Expanded?TEXT("H Hide controls"):TEXT("H Controls")};
    if(!Expanded)return Rows;
    Rows.Append({TEXT("CONTROLS"),TEXT("WASD Move"),TEXT("Mouse Look"),TEXT("F1 Aria  |  F2 Ben")});
    const auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;
    if(P&&P->IsPrepared()&&P->GetPresentation().bMealActive)Rows.Add(TEXT("X Cancel meal"));
    else if(P&&P->IsPrepared()&&P->GetPresentation().bMealAvailable)Rows.Add(TEXT("E Eat a meal"));
    else Rows.Add(TEXT("Meals unavailable"));
    Rows.Append({TEXT("PROPERTY"),TEXT("O Offer sale"),TEXT("L Fixed | N Recurring lease"),TEXT("B Buy  |  K Lease"),TEXT("R End lease"),TEXT("SAVE"),TEXT("F5 Save  |  F9 Load"),TEXT("I Import previous save")});
    return Rows;
}
void ALivingTownCafeWorldV3HUD::DrawHUD(){
    Super::DrawHUD();if(!Canvas||!GEngine||!GetWorld())return;
    auto* Font=GEngine->GetMediumFont();if(!Font)return;
    const auto* P=GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();
    // Two edge rails leave the middle 36% clear from head to feet. Font size
    // follows a readability breakpoint, never the length of a receipt string.
    const float Width=Canvas->ClipX,Height=Canvas->ClipY;
    if(Width<=0.f||Height<=0.f)return;
    const float Margin=FMath::Clamp(Width/64.f,10.f,24.f);
    const float Rail=FMath::Min(300.f,Width*.29f),Pad=Width<960.f?10.f:14.f,Gap=10.f;
    const float FontPixels=Width<960.f?14.f:16.f,Advance=FontPixels+4.f;
    const float TextScale=FontPixels/FMath::Max(1.f,float(Font->GetMaxCharHeight()));
    const FLinearColor Ink(.94f,.94f,.88f,1.f),Gold(.93f,.77f,.46f,1.f);
    const FLinearColor Muted(.78f,.83f,.80f,1.f),Panel(.035f,.058f,.062f,.88f);
    struct FHudLine { FString Text; FLinearColor Color; };
    const auto Measure=[&](const FString& Value){float W=0.f,H=0.f;GetTextSize(Value,W,H,Font,TextScale);return W;};
    const auto Wrap=[&](const FString& Value,float Available){
        TArray<FString> Lines,Paragraphs;Value.ParseIntoArray(Paragraphs,TEXT("\n"),false);
        for(const FString& Paragraph:Paragraphs){
            TArray<FString> Words;Paragraph.ParseIntoArrayWS(Words);
            FString Line;
            for(const FString& Word:Words){
                const FString Joined=Line.IsEmpty()?Word:Line+TEXT(" ")+Word;
                if(Measure(Joined)<=Available){Line=Joined;continue;}
                if(!Line.IsEmpty()){Lines.Add(Line);Line.Reset();}
                // A long token also wraps; no tiny-font escape hatch.
                for(TCHAR C:Word){
                    const FString Next=Line+FString::Chr(C);
                    if(!Line.IsEmpty()&&Measure(Next)>Available){Lines.Add(Line);Line.Reset();}
                    Line+=FString::Chr(C);
                }
            }
            if(!Line.IsEmpty())Lines.Add(Line);
        }
        if(Lines.IsEmpty())Lines.Add(TEXT(""));return Lines;
    };
    const auto Card=[&](float X,float Y,const TArray<FHudLine>& Rows,float AvailableHeight){
        if(AvailableHeight<2.f*Pad+Advance)return Y;
        TArray<FHudLine> Lines;
        for(const auto& Row:Rows)for(const auto& Line:Wrap(Row.Text,FMath::Max(1.f,Rail-2.f*Pad)))Lines.Add({Line,Row.Color});
        const int32 Limit=FMath::Max(1,FMath::FloorToInt((AvailableHeight-2.f*Pad)/Advance));
        if(Lines.Num()>Limit){Lines.SetNum(Limit);Lines.Last().Text=TEXT("...");}
        const float H=2.f*Pad+Advance*Lines.Num();DrawRect(Panel,X,Y,Rail,H);
        for(int32 I=0;I<Lines.Num();++I)DrawText(Lines[I].Text,Lines[I].Color,X+Pad,Y+Pad+I*Advance,Font,TextScale);
        return Y+H;
    };
    const float Left=Margin,Right=Width-Margin-Rail,Bottom=Height-Margin;
    TArray<FHudLine> Controls;
    for(const FString& Line:GetControlRows())Controls.Add({Line,Line==TEXT("CONTROLS")||Line==TEXT("PROPERTY")||Line==TEXT("SAVE")||Line.StartsWith(TEXT("H "))?Gold:Ink});
    const float ControlsBottom=Card(Right,Margin,Controls,Bottom-Margin);
    TArray<FHudLine> Status={{TEXT("LIVING TOWN / CAFE"),Gold}};
    if(!P||!P->IsPrepared()){
        Status.Add({TEXT("Cafe interaction is unavailable."),Ink});
        for(const FString& Line:GetFeedbackRows())if(!Line.IsEmpty())Status.Add({Line,Ink});
        Card(Left,Margin,Status,Bottom-Margin);return;
    }
    const auto& V=P->GetPresentation();
    const auto* PC=Cast<ALivingTownCafeWorldV3Controller>(PlayerOwner);
    const bool Nearby=IsCounterContextVisible();
    Status.Add({V.ResidentLabel,Ink});
    if(Nearby||(PC&&PC->AreControlsVisible())){
        Status.Add({V.PropertyLabel,Muted});Status.Add({V.ListingLabel,Gold});Status.Add({V.MealLabel,Ink});
    }
    const float StatusBottom=Card(Left,Margin,Status,Bottom-Margin);
    // Keep the live prompt and authority notice together, independently from
    // the controller's historical last-action result on the opposite rail.
    const auto Feedback=GetFeedbackRows();
    TArray<FHudLine> Interaction;
    if(Nearby){Interaction.Add({TEXT("NEARBY"),Gold});Interaction.Add({V.Prompt,Ink});}
    if(Feedback.Num()>0&&!Feedback[0].IsEmpty()){
        Interaction.Add({TEXT("CURRENT"),Gold});Interaction.Add({Feedback[0],Ink});
    }
    if(!Interaction.IsEmpty())Card(Left,StatusBottom+Gap,Interaction,Bottom-StatusBottom-Gap);
    if(Feedback.Num()>1){
        TArray<FHudLine> LastAction={{TEXT("LAST ACTION"),Gold},{Feedback[1],Ink}};
        Card(Right,ControlsBottom+Gap,LastAction,Bottom-ControlsBottom-Gap);
    }
}
