#include "LivingTownCafeWorldV3Scenario.h"
#include "LivingTownCafeWorldV3Subsystem.h"
#include "LivingTownCafePropertyV2Scenario.h"
#include "LivingTownCafeCharacter.h"
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
void ALivingTownCafeWorldV3GameMode::StartScenarioPlayer(APlayerController* PC){auto* P=GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();auto* C=Cast<ALivingTownCafeWorldV3Controller>(PC);if(!C||C->GetPawn()||!P||!P->IsPrepared())return;FString Choice=TEXT("ben"),Error;FParse::Value(FCommandLine::Get(),TEXT("CafeWorldPersona="),Choice);if(Choice!=TEXT("aria")&&Choice!=TEXT("ben")){UE_LOG(LogTemp,Error,TEXT("Exact authored cafe persona aria or ben required"));return;}if(!SelectPersona(C,Choice==TEXT("aria")?ELivingTownCafeWorldPersona::Aria:ELivingTownCafeWorldPersona::Ben,Error))UE_LOG(LogTemp,Error,TEXT("World v3 persona start refused: %s"),*Error);}
bool ALivingTownCafeWorldV3GameMode::SelectPersona(ALivingTownCafeWorldV3Controller* PC,ELivingTownCafeWorldPersona Persona,FString& Error){
    Error.Reset();auto* P=GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();if(!IsInGameThread()||!PC||PC!=GetWorld()->GetFirstPlayerController()||GetWorld()->GetNetMode()!=NM_Standalone||!P||!P->IsPrepared()||(Persona!=ELivingTownCafeWorldPersona::Aria&&Persona!=ELivingTownCafeWorldPersona::Ben)){Error=TEXT("owned_standalone_authored_persona_selection_required");return false;}
    if(PC->bAuthorized&&PC->Persona==Persona&&PC->GetPawn())return true;
    P->DetachNativeSession();PC->bAuthorized=false;if(APawn* Old=PC->GetPawn()){PC->UnPossess();Old->Destroy();}
    const auto& B=P->GetBinding();const FTransform Spawn(B.SpawnRotation,B.SpawnFeetCm+FVector(0,0,B.CapsuleHalfHeightCm));ACharacter* Pawn=nullptr;
    if(Persona==ELivingTownCafeWorldPersona::Ben){auto* Ben=GetWorld()->SpawnActorDeferred<ALivingTownCafeCharacter>(ALivingTownCafeCharacter::StaticClass(),Spawn,nullptr,nullptr,ESpawnActorCollisionHandlingMethod::AlwaysSpawn);if(!Ben||!Ben->ConfigureQualifiedBen(B,Error)){if(Ben)Ben->Destroy();return false;}Pawn=Ben;}
    else {auto* OwnerPawn=GetWorld()->SpawnActorDeferred<ALivingTownCafePropertyOwnerProxy>(ALivingTownCafePropertyOwnerProxy::StaticClass(),Spawn,nullptr,nullptr,ESpawnActorCollisionHandlingMethod::AlwaysSpawn);if(!OwnerPawn||!OwnerPawn->ConfigureFunctionalOwner(B,Error)){if(OwnerPawn)OwnerPawn->Destroy();return false;}Pawn=OwnerPawn;}
    Pawn->FinishSpawning(Spawn);FCollisionQueryParams Q(SCENE_QUERY_STAT(WorldV3PersonaSpawn),true);Q.AddIgnoredActor(Pawn);if(GetWorld()->OverlapBlockingTestByChannel(Pawn->GetActorLocation(),FQuat::Identity,ECC_Pawn,FCollisionShape::MakeCapsule(B.CapsuleRadiusCm,B.CapsuleHalfHeightCm),Q)){Pawn->Destroy();Error=TEXT("actual_persona_spawn_capsule_overlap");return false;}
    PC->Possess(Pawn);PC->SetViewTarget(Pawn);PC->SetControlRotation(B.SpawnRotation);PC->Persona=Persona;PC->bAuthorized=PC->GetPawn()==Pawn;
    if(!PC->bAuthorized||!P->BindNativeSession(PC,Pawn,Error)){PC->bAuthorized=false;PC->UnPossess();Pawn->Destroy();return false;}return true;
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
    InputComponent->BindKey(EKeys::F5,IE_Pressed,this,&ALivingTownCafeWorldV3Controller::Save);InputComponent->BindKey(EKeys::F9,IE_Pressed,this,&ALivingTownCafeWorldV3Controller::Load);
}
void ALivingTownCafeWorldV3Controller::SelectAria(){FString Error;auto* G=GetWorld()?GetWorld()->GetAuthGameMode<ALivingTownCafeWorldV3GameMode>():nullptr;OperationNotice=G&&G->SelectPersona(this,ELivingTownCafeWorldPersona::Aria,Error)?TEXT("Playing Aria."):TEXT("Unable to select Aria.");}
void ALivingTownCafeWorldV3Controller::SelectBen(){FString Error;auto* G=GetWorld()?GetWorld()->GetAuthGameMode<ALivingTownCafeWorldV3GameMode>():nullptr;OperationNotice=G&&G->SelectPersona(this,ELivingTownCafeWorldPersona::Ben,Error)?TEXT("Playing Ben."):TEXT("Unable to select Ben.");}
FLivingTownCafeWorldReceipt ALivingTownCafeWorldV3Controller::RequestMeal(const FLivingTownCafeMealCommand& C){
    auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;FLivingTownCafeWorldReceipt R;
    if(P&&GetWorld()->GetFirstPlayerController()==this)R=P->SubmitMeal(C);else {R.Reason=TEXT("native_world_controller_required");R.Message=TEXT("The cafe is unavailable.");}OperationNotice=P&&P->GetPresentation().Notice==R.Message?FString():R.Message;return R;
}
FLivingTownCafeWorldReceipt ALivingTownCafeWorldV3Controller::RequestCancelMeal(){auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;FLivingTownCafeWorldReceipt R;if(P&&GetWorld()->GetFirstPlayerController()==this)R=P->CancelMeal();else R.Message=TEXT("The cafe is unavailable.");OperationNotice=P&&P->GetPresentation().Notice==R.Message?FString():R.Message;return R;}
void ALivingTownCafeWorldV3Controller::Eat(){auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;if(!P)return;FLivingTownCafeMealCommand C;C.RequestId=TEXT("ui/meal/")+FGuid::NewGuid().ToString(EGuidFormats::Digits);C.ExpectedRevision=P->GetPresentation().Revision;RequestMeal(C);}
void ALivingTownCafeWorldV3Controller::Cancel(){RequestCancelMeal();}
void ALivingTownCafeWorldV3Controller::Save(){FString Error;auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;OperationNotice=P&&P->SaveSlot(Error)?TEXT("Cafe saved."):TEXT("Unable to save the cafe.");}
void ALivingTownCafeWorldV3Controller::Load(){FString Error;auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;OperationNotice=P&&P->LoadSlot(Error)?TEXT("Cafe restored. Previous meals stay stopped; earned progress is kept."):TEXT("Unable to restore this cafe save.");}
void ALivingTownCafeWorldV3Controller::SendProperty(ELivingTownCafePropertyAction A){auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;if(!P){OperationNotice=TEXT("The cafe is unavailable.");return;}FLivingTownCafePropertyCommand C;C.Action=A;C.RequestId=TEXT("ui/property/")+FGuid::NewGuid().ToString(EGuidFormats::Digits);const auto R=P->SubmitProperty(C);OperationNotice=P->GetPresentation().Notice==R.Message?FString():R.Message;}
void ALivingTownCafeWorldV3Controller::OfferSale(){SendProperty(ELivingTownCafePropertyAction::OfferSale);}void ALivingTownCafeWorldV3Controller::OfferLease(){SendProperty(ELivingTownCafePropertyAction::OfferLease);}void ALivingTownCafeWorldV3Controller::Buy(){SendProperty(ELivingTownCafePropertyAction::Buy);}void ALivingTownCafeWorldV3Controller::Lease(){SendProperty(ELivingTownCafePropertyAction::Lease);}void ALivingTownCafeWorldV3Controller::EndLease(){SendProperty(ELivingTownCafePropertyAction::EndLease);}
TArray<FString> ALivingTownCafeWorldV3HUD::GetFeedbackRows()const{
    TArray<FString> Rows;const auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>():nullptr;
    if(!P||!P->IsPrepared())return Rows;
    const FString& AuthorityNotice=P->GetPresentation().Notice;Rows.Add(AuthorityNotice);
    const auto* PC=Cast<ALivingTownCafeWorldV3Controller>(PlayerOwner);
    if(PC&&!PC->GetOperationNotice().IsEmpty()&&PC->GetOperationNotice()!=AuthorityNotice)Rows.Add(TEXT("Last action: ")+PC->GetOperationNotice());
    return Rows;
}
void ALivingTownCafeWorldV3HUD::DrawHUD(){
    Super::DrawHUD();if(!Canvas||!GEngine||!GetWorld())return;auto* Font=GEngine->GetMediumFont();if(!Font)return;
    const auto* P=GetWorld()->GetSubsystem<ULivingTownCafeWorldV3Subsystem>();
    const float S=FMath::Clamp(FMath::Min(Canvas->ClipX/1280.f,Canvas->ClipY/720.f),.75f,1.75f),X=18*S,Pad=14*S,W=FMath::Min(640*S,Canvas->ClipX-2*X),Row=25*S;
    const float TextScale=16*S/FMath::Max(1.f,float(Font->GetMaxCharHeight()));
    const FLinearColor Ink(.94f,.94f,.88f,1.f),Gold(.93f,.77f,.46f,1.f),Panel(.035f,.058f,.062f,.9f);
    const auto Line=[&](const FString& Value,float Y,FLinearColor Color){float TW=0,TH=0;GetTextSize(Value,TW,TH,Font,TextScale);DrawText(Value,Color,X+Pad,Y,Font,TW>W-2*Pad?TextScale*(W-2*Pad)/TW:TextScale);};
    DrawRect(Panel,X,X,W,9*Row);Line(TEXT("LIVING TOWN  /  CAFE"),X+Pad,Gold);
    if(!P||!P->IsPrepared()){Line(TEXT("Cafe interaction is unavailable."),X+Pad+Row,Ink);return;}
    const auto& V=P->GetPresentation();Line(V.ResidentLabel,X+Pad+Row,Ink);Line(V.PropertyLabel,X+Pad+2*Row,Ink);Line(V.ListingLabel,X+Pad+3*Row,Gold);Line(V.MealLabel,X+Pad+4*Row,Gold);Line(V.Prompt,X+Pad+5*Row,Ink);
    // Preserve the live authority notice and prompt. Historical controller
    // feedback remains independently visible, including F5 away from the counter.
    const auto Feedback=GetFeedbackRows();for(int32 I=0;I<Feedback.Num();++I)Line(Feedback[I],X+Pad+(6+I)*Row,Ink);
    const float Footer=Canvas->ClipY-X-2*Row;DrawRect(Panel,X,Footer,W,2*Row);
    Line(TEXT("WASD Move | Mouse Look | F1 Aria | F2 Ben | E Eat | X Cancel"),Footer+5*S,Ink);
    Line(TEXT("O Sell offer | L Lease offer | B Buy | K Lease | R End | F5 Save | F9 Load"),Footer+Row,Ink);
}
