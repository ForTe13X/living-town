#pragma once
// Portable C++17 authority for property, coins, stock and care grants.
// Native adapter and physical gameplay integration remain pending.
// No Unreal/Godot dependency. Never run beside v1 against the same balances.
#include "CafePropertyV2.hpp"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <charconv>
#include <cstdint>
#include <initializer_list>
#include <limits>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace living_town::cafe_world_v3 {
using Int = std::int64_t;
constexpr Int max_tick = 9007199254740991LL;
constexpr std::size_t max_events = 1024;
constexpr std::size_t max_journal_bytes = 12*1024*1024; // new bounded V3, includes preserved V2 lineage
inline constexpr const char* schema = "living_town.cafe_world_meal.v3";
inline constexpr const char* capability = "cafe.world_meal.v3";
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

// UI intent: no actor, price, payee, benefit or contact-success fields.
enum class MealKind { PurchaseMeal, PublicMeal };
inline std::string meal_kind_name(MealKind k) {
    switch(k) {case MealKind::PurchaseMeal:return "purchase_meal";case MealKind::PublicMeal:return "public_meal";}
    return {};
}
inline std::optional<MealKind> parse_meal_kind(const std::string& s) {
    for(auto k:{MealKind::PurchaseMeal,MealKind::PublicMeal})if(meal_kind_name(k)==s)return k;
    return {};
}
struct MealCommand {
    std::string request_id, site_id;
    MealKind kind=MealKind::PurchaseMeal;
    Int expected_revision=0; // immutable revision observed when this intent was made
};
// Trusted adapter observation ONLY. CPU fixtures supply data; they prove no rays,
// permissions, navigation, reservation or clip exists in a native scene.
struct MealContext {
    std::string actor, authenticated_actor;
    Int tick=0;
    bool fresh=false, correct_floor=false, reachable=false, permission=false;
    bool qualified_clip=false;
};
struct TrustedActivation { Int tick=0; bool explicitly_authorized=false; };
enum class ReleaseReason { Cancelled, Interrupted, AfterLoad, Completed };
inline std::string release_name(ReleaseReason r) {
    switch(r){case ReleaseReason::Cancelled:return "cancelled";case ReleaseReason::Interrupted:return "interrupted";case ReleaseReason::AfterLoad:return "after_load";case ReleaseReason::Completed:return "completed";}
    return {};
}
inline std::optional<ReleaseReason> parse_release(const std::string& s) {
    for(auto r:{ReleaseReason::Cancelled,ReleaseReason::Interrupted,ReleaseReason::AfterLoad,ReleaseReason::Completed})if(release_name(r)==s)return r;
    return {};
}
// completed_ticks is trusted action-state output, never a UI field. Completion
// also needs the elapsed authority time; the paired care adapter validates its
// actual replayed progress. Legacy four-field cancellation callers stay valid.
struct TrustedRelease { std::string resident; Int grant_event_id=-1, tick=0; ReleaseReason reason=ReleaseReason::Interrupted; Int completed_ticks=0; };
struct CareGrant {
    Int event_id=-1, tick=0, pay_event_id=-1, stock_event_id=-1, release_event_id=-1;
    std::string request_id, resident, site_id, provider, funding;
    bool active=true;
    // Authored effect description only: this transaction never applies needs.
    Int duration_ticks=18, hunger_gain=50, fun_gain=3;
};
enum class MealFault { None, AfterPayment, AfterStock, AfterGrant };
inline constexpr const char* meal_site = "cafe1f_dining_slot_pilot";
inline constexpr const char* meal_policy = "cafe_meal_v3_two_ration_pilot";
inline constexpr const char* meal_policy_sha256 = "2249112f2d3decec8254c6e487db129fcc68d33d0d799e6cce76968af1fb1a04";
constexpr Int meal_price=2, authored_opening_rations=2;

struct Event {
    Int id=0, tick=0;
    std::string type, actor, target, subject, note, txid;
    bool accepted=false;
    std::optional<Int> amt, amount, end_tick, pay_event_id, lease_event_id;
    std::optional<Int> title_revision, offer_revision;
    std::string request_id, action, owner_before, owner_after, offer_kind;
    std::optional<Context> context;
    std::optional<MealCommand> meal_command;
    std::optional<MealContext> meal_context;
    std::optional<Int> stock_event_id, grant_event_id;
};
struct Receipt { bool ok=false, already_applied=false; std::string reason; Int event_id=-1; };
struct MealRequest { MealCommand command; std::string actor; Receipt receipt; };
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

inline void write_meal_command(Writer& w,const MealCommand& c) {
    w.s(c.request_id);w.s(c.site_id);w.s(meal_kind_name(c.kind));w.n(c.expected_revision);
}
inline MealCommand read_meal_command(Reader& r) {
    MealCommand c;c.request_id=r.s();c.site_id=r.s();const auto k=parse_meal_kind(r.s());
    if(!k)throw std::invalid_argument("meal kind");
    c.kind=*k;c.expected_revision=r.n();return c;
}
inline void write_meal_context(Writer& w,const MealContext& c) {
    w.s(c.actor);w.s(c.authenticated_actor);w.n(c.tick);w.b(c.fresh);w.b(c.correct_floor);
    w.b(c.reachable);w.b(c.permission);w.b(c.qualified_clip);
}
inline MealContext read_meal_context(Reader& r) {
    MealContext c;c.actor=r.s();c.authenticated_actor=r.s();c.tick=r.n();c.fresh=r.b();
    c.correct_floor=r.b();c.reachable=r.b();c.permission=r.b();c.qualified_clip=r.b();return c;
}
inline void write_grant(Writer& w,const CareGrant& g) {
    w.n(g.event_id);w.n(g.tick);w.n(g.pay_event_id);w.n(g.stock_event_id);w.n(g.release_event_id);
    w.s(g.request_id);w.s(g.resident);w.s(g.site_id);w.s(g.provider);w.s(g.funding);w.b(g.active);
    w.n(g.duration_ticks);w.n(g.hunger_gain);w.n(g.fun_gain);
}
inline CareGrant read_grant(Reader& r) {
    CareGrant g;g.event_id=r.n();g.tick=r.n();g.pay_event_id=r.n();g.stock_event_id=r.n();g.release_event_id=r.n();
    g.request_id=r.s();g.resident=r.s();g.site_id=r.s();g.provider=r.s();g.funding=r.s();g.active=r.b();
    g.duration_ticks=r.n();g.hunger_gain=r.n();g.fun_gain=r.n();return g;
}
inline bool same_meal_command(const MealCommand& a,const MealCommand& b) {
    Writer x,y;write_meal_command(x,a);write_meal_command(y,b);return x.bytes==y.bytes;
}
inline bool valid_fraction(std::uint64_t bits) {
    double value=0;static_assert(sizeof(value)==sizeof(bits));std::memcpy(&value,&bits,sizeof(value));
    return std::isfinite(value)&&value>=0&&value<1;
}

inline void write_property_event(Writer& w,const Event& e) {
    w.n(e.id);w.n(e.tick);w.s(e.type);w.s(e.actor);w.s(e.target);w.s(e.subject);w.s(e.note);w.s(e.txid);w.b(e.accepted);
    w.o(e.amt);w.o(e.amount);w.o(e.end_tick);w.o(e.pay_event_id);w.o(e.lease_event_id);w.o(e.title_revision);w.o(e.offer_revision);
    w.s(e.request_id);w.s(e.action);w.s(e.owner_before);w.s(e.owner_after);w.s(e.offer_kind);
    w.b(e.context.has_value());if(e.context) write_context(w,*e.context);
}

inline void write_event(Writer& w,const Event& e) {
    write_property_event(w,e);
    w.b(e.meal_command.has_value());if(e.meal_command)write_meal_command(w,*e.meal_command);
    w.b(e.meal_context.has_value());if(e.meal_context)write_meal_context(w,*e.meal_context);
    w.o(e.stock_event_id);w.o(e.grant_event_id);
}
inline std::string property_event_bytes(const Event& e) {Writer w;write_property_event(w,e);return w.bytes;}
inline Event read_event(Reader& r) {
    Event e;e.id=r.n();e.tick=r.n();e.type=r.s();e.actor=r.s();e.target=r.s();e.subject=r.s();e.note=r.s();e.txid=r.s();e.accepted=r.b();
    e.amt=r.o();e.amount=r.o();e.end_tick=r.o();e.pay_event_id=r.o();e.lease_event_id=r.o();e.title_revision=r.o();e.offer_revision=r.o();
    e.request_id=r.s();e.action=r.s();e.owner_before=r.s();e.owner_after=r.s();e.offer_kind=r.s();if(r.b())e.context=read_context(r);
    if(r.b())e.meal_command=read_meal_command(r);
    if(r.b())e.meal_context=read_meal_context(r);
    e.stock_event_id=r.o();e.grant_event_id=r.o();return e;
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
    bool care_enabled=false;Int stock_opening=0, stock_current=0;
    std::vector<CareGrant> grants;
    std::string v2_origin;Int import_clock=0;std::uint64_t import_fraction_bits=0;
};
inline std::string encode(const Journal& j) {
    detail::Writer w;w.s(j.document_schema);w.s(j.document_capability);detail::write_terms(w,j.terms);
    detail::write_accounts(w,j.opening);detail::write_accounts(w,j.accounts);
    w.n(static_cast<Int>(j.events.size()));for(const auto& e:j.events)detail::write_event(w,e);
    detail::write_rights(w,j.title,j.offer,j.lease);w.n(j.last_tick);w.u(j.digest);
    w.b(j.care_enabled);w.n(j.stock_opening);w.n(j.stock_current);w.n(static_cast<Int>(j.grants.size()));
    for(const auto& g:j.grants)detail::write_grant(w,g);
    w.s(j.v2_origin);w.n(j.import_clock);w.u(j.import_fraction_bits);return w.bytes;
}
inline std::optional<Journal> decode(const std::string& bytes) {
    if(bytes.size()>max_journal_bytes)return {};
    try {
        detail::Reader r{bytes};Journal j;j.document_schema=r.s();j.document_capability=r.s();j.terms=detail::read_terms(r);
        j.opening=detail::read_accounts(r);j.accounts=detail::read_accounts(r);const auto count=r.count(max_events);
        for(std::size_t i=0;i<count;++i)j.events.push_back(detail::read_event(r));
        detail::read_rights(r,j.title,j.offer,j.lease);j.last_tick=r.n();j.digest=r.u();
        j.care_enabled=r.b();j.stock_opening=r.n();j.stock_current=r.n();
        const auto grants=r.count(max_events);for(std::size_t i=0;i<grants;++i)j.grants.push_back(detail::read_grant(r));
        j.v2_origin=r.s(living_town::cafe_property_v2::max_journal_bytes);j.import_clock=r.n();j.import_fraction_bits=r.u();
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

    bool care_enabled_=false;
    Int stock_opening_=0, stock_current_=0;
    std::vector<CareGrant> grants_;
    std::vector<MealRequest> meal_requests_;
    std::string v2_origin_;
    Int import_clock_=0;
    std::uint64_t import_fraction_bits_=0;
    // Runtime-only safety gate. Historical saved contact is never fresh access.
    bool loaded_grants_need_interruption_=false;
    std::size_t active_grants()const {
        return static_cast<std::size_t>(std::count_if(grants_.begin(),grants_.end(),[](const CareGrant& g){return g.active;}));
    }
    void reserve_events(std::size_t count,std::size_t release_reserve=0,bool reserve_existing_lease=true)const {
        const std::size_t future=active_grants()+release_reserve+(reserve_existing_lease&&lease_.active?1U:0U);
        if(count>max_events||future>max_events-count||events_.size()>max_events-count-future)
            throw std::overflow_error("whole transaction/reservation capacity");
    }
    Event meal_base(const MealCommand& input,const MealContext& at)const {
        Event e;e.tick=at.tick;e.actor=at.actor;e.target=input.site_id;e.subject=input.site_id;
        e.request_id=input.request_id;e.action=meal_kind_name(input.kind);e.meal_command=input;e.meal_context=at;return e;
    }
    Receipt meal_refuse(const MealCommand& input,const MealContext& at,const std::string& why) {
        reserve_events(1);Event e=meal_base(input,at);e.type="meal_refused";e.note=why;append(std::move(e));
        Receipt r{false,false,why,events_.back().id};meal_requests_.push_back({input,at.actor,r});return r;
    }
    Receipt apply_meal(const MealCommand& input,const MealContext& at,MealFault fault) {
        auto invalid=[](const std::string& why){return Receipt{false,false,why,-1};};
        if(!token(input.request_id)||!token(input.site_id)||meal_kind_name(input.kind).empty()||input.expected_revision<0||input.expected_revision>static_cast<Int>(max_events))return invalid("malformed_meal_command");
        if(at.actor!=at.authenticated_actor||!find(at.actor))return invalid("unauthenticated_actor");
        if(at.tick<0||at.tick>max_tick)return invalid("invalid_command_tick");
        // Identity is the original intent, including its observed revision. Replay
        // returns a receipt, not another physical-use permission or payment.
        for(const auto& old:meal_requests_)if(old.command.request_id==input.request_id) {
            if(old.actor!=at.actor||!detail::same_meal_command(old.command,input))return invalid("request_id_conflict");
            auto r=old.receipt;r.already_applied=true;return r;
        }
        for(const auto& old:requests_)if(old.intent.request_id==input.request_id)return invalid("request_id_conflict");
        if(at.tick<minimum_authority_tick())return invalid("invalid_command_tick");
        if(loaded_grants_need_interruption_)return invalid("loaded_grants_require_interruption");
        if(lease_.active&&at.tick>=lease_.end)return invalid("property_expiry_required");
        if(input.expected_revision!=revision())return meal_refuse(input,at,"stale_world_revision");
        if(!care_enabled_)return meal_refuse(input,at,"care_disabled");
        if(input.site_id!=meal_site)return meal_refuse(input,at,"unknown_meal_site");
        if(!at.fresh||!at.correct_floor||!at.reachable)return meal_refuse(input,at,"fresh_meal_contact_required");
        if(!at.permission)return meal_refuse(input,at,"meal_permission_denied");
        if(!at.qualified_clip)return meal_refuse(input,at,"qualified_meal_clip_required");
        for(const auto& g:grants_)if(g.active) {
            if(g.resident==at.actor)return meal_refuse(input,at,"resident_busy");
            if(g.site_id==input.site_id)return meal_refuse(input,at,"meal_site_occupied");
        }
        const auto provider=operator_at(at.tick);std::string funding;
        if(input.kind==MealKind::PurchaseMeal&&stock_current_==0)return meal_refuse(input,at,"meal_stock_unavailable");
        const bool paid=input.kind==MealKind::PurchaseMeal&&provider!=at.actor;
        if(paid) {
            const auto* from=find(at.actor);const auto* to=find(provider);
            if(!from||!to||from->coin<meal_price||to->coin>std::numeric_limits<Int>::max()-meal_price)
                return meal_refuse(input,at,"meal_settlement_rejected");
        }
        reserve_events(paid?3U:2U,1U);Int pay=-1,stock=-1;
        if(paid) {
            Event actual;
            // The unchanged V2 private transfer implementation is invoked INSIDE
            // this cloned/new authority. No wrapper wallet or forged pay event.
            if(!transfer({at.actor,provider,"meal:cafe*2","meal/"+input.request_id,meal_price,at.tick},actual))
                throw std::logic_error("meal_preflight_settlement_diverged");
            pay=actual.id;funding="Paid";
            if(fault==MealFault::AfterPayment)throw std::runtime_error("injected_meal_postpay");
        } else funding=input.kind==MealKind::PurchaseMeal?"OwnStock":(stock_current_>0?"PublicStock":"PublicRelief");
        Event supply;supply.tick=at.tick;supply.actor=at.actor;supply.target="ration";supply.subject=input.site_id;
        supply.type=stock_current_>0?"meal_stock_consumed":"public_meal_shortage";supply.accepted=true;
        supply.request_id=input.request_id;supply.amount=stock_current_>0?1:0;
        if(stock_current_>0)--stock_current_;
        append(std::move(supply));stock=events_.back().id;
        if(fault==MealFault::AfterStock)throw std::runtime_error("injected_meal_poststock");
        Event use=meal_base(input,at);use.type="care_meal_granted";use.accepted=true;use.note=funding;
        if(pay>0)use.pay_event_id=pay;
        use.stock_event_id=stock;append(std::move(use));
        const auto id=events_.back().id;
        CareGrant grant;grant.event_id=id;grant.tick=at.tick;grant.pay_event_id=pay;grant.stock_event_id=stock;
        grant.request_id=input.request_id;grant.resident=at.actor;grant.site_id=input.site_id;grant.provider=provider;grant.funding=funding;
        grants_.push_back(std::move(grant));Receipt r{true,false,funding,id};meal_requests_.push_back({input,at.actor,r});
        if(fault==MealFault::AfterGrant)throw std::runtime_error("injected_meal_postgrant");
        return r;
    }

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
        if(c.tick<last_tick_||c.tick<import_clock_||c.tick>max_tick)return invalid("invalid_command_tick");
        for(const auto& old:meal_requests_)if(old.command.request_id==i.request_id)return invalid("request_id_conflict");
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
            if(candidate.care_enabled_){const auto p=candidate.prepare(i,c);if(p.event){const bool ending=p.receipt.ok&&(i.action==Action::end_lease||i.action==Action::expire);candidate.reserve_events(p.payment?2U:1U,p.receipt.ok&&i.action==Action::lease?1U:0U,!ending);}}
            Receipt r=candidate.apply(i,c,fault);
            if(!candidate.verify_ledger()||!candidate.verify_care())throw std::logic_error("ledger_or_care_reconciliation");
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
        if(tick<minimum_authority_tick()||tick>max_tick)throw std::invalid_argument("rights tick");
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
        if(trusted_tick<minimum_authority_tick()||trusted_tick>max_tick)throw std::invalid_argument("expiry tick");
        if(!lease_.active||trusted_tick<lease_.end)return {};
        return Intent{"expire/"+terms_.property_id+"/"+std::to_string(lease_.event_id),terms_.property_id,Action::expire};
    }
    Int last_tick()const{return last_tick_;}
    std::uint64_t digest()const{return digest_;}
    Int coin(const std::string& id)const{const auto* a=find(id);if(!a)throw std::invalid_argument("unknown account");return a->coin;}
    Journal journal() const {
        Journal j;j.terms=terms_;j.opening=opening_;j.accounts=accounts_;j.events=events_;j.title=title_;j.offer=offer_;j.lease=lease_;j.last_tick=last_tick_;j.digest=digest_;
        j.care_enabled=care_enabled_;j.stock_opening=stock_opening_;j.stock_current=stock_current_;j.grants=grants_;
        j.v2_origin=v2_origin_;j.import_clock=import_clock_;j.import_fraction_bits=import_fraction_bits_;return j;
    }
    std::string save_bytes()const{return encode(journal());}

    Int revision()const{return static_cast<Int>(events_.size());}
    Int minimum_authority_tick()const{return std::max(last_tick_,import_clock_);}
    bool care_enabled()const{return care_enabled_;}
    Int rations()const{return stock_current_;}
    const std::vector<CareGrant>& care_grants()const{return grants_;}
    bool loaded_grants_require_interruption()const{return loaded_grants_need_interruption_;}
    Receipt activate_care(const TrustedActivation& at) {
        if(!at.explicitly_authorized)return {false,false,"explicit_care_activation_required",-1};
        if(at.tick<minimum_authority_tick()||at.tick>max_tick)return {false,false,"invalid_command_tick",-1};
        if(care_enabled_)return {true,true,"care_already_enabled",-1};
        Kernel candidate=*this;
        try {
            candidate.reserve_events(1);Event e;e.tick=at.tick;e.type="care_enabled";e.actor="town";
            e.subject=meal_policy;e.note=meal_policy_sha256;e.accepted=true;e.amount=authored_opening_rations;
            candidate.append(std::move(e));candidate.care_enabled_=true;
            candidate.stock_opening_=candidate.stock_current_=authored_opening_rations;
            if(!candidate.verify_care())throw std::logic_error("activation_reconciliation");
            const Int id=candidate.events_.back().id;*this=std::move(candidate);return {true,false,"care_enabled",id};
        }catch(const std::exception& e){return {false,false,std::string("technical_failure:")+e.what(),-1};}
    }
    Receipt execute_meal(const MealCommand& input,const MealContext& at,MealFault fault=MealFault::None) {
        Kernel candidate=*this;
        try {
            auto r=candidate.apply_meal(input,at,fault);
            if(!candidate.verify_ledger()||!candidate.verify_care())throw std::logic_error("meal_reconciliation");
            *this=std::move(candidate);return r;
        }catch(const std::exception& e){return {false,false,std::string("technical_failure:")+e.what(),-1};}
    }
    Receipt release_grant(const TrustedRelease& at) {
        if(at.tick<0||at.tick>max_tick||release_name(at.reason).empty()||
           (at.reason!=ReleaseReason::Completed&&at.completed_ticks!=0))return {false,false,"invalid_release",-1};
        auto where=std::find_if(grants_.begin(),grants_.end(),[&](const CareGrant& g){return g.event_id==at.grant_event_id&&g.resident==at.resident;});
        if(where==grants_.end())return {false,false,"unknown_care_grant",-1};
        if(at.reason==ReleaseReason::Completed&&(at.completed_ticks!=where->duration_ticks||
           at.tick<where->tick||at.tick-where->tick<where->duration_ticks))return {false,false,"meal_completion_not_elapsed",-1};
        if(!where->active) {
            if(where->release_event_id<1||static_cast<std::uint64_t>(where->release_event_id)>events_.size())return {false,false,"invalid_release_cache",-1};
            const auto& old=events_[static_cast<std::size_t>(where->release_event_id-1)];
            if(old.note!=release_name(at.reason)||old.amount!=(at.reason==ReleaseReason::Completed?std::optional<Int>(at.completed_ticks):std::nullopt))
                return {false,false,"release_reason_conflict",-1};
            return {true,true,"grant_already_released",where->release_event_id};
        }
        // Historical once-release replay returns its original receipt before NEW release time validation.
        if(at.tick<minimum_authority_tick())return {false,false,"invalid_release",-1};
        Kernel candidate=*this;
        try {
            const auto offset=static_cast<std::size_t>(where-grants_.begin());auto& g=candidate.grants_[offset];
            Event e;e.tick=at.tick;e.type="care_grant_released";e.actor=g.resident;e.subject=g.site_id;
            e.accepted=true;e.note=release_name(at.reason);e.grant_event_id=g.event_id;
            if(at.reason==ReleaseReason::Completed)e.amount=at.completed_ticks;
            candidate.append(std::move(e));
            g.active=false;g.release_event_id=candidate.events_.back().id;
            if(candidate.active_grants()==0)candidate.loaded_grants_need_interruption_=false;
            const Int id=g.release_event_id;*this=std::move(candidate);return {true,false,"grant_released",id};
        }catch(const std::exception& e){return {false,false,std::string("technical_failure:")+e.what(),-1};}
    }
    bool interrupt_loaded_grants(Int trusted_tick) {
        if(trusted_tick<minimum_authority_tick()||trusted_tick>max_tick)return false;
        if(!loaded_grants_need_interruption_)return active_grants()==0;
        Kernel candidate=*this;
        for(const auto& g:grants_)if(g.active) {
            const auto r=candidate.release_grant({g.resident,g.event_id,trusted_tick,ReleaseReason::AfterLoad});if(!r.ok)return false;
        }
        candidate.loaded_grants_need_interruption_=false;*this=std::move(candidate);return true;
    }
    bool verify_care()const {
        bool enabled=false;Int stock=0;
        for(const auto& e:events_) {
            if(e.type=="care_enabled") {
                if(enabled||!e.accepted||e.subject!=meal_policy||e.note!=meal_policy_sha256||e.amount!=authored_opening_rations)return false;
                enabled=true;stock=authored_opening_rations;
            }else if(e.type=="meal_stock_consumed") {
                if(!enabled||!e.accepted||e.target!="ration"||e.amount!=1||stock<1)return false;
                --stock;
            }else if(e.type=="public_meal_shortage") {
                if(!enabled||!e.accepted||e.amount!=0||stock!=0)return false;
            }
        }
        if(enabled!=care_enabled_||stock!=stock_current_||stock_opening_!=(enabled?authored_opening_rations:0))return false;
        for(std::size_t i=0;i<grants_.size();++i) {
            const auto& g=grants_[i];if(g.event_id<1||static_cast<std::uint64_t>(g.event_id)>events_.size())return false;
            if(events_[static_cast<std::size_t>(g.event_id-1)].type!="care_meal_granted")return false;
            for(std::size_t j=i+1;j<grants_.size();++j)if(g.event_id==grants_[j].event_id||
                (g.active&&grants_[j].active&&(g.resident==grants_[j].resident||g.site_id==grants_[j].site_id)))return false;
        }
        return true;
    }
    // The UE envelope must first pass its existing exact V2 provenance/SHA/field
    // checks. This consumes only the already extracted strict V2 payload+clock.
    // It does NOT claim to parse native JSON, identify a pawn, or authorize care.
    bool import_v2_payload(const std::string& bytes,Int clock,std::uint64_t fraction_bits) {
        namespace v2=living_town::cafe_property_v2;
        if(!events_.empty()||care_enabled_||!v2_origin_.empty()||clock<0||clock>max_tick||!detail::valid_fraction(fraction_bits))return false;
        try {
            std::vector<v2::Account> opening;for(const auto& a:opening_)opening.push_back({a.id,a.opening,a.coin});
            v2::Kernel original(v2::Terms{},opening);
            if(!original.restore_bytes(bytes)||clock<original.last_tick()||(original.lease().active&&clock>=original.lease().end))return false;
            if(original.events().size()+(original.lease().active?1U:0U)>max_events)return false;
            Kernel candidate(terms_,opening_);const auto& events=original.events();std::size_t at=0;
            while(at<events.size()) {
                const std::size_t terminal=events[at].type=="pay"?at+1:at;if(terminal>=events.size())return false;
                const auto& e=events[terminal];if(!e.context)return false;const auto action=parse_action(e.action);if(!action)return false;
                const auto& c=*e.context;const std::size_t before=candidate.events_.size();
                const auto receipt=candidate.execute({e.request_id,e.subject,*action},{c.actor,c.authenticated_actor,c.space_id,c.floor_id,c.interaction_id,c.tick,c.within_reach});
                (void)receipt;const auto added=candidate.events_.size()-before;if(added==0||at+added>events.size())return false;
                for(std::size_t n=0;n<added;++n)if(detail::property_event_bytes(candidate.events_[before+n])!=v2::detail::event_bytes(events[at+n]))return false;
                at+=added;
            }
            candidate.v2_origin_=bytes;candidate.import_clock_=clock;candidate.import_fraction_bits_=fraction_bits;
            *this=std::move(candidate);return true;
        }catch(const std::exception&){return false;}
    }


    bool restore(const Journal& incoming) {
        try {
            if(incoming.document_schema!=schema||incoming.document_capability!=capability||!detail::same_terms(incoming.terms,terms_)||
                !detail::same_accounts(incoming.opening,opening_)||incoming.events.size()>max_events)return false;
            Kernel candidate(terms_,opening_);std::size_t at=0;
            if(!incoming.v2_origin.empty()) {
                if(!candidate.import_v2_payload(incoming.v2_origin,incoming.import_clock,incoming.import_fraction_bits))return false;
                at=candidate.events_.size();if(at>incoming.events.size())return false;
                for(std::size_t n=0;n<at;++n)if(!detail::same_event(candidate.events_[n],incoming.events[n]))return false;
            }else if(incoming.import_clock!=0||incoming.import_fraction_bits!=0)return false;
            while(at<incoming.events.size()) {
                const auto& first=incoming.events[at];const std::size_t before=candidate.events_.size();
                if(first.type=="care_enabled")candidate.activate_care({first.tick,true});
                else if(first.type=="care_grant_released") {
                    const auto reason=parse_release(first.note);if(!reason||!first.grant_event_id)return false;
                    candidate.release_grant({first.actor,*first.grant_event_id,first.tick,*reason,first.amount.value_or(0)});
                }else {
                    std::size_t terminal=at;
                    if(first.type=="pay") {
                        terminal=at+1;if(terminal>=incoming.events.size())return false;
                        if(incoming.events[terminal].type=="meal_stock_consumed")++terminal;
                    }else if(first.type=="meal_stock_consumed"||first.type=="public_meal_shortage")terminal=at+1;
                    if(terminal>=incoming.events.size())return false;
                    const bool meal=incoming.events[terminal].meal_command.has_value();
                    if(meal) {
                        const auto& e=incoming.events[terminal];if(!e.meal_context)return false;
                        candidate.execute_meal(*e.meal_command,*e.meal_context);
                    }else {
                        terminal=first.type=="pay"?at+1:at;if(terminal>=incoming.events.size())return false;
                        const auto& e=incoming.events[terminal];if(!e.context||e.context->actor!=e.actor||e.context->tick!=e.tick)return false;
                        const auto action=parse_action(e.action);if(!action)return false;
                        candidate.execute({e.request_id,e.subject,*action},*e.context);
                    }
                }
                const auto added=candidate.events_.size()-before;if(added==0||at+added>incoming.events.size())return false;
                for(std::size_t n=0;n<added;++n)if(!detail::same_event(candidate.events_[before+n],incoming.events[at+n]))return false;
                at+=added;
            }
            if(!candidate.verify_ledger()||!candidate.verify_care()||encode(candidate.journal())!=encode(incoming))return false;
            // Import/replay never treats recorded contact as a live reservation.
            candidate.loaded_grants_need_interruption_=candidate.active_grants()>0;
            *this=std::move(candidate);return true;
        }catch(const std::exception&){return false;}
    }
    bool restore_bytes(const std::string& bytes){const auto j=decode(bytes);return j&&restore(*j);}
};
} // living_town::cafe_world_v3
