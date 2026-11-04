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
    TArray<FHudLine> Controls={
        {TEXT("CONTROLS"),Gold},{TEXT("WASD Move"),Ink},{TEXT("Mouse Look"),Ink},
        {TEXT("F1 Aria  |  F2 Ben"),Ink},{TEXT("E Eat  |  X Cancel"),Ink},
        {TEXT("PROPERTY"),Gold},{TEXT("O Offer sale"),Ink},{TEXT("L Offer lease"),Ink},
        {TEXT("B Buy  |  K Lease"),Ink},{TEXT("R End lease"),Ink},
        {TEXT("SAVE"),Gold},{TEXT("F5 Save  |  F9 Load"),Ink}};
    const float ControlsBottom=Card(Right,Margin,Controls,Bottom-Margin);
    TArray<FHudLine> Status={{TEXT("LIVING TOWN / CAFE"),Gold}};
    if(!P||!P->IsPrepared()){
        Status.Add({TEXT("Cafe interaction is unavailable."),Ink});Card(Left,Margin,Status,Bottom-Margin);return;
    }
    const auto& V=P->GetPresentation();
    Status.Add({V.ResidentLabel,Ink});Status.Add({V.PropertyLabel,Muted});
    Status.Add({V.ListingLabel,Gold});Status.Add({V.MealLabel,Ink});
    const float StatusBottom=Card(Left,Margin,Status,Bottom-Margin);
    // Keep the live prompt and authority notice together, independently from
    // the controller's historical last-action result on the opposite rail.
    const auto Feedback=GetFeedbackRows();
    TArray<FHudLine> Interaction={{TEXT("NEARBY"),Gold},{V.Prompt,Ink}};
    if(Feedback.Num()>0&&!Feedback[0].IsEmpty()){
        Interaction.Add({TEXT("CURRENT"),Gold});Interaction.Add({Feedback[0],Ink});
    }
    Card(Left,StatusBottom+Gap,Interaction,Bottom-StatusBottom-Gap);
    if(Feedback.Num()>1){
        TArray<FHudLine> LastAction={{TEXT("LAST ACTION"),Gold},{Feedback[1],Ink}};
        Card(Right,ControlsBottom+Gap,LastAction,Bottom-ControlsBottom-Gap);
    }
}
