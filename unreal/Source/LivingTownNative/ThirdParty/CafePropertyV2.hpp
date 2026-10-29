#pragma once
// UNCOMPILED CANDIDATE. One exclusive cafe ledger/property authority.
// No Unreal/Godot dependency. Never run beside v1 against the same balances.
#include <algorithm>
#include <charconv>
#include <cstdint>
#include <initializer_list>
#include <limits>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace living_town::cafe_property_v2 {
using Int = std::int64_t;
constexpr Int max_tick = 9007199254740991LL;
constexpr std::size_t max_events = 1024;
constexpr std::size_t max_journal_bytes = 4*1024*1024;
inline constexpr const char* schema = "living_town.cafe_property_title.v2";
inline constexpr const char* capability = "cafe.property_title.v2";
inline constexpr const char* source_config_sha256 = "d45f1b001e0177088757be4e45ee3a4910c5cd6b09b18128693058886f40637f";

struct Account { std::string id; Int opening=0, coin=0; };
struct Terms {
    std::string property_id="cafe_ground_commercial_v1", initial_owner="aria";
    std::string space_id="cafe", floor_id="1f", interaction_id="cafe1f_counter";
    std::string config_sha256=source_config_sha256;
    Int lease_fee=4, lease_duration=720, sale_price=12;
};
enum class Action { offer_lease, offer_sale, buy, lease, end_lease, expire };
inline std::string action_name(Action a) {
    switch(a) {
    case Action::offer_lease: return "offer_lease"; case Action::offer_sale: return "offer_sale";
    case Action::buy: return "buy"; case Action::lease: return "lease";
    case Action::end_lease: return "end_lease"; case Action::expire: return "expire";
    }
    return {};
}
inline std::optional<Action> parse_action(const std::string& s) {
    for(Action a: {Action::offer_lease,Action::offer_sale,Action::buy,Action::lease,Action::end_lease,Action::expire})
        if(action_name(a)==s) return a;
    return {};
}
// The native UI supplies only these three fields. Context is authority-only.
struct Intent { std::string request_id, property_id; Action action=Action::lease; };
struct Context {
    std::string actor, authenticated_actor, space_id, floor_id, interaction_id;
    Int tick=0;
    bool within_reach=false;
};
struct Event {
    Int id=0, tick=0;
    std::string type, actor, target, subject, note, txid;
    bool accepted=false;
    std::optional<Int> amt, amount, end_tick, pay_event_id, lease_event_id;
    std::optional<Int> title_revision, offer_revision;
    std::string request_id, action, owner_before, owner_after, offer_kind;
    std::optional<Context> context;
};
struct Receipt { bool ok=false, already_applied=false; std::string reason; Int event_id=-1; };
struct Title { std::string owner; Int revision=0, event_id=-1; };
struct Offer {
    bool present=true;
    std::string kind="lease", owner;
    Int revision=0, title_revision=0, event_id=-1;
};
struct Lease {
    bool active=false;
    std::string tenant, owner;
    Int start=0, end=0, event_id=-1, pay_event_id=-1, end_event_id=-1, ended_tick=-1;
};
struct Request { Intent intent; std::string actor; Receipt receipt; };
struct PaymentIntent { std::string actor, target, note, txid; Int amt=0, tick=0; };
struct Plan {
    Receipt receipt;
    std::optional<Event> event;
    std::optional<PaymentIntent> payment;
};
// Fault injection is an explicit CPU fixture hook, not a serialized/player field.
enum class FaultPoint { none, after_payment_before_property };

inline bool token(const std::string& s, std::size_t limit=128) {
    if(s.empty()||s.size()>limit) return false;
    for(unsigned char c:s) if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||
        c=='_'||c==':'||c=='/'||c=='.'||c=='-')) return false;
    return true;
}

namespace detail {
// Length-prefixed canonical fields: no escaping, locale, JSON rounding or delimiter ambiguity.
struct Writer {
    std::string bytes;
    void s(const std::string& v) { bytes+=std::to_string(v.size())+":"+v; }
    void n(Int v) { s(std::to_string(v)); }
    void u(std::uint64_t v) { s(std::to_string(v)); }
    void b(bool v) { s(v?"1":"0"); }
    void o(const std::optional<Int>& v) { b(v.has_value()); if(v) n(*v); }
};
struct Reader {
    const std::string& bytes; std::size_t at=0;
    std::string s(std::size_t limit=256) {
        const auto end=bytes.find(':',at);
        if(end==std::string::npos||end==at||end-at>8) throw std::invalid_argument("field length");
        std::size_t count=0;
        const auto result=std::from_chars(bytes.data()+at,bytes.data()+end,count);
        if(result.ec!=std::errc{}||result.ptr!=bytes.data()+end||count>limit||count>bytes.size()-end-1)
            throw std::invalid_argument("field bounds");
        at=end+1; const auto value=bytes.substr(at,count); at+=count; return value;
    }
    Int n() {
        const auto v=s(24); Int out=0;
        const auto result=std::from_chars(v.data(),v.data()+v.size(),out);
        if(result.ec!=std::errc{}||result.ptr!=v.data()+v.size()||std::to_string(out)!=v)
            throw std::invalid_argument("integer");
        return out;
    }
    std::uint64_t u() {
        const auto v=s(24); std::uint64_t out=0;
        const auto result=std::from_chars(v.data(),v.data()+v.size(),out);
        if(result.ec!=std::errc{}||result.ptr!=v.data()+v.size()||std::to_string(out)!=v)
            throw std::invalid_argument("unsigned integer");
        return out;
    }
    bool b() { const auto v=s(1); if(v!="0"&&v!="1") throw std::invalid_argument("boolean"); return v=="1"; }
    std::optional<Int> o() { if(b()) return n(); return {}; }
    std::size_t count(std::size_t maximum) {
        const Int v=n(); if(v<0||static_cast<std::uint64_t>(v)>maximum) throw std::invalid_argument("count");
        return static_cast<std::size_t>(v);
    }
};
inline void write_context(Writer& w,const Context& c) {
    w.s(c.actor);w.s(c.authenticated_actor);w.s(c.space_id);w.s(c.floor_id);w.s(c.interaction_id);w.n(c.tick);w.b(c.within_reach);
}
inline Context read_context(Reader& r) {
    Context c;c.actor=r.s();c.authenticated_actor=r.s();c.space_id=r.s();c.floor_id=r.s();c.interaction_id=r.s();c.tick=r.n();c.within_reach=r.b();return c;
}
inline void write_event(Writer& w,const Event& e) {
    w.n(e.id);w.n(e.tick);w.s(e.type);w.s(e.actor);w.s(e.target);w.s(e.subject);w.s(e.note);w.s(e.txid);w.b(e.accepted);
    w.o(e.amt);w.o(e.amount);w.o(e.end_tick);w.o(e.pay_event_id);w.o(e.lease_event_id);w.o(e.title_revision);w.o(e.offer_revision);
    w.s(e.request_id);w.s(e.action);w.s(e.owner_before);w.s(e.owner_after);w.s(e.offer_kind);
    w.b(e.context.has_value());if(e.context) write_context(w,*e.context);
}
inline Event read_event(Reader& r) {
    Event e;e.id=r.n();e.tick=r.n();e.type=r.s();e.actor=r.s();e.target=r.s();e.subject=r.s();e.note=r.s();e.txid=r.s();e.accepted=r.b();
    e.amt=r.o();e.amount=r.o();e.end_tick=r.o();e.pay_event_id=r.o();e.lease_event_id=r.o();e.title_revision=r.o();e.offer_revision=r.o();
    e.request_id=r.s();e.action=r.s();e.owner_before=r.s();e.owner_after=r.s();e.offer_kind=r.s();if(r.b())e.context=read_context(r);return e;
}
inline std::string event_bytes(const Event& e) { Writer w;write_event(w,e);return w.bytes; }
inline bool same_event(const Event& a,const Event& b) { return event_bytes(a)==event_bytes(b); }
inline void write_terms(Writer& w,const Terms& t) {
    w.s(t.property_id);w.s(t.initial_owner);w.s(t.space_id);w.s(t.floor_id);w.s(t.interaction_id);w.s(t.config_sha256);
    w.n(t.lease_fee);w.n(t.lease_duration);w.n(t.sale_price);
}
inline Terms read_terms(Reader& r) {
    Terms t;t.property_id=r.s();t.initial_owner=r.s();t.space_id=r.s();t.floor_id=r.s();t.interaction_id=r.s();t.config_sha256=r.s();
    t.lease_fee=r.n();t.lease_duration=r.n();t.sale_price=r.n();return t;
}
inline bool same_terms(const Terms& a,const Terms& b) { Writer x,y;write_terms(x,a);write_terms(y,b);return x.bytes==y.bytes; }
inline void write_accounts(Writer& w,const std::vector<Account>& accounts) {
    w.n(static_cast<Int>(accounts.size()));for(const auto& a:accounts){w.s(a.id);w.n(a.opening);w.n(a.coin);}
}
inline std::vector<Account> read_accounts(Reader& r) {
    std::vector<Account> out;const auto count=r.count(2);
    for(std::size_t i=0;i<count;++i){Account a;a.id=r.s();a.opening=r.n();a.coin=r.n();out.push_back(std::move(a));}return out;
}
inline bool same_accounts(const std::vector<Account>& a,const std::vector<Account>& b) {
    Writer x,y;write_accounts(x,a);write_accounts(y,b);return x.bytes==y.bytes;
}
inline void write_rights(Writer& w,const Title& t,const Offer& o,const Lease& l) {
    w.s(t.owner);w.n(t.revision);w.n(t.event_id);
    w.b(o.present);w.s(o.kind);w.s(o.owner);w.n(o.revision);w.n(o.title_revision);w.n(o.event_id);
    w.b(l.active);w.s(l.tenant);w.s(l.owner);w.n(l.start);w.n(l.end);w.n(l.event_id);w.n(l.pay_event_id);w.n(l.end_event_id);w.n(l.ended_tick);
}
inline void read_rights(Reader& r,Title& t,Offer& o,Lease& l) {
    t.owner=r.s();t.revision=r.n();t.event_id=r.n();
    o.present=r.b();o.kind=r.s();o.owner=r.s();o.revision=r.n();o.title_revision=r.n();o.event_id=r.n();
    l.active=r.b();l.tenant=r.s();l.owner=r.s();l.start=r.n();l.end=r.n();l.event_id=r.n();l.pay_event_id=r.n();l.end_event_id=r.n();l.ended_tick=r.n();
}
inline std::uint64_t hash_bytes(std::uint64_t h,const std::string& bytes) {
    for(unsigned char c:bytes){h^=c;h*=1099511628211ULL;}return h;
}
} // detail

// Typed save document. Its cache is checked against complete deterministic replay.
// This is not a v1 journal or whole-world Sim archive.
struct Journal {
    std::string document_schema=schema, document_capability=capability;
    Terms terms;
    std::vector<Account> opening, accounts;
    std::vector<Event> events;
    Title title;Offer offer;Lease lease;
    Int last_tick=0;
    std::uint64_t digest=14695981039346656037ULL;
};
inline std::string encode(const Journal& j) {
    detail::Writer w;w.s(j.document_schema);w.s(j.document_capability);detail::write_terms(w,j.terms);
    detail::write_accounts(w,j.opening);detail::write_accounts(w,j.accounts);
    w.n(static_cast<Int>(j.events.size()));for(const auto& e:j.events)detail::write_event(w,e);
    detail::write_rights(w,j.title,j.offer,j.lease);w.n(j.last_tick);w.u(j.digest);return w.bytes;
}
inline std::optional<Journal> decode(const std::string& bytes) {
    if(bytes.size()>max_journal_bytes)return {};
    try {
        detail::Reader r{bytes};Journal j;j.document_schema=r.s();j.document_capability=r.s();j.terms=detail::read_terms(r);
        j.opening=detail::read_accounts(r);j.accounts=detail::read_accounts(r);const auto count=r.count(max_events);
        for(std::size_t i=0;i<count;++i)j.events.push_back(detail::read_event(r));
        detail::read_rights(r,j.title,j.offer,j.lease);j.last_tick=r.n();j.digest=r.u();
        if(r.at!=bytes.size()||encode(j)!=bytes)return {};
        return j;
    } catch(const std::exception&) { return {}; }
}

class Kernel {
    Terms terms_;
    std::vector<Account> opening_, accounts_;
    std::vector<Event> events_;
    std::vector<Request> requests_;
    Title title_;Offer offer_;Lease lease_;
    Int last_tick_=0;
    std::uint64_t digest_=14695981039346656037ULL;
    Account* find(const std::string& id) {
        const auto it=std::find_if(accounts_.begin(),accounts_.end(),[&](const Account& a){return a.id==id;});
        return it==accounts_.end()?nullptr:&*it;
    }
    const Account* find(const std::string& id) const {
        const auto it=std::find_if(accounts_.begin(),accounts_.end(),[&](const Account& a){return a.id==id;});
        return it==accounts_.end()?nullptr:&*it;
    }
    Event base(const Intent& i,const Context& c) const {
        Event e;e.tick=c.tick;e.actor=c.actor;e.target=i.property_id;e.subject=i.property_id;e.request_id=i.request_id;
        e.action=action_name(i.action);e.context=c;e.owner_before=title_.owner;e.title_revision=title_.revision;return e;
    }
    void append(Event e) {
        if(events_.size()>=max_events)throw std::overflow_error("event capacity");
        e.id=static_cast<Int>(events_.size())+1;digest_=detail::hash_bytes(digest_,detail::event_bytes(e));
        last_tick_=e.tick;events_.push_back(std::move(e));
    }
    Receipt commit(const Intent& i,const Context& c,Event e,bool ok,const std::string& reason) {
        append(std::move(e));Receipt r{ok,false,reason,events_.back().id};requests_.push_back({i,c.actor,r});return r;
    }
    bool transfer(const PaymentIntent& p,Event& actual) {
        Account* from=find(p.actor);Account* to=find(p.target);
        if(!from||!to||from==to||p.amt<=0||from->coin<p.amt||to->coin<0||to->coin>std::numeric_limits<Int>::max()-p.amt)return false;
        actual={};actual.type="pay";actual.actor=p.actor;actual.target=p.target;actual.amt=p.amt;actual.tick=p.tick;
        actual.note=p.note;actual.txid=p.txid;actual.accepted=true;
        from->coin-=p.amt;to->coin+=p.amt;append(actual);actual=events_.back();return true;
    }
    Receipt apply(const Intent& i,const Context& c,FaultPoint fault) {
        Plan p=prepare(i,c);if(!p.event)return p.receipt;
        Event e=*p.event;
        if(p.payment) {
            if(events_.size()>max_events-2)throw std::overflow_error("transaction event capacity");
            Event actual;
            if(!transfer(*p.payment,actual)) {
                e.type="property_refused";e.accepted=false;e.note="settlement_rejected";e.txid.clear();
                e.amount.reset();e.end_tick.reset();e.owner_after.clear();e.offer_revision.reset();
                return commit(i,c,std::move(e),false,"settlement_rejected");
            }
            if(fault==FaultPoint::after_payment_before_property)throw std::runtime_error("injected_postpay");
            auto settled=settled_event(p,actual);if(!settled)throw std::logic_error("payment_receipt_mismatch");e=*settled;
        }
        const Receipt r=commit(i,c,e,p.receipt.ok,p.receipt.reason);
        if(!r.ok)return r;
        if(e.type=="property_offer_opened")offer_={true,e.offer_kind,c.actor,*e.offer_revision,title_.revision,r.event_id};
        else if(e.type=="property_deed_transferred") {
            title_={e.owner_after,title_.revision+1,r.event_id};offer_={false,"","",0,0,-1};
        } else if(e.type=="property_lease_granted") {
            lease_={true,c.actor,e.owner_before,c.tick,*e.end_tick,r.event_id,*e.pay_event_id,-1,-1};
        } else if(e.type=="property_lease_ended") {lease_.active=false;lease_.end_event_id=r.event_id;lease_.ended_tick=c.tick;}
        return r;
    }
public:
    explicit Kernel(Terms terms=Terms{},std::vector<Account> opening={{"aria",12,12},{"ben",12,12}})
        :terms_(std::move(terms)),opening_(opening),accounts_(std::move(opening)) {
        // Bounded source binding: callers cannot change a price, footprint or initial owner via UI/config overrides.
        if(!detail::same_terms(terms_,Terms{}))throw std::invalid_argument("unbound cafe terms");
        if(accounts_.size()!=2||accounts_[0].id!="aria"||accounts_[1].id!="ben")throw std::invalid_argument("opening account binding");
        for(const auto& a:accounts_)if(a.opening<0||a.coin!=a.opening)throw std::invalid_argument("opening balance");
        title_={terms_.initial_owner,0,-1};offer_={true,"lease",terms_.initial_owner,0,0,-1};
    }
    Plan prepare(const Intent& i,const Context& c) const {
        auto invalid=[](const std::string& why){Plan p;p.receipt.reason=why;return p;};
        if(!token(i.request_id)||!token(i.property_id,64)||action_name(i.action).empty())return invalid("malformed_request");
        if(i.property_id!=terms_.property_id)return invalid("unknown_property");
        if(c.actor!=c.authenticated_actor||(!find(c.actor)&&!(c.actor=="town"&&i.action==Action::expire)))return invalid("unauthenticated_actor");
        if(c.space_id.size()>128||c.floor_id.size()>128||c.interaction_id.size()>128)return invalid("malformed_context");
        if(c.tick<last_tick_||c.tick>max_tick)return invalid("invalid_command_tick");
        for(const auto& old:requests_)if(old.intent.request_id==i.request_id) {
            if(old.actor!=c.actor||old.intent.property_id!=i.property_id||old.intent.action!=i.action)return invalid("request_id_conflict");
            Plan p;p.receipt=old.receipt;p.receipt.already_applied=true;return p;
        }
        Event e=base(i,c);
        auto refuse=[&](const std::string& why){Plan p;Event denied=base(i,c);denied.type="property_refused";denied.note=why;denied.accepted=false;p.event=denied;p.receipt.reason=why;return p;};
        if(i.action!=Action::expire&&(c.space_id!=terms_.space_id||c.floor_id!=terms_.floor_id||c.interaction_id!=terms_.interaction_id||!c.within_reach))return refuse("not_at_commercial_counter");
        e.accepted=true;e.note=action_name(i.action);Plan p;p.receipt.ok=true;
        if(i.action==Action::offer_lease||i.action==Action::offer_sale) {
            if(c.actor!=title_.owner)return refuse("not_owner");
            if(lease_.active)return refuse("lease_must_end_first");
            if(offer_.revision>=max_tick)return refuse("offer_revision_overflow");
            e.type="property_offer_opened";e.offer_kind=i.action==Action::offer_lease?"lease":"sale";e.offer_revision=offer_.revision+1;
        } else if(i.action==Action::buy||i.action==Action::lease) {
            if(c.actor==title_.owner)return refuse("self_transaction");
            if(lease_.active)return refuse("lease_must_end_first");
            const bool buying=i.action==Action::buy;
            if(!offer_.present||offer_.kind!=(buying?"sale":"lease")||offer_.owner!=title_.owner||offer_.title_revision!=title_.revision)return refuse("no_owner_offer");
            if(buying&&title_.revision>=max_tick)return refuse("title_revision_overflow");
            e.type=buying?"property_deed_transferred":"property_lease_granted";e.offer_revision=offer_.revision;
            e.amount=buying?terms_.sale_price:terms_.lease_fee;
            if(buying)e.owner_after=c.actor;
            else {if(c.tick>max_tick-terms_.lease_duration)return refuse("lease_tick_overflow");e.end_tick=c.tick+terms_.lease_duration;}
            e.txid="property/"+i.request_id;
            p.payment=PaymentIntent{c.actor,title_.owner,(buying?"property_sale:":"property_lease:")+terms_.property_id+"*"+std::to_string(*e.amount),e.txid,*e.amount,c.tick};
        } else {
            if(!lease_.active)return refuse("no_active_lease");
            if(i.action==Action::end_lease&&c.actor!=lease_.tenant)return refuse("not_tenant");
            if(i.action==Action::expire&&(c.actor!="town"||c.tick<lease_.end))return refuse("lease_not_due");
            e.type="property_lease_ended";e.note=i.action==Action::expire?"expired":"surrendered";e.lease_event_id=lease_.event_id;
        }
        p.event=e;return p;
    }
    // Verifies an actual ledger-emitted receipt; no caller can publish it directly.
    static std::optional<Event> settled_event(const Plan& p,const Event& actual) {
        if(!p.receipt.ok||p.receipt.already_applied||!p.event||!p.payment)return {};
        const auto& x=*p.payment;
        if(actual.type!="pay"||!actual.accepted||actual.id<0||actual.id>max_tick||actual.actor!=x.actor||actual.target!=x.target||
            actual.amt!=std::optional<Int>(x.amt)||actual.tick!=x.tick||actual.note!=x.note||actual.txid!=x.txid)return {};
        Event e=*p.event;e.pay_event_id=actual.id;return e;
    }
    Receipt execute(const Intent& i,const Context& c,FaultPoint fault=FaultPoint::none) {
        Kernel candidate=*this;
        try {
            Receipt r=candidate.apply(i,c,fault);
            if(!candidate.verify_ledger())throw std::logic_error("ledger_reconciliation");
            *this=std::move(candidate);return r;
        } catch(const std::exception& e) {return {false,false,std::string("technical_failure:")+e.what(),-1};}
    }
    bool verify_ledger() const {
        auto expected=opening_;
        for(const auto& e:events_)if(e.type=="pay") {
            if(!e.accepted||!e.amt||*e.amt<=0||e.actor==e.target)return false;
            auto from=std::find_if(expected.begin(),expected.end(),[&](const Account& a){return a.id==e.actor;});
            auto to=std::find_if(expected.begin(),expected.end(),[&](const Account& a){return a.id==e.target;});
            if(from==expected.end()||to==expected.end()||from->coin<*e.amt||to->coin>std::numeric_limits<Int>::max()-*e.amt)return false;
            from->coin-=*e.amt;to->coin+=*e.amt;
        }
        return detail::same_accounts(expected,accounts_);
    }
    std::string operator_at(Int tick) const {
        if(tick<last_tick_||tick>max_tick)throw std::invalid_argument("rights tick");
        return lease_.active&&tick>=lease_.start&&tick<lease_.end?lease_.tenant:title_.owner;
    }
    bool can_operate(const std::string& actor,const std::string& space,const std::string& floor,Int tick) const {
        return space==terms_.space_id&&floor==terms_.floor_id&&actor==operator_at(tick);
    }
    const Terms& terms() const{return terms_;}
    const std::vector<Account>& accounts()const{return accounts_;}
    const std::vector<Event>& events()const{return events_;}
    const Title& title()const{return title_;}
    const Offer& offer()const{return offer_;}
    const Lease& lease()const{return lease_;}
    // The native natural-clock consumer executes this authority-generated request
    // before other commands/projection at a due tick. No player supplies town.
    std::optional<Intent> expiry_request(Int trusted_tick) const {
        if(trusted_tick<last_tick_||trusted_tick>max_tick)throw std::invalid_argument("expiry tick");
        if(!lease_.active||trusted_tick<lease_.end)return {};
        return Intent{"expire/"+terms_.property_id+"/"+std::to_string(lease_.event_id),terms_.property_id,Action::expire};
    }
    Int last_tick()const{return last_tick_;}
    std::uint64_t digest()const{return digest_;}
    Int coin(const std::string& id)const{const auto* a=find(id);if(!a)throw std::invalid_argument("unknown account");return a->coin;}
    Journal journal() const {
        Journal j;j.terms=terms_;j.opening=opening_;j.accounts=accounts_;j.events=events_;j.title=title_;j.offer=offer_;j.lease=lease_;j.last_tick=last_tick_;j.digest=digest_;return j;
    }
    std::string save_bytes()const{return encode(journal());}
    bool restore(const Journal& incoming) {
        try {
            if(incoming.document_schema!=schema||incoming.document_capability!=capability||!detail::same_terms(incoming.terms,terms_)||
                !detail::same_accounts(incoming.opening,opening_)||incoming.events.size()>max_events)return false;
            Kernel candidate(terms_,opening_);std::size_t at=0;
            while(at<incoming.events.size()) {
                std::size_t receipt_at=at;
                if(incoming.events[at].type=="pay"){if(at+1>=incoming.events.size())return false;receipt_at=at+1;}
                const Event& e=incoming.events[receipt_at];
                if(!e.context||e.context->actor!=e.actor||e.context->tick!=e.tick)return false;
                const auto action=parse_action(e.action);if(!action)return false;
                const std::size_t before=candidate.events_.size();
                candidate.execute({e.request_id,e.subject,*action},*e.context);
                const std::size_t added=candidate.events_.size()-before;
                if(added==0||at+added>incoming.events.size()||receipt_at!=at+added-1)return false;
                for(std::size_t n=0;n<added;++n)if(!detail::same_event(candidate.events_[before+n],incoming.events[at+n]))return false;
                at+=added;
            }
            if(!candidate.verify_ledger()||encode(candidate.journal())!=encode(incoming))return false;
            *this=std::move(candidate);return true;
        } catch(const std::exception&){return false;}
    }
    bool restore_bytes(const std::string& bytes){const auto j=decode(bytes);return j&&restore(*j);}
};
} // living_town::cafe_property_v2
