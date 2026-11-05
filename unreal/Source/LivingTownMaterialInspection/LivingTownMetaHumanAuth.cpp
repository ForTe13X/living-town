#include "LivingTownMetaHumanAuth.h"
#include "Cloud/MetaHumanServiceRequest.h"
#include "Editor.h"
#include "Async/Async.h"
#include "EditorConfigSubsystem.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Framework/Application/SlateApplication.h"
#include "Widgets/SWindow.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Text/STextBlock.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformMisc.h"
#include "HAL/PlatformProcess.h"
#include "Misc/Paths.h"
#include "Misc/App.h"
#include "HAL/PlatformTime.h"
#include <atomic>

namespace
{
    FString PrivateRoot;
    bool PrivateRootRegistered = false;
    TWeakPtr<SWindow> SignInWindow;
    std::atomic<bool> Checking{false};
    std::atomic<bool> Checked{false};
    std::atomic<bool> SignedIn{false};
    std::atomic<bool> LoginPending{false};
    std::atomic<int32> UserInitiatedAttempts{0};
    std::atomic<int32> NativeStatusChecks{0};
    std::atomic<int32> ButtonEvents{0};
    double RetryAfterSeconds = 0.;
    const TCHAR* LastAction = TEXT("NO_USER_ACTION");

    bool CanRequestSignIn()
    {
        return Checked.load() && !Checking.load() && !LoginPending.load() &&
            !SignedIn.load() && FPlatformTime::Seconds() >= RetryAfterSeconds;
    }

    bool OwnEditorContext()
    {
        return IsInGameThread() && GIsEditor && GEditor && !IsRunningCommandlet() &&
            !GEditor->PlayWorld && PrivateRootRegistered;
    }

    void RefreshNativeStatus()
    {
        bool Expected = false;
        if (!Checking.compare_exchange_strong(Expected, true)) return;
        ++NativeStatusChecks;
        using namespace UE::MetaHuman::ServiceAuthentication;
        CheckHasLoggedInUserAsync(FOnCheckHasLoggedInUserCompleteDelegate::CreateLambda(
            [](bool IsSignedIn, FString, FString)
            {
                // Account IDs and names are deliberately ignored and never serialized.
                SignedIn.store(IsSignedIn);
                Checked.store(true);
                Checking.store(false);
            }));
    }

    FString State(const TCHAR* Status)
    {
        auto Root = MakeShared<FJsonObject>();
        Root->SetStringField(TEXT("status"), Status);
        Root->SetNumberField(TEXT("owned_editor_pid"), FPlatformProcess::GetCurrentProcessId());
        Root->SetBoolField(TEXT("private_editor_config_registered"), PrivateRootRegistered);
        Root->SetStringField(TEXT("private_editor_config_root"), PrivateRoot);
        Root->SetBoolField(TEXT("launcher_open"), SignInWindow.IsValid());
        const TSharedPtr<SWindow> Window = SignInWindow.Pin();
        Root->SetBoolField(TEXT("launcher_widget_enabled"), Window.IsValid() && Window->IsEnabled());
        Root->SetBoolField(TEXT("launcher_active"), Window.IsValid() && Window->IsActive());
        Root->SetBoolField(TEXT("sign_in_button_enabled"), CanRequestSignIn());
        Root->SetBoolField(TEXT("process_unattended"), FApp::IsUnattended());
        Root->SetBoolField(TEXT("script_unattended"), GIsRunningUnattendedScript);
        Root->SetNumberField(TEXT("native_status_check_requests"), NativeStatusChecks.load());
        Root->SetNumberField(TEXT("button_events_received"), ButtonEvents.load());
        Root->SetStringField(TEXT("last_user_action_result"), LastAction);
        Root->SetBoolField(TEXT("status_read_is_passive"), true);
        Root->SetBoolField(TEXT("native_status_checked"), Checked.load());
        Root->SetBoolField(TEXT("native_status_check_pending"), Checking.load());
        Root->SetBoolField(TEXT("native_signed_in"), SignedIn.load());
        Root->SetBoolField(TEXT("login_pending"), LoginPending.load());
        Root->SetNumberField(TEXT("user_initiated_login_attempts"), UserInitiatedAttempts.load());
        Root->SetBoolField(TEXT("credentials_or_account_identifiers_emitted"), false);
        FString Result;
        FJsonSerializer::Serialize(Root, TJsonWriterFactory<>::Create(&Result));
        return Result;
    }

    FReply UserRequestedSignIn()
    {
        ++ButtonEvents;
        if (!OwnEditorContext()) { LastAction = TEXT("REFUSED_EDITOR_CONTEXT"); return FReply::Handled(); }
        if (!CanRequestSignIn()) { LastAction = TEXT("REFUSED_NOT_READY"); return FReply::Handled(); }
        bool Expected = false;
        if (!LoginPending.compare_exchange_strong(Expected, true)) return FReply::Handled();
        ++UserInitiatedAttempts;
        LastAction = TEXT("LOGIN_REQUESTED_BY_USER");
        using namespace UE::MetaHuman::ServiceAuthentication;
        LoginToAuthEnvironment(
            FOnLoginCompleteDelegate::CreateLambda([](FString)
            {
                AsyncTask(ENamedThreads::GameThread, []
                {
                    LoginPending.store(false);
                    LastAction = TEXT("LOGIN_COMPLETED");
                    RefreshNativeStatus();
                });
            }),
            FOnLoginFailedDelegate::CreateLambda([]()
            {
                AsyncTask(ENamedThreads::GameThread, []
                {
                    LoginPending.store(false);
                    SignedIn.store(false);
                    LastAction = TEXT("LOGIN_FAILED_MANUAL_RETRY_AFTER_30_SECONDS");
                    RetryAfterSeconds = FPlatformTime::Seconds() + 30.;
                });
            }));
        return FReply::Handled();
    }
}

void ULivingTownMetaHumanAuth::RegisterPrivateEditorConfig()
{
    const FString Requested = FPlatformMisc::GetEnvironmentVariable(TEXT("LT_EDITOR_JSON_CONFIG_DIR"));
    if (Requested.IsEmpty()) return;
    FString Root = FPaths::ConvertRelativePathToFull(Requested);
    FPaths::NormalizeDirectoryName(Root);
    if (!FPaths::CollapseRelativeDirectories(Root) ||
        !FPaths::IsUnderDirectory(Root, FPaths::ConvertRelativePathToFull(FPaths::ProjectDir())) ||
        (GEditor && GEditor->IsInitialized()) || !IFileManager::Get().DirectoryExists(*Root))
    {
        return;
    }
    UEditorConfigSubsystem::EarlyAddSearchDirectory(UEditorConfigSubsystem::ESearchDirectoryType::User, Root);
    PrivateRoot = Root;
    PrivateRootRegistered = true;
}

FString ULivingTownMetaHumanAuth::OpenSignInLauncher()
{
    if (!OwnEditorContext() || !FSlateApplication::IsInitialized()) return State(TEXT("REFUSED_EDITOR_CONTEXT"));
    if (SignInWindow.IsValid()) return State(TEXT("EXISTING_OWNED_SIGN_IN_LAUNCHER"));
    RefreshNativeStatus();
    TSharedRef<SWindow> Window = SNew(SWindow)
        .Title(FText::FromString(TEXT("Living Town - MetaHuman sign-in")))
        .ClientSize(FVector2D(540, 210)).SupportsMaximize(false).SupportsMinimize(false)
        [
            SNew(SBox).Padding(20)
            [
                SNew(SVerticalBox)
                + SVerticalBox::Slot().AutoHeight().Padding(0, 0, 0, 16)
                [ SNew(STextBlock).AutoWrapText(true).Text(FText::FromString(
                    TEXT("Connect this Editor to Epic's MetaHuman service. The button opens Epic's official browser sign-in. Complete authentication yourself; this launcher does not collect credentials."))) ]
                + SVerticalBox::Slot().AutoHeight().Padding(0, 0, 0, 16)
                [ SNew(SButton).Text(FText::FromString(TEXT("Sign in to MetaHuman")))
                    .IsEnabled_Lambda([] { return CanRequestSignIn(); })
                    .OnClicked(FOnClicked::CreateStatic(&UserRequestedSignIn)) ]
                + SVerticalBox::Slot().AutoHeight()
                [ SNew(STextBlock).Text_Lambda([]
                    {
                        return FText::FromString(SignedIn.load() ? TEXT("Native MetaHuman service: signed in") :
                            LoginPending.load() ? TEXT("Waiting for Epic browser authorization...") :
                            Checking.load() ? TEXT("Checking existing MetaHuman session once...") :
                            FPlatformTime::Seconds() < RetryAfterSeconds ? TEXT("Login failed. Wait 30 seconds before a manual retry.") :
                            TEXT("Native MetaHuman service: awaiting sign-in"));
                    }) ]
            ]
        ];
    SignInWindow = Window;
    FSlateApplication::Get().AddWindow(Window);
    return State(TEXT("OPENED_OWNED_SIGN_IN_LAUNCHER"));
}

FString ULivingTownMetaHumanAuth::ReadSignInState()
{
    if (!OwnEditorContext()) return State(TEXT("REFUSED_EDITOR_CONTEXT"));
    // A read must never initiate persistent login or generate network traffic.
    return State(TEXT("READ_NATIVE_METAHUMAN_SIGN_IN_STATE"));
}

FString ULivingTownMetaHumanAuth::CloseSignInLauncher()
{
    if (!OwnEditorContext()) return State(TEXT("REFUSED_EDITOR_CONTEXT"));
    if (TSharedPtr<SWindow> Window = SignInWindow.Pin()) Window->RequestDestroyWindow();
    SignInWindow.Reset();
    return State(TEXT("CLOSED_OWNED_SIGN_IN_LAUNCHER"));
}
