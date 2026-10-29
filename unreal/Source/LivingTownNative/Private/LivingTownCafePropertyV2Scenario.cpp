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

void ALivingTownCafePropertyV2Controller::BeginPlay(){Super::BeginPlay();bShowMouseCursor=false;SetInputMode(FInputModeGameOnly());if(PlayerCameraManager){PlayerCameraManager->ViewPitchMin=-55;PlayerCameraManager->ViewPitchMax=25;}}
void ALivingTownCafePropertyV2Controller::SetupInputComponent(){Super::SetupInputComponent();check(InputComponent);InputComponent->BindKey(EKeys::F1,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::SelectOwner);InputComponent->BindKey(EKeys::F2,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::SelectBuyer);InputComponent->BindKey(EKeys::O,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::OfferSale);InputComponent->BindKey(EKeys::L,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::OfferLease);InputComponent->BindKey(EKeys::B,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::Buy);InputComponent->BindKey(EKeys::E,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::Lease);InputComponent->BindKey(EKeys::R,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::EndLease);InputComponent->BindKey(EKeys::F5,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::Save);InputComponent->BindKey(EKeys::F9,IE_Pressed,this,&ALivingTownCafePropertyV2Controller::Load);}
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

void ALivingTownCafePropertyV2HUD::DrawHUD(){
    Super::DrawHUD();if(!Canvas||!GEngine||!GetWorld())return;const auto* P=GetWorld()->GetSubsystem<ULivingTownCafePropertyV2Subsystem>();if(!P)return;const auto& V=P->GetPresentation();auto* Font=GEngine->GetMediumFont();if(!Font)return;const float Scale=FMath::Clamp(Canvas->ClipY/900.f,.75f,1.3f),TextScale=FMath::Max(Scale,14.f/FMath::Max(1.f,float(Font->GetMaxCharHeight())));const float Margin=24*Scale,Width=FMath::Min(760*Scale,Canvas->ClipX-2*Margin);const FLinearColor Ink(.94f,.94f,.88f,1),Muted(.70f,.77f,.74f,1),Accent(.95f,.77f,.42f,1),Panel(.025f,.038f,.041f,.88f);
    DrawRect(Panel,Margin,Margin,Width,(54+24*V.Lines.Num())*Scale);float Y=Margin+14*Scale;DrawText(TEXT("LIVING TOWN / CAFE PROPERTY"),Accent,Margin+14*Scale,Y,Font,TextScale);Y+=30*Scale;for(const auto& Line:V.Lines){DrawText(Line,Ink,Margin+14*Scale,Y,Font,.86f*TextScale);Y+=24*Scale;}
    const float Bottom=Canvas->ClipY-136*Scale;DrawRect(Panel,Margin,Bottom,Width,112*Scale);DrawText(V.Prompt,V.bReachable?Accent:Ink,Margin+14*Scale,Bottom+12*Scale,Font,.85f*TextScale);DrawText(V.Notice,Muted,Margin+14*Scale,Bottom+37*Scale,Font,.83f*TextScale);const auto* PC=Cast<ALivingTownCafePropertyV2Controller>(PlayerOwner);if(PC)DrawText(PC->GetOperationNotice(),Ink,Margin+14*Scale,Bottom+60*Scale,Font,.83f*TextScale);DrawText(TEXT("WASD / mouse | F1 Aria owner | F2 Ben buyer | F5 save | F9 load"),Muted,Margin+14*Scale,Bottom+86*Scale,Font,.80f*TextScale);
}
