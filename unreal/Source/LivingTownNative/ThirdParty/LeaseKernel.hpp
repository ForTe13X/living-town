#pragma once
// SOURCE CANDIDATE, UNCOMPILED. No Unreal/Godot includes or live bridge.
// Bounded new-world pilot: one authored initial cafe title/listing, prepaid
// lease/end/expiry and an event-derived ledger. Not the 125-field Sim port.
#include <algorithm>
#include <cstdint>
#include <limits>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace living_town::lease_pilot {
using Tick = std::int64_t;
constexpr Tick max_tick = 9007199254740991LL;
struct Account { std::string id; std::int64_t opening; std::int64_t coin; };
struct Terms {
    std::string property_id, owner, space_id, floor_id, interaction_id;
    std::int64_t fee = 4;
    Tick duration = 720;
};
enum class Action { lease, end_lease, expire };
inline std::string action_name(Action a) {
    switch (a) { case Action::lease: return "lease"; case Action::end_lease: return "end_lease";
    case Action::expire: return "expire"; }
    throw std::invalid_argument("invalid action enum");
}
struct Intent { std::string request_id, property_id; Action action; };
// Trusted authority-only input. An Unreal UI must never deserialize this from
// client fields. The session binds actor, logical location, clock and reach.
struct Context {
    std::string actor, space_id, floor_id, interaction_id;
    Tick tick = 0;
    bool within_reach = false;
};
struct Event {
    std::int64_t id = 0;
    Tick tick = 0;
    std::string type, actor, target, subject, note, txid;
    bool accepted = false;
    std::optional<std::int64_t> amt, amount, end_tick, pay_event_id, lease_event_id;
    std::optional<std::int64_t> title_revision, offer_revision;
    std::string request_id, action, owner_before;
    std::optional<Context> context;
};
inline bool same_context(const Context& a, const Context& b) {
    return a.actor==b.actor && a.space_id==b.space_id && a.floor_id==b.floor_id &&
        a.interaction_id==b.interaction_id && a.tick==b.tick && a.within_reach==b.within_reach;
}
inline bool same_event(const Event& a, const Event& b) {
    return a.id==b.id && a.tick==b.tick && a.type==b.type && a.actor==b.actor &&
        a.target==b.target && a.subject==b.subject && a.note==b.note && a.txid==b.txid &&
        a.accepted==b.accepted && a.amt==b.amt && a.amount==b.amount && a.end_tick==b.end_tick &&
        a.pay_event_id==b.pay_event_id && a.lease_event_id==b.lease_event_id &&
        a.title_revision==b.title_revision && a.offer_revision==b.offer_revision &&
        a.request_id==b.request_id && a.action==b.action && a.owner_before==b.owner_before &&
        a.context.has_value()==b.context.has_value() &&
        (!a.context || same_context(*a.context,*b.context));
}
struct Receipt {
    bool ok=false, already_applied=false;
    std::string reason;
    std::int64_t event_id=-1;
};
struct Lease { std::string tenant; Tick start=0, end=0; std::int64_t event_id=-1; bool active=false; };
struct Request { std::string id, actor, property_id; Action action; Receipt receipt; };

inline bool token(const std::string& s, std::size_t limit=128) {
    if(s.empty() || s.size()>limit) return false;
    for(unsigned char c:s) if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||
        (c>='0'&&c<='9')||c=='_'||c==':'||c=='/'||c=='.'||c=='-')) return false;
    return true;
}
inline std::uint32_t fnv1a32(const std::string& s) {
    std::uint32_t h=2166136261U;
    for(unsigned char b:s) h=(h^b)*16777619U;
    return h;
}

class Kernel {
    Terms terms_;
    std::vector<Account> accounts_; // explicit source order, never hash-table iteration
    std::vector<Event> events_;
    std::vector<Request> requests_;
    Lease lease_;
    Tick last_tick_=0;
    std::int64_t next_id_=1;
    std::uint64_t digest_=0;
    Account* find(const std::string& id) {
        auto it=std::find_if(accounts_.begin(),accounts_.end(),[&](const Account& x){return x.id==id;});
        return it==accounts_.end()?nullptr:&*it;
    }
    const Account* find(const std::string& id) const {
        auto it=std::find_if(accounts_.begin(),accounts_.end(),[&](const Account& x){return x.id==id;});
        return it==accounts_.end()?nullptr:&*it;
    }
    void append(Event e) {
        if(next_id_>max_tick) throw std::overflow_error("pilot event id limit");
        e.id=next_id_++;
        std::string es=std::to_string(e.id)+":"+e.type+":"+e.actor+":"+e.target+":"+
            (e.accepted?"1":"0")+":"+e.subject+":"+std::to_string(e.tick);
        if(!e.txid.empty()) es+=":tx:"+e.txid;
        digest_=((digest_*1099511628211ULL)^fnv1a32(es))&0x7fffffffffffffffULL;
        last_tick_=e.tick;
        events_.push_back(std::move(e));
    }
    Event base(const Intent& i,const Context& c) const {
        Event e; e.tick=c.tick; e.actor=c.actor; e.target=i.property_id; e.subject=i.property_id;
        e.request_id=i.request_id; e.action=action_name(i.action); e.context=c;
        e.owner_before=terms_.owner; e.title_revision=0; return e;
    }
    Receipt commit(const Intent& i,const Context& c,Event e,bool ok,const std::string& reason) {
        append(std::move(e));
        Receipt r{ok,false,ok?"":reason,events_.back().id};
        requests_.push_back({i.request_id,c.actor,i.property_id,i.action,r});
        return r;
    }
    Receipt execute_in_place(const Intent& i,const Context& c) {
        if(!token(i.request_id)||!token(i.property_id,64)||!token(c.actor)) return {false,false,"malformed_request",-1};
        if(i.property_id!=terms_.property_id) return {false,false,"unknown_property",-1};
        if(!find(c.actor) && !(c.actor=="town"&&i.action==Action::expire)) return {false,false,"unauthenticated_actor",-1};
        if(c.tick<last_tick_||c.tick>max_tick) return {false,false,"invalid_command_tick",-1};
        for(const auto& old:requests_) if(old.id==i.request_id) {
            if(old.actor!=c.actor||old.property_id!=i.property_id||old.action!=i.action)
                return {false,false,"request_id_conflict",-1};
            Receipt r=old.receipt; r.already_applied=true; return r;
        }
        Event e=base(i,c);
        auto refuse=[&](const std::string& why) {
            e.type="property_refused"; e.note=why; e.accepted=false;
            return commit(i,c,e,false,why);
        };
        if(i.action!=Action::expire && (c.space_id!=terms_.space_id || c.floor_id!=terms_.floor_id ||
            c.interaction_id!=terms_.interaction_id || !c.within_reach)) return refuse("not_at_commercial_counter");
        if(i.action==Action::lease) {
            if(c.actor==terms_.owner) return refuse("self_transaction");
            if(lease_.active) return refuse("lease_must_end_first");
            if(c.tick>max_tick-terms_.duration) return refuse("lease_tick_overflow");
            Account* payer=find(c.actor); Account* payee=find(terms_.owner);
            // Same finite transfer guard as Sim.transfer. The entire operation is
            // performed on a candidate copy; allocation/errors cannot half-pay.
            if(!payer||!payee||payer->coin<terms_.fee||payee->coin<0||
                payee->coin>std::numeric_limits<std::int64_t>::max()-terms_.fee)
                return refuse("settlement_rejected");
            Event pay; pay.tick=c.tick; pay.type="pay"; pay.actor=c.actor; pay.target=terms_.owner;
            pay.accepted=true; pay.amt=terms_.fee; pay.txid="property/"+i.request_id;
            pay.note="property_lease:"+terms_.property_id+"*"+std::to_string(terms_.fee);
            payer->coin-=terms_.fee; payee->coin+=terms_.fee; append(pay);
            e.type="property_lease_granted"; e.accepted=true; e.note="lease";
            e.amount=terms_.fee; e.end_tick=c.tick+terms_.duration; e.pay_event_id=events_.back().id;
            e.offer_revision=0; e.txid=pay.txid;
            Receipt result=commit(i,c,e,true,"");
            lease_={c.actor,c.tick,*e.end_tick,result.event_id,true}; return result;
        }
        if(!lease_.active) return refuse("no_active_lease");
        if(i.action==Action::end_lease && c.actor!=lease_.tenant) return refuse("not_tenant");
        if(i.action==Action::expire && (c.actor!="town"||c.tick<lease_.end)) return refuse("lease_not_due");
        e.type="property_lease_ended"; e.accepted=true;
        e.note=i.action==Action::expire?"expired":"surrendered"; e.lease_event_id=lease_.event_id;
        Receipt result=commit(i,c,e,true,""); lease_.active=false; return result;
    }
public:
    Kernel(Terms terms,std::vector<Account> accounts):terms_(std::move(terms)),accounts_(std::move(accounts)) {
        if(!token(terms_.property_id,64)||!token(terms_.owner)||!token(terms_.space_id,64)||
            !token(terms_.floor_id,64)||!token(terms_.interaction_id,64)||terms_.fee<=0||terms_.fee>1000000||
            terms_.duration<=0||terms_.duration>87600||!find(terms_.owner)) throw std::invalid_argument("pilot terms");
        for(std::size_t i=0;i<accounts_.size();++i) {
            if(!token(accounts_[i].id)||accounts_[i].opening<0||accounts_[i].coin!=accounts_[i].opening)
                throw std::invalid_argument("pilot opening account");
            for(std::size_t j=0;j<i;++j) if(accounts_[j].id==accounts_[i].id) throw std::invalid_argument("duplicate account");
        }
    }
    Receipt execute(const Intent& i,const Context& c) {
        Kernel candidate=*this; Receipt result=candidate.execute_in_place(i,c);
        if(!candidate.verify_ledger()) throw std::logic_error("atomic ledger refusal");
        *this=std::move(candidate); return result;
    }
    bool verify_ledger() const {
        for(const auto& account:accounts_) {
            std::int64_t expected=account.opening;
            for(const auto& e:events_) if(e.type=="pay") {
                if(!e.amt||*e.amt<=0||!e.accepted||!find(e.actor)||!find(e.target)) return false;
                if(e.actor==account.id) expected-=*e.amt;
                if(e.target==account.id) {
                    if(expected>std::numeric_limits<std::int64_t>::max()-*e.amt) return false;
                    expected+=*e.amt;
                }
            }
            if(expected!=account.coin) return false;
        }
        return true;
    }
    std::string operator_at(Tick tick) const {
        if(tick<last_tick_||tick>max_tick) throw std::invalid_argument("rights tick");
        return lease_.active && tick>=lease_.start && tick<lease_.end?lease_.tenant:terms_.owner;
    }
    bool can_operate(const std::string& actor,const std::string& space,const std::string& floor,Tick tick) const {
        return space==terms_.space_id && floor==terms_.floor_id && actor==operator_at(tick);
    }
    const std::vector<Event>& events() const {return events_;}
    const std::vector<Account>& accounts() const {return accounts_;}
    std::uint64_t digest() const {return digest_;}
    const Lease& lease() const {return lease_;}
    // New pilot journal only; NOT a loader for legacy LTSAVE/whole Sim logs.
    // Regenerate each receipt and demand exact identity before replacing live.
    bool restore_events(const std::vector<Event>& incoming) {
        std::vector<Account> opening=accounts_;
        for(auto& a:opening) a.coin=a.opening;
        Kernel candidate(terms_,opening);
        std::size_t at=0;
        while(at<incoming.size()) {
            std::size_t receipt_at=at;
            if(incoming[at].type=="pay") {if(at+1>=incoming.size()) return false; receipt_at=at+1;}
            const auto& e=incoming[receipt_at];
            if(!e.context||e.request_id.empty()||e.actor!=e.context->actor||e.tick!=e.context->tick) return false;
            Action action;
            if(e.action=="lease") action=Action::lease;
            else if(e.action=="end_lease") action=Action::end_lease;
            else if(e.action=="expire") action=Action::expire;
            else return false;
            std::size_t before=candidate.events_.size();
            candidate.execute({e.request_id,e.subject,action},*e.context);
            std::size_t count=candidate.events_.size()-before;
            if(count==0||at+count>incoming.size()||receipt_at!=at+count-1) return false;
            for(std::size_t j=0;j<count;++j)
                if(!same_event(candidate.events_[before+j],incoming[at+j])) return false;
            at+=count;
        }
        if(!candidate.verify_ledger()) return false;
        *this=std::move(candidate); return true;
    }
};
} // namespace living_town::lease_pilot
