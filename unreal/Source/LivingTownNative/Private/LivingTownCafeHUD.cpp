#include "LivingTownCafeHUD.h"
#include "LivingTownCafeProjectionSubsystem.h"
#include "LivingTownCafePlayerController.h"
#include "Engine/Canvas.h"
#include "Engine/Font.h"
#include "Engine/Engine.h"
#include "Engine/World.h"

bool ALivingTownCafeHUD::IsCounterContextVisible()const
{
    const auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeProjectionSubsystem>():nullptr;
    return P&&(!P->GetPresentation().bReady||P->GetPresentation().bCounterNearby);
}
TArray<FString> ALivingTownCafeHUD::GetFeedbackRows()const
{
    const auto* P=GetWorld()?GetWorld()->GetSubsystem<ULivingTownCafeProjectionSubsystem>():nullptr;
    TArray<FString> Rows=P?P->GetPresentation().Feedback:TArray<FString>();
    const auto* Controller=Cast<ALivingTownCafePlayerController>(PlayerOwner);
    if(Controller&&!Controller->GetOperationNotice().IsEmpty())Rows.Add(TEXT("Last action: ")+Controller->GetOperationNotice());
    return Rows;
}
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

    const bool ShowPrompt=IsCounterContextVisible();
    const auto RawFeedback=GetFeedbackRows();
    // Operation failures may be longer than the cached live-status rows.
    // Measure only when content or actual draw metrics change, never each frame.
    const float FeedbackWidth=FMath::Min(670.f*Scale,Width-2.f*Margin)-34.f*Scale;
    const float FeedbackTextScale=.91f*TextScale;
    if(!bFeedbackLayoutCached||CachedFeedbackRows!=RawFeedback||CachedFeedbackWidth!=FeedbackWidth||CachedFeedbackTextScale!=FeedbackTextScale||CachedFeedbackFont.Get()!=Font){
        CachedFeedbackRows=RawFeedback;CachedFeedbackWidth=FeedbackWidth;CachedFeedbackTextScale=FeedbackTextScale;CachedFeedbackFont=Font;CachedWrappedFeedback.Reset();
        for(const FString& Row:RawFeedback){
            TArray<FString> Words;Row.ParseIntoArrayWS(Words);FString Line;
            for(const FString& Word:Words){
                const FString Joined=Line.IsEmpty()?Word:Line+TEXT(" ")+Word;float W=0.f,H=0.f;GetTextSize(Joined,W,H,Font,FeedbackTextScale);
                if(W<=FeedbackWidth){Line=Joined;continue;}
                if(!Line.IsEmpty()){CachedWrappedFeedback.Add(Line);Line.Reset();}
                for(TCHAR C:Word){
                    const FString Next=Line+FString::Chr(C);GetTextSize(Next,W,H,Font,FeedbackTextScale);
                    if(!Line.IsEmpty()&&W>FeedbackWidth){CachedWrappedFeedback.Add(Line);Line.Reset();}
                    Line+=FString::Chr(C);
                }
            }
            if(!Line.IsEmpty())CachedWrappedFeedback.Add(Line);
        }
        bFeedbackLayoutCached=true;
    }
    const auto& Feedback=CachedWrappedFeedback;
    const float LineHeight=22.f*Scale;
    const float PromptHeight=((ShowPrompt?52.f:26.f)+22.f*Feedback.Num())*Scale;
    const float PromptWidth=FMath::Min(670.f*Scale,Width-2.f*Margin);
    const float PromptX=(Width-PromptWidth)*.5f,PromptY=Height-Margin-27.f*Scale-PromptHeight;
    if(ShowPrompt||!Feedback.IsEmpty())
    {
        DrawRect(Panel,PromptX,PromptY,PromptWidth,PromptHeight);
        DrawRect(View.bReachable?Accent:Muted,PromptX,PromptY,PromptWidth,2.f*Scale);
        if(ShowPrompt)DrawText(View.Prompt,View.bReachable?Accent:Ink,PromptX+17.f*Scale,PromptY+13.f*Scale,Font,1.02f*TextScale);
        float FeedbackY=PromptY+(ShowPrompt?43.f:13.f)*Scale;
        for(const FString& Line:Feedback){DrawText(Line,Muted,PromptX+17.f*Scale,FeedbackY,Font,FeedbackTextScale);FeedbackY+=LineHeight;}
    }
    DrawRect(Panel,PromptX,Height-Margin-22.f*Scale,PromptWidth,32.f*Scale);
    DrawText(Controls,Muted,PromptX+8.f*Scale,Height-Margin-12.f*Scale,Font,TextScale);
    // The HUD composes cached presentation/history only. No collision queries,
    // authority mutations, JSON or file IO occur here.
}
