#pragma once
#include "CoreMinimal.h"
#include "Subsystems/GameInstanceSubsystem.h"
#include "LivingTownLeaseSubsystem.generated.h"

// FString deliberately preserves the portable core's case-sensitive stable IDs.
USTRUCT(BlueprintType)
struct LIVINGTOWNNATIVE_API FLivingTownStableId
{
    GENERATED_BODY()
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Living Town") FString Value;
    FLivingTownStableId() = default;
    explicit FLivingTownStableId(const FString& InValue) : Value(InValue) {}
};

UENUM(BlueprintType)
enum class ELivingTownLeaseAction : uint8 { Lease, EndLease };

USTRUCT(BlueprintType)
struct LIVINGTOWNNATIVE_API FLivingTownLeaseCommand
{
    GENERATED_BODY()
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Living Town") FLivingTownStableId RequestId;
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Living Town") FLivingTownStableId PropertyId;
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Living Town") ELivingTownLeaseAction Action = ELivingTownLeaseAction::Lease;
};

USTRUCT(BlueprintType)
struct LIVINGTOWNNATIVE_API FLivingTownLeaseReceipt
{
    GENERATED_BODY()
    UPROPERTY(BlueprintReadOnly, Category="Living Town") bool bAccepted = false;
    UPROPERTY(BlueprintReadOnly, Category="Living Town") bool bAlreadyApplied = false;
    UPROPERTY(BlueprintReadOnly, Category="Living Town") FString Reason;
    UPROPERTY(BlueprintReadOnly, Category="Living Town") int64 EventId = -1;
};

USTRUCT(BlueprintType)
struct LIVINGTOWNNATIVE_API FLivingTownLeaseView
{
    GENERATED_BODY()
    UPROPERTY(BlueprintReadOnly, Category="Living Town") FLivingTownStableId OwnerId;
    UPROPERTY(BlueprintReadOnly, Category="Living Town") FLivingTownStableId OperatorId;
    UPROPERTY(BlueprintReadOnly, Category="Living Town") FLivingTownStableId SessionId;
    UPROPERTY(BlueprintReadOnly, Category="Living Town") int64 AriaCoins = 0;
    UPROPERTY(BlueprintReadOnly, Category="Living Town") int64 BenCoins = 0;
    UPROPERTY(BlueprintReadOnly, Category="Living Town") int64 Clock = 0;
    UPROPERTY(BlueprintReadOnly, Category="Living Town") int64 EventCount = 0;
    UPROPERTY(BlueprintReadOnly, Category="Living Town") FString JournalDigest;
};

// Native authority-only observation. It cannot be deserialized from a widget or
// client command. A future adapter must derive these from calibrated real actors.
struct FLivingTownTrustedInteraction
{
    FString SpaceId;
    FString FloorId;
    FString InteractionId;
    bool bWithinReach = false;
};

UCLASS()
class LIVINGTOWNNATIVE_API ULivingTownLeaseSubsystem final : public UGameInstanceSubsystem
{
    GENERATED_BODY()
public:
    ULivingTownLeaseSubsystem();
    virtual ~ULivingTownLeaseSubsystem() override;
    virtual void Deinitialize() override;

    // Intent carries no actor, amount, clock, owner or reach fields.
    UFUNCTION(BlueprintCallable, Category="Living Town|Cafe Pilot")
    FLivingTownLeaseReceipt SubmitCommand(const FLivingTownLeaseCommand& Command);
    UFUNCTION(BlueprintPure, Category="Living Town|Cafe Pilot")
    FLivingTownLeaseView GetLeaseView() const;
    UFUNCTION(BlueprintCallable, Category="Living Town|Cafe Pilot")
    bool SaveNewPilotJournal(FString& OutJson, FString& OutError) const;
    UFUNCTION(BlueprintCallable, Category="Living Town|Cafe Pilot")
    bool LoadNewPilotJournal(const FString& Json, FString& OutError);

    // C++ authority boundary; neither function is a reflected/UI entry point.
    using FInteractionResolver = TFunction<bool(FLivingTownTrustedInteraction&)>;
    void InstallTrustedInteractionResolver(FInteractionResolver Resolver);
    bool AdvanceTrustedClockTo(int64 NewTick, FString& OutError);
private:
    struct FState;
    // Generated UObject vtable constructors also instantiate member cleanup.
    // Keep deletion out-of-line so their TU never needs the private core type.
    struct FStateDeleter { void operator()(FState* Pointer) const; };
    TUniquePtr<FState, FStateDeleter> State;
    FInteractionResolver InteractionResolver;
};
