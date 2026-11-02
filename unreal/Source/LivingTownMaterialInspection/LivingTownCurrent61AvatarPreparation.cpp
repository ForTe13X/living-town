#include "LivingTownCurrent61AvatarPreparation.h"
#include "LivingTownCafeBinding.h"
#include "LivingTownTileData.h"
#include "Animation/AnimSequence.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Animation/BlendSpace1D.h"
#include "Animation/Skeleton.h"
#include "AssetCompilingManager.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/ExternalMorphSet.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/SkeletalMeshSocket.h"
#include "Engine/SkeletalMeshSourceModel.h"
#include "MeshDescription.h"
#include "MeshDescriptionBase.h"
#include "SkeletalMeshAttributes.h"
#include "Rendering/SkeletalMeshModel.h"
#include "Engine/World.h"
#include "GameFramework/Actor.h"
#include "Materials/Material.h"
#include "Rendering/SkeletalMeshRenderData.h"
#include "Rendering/SkeletalMeshLODRenderData.h"
#include "Rendering/SkinWeightVertexBuffer.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/MemoryWriter.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "HAL/FileManager.h"
#include "UObject/Package.h"
#include "UObject/SavePackage.h"
#include "UObject/StrongObjectPtr.h"
#include "UObject/UnrealType.h"
#if PLATFORM_WINDOWS
#include "Windows/WindowsHWrapper.h"
#endif

namespace Current61AvatarCandidate
{
constexpr const TCHAR* SourcePath=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/SK_Worker110BakedPBR_v006.SK_Worker110BakedPBR_v006");
constexpr const TCHAR* SkeletonPath=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedDefault_v001/SK_Worker110Current61_BakedREST_v001_Skeleton.SK_Worker110Current61_BakedREST_v001_Skeleton");
constexpr const TCHAR* MeshPackage=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedAvatar_v001/SK_Worker110Current61_BakedAvatar_v001");
constexpr const TCHAR* MotionPackage=TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedAvatar_v001/BS_Worker110Current61_BakedIdleWalk_v001");
struct FExpectedPackage {const TCHAR* Package;const TCHAR* Hash;int64 Bytes;};
// EXACT_SOURCE_PACKAGES_BEGIN
static const FExpectedPackage ExpectedPackages[]={
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedDefault_v001/SK_Worker110Current61_BakedREST_v001"),TEXT("b3f22cd9736b8b3b148fe36d08f5bb00fd23c79cad8fc3e3553efd428cffbf0a"),12043447},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedDefault_v001/SK_Worker110Current61_BakedREST_v001_Skeleton"),TEXT("6769c3700866e27dc129f2e4bfcd701a1621e74ed1810d64f46c04fd2a7b89e6"),23914},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_apron_0"),TEXT("29e72ee9e35b2a05cd7744bf1c67c01f9308f3d256e0d2a1fd090890e285496e"),19405},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_body_1"),TEXT("4f60f6a6815e8098844c83d0494e4e1f9456f4c9af7fe2f993353a896f7ec603"),11950},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_body_2"),TEXT("63cbdad75e1b41187afb5dd1312561fa28e38b29b2a75a2134aaefd9c785da66"),13381},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_brows_0"),TEXT("b416988dba2967c81297763fd076561408d294013439e464c749013e68867851"),14345},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_eyes_0"),TEXT("5eff28bc564dc4315fda8074bbece189611d71c700b051c13e6cf5d5c711a248"),12264},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_garment_0"),TEXT("476cf8d6403d0f7d7a81779fd86e424599f5f5ba56b3482a257502a383463f83"),19102},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_pants_0"),TEXT("bc6a6240f6ecba801f18aec4f8443aaaa439cd2803262caa1dfb295576f5aac6"),13983},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Materials/M_Baked_shoes_0"),TEXT("568a92ad3838feade0345b32e37b712965d4c6602c7bcdac34fa62002a084ed8"),14872},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/SK_Worker110BakedPBR_v006"),TEXT("d184aedf07a2bf75261b356e86e2039e9c6a6f94e1a3338509db8591f32f9929"),12046294},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Textures/T_Baked_3fd0bba5dcbd"),TEXT("2fa77aca53f6c6655e129956a62884c0249d477a5c07cb954e55c6d2aa3982aa"),4401704},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Textures/T_Baked_4659691c7295"),TEXT("80c4bd068054df58849c87e285b09d6e3196d1d085faa8ef1488c30170f9ce47"),706851},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Textures/T_Baked_50c9a406a7f1"),TEXT("589ed737a042ab003fcf2010527044e65d049aa8fae96bf9ef309265fba3153a"),1557915},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Textures/T_Baked_7258dd3cf124"),TEXT("fb234f06622f6877c50eae9c3990573fef496171c470f8d350767b11eb4afa14"),104094},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Textures/T_Baked_81d01c6ea27d"),TEXT("a0bee5892cbd33b5fcc19aeaf809f58a7558e5b35375155c028152f5d1ce3731"),4407821},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Textures/T_Baked_95423492c8de"),TEXT("fed1a3de156a182df4b01ef3e6b38fe48e25f1bd4bfa2d5e2fdc530d206d6f50"),2387031},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Textures/T_Baked_a9bfd7223e98"),TEXT("38dbbb075ba44e7c958b47183bf67b59dbd036eb096001c12a8e27e001ba268c"),1106637},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Textures/T_Baked_c5733ad50cfe"),TEXT("b334f62cb6ca7d443b69b1af13e5b5fa8fad388d254dd63d7068505b497e91b3"),3863447},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Textures/T_Baked_c5f29705fc18"),TEXT("9f8a33158dfba09b75bea8fb5f53732d85baf148a8f6cf05d1ddbc6677dd05df"),5208697},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Textures/T_Baked_e71016e08dfe"),TEXT("70a1fa9d5e1d63e6c18fc8e2d01f21443a480b5b5344ce2e8f4224bbb26b2437"),3621091},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMaterials_v001/Textures/T_Baked_ff029fc5a335"),TEXT("890a6a19756e3a1e7f6a697c98aa1898567199f3a6c73d4eff67b443a383f04a"),2154619},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMotion_v001/A_Worker110_BakedIdle_v001"),TEXT("bbc30d666afc78f5026ae47436e89adf955c6495c821c39f5275e14b716a0c9e"),2356898},
    {TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedMotion_v001/A_Worker110_BakedWalk_v001"),TEXT("2a1251a23c38ccae4a2a5f6ce4a32a86fc6196784d265a23c25c55b1f2024fde"),319029}
};
// EXACT_SOURCE_PACKAGES_END
constexpr uint64 FileCap=256ull<<20,BodyCap=64ull<<20;
bool Context(){return IsInGameThread()&&GIsEditor&&!IsRunningCommandlet();}
bool Loaded(const UObject* O){return O&&!O->IsTemplate()&&!O->HasAnyFlags(RF_NeedLoad|RF_NeedPostLoad|RF_BeginDestroyed|RF_FinishDestroyed);}
int32 Work(){return FAssetCompilingManager::Get().GetNumRemainingAssets();}
bool Hash(const FString& S){if(S.Len()!=64||S==FString::ChrN(64,TCHAR('0')))return false;for(TCHAR C:S)if(!((C>='0'&&C<='9')||(C>='a'&&C<='f')))return false;return true;}
FString Json(const TSharedRef<FJsonObject>& O)
{
    FString S;FJsonSerializer::Serialize(O,TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&S));return S.Len()<=1048576?S:TEXT("{\"status\":\"REFUSED\",\"reason\":\"JSON_1MiB\"}");
}
FString Refuse(const TCHAR* Why){auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("REFUSED"));O->SetStringField(TEXT("reason"),Why);return Json(O);}
TArray<TSharedPtr<FJsonValue>> V(const FVector& P){return {MakeShared<FJsonValueNumber>(P.X),MakeShared<FJsonValueNumber>(P.Y),MakeShared<FJsonValueNumber>(P.Z)};}
TSharedRef<FJsonObject> TRS(const FTransform& T)
{
    auto O=MakeShared<FJsonObject>();O->SetArrayField(TEXT("translation_cm"),V(T.GetTranslation()));O->SetArrayField(TEXT("scale"),V(T.GetScale3D()));const auto Q=T.GetRotation();O->SetArrayField(TEXT("rotation_quat_xyzw"),{MakeShared<FJsonValueNumber>(Q.X),MakeShared<FJsonValueNumber>(Q.Y),MakeShared<FJsonValueNumber>(Q.Z),MakeShared<FJsonValueNumber>(Q.W)});return O;
}
bool NoReparse(const FString& Absolute)
{
#if PLATFORM_WINDOWS
    FString N=Absolute.Replace(TEXT("/"),TEXT("\\"));if(N.Len()<3||N[1]!=':'||N[2]!='\\')return false;
    FString P=N.Left(3);TArray<FString> Parts;N.Mid(3).ParseIntoArray(Parts,TEXT("\\"),true);
    auto Check=[](const FString& X){DWORD A=GetFileAttributesW(*X);return A!=INVALID_FILE_ATTRIBUTES&&!(A&FILE_ATTRIBUTE_REPARSE_POINT);};if(!Check(P))return false;
    for(const FString& Part:Parts){if(Part==TEXT(".")||Part==TEXT(".."))return false;P=FPaths::Combine(P,Part);if(IFileManager::Get().FileExists(*P)||IFileManager::Get().DirectoryExists(*P)){if(!Check(P))return false;}else break;}return true;
#else
    return false;
#endif
}
struct FFileState
{
    FString Package,File,Sha;UPackage* LoadedPackage=nullptr;int64 Bytes=-1;FDateTime Time;bool Dirty=false;
};
bool FileState(const FString& Package,FFileState& S)
{
    S.Package=Package;S.File=FPaths::ConvertRelativePathToFull(FPackageName::LongPackageNameToFilename(Package,FPackageName::GetAssetPackageExtension()));const FString Root=FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir());
    if(!FPaths::IsUnderDirectory(S.File,Root)||!NoReparse(S.File))return false;
    S.Bytes=IFileManager::Get().FileSize(*S.File);S.Time=IFileManager::Get().GetTimeStamp(*S.File);S.LoadedPackage=FindPackage(nullptr,*Package);S.Dirty=S.LoadedPackage&&S.LoadedPackage->IsDirty();
    if(S.Bytes<=0||uint64(S.Bytes)>FileCap||S.Dirty)return false;TArray<uint8> B;
    return FFileHelper::LoadFileToArray(B,*S.File)&&B.Num()==S.Bytes&&LivingTownTiles::HashBytes(B,S.Sha)&&IFileManager::Get().FileSize(*S.File)==S.Bytes&&IFileManager::Get().GetTimeStamp(*S.File)==S.Time;
}
bool SameFile(const FFileState& A,const FFileState& B){return A.Package==B.Package&&A.File==B.File&&A.Sha==B.Sha&&A.Bytes==B.Bytes&&A.Time==B.Time&&A.LoadedPackage==B.LoadedPackage&&A.Dirty==B.Dirty;}
bool Originals(TArray<FFileState>& Rows)
{
    for(const auto& E:ExpectedPackages){FFileState S;if(!FileState(E.Package,S)||S.Bytes!=E.Bytes||S.Sha!=E.Hash)return false;Rows.Add(S);}return Rows.Num()==24;
}
bool OriginalCustody(const TArray<FFileState>& Before)
{
    if(Before.Num()!=24)return false;for(const FFileState& A:Before){FFileState B;if(!FileState(A.Package,B)||!SameFile(A,B))return false;}return true;
}
bool Fresh(const TCHAR* Package)
{
    const FString File=FPaths::ConvertRelativePathToFull(FPackageName::LongPackageNameToFilename(Package,FPackageName::GetAssetPackageExtension()));
    if(!FPaths::IsUnderDirectory(File,FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()))||!NoReparse(File)||FindPackage(nullptr,Package)||IFileManager::Get().FileExists(*File))return false;
    for(const TCHAR* Ext:{TEXT(".uasset"),TEXT(".uexp"),TEXT(".ubulk"),TEXT(".uptnl")})if(IFileManager::Get().FileExists(*FPaths::ChangeExtension(File,Ext)))return false;return true;
}
bool HasCPUWeightAndLookupData(const FSkinWeightVertexBuffer* Skin)
{
    if(!Skin||Skin->GetNumVertices()!=43432||Skin->GetMaxBoneInfluences()>12)return false;
    const auto* Data=Skin->GetDataVertexBuffer();const auto* Lookup=Skin->GetLookupVertexBuffer();
    if(!Data||!Lookup||!Data->GetWeightData()||!Data->GetVertexDataSize()||uint64(Skin->GetVertexDataSize())>FileCap||Data->GetBoneIndexByteSize()>2||Data->GetBoneWeightByteSize()>2)return false;
    if((!Lookup->GetLookupData()&&Lookup->GetVertexDataSize())||
        (Skin->GetVariableBonesPerVertex()&&(!Lookup->GetLookupData()||Lookup->GetNumVertices()!=43432||uint64(Lookup->GetVertexDataSize())!=uint64(43432)*sizeof(uint32))))return false;
    if(!Skin->GetVariableBonesPerVertex()&&uint64(Data->GetVertexDataSize())!=uint64(43432)*Data->GetConstantInfluencesVertexStride())return false;
    for(uint32 I=0;I<43432;++I)
    {
        uint32 Offset=0,Influences=0;Skin->GetVertexInfluenceOffsetCount(I,Offset,Influences);
        if(Influences>12||uint64(Offset)+uint64(Influences)*Skin->GetBoneIndexAndWeightByteSize()>Data->GetVertexDataSize())return false;
    }
    return true;
}
bool Shape(USkeletalMesh* M)
{
    if(!Loaded(M)||M->IsCompiling()||!M->GetSkeleton()||M->GetSkeleton()->GetPathName()!=SkeletonPath||M->GetRefSkeleton().GetNum()!=62||M->GetMaterials().Num()!=8)return false;
    const auto& Ref=M->GetRefSkeleton();if(Ref.GetBoneName(0)!=FName(LivingTownCafeCurrent61Baked::WrapperBone)||Ref.GetParentIndex(0)!=INDEX_NONE||Ref.GetBoneName(1)!=FName(TEXT("root"))||Ref.GetParentIndex(1)!=0||Ref.FindBoneIndex(TEXT("hand_r"))==INDEX_NONE)return false;
    const auto* R=M->GetResourceForRendering();if(!R||R->LODRenderData.Num()!=1)return false;const auto& L=R->LODRenderData[0];
    if(L.GetNumVertices()!=43432||L.GetTotalFaces()!=72848||L.GetNumTexCoords()!=3||L.RenderSections.Num()!=8||L.StaticVertexBuffers.PositionVertexBuffer.GetVertexData()==nullptr||L.SkinWeightVertexBuffer.GetNumVertices()!=43432||!HasCPUWeightAndLookupData(&L.SkinWeightVertexBuffer))return false;
    const auto& Paths=LivingTownCafeCurrent61Baked::MaterialAssets();for(int32 I=0;I<8;++I){auto* Material=Cast<UMaterial>(M->GetMaterials()[I].MaterialInterface.Get());if(!Loaded(Material)||Material->GetClass()!=UMaterial::StaticClass()||Material->GetPathName()!=Paths[I]||!Material->GetUsageByFlag(MATUSAGE_SkeletalMesh))return false;}
    return M->GetMeshClothingAssets().IsEmpty();
}
// Socket-independent digest covers actual render attributes/indices/skin/sections,
// 62 reference names/parents/TRS, exact material objects/slot metadata. This is
// not a source MeshDescription or full morph-bulk equivalence claim.
bool BodyDigest(USkeletalMesh* M,FString& Result)
{
    if(!Shape(M))return false;TArray<uint8> B;FMemoryWriter W(B);const auto& Ref=M->GetRefSkeleton();int32 Bones=Ref.GetNum();W<<Bones;
    for(int32 I=0;I<Bones;++I){FString Name=Ref.GetBoneName(I).ToString();int32 Parent=Ref.GetParentIndex(I);FTransform T=Ref.GetRefBonePose()[I];W<<Name;W<<Parent;W<<T;}
    const auto& L=M->GetResourceForRendering()->LODRenderData[0];const auto& VB=L.StaticVertexBuffers;const auto& Skin=L.SkinWeightVertexBuffer;uint32 N=L.GetNumVertices(),UVs=L.GetNumTexCoords(),Influences=Skin.GetMaxBoneInfluences();W<<N;W<<UVs;W<<Influences;if(Influences>12)return false;
    for(uint32 I=0;I<N;++I){auto P=VB.PositionVertexBuffer.VertexPosition(I);auto X=VB.StaticMeshVertexBuffer.VertexTangentX(I);auto Y=VB.StaticMeshVertexBuffer.VertexTangentY(I);auto Z=VB.StaticMeshVertexBuffer.VertexTangentZ(I);W<<P;W<<X;W<<Y;W<<Z;for(uint32 U=0;U<UVs;++U){auto UV=VB.StaticMeshVertexBuffer.GetVertexUV(I,U);W<<UV;}if(VB.ColorVertexBuffer.GetNumVertices()){auto C=VB.ColorVertexBuffer.VertexColor(I);W<<C;}for(uint32 J=0;J<Influences;++J){uint32 Bone=Skin.GetBoneIndex(I,J);uint16 Weight=Skin.GetBoneWeight(I,J);W<<Bone;W<<Weight;}}
    const auto* Index=L.MultiSizeIndexContainer.GetIndexBuffer();if(!Index)return false;uint32 Count=Index->Num();W<<Count;for(uint32 I=0;I<Count;++I){uint32 Value=Index->Get(I);W<<Value;}
    for(const auto& S:L.RenderSections){uint16 Material=S.MaterialIndex;uint32 Base=S.BaseIndex,Triangles=S.NumTriangles,Vertex=S.BaseVertexIndex,Vertices=S.NumVertices;W<<Material;W<<Base;W<<Triangles;W<<Vertex;W<<Vertices;TArray<FBoneIndexType> Map=S.BoneMap;W<<Map;}
    for(const auto& S:M->GetMaterials()){FString Path=S.MaterialInterface->GetPathName(),Slot=S.MaterialSlotName.ToString(),Imported=S.ImportedMaterialSlotName.ToString();W<<Path;W<<Slot;W<<Imported;bool Init=S.UVChannelData.bInitialized,Override=S.UVChannelData.bOverrideDensities;W<<Init;W<<Override;for(float Density:S.UVChannelData.LocalUVDensities)W<<Density;}
    W.Close();return uint64(B.Num())<=BodyCap&&LivingTownTiles::HashBytes(B,Result);
}
struct FReferenceState
{
    TArray<FName> Names;TArray<int32> Parents;TArray<FTransform> Poses;
};
FReferenceState Reference(const FReferenceSkeleton& Ref)
{
    FReferenceState S;S.Poses=Ref.GetRefBonePose();
    for(int32 I=0;I<Ref.GetNum();++I){S.Names.Add(Ref.GetBoneName(I));S.Parents.Add(Ref.GetParentIndex(I));}
    return S;
}
bool SameReference(const FReferenceState& A,const FReferenceState& B)
{
    if(A.Names!=B.Names||A.Parents!=B.Parents||A.Poses.Num()!=B.Poses.Num())return false;
    for(int32 I=0;I<A.Poses.Num();++I)
    {
        if(A.Poses[I].GetTranslation()!=B.Poses[I].GetTranslation()||A.Poses[I].GetRotation()!=B.Poses[I].GetRotation()||A.Poses[I].GetScale3D()!=B.Poses[I].GetScale3D())return false;
    }
    return true;
}
struct FMaterialState
{
    UMaterialInterface* Material=nullptr;FName Slot,Imported;FMeshUVChannelInfo UV;
};
TArray<FMaterialState> Materials(const USkeletalMesh* Mesh)
{
    TArray<FMaterialState> S;
    for(const auto& M:Mesh->GetMaterials()){FMaterialState V;V.Material=M.MaterialInterface;V.Slot=M.MaterialSlotName;V.Imported=M.ImportedMaterialSlotName;V.UV=M.UVChannelData;S.Add(V);}
    return S;
}
bool SameMaterials(const TArray<FMaterialState>& A,const TArray<FMaterialState>& B)
{
    if(A.Num()!=B.Num())return false;
    for(int32 I=0;I<A.Num();++I)
    {
        if(A[I].Material!=B[I].Material||A[I].Slot!=B[I].Slot||A[I].Imported!=B[I].Imported||A[I].UV.bInitialized!=B[I].UV.bInitialized||A[I].UV.bOverrideDensities!=B[I].UV.bOverrideDensities)return false;
        for(int32 C=0;C<UE_ARRAY_COUNT(A[I].UV.LocalUVDensities);++C)if(A[I].UV.LocalUVDensities[C]!=B[I].UV.LocalUVDensities[C])return false;
    }
    return true;
}

bool CandidateCachedBounds(const FMeshDescription& D)
{
    if(!D.Vertices().Num()||D.Vertices().GetArraySize()>250000||D.VertexInstances().GetArraySize()>250000||D.Triangles().GetArraySize()>100000||D.Polygons().GetArraySize()>100000||D.Edges().GetArraySize()>300000||D.PolygonGroups().GetArraySize()>32)return false;
    const FSkeletalMeshConstAttributes A(D);
    return A.HasSourceGeometryParts()&&A.GetNumSourceGeometryParts()==7&&A.HasBoneNameAttribute()&&A.HasBoneParentIndexAttribute()&&A.HasBonePoseAttribute()&&A.GetNumBones()>=61&&A.GetNumBones()<=64&&A.GetVertexSkinWeights().IsValid()&&A.GetVertexInstanceUVs().GetNumChannels()<=8&&A.GetMorphTargetNames().Num()<=16&&A.GetSkinWeightProfileNames().Num()==1;
}

bool MotionPolicy(UBlendSpace1D* M,UAnimSequence* Idle,UAnimSequence* Walk,float Speed)
{
    if(!M||M->GetSkeleton()!=Idle->GetSkeleton()||!LivingTownCafeCurrent61Baked::HasUnfilteredUnscaled1DMotionPolicy(M)||M->GetBlendParameter(0).Min!=0||M->GetBlendParameter(0).Max!=Speed||M->GetBlendSamples().Num()!=2)return false;
    for(const auto& S:M->GetBlendSamples())if(!((S.Animation==Idle&&S.SampleValue==FVector::ZeroVector)||(S.Animation==Walk&&S.SampleValue==FVector(Speed,0,0)))||S.RateScale!=1||S.bUseSingleFrameForBlending||S.bMirror)return false;
    for(double F:{0.,.5,1.}){TArray<FBlendSampleData> Samples;int32 Segment=INDEX_NONE;if(!M->GetSamplesFromBlendInput(FVector(Speed*F,0,0),Samples,Segment,true)||Samples.IsEmpty()||Samples.Num()>2)return false;double IW=0,WW=0;for(const auto& S:Samples){if(!FMath::IsFinite(S.TotalWeight)||S.TotalWeight<=0||(S.Animation!=Idle&&S.Animation!=Walk))return false;if(S.Animation==Idle)IW+=S.TotalWeight;else WW+=S.TotalWeight;}if(!FMath::IsNearlyEqual(IW,1-F,.001)||!FMath::IsNearlyEqual(WW,F,.001))return false;}return true;
}
bool SaveNew(UObject* O)
{
    if(Work()!=0)return false;FString File=FPaths::ConvertRelativePathToFull(FPackageName::LongPackageNameToFilename(O->GetOutermost()->GetName(),FPackageName::GetAssetPackageExtension()));if(!NoReparse(File)||IFileManager::Get().FileExists(*File))return false;
    IFileManager::Get().MakeDirectory(*FPaths::GetPath(File),true);O->MarkPackageDirty();FSavePackageArgs Args;Args.TopLevelFlags=RF_Public|RF_Standalone;Args.bSlowTask=false;return UPackage::SavePackage(O->GetOutermost(),O,*File,Args);
}
struct FSession
{
    bool Started=false,Poisoned=false,Finalized=false;TStrongObjectPtr<USkeletalMesh> Candidate;TWeakObjectPtr<USkeletalMesh> Source;TWeakObjectPtr<UAnimSequence> Idle,Walk;TArray<FFileState> OriginalsBefore;FString BodyBefore;FTransform Palm;double Speed=0;
};
FSession Session;
}

FString ULivingTownCurrent61AvatarPreparation::CreateCandidateAvatar(USkeletalMesh* SourceMesh,UAnimSequence* Idle,UAnimSequence* Walk,double Speed,FTransform Palm)
{
    using namespace Current61AvatarCandidate;
    if(!Context()||Session.Started||Work()!=0||!Shape(SourceMesh)||SourceMesh->GetPathName()!=SourcePath||!Loaded(Idle)||!Loaded(Walk)||Idle==Walk||Idle->GetPathName()!=LivingTownCafeCurrent61Baked::IdleAsset||Walk->GetPathName()!=LivingTownCafeCurrent61Baked::WalkAsset||Idle->GetSkeleton()!=SourceMesh->GetSkeleton()||Walk->GetSkeleton()!=SourceMesh->GetSkeleton()||
        Idle->GetNumberOfSampledKeys()!=461||Walk->GetNumberOfSampledKeys()!=71||Idle->RateScale!=1||Walk->RateScale!=1||Idle->IsValidAdditive()||Walk->IsValidAdditive()||Idle->bEnableRootMotion||Walk->bEnableRootMotion||
        double(Idle->GetPlayLength())!=15.333333015441895||double(Walk->GetPlayLength())!=2.3333332538604736||!FMath::IsFinite(Speed)||Speed<60||Speed>500||!Palm.IsValid()||Palm.GetScale3D()!=FVector::OneVector||Palm.GetTranslation().Size()>20||!Fresh(MeshPackage)||!Fresh(MotionPackage)||SourceMesh->FindSocket(FName(LivingTownCafeCurrent61Baked::PalmSocket)))return Refuse(TEXT("exact_saved_inputs_numeric_candidate_or_fresh_destination"));
    TArray<FFileState> Before;FString Body;if(!Originals(Before)||!BodyDigest(SourceMesh,Body))return Refuse(TEXT("source_package_or_body_custody"));
    Session.Started=true;Session.Poisoned=true;Session.OriginalsBefore=Before;Session.BodyBefore=Body;Session.Source=SourceMesh;Session.Idle=Idle;Session.Walk=Walk;Session.Speed=Speed;Session.Palm=Palm;
    auto* Candidate=DuplicateObject<USkeletalMesh>(SourceMesh,CreatePackage(MeshPackage),TEXT("SK_Worker110Current61_BakedAvatar_v001"));Session.Candidate.Reset(Candidate);
    if(!Candidate||Candidate->GetPathName()!=LivingTownCafeCurrent61Baked::MeshAsset||!OriginalCustody(Before))return Refuse(TEXT("duplicate_failed_or_original_custody_changed_partials_retained"));
    Candidate->ClearFlags(RF_Transient);Candidate->SetFlags(RF_Public|RF_Standalone);Session.Poisoned=false;
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),Work()!=0||Candidate->IsCompiling()?TEXT("CREATED_CANDIDATE_PENDING_OUTER_COMPILATION_READINESS"):TEXT("CREATED_CANDIDATE_READY_FOR_FINALIZER"));O->SetStringField(TEXT("candidate_mesh"),Candidate->GetPathName());O->SetNumberField(TEXT("registered_asset_compilations_after"),Work());O->SetBoolField(TEXT("internal_wait_finish_or_post_edit_called"),false);O->SetBoolField(TEXT("candidate_only_no_contact_or_binding_qualification"),true);return Json(O);
}

FString ULivingTownCurrent61AvatarPreparation::FinalizeCandidateAvatar(USkeletalMesh* Candidate)
{
    using namespace Current61AvatarCandidate;
    if(!Context()||!Session.Started||Session.Poisoned||Session.Finalized||!Candidate||Candidate!=Session.Candidate.Get())return Refuse(TEXT("exact_once_owned_candidate_session"));
    if(Work()!=0||Candidate->IsCompiling())return Refuse(TEXT("inflight_outer_readiness_required_no_mutation_or_wait"));
    auto* Source=Session.Source.Get();auto* Idle=Session.Idle.Get();auto* Walk=Session.Walk.Get();FString SourceBody,CopyBody;
    if(!OriginalCustody(Session.OriginalsBefore)||!Shape(Source)||!Shape(Candidate)||!Loaded(Idle)||!Loaded(Walk)||Candidate->GetSkeleton()!=Source->GetSkeleton()||!BodyDigest(Source,SourceBody)||!BodyDigest(Candidate,CopyBody)||SourceBody!=Session.BodyBefore||CopyBody!=SourceBody||!Fresh(MotionPackage)||Candidate->FindSocket(FName(LivingTownCafeCurrent61Baked::PalmSocket)))return Refuse(TEXT("exact_ready_duplicate_body_source_or_fresh_motion"));
    Session.Poisoned=true;
    auto* Socket=NewObject<USkeletalMeshSocket>(Candidate);Socket->SocketName=FName(LivingTownCafeCurrent61Baked::PalmSocket);Socket->BoneName=TEXT("hand_r");Socket->RelativeLocation=Session.Palm.GetTranslation();Socket->RelativeRotation=Session.Palm.Rotator();Socket->RelativeScale=FVector::OneVector;Socket->bForceAlwaysAnimated=true;Candidate->AddSocket(Socket,false);
    auto* Motion=NewObject<UBlendSpace1D>(CreatePackage(MotionPackage),TEXT("BS_Worker110Current61_BakedIdleWalk_v001"),RF_Public|RF_Standalone);Motion->SetSkeleton(Candidate->GetSkeleton());
    auto* Property=FindFProperty<FStructProperty>(UBlendSpace::StaticClass(),TEXT("BlendParameters"));if(!Property||Property->ArrayDim!=3||Property->Struct!=FBlendParameter::StaticStruct())return Refuse(TEXT("blend_parameter_property_partial_candidates_retained"));
    auto* Axis=Property->ContainerPtrToValuePtr<FBlendParameter>(Motion,0);Axis->DisplayName=TEXT("Speed cm/s");Axis->Min=0;Axis->Max=float(Session.Speed);Axis->GridNum=4;Axis->bSnapToGrid=false;Axis->bWrapInput=false;Motion->bScaleAnimation=false;Motion->TargetWeightInterpolationSpeedPerSec=0;Motion->InterpolationParam[0].InterpolationTime=0;
    Motion->AddSample(Idle,FVector::ZeroVector);Motion->AddSample(Walk,FVector(float(Session.Speed),0,0));Motion->ValidateSampleData();Motion->ResampleData();
    FString After;if(Work()!=0||Candidate->IsCompiling()||!BodyDigest(Candidate,After)||After!=SourceBody||Candidate->FindSocket(FName(LivingTownCafeCurrent61Baked::PalmSocket))!=Socket||Socket->GetOuter()!=Candidate||!Socket->GetSocketLocalTransform().Equals(Session.Palm,1e-9)||!MotionPolicy(Motion,Idle,Walk,float(Session.Speed))||!OriginalCustody(Session.OriginalsBefore))return Refuse(TEXT("candidate_socket_body_sampler_or_custody_partials_retained"));
    if(!SaveNew(Candidate)||!SaveNew(Motion)||Work()!=0||!OriginalCustody(Session.OriginalsBefore))return Refuse(TEXT("save_or_custody_failed_partial_candidates_retained"));
    FFileState MeshFile,MotionFile;if(!FileState(MeshPackage,MeshFile)||!FileState(MotionPackage,MotionFile))return Refuse(TEXT("saved_candidate_package_readback_failed"));
    Session.Finalized=true;Session.Poisoned=false;auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("SAVED_CANDIDATE_AVATAR_AND_MOTION_COLD_CONTACT_AND_RUNTIME_PENDING"));O->SetStringField(TEXT("candidate_mesh"),Candidate->GetPathName());O->SetStringField(TEXT("candidate_mesh_sha256"),MeshFile.Sha);O->SetStringField(TEXT("candidate_motion"),Motion->GetPathName());O->SetStringField(TEXT("candidate_motion_sha256"),MotionFile.Sha);O->SetStringField(TEXT("render_reference_skin_material_SHA256"),After);O->SetNumberField(TEXT("candidate_speed_declared_double_cm_s"),Session.Speed);O->SetNumberField(TEXT("candidate_speed_native_float_cm_s"),float(Session.Speed));O->SetObjectField(TEXT("candidate_palm_local"),TRS(Socket->GetSocketLocalTransform()));O->SetBoolField(TEXT("all24_original_package_bytes_time_loaded_identity_dirty_unchanged"),true);O->SetBoolField(TEXT("full_source_MeshDescription_morph_skin_contact_or_runtime_qualified"),false);return Json(O);
}

FString ULivingTownCurrent61AvatarPreparation::ReadCandidatePose(USkeletalMeshComponent* C,const TArray<int32>& Vertices,const FString& ExpectedHash)
{
    using namespace Current61AvatarCandidate;
    // Capture scalar readiness once; the same snapshot decides the unchanged guard.
    // No component/owner/world dereference occurs before the context check.
    const bool GameThread=IsInGameThread(),Editor=GIsEditor,Commandlet=IsRunningCommandlet();
    const bool AllowedContext=GameThread&&Editor&&!Commandlet;
    auto Readiness=MakeShared<FJsonObject>();Readiness->SetStringField(TEXT("status"),TEXT("REFUSED"));Readiness->SetStringField(TEXT("reason"),TEXT("owned_editor_component_idle_parallel_state_or_selected_vertex_bound"));
    Readiness->SetBoolField(TEXT("game_thread"),GameThread);Readiness->SetBoolField(TEXT("GIsEditor"),Editor);Readiness->SetBoolField(TEXT("running_commandlet"),Commandlet);Readiness->SetBoolField(TEXT("context_allowed"),AllowedContext);
    Readiness->SetBoolField(TEXT("scalar_snapshot_used_by_guard"),true);Readiness->SetBoolField(TEXT("pose_proxy_matrix_refresh_wait_or_mutation_called"),false);
    if(!AllowedContext){Readiness->SetStringField(TEXT("first_failed_predicate"),TEXT("context_allowed"));Readiness->SetStringField(TEXT("component_observation"),TEXT("UNOBSERVED_OUTSIDE_CONTEXT_NO_DEREFERENCE"));return Json(Readiness);}
    const int32 Remaining=Work();const bool Present=C!=nullptr;
    // Reflection supplies live UObject arguments. IsValid guards diagnostic getters
    // from invalid/dead objects; they are refused without dereferencing them.
    const bool Valid=IsValid(C);const bool ComponentLoaded=Valid&&Loaded(C);
    Readiness->SetNumberField(TEXT("registered_asset_compilations"),Remaining);Readiness->SetBoolField(TEXT("component_present"),Present);Readiness->SetBoolField(TEXT("component_valid"),Valid);Readiness->SetBoolField(TEXT("component_loaded_non_template"),ComponentLoaded);
    if(!ComponentLoaded)
    {
        if(Valid){Readiness->SetBoolField(TEXT("component_is_template"),C->IsTemplate());Readiness->SetNumberField(TEXT("component_load_or_destruction_flags"),uint32(C->GetFlags()&(RF_NeedLoad|RF_NeedPostLoad|RF_BeginDestroyed|RF_FinishDestroyed)));}
        else Readiness->SetStringField(TEXT("component_observation"),TEXT("UNOBSERVED_INVALID_COMPONENT_NO_DEREFERENCE"));
        Readiness->SetStringField(TEXT("first_failed_predicate"),Remaining!=0?TEXT("registered_asset_compilations_zero"):TEXT("component_loaded_non_template"));return Json(Readiness);
    }
    UWorld* World=C->GetWorld();AActor* Owner=C->GetOwner();
    const bool WorldPresent=World!=nullptr,EditorWorld=WorldPresent&&World->IsEditorWorld(),Registered=C->IsRegistered(),OwnerPresent=Owner!=nullptr;
    const bool OwnerTransient=OwnerPresent&&Owner->HasAnyFlags(RF_Transient),Parallel=C->IsRunningParallelEvaluation(),Leader=C->LeaderPoseComponent.IsValid(),RefOverride=C->GetRefPoseOverride().IsValid(),Physics=C->IsSimulatingPhysics();
    const bool HashValid=Hash(ExpectedHash);const int32 VertexCount=Vertices.Num();
    Readiness->SetStringField(TEXT("component"),C->GetPathName());Readiness->SetBoolField(TEXT("component_is_template"),C->IsTemplate());Readiness->SetNumberField(TEXT("component_load_or_destruction_flags"),uint32(C->GetFlags()&(RF_NeedLoad|RF_NeedPostLoad|RF_BeginDestroyed|RF_FinishDestroyed)));
    Readiness->SetBoolField(TEXT("world_present"),WorldPresent);Readiness->SetBoolField(TEXT("world_is_editor_world"),EditorWorld);if(WorldPresent){Readiness->SetStringField(TEXT("world"),World->GetPathName());Readiness->SetNumberField(TEXT("world_type"),int32(World->WorldType));}
    Readiness->SetBoolField(TEXT("component_registered"),Registered);Readiness->SetBoolField(TEXT("owner_present"),OwnerPresent);Readiness->SetBoolField(TEXT("owner_RF_Transient"),OwnerTransient);if(OwnerPresent){Readiness->SetStringField(TEXT("owner"),Owner->GetPathName());Readiness->SetNumberField(TEXT("owner_flags"),uint32(Owner->GetFlags()));}
    Readiness->SetBoolField(TEXT("parallel_animation_evaluation_active"),Parallel);Readiness->SetBoolField(TEXT("leader_pose_active"),Leader);Readiness->SetBoolField(TEXT("reference_pose_override_active"),RefOverride);Readiness->SetBoolField(TEXT("physics_simulating"),Physics);Readiness->SetBoolField(TEXT("supplied_saved_hash_valid"),HashValid);Readiness->SetNumberField(TEXT("selected_vertex_count"),VertexCount);
    const bool Ready=AllowedContext&&Remaining==0&&ComponentLoaded&&WorldPresent&&EditorWorld&&Registered&&OwnerPresent&&OwnerTransient&&!Parallel&&!Leader&&!RefOverride&&!Physics&&HashValid&&VertexCount>0&&VertexCount<=2048;
    if(!Ready)
    {
        TArray<TSharedPtr<FJsonValue>> Failed;
        auto Add=[&Failed](bool Pass,const TCHAR* Name){if(!Pass)Failed.Add(MakeShared<FJsonValueString>(Name));};
        Add(Remaining==0,TEXT("registered_asset_compilations_zero"));Add(ComponentLoaded,TEXT("component_loaded_non_template"));Add(WorldPresent,TEXT("world_present"));Add(EditorWorld,TEXT("world_is_editor_world"));Add(Registered,TEXT("component_registered"));Add(OwnerPresent,TEXT("owner_present"));Add(OwnerTransient,TEXT("owner_RF_Transient"));Add(!Parallel,TEXT("parallel_animation_evaluation_idle"));Add(!Leader,TEXT("no_leader_pose"));Add(!RefOverride,TEXT("no_reference_pose_override"));Add(!Physics,TEXT("no_physics_simulation"));Add(HashValid,TEXT("supplied_saved_hash_valid"));Add(VertexCount>0,TEXT("selected_vertex_nonempty"));Add(VertexCount<=2048,TEXT("selected_vertex_bound2048"));
        Readiness->SetArrayField(TEXT("failed_predicates"),Failed);Readiness->SetStringField(TEXT("first_failed_predicate"),Failed[0]->AsString());return Json(Readiness);
    }
    auto* M=C->GetSkeletalMeshAsset();auto* A=C->GetSingleNodeInstance();if(!Shape(M)||M->GetPathName()!=LivingTownCafeCurrent61Baked::MeshAsset||!A||A->GetClass()!=UAnimSingleNodeInstance::StaticClass()||C->GetAnimationMode()!=EAnimationMode::AnimationSingleNode||C->GetNumBones()!=62||C->GetComponentSpaceTransforms().Num()!=62)return Refuse(TEXT("saved_candidate_plain_current62_state"));
    auto* Asset=A->GetCurrentAsset();if(!Asset||(Asset->GetPathName()!=LivingTownCafeCurrent61Baked::IdleAsset&&Asset->GetPathName()!=LivingTownCafeCurrent61Baked::WalkAsset&&Asset->GetPathName()!=LivingTownCafeCurrent61Baked::MotionAsset))return Refuse(TEXT("exact_current_candidate_animation"));
    // ExternalMorphSets and ExternalMorphWeightData are outer arrays, one entry
    // per LOD. A registered ordinary component has an empty map at each LOD;
    // outer-array nonemptiness is not external morph registration.
    constexpr int32 ExpectedMorphLODs=1,MorphCountCap=16,MorphLODCountCap=8;
    const int32 ComponentLODs=C->GetNumLODs(),SetLODs=C->ExternalMorphSets.Num(),WeightLODs=C->ExternalMorphWeightData.Num();
    const int32 MorphWeightCount=C->MorphTargetWeights.Num(),ActiveMorphCount=C->ActiveMorphTargets.Num();
    const auto& MorphCurves=C->GetMorphTargetCurves();const int32 MorphCurveCount=MorphCurves.Num();
    const bool LODCountsBounded=ComponentLODs>0&&ComponentLODs<=MorphLODCountCap&&SetLODs<=MorphLODCountCap&&WeightLODs<=MorphLODCountCap;
    const bool LODLayout=ComponentLODs==ExpectedMorphLODs&&SetLODs==ExpectedMorphLODs&&WeightLODs==ExpectedMorphLODs;
    const bool WeightsBounded=MorphWeightCount<=MorphCountCap,CurvesBounded=MorphCurveCount<=MorphCountCap;
    bool MorphWeightsFinite=true,MorphWeightsZero=true,CurvesFinite=true,CurvesZero=true,ExternalSetMapsEmpty=true,ExternalWeightMapsEmpty=true,ExternalActiveCountsZero=true;
    TArray<TSharedPtr<FJsonValue>> SetRows,WeightRows;
    if(WeightsBounded)for(float W:C->MorphTargetWeights){MorphWeightsFinite&=FMath::IsFinite(W);MorphWeightsZero&=W==0.f;}
    if(CurvesBounded)for(const auto& Pair:MorphCurves){CurvesFinite&=FMath::IsFinite(Pair.Value);CurvesZero&=Pair.Value==0.f;}
    for(int32 I=0;I<FMath::Min(SetLODs,MorphLODCountCap);++I)
    {
        const int32 Count=C->ExternalMorphSets[I].Num();ExternalSetMapsEmpty&=Count==0;auto Row=MakeShared<FJsonObject>();Row->SetNumberField(TEXT("lod"),I);Row->SetNumberField(TEXT("registered_external_set_entries"),Count);SetRows.Add(MakeShared<FJsonValueObject>(Row));
    }
    for(int32 I=0;I<FMath::Min(WeightLODs,MorphLODCountCap);++I)
    {
        const auto& Data=C->ExternalMorphWeightData[I];const int32 Count=Data.MorphSets.Num(),Active=Data.NumActiveMorphTargets;ExternalWeightMapsEmpty&=Count==0;ExternalActiveCountsZero&=Active==0;auto Row=MakeShared<FJsonObject>();Row->SetNumberField(TEXT("lod"),I);Row->SetNumberField(TEXT("external_weight_set_entries"),Count);Row->SetNumberField(TEXT("external_active_morph_count"),Active);WeightRows.Add(MakeShared<FJsonValueObject>(Row));
    }
    auto MorphDomain=MakeShared<FJsonObject>();MorphDomain->SetStringField(TEXT("status"),TEXT("REFUSED"));MorphDomain->SetStringField(TEXT("reason"),TEXT("morph_deformer_not_linear_skin_domain"));
    MorphDomain->SetBoolField(TEXT("morph_domain_snapshot_used_by_guard"),true);MorphDomain->SetBoolField(TEXT("pose_proxy_matrix_refresh_wait_or_mutation_called"),false);
    MorphDomain->SetNumberField(TEXT("expected_lods"),ExpectedMorphLODs);MorphDomain->SetNumberField(TEXT("component_lods"),ComponentLODs);MorphDomain->SetNumberField(TEXT("external_set_array_lods"),SetLODs);MorphDomain->SetNumberField(TEXT("external_weight_array_lods"),WeightLODs);MorphDomain->SetBoolField(TEXT("lod_counts_bounded"),LODCountsBounded);MorphDomain->SetBoolField(TEXT("exact_expected_lod_layout"),LODLayout);
    MorphDomain->SetNumberField(TEXT("morph_weight_count"),MorphWeightCount);MorphDomain->SetBoolField(TEXT("morph_weights_bounded"),WeightsBounded);MorphDomain->SetBoolField(TEXT("morph_weights_all_finite"),WeightsBounded&&MorphWeightsFinite);MorphDomain->SetBoolField(TEXT("morph_weights_all_exact_zero"),WeightsBounded&&MorphWeightsZero);
    MorphDomain->SetNumberField(TEXT("active_morph_registration_count"),ActiveMorphCount);MorphDomain->SetBoolField(TEXT("active_morph_registrations_empty"),ActiveMorphCount==0);
    MorphDomain->SetNumberField(TEXT("morph_curve_count"),MorphCurveCount);MorphDomain->SetBoolField(TEXT("morph_curves_bounded"),CurvesBounded);MorphDomain->SetBoolField(TEXT("morph_curves_all_finite"),CurvesBounded&&CurvesFinite);MorphDomain->SetBoolField(TEXT("morph_curves_all_exact_zero"),CurvesBounded&&CurvesZero);
    MorphDomain->SetArrayField(TEXT("external_set_maps_by_lod"),SetRows);MorphDomain->SetArrayField(TEXT("external_weight_maps_by_lod"),WeightRows);MorphDomain->SetBoolField(TEXT("external_set_maps_all_empty"),ExternalSetMapsEmpty&&SetLODs<=MorphLODCountCap);MorphDomain->SetBoolField(TEXT("external_weight_maps_all_empty"),ExternalWeightMapsEmpty&&WeightLODs<=MorphLODCountCap);MorphDomain->SetBoolField(TEXT("external_active_counts_all_zero"),ExternalActiveCountsZero&&WeightLODs<=MorphLODCountCap);
    TArray<TSharedPtr<FJsonValue>> MorphFailed;auto AddMorphFailure=[&MorphFailed](bool Pass,const TCHAR* Name){if(!Pass)MorphFailed.Add(MakeShared<FJsonValueString>(Name));};
    AddMorphFailure(LODCountsBounded,TEXT("lod_counts_bounded"));AddMorphFailure(LODLayout,TEXT("exact_expected_lod_layout"));AddMorphFailure(WeightsBounded,TEXT("morph_weights_bounded"));AddMorphFailure(WeightsBounded&&MorphWeightsFinite,TEXT("morph_weights_all_finite"));AddMorphFailure(WeightsBounded&&MorphWeightsZero,TEXT("morph_weights_all_exact_zero"));AddMorphFailure(ActiveMorphCount==0,TEXT("active_morph_registrations_empty"));AddMorphFailure(CurvesBounded,TEXT("morph_curves_bounded"));AddMorphFailure(CurvesBounded&&CurvesFinite,TEXT("morph_curves_all_finite"));AddMorphFailure(CurvesBounded&&CurvesZero,TEXT("morph_curves_all_exact_zero"));AddMorphFailure(ExternalSetMapsEmpty&&SetLODs<=MorphLODCountCap,TEXT("external_set_maps_all_empty"));AddMorphFailure(ExternalWeightMapsEmpty&&WeightLODs<=MorphLODCountCap,TEXT("external_weight_maps_all_empty"));AddMorphFailure(ExternalActiveCountsZero&&WeightLODs<=MorphLODCountCap,TEXT("external_active_counts_all_zero"));
    MorphDomain->SetArrayField(TEXT("failed_predicates"),MorphFailed);if(!MorphFailed.IsEmpty()){MorphDomain->SetStringField(TEXT("first_failed_predicate"),MorphFailed[0]->AsString());return Json(MorphDomain);}
    MorphDomain->SetStringField(TEXT("status"),TEXT("EMPTY_MORPH_DEFORMATION_DOMAIN_OBSERVED"));MorphDomain->RemoveField(TEXT("reason"));
    TArray<FFileState> OriginalsBefore;FFileState CandidateBefore;if(!Originals(OriginalsBefore)||!FileState(MeshPackage,CandidateBefore)||CandidateBefore.Sha!=ExpectedHash)return Refuse(TEXT("saved_source_or_candidate_package_custody"));
    const auto& L=M->GetResourceForRendering()->LODRenderData[0];auto* Skin=C->GetSkinWeightBuffer(0);if(!Skin||Skin!=&L.SkinWeightVertexBuffer||Skin->GetMaxBoneInfluences()>12||!HasCPUWeightAndLookupData(Skin))return Refuse(TEXT("exact_original_LOD0_CPU_skin_buffer"));
    TSet<int32> Seen;for(int32 I:Vertices){if(I<0||I>=43432||Seen.Contains(I))return Refuse(TEXT("unique_LOD0_vertex_indices_required"));Seen.Add(I);}
    const auto BonesBefore=C->GetComponentSpaceTransforms();const FTransform WorldBefore=C->GetComponentTransform();const uint32 Revision=C->GetBoneTransformRevisionNumber();const float Time=A->GetCurrentTime(),Rate=A->GetPlayRate();const bool Playing=A->IsPlaying(),Looping=A->IsLooping();const FVector Filter=A->GetFilterLastOutput();
    if(!FMath::IsFinite(Time)||!FMath::IsFinite(Rate)||Filter.ContainsNaN()||!WorldBefore.IsValid())return Refuse(TEXT("finite_current_animation_state"));TArray<FMatrix44f> Matrices;C->GetCurrentRefToLocalMatrices(Matrices,0);if(Matrices.Num()!=62)return Refuse(TEXT("actual_current_ref_to_local_palette"));
    TArray<TSharedPtr<FJsonValue>> Points,Bones;
    for(int32 I=0;I<62;++I){if(!BonesBefore[I].IsValid())return Refuse(TEXT("finite_current_bone_transform"));auto O=TRS(BonesBefore[I]);O->SetNumberField(TEXT("bone_index"),I);O->SetStringField(TEXT("displayed_name"),C->GetBoneName(I).ToString());Bones.Add(MakeShared<FJsonValueObject>(O));}
    for(int32 I:Vertices)
    {
        int32 SectionIndex=INDEX_NONE,Local=INDEX_NONE;L.GetSectionFromVertexIndex(I,SectionIndex,Local);if(!L.RenderSections.IsValidIndex(SectionIndex))return Refuse(TEXT("selected_vertex_section"));const auto& S=L.RenderSections[SectionIndex];
        for(uint32 J=0;J<Skin->GetMaxBoneInfluences();++J){const int32 Bone=Skin->GetBoneIndex(I,J);if(!S.BoneMap.IsValidIndex(Bone)||S.BoneMap[Bone]>=62)return Refuse(TEXT("selected_vertex_bone_palette"));}
        const FVector P(USkinnedMeshComponent::GetSkinnedVertexPosition(C,I,L,*Skin,Matrices));if(P.ContainsNaN())return Refuse(TEXT("finite_actual_selected_CPU_skin"));auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("render_vertex_index"),I);O->SetArrayField(TEXT("component_cm"),V(P));O->SetArrayField(TEXT("world_cm"),V(WorldBefore.TransformPosition(P)));Points.Add(MakeShared<FJsonValueObject>(O));
    }
    FFileState CandidateAfter;bool BonesSame=C->GetComponentSpaceTransforms().Num()==BonesBefore.Num();for(int32 I=0;BonesSame&&I<62;++I){const auto& T=C->GetComponentSpaceTransforms()[I];BonesSame=T.GetTranslation()==BonesBefore[I].GetTranslation()&&T.GetRotation()==BonesBefore[I].GetRotation()&&T.GetScale3D()==BonesBefore[I].GetScale3D();}
    if(Work()!=0||C->IsRunningParallelEvaluation()||!BonesSame||C->GetBoneTransformRevisionNumber()!=Revision||A->GetCurrentAsset()!=Asset||A->GetCurrentTime()!=Time||A->GetPlayRate()!=Rate||A->IsPlaying()!=Playing||A->IsLooping()!=Looping||C->GetComponentTransform().GetTranslation()!=WorldBefore.GetTranslation()||C->GetComponentTransform().GetRotation()!=WorldBefore.GetRotation()||C->GetComponentTransform().GetScale3D()!=WorldBefore.GetScale3D()||!FileState(MeshPackage,CandidateAfter)||!SameFile(CandidateBefore,CandidateAfter)||!OriginalCustody(OriginalsBefore))return Refuse(TEXT("current_state_or_saved_package_changed_readonly_refused"));
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),TEXT("READ_ONLY_CURRENT61_CANDIDATE_CURRENT_LINEAR_SKIN_SELECTED_VERTICES"));O->SetStringField(TEXT("mesh"),M->GetPathName());O->SetStringField(TEXT("saved_candidate_sha256"),CandidateBefore.Sha);O->SetStringField(TEXT("current_animation"),Asset->GetPathName());O->SetNumberField(TEXT("current_single_node_proxy_time_raw_seconds"),Time);O->SetNumberField(TEXT("play_rate"),Rate);O->SetBoolField(TEXT("playing"),Playing);O->SetBoolField(TEXT("looping"),Looping);O->SetArrayField(TEXT("filter_last_output"),V(Filter));O->SetNumberField(TEXT("bone_revision"),Revision);O->SetNumberField(TEXT("world_time_seconds"),C->GetWorld()->GetTimeSeconds());O->SetObjectField(TEXT("component_to_world"),TRS(WorldBefore));O->SetArrayField(TEXT("actual62_current_component_bones"),Bones);O->SetArrayField(TEXT("selected_linear_skin_positions"),Points);O->SetBoolField(TEXT("all_source_and_saved_candidate_package_custody_unchanged"),true);O->SetBoolField(TEXT("Tick_Refresh_SetPosition_Complete_Wait_Finish_called"),false);O->SetStringField(TEXT("domain"),TEXT("stock_CPU_linear_blend_current_component_pose_no_morph_no_cloth_not_GPU"));O->SetBoolField(TEXT("single_snapshot_proves_natural_motion_progress_or_contact"),false);O->SetObjectField(TEXT("morph_domain_snapshot"),MorphDomain);O->SetStringField(TEXT("installed_UE_cached_overload_semantics"),TEXT("GetSkinnedVertexPosition supplied-matrices overload currently instantiates GetTyped<false>; reads unchanged current component transforms rather than the supplied cache"));return Json(O);
}

FString ULivingTownCurrent61AvatarPreparation::CacheCandidateMeshDescription(USkeletalMesh* Mesh,const FString& ExpectedHash)
{
    using namespace Current61AvatarCandidate;
    if(!Context()||!Hash(ExpectedHash)||!Loaded(Mesh)||Mesh->GetClass()!=USkeletalMesh::StaticClass()||Mesh->GetPathName()!=LivingTownCafeCurrent61Baked::MeshAsset||FindObject<USkeletalMesh>(nullptr,LivingTownCafeCurrent61Baked::MeshAsset)!=Mesh)return Refuse(TEXT("exact_already_loaded_saved_candidate_only_no_load"));
    const int32 RemainingBefore=Work();if(RemainingBefore!=0||Mesh->IsCompiling())return Refuse(TEXT("all_registered_asset_compilations_must_be_zero_no_wait"));
    if(!Shape(Mesh)||Mesh->GetLODNum()!=1||Mesh->GetNumSourceModels()!=1)return Refuse(TEXT("exact_candidate_LOD0_bounds"));
    const auto* Imported=Mesh->GetImportedModel();if(!Imported||Imported->LODModels.Num()!=1||!Imported->LODModels[0].NumVertices||Imported->LODModels[0].NumVertices>250000||Imported->LODModels[0].IndexBuffer.Num()>300000)return Refuse(TEXT("bounded_original_imported_LOD0"));
    TArray<FFileState> OriginalBefore;FFileState CandidateBefore;FString DigestBefore;
    if(!Originals(OriginalBefore)||!FileState(MeshPackage,CandidateBefore)||CandidateBefore.Sha!=ExpectedHash||!BodyDigest(Mesh,DigestBefore))return Refuse(TEXT("actual_saved_clean_candidate_hash_and_all24_original_packages"));
    const auto MeshRef=Reference(Mesh->GetRefSkeleton());const auto MaterialBefore=Materials(Mesh);auto* Skeleton=Mesh->GetSkeleton();if(!Loaded(Skeleton))return Refuse(TEXT("loaded_exact_shared_skeleton"));const auto SkeletonRef=Reference(Skeleton->GetReferenceSkeleton());
    USkeletalMesh* SourcePbr=FindObject<USkeletalMesh>(nullptr,SourcePath);USkeletalMesh* OriginalBody=FindObject<USkeletalMesh>(nullptr,TEXT("/Game/LivingTown_UEPilot/Worker110Current61REST_v001/BakedDefault_v001/SK_Worker110Current61_BakedREST_v001.SK_Worker110Current61_BakedREST_v001"));
    if(!Loaded(SourcePbr)||!Loaded(OriginalBody)||SourcePbr->IsCompiling()||OriginalBody->IsCompiling()||SourcePbr->GetSkeleton()!=Skeleton||OriginalBody->GetSkeleton()!=Skeleton)return Refuse(TEXT("already_loaded_two_original_body_references_required"));
    const auto PbrRef=Reference(SourcePbr->GetRefSkeleton()),OriginalRef=Reference(OriginalBody->GetRefSkeleton());const auto PbrMaterials=Materials(SourcePbr),OriginalMaterials=Materials(OriginalBody);
    const FSkeletalMeshSourceModel& Source=Mesh->GetSourceModel(0);if(!Source.IsInitialized())return Refuse(TEXT("initialized_persisted_candidate_source_model"));
    const auto* Property=FindFProperty<FObjectPropertyBase>(FSkeletalMeshSourceModel::StaticStruct(),TEXT("MeshDescriptionBulkData"));auto* Bulk=Property?Cast<USkeletalMeshDescriptionBulkData>(Property->GetObjectPropertyValue_InContainer(&Source)):nullptr;
    if(!Bulk||!Bulk->IsBulkDataValid())return Refuse(TEXT("candidate_saved_source_bulk_required"));const int64 BulkBytes=Bulk->GetBulkData().GetBulkDataSize();if(BulkBytes<=0||uint64(BulkBytes)>(96ull<<20))return Refuse(TEXT("candidate_saved_bulk_96MiB"));const FString BulkId=Bulk->GetBulkData().GetVersionedIdString();
    const bool CachedBefore=Bulk->HasCachedMeshDescription();bool Created=false,LoadedCache=false;FString Failure;
    if(!CachedBefore)
    {
        const auto* Preallocated=FindFProperty<FObjectPropertyBase>(UMeshDescriptionBaseBulkData::StaticClass(),TEXT("PreallocatedMeshDescription"));const bool HasTemplate=Preallocated&&Cast<UMeshDescriptionBase>(Preallocated->GetObjectPropertyValue_InContainer(Bulk));
        if(HasTemplate)Created=Bulk->CreateMeshDescription()!=nullptr;
        if(Created)LoadedCache=Bulk->CacheMeshDescription();
        if(!Created||!LoadedCache)Failure=TEXT("explicit_transient_wrapper_or_saved_bulk_cache_failed_stop");
    }
    const bool CachedAfter=Bulk->HasCachedMeshDescription();const UMeshDescriptionBase* Wrapper=Bulk->GetMeshDescription();const bool Bounds=CachedAfter&&Wrapper&&CandidateCachedBounds(Wrapper->GetMeshDescription());
    const int32 RemainingAfter=Work();const bool NoInflight=RemainingAfter==0&&!Mesh->IsCompiling()&&!SourcePbr->IsCompiling()&&!OriginalBody->IsCompiling();
    FFileState CandidateAfter;FString DigestAfter;const bool PackageCustody=FileState(MeshPackage,CandidateAfter)&&SameFile(CandidateBefore,CandidateAfter)&&OriginalCustody(OriginalBefore);
    const bool ReferenceCustody=NoInflight&&Mesh->GetSkeleton()==Skeleton&&SourcePbr->GetSkeleton()==Skeleton&&OriginalBody->GetSkeleton()==Skeleton&&SameReference(MeshRef,Reference(Mesh->GetRefSkeleton()))&&SameReference(SkeletonRef,Reference(Skeleton->GetReferenceSkeleton()))&&SameReference(PbrRef,Reference(SourcePbr->GetRefSkeleton()))&&SameReference(OriginalRef,Reference(OriginalBody->GetRefSkeleton()));
    const bool MaterialCustody=NoInflight&&SameMaterials(MaterialBefore,Materials(Mesh))&&SameMaterials(PbrMaterials,Materials(SourcePbr))&&SameMaterials(OriginalMaterials,Materials(OriginalBody));
    const bool BodyCustody=NoInflight&&BodyDigest(Mesh,DigestAfter)&&DigestBefore==DigestAfter;const bool BulkCustody=Bulk->IsBulkDataValid()&&Bulk->GetBulkData().GetBulkDataSize()==BulkBytes&&Bulk->GetBulkData().GetVersionedIdString()==BulkId;
    const bool Good=Failure.IsEmpty()&&Bounds&&NoInflight&&PackageCustody&&ReferenceCustody&&MaterialCustody&&BodyCustody&&BulkCustody;
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("status"),Good?TEXT("CACHED_SAVED_CURRENT61_CANDIDATE_SOURCE_DESCRIPTION_ONLY"):TEXT("HOLD_CANDIDATE_CACHE_FAILED_STOP"));O->SetStringField(TEXT("reason"),Failure);O->SetStringField(TEXT("mesh"),Mesh->GetPathName());O->SetStringField(TEXT("saved_candidate_sha256"),CandidateBefore.Sha);O->SetBoolField(TEXT("cached_before"),CachedBefore);O->SetBoolField(TEXT("transient_wrapper_created"),Created);O->SetBoolField(TEXT("saved_bulk_loaded_into_transient_cache"),LoadedCache);O->SetBoolField(TEXT("cached_after"),CachedAfter);O->SetNumberField(TEXT("saved_bulk_bytes"),double(BulkBytes));O->SetStringField(TEXT("saved_bulk_versioned_id"),BulkId);O->SetBoolField(TEXT("saved_bulk_unchanged"),BulkCustody);O->SetBoolField(TEXT("cached_parent_domain_bounds"),Bounds);O->SetNumberField(TEXT("registered_asset_compilations_before"),RemainingBefore);O->SetNumberField(TEXT("registered_asset_compilations_after"),RemainingAfter);O->SetStringField(TEXT("compilation_guard_scope"),TEXT("all_registered_asset_managers_including_AnimSequence_not_per_asset"));O->SetBoolField(TEXT("candidate_and_all24_original_package_bytes_time_loaded_identity_dirty_unchanged"),PackageCustody);O->SetBoolField(TEXT("candidate_and_three_original_reference_domains_unchanged"),ReferenceCustody);O->SetBoolField(TEXT("candidate_and_two_original_material_domains_unchanged"),MaterialCustody);O->SetBoolField(TEXT("candidate_render_reference_skin_material_digest_unchanged"),BodyCustody);O->SetBoolField(TEXT("source_model_getter_bone_update_commit_build_save_finish_wait_or_reimport_called"),false);O->SetBoolField(TEXT("full_raw_source_parity_skin_contact_or_runtime_qualified"),false);return Json(O);
}
