#pragma once
// Portable C++17: one resident's care-action progression only.
// No money, inventory, clock source, Unreal calls or animation.
// The future sole WorldV3 authority must issue a grant and commit this state together
// with reservation/stock/payment/events. Never expose ApprovedUse/Contact to UI.
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <initializer_list>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace living_town::daily_life_use_v1 {
using Tick = std::int64_t;
constexpr Tick max_tick = 9007199254740991LL;
constexpr std::size_t max_requests = 1024;
// At most one Begin, forty observed ticks, one terminal cancellation and two
// idle boundaries per accepted request. Adjacent inactive ticks coalesce.
constexpr std::size_t max_history = max_requests*44+1;
inline constexpr const char* journal_schema="LivingTown.DailyLifeUse";
inline constexpr const char* journal_version="2"; // first durable format; includes meal fun
constexpr int full = 10000; // hundredths of the authored 0..100 needs scale
enum class Kind { Eat, Sleep, WashFace };
struct Rule { int duration, gain; int fun_gain=0; };
inline std::optional<Rule> rule(Kind kind) {
    switch (kind) {
    case Kind::Eat: return Rule{18,5000,300};
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
// Fun has no newly invented passive decay. Only the authored meal +3 is added.
struct Needs { int hunger=7200, energy=7200, hygiene=7200, fun=7200; };
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
enum class End { Active, Completed, Cancelled, Interrupted, AfterLoad };
struct RequestRecord {
    ApprovedUse grant; BeginReceipt receipt;
    int progressed_ticks=0;
    End end=End::Active;
    Tick end_tick=-1;
};
enum class Op { Begin, Advance, IdleTo, Cancel, AfterLoad, Interrupt };
struct Transition {
    Op op=Op::IdleTo;
    Tick tick=0;
    std::optional<ApprovedUse> grant;
    std::optional<Contact> contact;
};
// A replayable logical history plus redundant caches. It records the trusted
// observations supplied to this primitive, not proof of native contact/animation.
struct Journal {
    std::string schema=journal_schema, version=journal_version, resident;
    Tick tick=0;
    Needs needs;
    std::optional<ActiveUse> active;
    std::vector<RequestRecord> requests;
    std::vector<Transition> history;
};
inline bool same_request(const ApprovedUse& a,const ApprovedUse& b) {
    // tick is the immutable authority-event tick, not the caller current clock.
    // Replay presents the original grant unchanged; no new use is acquired.
    return a.request_id==b.request_id && a.resident_id==b.resident_id &&
           a.site_id==b.site_id && a.grant_id==b.grant_id && a.kind==b.kind &&
           a.grant_event_id==b.grant_event_id && a.tick==b.tick;
}
inline bool same_need_values(const Needs& a,const Needs& b) {
    return a.hunger==b.hunger&&a.energy==b.energy&&a.hygiene==b.hygiene&&a.fun==b.fun;
}
inline bool same_contact(const Contact& a,const Contact& b) {
    return a.resident_id==b.resident_id&&a.site_id==b.site_id&&a.grant_id==b.grant_id&&
        a.freshly_observed==b.freshly_observed&&a.grounded==b.grounded&&a.reachable==b.reachable&&
        a.permission_valid==b.permission_valid&&a.reservation_valid==b.reservation_valid;
}
inline bool same_journal(const Journal& a,const Journal& b) {
    if(a.schema!=b.schema||a.version!=b.version||a.resident!=b.resident||a.tick!=b.tick||
       !same_need_values(a.needs,b.needs)||bool(a.active)!=bool(b.active)||
       a.requests.size()!=b.requests.size()||a.history.size()!=b.history.size())return false;
    if(a.active&&(!same_request(a.active->grant,b.active->grant)||a.active->elapsed!=b.active->elapsed))return false;
    for(std::size_t i=0;i<a.requests.size();++i) {
        const auto& x=a.requests[i];const auto& y=b.requests[i];
        if(!same_request(x.grant,y.grant)||x.receipt.accepted!=y.receipt.accepted||
           x.receipt.already_applied!=y.receipt.already_applied||x.receipt.reason!=y.receipt.reason||
           x.progressed_ticks!=y.progressed_ticks||x.end!=y.end||x.end_tick!=y.end_tick)return false;
    }
    for(std::size_t i=0;i<a.history.size();++i) {
        const auto& x=a.history[i];const auto& y=b.history[i];
        if(x.op!=y.op||x.tick!=y.tick||bool(x.grant)!=bool(y.grant)||bool(x.contact)!=bool(y.contact))return false;
        if(x.grant&&!same_request(*x.grant,*y.grant))return false;
        if(x.contact&&!same_contact(*x.contact,*y.contact))return false;
    }
    return true;
}
class ResidentUse {
    std::string resident_;
    Tick tick_=0;
    Needs needs_;
    std::optional<ActiveUse> active_;
    std::vector<RequestRecord> requests_;
    std::vector<Transition> history_;
    void decay(Tick count) {
        // max_tick*28 fits int64; clamp before narrowing to the authored int scale.
        needs_.hunger=static_cast<int>(std::max<Tick>(0,needs_.hunger-count*28));
        needs_.energy=static_cast<int>(std::max<Tick>(0,needs_.energy-count*18));
        needs_.hygiene=static_cast<int>(std::max<Tick>(0,needs_.hygiene-count*11));
    }
    bool stop(End reason,Op op) {
        if(!active_)return false;
        history_.push_back({op,tick_,{}, {}});
        requests_.back().end=reason;requests_.back().end_tick=tick_;
        active_.reset();return true;
    }
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
    const std::string& resident()const{return resident_;}
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
        requests_.push_back({grant,receipt});active_=ActiveUse{grant,0};
        history_.push_back({Op::Begin,tick_,grant,{}});return receipt;
    }
    // Exactly one observed authority tick. A long frame may not fabricate repeated
    // contact samples: the UE wrapper must interrupt use before any gap catch-up.
    Outcome advance_one(Tick next,const Contact& contact) {
        if (tick_>=max_tick || next!=tick_+1) return Outcome::RejectedTick;
        if(!active_)return advance_idle_to(next)?Outcome::TickOnly:Outcome::RejectedTick;
        const bool bounded=contact.resident_id.size()<=128&&contact.site_id.size()<=128&&contact.grant_id.size()<=128;
        // An oversized identity can never match the bounded active grant. Record
        // a canonical failed observation while retaining the same interrupted tick.
        history_.push_back({Op::Advance,next,{},bounded?contact:Contact{}});
        tick_=next;
        decay(1);
        if (!contact_ok(contact)) {requests_.back().end=End::Interrupted;requests_.back().end_tick=tick_;active_.reset();return Outcome::Interrupted;}
        const auto r=*rule(active_->grant.kind);const int old=active_->elapsed;
        const int now=old+1;
        // Integer remainder distribution gives exactly the authored total benefit
        // before 0..100 clamping, without per-frame floating-point accumulation.
        const int increment=(r.gain*now)/r.duration-(r.gain*old)/r.duration;
        int& need=value(needs_,active_->grant.kind);need=std::min(full,need+increment);
        needs_.fun=std::min(full,needs_.fun+(r.fun_gain*now)/r.duration-(r.fun_gain*old)/r.duration);
        active_->elapsed=now;
        requests_.back().progressed_ticks=now;
        if (now==r.duration) {requests_.back().end=End::Completed;requests_.back().end_tick=tick_;active_.reset();return Outcome::Completed;}
        return Outcome::Progress;
    }
    // Clock catch-up is legal only while no action is active. Never synthesizes
    // contact samples or benefits for a long frame. Native code cancels first.
    bool advance_idle_to(Tick next) {
        if(active_||next<=tick_||next>max_tick)return false;
        decay(next-tick_);tick_=next;
        if(!history_.empty()&&history_.back().op==Op::IdleTo)history_.back().tick=next;
        else history_.push_back({Op::IdleTo,next,{}, {}});
        return true;
    }
    bool cancel() {return stop(End::Cancelled,Op::Cancel);}
    bool interrupt() {return stop(End::Interrupted,Op::Interrupt);}
    // Called only after an enclosing validated WorldV3 load. Recovered journal
    // data never grants current spatial access, possession, or old reservations.
    bool invalidate_use_after_load() {return stop(End::AfterLoad,Op::AfterLoad);}
    Journal export_state()const {
        Journal j;j.resident=resident_;j.tick=tick_;j.needs=needs_;j.active=active_;
        j.requests=requests_;j.history=history_;return j;
    }
    // Candidate replay validates every redundant cache. Publication is one swap;
    // an accepted state does not make its old spatial observations current.
    bool restore_state(const Journal& incoming) {
        if(incoming.schema!=journal_schema||incoming.version!=journal_version||
           incoming.resident!=resident_||!token(resident_)||incoming.tick<0||incoming.tick>max_tick||
           incoming.requests.size()>max_requests||incoming.history.size()>max_history)return false;
        for(int n:{incoming.needs.hunger,incoming.needs.energy,incoming.needs.hygiene,incoming.needs.fun})if(n<0||n>full)return false;
        try {
            ResidentUse candidate(resident_);
            for(const auto& e:incoming.history) {
                if(e.tick<0||e.tick>max_tick)return false;
                switch(e.op) {
                case Op::Begin:
                    if(!e.grant||e.contact||e.tick!=candidate.tick_)return false;
                    {const auto r=candidate.begin(*e.grant);if(!r.accepted||r.already_applied)return false;}break;
                case Op::Advance:
                    if(e.grant||!e.contact||!candidate.active_||e.contact->resident_id.size()>128||e.contact->site_id.size()>128||e.contact->grant_id.size()>128||candidate.advance_one(e.tick,*e.contact)==Outcome::RejectedTick)return false;
                    break;
                case Op::IdleTo:
                    if(e.grant||e.contact||!candidate.advance_idle_to(e.tick))return false;
                    break;
                case Op::Cancel:
                    if(e.grant||e.contact||e.tick!=candidate.tick_||!candidate.cancel())return false;
                    break;
                case Op::AfterLoad:
                    if(e.grant||e.contact||e.tick!=candidate.tick_||!candidate.invalidate_use_after_load())return false;
                    break;
                case Op::Interrupt:
                    if(e.grant||e.contact||e.tick!=candidate.tick_||!candidate.interrupt())return false;
                    break;
                default:return false;
                }
            }
            if(!same_journal(candidate.export_state(),incoming))return false;
            *this=std::move(candidate);return true;
        }catch(...){return false;}
    }
};
} // namespace living_town::daily_life_use_v1
