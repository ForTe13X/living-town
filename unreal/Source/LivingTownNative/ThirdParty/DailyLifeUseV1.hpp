#pragma once
// Portable C++17: one resident's care-action progression only.
// No money, inventory, clock source, Unreal calls, persistence parser or animation.
// The future sole WorldV3 authority must issue a grant and commit this state together
// with reservation/stock/payment/events. Never expose ApprovedUse/Contact to UI.
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace living_town::daily_life_use_v1 {
using Tick = std::int64_t;
constexpr Tick max_tick = 9007199254740991LL;
constexpr std::size_t max_requests = 1024;
constexpr int full = 10000; // hundredths of the authored 0..100 needs scale
enum class Kind { Eat, Sleep, WashFace };
struct Rule { int duration, gain; };
inline std::optional<Rule> rule(Kind kind) {
    switch (kind) {
    case Kind::Eat: return Rule{18,5000};
    case Kind::Sleep: return Rule{40,6200};
    case Kind::WashFace: return Rule{6,1800};
    }
    return {};
}
inline bool token(const std::string& s) {
    if (s.empty() || s.size()>128) return false;
    for (unsigned char c:s)
        if (!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||
              c=='_'||c=='/'||c=='.'||c==':'||c=='-')) return false;
    return true;
}
struct Needs { int hunger=7200, energy=7200, hygiene=7200; };
// This is a trusted internal grant, not a player command or loadable capability.
// grant_event_id identifies a real accepted WorldV3 use-grant event, never a UI ID.
struct ApprovedUse {
    std::string request_id, resident_id, site_id, grant_id;
    Kind kind=Kind::Eat;
    Tick tick=0, grant_event_id=-1;
};
struct Contact {
    std::string resident_id, site_id, grant_id;
    bool freshly_observed=false, grounded=false, reachable=false;
    bool permission_valid=false, reservation_valid=false;
};
struct ActiveUse { ApprovedUse grant; int elapsed=0; };
enum class Outcome { TickOnly, Progress, Completed, Interrupted, RejectedTick };
struct BeginReceipt { bool accepted=false, already_applied=false; std::string reason; };
struct RequestRecord { ApprovedUse grant; BeginReceipt receipt; };
inline bool same_request(const ApprovedUse& a,const ApprovedUse& b) {
    // tick is the immutable authority-event tick, not the caller current clock.
    // Replay presents the original grant unchanged; no new use is acquired.
    return a.request_id==b.request_id && a.resident_id==b.resident_id &&
           a.site_id==b.site_id && a.grant_id==b.grant_id && a.kind==b.kind &&
           a.grant_event_id==b.grant_event_id && a.tick==b.tick;
}
class ResidentUse {
    std::string resident_;
    Tick tick_=0;
    Needs needs_;
    std::optional<ActiveUse> active_;
    std::vector<RequestRecord> requests_;
    static int& value(Needs& needs,Kind kind) {
        if (kind==Kind::Eat) return needs.hunger;
        if (kind==Kind::Sleep) return needs.energy;
        return needs.hygiene;
    }
    bool contact_ok(const Contact& c)const {
        return active_ && c.resident_id==resident_ &&
            c.site_id==active_->grant.site_id && c.grant_id==active_->grant.grant_id &&
            c.freshly_observed && c.grounded && c.reachable &&
            c.permission_valid && c.reservation_valid;
    }
public:
    explicit ResidentUse(std::string resident):resident_(std::move(resident)) {}
    Tick tick()const{return tick_;}
    const Needs& needs()const{return needs_;}
    const std::optional<ActiveUse>& active()const{return active_;}
    const std::vector<RequestRecord>& requests()const{return requests_;}
    BeginReceipt begin(const ApprovedUse& grant) {
        if (!token(resident_) || grant.resident_id!=resident_ ||
            !token(grant.request_id)||!token(grant.site_id)||!token(grant.grant_id)||
            !rule(grant.kind)||grant.grant_event_id<1)
            return {false,false,"invalid_authority_grant"};
        for (const auto& old:requests_) if(old.grant.request_id==grant.request_id) {
            if (!same_request(old.grant,grant)) return {false,false,"request_id_conflict"};
            auto receipt=old.receipt;receipt.already_applied=true;return receipt;
        }
        for (const auto& old:requests_) if(old.grant.grant_id==grant.grant_id)
            return {false,false,"grant_already_consumed"};
        // Only a NEW grant must begin on the current authority tick. An accepted
        // original grant remains replayable after progress, completion or cancel.
        if (grant.tick<0 || grant.tick>max_tick || grant.tick!=tick_)
            return {false,false,"invalid_authority_grant"};
        if (active_) return {false,false,"resident_busy"};
        if (requests_.size()>=max_requests) return {false,false,"request_capacity"};
        BeginReceipt receipt{true,false,"started"};
        requests_.push_back({grant,receipt});active_=ActiveUse{grant,0};return receipt;
    }
    // Exactly one observed authority tick. A long frame may not fabricate repeated
    // contact samples: the UE wrapper must interrupt use before any gap catch-up.
    Outcome advance_one(Tick next,const Contact& contact) {
        if (tick_>=max_tick || next!=tick_+1) return Outcome::RejectedTick;
        tick_=next;
        needs_.hunger=std::max(0,needs_.hunger-28);
        needs_.energy=std::max(0,needs_.energy-18);
        needs_.hygiene=std::max(0,needs_.hygiene-11);
        if (!active_) return Outcome::TickOnly;
        if (!contact_ok(contact)) {active_.reset();return Outcome::Interrupted;}
        const auto r=*rule(active_->grant.kind);const int old=active_->elapsed;
        const int now=old+1;
        // Integer remainder distribution gives exactly the authored total benefit
        // before 0..100 clamping, without per-frame floating-point accumulation.
        const int increment=(r.gain*now)/r.duration-(r.gain*old)/r.duration;
        int& need=value(needs_,active_->grant.kind);need=std::min(full,need+increment);
        active_->elapsed=now;
        if (now==r.duration) {active_.reset();return Outcome::Completed;}
        return Outcome::Progress;
    }
    bool cancel() {const bool had=active_.has_value();active_.reset();return had;}
    // Called only after an enclosing validated WorldV3 load. Recovered journal
    // data never grants current spatial access, possession, or old reservations.
    bool invalidate_use_after_load() {return cancel();}
};
} // namespace living_town::daily_life_use_v1
