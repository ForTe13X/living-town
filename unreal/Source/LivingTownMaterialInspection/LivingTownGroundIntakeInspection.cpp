#include "LivingTownGroundIntakeInspection.h"
#include "LivingTownTileData.h"
#include "Engine/StaticMesh.h"
#include "Engine/StaticMeshSourceData.h"
#include "Engine/Texture2D.h"
#include "Engine/TextureLODSettings.h"
#include "MeshDescription.h"
#include "MeshDescriptionBase.h"
#include "StaticMeshAttributes.h"
#include "StaticMeshResources.h"
#include "PhysicsEngine/BodySetup.h"
#include "PhysicsEngine/BodyInstance.h"
#include "PhysicsEngine/AggregateGeom.h"
#include "Interfaces/Interface_CollisionDataProvider.h"
#include "Chaos/TriangleMeshImplicitObject.h"
#include "DeviceProfiles/DeviceProfile.h"
#include "DeviceProfiles/DeviceProfileManager.h"
#include "TextureResource.h"
#include "RenderingThread.h"
#include "RHI.h"
#include "RHIResources.h"
#include "DynamicRHI.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/ScopeTryLock.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformTime.h"
#include "HAL/PlatformMisc.h"
#include "UObject/StrongObjectPtr.h"
#include "UObject/Package.h"
#include <atomic>
#include <type_traits>
#if PLATFORM_WINDOWS
#include "Windows/WindowsHWrapper.h"
#endif

namespace GroundIntake
{
constexpr uint32 MaxV=200000,MaxT=200000,MaxShapes=8,MaxSections=64,MaxUV=8,MaxSimple=256;
constexpr uint64 FileCap=32ull<<20,CallCap=256ull<<20,SessionCap=512ull<<20;
constexpr uint32 NoShape=0xffffffffu;
constexpr ANSICHAR Magic[]="LTGROUNDCHAO0001";
static_assert(sizeof(Magic)==17,"16-byte protocol magic");
constexpr const TCHAR* Prefix=TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/");
const TCHAR* const MeshRoster[]={
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00010_zm00008.SM_CC_Terrain_xm00010_zm00008"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00010_zm00007.SM_CC_Terrain_xm00010_zm00007"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00010_zm00006.SM_CC_Terrain_xm00010_zm00006"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00010_zm00005.SM_CC_Terrain_xm00010_zm00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00010_zm00004.SM_CC_Terrain_xm00010_zm00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00010_zm00003.SM_CC_Terrain_xm00010_zm00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00010_zm00002.SM_CC_Terrain_xm00010_zm00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00010_zm00001.SM_CC_Terrain_xm00010_zm00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00010_zp00000.SM_CC_Terrain_xm00010_zp00000"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00010_zp00001.SM_CC_Terrain_xm00010_zp00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00010_zp00002.SM_CC_Terrain_xm00010_zp00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00010_zp00003.SM_CC_Terrain_xm00010_zp00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00010_zp00004.SM_CC_Terrain_xm00010_zp00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00010_zp00005.SM_CC_Terrain_xm00010_zp00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00009_zm00008.SM_CC_Terrain_xm00009_zm00008"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00009_zm00007.SM_CC_Terrain_xm00009_zm00007"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00009_zm00006.SM_CC_Terrain_xm00009_zm00006"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00009_zm00005.SM_CC_Terrain_xm00009_zm00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00009_zm00004.SM_CC_Terrain_xm00009_zm00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00009_zm00003.SM_CC_Terrain_xm00009_zm00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00009_zm00002.SM_CC_Terrain_xm00009_zm00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00009_zm00001.SM_CC_Terrain_xm00009_zm00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00009_zp00000.SM_CC_Terrain_xm00009_zp00000"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00009_zp00001.SM_CC_Terrain_xm00009_zp00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00009_zp00002.SM_CC_Terrain_xm00009_zp00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00009_zp00003.SM_CC_Terrain_xm00009_zp00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00009_zp00004.SM_CC_Terrain_xm00009_zp00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00009_zp00005.SM_CC_Terrain_xm00009_zp00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00008_zm00008.SM_CC_Terrain_xm00008_zm00008"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00008_zm00007.SM_CC_Terrain_xm00008_zm00007"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00008_zm00006.SM_CC_Terrain_xm00008_zm00006"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00008_zm00005.SM_CC_Terrain_xm00008_zm00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00008_zm00004.SM_CC_Terrain_xm00008_zm00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00008_zm00003.SM_CC_Terrain_xm00008_zm00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00008_zm00002.SM_CC_Terrain_xm00008_zm00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00008_zm00001.SM_CC_Terrain_xm00008_zm00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00008_zp00000.SM_CC_Terrain_xm00008_zp00000"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00008_zp00001.SM_CC_Terrain_xm00008_zp00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00008_zp00002.SM_CC_Terrain_xm00008_zp00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00008_zp00003.SM_CC_Terrain_xm00008_zp00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00008_zp00004.SM_CC_Terrain_xm00008_zp00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00008_zp00005.SM_CC_Terrain_xm00008_zp00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00007_zm00008.SM_CC_Terrain_xm00007_zm00008"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00007_zm00007.SM_CC_Terrain_xm00007_zm00007"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00007_zm00006.SM_CC_Terrain_xm00007_zm00006"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00007_zm00005.SM_CC_Terrain_xm00007_zm00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00007_zm00004.SM_CC_Terrain_xm00007_zm00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00007_zm00003.SM_CC_Terrain_xm00007_zm00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00007_zm00002.SM_CC_Terrain_xm00007_zm00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00007_zm00001.SM_CC_Terrain_xm00007_zm00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00007_zp00000.SM_CC_Terrain_xm00007_zp00000"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00007_zp00001.SM_CC_Terrain_xm00007_zp00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00007_zp00002.SM_CC_Terrain_xm00007_zp00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00007_zp00003.SM_CC_Terrain_xm00007_zp00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00007_zp00004.SM_CC_Terrain_xm00007_zp00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00007_zp00005.SM_CC_Terrain_xm00007_zp00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00006_zm00008.SM_CC_Terrain_xm00006_zm00008"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00006_zm00007.SM_CC_Terrain_xm00006_zm00007"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00006_zm00006.SM_CC_Terrain_xm00006_zm00006"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00006_zm00005.SM_CC_Terrain_xm00006_zm00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00006_zm00004.SM_CC_Terrain_xm00006_zm00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00006_zm00003.SM_CC_Terrain_xm00006_zm00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00006_zm00002.SM_CC_Terrain_xm00006_zm00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00006_zm00001.SM_CC_Terrain_xm00006_zm00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00006_zp00000.SM_CC_Terrain_xm00006_zp00000"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00006_zp00001.SM_CC_Terrain_xm00006_zp00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00006_zp00002.SM_CC_Terrain_xm00006_zp00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00006_zp00003.SM_CC_Terrain_xm00006_zp00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00006_zp00004.SM_CC_Terrain_xm00006_zp00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00006_zp00005.SM_CC_Terrain_xm00006_zp00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00005_zm00008.SM_CC_Terrain_xm00005_zm00008"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00005_zm00007.SM_CC_Terrain_xm00005_zm00007"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00005_zm00006.SM_CC_Terrain_xm00005_zm00006"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00005_zm00005.SM_CC_Terrain_xm00005_zm00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00005_zm00004.SM_CC_Terrain_xm00005_zm00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00005_zm00003.SM_CC_Terrain_xm00005_zm00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00005_zm00002.SM_CC_Terrain_xm00005_zm00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00005_zm00001.SM_CC_Terrain_xm00005_zm00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00005_zp00000.SM_CC_Terrain_xm00005_zp00000"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00005_zp00001.SM_CC_Terrain_xm00005_zp00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00005_zp00002.SM_CC_Terrain_xm00005_zp00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00005_zp00003.SM_CC_Terrain_xm00005_zp00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00005_zp00004.SM_CC_Terrain_xm00005_zp00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00005_zp00005.SM_CC_Terrain_xm00005_zp00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00004_zm00008.SM_CC_Terrain_xm00004_zm00008"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00004_zm00007.SM_CC_Terrain_xm00004_zm00007"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00004_zm00006.SM_CC_Terrain_xm00004_zm00006"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00004_zm00005.SM_CC_Terrain_xm00004_zm00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00004_zm00004.SM_CC_Terrain_xm00004_zm00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00004_zm00003.SM_CC_Terrain_xm00004_zm00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00004_zm00002.SM_CC_Terrain_xm00004_zm00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00004_zm00001.SM_CC_Terrain_xm00004_zm00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00004_zp00000.SM_CC_Terrain_xm00004_zp00000"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00004_zp00001.SM_CC_Terrain_xm00004_zp00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00004_zp00002.SM_CC_Terrain_xm00004_zp00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00004_zp00003.SM_CC_Terrain_xm00004_zp00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00004_zp00004.SM_CC_Terrain_xm00004_zp00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00004_zp00005.SM_CC_Terrain_xm00004_zp00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00003_zm00008.SM_CC_Terrain_xm00003_zm00008"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00003_zm00007.SM_CC_Terrain_xm00003_zm00007"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00003_zm00006.SM_CC_Terrain_xm00003_zm00006"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00003_zm00005.SM_CC_Terrain_xm00003_zm00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00003_zm00004.SM_CC_Terrain_xm00003_zm00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00003_zm00003.SM_CC_Terrain_xm00003_zm00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00003_zm00002.SM_CC_Terrain_xm00003_zm00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00003_zm00001.SM_CC_Terrain_xm00003_zm00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00003_zp00000.SM_CC_Terrain_xm00003_zp00000"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00003_zp00001.SM_CC_Terrain_xm00003_zp00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00003_zp00002.SM_CC_Terrain_xm00003_zp00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00003_zp00003.SM_CC_Terrain_xm00003_zp00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00003_zp00004.SM_CC_Terrain_xm00003_zp00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00003_zp00005.SM_CC_Terrain_xm00003_zp00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00002_zm00008.SM_CC_Terrain_xm00002_zm00008"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00002_zm00007.SM_CC_Terrain_xm00002_zm00007"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00002_zm00006.SM_CC_Terrain_xm00002_zm00006"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00002_zm00005.SM_CC_Terrain_xm00002_zm00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00002_zm00004.SM_CC_Terrain_xm00002_zm00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00002_zm00003.SM_CC_Terrain_xm00002_zm00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00002_zm00002.SM_CC_Terrain_xm00002_zm00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00002_zm00001.SM_CC_Terrain_xm00002_zm00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00002_zp00000.SM_CC_Terrain_xm00002_zp00000"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00002_zp00001.SM_CC_Terrain_xm00002_zp00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00002_zp00002.SM_CC_Terrain_xm00002_zp00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00002_zp00003.SM_CC_Terrain_xm00002_zp00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00002_zp00004.SM_CC_Terrain_xm00002_zp00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00002_zp00005.SM_CC_Terrain_xm00002_zp00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00001_zm00008.SM_CC_Terrain_xm00001_zm00008"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00001_zm00007.SM_CC_Terrain_xm00001_zm00007"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00001_zm00006.SM_CC_Terrain_xm00001_zm00006"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00001_zm00005.SM_CC_Terrain_xm00001_zm00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00001_zm00004.SM_CC_Terrain_xm00001_zm00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00001_zm00003.SM_CC_Terrain_xm00001_zm00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00001_zm00002.SM_CC_Terrain_xm00001_zm00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00001_zm00001.SM_CC_Terrain_xm00001_zm00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00001_zp00000.SM_CC_Terrain_xm00001_zp00000"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00001_zp00001.SM_CC_Terrain_xm00001_zp00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00001_zp00002.SM_CC_Terrain_xm00001_zp00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00001_zp00003.SM_CC_Terrain_xm00001_zp00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00001_zp00004.SM_CC_Terrain_xm00001_zp00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xm00001_zp00005.SM_CC_Terrain_xm00001_zp00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xp00000_zm00008.SM_CC_Terrain_xp00000_zm00008"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xp00000_zm00007.SM_CC_Terrain_xp00000_zm00007"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xp00000_zm00006.SM_CC_Terrain_xp00000_zm00006"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xp00000_zm00005.SM_CC_Terrain_xp00000_zm00005"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xp00000_zm00004.SM_CC_Terrain_xp00000_zm00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xp00000_zm00003.SM_CC_Terrain_xp00000_zm00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xp00000_zm00002.SM_CC_Terrain_xp00000_zm00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xp00000_zm00001.SM_CC_Terrain_xp00000_zm00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xp00000_zp00000.SM_CC_Terrain_xp00000_zp00000"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xp00000_zp00001.SM_CC_Terrain_xp00000_zp00001"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xp00000_zp00002.SM_CC_Terrain_xp00000_zp00002"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xp00000_zp00003.SM_CC_Terrain_xp00000_zp00003"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xp00000_zp00004.SM_CC_Terrain_xp00000_zp00004"),
    TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/Terrain/SM_CC_Terrain_xp00000_zp00005.SM_CC_Terrain_xp00000_zp00005"),
};
struct FTextureExpected{const TCHAR* Path;int32 Width,Height,Mips;EPixelFormat Format;};
const FTextureExpected TextureRoster[]={
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/TerrainTextures/T_CC_Terrain_SRC0375.T_CC_Terrain_SRC0375"),512,512,10,PF_BC5},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/TerrainTextures/T_CC_Terrain_SRC0376.T_CC_Terrain_SRC0376"),1024,1024,11,PF_BC7},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/TerrainTextures/T_CC_Terrain_SRC0377.T_CC_Terrain_SRC0377"),512,512,10,PF_BC7},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/TerrainTextures/T_CC_Terrain_SRC0378.T_CC_Terrain_SRC0378"),2048,2048,12,PF_BC5},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/TerrainTextures/T_CC_Terrain_SRC0379.T_CC_Terrain_SRC0379"),2048,2048,12,PF_BC7},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/TerrainTextures/T_CC_Terrain_SRC0380.T_CC_Terrain_SRC0380"),2048,2048,12,PF_BC7},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/TerrainTextures/T_CC_Terrain_SRC0381.T_CC_Terrain_SRC0381"),8192,8192,14,PF_BC5},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/TerrainTextures/T_CC_Terrain_SRC0382.T_CC_Terrain_SRC0382"),8192,8192,14,PF_BC7},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/TerrainTextures/T_CC_Terrain_SRC0383.T_CC_Terrain_SRC0383"),8192,8192,14,PF_BC7},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/TerrainTextures/T_CC_Terrain_SRC0384.T_CC_Terrain_SRC0384"),2048,2048,12,PF_BC5},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/TerrainTextures/T_CC_Terrain_SRC0385.T_CC_Terrain_SRC0385"),2048,2048,12,PF_BC7},
    {TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/CoherentContextHybridN20_v001/TerrainTextures/T_CC_Terrain_SRC0386.T_CC_Terrain_SRC0386"),2048,2048,12,PF_BC7},
};
static_assert(UE_ARRAY_COUNT(MeshRoster)==154,"Exact source ground roster");
static_assert(UE_ARRAY_COUNT(TextureRoster)==12,"Exact source texture roster");

FString Json(const TSharedRef<FJsonObject>& O)
{
    FString Text;FJsonSerializer::Serialize(O,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Text));
    return Text.Len()<=2*1024*1024?Text:TEXT("{\"status\":\"ERROR\",\"reason\":\"json_bound\"}");
}
FString Reply(const TCHAR* Status,const FString& Why)
{auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),Status);O->SetStringField(TEXT("reason"),Why);O->SetBoolField(TEXT("asset_repaired_or_saved"),false);return Json(O);}
bool Refuse(FString& Error,const FString& Why){Error=Why;return false;}
bool Count(int64 N,int64 Cap){return N>=0&&N<=Cap;}
template<typename V> bool FinitePoint(const V& P){return FMath::IsFinite(P[0])&&FMath::IsFinite(P[1])&&FMath::IsFinite(P[2]);}
bool Triangle(int64 A,int64 B,int64 C,int64 V){return A>=0&&B>=0&&C>=0&&A<V&&B<V&&C<V&&A!=B&&B!=C&&A!=C;}
int32 RosterIndex(const FString& Path)
{if(!Path.StartsWith(Prefix,ESearchCase::CaseSensitive))return INDEX_NONE;for(int32 I=0;I<UE_ARRAY_COUNT(MeshRoster);++I)if(Path.Equals(MeshRoster[I],ESearchCase::CaseSensitive))return I;return INDEX_NONE;}
const FTextureExpected* TextureExpected(const FString& Path)
{if(!Path.StartsWith(Prefix,ESearchCase::CaseSensitive))return nullptr;for(const auto& R:TextureRoster)if(Path.Equals(R.Path,ESearchCase::CaseSensitive))return &R;return nullptr;}
bool NoReparse(const FString& Absolute)
{
#if PLATFORM_WINDOWS
    FString N=Absolute.Replace(TEXT("/"),TEXT("\\"));if(N.Len()<3||N[1]!=':'||N[2]!='\\')return false;
    FString P=N.Left(3);TArray<FString> Parts;N.Mid(3).ParseIntoArray(Parts,TEXT("\\"),true);
    auto Check=[](const FString& X){const DWORD A=GetFileAttributesW(*X);return A!=INVALID_FILE_ATTRIBUTES&&!(A&FILE_ATTRIBUTE_REPARSE_POINT);};
    if(!Check(P))return false;for(const FString& X:Parts){if(X==TEXT(".")||X==TEXT(".."))return false;P=FPaths::Combine(P,X);if(!Check(P))return false;}return true;
#else
    return false;
#endif
}
bool Leaf(const FString& Name)
{if(Name.IsEmpty()||Name.Len()>64)return false;for(TCHAR C:Name)if(!((C>='a'&&C<='z')||(C>='A'&&C<='Z')||(C>='0'&&C<='9')||C=='_'))return false;return true;}
bool NewJson(const FString& P,const TSharedRef<FJsonObject>& O)
{return FFileHelper::SaveStringToFile(Json(O)+TEXT("\n"),*P,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM,&IFileManager::Get(),FILEWRITE_NoReplaceExisting);}
bool Digest(const FString& P,uint64 Cap,FString& Hash,int64& Bytes)
{Bytes=IFileManager::Get().FileSize(*P);if(Bytes<0||uint64(Bytes)>Cap||!NoReparse(P))return false;TArray<uint8> B;if(!FFileHelper::LoadFileToArray(B,*P)||B.Num()!=Bytes)return false;return LivingTownTiles::HashBytes(B,Hash)&&IFileManager::Get().FileSize(*P)==Bytes;}

class FWriter
{
    TUniquePtr<FArchive> File;TArray<uint8> Buffer;uint64 Written=0;bool Good=false;
    void Flush(){if(File&&Buffer.Num()){File->Serialize(Buffer.GetData(),Buffer.Num());Good&=!File->IsError();Buffer.Reset();}}
public:
    explicit FWriter(const FString& Path){File.Reset(IFileManager::Get().CreateFileWriter(*Path,FILEWRITE_NoReplaceExisting));Buffer.Reserve(65536);Good=File.IsValid();}
    void U8(uint8 X){if(!Good||Written>=FileCap){Good=false;return;}Buffer.Add(X);++Written;if(Buffer.Num()>=65536)Flush();}
    void U32(uint32 X){for(int32 I=0;I<4;++I)U8(uint8(X>>(8*I)));}
    void I32(int32 X){U32(uint32(X));}
    void U64(uint64 X){for(int32 I=0;I<8;++I)U8(uint8(X>>(8*I)));}
    template<typename Scalar> void Number(Scalar X)
    {static_assert(std::is_same_v<Scalar,float>||std::is_same_v<Scalar,double>);if(!FMath::IsFinite(X)){Good=false;return;}if constexpr(sizeof(Scalar)==4){uint32 B;FMemory::Memcpy(&B,&X,4);U32(B);}else{uint64 B;FMemory::Memcpy(&B,&X,8);U64(B);}}
    template<typename V> void Point(const V& P){using Scalar=std::remove_cv_t<std::remove_reference_t<decltype(P[0])>>;Number<Scalar>(P[0]);Number<Scalar>(P[1]);Number<Scalar>(P[2]);}
    uint64 Tell()const{return Written;}
    bool Finish(){Flush();if(!File)return false;const bool Closed=File->Close();Good&=Closed&&!File->IsError();File.Reset();return Good;}
};
struct FEntry
{
    uint32 Kind=0,Shape=NoShape,Stride=0,N=0,PositionBytes=0,IndexBytes=0,Flags=0;
    uint64 Offset=0,Bytes=0;TFunction<void(FWriter&)> Emit;
};
struct FSnapshot
{
    TStrongObjectPtr<UStaticMesh> Mesh;const UBodySetup* Body=nullptr;const FStaticMeshLODResources* Render=nullptr;
    const FMeshDescription* MD=nullptr;TUniquePtr<FScopeTryLock> MDLock;FTriMeshCollisionData Provider;
    TArray<FEntry> Entries;TSharedRef<FJsonObject> Meta=MakeShared<FJsonObject>();
    int32 Roster=INDEX_NONE;bool Dirty=false;FGuid Guid;FString PackageFile,PackageHash;int64 PackageBytes=0;uint64 Expected=0;
};

bool Preflight(FSnapshot& S,FString& Error)
{
    UStaticMesh* M=S.Mesh.Get();
    if(M->IsCompiling())return Refuse(Error,TEXT("HOLD_mesh_compiling_no_wait"));
    if(M->GetNumSourceModels()!=1)return Refuse(Error,TEXT("source_LOD0_only"));
    if(!M->bAllowCPUAccess||M->GetNaniteSettings().bEnabled||(M->ComplexCollisionMesh&&M->ComplexCollisionMesh!=M))return Refuse(Error,TEXT("ground_CPU_nonNanite_no_external_collision_required"));
    const FStaticMeshRenderData* RD=M->GetRenderData();if(!RD||RD->LODResources.Num()!=1)return Refuse(Error,TEXT("HOLD_render_LOD0_not_ready"));
    const auto& L=RD->LODResources[0];const uint32 V=L.VertexBuffers.PositionVertexBuffer.GetNumVertices(),NI=L.IndexBuffer.GetNumIndices();
    if(!V||!NI||NI%3||!Count(V,MaxV)||!Count(NI/3,MaxT)||!Count(L.Sections.Num(),MaxSections)||!Count(L.VertexBuffers.StaticMeshVertexBuffer.GetNumTexCoords(),MaxUV)||!L.IndexBuffer.GetAllowCPUAccess()||!L.VertexBuffers.PositionVertexBuffer.GetVertexData())return Refuse(Error,TEXT("render_preallocation_bounds_or_CPU_data"));
    S.Render=&L;uint64 ST=0;for(const auto& Section:L.Sections){ST+=Section.NumTriangles;if(ST>MaxT||uint64(Section.FirstIndex)+uint64(Section.NumTriangles)*3>NI)return Refuse(Error,TEXT("render_sections_bound"));}
    if(ST!=NI/3)return Refuse(Error,TEXT("render_section_full_coverage"));
    const FIndexArrayView Ind=L.IndexBuffer.GetArrayView();if(Ind.Num()!=int32(NI))return Refuse(Error,TEXT("render_index_count"));
    for(uint32 I=0;I<V;++I)if(!FinitePoint(L.VertexBuffers.PositionVertexBuffer.VertexPosition(I)))return Refuse(Error,TEXT("render_nonfinite_P"));
    for(uint32 I=0;I<NI;I+=3)if(!Triangle(Ind[I],Ind[I+1],Ind[I+2],V))return Refuse(Error,TEXT("render_invalid_indices"));
    const FStaticMeshSourceModel& Source=M->GetSourceModel(0);S.MDLock=MakeUnique<FScopeTryLock>(&Source.StaticMeshDescriptionBulkDataCS);
    if(!S.MDLock->IsLocked())return Refuse(Error,TEXT("HOLD_source_MD_busy_no_wait"));
    const UStaticMeshDescriptionBulkData* Bulk=Source.StaticMeshDescriptionBulkData;
    if(!Bulk||!Bulk->HasCachedMeshDescription())return Refuse(Error,TEXT("HOLD_source_MD_not_resident_no_load"));
    const UMeshDescriptionBase* Wrapper=Bulk->GetMeshDescription();if(!Wrapper)return Refuse(Error,TEXT("source_MD_wrapper"));S.MD=&Wrapper->GetMeshDescription();const auto& D=*S.MD;
    if(!Count(D.Vertices().Num(),MaxV)||!Count(D.Vertices().GetArraySize(),MaxV)||!Count(D.Triangles().Num(),MaxT)||!Count(D.Triangles().GetArraySize(),MaxT)||!Count(D.VertexInstances().Num(),uint64(MaxT)*3)||!Count(D.VertexInstances().GetArraySize(),uint64(MaxT)*3)||!Count(D.PolygonGroups().GetArraySize(),MaxSections))return Refuse(Error,TEXT("source_MD_count_or_ID_extent"));
    const auto Pos=FStaticMeshConstAttributes(D).GetVertexPositions();for(FVertexID ID:D.Vertices().GetElementIDs())if(!FinitePoint(Pos[ID]))return Refuse(Error,TEXT("source_MD_nonfinite"));
    for(FTriangleID ID:D.Triangles().GetElementIDs()){const auto T=D.GetTriangleVertices(ID);if(T.Num()!=3||!D.IsVertexValid(T[0])||!D.IsVertexValid(T[1])||!D.IsVertexValid(T[2])||!D.IsPolygonGroupValid(D.GetTrianglePolygonGroup(ID))||!Triangle(T[0].GetValue(),T[1].GetValue(),T[2].GetValue(),D.Vertices().GetArraySize()))return Refuse(Error,TEXT("source_MD_invalid_triangle"));}
    S.Body=M->GetBodySetup();if(!S.Body||S.Body->GetOuter()!=M||!S.Body->bCreatedPhysicsMeshes)return Refuse(Error,TEXT("HOLD_created_BodySetup_not_ready_no_cook"));
    if(S.Body->bFailedToCreatePhysicsMeshes||!S.Body->BodySetupGuid.IsValid())return Refuse(Error,TEXT("body_failed_or_GUID_missing"));S.Guid=S.Body->BodySetupGuid;
    const auto& Simple=S.Body->AggGeom;const int64 NS=int64(Simple.SphereElems.Num())+Simple.BoxElems.Num()+Simple.SphylElems.Num()+Simple.ConvexElems.Num()+Simple.TaperedCapsuleElems.Num()+Simple.LevelSetElems.Num()+Simple.SkinnedLevelSetElems.Num()+Simple.MLLevelSetElems.Num()+Simple.SkinnedTriangleMeshElems.Num();if(!Count(NS,MaxSimple)||!Count(S.Body->TriMeshGeometries.Num(),MaxShapes))return Refuse(Error,TEXT("body_shape_bounds"));
    uint64 CV=0,CT=0;for(const auto& Shape:S.Body->TriMeshGeometries){if(!Shape)return Refuse(Error,TEXT("null_cooked_shape"));const auto& P=Shape->Particles();const auto& E=Shape->Elements();CV+=P.Size();CT+=E.GetNumTriangles();if(CV>MaxV||CT>MaxT)return Refuse(Error,TEXT("aggregate_cooked_bounds"));for(int32 I=0;I<int32(P.Size());++I)if(!FinitePoint(P.GetX(I)))return Refuse(Error,TEXT("cooked_nonfinite"));for(int32 I=0;I<E.GetNumTriangles();++I){int32 A,B,C;if(E.RequiresLargeIndices()){const auto& T=E.GetLargeIndexBuffer()[I];A=T[0];B=T[1];C=T[2];}else{const auto& T=E.GetSmallIndexBuffer()[I];A=T[0];B=T[1];C=T[2];}const int32 X=Shape->GetExternalFaceIndexFromInternal(I);if(!Triangle(A,B,C,P.Size())||X<INDEX_NONE||X>=int32(MaxT))return Refuse(Error,TEXT("cooked_index_or_remap_range"));}}
    // GetPhysicsTriMeshData may allocate. Bound both possible native input domains first.
    if(RD->CollisionDataForCookedCooker){const auto& C=*RD->CollisionDataForCookedCooker;if(!Count(C.Vertices.Num(),MaxV)||!Count(C.Indices.Num(),MaxT)||!Count(C.MaterialIndices.Num(),MaxT)||!Count(C.UVs.Num(),MaxUV))return Refuse(Error,TEXT("cached_provider_preallocation_bounds"));for(const auto& UV:C.UVs)if(!Count(UV.Num(),MaxV))return Refuse(Error,TEXT("cached_provider_UV_bounds"));}
    if(!M->GetPhysicsTriMeshData(&S.Provider,true))return Refuse(Error,TEXT("provider_unavailable_no_repair"));const auto& C=S.Provider;
    if(!Count(C.Vertices.Num(),MaxV)||!Count(C.Indices.Num(),MaxT)||!Count(C.MaterialIndices.Num(),MaxT)||!Count(C.UVs.Num(),MaxUV)||(C.MaterialIndices.Num()!=0&&C.MaterialIndices.Num()!=C.Indices.Num()))return Refuse(Error,TEXT("provider_actual_bounds"));
    for(const auto& P:C.Vertices)if(!FinitePoint(P))return Refuse(Error,TEXT("provider_nonfinite"));for(const auto& T:C.Indices)if(!Triangle(T.v0,T.v1,T.v2,C.Vertices.Num()))return Refuse(Error,TEXT("provider_invalid_indices"));for(const auto& UV:C.UVs){if(!Count(UV.Num(),MaxV))return Refuse(Error,TEXT("provider_UV_bounds"));for(const auto& P:UV)if(!FMath::IsFinite(P.X)||!FMath::IsFinite(P.Y))return Refuse(Error,TEXT("provider_nonfinite_UV"));}
    S.Meta->SetStringField(TEXT("asset"),M->GetPathName());S.Meta->SetStringField(TEXT("body"),S.Body->GetPathName());S.Meta->SetStringField(TEXT("body_GUID"),S.Guid.ToString(EGuidFormats::Digits));S.Meta->SetNumberField(TEXT("collision_mode"),int32(S.Body->CollisionTraceFlag));S.Meta->SetBoolField(TEXT("double_sided_geometry"),S.Body->bDoubleSidedGeometry);S.Meta->SetBoolField(TEXT("created_physics_meshes"),S.Body->bCreatedPhysicsMeshes);S.Meta->SetBoolField(TEXT("failed_physics_meshes"),S.Body->bFailedToCreatePhysicsMeshes);S.Meta->SetNumberField(TEXT("simple_elements"),double(NS));S.Meta->SetBoolField(TEXT("provider_flip_normals"),C.bFlipNormals);S.Meta->SetNumberField(TEXT("provider_UV_channels_observed_not_exported"),C.UVs.Num());S.Meta->SetStringField(TEXT("cooked_stored_material_array"),TEXT("UNOBSERVED_PRIVATE_STORAGE"));S.Meta->SetStringField(TEXT("cooked_effective_material_kind12"),TEXT("GetMaterialIndex(internalTriangleI), native uint16 result; accessor returns fallback0 when backing array lacks that index; NOT raw stored-array proof"));
    const FBodyInstance& Defaults=S.Body->DefaultInstance;S.Meta->SetStringField(TEXT("default_collision_profile"),Defaults.GetCollisionProfileName().ToString());S.Meta->SetNumberField(TEXT("default_object_type"),int32(Defaults.GetObjectType()));S.Meta->SetNumberField(TEXT("default_collision_enabled"),int32(Defaults.GetCollisionEnabled()));S.Meta->SetBoolField(TEXT("default_simulate_physics"),Defaults.bSimulatePhysics);S.Meta->SetNumberField(TEXT("default_Pawn_response"),int32(Defaults.GetResponseToChannel(ECC_Pawn)));S.Meta->SetNumberField(TEXT("default_Camera_response"),int32(Defaults.GetResponseToChannel(ECC_Camera)));S.Meta->SetBoolField(TEXT("asset_defaults_not_live_world_policy"),true);S.Meta->SetBoolField(TEXT("outer_owner_all_source_sidecars_custody_required"),true);
    return true;
}

void Entries(FSnapshot& S)
{
    auto Add=[&](uint32 Kind,uint32 Shape,uint32 Stride,uint32 N,uint32 PB,uint32 IB,uint32 Flags,TFunction<void(FWriter&)> Emit){FEntry E;E.Kind=Kind;E.Shape=Shape;E.Stride=Stride;E.N=N;E.PositionBytes=PB;E.IndexBytes=IB;E.Flags=Flags;E.Bytes=uint64(Stride)*N;E.Emit=MoveTemp(Emit);S.Entries.Add(MoveTemp(E));};
    const auto& D=*S.MD;const auto Pos=FStaticMeshConstAttributes(D).GetVertexPositions();
    Add(1,NoShape,16,D.Vertices().Num(),4,4,1,[&D,Pos](FWriter& W){for(FVertexID ID:D.Vertices().GetElementIDs()){W.U32(ID.GetValue());W.Point(Pos[ID]);}});
    Add(2,NoShape,20,D.Triangles().Num(),0,4,1,[&D](FWriter& W){for(FTriangleID ID:D.Triangles().GetElementIDs()){const auto V=D.GetTriangleVertices(ID);W.U32(ID.GetValue());for(FVertexID X:V)W.U32(X.GetValue());W.I32(D.GetTrianglePolygonGroup(ID).GetValue());}});
    const auto& L=*S.Render;Add(3,NoShape,12,L.VertexBuffers.PositionVertexBuffer.GetNumVertices(),4,0,0,[&L](FWriter& W){for(uint32 I=0;I<L.VertexBuffers.PositionVertexBuffer.GetNumVertices();++I)W.Point(L.VertexBuffers.PositionVertexBuffer.VertexPosition(I));});
    Add(4,NoShape,12,L.IndexBuffer.GetNumIndices()/3,0,L.IndexBuffer.GetIndexDataSize()/L.IndexBuffer.GetNumIndices(),0,[&L](FWriter& W){const auto V=L.IndexBuffer.GetArrayView();for(int32 I=0;I<V.Num();++I)W.U32(V[I]);});
    Add(5,NoShape,20,L.Sections.Num(),0,4,0,[&L](FWriter& W){for(const auto& X:L.Sections){W.U32(X.MaterialIndex);W.U32(X.FirstIndex);W.U32(X.NumTriangles);W.U32(X.MinVertexIndex);W.U32(X.MaxVertexIndex);}});
    const auto& C=S.Provider;Add(6,NoShape,12,C.Vertices.Num(),4,0,0,[&C](FWriter& W){for(const auto& X:C.Vertices)W.Point(X);});
    Add(7,NoShape,12,C.Indices.Num(),0,sizeof(FTriIndices::v0),1,[&C](FWriter& W){for(const auto& X:C.Indices){W.I32(X.v0);W.I32(X.v1);W.I32(X.v2);}});
    Add(8,NoShape,4,C.MaterialIndices.Num(),0,sizeof(decltype(C.MaterialIndices)::ElementType),0,[&C](FWriter& W){for(const auto X:C.MaterialIndices)W.U32(X);});
    for(int32 Shape=0;Shape<S.Body->TriMeshGeometries.Num();++Shape)
    {
        const auto* Object=S.Body->TriMeshGeometries[Shape].GetReference();const auto& P=Object->Particles();const auto& E=Object->Elements();using Scalar=std::remove_cv_t<std::remove_reference_t<decltype(P.GetX(0)[0])>>;static_assert(std::is_same_v<Scalar,float>||std::is_same_v<Scalar,double>);
        Add(9,Shape,3*sizeof(Scalar),P.Size(),sizeof(Scalar),0,0,[Object](FWriter& W){const auto& V=Object->Particles();for(int32 I=0;I<int32(V.Size());++I)W.Point(V.GetX(I));});
        using LargeIndex=std::remove_cv_t<std::remove_reference_t<decltype(E.GetLargeIndexBuffer()[0][0])>>;using SmallIndex=std::remove_cv_t<std::remove_reference_t<decltype(E.GetSmallIndexBuffer()[0][0])>>;static_assert(sizeof(LargeIndex)==4&&sizeof(SmallIndex)==2);
        const uint32 IndexBytes=E.RequiresLargeIndices()?sizeof(LargeIndex):sizeof(SmallIndex),IndexSigned=E.RequiresLargeIndices()?uint32(std::is_signed_v<LargeIndex>):uint32(std::is_signed_v<SmallIndex>);
        Add(10,Shape,12,E.GetNumTriangles(),0,IndexBytes,IndexSigned,[Object](FWriter& W){const auto& V=Object->Elements();for(int32 I=0;I<V.GetNumTriangles();++I){if(V.RequiresLargeIndices()){const auto& T=V.GetLargeIndexBuffer()[I];for(int32 C=0;C<3;++C)W.U32(T[C]);}else{const auto& T=V.GetSmallIndexBuffer()[I];for(int32 C=0;C<3;++C)W.U32(T[C]);}}});
        Add(11,Shape,4,E.GetNumTriangles(),0,4,1,[Object](FWriter& W){for(int32 I=0;I<Object->Elements().GetNumTriangles();++I)W.I32(Object->GetExternalFaceIndexFromInternal(I));});
        static_assert(std::is_same_v<decltype(Object->GetMaterialIndex(0u)),uint16>);
        Add(12,Shape,4,E.GetNumTriangles(),0,sizeof(decltype(Object->GetMaterialIndex(0u))),0,[Object](FWriter& W){for(int32 I=0;I<Object->Elements().GetNumTriangles();++I)W.U32(Object->GetMaterialIndex(uint32(I)));});
    }
    S.Expected=64+uint64(S.Entries.Num())*64;for(auto& E:S.Entries){E.Offset=S.Expected;S.Expected+=E.Bytes;}
}

FString CollisionSessionRoot;uint64 CollisionSessionReserved=0;bool CollisionSessionFailed=false;TSet<int32> CollisionSeen;

struct FRHIObserved
{
    std::atomic<bool> Done{false};bool Valid=false;int32 X=0,Y=0,Mips=0,Format=0;uint64 Flags=0;double Finished=0;
};
struct FTexturePending
{
    TStrongObjectPtr<UTexture2D> Texture;FTextureResource* Resource=nullptr;const FTextureExpected* Expected=nullptr;
    TSharedRef<FRHIObserved,ESPMode::ThreadSafe> RHI=MakeShared<FRHIObserved,ESPMode::ThreadSafe>();
    TSharedRef<FJsonObject> Snapshot=MakeShared<FJsonObject>();FString Token,SourceId;bool Dirty=false;double Started=0;
};
TUniquePtr<FTexturePending> Pending;bool TextureSessionFailed=false;TSet<FString> TextureCompleted;
TSharedRef<FJsonObject> TextureScalars(UTexture2D* T)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("asset"),T->GetPathName());O->SetBoolField(TEXT("package_dirty"),T->GetOutermost()->IsDirty());O->SetStringField(TEXT("source_GUID"),T->Source.GetId().ToString(EGuidFormats::Digits));O->SetNumberField(TEXT("source_width"),T->Source.GetSizeX());O->SetNumberField(TEXT("source_height"),T->Source.GetSizeY());O->SetNumberField(TEXT("source_mips"),T->Source.GetNumMips());O->SetNumberField(TEXT("source_format"),int32(T->Source.GetFormat()));O->SetNumberField(TEXT("source_blocks"),T->Source.GetNumBlocks());O->SetNumberField(TEXT("source_layers"),T->Source.GetNumLayers());
    const FTexturePlatformData* P=T->GetPlatformData();O->SetBoolField(TEXT("platform_present"),P!=nullptr);TArray<TSharedPtr<FJsonValue>> Mips;if(P){O->SetNumberField(TEXT("platform_width"),P->SizeX);O->SetNumberField(TEXT("platform_height"),P->SizeY);O->SetNumberField(TEXT("platform_format"),int32(P->PixelFormat));O->SetNumberField(TEXT("platform_mips"),P->Mips.Num());for(int32 I=0;I<P->Mips.Num()&&I<15;++I){const auto& M=P->Mips[I];auto R=MakeShared<FJsonObject>();R->SetNumberField(TEXT("index"),I);R->SetNumberField(TEXT("width"),M.SizeX);R->SetNumberField(TEXT("height"),M.SizeY);R->SetNumberField(TEXT("depth"),M.SizeZ);Mips.Add(MakeShared<FJsonValueObject>(R));}}O->SetArrayField(TEXT("platform_mip_rows"),Mips);
    O->SetNumberField(TEXT("resident_mips"),T->GetNumResidentMips());O->SetNumberField(TEXT("allowed_mips"),T->GetNumMipsAllowed(false));O->SetNumberField(TEXT("LOD_bias"),T->LODBias);O->SetNumberField(TEXT("asset_max_texture_size"),T->MaxTextureSize);O->SetNumberField(TEXT("texture_group"),int32(T->LODGroup));O->SetBoolField(TEXT("sRGB"),T->SRGB);O->SetNumberField(TEXT("compression_settings"),int32(T->CompressionSettings));O->SetBoolField(TEXT("virtual_streaming"),T->VirtualTextureStreaming);O->SetBoolField(TEXT("never_stream"),T->NeverStream);O->SetNumberField(TEXT("address_x"),int32(T->AddressX));O->SetNumberField(TEXT("address_y"),int32(T->AddressY));O->SetNumberField(TEXT("filter"),int32(T->Filter));O->SetNumberField(TEXT("mip_gen_settings"),int32(T->MipGenSettings));
    const UDeviceProfile* Profile=UDeviceProfileManager::Get().GetActiveProfile();O->SetStringField(TEXT("active_device_profile"),Profile?Profile->GetName():TEXT(""));if(Profile&&Profile->GetTextureLODSettings()&&int32(T->LODGroup)>=0&&int32(T->LODGroup)<TEXTUREGROUP_MAX){const auto& G=Profile->GetTextureLODSettings()->GetTextureLODGroup(T->LODGroup);O->SetNumberField(TEXT("group_max_LOD_size"),G.MaxLODSize);O->SetNumberField(TEXT("group_max_LOD_mips"),G.MaxLODMipCount);O->SetNumberField(TEXT("group_LOD_bias"),G.LODBias);O->SetNumberField(TEXT("resolved_combined_LOD_bias"),Profile->GetTextureLODSettings()->CalculateLODBias(T));}O->SetStringField(TEXT("native_RHI"),GDynamicRHI?FString(GDynamicRHI->GetName()):TEXT("NONE"));return O;
}
} // namespace GroundIntake

static bool ExportGroundCollisionMeshesImpl(const TArray<FString>& Paths,const FString& Relative,FString& ReceiptJson,FString& Error)
{
    using namespace GroundIntake;ReceiptJson.Empty();Error.Empty();
    if(!IsInGameThread()||!GIsEditor||Paths.IsEmpty()||Paths.Num()>8||!Leaf(Relative))return Refuse(Error,TEXT("editor_thread_batch8_fresh_leaf_required"));
    FString Owned=FPlatformMisc::GetEnvironmentVariable(TEXT("LIVING_TOWN_BOOTSTRAP_OUTPUT"));if(Owned.IsEmpty()||FPaths::IsRelative(Owned))return Refuse(Error,TEXT("owned_output_environment"));Owned=FPaths::ConvertRelativePathToFull(Owned);FPaths::NormalizeDirectoryName(Owned);const FString Out=FPaths::Combine(Owned,Relative);
    if(!NoReparse(Owned)||!FPaths::IsUnderDirectory(Out,Owned)||FPaths::IsUnderDirectory(Out,FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()))||FPaths::IsUnderDirectory(Out,FPaths::ConvertRelativePathToFull(FPaths::EngineDir()))||IFileManager::Get().FileExists(*Out)||IFileManager::Get().DirectoryExists(*Out))return Refuse(Error,TEXT("fresh_owned_output_boundary"));
    if(CollisionSessionFailed||(!CollisionSessionRoot.IsEmpty()&&CollisionSessionRoot!=Owned))return Refuse(Error,TEXT("single_owned_session_no_failure_retry"));
    TArray<TUniquePtr<FSnapshot>> Snapshots;TSet<int32> Batch;uint64 CallBytes=0;
    for(const FString& Path:Paths)
    {
        const int32 ID=RosterIndex(Path);if(ID==INDEX_NONE||Batch.Contains(ID)||CollisionSeen.Contains(ID))return Refuse(Error,TEXT("exact154_roster_unique_not_previous_export"));Batch.Add(ID);
        UStaticMesh* M=FindObject<UStaticMesh>(nullptr,*Path);if(!IsValid(M)||M->GetClass()!=UStaticMesh::StaticClass()||M->IsTemplate()||M->HasAnyFlags(RF_NeedLoad|RF_NeedPostLoad|RF_NeedPostLoadSubobjects))return Refuse(Error,TEXT("already_loaded_exact_StaticMesh_no_load"));
        auto S=MakeUnique<FSnapshot>();S->Mesh.Reset(M);S->Roster=ID;S->Dirty=M->GetOutermost()->IsDirty();if(S->Dirty)return Refuse(Error,TEXT("saved_clean_asset_required"));S->PackageFile=FPaths::ConvertRelativePathToFull(FPackageName::LongPackageNameToFilename(M->GetOutermost()->GetName(),FPackageName::GetAssetPackageExtension()));if(!FPaths::IsUnderDirectory(S->PackageFile,FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()))||!Digest(S->PackageFile,256ull<<20,S->PackageHash,S->PackageBytes))return Refuse(Error,TEXT("saved_owned_asset_file_boundary_or_hash"));
        if(!Preflight(*S,Error))return false;Entries(*S);if(S->Expected>FileCap)return Refuse(Error,TEXT("binary_file32MiB"));CallBytes+=S->Expected;if(CallBytes>CallCap)return Refuse(Error,TEXT("binary_call256MiB"));Snapshots.Add(MoveTemp(S));
    }
    if(CollisionSessionReserved+CallBytes>SessionCap)return Refuse(Error,TEXT("binary_session512MiB"));CollisionSessionRoot=Owned;CollisionSessionReserved+=CallBytes;for(int32 ID:Batch)CollisionSeen.Add(ID);CollisionSessionFailed=true; // remains closed on any partial/error
    if(!IFileManager::Get().MakeDirectory(*Out,false)||!NoReparse(Out))return Refuse(Error,TEXT("fresh_output_create"));TArray<TSharedPtr<FJsonValue>> Results;
    for(auto& Ptr:Snapshots)
    {
        auto& S=*Ptr;const FString Name=FString::Printf(TEXT("Ground_%03d.bin"),S.Roster),File=FPaths::Combine(Out,Name);FWriter W(File);for(int32 I=0;I<16;++I)W.U8(uint8(Magic[I]));for(uint32 X:{1u,64u,uint32(S.Roster),uint32(S.Entries.Num()),0x01020304u,0u})W.U32(X);W.U64(S.Expected);W.U64(64);W.U64(uint64(S.Entries.Num())*64);
        for(const auto& E:S.Entries){for(uint32 X:{E.Kind,E.Shape,E.Stride,E.N})W.U32(X);W.U64(E.Offset);W.U64(E.Bytes);for(uint32 X:{E.PositionBytes,E.IndexBytes,E.Flags,0u})W.U32(X);W.U64(0);W.U64(0);}
        for(const auto& E:S.Entries){if(W.Tell()!=E.Offset)return Refuse(Error,TEXT("binary_offset_custody"));E.Emit(W);if(W.Tell()!=E.Offset+E.Bytes)return Refuse(Error,TEXT("binary_section_actual_size"));}if(!W.Finish()||W.Tell()!=S.Expected)return Refuse(Error,TEXT("binary_close_or_length"));
        FString Hash,NowHash;int64 Bytes=0,NowBytes=0;if(!Digest(File,FileCap,Hash,Bytes)||!Digest(S.PackageFile,256ull<<20,NowHash,NowBytes)||NowHash!=S.PackageHash||NowBytes!=S.PackageBytes||S.Mesh->IsCompiling()||S.Mesh->GetBodySetup()!=S.Body||S.Body->BodySetupGuid!=S.Guid||S.Mesh->GetOutermost()->IsDirty()!=S.Dirty)return Refuse(Error,TEXT("saved_asset_body_or_byte_custody_changed"));
        S.Meta->SetStringField(TEXT("binary"),Name);S.Meta->SetStringField(TEXT("binary_sha256"),Hash);S.Meta->SetNumberField(TEXT("binary_bytes"),double(Bytes));S.Meta->SetStringField(TEXT("source_package"),S.PackageFile);S.Meta->SetStringField(TEXT("source_package_sha256"),S.PackageHash);S.Meta->SetNumberField(TEXT("source_package_bytes"),double(S.PackageBytes));S.Meta->SetNumberField(TEXT("roster_index"),S.Roster);S.Meta->SetBoolField(TEXT("package_dirty_before"),S.Dirty);S.Meta->SetBoolField(TEXT("package_dirty_after"),S.Mesh->GetOutermost()->IsDirty());S.Meta->SetBoolField(TEXT("source_or_cooked_equality_qualified"),false);Results.Add(MakeShared<FJsonValueObject>(S.Meta));
    }
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("schema"),TEXT("LivingTown.GroundCollisionBinary.v1"));O->SetStringField(TEXT("status"),TEXT("READ_ONLY_NATIVE_GROUND_COLLISION_RAW_ARRAYS_EXPORTED"));O->SetArrayField(TEXT("exports"),Results);O->SetNumberField(TEXT("call_binary_bytes"),double(CallBytes));O->SetNumberField(TEXT("session_reserved_binary_bytes"),double(CollisionSessionReserved));O->SetBoolField(TEXT("asset_repaired_cooked_or_saved"),false);O->SetBoolField(TEXT("source_equality_art_world_GPU_DF_or_performance_qualified"),false);if(!NewJson(FPaths::Combine(Out,TEXT("MANIFEST.json")),O))return Refuse(Error,TEXT("manifest_new_write"));CollisionSessionFailed=false;ReceiptJson=Json(O);return true;
}

FString ULivingTownGroundIntakeInspection::ExportGroundCollisionMeshes(const TArray<FString>& Paths,const FString& Relative)
{
    FString Receipt,Error;
    if(ExportGroundCollisionMeshesImpl(Paths,Relative,Receipt,Error))return Receipt;
    return GroundIntake::Reply(Error.StartsWith(TEXT("HOLD_"))?TEXT("HOLD_RESOURCE_PENDING"):TEXT("REFUSED"),Error);
}

FString ULivingTownGroundIntakeInspection::BeginGroundTextureRead(UTexture2D* T)
{
    using namespace GroundIntake;if(!IsInGameThread()||!GIsEditor)return Reply(TEXT("REFUSED"),TEXT("Editor_GameThread_required"));if(TextureSessionFailed||Pending)return Reply(TEXT("REFUSED"),TEXT("one_pending_read_or_session_failed"));
    if(!IsValid(T)||T->GetClass()!=UTexture2D::StaticClass()||T->IsTemplate()||T->HasAnyFlags(RF_NeedLoad|RF_NeedPostLoad|RF_NeedPostLoadSubobjects))return Reply(TEXT("REFUSED"),TEXT("already_loaded_exact_Texture2D"));const auto* Expected=TextureExpected(T->GetPathName());if(!Expected||TextureCompleted.Contains(T->GetPathName()))return Reply(TEXT("REFUSED"),TEXT("exact12_roster_once_each"));
    if(T->IsCompiling()||!T->Source.IsValid()||!T->GetResource()||T->GetResource()->IsProxy())return Reply(TEXT("HOLD_RESOURCE_PENDING"),TEXT("compilation_source_or_resource_unavailable_no_wait"));const auto* P=T->GetPlatformData();if(!P||P->Mips.Num()<1||P->Mips.Num()>15)return Reply(TEXT("HOLD_RESOURCE_PENDING"),TEXT("platform_mips_not_ready"));
    if(T->GetOutermost()->IsDirty()||T->Source.GetNumBlocks()!=1||T->Source.GetNumLayers()!=1)return Reply(TEXT("REFUSED"),TEXT("saved_clean_single_layer_source_required"));
    if(T->Source.GetSizeX()!=Expected->Width||T->Source.GetSizeY()!=Expected->Height||P->SizeX!=Expected->Width||P->SizeY!=Expected->Height||P->PixelFormat!=Expected->Format||P->Mips.Num()!=Expected->Mips||T->GetNumResidentMips()!=Expected->Mips||T->GetNumMipsAllowed(false)!=Expected->Mips||T->VirtualTextureStreaming)return Reply(TEXT("HOLD_RESOURCE_PENDING"),TEXT("source_platform_allowed_resident_full_size_required_before_RHI_request"));
    Pending=MakeUnique<FTexturePending>();Pending->Texture.Reset(T);Pending->Expected=Expected;Pending->Resource=T->GetResource();Pending->SourceId=T->Source.GetId().ToString(EGuidFormats::Digits);Pending->Dirty=T->GetOutermost()->IsDirty();Pending->Snapshot=TextureScalars(T);Pending->Token=FGuid::NewGuid().ToString(EGuidFormats::Digits);Pending->Started=FPlatformTime::Seconds();const auto Shared=Pending->RHI;FTextureResource* Resource=Pending->Resource;
    // GT enqueues before any subsequent GT resource release; strong UObject prevents GC.
    // RT copies scalar fields while that ordered resource/RHI is held by the engine.
    ENQUEUE_RENDER_COMMAND(LivingTownGroundTextureScalars)([Shared,Resource](FRHICommandListImmediate&){FTextureRHIRef Hold=Resource?Resource->TextureRHI:FTextureRHIRef();FRHITexture* R=Hold.IsValid()?Hold->GetTexture2D():nullptr;if(R){const FRHITextureDesc D=R->GetDesc();Shared->Valid=true;Shared->X=D.Extent.X;Shared->Y=D.Extent.Y;Shared->Mips=D.NumMips;Shared->Format=int32(D.Format);Shared->Flags=uint64(D.Flags);}Shared->Finished=FPlatformTime::Seconds();Shared->Done.store(true,std::memory_order_release);});
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("PENDING_RENDER_THREAD_SCALARS"));O->SetStringField(TEXT("token"),Pending->Token);O->SetObjectField(TEXT("before"),Pending->Snapshot);O->SetNumberField(TEXT("deadline_seconds"),5.0);O->SetBoolField(TEXT("flush_or_force_stream_called"),false);return Json(O);
}

FString ULivingTownGroundIntakeInspection::PollGroundTextureRead(const FString& Token)
{
    using namespace GroundIntake;if(!IsInGameThread()||!GIsEditor||!Pending||Token!=Pending->Token)return Reply(TEXT("REFUSED"),TEXT("exact_pending_token_Editor_GameThread"));const double Now=FPlatformTime::Seconds();if(!Pending->RHI->Done.load(std::memory_order_acquire)){if(Now-Pending->Started<=5)return Reply(TEXT("PENDING_RENDER_THREAD_SCALARS"),TEXT("not_ready_no_wait"));TextureSessionFailed=true;Pending.Reset();return Reply(TEXT("HOLD_RESOURCE_PENDING"),TEXT("render_thread_scalar_deadline_no_retry"));}
    auto Job=MoveTemp(Pending);UTexture2D* T=Job->Texture.Get();auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("schema"),TEXT("LivingTown.GroundTextureNativeScalars.v1"));O->SetStringField(TEXT("token"),Job->Token);O->SetObjectField(TEXT("before"),Job->Snapshot);O->SetBoolField(TEXT("GPU_texels_or_sampling_LOD_qualified"),false);O->SetBoolField(TEXT("asset_repaired_or_saved_or_stream_forced"),false);auto R=MakeShared<FJsonObject>();R->SetBoolField(TEXT("valid"),Job->RHI->Valid);R->SetNumberField(TEXT("extent_x"),Job->RHI->X);R->SetNumberField(TEXT("extent_y"),Job->RHI->Y);R->SetNumberField(TEXT("mips"),Job->RHI->Mips);R->SetNumberField(TEXT("format"),Job->RHI->Format);R->SetStringField(TEXT("flags_u64_decimal"),LexToString(Job->RHI->Flags));R->SetNumberField(TEXT("request_to_RT_seconds"),Job->RHI->Finished-Job->Started);O->SetObjectField(TEXT("render_thread_RHI"),R);
    if(!IsValid(T)||T->IsCompiling()||T->GetResource()!=Job->Resource||T->Source.GetId().ToString(EGuidFormats::Digits)!=Job->SourceId||T->GetOutermost()->IsDirty()!=Job->Dirty){TextureSessionFailed=true;O->SetStringField(TEXT("status"),TEXT("HOLD_RESOURCE_CHANGED"));return Json(O);}auto After=TextureScalars(T);O->SetObjectField(TEXT("after"),After);const auto* P=T->GetPlatformData();const auto& E=*Job->Expected;bool Full=P&&T->Source.GetSizeX()==E.Width&&T->Source.GetSizeY()==E.Height&&P->SizeX==E.Width&&P->SizeY==E.Height&&P->PixelFormat==E.Format&&P->Mips.Num()==E.Mips&&T->GetNumMipsAllowed(false)==E.Mips&&T->GetNumResidentMips()==E.Mips&&Job->RHI->Valid&&Job->RHI->X==E.Width&&Job->RHI->Y==E.Height&&Job->RHI->Format==E.Format&&Job->RHI->Mips==E.Mips&&Job->RHI->Finished-Job->Started<=5.0;
    if(P)for(int32 I=0;I<P->Mips.Num();++I)Full&=P->Mips[I].SizeX==FMath::Max(1,E.Width>>I)&&P->Mips[I].SizeY==FMath::Max(1,E.Height>>I);
    Full&=Json(Job->Snapshot)==Json(After);
    O->SetStringField(TEXT("status"),Full?TEXT("READ_ONLY_FULL_SOURCE_PLATFORM_RESIDENT_RHI_SCALARS_OBSERVED"):TEXT("HOLD_FULL_RESOURCE_EXPECTATION_NOT_MET"));if(Full)TextureCompleted.Add(T->GetPathName());else TextureSessionFailed=true;return Json(O);
}
