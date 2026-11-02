#include "LivingTownCafeBinding.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "Misc/FileHelper.h"
#include "HAL/FileManager.h"
#include "String/BytesToHex.h"
#include "Containers/StringConv.h"
THIRD_PARTY_INCLUDES_START
#include <openssl/sha.h>
THIRD_PARTY_INCLUDES_END

namespace
{
bool Keys(const FJsonObject& O,std::initializer_list<const TCHAR*> K)
{
    if(O.Values.Num()!=int32(K.size())) return false;
    for(const TCHAR* S:K) if(!O.Values.Contains(S)) return false; return true;
}
bool Str(const FJsonObject& O,const TCHAR* K,FString& V,int32 Limit=512)
{
    const auto P=O.TryGetField(K); if(!P || P->Type!=EJson::String) return false; V=P->AsString(); return !V.IsEmpty() && V.Len()<=Limit;
}
bool Hash(const FString& S,int32 Length=64)
{
    if(S.Len()!=Length) return false; for(TCHAR C:S) if(!((C>='0'&&C<='9')||(C>='a'&&C<='f'))) return false; return true;
}
bool Bool(const FJsonObject& O,const TCHAR* K,bool& V) { const auto P=O.TryGetField(K); if(!P || P->Type!=EJson::Boolean) return false; V=P->AsBool(); return true; }
bool Number(const FJsonObject& O,const TCHAR* K,double& V,double Min,double Max)
{
    const auto P=O.TryGetField(K); if(!P || P->Type!=EJson::Number) return false; V=P->AsNumber(); return FMath::IsFinite(V)&&V>=Min&&V<=Max;
}
bool VectorValue(const TSharedPtr<FJsonValue>& V,FVector& Out)
{
    if(!V || V->Type!=EJson::Array || V->AsArray().Num()!=3) return false;
    const auto& A=V->AsArray(); double C[3]; for(int I=0;I<3;++I) { if(A[I]->Type!=EJson::Number) return false; C[I]=A[I]->AsNumber(); if(!FMath::IsFinite(C[I])||FMath::Abs(C[I])>10000000) return false; }
    Out=FVector(C[0],C[1],C[2]); return true;
}
bool Transform(const FJsonObject& O,FTransform& Out)
{
    if(!Keys(O,{TEXT("translation_cm"),TEXT("rotation_quat_xyzw"),TEXT("scale")})) return false;
    FVector T,S; if(!VectorValue(O.TryGetField(TEXT("translation_cm")),T)||!VectorValue(O.TryGetField(TEXT("scale")),S)||S.GetAbsMin()<.0001||S.GetAbsMax()>1000) return false;
    const auto Q=O.TryGetField(TEXT("rotation_quat_xyzw")); if(!Q || Q->Type!=EJson::Array || Q->AsArray().Num()!=4) return false;
    double C[4]; for(int I=0;I<4;++I) { if(Q->AsArray()[I]->Type!=EJson::Number) return false; C[I]=Q->AsArray()[I]->AsNumber(); if(!FMath::IsFinite(C[I])) return false; }
    const FQuat Rotation(C[0],C[1],C[2],C[3]); if(!FMath::IsNearlyEqual(Rotation.SizeSquared(),1.,1e-6)) return false;
    Out=FTransform(Rotation,T,S); return Out.IsValid();
}
const FJsonObject* Object(const FJsonObject& O,const TCHAR* K)
{
    const auto P=O.TryGetField(K); return P && P->Type==EJson::Object && P->AsObject() ? P->AsObject().Get() : nullptr;
}
bool Current61Calibration(const FJsonObject& O,FLivingTownCurrent61BakedCalibration& C)
{
    if(!Keys(O,{TEXT("format"),TEXT("version"),TEXT("status"),TEXT("qualification_sha256"),TEXT("palm_socket_transform"),TEXT("walk_speed_cm_s"),TEXT("idle_duration_seconds"),TEXT("walk_duration_seconds")}))return false;
    FString Format,Version,Status;const FJsonObject* Palm=Object(O,TEXT("palm_socket_transform"));
    if(!Str(O,TEXT("format"),Format)||Format!=TEXT("LivingTown.Current61BakedAvatarCalibration")||
        !Str(O,TEXT("version"),Version)||Version!=TEXT("1")||!Str(O,TEXT("status"),Status)||Status!=TEXT("UE_AVATAR_CONTACT_QUALIFIED")||
        !Str(O,TEXT("qualification_sha256"),C.QualificationSha256)||!Hash(C.QualificationSha256)||C.QualificationSha256==FString::ChrN(64,TCHAR('0'))||
        !Palm||!Transform(*Palm,C.PalmSocketLocalTransform)||C.PalmSocketLocalTransform.GetScale3D()!=FVector::OneVector||
        !Number(O,TEXT("walk_speed_cm_s"),C.WalkSpeedCmPerSecond,60,500)||
        !Number(O,TEXT("idle_duration_seconds"),C.IdleDurationSeconds,15.333333333333334-1e-6,15.333333333333334+1e-6)||
        !Number(O,TEXT("walk_duration_seconds"),C.WalkDurationSeconds,2.3333333333333335-1e-6,2.3333333333333335+1e-6))return false;
    C.bReadQualifiedDescriptor=true;return C.IsValidated();
}
bool GameAsset(const FString& S) { return S.StartsWith(TEXT("/Game/")) && S.Contains(TEXT(".")) && !S.Contains(TEXT("..")) && !S.Contains(TEXT("\\")); }
bool MaterialAsset(const FString& S) { return (S.StartsWith(TEXT("/Game/"))||S.StartsWith(TEXT("/Engine/")))&&S.Contains(TEXT("."))&&!S.Contains(TEXT(".."))&&!S.Contains(TEXT("\\")); }
bool PartIdentity(const FString& S)
{
    const FString Legacy=TEXT("town_10_urban_core:node:");
    if(S.StartsWith(Legacy)) { int32 Node=0;return LexTryParseString(Node,*S.Mid(Legacy.Len()))&&Node>=8534&&Node<=8822&&S==FString::Printf(TEXT("town_10_urban_core:node:%d"),Node); }
    const FString Authored=TEXT("authored_cafe:instance:");
    if(!S.StartsWith(Authored,ESearchCase::CaseSensitive)||S.Len()<=Authored.Len()||S.Len()>192)return false;
    for(TCHAR C:S.Mid(Authored.Len()))if(!((C>='a'&&C<='z')||(C>='A'&&C<='Z')||(C>='0'&&C<='9')||C=='_'))return false;
    return true;
}
bool IdSet(const FJsonObject& O,const TCHAR* Key,TSet<FString>& Out)
{
    const TArray<TSharedPtr<FJsonValue>>* A=nullptr;
    if(!O.TryGetArrayField(Key,A)||A->IsEmpty()||A->Num()>512)return false;
    TSet<FName> Tags;
    for(const auto& V:*A)
    {
        if(!V||V->Type!=EJson::String)return false;const FString S=V->AsString();
        if(!PartIdentity(S)||Out.Contains(S))return false;const FName Tag(*S);
        if(Tags.Contains(Tag))return false;Out.Add(S);Tags.Add(Tag);
    }
    return true;
}
bool PartContract(const FJsonObject& O,FLivingTownCafeBinding& B)
{
    if(!Keys(O,{TEXT("format"),TEXT("version"),TEXT("scope"),TEXT("declared_count"),TEXT("part_ids"),TEXT("floor_ids"),TEXT("counter_ids"),TEXT("source_context"),TEXT("asset_materials")}))return false;
    FString Format,Version,Scope;double Count=0;
    if(!Str(O,TEXT("format"),Format)||Format!=TEXT("LivingTown.CafePartContract")||!Str(O,TEXT("version"),Version)||Version!=TEXT("1")||!Str(O,TEXT("scope"),Scope)||Scope!=TEXT("private_authored_cafe_scene.v1")||!Number(O,TEXT("declared_count"),Count,1,512)||Count!=double(int32(Count)))return false;
    B.DeclaredPartCount=int32(Count);
    if(!IdSet(O,TEXT("part_ids"),B.DeclaredPartIds)||!IdSet(O,TEXT("floor_ids"),B.DeclaredFloorPartIds)||!IdSet(O,TEXT("counter_ids"),B.DeclaredCounterPartIds)||B.DeclaredPartIds.Num()!=B.DeclaredPartCount)return false;
    for(const FString& Id:B.DeclaredFloorPartIds)if(!B.DeclaredPartIds.Contains(Id)||B.DeclaredCounterPartIds.Contains(Id))return false;
    for(const FString& Id:B.DeclaredCounterPartIds)if(!B.DeclaredPartIds.Contains(Id))return false;
    const FJsonObject* C=Object(O,TEXT("source_context"));
    if(!C||!Keys(*C,{TEXT("parent_binding_sha256"),TEXT("layout_plan_sha256"),TEXT("asset_cold_proof_sha256"),TEXT("source_geometry_manifest_sha256"),TEXT("context_sha256")}))return false;
    FString Tagged=TEXT("LivingTown.CafePartContext.v1\n");
    for(const TCHAR* K:{TEXT("parent_binding_sha256"),TEXT("layout_plan_sha256"),TEXT("asset_cold_proof_sha256"),TEXT("source_geometry_manifest_sha256")})
    { FString H;if(!Str(*C,K,H)||!Hash(H))return false;Tagged+=H+TEXT("\n"); }
    FString Claimed;FTCHARToUTF8 Encoded(*Tagged);TArray<uint8> Bytes;Bytes.Append(reinterpret_cast<const uint8*>(Encoded.Get()),Encoded.Length());
    if(!Str(*C,TEXT("context_sha256"),Claimed)||!Hash(Claimed)||!LivingTownCafeJournal::Sha256(Bytes,B.PartSourceContextSha256)||Claimed!=B.PartSourceContextSha256||Claimed!=B.PhysicalQualificationSha256)return false;
    const TArray<TSharedPtr<FJsonValue>>* Materials=nullptr;
    if(!O.TryGetArrayField(TEXT("asset_materials"),Materials)||Materials->IsEmpty()||Materials->Num()>B.DeclaredPartCount)return false;
    for(const auto& V:*Materials)
    {
        if(!V||V->Type!=EJson::Object||!V->AsObject())return false;const FJsonObject& M=*V->AsObject();FString Asset;
        const TArray<TSharedPtr<FJsonValue>>* Slots=nullptr;
        if(!Keys(M,{TEXT("asset"),TEXT("materials")})||!Str(M,TEXT("asset"),Asset)||!GameAsset(Asset)||B.DeclaredAssetMaterials.Contains(Asset)||!M.TryGetArrayField(TEXT("materials"),Slots)||Slots->IsEmpty()||Slots->Num()>16)return false;
        TArray<FString> Paths;
        for(const auto& S:*Slots) { if(!S||S->Type!=EJson::String||S->AsString().Len()>512||!MaterialAsset(S->AsString()))return false;Paths.Add(S->AsString()); }
        B.DeclaredAssetMaterials.Add(Asset,MoveTemp(Paths));
    }
    return true;
}
}

bool FLivingTownCurrent61BakedCalibration::IsValidated() const
{
    return bReadQualifiedDescriptor&&Hash(QualificationSha256)&&QualificationSha256!=FString::ChrN(64,TCHAR('0'))&&
        PalmSocketLocalTransform.IsValid()&&PalmSocketLocalTransform.GetScale3D()==FVector::OneVector&&
        FMath::IsFinite(WalkSpeedCmPerSecond)&&WalkSpeedCmPerSecond>=60&&WalkSpeedCmPerSecond<=500&&
        FMath::IsFinite(IdleDurationSeconds)&&FMath::Abs(IdleDurationSeconds-15.333333333333334)<=1e-6&&FMath::Abs(IdleDurationSeconds-15.333332821726799)<=1e-6&&
        FMath::IsFinite(WalkDurationSeconds)&&FMath::Abs(WalkDurationSeconds-2.3333333333333335)<=1e-6&&FMath::Abs(WalkDurationSeconds-2.333333139618238)<=1e-6;
}

bool FLivingTownCafeBinding::HasValidatedCurrent61BakedAvatarBinding() const
{
    return MotionStrategy==ELivingTownCafeMotionStrategy::Current61BakedSingleNode&&HasValidatedPartRoster()&&Current61BakedCalibration.IsValidated()&&
        Hash(PhysicalSceneSha256)&&Hash(SourceProjectionSha256)&&Hash(PhysicalQualificationSha256)&&Hash(BindingFileSha256)&&Hash(VisualSha256)&&
        MeshRelativeTransform.IsValid()&&MeshRelativeTransform.GetScale3D()==FVector::OneVector&&IdleRootDeltaCm==FVector::ZeroVector;
}

bool FLivingTownCafeBinding::HasValidatedPartRoster() const
{
    if(!bPartRosterValidated||DeclaredPartCount<1||DeclaredPartCount>512||Parts.Num()!=DeclaredPartCount||DeclaredPartIds.Num()!=DeclaredPartCount||DeclaredFloorPartIds.IsEmpty()||DeclaredCounterPartIds.IsEmpty())return false;
    if(!bAuthoredSceneTrial&&(DeclaredPartCount!=289||DeclaredFloorPartIds.Num()!=6||DeclaredCounterPartIds.Num()!=6))return false;
    TSet<FString> Ids,Assets;TSet<FName> Tags;TMap<FString,FString> Signatures;
    for(const auto& P:Parts)
    {
        if(!PartIdentity(P.Id)||(!bAuthoredSceneTrial&&!P.Id.StartsWith(TEXT("town_10_urban_core:node:")))||!GameAsset(P.AssetPath)||!Hash(P.RenderSha256)||!Hash(P.CollisionGuid,32))return false;
        if(P.Transform.GetScale3D().GetAbsMin()<.0001||P.Transform.GetScale3D().GetAbsMax()>1000)return false;
        const FName Tag(*P.Id);
        if(Ids.Contains(P.Id)||Tags.Contains(Tag)||!DeclaredPartIds.Contains(P.Id)||P.bFloor!=DeclaredFloorPartIds.Contains(P.Id)||P.bCounter!=DeclaredCounterPartIds.Contains(P.Id)||(P.bFloor&&P.bCounter)||!P.Transform.IsValid())return false;
        if(bAuthoredSceneTrial&&(!PartIdentity(P.Id)||P.Transform.GetScale3D().GetMin()<=0||!DeclaredAssetMaterials.Contains(P.AssetPath)))return false;
        const FString Signature=P.RenderSha256+TEXT(":")+P.CollisionGuid;
        if(const FString* Earlier=Signatures.Find(P.AssetPath);Earlier&&*Earlier!=Signature)return false;
        if(!bAuthoredSceneTrial&&Assets.Contains(P.AssetPath))return false;
        Ids.Add(P.Id);Tags.Add(Tag);Assets.Add(P.AssetPath);Signatures.Add(P.AssetPath,Signature);
    }
    if(bAuthoredSceneTrial)
    {
        for(const auto& Item:DeclaredAssetMaterials)
        { if(Item.Value.IsEmpty()||Item.Value.Num()>16)return false;for(const FString& Path:Item.Value)if(Path.Len()>512||!MaterialAsset(Path))return false; }
    }
    return !bAuthoredSceneTrial||(Assets.Num()==DeclaredAssetMaterials.Num()&&Hash(PartSourceContextSha256)&&PartSourceContextSha256==PhysicalQualificationSha256);
}

bool LivingTownCafeJournal::Sha256(const TArray<uint8>& Bytes,FString& Out)
{
    Out.Reset();uint8 Digest[SHA256_DIGEST_LENGTH];const uint8 Empty=0;
    const uint8* Data=Bytes.IsEmpty()?&Empty:Bytes.GetData();
    if(::SHA256(Data,static_cast<size_t>(Bytes.Num()),Digest)!=Digest)return false;
    BytesToHexLower(Digest,SHA256_DIGEST_LENGTH,Out);return Hash(Out);
}

bool LivingTownCafeJournal::HasUniqueObjectKeys(const FString& Json)
{
    struct FFrame { bool bObject; TSet<FString> Seen; explicit FFrame(bool B):bObject(B){} };
    TArray<FFrame> Stack; const TSharedRef<TJsonReader<>> Reader=TJsonReaderFactory<>::Create(Json); EJsonNotation N;
    while(Reader->ReadNext(N))
    {
        if(N==EJsonNotation::ObjectEnd || N==EJsonNotation::ArrayEnd) { if(Stack.IsEmpty()) return false; Stack.Pop(EAllowShrinking::No); continue; }
        if(!Stack.IsEmpty() && Stack.Last().bObject) { const FString K=Reader->GetIdentifier(); if(K.IsEmpty()||Stack.Last().Seen.Contains(K)) return false; Stack.Last().Seen.Add(K); }
        if(N==EJsonNotation::ObjectStart) Stack.Emplace(true); else if(N==EJsonNotation::ArrayStart) Stack.Emplace(false); else if(N==EJsonNotation::Error) return false;
    }
    return Stack.IsEmpty() && Reader->GetErrorMessage().IsEmpty();
}

bool FLivingTownCafeBinding::ReadQualifiedFile(const FString& Path,FLivingTownCafeBinding& Out,FString& Error)
{
    Error.Reset(); auto Fail=[&Error](const TCHAR* S){Error=S;return false;};
    const int64 Size=IFileManager::Get().FileSize(*Path);if(Size<=0||Size>2*1024*1024)return Fail(TEXT("physical_binding_missing_or_oversize"));
    TArray<uint8> Bytes; if(!FFileHelper::LoadFileToArray(Bytes,*Path)||Bytes.IsEmpty()||Bytes.Num()>2*1024*1024) return Fail(TEXT("physical_binding_missing_or_oversize"));
    FString Json; FFileHelper::BufferToString(Json,Bytes.GetData(),Bytes.Num()); if(!LivingTownCafeJournal::HasUniqueObjectKeys(Json)) return Fail(TEXT("invalid_or_duplicate_binding_json"));
    TSharedPtr<FJsonObject> O; if(!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),O)||!O) return Fail(TEXT("invalid_binding_json"));
    const bool bExplicitPartContract=O->Values.Contains(TEXT("part_contract"));
    const bool TopKeys=bExplicitPartContract
        ?Keys(*O,{TEXT("format"),TEXT("version"),TEXT("status"),TEXT("physical_scene_sha256"),TEXT("source_projection_sha256"),TEXT("physical_qualification_sha256"),TEXT("visual_sha256"),TEXT("logical_identity"),TEXT("resident"),TEXT("movement"),TEXT("spawn"),TEXT("counter_use_point_cm"),TEXT("floor_bounds_cm"),TEXT("parts"),TEXT("part_contract")})
        :Keys(*O,{TEXT("format"),TEXT("version"),TEXT("status"),TEXT("physical_scene_sha256"),TEXT("source_projection_sha256"),TEXT("physical_qualification_sha256"),TEXT("visual_sha256"),TEXT("logical_identity"),TEXT("resident"),TEXT("movement"),TEXT("spawn"),TEXT("counter_use_point_cm"),TEXT("floor_bounds_cm"),TEXT("parts")});
    if(!TopKeys)return Fail(TEXT("unsupported_physical_binding_fields"));
    FString Format,Version,Status; FLivingTownCafeBinding B;
    if(!Str(*O,TEXT("format"),Format)||Format!=TEXT("LivingTown.CafeProjectionBinding")||!Str(*O,TEXT("version"),Version)||(Version!=TEXT("1")&&Version!=TEXT("2")&&Version!=TEXT("3"))||!Str(*O,TEXT("status"),Status)||Status!=(bExplicitPartContract?TEXT("UE_ASSET_QUALIFIED_TRIAL"):TEXT("UE_PHYSICAL_QUALIFIED"))) return Fail(TEXT("physical_calibration_not_qualified"));
    if(!Str(*O,TEXT("physical_scene_sha256"),B.PhysicalSceneSha256)||!Hash(B.PhysicalSceneSha256)||!Str(*O,TEXT("source_projection_sha256"),B.SourceProjectionSha256)||!Hash(B.SourceProjectionSha256)||!Str(*O,TEXT("physical_qualification_sha256"),B.PhysicalQualificationSha256)||!Hash(B.PhysicalQualificationSha256)||!Str(*O,TEXT("visual_sha256"),B.VisualSha256)||!Hash(B.VisualSha256)||!LivingTownCafeJournal::Sha256(Bytes,B.BindingFileSha256)) return Fail(TEXT("invalid_physical_provenance"));
    B.bAuthoredSceneTrial=bExplicitPartContract;
    if(bExplicitPartContract) { const FJsonObject* Contract=Object(*O,TEXT("part_contract"));if(!Contract||!PartContract(*Contract,B))return Fail(TEXT("invalid_authored_part_contract_or_source_context")); }
    const FJsonObject* Identity=Object(*O,TEXT("logical_identity")); FString Space,Floor,Interaction,Property,Model;
    if(!Identity||!Keys(*Identity,{TEXT("space_id"),TEXT("floor_id"),TEXT("interaction_id"),TEXT("property_id"),TEXT("model_asset_id")})||!Str(*Identity,TEXT("space_id"),Space)||Space!=TEXT("cafe")||!Str(*Identity,TEXT("floor_id"),Floor)||Floor!=TEXT("1f")||!Str(*Identity,TEXT("interaction_id"),Interaction)||Interaction!=TEXT("cafe1f_counter")||!Str(*Identity,TEXT("property_id"),Property)||Property!=TEXT("cafe_ground_commercial_v1")||!Str(*Identity,TEXT("model_asset_id"),Model)||Model!=TEXT("Main_cafe_L00_Public_Room_A00_cafe_counter")) return Fail(TEXT("wrong_logical_to_physical_counter_identity"));
    const FJsonObject* Resident=Object(*O,TEXT("resident")); const FJsonObject* MeshTransform=Resident?Object(*Resident,TEXT("mesh_transform")):nullptr;
    const bool bWorker110=Version==TEXT("2");
    const bool bCurrent61Baked=Version==TEXT("3");
    const bool ResidentKeys=Resident&&(bCurrent61Baked
        ?Keys(*Resident,{TEXT("id"),TEXT("skeletal_mesh"),TEXT("idle_walk_blendspace"),TEXT("use_socket"),TEXT("mesh_transform"),TEXT("motion_strategy"),TEXT("idle_animation"),TEXT("walk_animation"),TEXT("avatar_calibration")})
        :(bWorker110
        ?Keys(*Resident,{TEXT("id"),TEXT("skeletal_mesh"),TEXT("idle_walk_blendspace"),TEXT("use_socket"),TEXT("mesh_transform"),TEXT("motion_strategy"),TEXT("idle_animation"),TEXT("walk_animation"),TEXT("idle_root_delta_cm")})
        :Keys(*Resident,{TEXT("id"),TEXT("skeletal_mesh"),TEXT("idle_walk_blendspace"),TEXT("use_socket"),TEXT("mesh_transform")})));
    if(!Resident||!ResidentKeys||!Str(*Resident,TEXT("id"),B.ResidentId)||B.ResidentId!=TEXT("ben")||!Str(*Resident,TEXT("skeletal_mesh"),B.VisualAssetPath)||!GameAsset(B.VisualAssetPath)||!Str(*Resident,TEXT("idle_walk_blendspace"),B.IdleWalkBlendSpacePath)||!GameAsset(B.IdleWalkBlendSpacePath)||!Str(*Resident,TEXT("use_socket"),B.UseSocket,128)||!MeshTransform||!Transform(*MeshTransform,B.MeshRelativeTransform)) return Fail(TEXT("qualified_Ben_visual_or_motion_binding_missing"));
    if(bWorker110)
    {
        FString Strategy;
        if(!Str(*Resident,TEXT("motion_strategy"),Strategy)||Strategy!=LivingTownCafeWorker110::Strategy||
            !Str(*Resident,TEXT("idle_animation"),B.IdleAnimationPath)||B.IdleAnimationPath!=LivingTownCafeWorker110::IdleAsset||
            !Str(*Resident,TEXT("walk_animation"),B.WalkAnimationPath)||B.WalkAnimationPath!=LivingTownCafeWorker110::WalkAsset||
            !VectorValue(Resident->TryGetField(TEXT("idle_root_delta_cm")),B.IdleRootDeltaCm)||
            B.IdleRootDeltaCm!=LivingTownCafeWorker110::RootDeltaCm()||
            B.VisualAssetPath!=LivingTownCafeWorker110::MeshAsset||B.IdleWalkBlendSpacePath!=LivingTownCafeWorker110::MotionAsset||B.UseSocket!=LivingTownCafeWorker110::PalmSocket)
            return Fail(TEXT("unsupported_or_unqualified_worker110_family"));
        B.MotionStrategy=ELivingTownCafeMotionStrategy::CafeWorker110RootAligned;
    }
    if(bCurrent61Baked)
    {
        FString Strategy;const FJsonObject* Calibration=Object(*Resident,TEXT("avatar_calibration"));
        if(!Str(*Resident,TEXT("motion_strategy"),Strategy)||Strategy!=LivingTownCafeCurrent61Baked::Strategy||
            !Str(*Resident,TEXT("idle_animation"),B.IdleAnimationPath)||B.IdleAnimationPath!=LivingTownCafeCurrent61Baked::IdleAsset||
            !Str(*Resident,TEXT("walk_animation"),B.WalkAnimationPath)||B.WalkAnimationPath!=LivingTownCafeCurrent61Baked::WalkAsset||
            B.VisualAssetPath!=LivingTownCafeCurrent61Baked::MeshAsset||B.IdleWalkBlendSpacePath!=LivingTownCafeCurrent61Baked::MotionAsset||B.UseSocket!=LivingTownCafeCurrent61Baked::PalmSocket||
            B.MeshRelativeTransform.GetScale3D()!=FVector::OneVector||!Calibration||!Current61Calibration(*Calibration,B.Current61BakedCalibration))
            return Fail(TEXT("unsupported_or_unqualified_current61_baked_avatar_calibration"));
        B.MotionStrategy=ELivingTownCafeMotionStrategy::Current61BakedSingleNode;
    }
    const FJsonObject* Move=Object(*O,TEXT("movement")); double Radius,Half,Reach,Speed,Arm;
    if(!Move||!Keys(*Move,{TEXT("capsule_radius_cm"),TEXT("capsule_half_height_cm"),TEXT("reach_cm"),TEXT("walk_speed_cm_s"),TEXT("camera_arm_cm")})||!Number(*Move,TEXT("capsule_radius_cm"),Radius,12,45)||!Number(*Move,TEXT("capsule_half_height_cm"),Half,50,120)||Radius>=Half||!Number(*Move,TEXT("reach_cm"),Reach,25,160)||!Number(*Move,TEXT("walk_speed_cm_s"),Speed,60,500)||!Number(*Move,TEXT("camera_arm_cm"),Arm,100,450)) return Fail(TEXT("invalid_calibrated_movement_dimensions"));
    if(bWorker110&&Speed!=110.)return Fail(TEXT("worker110_movement_axis_must_match"));
    if(bCurrent61Baked&&Speed!=B.Current61BakedCalibration.WalkSpeedCmPerSecond)return Fail(TEXT("current61_baked_movement_must_match_measured_gait_axis"));
    B.CapsuleRadiusCm=float(Radius); B.CapsuleHalfHeightCm=float(Half); B.ReachCm=float(Reach); B.WalkSpeedCmPerSecond=float(Speed); B.CameraArmCm=float(Arm);
    const FJsonObject* Spawn=Object(*O,TEXT("spawn")); FVector Rotation=FVector::ZeroVector;
    if(!Spawn||!Keys(*Spawn,{TEXT("feet_cm"),TEXT("rotation_degrees")})||!VectorValue(Spawn->TryGetField(TEXT("feet_cm")),B.SpawnFeetCm)||!VectorValue(Spawn->TryGetField(TEXT("rotation_degrees")),Rotation)||!VectorValue(O->TryGetField(TEXT("counter_use_point_cm")),B.CounterUsePointCm)) return Fail(TEXT("invalid_calibrated_spawn_or_use_point"));
    B.SpawnRotation=FRotator(Rotation.X,Rotation.Y,Rotation.Z);
    const auto Bounds=O->TryGetField(TEXT("floor_bounds_cm")); FVector Min,Max;
    if(!Bounds||Bounds->Type!=EJson::Array||Bounds->AsArray().Num()!=2||!VectorValue(Bounds->AsArray()[0],Min)||!VectorValue(Bounds->AsArray()[1],Max)||Min.X>=Max.X||Min.Y>=Max.Y||Min.Z>Max.Z) return Fail(TEXT("invalid_actual_floor_bounds")); B.FloorBoundsCm=FBox(Min,Max);
    const int32 ExpectedParts=bExplicitPartContract?B.DeclaredPartCount:289;
    const TArray<TSharedPtr<FJsonValue>>* Parts=nullptr; if(!O->TryGetArrayField(TEXT("parts"),Parts)||Parts->Num()!=ExpectedParts) return Fail(bExplicitPartContract?TEXT("exact_declared_source_parts_required"):TEXT("exact_289_source_parts_required"));
    TSet<FString> Seen,SeenAssets,FloorIds,CounterIds;int32 Floors=0,Counters=0;
    const TSet<int32> FloorNodes={8559,8562,8615,8649,8673,8684};const TSet<int32> CounterNodes={8564,8565,8566,8570,8571,8572};
    for(const auto& V:*Parts)
    {
        if(!V||V->Type!=EJson::Object||!V->AsObject()) return Fail(TEXT("invalid_part_record")); const FJsonObject& P=*V->AsObject(); FLivingTownCafePartBinding Part;
        if(!Keys(P,{TEXT("id"),TEXT("asset"),TEXT("render_sha256"),TEXT("collision_guid"),TEXT("transform"),TEXT("floor"),TEXT("counter")})) return Fail(TEXT("unsupported_part_fields"));
        const FJsonObject* T=Object(P,TEXT("transform"));
        if(!Str(P,TEXT("id"),Part.Id)||(!bExplicitPartContract&&!Part.Id.StartsWith(TEXT("town_10_urban_core:node:")))||Seen.Contains(Part.Id)||!Str(P,TEXT("asset"),Part.AssetPath)||!GameAsset(Part.AssetPath)||!Str(P,TEXT("render_sha256"),Part.RenderSha256)||!Hash(Part.RenderSha256)||!Str(P,TEXT("collision_guid"),Part.CollisionGuid)||!Hash(Part.CollisionGuid,32)||!T||!Transform(*T,Part.Transform)||!Bool(P,TEXT("floor"),Part.bFloor)||!Bool(P,TEXT("counter"),Part.bCounter)||(Part.bFloor&&Part.bCounter)) return Fail(TEXT("invalid_or_duplicate_exact_source_part"));
        int32 SourceNode=0;const FString ScopePrefix=TEXT("town_10_urban_core:node:");const FString Suffix=Part.Id.Mid(ScopePrefix.Len());
        if(bExplicitPartContract)
        {
            if(!PartIdentity(Part.Id)||!B.DeclaredPartIds.Contains(Part.Id)||Part.bFloor!=B.DeclaredFloorPartIds.Contains(Part.Id)||Part.bCounter!=B.DeclaredCounterPartIds.Contains(Part.Id)||Part.Transform.GetScale3D().GetMin()<=0)return Fail(TEXT("declared_part_identity_role_or_transform_mismatch"));
        }
        else if(!LexTryParseString(SourceNode,*Suffix)||SourceNode<8534||SourceNode>8822||Part.Id!=FString::Printf(TEXT("town_10_urban_core:node:%d"),SourceNode)||Part.bFloor!=FloorNodes.Contains(SourceNode)||Part.bCounter!=CounterNodes.Contains(SourceNode)||SeenAssets.Contains(Part.AssetPath))return Fail(TEXT("exact_source_node_asset_or_role_scope_mismatch"));
        if(Part.bFloor)FloorIds.Add(Part.Id);if(Part.bCounter)CounterIds.Add(Part.Id);
        Seen.Add(Part.Id);SeenAssets.Add(Part.AssetPath);Floors+=Part.bFloor?1:0;Counters+=Part.bCounter?1:0;B.Parts.Add(MoveTemp(Part));
    }
    if(Seen.Num()!=ExpectedParts||(!bExplicitPartContract&&(Floors!=6||Counters!=6))) return Fail(TEXT("exact_actual_floor_and_counter_parts_required"));
    if(!bExplicitPartContract) { B.DeclaredPartCount=289;B.DeclaredPartIds=Seen;B.DeclaredFloorPartIds=FloorIds;B.DeclaredCounterPartIds=CounterIds; }
    B.bPartRosterValidated=true;if(!B.HasValidatedPartRoster())return Fail(TEXT("authored_roster_asset_alias_or_material_scope_mismatch"));
    Out=MoveTemp(B); return true; // no partially accepted binding escapes
}

bool LivingTownCafeJournal::Encode(const FLivingTownCafeBinding& B,const FString& Inner,FString& Out,FString& Error)
{
    Out.Reset(); Error.Reset(); if(!Hash(B.PhysicalSceneSha256)||!Hash(B.BindingFileSha256)||!Hash(B.VisualSha256)||!Hash(B.PhysicalQualificationSha256)||Inner.IsEmpty()||Inner.Len()>2*1024*1024) { Error=TEXT("projection_not_bound_or_inner_oversize"); return false; }
    const auto O=MakeShared<FJsonObject>(); O->SetStringField(TEXT("format"),TEXT("LivingTown.CafeProjectionJournal")); O->SetStringField(TEXT("version"),TEXT("1")); O->SetStringField(TEXT("scope"),TEXT("native_cafe_walk_lease.v1"));
    O->SetStringField(TEXT("physical_scene_sha256"),B.PhysicalSceneSha256); O->SetStringField(TEXT("physical_binding_sha256"),B.BindingFileSha256); O->SetStringField(TEXT("physical_qualification_sha256"),B.PhysicalQualificationSha256); O->SetStringField(TEXT("visual_sha256"),B.VisualSha256); O->SetStringField(TEXT("session_id"),TEXT("ben")); O->SetStringField(TEXT("position_policy"),TEXT("current_physical_position_unchanged")); O->SetStringField(TEXT("lease_journal"),Inner);
    const bool Ok=FJsonSerializer::Serialize(O,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Out))&&Out.Len()<=6*1024*1024; if(!Ok) Error=TEXT("projection_encoding_failed"); return Ok;
}
bool LivingTownCafeJournal::Decode(const FString& Json,const FLivingTownCafeBinding& B,FString& Inner,FString& Error)
{
    Inner.Reset(); Error.Reset(); auto Fail=[&Error](const TCHAR* S){Error=S;return false;}; if(Json.Len()>6*1024*1024||!HasUniqueObjectKeys(Json)) return Fail(TEXT("invalid_or_duplicate_projection_json"));
    TSharedPtr<FJsonObject> O; if(!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),O)||!O) return Fail(TEXT("invalid_projection_json"));
    if(!Keys(*O,{TEXT("format"),TEXT("version"),TEXT("scope"),TEXT("physical_scene_sha256"),TEXT("physical_binding_sha256"),TEXT("physical_qualification_sha256"),TEXT("visual_sha256"),TEXT("session_id"),TEXT("position_policy"),TEXT("lease_journal")})) return Fail(TEXT("legacy_or_unsupported_projection_envelope"));
    FString Format,Version,Scope,Scene,Binding,Qualification,Visual,Session,Position,Lease;
    if(!Str(*O,TEXT("format"),Format)||Format!=TEXT("LivingTown.CafeProjectionJournal")||!Str(*O,TEXT("version"),Version)||Version!=TEXT("1")||!Str(*O,TEXT("scope"),Scope)||Scope!=TEXT("native_cafe_walk_lease.v1")||!Str(*O,TEXT("physical_scene_sha256"),Scene)||Scene!=B.PhysicalSceneSha256||!Str(*O,TEXT("physical_binding_sha256"),Binding)||Binding!=B.BindingFileSha256||!Str(*O,TEXT("physical_qualification_sha256"),Qualification)||Qualification!=B.PhysicalQualificationSha256||!Str(*O,TEXT("visual_sha256"),Visual)||Visual!=B.VisualSha256||!Str(*O,TEXT("session_id"),Session)||Session!=TEXT("ben")||!Str(*O,TEXT("position_policy"),Position)||Position!=TEXT("current_physical_position_unchanged")||!Str(*O,TEXT("lease_journal"),Lease,2*1024*1024)) return Fail(TEXT("unsupported_projection_version_or_physical_provenance"));
    Inner=MoveTemp(Lease); return true; // caller invokes unchanged strict atomic lease loader exactly once
}
