#pragma once
namespace living_town::cafe_property_backend {
enum class Backend { LegacyV1, PropertyV2 };
// Exactly one subsystem selection, including invalid/conflicting scenario requests.
constexpr Backend Select(bool PropertyV2Flag) {return PropertyV2Flag?Backend::PropertyV2:Backend::LegacyV1;}
constexpr bool CanActivateV2(bool Flag,bool ExactV2Mode,bool Standalone,bool WorkerPreviewFlag,bool ExplicitLegacyFlag) {
    return Flag&&ExactV2Mode&&Standalone&&!WorkerPreviewFlag&&!ExplicitLegacyFlag;
}
}
