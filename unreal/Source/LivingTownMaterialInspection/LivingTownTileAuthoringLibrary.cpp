#include "LivingTownTileAuthoringLibrary.h"
#include "LivingTownTileData.h"
#include "LivingTownTilePlan.h"
#include "LivingTownCafeGeometryLibrary.h"
#include "LivingTownTileDriver.h"
#include "EngineUtils.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "Engine/Level.h"
#include "GameFramework/Actor.h"
#include "GameFramework/Pawn.h"
#include "Components/StaticMeshComponent.h"
#include "Components/InstancedStaticMeshComponent.h"
#include "StaticMeshCompiler.h"
#include "Materials/MaterialInterface.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformMisc.h"
#include "UObject/Package.h"
#include "UObject/StrongObjectPtr.h"
#include "UObject/UObjectGlobals.h"
#include <limits>
#if PLATFORM_WINDOWS
#include "Windows/WindowsHWrapper.h"
#endif

namespace
{
constexpr const TCHAR* PlanSha=TEXT("b24cb6a1c0612967b9b3a8f33ce707aa5b75ac878da9415bf9e0f3cbb3a64af0");
constexpr const TCHAR* StagePrefix=TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/TypedStage_v001/");
constexpr const TCHAR* DefinitionPrefix=TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/Definitions/");
constexpr const TCHAR* RootPath=TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/TypedStage_v001/DA_TownRoot_Stage_v001.DA_TownRoot_Stage_v001");

FString Pack(const FString& Status,const FString& Error,TSharedPtr<FJsonObject> Readback=nullptr)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("schema"),TEXT("living_town.typed_town_authoring_result.v1"));
    O->SetStringField(TEXT("status"),Status);O->SetStringField(TEXT("error"),Error);
    if(Readback)O->SetObjectField(TEXT("readback"),Readback);else O->SetField(TEXT("readback"),MakeShared<FJsonValueNull>());
    FString Text;auto W=TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Text);
    if(!FJsonSerializer::Serialize(O,W)||Text.Len()>16*1024*1024)return TEXT("{\"schema\":\"living_town.typed_town_authoring_result.v1\",\"status\":\"REFUSED\",\"error\":\"result_json_bound\",\"readback\":null}");return Text;
}
bool Utf8Hash(const FString& Text,FString& Out)
{FTCHARToUTF8 U(*Text);TArray<uint8> B;B.Append(reinterpret_cast<const uint8*>(U.Get()),U.Length());return LivingTownTiles::HashBytes(B,Out);}
FString DoubleHash(const TArray<double>& Values)
{
    TArray<uint8> B;B.Reserve(Values.Num()*8);
    for(double V:Values){uint64 Bits=0;FMemory::Memcpy(&Bits,&V,8);for(int32 I=0;I<8;++I)B.Add(uint8(Bits>>(8*I)));}
    FString Hash;LivingTownTiles::HashBytes(B,Hash);return Hash;
}
bool JsonObject(const FString& Text,TSharedPtr<FJsonObject>& Out)
{if(Text.IsEmpty()||Text.Len()>8*1024*1024)return false;auto R=TJsonReaderFactory<>::Create(Text);return FJsonSerializer::Deserialize(R,Out)&&Out.IsValid();}
bool FrozenPlan(const FString& Text,TSharedPtr<FJsonObject>& Out)
{FString Hash;return Utf8Hash(Text,Hash)&&Hash==PlanSha&&JsonObject(Text,Out)&&Out->GetStringField(TEXT("schema"))==TEXT("living_town.typed_town_staging_plan.v1");}
TSharedPtr<FJsonObject> Object(const TSharedPtr<FJsonValue>& V)
{return V.IsValid()&&V->Type==EJson::Object?V->AsObject():nullptr;}
bool Text(const TSharedPtr<FJsonObject>& O,const TCHAR* Name,FString& Out)
{return O&&O->TryGetStringField(Name,Out);}
bool NoReparse(const FString& Absolute)
{
#if PLATFORM_WINDOWS
    const FString N=Absolute.Replace(TEXT("/"),TEXT("\\"));if(N.Len()<3||N[1]!=':'||N[2]!='\\')return false;
    auto Check=[](const FString& P){const DWORD A=GetFileAttributesW(*P);return A!=INVALID_FILE_ATTRIBUTES&&!(A&FILE_ATTRIBUTE_REPARSE_POINT);};
    FString P=N.Left(3);if(!Check(P))return false;TArray<FString> Parts;N.Mid(3).ParseIntoArray(Parts,TEXT("\\"),true);
    for(const FString& C:Parts){if(C==TEXT(".")||C==TEXT(".."))return false;P=FPaths::Combine(P,C);if(!Check(P))return false;}return true;
#else
    return false;
#endif
}
bool OwnedProject()
{
    if(!GIsEditor||!IsInGameThread())return false;
    FString Owned=FPlatformMisc::GetEnvironmentVariable(TEXT("LIVING_TOWN_BOOTSTRAP_OUTPUT"));
    if(Owned.IsEmpty()||FPaths::IsRelative(Owned))return false;Owned=FPaths::ConvertRelativePathToFull(Owned);FPaths::NormalizeDirectoryName(Owned);
    FString Project=FPaths::ConvertRelativePathToFull(FPaths::ProjectDir());FPaths::NormalizeDirectoryName(Project);
    return Owned.Len()>3&&Owned.Left(2).Equals(TEXT("F:"),ESearchCase::IgnoreCase)&&FPaths::IsUnderDirectory(Project,Owned)&&NoReparse(Owned)&&NoReparse(Project);
}
bool StagingObject(const UObject* O,const FString& Expected,bool bUnsaved)
{
    if(!IsValid(O)||O->GetPathName()!=Expected||!Expected.StartsWith(StagePrefix,ESearchCase::CaseSensitive)||
       !O->GetOutermost()||O->GetOutermost()->HasAnyPackageFlags(PKG_PlayInEditor))return false;
    const FString File=FPaths::ConvertRelativePathToFull(FPackageName::LongPackageNameToFilename(O->GetOutermost()->GetName(),FPackageName::GetAssetPackageExtension()));
    return FPaths::IsUnderDirectory(File,FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()))&&(!bUnsaved||!IFileManager::Get().FileExists(*File));
}
bool AllFalse(const FLivingTownTileQualification& Q)
{return !Q.bAssetsQualified&&!Q.bCoordinatesQualified&&!Q.bMaterialsQualified&&!Q.bCollisionQualified;}
bool Strings(const TArray<TSharedPtr<FJsonValue>>& Values,TArray<FString>& Out)
{for(const auto& V:Values){if(!V||V->Type!=EJson::String)return false;Out.Add(V->AsString());}return true;}
bool SameStrings(const TArray<TSharedPtr<FJsonValue>>& Expected,const TArray<FString>& Actual)
{TArray<FString> Values;return Strings(Expected,Values)&&Values==Actual;}
bool MatrixPlacement(const TSharedPtr<FJsonObject>& Input,FLivingTownTilePlacement& Out,FString& Error)
{
    Out.SourcePlacementId=Input->GetStringField(TEXT("source_placement_id"));
    for(const auto& V:Input->GetArrayField(TEXT("source_matrix_row_major")))Out.SourceWorldMatrixRowMajor.Add(V->AsNumber());
    const auto& A=Out.SourceWorldMatrixRowMajor;
    if(A.Num()!=16){Error=TEXT("placement_matrix_count");return false;}
    for(double V:A)if(!FMath::IsFinite(V)){Error=TEXT("placement_nonfinite");return false;}
    if(A[12]!=0||A[13]!=0||A[14]!=0||A[15]!=1){Error=TEXT("placement_nonaffine");return false;}
    if(DoubleHash(A)!=Input->GetStringField(TEXT("source_matrix_sha256"))){Error=TEXT("placement_raw_f64_identity");return false;}
    const FVector C[3]={FVector(A[0],A[4],A[8]),FVector(A[1],A[5],A[9]),FVector(A[2],A[6],A[10])};
    const double N[3]={C[0].Size(),C[1].Size(),C[2].Size()};constexpr double E=64*std::numeric_limits<double>::epsilon();
    for(double V:N)if(!FMath::IsFinite(V)||V<=0){Error=TEXT("placement_singular");return false;}
    for(int32 I=0;I<3;++I)for(int32 J=I+1;J<3;++J)if(FMath::Abs(FVector::DotProduct(C[I]/N[I],C[J]/N[J]))>E){Error=TEXT("placement_shear");return false;}
    if(FVector::DotProduct(C[0],FVector::CrossProduct(C[1],C[2]))<=0){Error=TEXT("placement_reflection");return false;}
    FMatrix Native=FMatrix::Identity;const int32 S[3]={0,2,1};for(int32 I=0;I<3;++I)for(int32 J=0;J<3;++J)Native.M[I][J]=A[S[J]*4+S[I]];
    Native.M[3][0]=100*A[3];Native.M[3][1]=100*A[11];Native.M[3][2]=100*A[7];Out.QualifiedNativeTransform=FTransform(Native);
    return LivingTownTiles::ValidatePlacement(Out,Error);
}
TArray<TSharedPtr<FJsonValue>> Vector(const FVector& V)
{return {MakeShared<FJsonValueNumber>(V.X),MakeShared<FJsonValueNumber>(V.Y),MakeShared<FJsonValueNumber>(V.Z)};}
TSharedRef<FJsonObject> GeometryReadback(const FLivingTownTileGeometry& G)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("entry_id"),G.EntryId);O->SetStringField(TEXT("mesh_key"),G.SourceMeshKey);O->SetStringField(TEXT("asset_path"),G.Mesh.ToSoftObjectPath().ToString());
    O->SetStringField(TEXT("owner_id"),G.OwnerId);O->SetStringField(TEXT("floor_id"),G.FloorId);O->SetStringField(TEXT("room_id"),G.RoomId);O->SetNumberField(TEXT("kind"),int32(G.Kind));
    O->SetStringField(TEXT("native_render_sha256"),G.NativeRenderSha256);O->SetStringField(TEXT("native_collision_guid"),G.NativeCollisionGuid);O->SetStringField(TEXT("native_mesh_receipt_sha256"),G.NativeMeshReceiptSha256);
    O->SetBoolField(TEXT("blocking_collision"),G.bBlockingCollision);O->SetArrayField(TEXT("actual_min_cm"),Vector(G.ActualNativeBoundsCm.Min));O->SetArrayField(TEXT("actual_max_cm"),Vector(G.ActualNativeBoundsCm.Max));
    TArray<TSharedPtr<FJsonValue>> Ids;for(const auto& Id:G.SourcePlacementIds)Ids.Add(MakeShared<FJsonValueString>(Id));O->SetArrayField(TEXT("source_placement_ids"),Ids);
    TArray<TSharedPtr<FJsonValue>> Poses;
    for(const auto& P:G.Placements)
    {
        auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("source_placement_id"),P.SourcePlacementId);R->SetStringField(TEXT("raw_f64_sha256"),DoubleHash(P.SourceWorldMatrixRowMajor));
        R->SetArrayField(TEXT("translation_cm"),Vector(P.QualifiedNativeTransform.GetTranslation()));R->SetArrayField(TEXT("scale"),Vector(P.QualifiedNativeTransform.GetScale3D()));
        const FQuat Q=P.QualifiedNativeTransform.GetRotation();R->SetArrayField(TEXT("rotation_xyzw"),{MakeShared<FJsonValueNumber>(Q.X),MakeShared<FJsonValueNumber>(Q.Y),MakeShared<FJsonValueNumber>(Q.Z),MakeShared<FJsonValueNumber>(Q.W)});
        const FMatrix M=P.QualifiedNativeTransform.ToMatrixWithScale();TArray<double> Values;for(int32 I=0;I<4;++I)for(int32 J=0;J<4;++J)Values.Add(M.M[I][J]);R->SetStringField(TEXT("native_transform_matrix_f64_sha256"),DoubleHash(Values));
        Poses.Add(MakeShared<FJsonValueObject>(R));
    }
    O->SetArrayField(TEXT("placements"),Poses);TArray<TSharedPtr<FJsonValue>> Slots;
    for(int32 I=0;I<G.QualifiedMaterialPaths.Num();++I){auto S=MakeShared<FJsonObject>();S->SetStringField(TEXT("path"),G.QualifiedMaterialPaths[I].ToString());S->SetStringField(TEXT("name"),G.QualifiedMaterialSlotNames[I]);S->SetNumberField(TEXT("blend_mode"),G.QualifiedMaterialBlendModes[I]);Slots.Add(MakeShared<FJsonValueObject>(S));}O->SetArrayField(TEXT("material_slots"),Slots);return O;
}
}

FString ULivingTownTileAuthoringLibrary::PopulateStagedTownAssets(ULivingTownTileRootData* Root,const TArray<ULivingTownRenderUnitData*>& Units,const FString& SourcePlanJson,const FString& NativeReceiptJson)
{
    TSharedPtr<FJsonObject> Plan,Receipts;if(!OwnedProject()||!FrozenPlan(SourcePlanJson,Plan)||!JsonObject(NativeReceiptJson,Receipts))return Pack(TEXT("REFUSED"),TEXT("owned_project_frozen_plan_or_receipt_json"));
    FString Schema,ManifestHash;if(!Text(Receipts,TEXT("schema"),Schema)||Schema!=TEXT("living_town.typed_town_native_asset_input.v1")||!Text(Receipts,TEXT("native_manifest_sha256"),ManifestHash)||!LivingTownTiles::IsSha256(ManifestHash))return Pack(TEXT("REFUSED"),TEXT("actual_native_receipt_identity"));
    const TArray<TSharedPtr<FJsonValue>>* ReceiptRows=nullptr;if(!Receipts->TryGetArrayField(TEXT("mesh_receipts"),ReceiptRows)||!ReceiptRows||ReceiptRows->Num()!=1488)return Pack(TEXT("REFUSED"),TEXT("actual_native_receipt_census"));
    if(!StagingObject(Root,RootPath,true)||!Root->Units.IsEmpty()||!Root->SourceFixtureInventory.IsEmpty()||!AllFalse(Root->Qualification))return Pack(TEXT("REFUSED"),TEXT("fresh_unsaved_empty_root_required"));
    const auto& SourceUnits=Plan->GetArrayField(TEXT("units"));if(SourceUnits.Num()!=116||Units.Num()!=116)return Pack(TEXT("REFUSED"),TEXT("exact_staging_unit_count"));
    TMap<FString,ULivingTownRenderUnitData*> Targets;for(auto* U:Units)
    {if(!U||!U->Geometry.IsEmpty()||!U->DeferredFixtures.IsEmpty()||!U->UnitId.IsEmpty()||!AllFalse(U->Qualification)||Targets.Contains(U->GetPathName()))return Pack(TEXT("REFUSED"),TEXT("fresh_unsaved_empty_units_required"));Targets.Add(U->GetPathName(),U);}
    for(const auto& V:SourceUnits){auto U=Object(V);if(!U||!Targets.Contains(U->GetStringField(TEXT("asset_path")))||!StagingObject(Targets[U->GetStringField(TEXT("asset_path"))],U->GetStringField(TEXT("asset_path")),true))return Pack(TEXT("REFUSED"),TEXT("exact_unit_paths_required"));}
    TMap<FString,TSharedPtr<FJsonObject>> ReceiptMap;TMap<FString,TStrongObjectPtr<UStaticMesh>> Meshes;TArray<UStaticMesh*> Compiling;
    for(const auto& V:*ReceiptRows)
    {
        auto R=Object(V);FString Path,Render,Meta,Collision;
        if(!Text(R,TEXT("asset_path"),Path)||!Path.StartsWith(DefinitionPrefix,ESearchCase::CaseSensitive)||!LivingTownTiles::IsPilotAssetPath(FSoftObjectPath(Path))||ReceiptMap.Contains(Path)||!Text(R,TEXT("native_render_sha256"),Render)||!LivingTownTiles::IsSha256(Render)||!Text(R,TEXT("metadata_sha256"),Meta)||!LivingTownTiles::IsSha256(Meta)||!Text(R,TEXT("collision_guid"),Collision))return Pack(TEXT("REFUSED"),TEXT("native_receipt_path_hash_or_alias"));
        auto* Mesh=LoadObject<UStaticMesh>(nullptr,*Path);if(!IsValid(Mesh)||Mesh->GetPathName()!=Path||!Mesh->bAllowCPUAccess)return Pack(TEXT("REFUSED"),TEXT("actual_mesh_identity_or_cpu_access"));
        const FString File=FPaths::ConvertRelativePathToFull(FPackageName::LongPackageNameToFilename(Mesh->GetOutermost()->GetName(),FPackageName::GetAssetPackageExtension()));
        if(!FPaths::IsUnderDirectory(File,FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()))||!IFileManager::Get().FileExists(*File)||!NoReparse(File))return Pack(TEXT("REFUSED"),TEXT("saved_mesh_in_owned_project_required"));
        ReceiptMap.Add(Path,R);Meshes.Emplace(Path,TStrongObjectPtr<UStaticMesh>(Mesh));Compiling.Add(Mesh);
    }
    FStaticMeshCompilingManager::Get().FinishCompilation(Compiling); // one batch, no per-mesh waits
    for(auto* M:Compiling)if(M->IsCompiling())return Pack(TEXT("REFUSED"),TEXT("mesh_compilation_pending"));
    TMap<FString,FLivingTownTileGeometry> NativeTemplates;
    for(const auto& Pair:ReceiptMap)
    {
        auto* Mesh=Meshes[Pair.Key].Get();const auto R=Pair.Value;FString Render,Collision,Error;
        if(!ULivingTownCafeGeometryLibrary::InspectCafeMesh(Mesh,Render,Collision,Error)||Render!=R->GetStringField(TEXT("native_render_sha256"))||Collision!=R->GetStringField(TEXT("collision_guid")))return Pack(TEXT("REFUSED"),TEXT("actual_mesh_full_identity_mismatch: ")+Error);
        FLivingTownTileGeometry T;T.Mesh=TSoftObjectPtr<UStaticMesh>(FSoftObjectPath(Pair.Key));T.NativeRenderSha256=Render;T.NativeCollisionGuid=Collision;T.NativeMeshReceiptSha256=R->GetStringField(TEXT("metadata_sha256"));
        const TArray<TSharedPtr<FJsonValue>>* ExpectedSlots=nullptr;const auto& Slots=Mesh->GetStaticMaterials();
        if(!R->TryGetArrayField(TEXT("materials"),ExpectedSlots)||!ExpectedSlots||ExpectedSlots->Num()!=Slots.Num()||Slots.IsEmpty()||Slots.Num()>128)return Pack(TEXT("REFUSED"),TEXT("actual_material_slot_census"));
        for(int32 I=0;I<Slots.Num();++I)
        {
            auto S=Object((*ExpectedSlots)[I]);const auto* M=Slots[I].MaterialInterface.Get();FString Path,Name;double Blend=-1,Index=-1;
            if(!M||!Text(S,TEXT("asset_path"),Path)||Path!=M->GetPathName()||!Path.StartsWith(TEXT("/Game/LivingTown_UEPilot/"),ESearchCase::CaseSensitive)||!Text(S,TEXT("slot_name"),Name)||Name.IsEmpty()||Name!=Slots[I].MaterialSlotName.ToString()||!S->TryGetNumberField(TEXT("blend_mode"),Blend)||Blend!=int32(M->GetBlendMode())||!S->TryGetNumberField(TEXT("slot_index"),Index)||Index!=I)return Pack(TEXT("REFUSED"),TEXT("actual_material_slot_path_name_or_mode"));
            T.QualifiedMaterialPaths.Add(FSoftObjectPath(M));T.QualifiedMaterialSlotNames.Add(Name);T.QualifiedMaterialBlendModes.Add(uint8(M->GetBlendMode()));
        }
        const auto B=Mesh->GetBounds();T.ActualNativeBoundsCm=FBox(FVector(B.Origin-B.BoxExtent),FVector(B.Origin+B.BoxExtent));
        if(!T.ActualNativeBoundsCm.IsValid||T.ActualNativeBoundsCm.Min.ContainsNaN()||T.ActualNativeBoundsCm.Max.ContainsNaN())return Pack(TEXT("REFUSED"),TEXT("actual_native_mesh_bounds"));
        NativeTemplates.Add(Pair.Key,MoveTemp(T));
    }
    TStrongObjectPtr<ULivingTownTileRootData> DraftRoot(NewObject<ULivingTownTileRootData>(GetTransientPackage()));auto& DR=*DraftRoot.Get();
    DR.Qualification.SourceAssemblySha256=Plan->GetStringField(TEXT("source_assembly_sha256"));DR.Qualification.SourceSliceSha256=Plan->GetStringField(TEXT("source_slice_sha256"));
    DR.Qualification.QualifiedDerivativeSha256=Plan->GetStringField(TEXT("source_profile_sha256"));DR.Qualification.NativeReadbackReceiptSha256=ManifestHash; // identities only; all proof flags stay false
    DR.ExistingCafeBindingSha256=Plan->GetStringField(TEXT("existing_cafe_binding_sha256"));TMap<FString,FLivingTownDeferredFixture> Fixtures;
    for(const auto& V:Plan->GetArrayField(TEXT("fixture_inventory")))
    {
        const auto F=V->AsObject();FLivingTownDeferredFixture D;D.SourceGroupId=F->GetStringField(TEXT("source_group_id"));Strings(F->GetArrayField(TEXT("source_placement_ids")),D.SourcePlacementIds);
        FTCHARToUTF8 U(*F->GetStringField(TEXT("source_metadata_canonical_utf8")));D.SourceMetadataCanonicalUtf8.Append(reinterpret_cast<const uint8*>(U.Get()),U.Length());D.SourceMetadataSha256=F->GetStringField(TEXT("source_metadata_sha256"));
        FString Hash;if(!LivingTownTiles::HashBytes(D.SourceMetadataCanonicalUtf8,Hash)||Hash!=D.SourceMetadataSha256||Fixtures.Contains(D.SourceGroupId))return Pack(TEXT("REFUSED"),TEXT("fixture_canonical_bytes_or_alias"));
        Fixtures.Add(D.SourceGroupId,D);DR.SourceFixtureInventory.Add(MoveTemp(D));
    }
    TArray<TStrongObjectPtr<ULivingTownRenderUnitData>> Drafts;TMap<FString,int32> DraftById;TSet<FString> EntryIds,InstanceIds,MeshPaths,Doors,PrototypeKeys;FString Error;
    for(const auto& V:SourceUnits)
    {
        const auto SU=V->AsObject();TStrongObjectPtr<ULivingTownRenderUnitData> Draft(NewObject<ULivingTownRenderUnitData>(GetTransientPackage()));auto& D=*Draft.Get();D.UnitId=SU->GetStringField(TEXT("unit_id"));D.Qualification=DR.Qualification;
        FLivingTownTileUnitRef Ref;Ref.UnitId=D.UnitId;Ref.Asset=TSoftObjectPtr<ULivingTownRenderUnitData>(FSoftObjectPath(SU->GetStringField(TEXT("asset_path"))));Strings(SU->GetArrayField(TEXT("dependencies")),Ref.Dependencies);Ref.ActualNativeBoundsCm=FBox(ForceInit);
        for(const auto& EV:SU->GetArrayField(TEXT("entries")))
        {
            const auto E=EV->AsObject();const FString Path=E->GetStringField(TEXT("asset_path"));const auto* Template=NativeTemplates.Find(Path);if(!Template)return Pack(TEXT("REFUSED"),TEXT("plan_mesh_not_in_actual_receipt"));
            FLivingTownTileGeometry G=*Template;G.EntryId=E->GetStringField(TEXT("entry_id"));G.SourceMeshKey=E->GetStringField(TEXT("mesh_key"));G.OwnerId=E->GetStringField(TEXT("owner_id"));G.FloorId=E->GetStringField(TEXT("floor_id"));G.RoomId=E->GetStringField(TEXT("room_id"));
            const FString Kind=E->GetStringField(TEXT("kind"));G.Kind=Kind==TEXT("Instanced")?ELivingTownTileEntryKind::Instanced:(Kind==TEXT("DeferredDoor")?ELivingTownTileEntryKind::DeferredDoor:ELivingTownTileEntryKind::Static);
            Strings(E->GetArrayField(TEXT("source_placement_ids")),G.SourcePlacementIds);G.ActualNativeBoundsCm=FBox(ForceInit);
            for(const auto& Id:G.SourcePlacementIds)if(LivingTownTiles::IsReservedCafeSourceId(Id))return Pack(TEXT("REFUSED"),TEXT("existing_cafe_source_duplicate"));
            for(const auto& PV:E->GetArrayField(TEXT("placements")))
            {
                FLivingTownTilePlacement P;if(!MatrixPlacement(PV->AsObject(),P,Error))return Pack(TEXT("REFUSED"),Error);
                if(G.Kind!=ELivingTownTileEntryKind::Instanced&&!P.QualifiedNativeTransform.Equals(FTransform::Identity,0))return Pack(TEXT("REFUSED"),TEXT("baked_static_double_transform"));
                if(G.Kind==ELivingTownTileEntryKind::Instanced){if(InstanceIds.Contains(P.SourcePlacementId))return Pack(TEXT("REFUSED"),TEXT("duplicate_instance_source_id"));InstanceIds.Add(P.SourcePlacementId);Ref.DeclaredInstanceSourceIds.Add(P.SourcePlacementId);}
                G.ActualNativeBoundsCm+=Template->ActualNativeBoundsCm.TransformBy(P.QualifiedNativeTransform.ToMatrixWithScale());G.Placements.Add(MoveTemp(P));
            }
            if(EntryIds.Contains(G.EntryId))return Pack(TEXT("REFUSED"),TEXT("duplicate_render_entry"));EntryIds.Add(G.EntryId);MeshPaths.Add(Path);Ref.DeclaredEntryIds.Add(G.EntryId);
            if(G.Kind==ELivingTownTileEntryKind::Instanced){PrototypeKeys.Add(G.SourceMeshKey);Ref.DeclaredInstanceEntryIds.Add(G.EntryId);Ref.DeclaredPrototypeMeshKeys.AddUnique(G.SourceMeshKey);}
            if(G.Kind==ELivingTownTileEntryKind::DeferredDoor){Doors.Add(G.EntryId);Ref.DeclaredDeferredDoorEntryIds.Add(G.EntryId);}
            Ref.ActualNativeBoundsCm+=G.ActualNativeBoundsCm;D.Geometry.Add(MoveTemp(G));
        }
        for(const auto& FV:SU->GetArrayField(TEXT("fixture_group_ids"))){const auto* F=Fixtures.Find(FV->AsString());if(!F)return Pack(TEXT("REFUSED"),TEXT("unit_fixture_missing"));D.DeferredFixtures.Add(*F);}
        if(D.Geometry.IsEmpty()||D.Geometry.Num()>128||DraftById.Contains(D.UnitId))return Pack(TEXT("REFUSED"),TEXT("bounded_unit_identity_or_geometry"));
        DraftById.Add(D.UnitId,Drafts.Num());Drafts.Add(MoveTemp(Draft));DR.Units.Add(MoveTemp(Ref));
    }
    if(EntryIds.Num()!=1638||InstanceIds.Num()!=587||MeshPaths.Num()!=1488||Doors.Num()!=150||PrototypeKeys.Num()!=52||Fixtures.Num()!=385)return Pack(TEXT("REFUSED"),TEXT("exact_native_staging_census"));
    for(const auto& SV:Plan->GetArrayField(TEXT("supports")))
    {
        const auto S=SV->AsObject();FLivingTownTileSupport D;D.SupportId=S->GetStringField(TEXT("support_id"));D.bRequestedCell=S->GetBoolField(TEXT("requested_cell"));const auto& L=S->GetArrayField(TEXT("min_native_xy_cm"));const auto& H=S->GetArrayField(TEXT("max_native_xy_cm"));
        D.MinNativeXYCm=FVector2D(L[0]->AsNumber(),L[1]->AsNumber());D.MaxNativeXYCm=FVector2D(H[0]->AsNumber(),H[1]->AsNumber());Strings(S->GetArrayField(TEXT("units")),D.Units);DR.Supports.Add(MoveTemp(D));
    }
    Strings(Plan->GetArrayField(TEXT("persistent_units")),DR.PersistentUnits);FLivingTownTileDemand Demand;if(!Demand.Initialize(DR.Units,Error))return Pack(TEXT("REFUSED"),Error);
    TMap<FString,TArray<FString>> AllSupports;for(const auto& S:DR.Supports)AllSupports.Add(S.SupportId,S.Units);AllSupports.Add(TEXT("persistent"),DR.PersistentUnits);
    if(!Demand.SetSupports(AllSupports,Error)||Demand.Counts().Num()!=DR.Units.Num())return Pack(TEXT("REFUSED"),TEXT("native_demand_graph_coverage: ")+Error);
    // Strict runtime validators must refuse staging because proof is pending.
    // No scratch flag promotion, validation bypass, or claimed activation.
    if(LivingTownTiles::ValidateRoot(DR,Error)||Error!=TEXT("tile_native_qualification_pending"))return Pack(TEXT("REFUSED"),TEXT("staging_runtime_refusal_contract: ")+Error);
    for(int32 I=0;I<Drafts.Num();++I){if(LivingTownTiles::ValidateUnit(*Drafts[I].Get(),DR.Units[I],DR.Qualification,Error)||Error!=TEXT("tile_native_qualification_pending"))return Pack(TEXT("REFUSED"),TEXT("staging_unit_runtime_refusal_contract: ")+Error);}
    // Commit only to previously validated empty, unsaved new staging objects.
    for(int32 I=0;I<Drafts.Num();++I){auto* Target=Targets[DR.Units[I].Asset.ToSoftObjectPath().ToString()];auto& D=*Drafts[I].Get();Target->SchemaVersion=D.SchemaVersion;Target->UnitId=D.UnitId;Target->Qualification=D.Qualification;Target->Geometry=MoveTemp(D.Geometry);Target->DeferredFixtures=MoveTemp(D.DeferredFixtures);}
    Root->SchemaVersion=DR.SchemaVersion;Root->Qualification=DR.Qualification;Root->ExistingCafeBindingSha256=DR.ExistingCafeBindingSha256;Root->Units=MoveTemp(DR.Units);Root->Supports=MoveTemp(DR.Supports);Root->PersistentUnits=MoveTemp(DR.PersistentUnits);Root->SourceFixtureInventory=MoveTemp(DR.SourceFixtureInventory);
    return ReadStagedTownAssets(Root,SourcePlanJson);
}

FString ULivingTownTileAuthoringLibrary::ReadStagedTownAssets(ULivingTownTileRootData* Root,const FString& SourcePlanJson)
{
    TSharedPtr<FJsonObject> Plan;if(!OwnedProject()||!FrozenPlan(SourcePlanJson,Plan)||!StagingObject(Root,RootPath,false)||!AllFalse(Root->Qualification)||Root->Units.Num()!=116||Root->Supports.Num()!=24||Root->SourceFixtureInventory.Num()!=385||Root->SourceMeshDefinitions!=1488||Root->SourcePlacedNodes!=2023||Root->SourceRepeatedPlacements!=587||Root->SourcePrototypeMeshes!=52||Root->SourceDeferredDoorBatches!=150||Root->SourceFixtureGroups!=385)return Pack(TEXT("REFUSED"),TEXT("staging_readback_owned_root_or_plan"));
    auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("schema"),TEXT("living_town.typed_town_staging_readback.v1"));R->SetStringField(TEXT("source_plan_sha256"),PlanSha);R->SetStringField(TEXT("root_asset_path"),Root->GetPathName());
    R->SetStringField(TEXT("source_assembly_sha256"),Root->Qualification.SourceAssemblySha256);R->SetStringField(TEXT("source_slice_sha256"),Root->Qualification.SourceSliceSha256);R->SetStringField(TEXT("expected_derivative_sha256"),Root->Qualification.QualifiedDerivativeSha256);R->SetStringField(TEXT("native_manifest_sha256"),Root->Qualification.NativeReadbackReceiptSha256);R->SetStringField(TEXT("existing_cafe_binding_sha256"),Root->ExistingCafeBindingSha256);
    R->SetBoolField(TEXT("assets_qualified"),false);R->SetBoolField(TEXT("coordinates_qualified"),false);R->SetBoolField(TEXT("materials_qualified"),false);R->SetBoolField(TEXT("collision_qualified"),false);R->SetBoolField(TEXT("runtime_enabled"),false);
    FString Error;const bool Accepted=LivingTownTiles::ValidateRoot(*Root,Error);if(Accepted||Error!=TEXT("tile_native_qualification_pending"))return Pack(TEXT("REFUSED"),TEXT("runtime_staging_refusal_changed: ")+Error);R->SetStringField(TEXT("strict_runtime_validation_error"),Error);
    TArray<TSharedPtr<FJsonValue>> Rows;int32 Entries=0,Instances=0,Doors=0;TSet<FString> EntryIds,InstanceIds,Prototypes,Paths;
    const auto& SourceUnits=Plan->GetArrayField(TEXT("units"));
    for(int32 I=0;I<Root->Units.Num();++I)
    {
        const auto& Ref=Root->Units[I];const auto SU=SourceUnits[I]->AsObject();const FString Path=Ref.Asset.ToSoftObjectPath().ToString();
        if(Ref.UnitId!=SU->GetStringField(TEXT("unit_id"))||Path!=SU->GetStringField(TEXT("asset_path"))||!SameStrings(SU->GetArrayField(TEXT("dependencies")),Ref.Dependencies))return Pack(TEXT("REFUSED"),TEXT("serialized_unit_catalog_identity"));
        auto* Unit=LoadObject<ULivingTownRenderUnitData>(nullptr,*Path);if(!StagingObject(Unit,Path,false)||Unit->UnitId!=Ref.UnitId||!AllFalse(Unit->Qualification)||Unit->Qualification.SourceAssemblySha256!=Root->Qualification.SourceAssemblySha256||Unit->Qualification.SourceSliceSha256!=Root->Qualification.SourceSliceSha256||Unit->Qualification.QualifiedDerivativeSha256!=Root->Qualification.QualifiedDerivativeSha256||Unit->Qualification.NativeReadbackReceiptSha256!=Root->Qualification.NativeReadbackReceiptSha256||Unit->Geometry.Num()!=SU->GetArrayField(TEXT("entries")).Num())return Pack(TEXT("REFUSED"),TEXT("serialized_unit_asset_identity"));
        auto U=MakeShared<FJsonObject>();U->SetStringField(TEXT("unit_id"),Ref.UnitId);U->SetStringField(TEXT("asset_path"),Path);TArray<TSharedPtr<FJsonValue>> Dependencies;for(const auto& D:Ref.Dependencies)Dependencies.Add(MakeShared<FJsonValueString>(D));U->SetArrayField(TEXT("dependencies"),Dependencies);
        TArray<TSharedPtr<FJsonValue>> Geometry;
        for(int32 J=0;J<Unit->Geometry.Num();++J)
        {
            const auto& G=Unit->Geometry[J];const auto Expected=SU->GetArrayField(TEXT("entries"))[J]->AsObject();
            const FString Kind=Expected->GetStringField(TEXT("kind"));const auto ExpectedKind=Kind==TEXT("Instanced")?ELivingTownTileEntryKind::Instanced:(Kind==TEXT("DeferredDoor")?ELivingTownTileEntryKind::DeferredDoor:ELivingTownTileEntryKind::Static);
            if(G.EntryId!=Expected->GetStringField(TEXT("entry_id"))||G.SourceMeshKey!=Expected->GetStringField(TEXT("mesh_key"))||G.Mesh.ToSoftObjectPath().ToString()!=Expected->GetStringField(TEXT("asset_path"))||G.Kind!=ExpectedKind||G.OwnerId!=Expected->GetStringField(TEXT("owner_id"))||G.FloorId!=Expected->GetStringField(TEXT("floor_id"))||G.RoomId!=Expected->GetStringField(TEXT("room_id"))||!SameStrings(Expected->GetArrayField(TEXT("source_placement_ids")),G.SourcePlacementIds)||G.bBlockingCollision||EntryIds.Contains(G.EntryId)||G.Placements.Num()!=Expected->GetArrayField(TEXT("placements")).Num())return Pack(TEXT("REFUSED"),TEXT("serialized_geometry_contract"));
            EntryIds.Add(G.EntryId);Paths.Add(G.Mesh.ToSoftObjectPath().ToString());++Entries;
            for(int32 K=0;K<G.Placements.Num();++K)
            {
                const auto P=Expected->GetArrayField(TEXT("placements"))[K]->AsObject();const auto& Actual=G.Placements[K];
                if(Actual.SourcePlacementId!=P->GetStringField(TEXT("source_placement_id"))||DoubleHash(Actual.SourceWorldMatrixRowMajor)!=P->GetStringField(TEXT("source_matrix_sha256"))||!LivingTownTiles::ValidatePlacement(Actual,Error))return Pack(TEXT("REFUSED"),TEXT("serialized_f64_placement: ")+Error);
                if(G.Kind==ELivingTownTileEntryKind::Instanced){if(InstanceIds.Contains(Actual.SourcePlacementId))return Pack(TEXT("REFUSED"),TEXT("serialized_instance_duplicate"));InstanceIds.Add(Actual.SourcePlacementId);++Instances;Prototypes.Add(G.SourceMeshKey);}
            }
            if(G.Kind==ELivingTownTileEntryKind::DeferredDoor)++Doors;Geometry.Add(MakeShared<FJsonValueObject>(GeometryReadback(G)));
        }
        U->SetArrayField(TEXT("geometry"),Geometry);U->SetArrayField(TEXT("actual_min_cm"),Vector(Ref.ActualNativeBoundsCm.Min));U->SetArrayField(TEXT("actual_max_cm"),Vector(Ref.ActualNativeBoundsCm.Max));
        TArray<TSharedPtr<FJsonValue>> Declared;for(const auto& Id:Ref.DeclaredEntryIds)Declared.Add(MakeShared<FJsonValueString>(Id));U->SetArrayField(TEXT("declared_entry_ids"),Declared);
        auto StringArray=[](const TArray<FString>& Values){TArray<TSharedPtr<FJsonValue>> A;for(const auto& V:Values)A.Add(MakeShared<FJsonValueString>(V));return A;};
        U->SetArrayField(TEXT("declared_instance_entry_ids"),StringArray(Ref.DeclaredInstanceEntryIds));U->SetArrayField(TEXT("declared_prototype_mesh_keys"),StringArray(Ref.DeclaredPrototypeMeshKeys));U->SetArrayField(TEXT("declared_instance_source_ids"),StringArray(Ref.DeclaredInstanceSourceIds));U->SetArrayField(TEXT("declared_deferred_door_entry_ids"),StringArray(Ref.DeclaredDeferredDoorEntryIds));
        TArray<TSharedPtr<FJsonValue>> FixtureIds;for(const auto& F:Unit->DeferredFixtures)FixtureIds.Add(MakeShared<FJsonValueString>(F.SourceGroupId));U->SetArrayField(TEXT("fixture_group_ids"),FixtureIds);Rows.Add(MakeShared<FJsonValueObject>(U));
    }
    if(Entries!=1638||Instances!=587||Doors!=150||Prototypes.Num()!=52||Paths.Num()!=1488)return Pack(TEXT("REFUSED"),TEXT("serialized_census"));
    R->SetArrayField(TEXT("units"),Rows);R->SetNumberField(TEXT("entry_count"),Entries);R->SetNumberField(TEXT("instance_count"),Instances);R->SetNumberField(TEXT("door_count"),Doors);
    TArray<TSharedPtr<FJsonValue>> Supports;for(const auto& S:Root->Supports){auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("id"),S.SupportId);O->SetBoolField(TEXT("requested_cell"),S.bRequestedCell);O->SetArrayField(TEXT("min_xy_cm"),{MakeShared<FJsonValueNumber>(S.MinNativeXYCm.X),MakeShared<FJsonValueNumber>(S.MinNativeXYCm.Y)});O->SetArrayField(TEXT("max_xy_cm"),{MakeShared<FJsonValueNumber>(S.MaxNativeXYCm.X),MakeShared<FJsonValueNumber>(S.MaxNativeXYCm.Y)});TArray<TSharedPtr<FJsonValue>> Ids;for(const auto& Id:S.Units)Ids.Add(MakeShared<FJsonValueString>(Id));O->SetArrayField(TEXT("units"),Ids);Supports.Add(MakeShared<FJsonValueObject>(O));}R->SetArrayField(TEXT("supports"),Supports);
    TArray<TSharedPtr<FJsonValue>> Fixtures;const auto& ExpectedFixtures=Plan->GetArrayField(TEXT("fixture_inventory"));
    for(int32 I=0;I<Root->SourceFixtureInventory.Num();++I)
    {
        const auto& F=Root->SourceFixtureInventory[I];const auto Expected=ExpectedFixtures[I]->AsObject();FString ActualHash;
        if(F.SourceGroupId!=Expected->GetStringField(TEXT("source_group_id"))||!SameStrings(Expected->GetArrayField(TEXT("source_placement_ids")),F.SourcePlacementIds)||!LivingTownTiles::HashBytes(F.SourceMetadataCanonicalUtf8,ActualHash)||ActualHash!=F.SourceMetadataSha256||ActualHash!=Expected->GetStringField(TEXT("source_metadata_sha256")))return Pack(TEXT("REFUSED"),TEXT("serialized_fixture_bytes_or_identity"));
        auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("id"),F.SourceGroupId);O->SetStringField(TEXT("sha256"),ActualHash);O->SetNumberField(TEXT("bytes"),F.SourceMetadataCanonicalUtf8.Num());Fixtures.Add(MakeShared<FJsonValueObject>(O));
    }
    R->SetArrayField(TEXT("fixture_inventory"),Fixtures);
    TArray<TSharedPtr<FJsonValue>> Persistent;for(const auto& Id:Root->PersistentUnits)Persistent.Add(MakeShared<FJsonValueString>(Id));R->SetArrayField(TEXT("persistent_units"),Persistent);
    R->SetBoolField(TEXT("native_or_asset_qualification_claimed"),false);return Pack(TEXT("PASS_STAGED_TYPED_DATA_RUNTIME_DISABLED"),FString(),R);
}

FString ULivingTownTileAuthoringLibrary::AddDisabledPreviewEntry(UWorld* World,ULivingTownRenderUnitData* Unit,int32 EntryIndex)
{
    if(!OwnedProject()||!IsValid(World)||World->WorldType!=EWorldType::Editor||!World->PersistentLevel||World->GetOutermost()->GetName()!=TEXT("/Game/LivingTown_UEPilot/Review_v001/L_TownSlice_Stage_v001")||!IsValid(Unit)||!StagingObject(Unit,Unit->GetPathName(),false)||!AllFalse(Unit->Qualification)||!Unit->Geometry.IsValidIndex(EntryIndex))return Pack(TEXT("REFUSED"),TEXT("preview_exact_editor_world_owned_staging_unit"));
    const auto& G=Unit->Geometry[EntryIndex];if(G.bBlockingCollision||G.Placements.IsEmpty())return Pack(TEXT("REFUSED"),TEXT("preview_collision_or_empty_placement"));
    for(const auto& Id:G.SourcePlacementIds)if(LivingTownTiles::IsReservedCafeSourceId(Id))return Pack(TEXT("REFUSED"),TEXT("preview_existing_cafe_duplicate"));
    FString Why;for(const auto& P:G.Placements)if(!LivingTownTiles::ValidatePlacement(P,Why))return Pack(TEXT("REFUSED"),TEXT("preview_placement_invalid: ")+Why);
    UStaticMesh* Mesh=G.Mesh.Get();if(!Mesh||Mesh->IsCompiling())return Pack(TEXT("REFUSED"),TEXT("preview_preloaded_immutable_mesh_required"));
    const FString Name=TEXT("LT_PREVIEW_")+Unit->UnitId+TEXT("_")+G.EntryId;
    if(Name.Len()>240||FindObject<UObject>(World->PersistentLevel,*Name))return Pack(TEXT("REFUSED"),TEXT("preview_duplicate_actor_name"));
    FActorSpawnParameters Params;Params.Name=FName(*Name);Params.ObjectFlags=RF_Transactional;
    AActor* Actor=World->SpawnActor<AActor>(AActor::StaticClass(),FTransform::Identity,Params);if(!Actor)return Pack(TEXT("REFUSED"),TEXT("preview_spawn_actor"));
    Actor->bIsEditorOnlyActor=true;Actor->PrimaryActorTick.bCanEverTick=false;Actor->SetActorTickEnabled(false);Actor->SetActorEnableCollision(false);Actor->SetActorHiddenInGame(true);Actor->SetActorLabel(Name,false);
    UStaticMeshComponent* Component=nullptr;
    if(G.Kind==ELivingTownTileEntryKind::Instanced)
    {
        auto* ISM=NewObject<UInstancedStaticMeshComponent>(Actor);Component=ISM;
        if(!ISM->SetStaticMesh(Mesh)){Actor->Destroy();return Pack(TEXT("REFUSED"),TEXT("preview_set_instanced_mesh"));}
        TArray<FTransform> Transforms;for(const auto& P:G.Placements)Transforms.Add(P.QualifiedNativeTransform);
        ISM->AddInstances(Transforms,false,false,false);if(ISM->GetInstanceCount()!=Transforms.Num()){Actor->Destroy();return Pack(TEXT("REFUSED"),TEXT("preview_instance_count"));}
    }
    else
    {
        if(G.Placements.Num()!=1){Actor->Destroy();return Pack(TEXT("REFUSED"),TEXT("preview_static_placement_count"));}
        Component=NewObject<UStaticMeshComponent>(Actor);if(!Component->SetStaticMesh(Mesh)){Actor->Destroy();return Pack(TEXT("REFUSED"),TEXT("preview_set_static_mesh"));}
        Component->SetRelativeTransform(G.Placements[0].QualifiedNativeTransform);
    }
    Component->SetMobility(EComponentMobility::Static);Component->PrimaryComponentTick.bCanEverTick=false;Component->SetComponentTickEnabled(false);Component->SetCanEverAffectNavigation(false);Component->SetGenerateOverlapEvents(false);Component->SetCollisionEnabled(ECollisionEnabled::NoCollision);Component->SetHiddenInGame(true);Component->SetVisibility(true);Component->ComponentTags.Add(FName(*G.EntryId));
    Actor->SetRootComponent(Component);Actor->AddInstanceComponent(Component);Component->RegisterComponent();if(!Component->IsRegistered()){Actor->Destroy();return Pack(TEXT("REFUSED"),TEXT("preview_component_registration"));}
    auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("actor_path"),Actor->GetPathName());R->SetStringField(TEXT("entry_id"),G.EntryId);R->SetNumberField(TEXT("created_components"),1);R->SetNumberField(TEXT("instances"),G.Kind==ELivingTownTileEntryKind::Instanced?G.Placements.Num():0);R->SetBoolField(TEXT("editor_only"),true);R->SetBoolField(TEXT("collision_enabled"),false);R->SetBoolField(TEXT("runtime_streaming_qualified"),false);return Pack(TEXT("PASS_EDITOR_ONLY_PREVIEW_COMPONENT_CREATED"),FString(),R);
}

FString ULivingTownTileAuthoringLibrary::ReadDisabledPreviewWorld(UWorld* World,ULivingTownTileRootData* Root)
{
    if(!OwnedProject()||!IsValid(World)||World->WorldType!=EWorldType::Editor||World->GetOutermost()->GetName()!=TEXT("/Game/LivingTown_UEPilot/Review_v001/L_TownSlice_Stage_v001")||!StagingObject(Root,RootPath,false)||!AllFalse(Root->Qualification))return Pack(TEXT("REFUSED"),TEXT("preview_readback_exact_world_staging_root"));
    TMap<FString,const FLivingTownTileGeometry*> Expected;TArray<TStrongObjectPtr<ULivingTownRenderUnitData>> Units;
    for(const auto& Ref:Root->Units)
    {
        auto* U=LoadObject<ULivingTownRenderUnitData>(nullptr,*Ref.Asset.ToSoftObjectPath().ToString());if(!U||!AllFalse(U->Qualification))return Pack(TEXT("REFUSED"),TEXT("preview_readback_unit_missing"));Units.Emplace(U);
        for(const auto& G:U->Geometry){const FString Name=TEXT("LT_PREVIEW_")+U->UnitId+TEXT("_")+G.EntryId;if(Expected.Contains(Name))return Pack(TEXT("REFUSED"),TEXT("preview_readback_duplicate_entry"));Expected.Add(Name,&G);}
    }
    int32 Components=0,Instances=0,Doors=0,Drivers=0,Pawns=0;double MaxInstanceMatrixDelta=0;TSet<FString> Seen;TMap<FString,int32> Classes;
    for(TActorIterator<AActor> It(World);It;++It)
    {
        AActor* A=*It;++Classes.FindOrAdd(A->GetClass()->GetPathName());if(A->IsA<APawn>())++Pawns;
        if(A->GetClass()->GetName().StartsWith(TEXT("LivingTownCafe")))return Pack(TEXT("REFUSED"),TEXT("preview_unexpected_cafe_actor"));
        if(auto* Driver=Cast<ALivingTownTileDriver>(A)){++Drivers;if(Driver->bEnableQualifiedPilot||!Driver->IsIdentityPlacement()||Driver->RootAsset.Get()!=Root)return Pack(TEXT("REFUSED"),TEXT("preview_driver_enabled_or_wrong_root"));}
        if(!A->GetName().StartsWith(TEXT("LT_PREVIEW_")))continue;
        const auto* Found=Expected.Find(A->GetName());if(!Found||Seen.Contains(A->GetName()))return Pack(TEXT("REFUSED"),TEXT("preview_actor_unexpected_or_duplicate"));Seen.Add(A->GetName());const auto& G=**Found;
        auto* C=Cast<UStaticMeshComponent>(A->GetRootComponent());
        if(!A->IsEditorOnly()||A->PrimaryActorTick.bCanEverTick||A->IsActorTickEnabled()||A->GetActorEnableCollision()||!A->GetActorTransform().Equals(FTransform::Identity,0)||!C||C->PrimaryComponentTick.bCanEverTick||C->IsComponentTickEnabled()||C->GetCollisionEnabled()!=ECollisionEnabled::NoCollision||C->CanEverAffectNavigation()||!C->GetStaticMesh()||C->GetStaticMesh()->GetPathName()!=G.Mesh.ToSoftObjectPath().ToString())return Pack(TEXT("REFUSED"),TEXT("preview_actor_component_identity_tick_or_collision"));
        ++Components;
        if(G.Kind==ELivingTownTileEntryKind::Instanced)
        {
            auto* ISM=Cast<UInstancedStaticMeshComponent>(C);if(!ISM||ISM->GetInstanceCount()!=G.Placements.Num())return Pack(TEXT("REFUSED"),TEXT("preview_ism_count_or_type"));
            for(int32 I=0;I<G.Placements.Num();++I)
            {
                FTransform Actual;if(!ISM->GetInstanceTransform(I,Actual,false)||Actual.ContainsNaN())return Pack(TEXT("REFUSED"),TEXT("preview_instance_transform_unavailable"));
                const FMatrix A0=Actual.ToMatrixWithScale(),B0=G.Placements[I].QualifiedNativeTransform.ToMatrixWithScale();
                for(int32 R=0;R<4;++R)for(int32 K=0;K<4;++K)MaxInstanceMatrixDelta=FMath::Max(MaxInstanceMatrixDelta,FMath::Abs(A0.M[R][K]-B0.M[R][K]));
                ++Instances;
            }
        }
        else if(C->GetRelativeTransform().Equals(G.Placements[0].QualifiedNativeTransform,0)==false)return Pack(TEXT("REFUSED"),TEXT("preview_static_transform_mismatch"));
        if(G.Kind==ELivingTownTileEntryKind::DeferredDoor)++Doors;
    }
    auto R=MakeShared<FJsonObject>();R->SetNumberField(TEXT("preview_components"),Components);R->SetNumberField(TEXT("instances"),Instances);R->SetNumberField(TEXT("deferred_door_components"),Doors);R->SetNumberField(TEXT("disabled_drivers"),Drivers);R->SetNumberField(TEXT("pawn_actors"),Pawns);
    R->SetNumberField(TEXT("maximum_instance_native_matrix_abs_delta"),MaxInstanceMatrixDelta);R->SetBoolField(TEXT("instance_buffer_coordinate_precision_qualified"),false);
    R->SetBoolField(TEXT("collision_enabled"),false);R->SetBoolField(TEXT("runtime_streaming_enabled"),false);R->SetBoolField(TEXT("gameplay_route_or_art_fps_qualified"),false);
    auto Census=MakeShared<FJsonObject>();for(const auto& P:Classes)Census->SetNumberField(P.Key,P.Value);R->SetObjectField(TEXT("all_actor_class_census"),Census);
    if(Expected.Num()!=1638||Components!=1638||Instances!=587||Doors!=150||Drivers!=1||Pawns!=0)return Pack(TEXT("REFUSED"),TEXT("preview_complete_inventory_count"),R);
    return Pack(TEXT("PASS_EDITOR_PREVIEW_INVENTORY_COORDINATE_DELTAS_UNQUALIFIED"),FString(),R);
}
