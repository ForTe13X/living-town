#include "LivingTownCafePropertyV2Scenario.h"
#include "LivingTownCafePropertyV2Subsystem.h"
#include "LivingTownCafeCharacter.h"
#include "Engine/World.h"
#include "Engine/Engine.h"
#include "Engine/Canvas.h"
#include "Engine/Font.h"
#include "Engine/StaticMesh.h"
#include "Components/StaticMeshComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/InputComponent.h"
#include "Camera/CameraComponent.h"
#include "Camera/PlayerCameraManager.h"
#include "GameFramework/SpringArmComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "InputCoreTypes.h"
#include "GameFramework/PlayerInput.h"

ALivingTownCafePropertyOwnerProxy::ALivingTownCafePropertyOwnerProxy(){
    bUseControllerRotationYaw=false;GetCharacterMovement()->bOrientRotationToMovement=true;GetCharacterMovement()->RotationRate=FRotator(0,480,0);GetMesh()->SetVisibility(false);
    CameraArm=CreateDefaultSubobject<USpringArmComponent>(TEXT("OwnerRoleCameraArm"));CameraArm->SetupAttachment(GetRootComponent());CameraArm->bUsePawnControlRotation=true;CameraArm->bDoCollisionTest=true;CameraArm->TargetOffset=FVector(0,0,45);
    Camera=CreateDefaultSubobject<UCameraComponent>(TEXT("OwnerRoleCamera"));Camera->SetupAttachment(CameraArm);Camera->bUsePawnControlRotation=false;
    FunctionalMarker=CreateDefaultSubobject<UStaticMeshComponent>(TEXT("FunctionalOwnerRoleMarker"));FunctionalMarker->SetupAttachment(GetRootComponent());FunctionalMarker->SetCollisionEnabled(ECollisionEnabled::NoCollision);FunctionalMarker->SetVisibility(false);
}
bool ALivingTownCafePropertyOwnerProxy::ConfigureFunctionalOwner(const FLivingTownCafeBinding& B,FString& Error){
    Error.Reset();if(bConfigured){Error=TEXT("owner_role_already_configured");return false;}auto* Marker=LoadObject<UStaticMesh>(nullptr,TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));if(!Marker){Error=TEXT("functional_role_marker_unavailable");return false;}
    GetCapsuleComponent()->SetCapsuleSize(B.CapsuleRadiusCm,B.CapsuleHalfHeightCm);GetCharacterMovement()->MaxWalkSpeed=B.WalkSpeedCmPerSecond;CameraArm->TargetArmLength=B.CameraArmCm;
    FunctionalMarker->SetStaticMesh(Marker);FunctionalMarker->SetRelativeScale3D(FVector(2*B.CapsuleRadiusCm/100.f,2*B.CapsuleRadiusCm/100.f,2*B.CapsuleHalfHeightCm/100.f));FunctionalMarker->SetVisibility(true);bConfigured=true;return true;
}
void ALivingTownCafePropertyOwnerProxy::Forward(float V){if(Controller&&V!=0)AddMovementInput(FRotationMatrix(FRotator(0,Controller->GetControlRotation().Yaw,0)).GetUnitAxis(EAxis::X),V);}
void ALivingTownCafePropertyOwnerProxy::Right(float V){if(Controller&&V!=0)AddMovementInput(FRotationMatrix(FRotator(0,Controller->GetControlRotation().Yaw,0)).GetUnitAxis(EAxis::Y),V);}
void ALivingTownCafePropertyOwnerProxy::Yaw(float V){AddControllerYawInput(V);}
void ALivingTownCafePropertyOwnerProxy::Pitch(float V){AddControllerPitchInput(V);}
void ALivingTownCafePropertyOwnerProxy::SetupPlayerInputComponent(UInputComponent* I){Super::SetupPlayerInputComponent(I);check(I);I->BindAxis(TEXT("CafeForward"),this,&ALivingTownCafePropertyOwnerProxy::Forward);I->BindAxis(TEXT("CafeRight"),this,&ALivingTownCafePropertyOwnerProxy::Right);I->BindAxis(TEXT("CafeYaw"),this,&ALivingTownCafePropertyOwnerProxy::Yaw);I->BindAxis(TEXT("CafePitch"),this,&ALivingTownCafePropertyOwnerProxy::Pitch);}

ALivingTownCafePropertyV2Controller::ALivingTownCafePropertyV2Controller(){bAutoManageActiveCameraTarget=false;}
void ALivingTownCafePropertyV2Controller::BeginPlay(){Super::BeginPlay();bShowMouseCursor=false;SetInputMode(FInputModeGameOnly());if(PlayerCameraManager){PlayerCameraManager->ViewPitchMin=-55;PlayerCameraManager->ViewPitchMax=25;}}
void ALivingTownCafePropertyV2Controller::SetupInputComponent(){Super::SetupInputComponent();check(InputComponent);
// Disable only the four stock debug commands that share advertised game
// shortcuts. This is this controller's live input object, never a CDO/config.
if(PlayerInput&&PlayerInput->GetOuter()==this){
    for(FKeyBind& Bind:PlayerInput->DebugExecBindings){
        const bool DefaultModifiers=!Bind.Control&&!Bind.Shift&&!Bind.Alt&&!Bind.Cmd&&!Bind.bIgnoreCtrl&&!Bind.bIgnoreAlt&&!Bind.bIgnoreCmd;
        const bool StockF1=Bind.Key==EKeys::F1&&Bind.bIgnoreShift&&Bind.Command.Equals(TEXT("viewmode wireframe"),ESearchCase::CaseSensitive);
        const bool StockOther=!Bind.bIgnoreShift&&(
            (Bind.Key==EKeys::F2&&Bind.Command.Equals(TEXT("viewmode unlit"),ESearchCase::CaseSensitive))||
            (Bind.Key==EKeys::F5&&Bind.Command.Equals(TEXT("viewmode shadercomplexity"),ESearchCase::CaseSensitive))||
            (Bind.Key==EKeys::F9&&Bind.Command.Equals(TEXT("shot showui"),ESearchCase::CaseSensitive)));
        if(DefaultModifiers&&(StockF1||StockOther))Bind.bDisabled=true;
    }
}
InputComponent->BindKey(EKeys::F1,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::SelectOwner);InputComponent->BindKey(EKeys::F2,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::SelectBuyer);InputComponent->BindKey(EKeys::O,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::OfferSale);InputComponent->BindKey(EKeys::L,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::OfferLease);InputComponent->BindKey(EKeys::B,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::Buy);InputComponent->BindKey(EKeys::E,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::Lease);InputComponent->BindKey(EKeys::R,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::EndLease);InputComponent->BindKey(EKeys::F5,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::Save);InputComponent->BindKey(EKeys::F9,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::Load);InputComponent->BindKey(EKeys::I,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::ToggleDetails);InputComponent->BindKey(EKeys::RightBracket,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::NextDetailsPage);InputComponent->BindKey(EKeys::LeftBracket,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::PreviousDetailsPage);}
void ALivingTownCafePropertyV2Controller::SelectOwner(){FString Error;auto* G=GetWorld()?GetWorld()->GetAuthGameMode<ALivingTownCafePropertyV2GameMode>():nullptr;OperationNotice=G&&G->SelectPersona(this,ELivingTownCafePropertyPersona::Aria,Error)?TEXT("Playing authored Aria owner role; walk from the source spawn."):TEXT("Owner selection refused: ")+Error;}
void ALivingTownCafePropertyV2Controller::SelectBuyer(){FString Error;auto* G=GetWorld()?GetWorld()->GetAuthGameMode<ALivingTownCafePropertyV2GameMode>():nullptr;OperationNotice=G&&G->SelectPersona(this,ELivingTownCafePropertyPersona::Ben,Error)?TEXT("Playing authored Ben buyer role; walk from the source spawn."):TEXT("Buyer selection refused: ")+Error;}
void ALivingTownCafePropertyV2Controller::Send(ELivingTownCafePropertyAction A){OperationNotice.Reset();auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafePropertyV2Subsystem>():nullptr;if(!P){OperationNotice=TEXT("Property v2 is unavailable in this scenario.");return;}FLivingTownCafePropertyCommand C;C.Action=A;C.RequestId=TEXT("ui/")+FGuid::NewGuid().ToString(EGuidFormats::Digits);const auto R=P->SubmitCommand(C);OperationNotice=R.bAccepted?TEXT("Recorded property action."):TEXT("Refused: ")+R.Reason;}
void ALivingTownCafePropertyV2Controller::OfferSale(){Send(ELivingTownCafePropertyAction::OfferSale);}void ALivingTownCafePropertyV2Controller::OfferLease(){Send(ELivingTownCafePropertyAction::OfferLease);}void ALivingTownCafePropertyV2Controller::Buy(){Send(ELivingTownCafePropertyAction::Buy);}void ALivingTownCafePropertyV2Controller::Lease(){Send(ELivingTownCafePropertyAction::Lease);}void ALivingTownCafePropertyV2Controller::EndLease(){Send(ELivingTownCafePropertyAction::EndLease);}
void ALivingTownCafePropertyV2Controller::Save(){FString Error;auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafePropertyV2Subsystem>():nullptr;OperationNotice=P&&P->SaveSlot(Error)?TEXT("Property title and ledger saved atomically."):TEXT("Save refused: ")+Error;}
void ALivingTownCafePropertyV2Controller::Load(){FString Error;auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafePropertyV2Subsystem>():nullptr;OperationNotice=P&&P->LoadSlot(Error)?TEXT("Property replay loaded; persona and position unchanged."):TEXT("Load refused: ")+Error;}

ALivingTownCafePropertyV2GameMode::ALivingTownCafePropertyV2GameMode(){DefaultPawnClass=nullptr;SpectatorClass=nullptr;PlayerControllerClass=ALivingTownCafePropertyV2Controller::StaticClass();HUDClass=ALivingTownCafePropertyV2HUD::StaticClass();bUseSeamlessTravel=false;}
APawn* ALivingTownCafePropertyV2GameMode::SpawnDefaultPawnAtTransform_Implementation(AController*,const FTransform&){return nullptr;}
void ALivingTownCafePropertyV2GameMode::StartPlay(){Super::StartPlay();FString Error;auto* P=GetWorld()->GetSubsystem<ULivingTownCafePropertyV2Subsystem>();if(!P||!P->PrepareScenario(Error)){UE_LOG(LogTemp,Error,TEXT("Property v2 scenario refused: %s"),*Error);return;}for(FConstPlayerControllerIterator It=GetWorld()->GetPlayerControllerIterator();It;++It)StartScenarioPlayer(It->Get());}
void ALivingTownCafePropertyV2GameMode::HandleStartingNewPlayer_Implementation(APlayerController* PC){Super::HandleStartingNewPlayer_Implementation(PC);StartScenarioPlayer(PC);}
void ALivingTownCafePropertyV2GameMode::StartScenarioPlayer(APlayerController* PC){auto* P=GetWorld()->GetSubsystem<ULivingTownCafePropertyV2Subsystem>();auto* C=Cast<ALivingTownCafePropertyV2Controller>(PC);if(!C||C->GetPawn()||!P||!P->IsPrepared())return;FString Choice=TEXT("aria"),Error;FParse::Value(FCommandLine::Get(),TEXT("CafePropertyPersona="),Choice);if(Choice!=TEXT("aria")&&Choice!=TEXT("ben")){UE_LOG(LogTemp,Error,TEXT("Exact authored cafe persona aria or ben required"));return;}if(!SelectPersona(C,Choice==TEXT("aria")?ELivingTownCafePropertyPersona::Aria:ELivingTownCafePropertyPersona::Ben,Error))UE_LOG(LogTemp,Error,TEXT("Property persona start refused: %s"),*Error);}
bool ALivingTownCafePropertyV2GameMode::SelectPersona(ALivingTownCafePropertyV2Controller* PC,ELivingTownCafePropertyPersona Persona,FString& Error){
    Error.Reset();auto* P=GetWorld()->GetSubsystem<ULivingTownCafePropertyV2Subsystem>();if(!IsInGameThread()||!PC||PC!=GetWorld()->GetFirstPlayerController()||GetWorld()->GetNetMode()!=NM_Standalone||!P||!P->IsPrepared()||(Persona!=ELivingTownCafePropertyPersona::Aria&&Persona!=ELivingTownCafePropertyPersona::Ben)){Error=TEXT("owned_standalone_authored_persona_selection_required");return false;}
    if(PC->bAuthorized&&PC->Persona==Persona&&PC->GetPawn())return true;
    P->DetachNativeSession();PC->bAuthorized=false;if(APawn* Old=PC->GetPawn()){PC->UnPossess();Old->Destroy();}
    const auto& B=P->GetBinding();const FTransform Spawn(B.SpawnRotation,B.SpawnFeetCm+FVector(0,0,B.CapsuleHalfHeightCm));ACharacter* Pawn=nullptr;
    if(Persona==ELivingTownCafePropertyPersona::Ben){auto* Ben=GetWorld()->SpawnActorDeferred<ALivingTownCafeCharacter>(ALivingTownCafeCharacter::StaticClass(),Spawn,nullptr,nullptr,ESpawnActorCollisionHandlingMethod::AlwaysSpawn);if(!Ben||!Ben->ConfigureQualifiedBen(B,Error)){if(Ben)Ben->Destroy();return false;}Pawn=Ben;}
    else {auto* OwnerPawn=GetWorld()->SpawnActorDeferred<ALivingTownCafePropertyOwnerProxy>(ALivingTownCafePropertyOwnerProxy::StaticClass(),Spawn,nullptr,nullptr,ESpawnActorCollisionHandlingMethod::AlwaysSpawn);if(!OwnerPawn||!OwnerPawn->ConfigureFunctionalOwner(B,Error)){if(OwnerPawn)OwnerPawn->Destroy();return false;}Pawn=OwnerPawn;}
    Pawn->FinishSpawning(Spawn);FCollisionQueryParams Q(SCENE_QUERY_STAT(PropertyV2PersonaSpawn),true);Q.AddIgnoredActor(Pawn);if(GetWorld()->OverlapBlockingTestByChannel(Pawn->GetActorLocation(),FQuat::Identity,ECC_Pawn,FCollisionShape::MakeCapsule(B.CapsuleRadiusCm,B.CapsuleHalfHeightCm),Q)){Pawn->Destroy();Error=TEXT("actual_persona_spawn_capsule_overlap");return false;}
    PC->Possess(Pawn);PC->SetViewTarget(Pawn);PC->SetControlRotation(B.SpawnRotation);PC->Persona=Persona;PC->bAuthorized=PC->GetPawn()==Pawn;
    if(!PC->bAuthorized||!P->BindNativeSession(PC,Pawn,Error)){PC->bAuthorized=false;PC->UnPossess();Pawn->Destroy();return false;}return true;
}

void ALivingTownCafePropertyV2Controller::ToggleDetails(){if(auto* H=Cast<ALivingTownCafePropertyV2HUD>(GetHUD()))H->ToggleDetails();}
void ALivingTownCafePropertyV2Controller::NextDetailsPage(){if(auto* H=Cast<ALivingTownCafePropertyV2HUD>(GetHUD()))H->NextDetailsPage();}
void ALivingTownCafePropertyV2Controller::PreviousDetailsPage(){if(auto* H=Cast<ALivingTownCafePropertyV2HUD>(GetHUD()))H->PreviousDetailsPage();}

namespace {
FString ReadableCafeNotice(const FString& Raw){
    if(Raw.IsEmpty()||Raw.StartsWith(TEXT("New-world property v2:"))||Raw.StartsWith(TEXT("Aria owner role selected."))||Raw.StartsWith(TEXT("Ben buyer role selected.")))return FString();
    if(Raw==TEXT("Recorded property action.")||Raw==TEXT("Property action recorded; balances and rights updated."))return TEXT("Property updated.");
    if(Raw==TEXT("Property title and ledger saved atomically."))return TEXT("Saved.");
    if(Raw.StartsWith(TEXT("Property replay loaded;"))||Raw.StartsWith(TEXT("Validated property journal loaded;")))return TEXT("Loaded. Your position is unchanged.");
    if(Raw.StartsWith(TEXT("Playing authored Aria"))||Raw.StartsWith(TEXT("Playing authored Ben")))return TEXT("Resident selected.");
    if(Raw.StartsWith(TEXT("Save refused:")))return TEXT("Save failed. Press I for details.");
    if(Raw.StartsWith(TEXT("Load refused:")))return TEXT("Load failed. Press I for details.");
    if(Raw.StartsWith(TEXT("Owner selection refused:"))||Raw.StartsWith(TEXT("Buyer selection refused:")))return TEXT("Resident selection failed. Press I for details.");
    FString Reason;
    if(Raw.StartsWith(TEXT("Refused: ")))Reason=Raw.Mid(9);
    else if(Raw.StartsWith(TEXT("Property action refused: ")))Reason=Raw.Mid(25);
    if(!Reason.IsEmpty()){
        FString Primary,Extra;
        if(Reason.Split(TEXT(" / "),&Primary,&Extra))Reason=Primary;
        if(Reason==TEXT("not_at_commercial_counter"))return TEXT("Visit the cafe counter to do that.");
        if(Reason==TEXT("not_owner"))return TEXT("Only the current owner can list the property.");
        if(Reason==TEXT("not_tenant"))return TEXT("Only the current tenant can end this lease.");
        if(Reason==TEXT("no_active_lease"))return TEXT("There is no active lease to end.");
        if(Reason==TEXT("lease_must_end_first"))return TEXT("The current lease must end first.");
        if(Reason==TEXT("self_transaction"))return TEXT("You already own this property.");
        if(Reason==TEXT("no_owner_offer"))return TEXT("The owner has no matching offer available.");
        if(Reason==TEXT("insufficient_funds"))return TEXT("You do not have enough coins.");
        return TEXT("Property action refused. Press I for details.");
    }
    return TEXT("Cafe status needs attention. Press I for details.");
}
}

void ALivingTownCafePropertyV2HUD::ToggleDetails(){bDetailsVisible=!bDetailsVisible;DetailsPage=0;}
void ALivingTownCafePropertyV2HUD::NextDetailsPage(){if(bDetailsVisible)DetailsPage=FMath::Min(DetailsPage+1,DetailsPageCount-1);}
void ALivingTownCafePropertyV2HUD::PreviousDetailsPage(){if(bDetailsVisible)DetailsPage=FMath::Max(0,DetailsPage-1);}

void ALivingTownCafePropertyV2HUD::DrawHUD(){
    Super::DrawHUD();
    if(!Canvas||!GEngine||!GetWorld())return;
    auto* Font=GEngine->GetMediumFont();if(!Font)return;
    const auto* P=GetWorld()->GetSubsystem<ULivingTownCafePropertyV2Subsystem>();
    static const FLivingTownCafePropertyView Unavailable=[](){
        FLivingTownCafePropertyView V;V.ResidentLabel=TEXT("No resident selected");V.PropertyLabel=TEXT("Property interaction unavailable");
        V.InteractionLabel=TEXT("Cafe interaction is unavailable. Press I for details.");V.bPresentationWarning=true;
        V.Prompt=TEXT("property_subsystem_missing");return V;
    }();
    const auto& V=P?P->GetPresentation():Unavailable;
    const auto* PC=Cast<ALivingTownCafePropertyV2Controller>(PlayerOwner);
    static const FString Empty;
    const FString& Operation=PC?PC->GetOperationNotice():Empty;
    // A current binding/scene warning must never display a previous success.
    // Prompt is the current observation; Notice/Operation may be historical.
    const FString& RawFeedback=V.bPresentationWarning?V.Prompt:(Operation.IsEmpty()?V.Notice:Operation);
    if(RawFeedback!=LastFeedback||bLastFeedbackWasWarning!=V.bPresentationWarning){
        LastFeedback=RawFeedback;bLastFeedbackWasWarning=V.bPresentationWarning;
        FriendlyFeedback=V.bPresentationWarning?V.InteractionLabel:ReadableCafeNotice(RawFeedback);
    }
    const float Scale=FMath::Clamp(FMath::Min(Canvas->ClipX/1280.f,Canvas->ClipY/720.f),.85f,2.f);
    const float Margin=18.f*Scale,Pad=14.f*Scale,Row=21.f*Scale;
    const float TextScale=14.f*Scale/FMath::Max(1.f,float(Font->GetMaxCharHeight()));
    const FLinearColor Ink(.94f,.94f,.88f,1),Muted(.72f,.79f,.76f,1),Accent(.93f,.77f,.46f,1),Warning(1.f,.71f,.48f,1),Panel(.035f,.058f,.062f,.88f);
    const auto Text=[&](const FString& Value,FLinearColor Color,float X,float Y,float MaxWidth,float Multiplier=1.f){
        if(Value.IsEmpty())return;
        float W=0,H=0;const float Wanted=TextScale*Multiplier;GetTextSize(Value,W,H,Font,Wanted);
        DrawText(Value,Color,X,Y,Font,W>MaxWidth?Wanted*MaxWidth/FMath::Max(W,1.f):Wanted);
    };
    const float CardWidth=FMath::Min(320.f*Scale,Canvas->ClipX-2*Margin),CardHeight=126.f*Scale;
    DrawRect(Panel,Margin,Margin,CardWidth,CardHeight);DrawRect(Accent,Margin,Margin,3.f*Scale,CardHeight);
    float Y=Margin+12.f*Scale;
    Text(TEXT("LIVING TOWN  /  CAFE"),Accent,Margin+Pad,Y,CardWidth-2*Pad,.92f);Y+=Row;
    Text(V.ResidentLabel,Ink,Margin+Pad,Y,CardWidth-2*Pad,1.13f);Y+=Row;
    Text(V.PropertyLabel,Muted,Margin+Pad,Y,CardWidth-2*Pad,.88f);Y+=Row;
    Text(V.ListingLabel,Accent,Margin+Pad,Y,CardWidth-2*Pad,.94f);Y+=Row;
    if(!V.bShowCounterHint)Text(V.InteractionLabel,V.bPresentationWarning?Warning:Muted,Margin+Pad,Y,CardWidth-2*Pad,.86f);

    static const FString Controls(TEXT("WASD Move  |  Mouse Look     F1 Aria  F2 Ben     [I] Details     F5 Save  F9 Load"));
    const float FooterHeight=28.f*Scale,FooterWidth=FMath::Min(800.f*Scale,Canvas->ClipX-2*Margin),FooterX=(Canvas->ClipX-FooterWidth)*.5f,FooterY=Canvas->ClipY-Margin-FooterHeight;
    DrawRect(Panel,FooterX,FooterY,FooterWidth,FooterHeight);
    Text(Controls,Muted,FooterX+Pad,FooterY+6.f*Scale,FooterWidth-2*Pad,.88f);
    const bool HasFeedback=!FriendlyFeedback.IsEmpty();
    const float ContextHeight=(V.bShowCounterHint?(HasFeedback?96.f:73.f):(HasFeedback?38.f:0.f))*Scale;
    if(ContextHeight>0){
        const float W=FMath::Min(600.f*Scale,Canvas->ClipX-2*Margin),X=(Canvas->ClipX-W)*.5f,Top=FooterY-8.f*Scale-ContextHeight;
        DrawRect(Panel,X,Top,W,ContextHeight);DrawRect(V.bReachable?Accent:Muted,X,Top,W,2.f*Scale);
        float LineY=Top+12.f*Scale;
        if(V.bShowCounterHint){
            Text(V.InteractionLabel,Accent,X+Pad,LineY,W-2*Pad,1.06f);LineY+=Row;
            Text(V.ActionHint,Ink,X+Pad,LineY,W-2*Pad);LineY+=Row+2.f*Scale;
        }
        if(HasFeedback)Text(FriendlyFeedback,Ink,X+Pad,LineY,W-2*Pad,.94f);
    }
    if(!bDetailsVisible)return;

    const float DetailWidth=FMath::Min(640.f*Scale,Canvas->ClipX-CardWidth-3*Margin),DetailX=Canvas->ClipX-Margin-DetailWidth;
    const float DetailHeight=Canvas->ClipY-2*Margin-FooterHeight-ContextHeight-16.f*Scale;
    const float DetailTextScale=TextScale*.91f,LineWidth=DetailWidth-2*Pad;
    if(CachedDetailsWidth!=LineWidth||CachedDetailsTextScale!=DetailTextScale||CachedSourceLines!=V.Lines||CachedPrompt!=V.Prompt||CachedNotice!=V.Notice||CachedOperation!=Operation){
        CachedDetailsWidth=LineWidth;CachedDetailsTextScale=DetailTextScale;CachedSourceLines=V.Lines;CachedPrompt=V.Prompt;CachedNotice=V.Notice;CachedOperation=Operation;
        CachedDetailLines.Reset();
        const auto Wrap=[&](const FString& Source){
            TArray<FString> Logical;Source.ParseIntoArrayLines(Logical,false);
            for(FString Remaining:Logical){
                while(!Remaining.IsEmpty()){
                    float W=0,H=0;GetTextSize(Remaining,W,H,Font,DetailTextScale);
                    int32 Break=Remaining.Len();
                    if(W>LineWidth){
                        int32 Low=1,High=Remaining.Len();
                        while(Low<High){const int32 Mid=(Low+High+1)/2;GetTextSize(Remaining.Left(Mid),W,H,Font,DetailTextScale);if(W<=LineWidth)Low=Mid;else High=Mid-1;}
                        Break=Low;
                        for(int32 I=Break-1;I>0;--I)if(FChar::IsWhitespace(Remaining[I])){Break=I;break;}
                    }
                    CachedDetailLines.Add(Remaining.Left(Break));Remaining=Remaining.Mid(Break);Remaining.TrimStartInline();
                }
            }
        };
        for(const FString& Line:V.Lines)Wrap(Line);
        Wrap(TEXT("Prompt: ")+V.Prompt);Wrap(TEXT("Status: ")+V.Notice);Wrap(TEXT("Last action: ")+Operation);
    }
    const int32 RowsPerPage=FMath::Max(1,FMath::FloorToInt((DetailHeight-72.f*Scale)/Row));
    DetailsPageCount=FMath::Max(1,FMath::DivideAndRoundUp(CachedDetailLines.Num(),RowsPerPage));DetailsPage=FMath::Clamp(DetailsPage,0,DetailsPageCount-1);
    DrawRect(Panel,DetailX,Margin,DetailWidth,DetailHeight);
    Text(TEXT("CAFE DETAILS  /  [I] CLOSE"),Accent,DetailX+Pad,Margin+12.f*Scale,LineWidth,.95f);
    Y=Margin+39.f*Scale;
    const int32 First=DetailsPage*RowsPerPage,End=FMath::Min(First+RowsPerPage,CachedDetailLines.Num());
    for(int32 I=First;I<End;++I){DrawText(CachedDetailLines[I],Muted,DetailX+Pad,Y,Font,DetailTextScale);Y+=Row;}
    const FString Page=FString::Printf(TEXT("[ / ]   |   Page %d of %d"),DetailsPage+1,DetailsPageCount);
    Text(Page,Accent,DetailX+Pad,Margin+DetailHeight-25.f*Scale,LineWidth,.88f);
    // Default HUD draws cached presentation strings only. Raw diagnostic wraps
    // are rebuilt only when their text, font scale or available width changes.
}
