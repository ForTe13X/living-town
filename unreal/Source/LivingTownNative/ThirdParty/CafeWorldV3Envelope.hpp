#pragma once
// Portable candidate envelope, NOT native JSON/atomic disk persistence.
// Canonical FNV checksums detect accidental corruption; they are not signatures
// or cryptographic authentication. Native integration must retain the existing
// SHA256 envelope/strict provenance/WriteAtomic path with a new declared version.
#include "CafeWorldV3.hpp"
#include "DailyLifeUseV1.hpp"

namespace living_town::cafe_world_v3 {
struct SourceBindings {
    std::string core_sha256, fixture_sha256, physical_sha256, clip_sha256, roster_sha256;
    std::string property_config_sha256=source_config_sha256, catalogue_sha256=meal_policy_sha256;
};
struct ClockMetadata {Int tick=0;std::uint64_t fraction_bits=0;};
inline bool sha_token(const std::string& s) {
    if(s.size()!=64)return false;
    for(char c:s)if(!((c>='0'&&c<='9')||(c>='a'&&c<='f')))return false;
    return true;
}
inline bool valid_bindings(const SourceBindings& b) {
    return sha_token(b.core_sha256)&&sha_token(b.fixture_sha256)&&sha_token(b.physical_sha256)&&
        sha_token(b.clip_sha256)&&sha_token(b.roster_sha256)&&b.property_config_sha256==source_config_sha256&&
        b.catalogue_sha256==meal_policy_sha256;
}
inline void write_bindings(detail::Writer& w,const SourceBindings& b) {
    w.s(b.core_sha256);w.s(b.fixture_sha256);w.s(b.physical_sha256);w.s(b.clip_sha256);
    w.s(b.roster_sha256);w.s(b.property_config_sha256);w.s(b.catalogue_sha256);
}
inline SourceBindings read_bindings(detail::Reader& r) {
    SourceBindings b;b.core_sha256=r.s(64);b.fixture_sha256=r.s(64);b.physical_sha256=r.s(64);
    b.clip_sha256=r.s(64);b.roster_sha256=r.s(64);b.property_config_sha256=r.s(64);b.catalogue_sha256=r.s(64);return b;
}
inline bool same_bindings(const SourceBindings& a,const SourceBindings& b) {
    detail::Writer x,y;write_bindings(x,a);write_bindings(y,b);return x.bytes==y.bytes;
}
inline bool valid_clock_for(const Kernel& k,const ClockMetadata& clock) {
    const auto pending=static_cast<std::size_t>(std::count_if(k.care_grants().begin(),k.care_grants().end(),[](const CareGrant& g){return g.active;}));
    return clock.tick>=k.minimum_authority_tick()&&clock.tick<=max_tick&&detail::valid_fraction(clock.fraction_bits)&&
        !(k.lease().active&&clock.tick>=k.lease().end)&&
        k.events().size()+pending+(k.lease().active?1U:0U)<=max_events;
}
struct Envelope {
    std::string format="LivingTown.CafeWorldMeal.PortableEnvelope", version="3";
    std::string integrity="fnv64_canonical_not_authentication";
    SourceBindings bindings;
    ClockMetadata clock;
    std::string saved_persona="ben"; // metadata only: never possession/position
    std::string session_policy="live_native_identity_position_unchanged";
    std::string payload;
    std::uint64_t payload_digest=0;
};
inline std::string envelope_body(const Envelope& e) {
    detail::Writer w;w.s(e.format);w.s(e.version);w.s(e.integrity);write_bindings(w,e.bindings);
    w.n(e.clock.tick);w.u(e.clock.fraction_bits);w.s(e.saved_persona);w.s(e.session_policy);
    w.s(e.payload);w.u(e.payload_digest);return w.bytes;
}
inline std::string encode_envelope_document(const Envelope& e) {
    detail::Writer w;const auto body=envelope_body(e);w.s(body);
    w.u(detail::hash_bytes(14695981039346656037ULL,body));return w.bytes;
}
inline std::optional<Envelope> decode_envelope_document(const std::string& bytes) {
    if(bytes.size()>max_journal_bytes+8192U)return {};
    try {
        detail::Reader outer{bytes};const auto body=outer.s(max_journal_bytes+4096U);const auto sum=outer.u();
        if(outer.at!=bytes.size()||detail::hash_bytes(14695981039346656037ULL,body)!=sum)return {};
        detail::Reader r{body};Envelope e;e.format=r.s();e.version=r.s();e.integrity=r.s();e.bindings=read_bindings(r);
        e.clock.tick=r.n();e.clock.fraction_bits=r.u();e.saved_persona=r.s();e.session_policy=r.s();
        e.payload=r.s(max_journal_bytes);e.payload_digest=r.u();
        if(r.at!=body.size()||encode_envelope_document(e)!=bytes)return {};
        return e;
    }catch(const std::exception&){return {};}
}
inline std::optional<std::string> save_envelope(const Kernel& k,const SourceBindings& bindings,
    const ClockMetadata& clock,const std::string& saved_persona="ben") {
    if(!valid_bindings(bindings)||!valid_clock_for(k,clock)||!k.verify_ledger()||!k.verify_care()||
        (saved_persona!="aria"&&saved_persona!="ben"))return {};
    Envelope e;e.bindings=bindings;e.clock=clock;e.saved_persona=saved_persona;e.payload=k.save_bytes();
    if(e.payload.size()>max_journal_bytes)return {};
    e.payload_digest=detail::hash_bytes(14695981039346656037ULL,e.payload);return encode_envelope_document(e);
}
inline bool load_envelope(Kernel& live,const std::string& bytes,const SourceBindings& expected,ClockMetadata& live_clock) {
    const auto e=decode_envelope_document(bytes);if(!e||!valid_bindings(expected)||!valid_bindings(e->bindings)||
        !same_bindings(e->bindings,expected)||e->format!="LivingTown.CafeWorldMeal.PortableEnvelope"||e->version!="3"||
        e->integrity!="fnv64_canonical_not_authentication"||e->session_policy!="live_native_identity_position_unchanged"||
        (e->saved_persona!="aria"&&e->saved_persona!="ben")||
        detail::hash_bytes(14695981039346656037ULL,e->payload)!=e->payload_digest)return false;
    Kernel candidate=live;
    if(!candidate.restore_bytes(e->payload)||!valid_clock_for(candidate,e->clock))return false;
    // All validation/replay is complete. No pawn exists in this portable API.
    live=std::move(candidate);live_clock=e->clock;return true;
}

// First paired durable-care format. The original V3 envelope API/bytes remain
// unchanged. This V4 seam covers ONE resident's meals, not a new simulation or
// native persistence backend. Native adoption still needs SHA256 + WriteAtomic.
namespace care=living_town::daily_life_use_v1;
constexpr std::size_t max_care_bytes=32*1024*1024;
constexpr std::size_t max_paired_bytes=max_journal_bytes+max_care_bytes+16384;
namespace care_detail {
inline void grant(detail::Writer& w,const care::ApprovedUse& g) {
    w.s(g.request_id);w.s(g.resident_id);w.s(g.site_id);w.s(g.grant_id);
    w.n(static_cast<Int>(g.kind));w.n(g.tick);w.n(g.grant_event_id);
}
inline care::ApprovedUse grant(detail::Reader& r) {
    care::ApprovedUse g;g.request_id=r.s(128);g.resident_id=r.s(128);g.site_id=r.s(128);g.grant_id=r.s(128);
    const Int kind=r.n();if(kind<0||kind>2)throw std::invalid_argument("care kind");
    g.kind=static_cast<care::Kind>(kind);g.tick=r.n();g.grant_event_id=r.n();return g;
}
inline void contact(detail::Writer& w,const care::Contact& c) {
    w.s(c.resident_id);w.s(c.site_id);w.s(c.grant_id);w.b(c.freshly_observed);
    w.b(c.grounded);w.b(c.reachable);w.b(c.permission_valid);w.b(c.reservation_valid);
}
inline care::Contact contact(detail::Reader& r) {
    care::Contact c;c.resident_id=r.s(128);c.site_id=r.s(128);c.grant_id=r.s(128);
    c.freshly_observed=r.b();c.grounded=r.b();c.reachable=r.b();c.permission_valid=r.b();c.reservation_valid=r.b();return c;
}
inline int small(detail::Reader& r,Int low,Int high) {
    const Int n=r.n();if(n<low||n>high)throw std::invalid_argument("care integer range");return static_cast<int>(n);
}
}
inline std::string encode_care_document(const care::Journal& j) {
    detail::Writer w;w.s(j.schema);w.s(j.version);w.s(j.resident);w.n(j.tick);
    w.n(j.needs.hunger);w.n(j.needs.energy);w.n(j.needs.hygiene);w.n(j.needs.fun);
    w.b(bool(j.active));if(j.active){care_detail::grant(w,j.active->grant);w.n(j.active->elapsed);}
    w.n(static_cast<Int>(j.requests.size()));
    for(const auto& x:j.requests){care_detail::grant(w,x.grant);w.b(x.receipt.accepted);w.b(x.receipt.already_applied);w.s(x.receipt.reason);w.n(x.progressed_ticks);w.n(static_cast<Int>(x.end));w.n(x.end_tick);}
    w.n(static_cast<Int>(j.history.size()));
    for(const auto& x:j.history){w.n(static_cast<Int>(x.op));w.n(x.tick);w.b(bool(x.grant));if(x.grant)care_detail::grant(w,*x.grant);w.b(bool(x.contact));if(x.contact)care_detail::contact(w,*x.contact);}
    return w.bytes;
}
inline std::optional<care::Journal> decode_care_document(const std::string& bytes) {
    if(bytes.size()>max_care_bytes)return {};
    try {
        detail::Reader r{bytes};care::Journal j;j.schema=r.s(128);j.version=r.s(16);j.resident=r.s(128);j.tick=r.n();
        j.needs.hunger=care_detail::small(r,0,care::full);j.needs.energy=care_detail::small(r,0,care::full);j.needs.hygiene=care_detail::small(r,0,care::full);j.needs.fun=care_detail::small(r,0,care::full);
        if(r.b()){care::ActiveUse a;a.grant=care_detail::grant(r);a.elapsed=care_detail::small(r,0,40);j.active=std::move(a);}
        const auto requests=r.count(care::max_requests);j.requests.reserve(requests);
        for(std::size_t i=0;i<requests;++i){care::RequestRecord x;x.grant=care_detail::grant(r);x.receipt.accepted=r.b();x.receipt.already_applied=r.b();x.receipt.reason=r.s(128);x.progressed_ticks=care_detail::small(r,0,40);x.end=static_cast<care::End>(care_detail::small(r,0,4));x.end_tick=r.n();j.requests.push_back(std::move(x));}
        const auto history=r.count(care::max_history);j.history.reserve(history);
        for(std::size_t i=0;i<history;++i){care::Transition x;x.op=static_cast<care::Op>(care_detail::small(r,0,5));x.tick=r.n();if(r.b())x.grant=care_detail::grant(r);if(r.b())x.contact=care_detail::contact(r);j.history.push_back(std::move(x));}
        if(r.at!=bytes.size()||encode_care_document(j)!=bytes)return {};
        care::ResidentUse checked(j.resident);if(!checked.restore_state(j))return {};
        return j;
    }catch(const std::exception&){return {};}
}
inline std::string meal_use_id(Int event_id){return "world-meal/"+std::to_string(event_id);}
inline care::ApprovedUse approved_meal(const CareGrant& g) {
    return {g.request_id,g.resident,g.site_id,meal_use_id(g.event_id),care::Kind::Eat,g.tick,g.event_id};
}
inline bool care_matches_world(const Kernel& world,const care::ResidentUse& use) {
    if(!world.verify_ledger()||!world.verify_care()||use.requests().size()!=world.care_grants().size())return false;
    for(const auto& g:world.care_grants()) {
        const auto it=std::find_if(use.requests().begin(),use.requests().end(),[&](const care::RequestRecord& x){return x.grant.grant_event_id==g.event_id;});
        if(it==use.requests().end()||g.resident!=use.resident()||!care::same_request(it->grant,approved_meal(g))||
           g.duration_ticks!=18||g.hunger_gain!=50||g.fun_gain!=3)return false;
        if(g.active) {
            if(it->end!=care::End::Active||!use.active()||!care::same_request(use.active()->grant,it->grant))return false;
        }else {
            if(it->end==care::End::Active||g.release_event_id<1||static_cast<std::uint64_t>(g.release_event_id)>world.events().size())return false;
            const auto& e=world.events()[static_cast<std::size_t>(g.release_event_id-1)];
            const char* reason=it->end==care::End::Completed?"completed":it->end==care::End::Cancelled?"cancelled":it->end==care::End::Interrupted?"interrupted":"after_load";
            if(e.note!=reason||e.tick!=it->end_tick||e.amount!=(it->end==care::End::Completed?std::optional<Int>(18):std::nullopt))return false;
        }
    }
    return true;
}
// Composition helpers swap both values only after both sides reconcile. A native
// sole-authority owner must still advance its clock/expiry and publish all state
// together. No callback, widget, animation notify or caller-supplied needs setter.
// Explicit CPU fixture hooks, never a persisted field or native/UI command.
enum class CareCommitFault { None, AfterCareBegin, AfterCareAdvance };
inline Receipt begin_meal_use(Kernel& live,care::ResidentUse& use,const MealCommand& command,const MealContext& at,MealFault fault=MealFault::None,CareCommitFault care_fault=CareCommitFault::None) {
    if(!care_matches_world(live,use)||at.actor!=use.resident()||at.tick!=use.tick())return {false,false,"care_world_or_clock_mismatch",-1};
    try {
        Kernel candidate=live;care::ResidentUse care_candidate=use;
        const auto receipt=candidate.execute_meal(command,at,fault);
        if(receipt.ok&&!receipt.already_applied) {
            const auto& g=candidate.care_grants().back();const auto started=care_candidate.begin(approved_meal(g));
            if(!started.accepted||started.already_applied)return {false,false,"care_begin_refused_rollback",-1};
            if(care_fault==CareCommitFault::AfterCareBegin)throw std::runtime_error("injected_after_care_begin");
        }
        if(!care_matches_world(candidate,care_candidate))return {false,false,"care_reconciliation_rollback",-1};
        live=std::move(candidate);use=std::move(care_candidate);return receipt;
    }catch(const std::exception&){return {false,false,"care_transaction_exception",-1};}
}
struct CareTickReceipt {bool ok=false;care::Outcome outcome=care::Outcome::RejectedTick;std::string reason;};
inline CareTickReceipt advance_meal_use(Kernel& live,care::ResidentUse& use,Int next,const care::Contact& observation,CareCommitFault fault=CareCommitFault::None) {
    if(!care_matches_world(live,use)||live.loaded_grants_require_interruption()||next<live.minimum_authority_tick())return {false,care::Outcome::RejectedTick,"care_world_not_live"};
    try {
        Kernel candidate=live;care::ResidentUse care_candidate=use;const auto active=care_candidate.active();
        const auto outcome=care_candidate.advance_one(next,observation);
        if(outcome==care::Outcome::RejectedTick)return {false,outcome,"nonconsecutive_care_tick"};
        if(fault==CareCommitFault::AfterCareAdvance)throw std::runtime_error("injected_after_care_advance");
        if(active&&(outcome==care::Outcome::Completed||outcome==care::Outcome::Interrupted)) {
            const auto reason=outcome==care::Outcome::Completed?ReleaseReason::Completed:ReleaseReason::Interrupted;
            const auto released=candidate.release_grant({use.resident(),active->grant.grant_event_id,next,reason,outcome==care::Outcome::Completed?18:0});
            if(!released.ok)return {false,care::Outcome::RejectedTick,"care_release_refused_rollback"};
        }
        if(!care_matches_world(candidate,care_candidate))return {false,care::Outcome::RejectedTick,"care_reconciliation_rollback"};
        live=std::move(candidate);use=std::move(care_candidate);return {true,outcome,"care_tick_committed"};
    }catch(const std::exception&){return {false,care::Outcome::RejectedTick,"care_tick_exception"};}
}
inline Receipt cancel_meal_use(Kernel& live,care::ResidentUse& use,ReleaseReason reason=ReleaseReason::Cancelled) {
    if(!care_matches_world(live,use)||live.loaded_grants_require_interruption()||(reason!=ReleaseReason::Cancelled&&reason!=ReleaseReason::Interrupted))return {false,false,"invalid_care_cancel",-1};
    if(!use.active())return {true,true,"no_active_care",-1};
    try {
        Kernel candidate=live;care::ResidentUse care_candidate=use;const auto active=*care_candidate.active();
        const bool stopped=reason==ReleaseReason::Cancelled?care_candidate.cancel():care_candidate.interrupt();
        const auto receipt=candidate.release_grant({use.resident(),active.grant.grant_event_id,use.tick(),reason});
        if(!stopped||!receipt.ok||!care_matches_world(candidate,care_candidate))return {false,false,"care_cancel_refused_rollback",-1};
        live=std::move(candidate);use=std::move(care_candidate);return receipt;
    }catch(const std::exception&){return {false,false,"care_cancel_exception",-1};}
}
struct CareBindings {SourceBindings world;std::string care_core_sha256;};
inline bool valid_care_bindings(const CareBindings& b){return valid_bindings(b.world)&&sha_token(b.care_core_sha256);}
struct CareEnvelope {
    std::string format="LivingTown.CafeWorldMealCare.PortableEnvelope",version="4",integrity="fnv64_canonical_not_authentication";
    CareBindings bindings;ClockMetadata clock;
    std::string saved_persona="ben",session_policy="live_native_identity_position_unchanged";
    std::string world_payload,care_payload;
    std::uint64_t world_digest=0,care_digest=0;
};
inline std::string encode_care_envelope_document(const CareEnvelope& e) {
    detail::Writer body;body.s(e.format);body.s(e.version);body.s(e.integrity);write_bindings(body,e.bindings.world);body.s(e.bindings.care_core_sha256);
    body.n(e.clock.tick);body.u(e.clock.fraction_bits);body.s(e.saved_persona);body.s(e.session_policy);
    body.s(e.world_payload);body.u(e.world_digest);body.s(e.care_payload);body.u(e.care_digest);
    detail::Writer out;out.s(body.bytes);out.u(detail::hash_bytes(14695981039346656037ULL,body.bytes));return out.bytes;
}
inline std::optional<CareEnvelope> decode_care_envelope_document(const std::string& bytes) {
    if(bytes.size()>max_paired_bytes)return {};
    try {
        detail::Reader outer{bytes};const auto body=outer.s(max_paired_bytes);const auto hash=outer.u();
        if(outer.at!=bytes.size()||detail::hash_bytes(14695981039346656037ULL,body)!=hash)return {};
        detail::Reader r{body};CareEnvelope e;e.format=r.s(128);e.version=r.s(16);e.integrity=r.s(128);e.bindings.world=read_bindings(r);e.bindings.care_core_sha256=r.s(64);
        e.clock.tick=r.n();e.clock.fraction_bits=r.u();e.saved_persona=r.s(128);e.session_policy=r.s(128);
        e.world_payload=r.s(max_journal_bytes);e.world_digest=r.u();e.care_payload=r.s(max_care_bytes);e.care_digest=r.u();
        if(r.at!=body.size()||encode_care_envelope_document(e)!=bytes)return {};
        return e;
    }catch(const std::exception&){return {};}
}
inline std::optional<std::string> save_care_envelope(const Kernel& world,const care::ResidentUse& use,const CareBindings& bindings,const ClockMetadata& clock,const std::string& persona="ben") {
    if(!valid_care_bindings(bindings)||!valid_clock_for(world,clock)||clock.tick!=use.tick()||
       !care_matches_world(world,use)||(persona!="aria"&&persona!="ben"))return {};
    care::ResidentUse checked(use.resident());if(!checked.restore_state(use.export_state()))return {};
    CareEnvelope e;e.bindings=bindings;e.clock=clock;e.saved_persona=persona;e.world_payload=world.save_bytes();e.care_payload=encode_care_document(use.export_state());
    if(e.world_payload.size()>max_journal_bytes||e.care_payload.size()>max_care_bytes)return {};
    e.world_digest=detail::hash_bytes(14695981039346656037ULL,e.world_payload);e.care_digest=detail::hash_bytes(14695981039346656037ULL,e.care_payload);return encode_care_envelope_document(e);
}
inline bool load_care_envelope(Kernel& live,care::ResidentUse& use,const std::string& bytes,const CareBindings& expected,ClockMetadata& clock) {
    const auto e=decode_care_envelope_document(bytes);
    if(!e||!valid_care_bindings(expected)||!valid_care_bindings(e->bindings)||
       !same_bindings(expected.world,e->bindings.world)||expected.care_core_sha256!=e->bindings.care_core_sha256||
       e->format!="LivingTown.CafeWorldMealCare.PortableEnvelope"||e->version!="4"||e->integrity!="fnv64_canonical_not_authentication"||
       e->session_policy!="live_native_identity_position_unchanged"||(e->saved_persona!="aria"&&e->saved_persona!="ben")||
       detail::hash_bytes(14695981039346656037ULL,e->world_payload)!=e->world_digest||detail::hash_bytes(14695981039346656037ULL,e->care_payload)!=e->care_digest)return false;
    const auto journal=decode_care_document(e->care_payload);if(!journal)return false;
    Kernel candidate=live;care::ResidentUse care_candidate=use;
    if(!candidate.restore_bytes(e->world_payload)||!care_candidate.restore_state(*journal)||
       !valid_clock_for(candidate,e->clock)||e->clock.tick!=care_candidate.tick()||!care_matches_world(candidate,care_candidate))return false;
    // Saved observations are historical. Release actual recorded reservations
    // and invalidate use together before publication; keep earned needs/fun.
    if(!candidate.interrupt_loaded_grants(e->clock.tick))return false;
    care_candidate.invalidate_use_after_load();
    if(!care_matches_world(candidate,care_candidate))return false;
    live=std::move(candidate);use=std::move(care_candidate);clock=e->clock;return true;
}
} // namespace living_town::cafe_world_v3
