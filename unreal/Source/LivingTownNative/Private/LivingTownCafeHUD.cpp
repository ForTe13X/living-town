#include "LivingTownCafeHUD.h"
#include "LivingTownCafeProjectionSubsystem.h"
#include "LivingTownCafePlayerController.h"
#include "Engine/Canvas.h"
#include "Engine/Font.h"
#include "Engine/Engine.h"
#include "Engine/World.h"

void ALivingTownCafeHUD::DrawHUD()
{
    Super::DrawHUD();
    if(!Canvas||!GEngine||!GetWorld())return;
    const auto* Projection=GetWorld()->GetSubsystem<ULivingTownCafeProjectionSubsystem>();
    if(!Projection)return;
    const auto& View=Projection->GetPresentation();
    UFont* Font=GEngine->GetMediumFont();
    static const FString Title(TEXT("LIVING TOWN  /  CAFE"));
    static const FString Controls(TEXT("WASD Move  |  Mouse Look  |  F5 Save ledger  |  F9 Load ledger"));
    const float Scale=FMath::Clamp(Canvas->ClipY/900.f,.75f,1.3f);
    const float TextScale=FMath::Max(Scale,14.f/FMath::Max(1.f,float(Font->GetMaxCharHeight())));
    const float Margin=24.f*Scale,Width=Canvas->ClipX,Height=Canvas->ClipY;
    const FLinearColor Ink(.94f,.94f,.88f,1.f),Muted(.70f,.77f,.74f,1.f),Accent(.95f,.77f,.42f,1.f),Panel(.025f,.038f,.041f,.88f);
    const float CardWidth=FMath::Min(376.f*Scale,Width-2.f*Margin);
    DrawRect(Panel,Margin,Margin,CardWidth,127.f*Scale);
    DrawRect(Accent,Margin,Margin,3.f*Scale,127.f*Scale);
    DrawText(Title,Accent,Margin+18.f*Scale,Margin+13.f*Scale,Font,TextScale);
    DrawText(View.Resident,Ink,Margin+18.f*Scale,Margin+44.f*Scale,Font,1.08f*TextScale);
    DrawText(View.Stewardship,Muted,Margin+18.f*Scale,Margin+77.f*Scale,Font,.91f*TextScale);
    DrawText(View.Offer,Ink,Margin+18.f*Scale,Margin+99.f*Scale,Font,.91f*TextScale);

    const auto* Controller=Cast<ALivingTownCafePlayerController>(PlayerOwner);
    const bool HasNotice=Controller&&!Controller->GetOperationNotice().IsEmpty();
    const float LineHeight=22.f*Scale;
    const float FeedbackRows=HasNotice?1.f:float(View.Feedback.Num());
    const float PromptHeight=(52.f+22.f*FeedbackRows)*Scale;
    const float PromptWidth=FMath::Min(670.f*Scale,Width-2.f*Margin);
    const float PromptX=(Width-PromptWidth)*.5f,PromptY=Height-Margin-27.f*Scale-PromptHeight;
    DrawRect(Panel,PromptX,PromptY,PromptWidth,PromptHeight);
    DrawRect(View.bReachable?Accent:Muted,PromptX,PromptY,PromptWidth,2.f*Scale);
    DrawText(View.Prompt,View.bReachable?Accent:Ink,PromptX+17.f*Scale,PromptY+13.f*Scale,Font,1.02f*TextScale);
    float FeedbackY=PromptY+43.f*Scale;
    if(HasNotice)DrawText(Controller->GetOperationNotice(),Ink,PromptX+17.f*Scale,FeedbackY,Font,.91f*TextScale);
    else for(const FString& Line:View.Feedback){DrawText(Line,Muted,PromptX+17.f*Scale,FeedbackY,Font,.91f*TextScale);FeedbackY+=LineHeight;}
    DrawText(Controls,Muted,PromptX+8.f*Scale,Height-Margin-12.f*Scale,Font,.85f*TextScale);
    // Canvas receives only cached strings. No collision, authority reads,
    // JSON, file IO, wrapping or display-string construction occurs here.
}
