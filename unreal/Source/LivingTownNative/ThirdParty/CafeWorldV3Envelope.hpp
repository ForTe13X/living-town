#pragma once
// Portable candidate envelope, NOT native JSON/atomic disk persistence.
// Canonical FNV checksums detect accidental corruption; they are not signatures
// or cryptographic authentication. Native integration must retain the existing
// SHA256 envelope/strict provenance/WriteAtomic path with a new declared version.
#include "CafeWorldV3.hpp"

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
} // namespace living_town::cafe_world_v3
