#pragma once
// Proposed shared selector only. No runtime subsystem/entrypoint was edited.
namespace living_town::cafe_backend_v3 {
enum class Backend { Invalid, LegacyV1, PropertyV2, WorldV3 };
struct Flags {bool property_v2=false,world_v3=false,explicit_legacy=false,worker_preview=false;};
constexpr Backend select(Flags f) {
    const int count=(f.property_v2?1:0)+(f.world_v3?1:0)+(f.explicit_legacy?1:0);
    if(count>1||(f.worker_preview&&(f.property_v2||f.world_v3)))return Backend::Invalid;
    return f.world_v3?Backend::WorldV3:(f.property_v2?Backend::PropertyV2:Backend::LegacyV1);
}
enum class ExactMode {Other,LegacyV1,PropertyV2,WorldV3};
constexpr bool can_activate(Backend b,ExactMode mode,bool standalone,bool worker_preview) {
    if(!standalone||worker_preview)return false;
    return (b==Backend::LegacyV1&&mode==ExactMode::LegacyV1)||
        (b==Backend::PropertyV2&&mode==ExactMode::PropertyV2)||
        (b==Backend::WorldV3&&mode==ExactMode::WorldV3);
}
} // namespace living_town::cafe_backend_v3
