#include "LivingTownWestwoodMaterialLibrary.h"
#include "Materials/Material.h"
#include "MaterialDomain.h"
#include "Materials/MaterialExpressionCustom.h"
#include "Materials/MaterialAttributeDefinitionMap.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformMisc.h"
#include "UObject/Package.h"
#include "UObject/UnrealType.h"
#include "UObject/SoftObjectPtr.h"
#include "Shader/ShaderTypes.h"
#if PLATFORM_WINDOWS
#include "Windows/WindowsHWrapper.h"
#endif

namespace
{
constexpr const TCHAR* SourcePath=TEXT("/Game/LivingTown_UEPilot/TownSlice_v003/Definitions/Main/M_SRC_0010.M_SRC_0010");
constexpr const TCHAR* DerivedPath=TEXT("/Game/LivingTown_UEPilot/Westwood_v001/M_Westwood_v001.M_Westwood_v001");
constexpr const TCHAR* AdapterDescription=TEXT("WESTWOOD_NATIVE_ADAPTER_V001");
const EMaterialProperty Properties[4]={MP_BaseColor,MP_Roughness,MP_Metallic,MP_Normal};
const TCHAR* PropertyNames[4]={TEXT("BaseColor"),TEXT("Roughness"),TEXT("Metallic"),TEXT("Normal")};
const int32 OutputIndices[4]={0,2,3,1};

FString Json(const TSharedRef<FJsonObject>& Object)
{
    FString Text;auto Writer=TJsonWriterFactory<TCHAR,TCondensedJsonPrintPolicy<TCHAR>>::Create(&Text);
    return FJsonSerializer::Serialize(Object,Writer)?Text:TEXT("{\"status\":\"REFUSED\",\"error\":\"json_serialization\"}");
}
FString Refuse(const FString& Error)
{
    auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("schema"),TEXT("living_town.westwood_material_snapshot.v1"));
    O->SetStringField(TEXT("status"),TEXT("REFUSED"));O->SetStringField(TEXT("error"),Error);return Json(O);
}
bool Allowed(UMaterial* M)
{
    return IsInGameThread()&&GIsEditor&&IsValid(M)&&M->GetOutermost()&&!M->GetOutermost()->HasAnyPackageFlags(PKG_PlayInEditor)&&
        (M->GetPathName()==SourcePath||M->GetPathName()==DerivedPath)&&M->GetEditorOnlyData();
}
bool NoReparseAncestors(const FString& Absolute)
{
#if PLATFORM_WINDOWS
    const FString Native=Absolute.Replace(TEXT("/"),TEXT("\\"));
    if(Native.Len()<3||Native[1]!=':'||Native[2]!='\\')return false;
    auto Check=[](const FString& P){const DWORD A=GetFileAttributesW(*P);return A!=INVALID_FILE_ATTRIBUTES&&!(A&FILE_ATTRIBUTE_REPARSE_POINT);};
    FString Prefix=Native.Left(3);if(!Check(Prefix))return false;
    TArray<FString> Parts;Native.Mid(3).ParseIntoArray(Parts,TEXT("\\"),true);
    for(const FString& P:Parts){if(P==TEXT(".")||P==TEXT(".."))return false;Prefix=FPaths::Combine(Prefix,P);if(!Check(Prefix))return false;}
    return true;
#else
    return false;
#endif
}

// Normalize object identity structurally. Arbitrary strings, texture paths,
// parameter names, GUIDs and exported scalar data are never search/replaced.
FString ObjectIdentity(const UObject* O,const UMaterial* Owner)
{
    if(!O)return FString();
    if(O==Owner)return TEXT("$OWNER");
    if(O==Owner->GetEditorOnlyData())return TEXT("$OWNER_EDITOR_ONLY_DATA");
    if(O->IsIn(Owner))return TEXT("$OWNER:")+O->GetPathName(Owner);
    return O->GetPathName();
}
FString SoftIdentity(const FSoftObjectPath& P,const UMaterial* Owner)
{
    if(P.GetAssetPath().ToString()==Owner->GetPathName())
        return P.GetSubPathString().IsEmpty()?TEXT("$OWNER"):TEXT("$OWNER:")+P.GetSubPathString();
    return P.ToString();
}

struct FSnapshot
{
    UMaterial* Owner=nullptr;int32 Values=0;FString Error;
    bool Bounded(int32 Depth)
    {
        if(++Values>100000||Depth>32){Error=TEXT("reflection_snapshot_bound");return false;}return true;
    }
    TSharedPtr<FJsonValue> Value(const FProperty* P,const void* Address,int32 Depth)
    {
        if(!Bounded(Depth))return nullptr;
        if(const auto* Soft=CastField<FSoftObjectProperty>(P))
        {
            (void)Soft;auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("soft_object"),SoftIdentity(static_cast<const FSoftObjectPtr*>(Address)->ToSoftObjectPath(),Owner));return MakeShared<FJsonValueObject>(O);
        }
        if(const auto* Object=CastField<FObjectPropertyBase>(P))
        {
            const UObject* Target=Object->GetObjectPropertyValue(Address);auto O=MakeShared<FJsonObject>();
            if(Target)O->SetStringField(TEXT("object"),ObjectIdentity(Target,Owner));else O->SetField(TEXT("object"),MakeShared<FJsonValueNull>());
            return MakeShared<FJsonValueObject>(O);
        }
        if(const auto* Struct=CastField<FStructProperty>(P))return MakeShared<FJsonValueObject>(Fields(Struct->Struct,Address,Depth+1));
        if(const auto* Array=CastField<FArrayProperty>(P))
        {
            FScriptArrayHelper H(Array,Address);if(H.Num()>16384){Error=TEXT("reflection_array_bound");return nullptr;}
            TArray<TSharedPtr<FJsonValue>> A;for(int32 I=0;I<H.Num();++I){auto V=Value(Array->Inner,H.GetRawPtr(I),Depth+1);if(!V)return nullptr;A.Add(V);}return MakeShared<FJsonValueArray>(A);
        }
        if(const auto* Set=CastField<FSetProperty>(P))
        {
            FScriptSetHelper H(Set,Address);if(H.Num()>16384||H.GetMaxIndex()>32768){Error=TEXT("reflection_set_bound");return nullptr;}
            TArray<FString> Canonical;
            for(int32 I=0;I<H.GetMaxIndex();++I)if(H.IsValidIndex(I))
            {auto V=Value(Set->ElementProp,H.GetElementPtr(I),Depth+1);if(!V)return nullptr;auto E=MakeShared<FJsonObject>();E->SetField(TEXT("element"),V);Canonical.Add(Json(E));}
            Canonical.Sort();TArray<TSharedPtr<FJsonValue>> A;for(const auto& E:Canonical)A.Add(MakeShared<FJsonValueString>(E));auto O=MakeShared<FJsonObject>();O->SetArrayField(TEXT("set_entries_canonical_json"),A);return MakeShared<FJsonValueObject>(O);
        }
        if(const auto* Map=CastField<FMapProperty>(P))
        {
            FScriptMapHelper H(Map,Address);if(H.Num()>16384||H.GetMaxIndex()>32768){Error=TEXT("reflection_map_bound");return nullptr;}
            TArray<FString> Canonical;
            for(int32 I=0;I<H.GetMaxIndex();++I)if(H.IsValidIndex(I))
            {auto K=Value(Map->KeyProp,H.GetKeyPtr(I),Depth+1),V=Value(Map->ValueProp,H.GetValuePtr(I),Depth+1);if(!K||!V)return nullptr;auto E=MakeShared<FJsonObject>();E->SetField(TEXT("key"),K);E->SetField(TEXT("value"),V);Canonical.Add(Json(E));}
            Canonical.Sort();TArray<TSharedPtr<FJsonValue>> A;for(const auto& E:Canonical)A.Add(MakeShared<FJsonValueString>(E));auto O=MakeShared<FJsonObject>();O->SetArrayField(TEXT("map_entries_canonical_json"),A);return MakeShared<FJsonValueObject>(O);
        }
        if(CastField<FInterfaceProperty>(P)||CastField<FDelegateProperty>(P)||CastField<FMulticastDelegateProperty>(P))
        {Error=TEXT("reflection_unsupported_interface_or_delegate");return nullptr;}
        FString Text;P->ExportTextItem_Direct(Text,Address,nullptr,Owner,PPF_None);
        if(Text.Len()>65536){Error=TEXT("reflection_scalar_bound");return nullptr;}
        return MakeShared<FJsonValueString>(Text);
    }
    TSharedRef<FJsonObject> Fields(const UStruct* Type,const void* Container,int32 Depth)
    {
        auto O=MakeShared<FJsonObject>();if(!Bounded(Depth))return O;int32 Count=0;
        for(TFieldIterator<FProperty> It(Type,EFieldIteratorFlags::IncludeSuper);It;++It)
        {
            const FProperty* P=*It;if(P->HasAnyPropertyFlags(CPF_Transient))continue;
            if(++Count>2048||P->ArrayDim>16384){Error=TEXT("reflection_property_bound");return O;}
            const FString Key=P->GetOwnerStruct()->GetPathName()+TEXT("::")+P->GetName();
            if(O->HasField(Key)){Error=TEXT("reflection_property_alias");return O;}
            auto Entry=MakeShared<FJsonObject>();Entry->SetStringField(TEXT("cpp_type"),P->GetCPPType());
            Entry->SetStringField(TEXT("flags_u64"),LexToString(uint64(P->PropertyFlags)));
            if(P->ArrayDim==1)
            {auto V=Value(P,P->ContainerPtrToValuePtr<void>(Container),Depth+1);if(!V)return O;Entry->SetField(TEXT("value"),V);}
            else
            {TArray<TSharedPtr<FJsonValue>> A;for(int32 I=0;I<P->ArrayDim;++I){auto V=Value(P,P->ContainerPtrToValuePtr<void>(Container,I),Depth+1);if(!V)return O;A.Add(V);}Entry->SetArrayField(TEXT("value"),A);}
            O->SetObjectField(Key,Entry);if(!Error.IsEmpty())return O;
        }
        return O;
    }
};

// UE5.8 FValue::ToString and FType out-of-line convenience methods are
// not exported from the installed Engine DLL. Serialize public typed storage
// through the exported type description API; no engine-private implementation
// is copied, and no component, width, sign bit or storage bit is discarded.
bool ShaderConstantRecord(const UE::Shader::FValue& Value,const TSharedRef<FJsonObject>& Out,FString& Error)
{
    using namespace UE::Shader;
    const EValueType Type=Value.Type.ValueType;
    if(uint32(Type)>=uint32(EValueType::Num)||Type==EValueType::Struct||Type==EValueType::Object||Type==EValueType::Any||
        Value.Type.StructType!=nullptr||!Value.Type.ObjectType.IsNone())
    {Error=TEXT("unsupported_aggregate_object_or_untyped_shader_constant");return false;}
    const FValueTypeDescription& D=GetValueTypeDescription(Type); // ENGINE_API
    int32 Width=0;const TCHAR* ComponentName=nullptr;
    switch(D.ComponentType)
    {
    case EValueComponentType::Void: Width=0;ComponentName=TEXT("void");break;
    case EValueComponentType::Float: Width=4;ComponentName=TEXT("float32");break;
    case EValueComponentType::Double: Width=8;ComponentName=TEXT("float64");break;
    case EValueComponentType::Numeric: Width=8;ComponentName=TEXT("numeric_stored_float64");break;
    case EValueComponentType::Int: Width=4;ComponentName=TEXT("int32");break;
    case EValueComponentType::Bool: Width=1;ComponentName=TEXT("uint8_boolean");break;
    default: Error=TEXT("unsupported_shader_component_type");return false;
    }
    if(D.ValueType!=Type||D.ComponentSizeInBytes!=Width||D.NumComponents<0||D.NumComponents>16||
        Value.Component.Num()!=D.NumComponents||(Type==EValueType::Void)!=(D.NumComponents==0)||
        (D.ComponentType==EValueComponentType::Void)!=(Type==EValueType::Void))
    {Error=TEXT("shader_component_type_width_or_count_mismatch");return false;}
    static_assert(sizeof(FValueComponent)==8&&sizeof(float)==4&&sizeof(double)==8&&sizeof(int32)==4,"Shader component storage layout changed");
    Out->SetStringField(TEXT("schema"),TEXT("living_town.shader_constant_storage.v1"));
    Out->SetNumberField(TEXT("value_type_enum"),int32(Type));Out->SetStringField(TEXT("value_type_name"),D.Name);
    Out->SetNumberField(TEXT("component_type_enum"),int32(D.ComponentType));Out->SetStringField(TEXT("component_type_name"),ComponentName);
    Out->SetNumberField(TEXT("component_width_bits"),Width*8);Out->SetNumberField(TEXT("component_count"),D.NumComponents);
    Out->SetNumberField(TEXT("storage_component_width_bits"),64);
#if PLATFORM_LITTLE_ENDIAN
    Out->SetStringField(TEXT("storage_byte_order"),TEXT("little"));
#else
    Out->SetStringField(TEXT("storage_byte_order"),TEXT("big"));
#endif
    TArray<TSharedPtr<FJsonValue>> Components;
    for(int32 N=0;N<Value.Component.Num();++N)
    {
        const FValueComponent& C=Value.Component[N];auto Item=MakeShared<FJsonObject>();
        uint64 Storage=0;FMemory::Memcpy(&Storage,&C,sizeof(Storage));
        Item->SetNumberField(TEXT("index"),N);Item->SetStringField(TEXT("raw_storage_u64_hex"),FString::Printf(TEXT("%016llx"),static_cast<unsigned long long>(Storage)));
        FString Bits;
        if(Width==8)Bits=FString::Printf(TEXT("%016llx"),static_cast<unsigned long long>(Storage));
        else if(Width==4){uint32 Raw=0;FMemory::Memcpy(&Raw,&C,sizeof(Raw));Bits=FString::Printf(TEXT("%08x"),Raw);}
        else Bits=FString::Printf(TEXT("%02x"),uint32(C.Bool));
        Item->SetStringField(TEXT("raw_value_bits_hex"),Bits);bool Finite=true;
        switch(D.ComponentType)
        {
        case EValueComponentType::Float: Finite=FMath::IsFinite(C.Float);if(Finite)Item->SetNumberField(TEXT("value"),double(C.Float));break;
        case EValueComponentType::Double:
        case EValueComponentType::Numeric: Finite=FMath::IsFinite(C.Double);if(Finite)Item->SetNumberField(TEXT("value"),C.Double);break;
        case EValueComponentType::Int: Item->SetNumberField(TEXT("value"),C.Int);break;
        case EValueComponentType::Bool: Item->SetBoolField(TEXT("value"),C.Bool!=0);break;
        default: Error=TEXT("unsupported_nonempty_shader_component");return false;
        }
        Item->SetBoolField(TEXT("finite"),Finite);
        if(!Finite){Error=TEXT("nonfinite_shader_constant");return false;}
        Components.Add(MakeShared<FJsonValueObject>(Item));
    }
    Out->SetBoolField(TEXT("all_components_finite"),true);Out->SetArrayField(TEXT("components"),Components);return true;
}

TArray<TSharedPtr<FJsonValue>> Numbers(std::initializer_list<double> Values,bool& Good)
{
    TArray<TSharedPtr<FJsonValue>> Out;for(double V:Values){Good&=FMath::IsFinite(V);Out.Add(MakeShared<FJsonValueNumber>(V));}return Out;
}
TSharedRef<FJsonObject> Describe(UMaterial* M,EMaterialProperty P,const FMaterialInputDescription& D,bool& Good)
{
    auto O=MakeShared<FJsonObject>();const FExpressionInput* I=D.Input;
    if(!I){Good=false;return O;}const auto* EO=M->GetEditorOnlyData();
    O->SetBoolField(TEXT("use_constant"),D.bUseConstant);
    if(P==MP_BaseColor)O->SetArrayField(TEXT("constant"),Numbers({EO->BaseColor.Constant.R,EO->BaseColor.Constant.G,EO->BaseColor.Constant.B,EO->BaseColor.Constant.A},Good));
    else if(P==MP_Normal)O->SetArrayField(TEXT("constant"),Numbers({EO->Normal.Constant.X,EO->Normal.Constant.Y,EO->Normal.Constant.Z},Good));
    else
    {const double C=P==MP_Roughness?EO->Roughness.Constant:EO->Metallic.Constant;Good&=FMath::IsFinite(C);O->SetNumberField(TEXT("constant"),C);}
    if(I->Expression)O->SetStringField(TEXT("expression_name"),I->Expression->GetName());else O->SetField(TEXT("expression_name"),MakeShared<FJsonValueNull>());
    O->SetNumberField(TEXT("output_index"),I->OutputIndex);O->SetNumberField(TEXT("mask"),I->Mask);
    O->SetArrayField(TEXT("mask_rgba"),Numbers({double(I->MaskR),double(I->MaskG),double(I->MaskB),double(I->MaskA)},Good));
    FString Kind;
    if(P==MP_Normal&&!M->bTangentSpaceNormal&&(D.bUseConstant||!I->Expression))Kind=TEXT("vertex_normal");
    else if(D.bUseConstant)Kind=TEXT("literal");
    else if(I->Expression)Kind=TEXT("connected");
    else Kind=TEXT("default_constant");
    O->SetStringField(TEXT("effective_kind"),Kind);
    if(Kind==TEXT("default_constant"))
    {
        const EMaterialValueType T=FMaterialAttributeDefinitionMap::GetValueType(P);
        if((P==MP_Roughness||P==MP_Metallic)?(T!=MCT_Float&&T!=MCT_Float1):(T!=MCT_Float3)){Good=false;return O;}
        const FVector4f V=FMaterialAttributeDefinitionMap::GetDefaultValue(P);
        if(P==MP_Roughness||P==MP_Metallic){Good&=FMath::IsFinite(V.X);O->SetNumberField(TEXT("effective_default_constant"),V.X);}
        else O->SetArrayField(TEXT("effective_default_constant"),Numbers({V.X,V.Y,V.Z},Good));
        O->SetStringField(TEXT("default_source"),TEXT("FMaterialAttributeDefinitionMap::GetDefaultValue"));
    }
    O->SetBoolField(TEXT("root_property_active"),!M->bUseMaterialAttributes);return O;
}
}

FString ULivingTownWestwoodMaterialLibrary::ReadWestwoodMaterial(UMaterial* Material)
{
    if(!Allowed(Material))return Refuse(TEXT("editor_thread_exact_material_path_or_data"));
    auto Result=MakeShared<FJsonObject>();Result->SetStringField(TEXT("schema"),TEXT("living_town.westwood_material_snapshot.v1"));
    Result->SetStringField(TEXT("status"),TEXT("PASS_READ_ONLY_SNAPSHOT"));Result->SetStringField(TEXT("material_path"),Material->GetPathName());
    Result->SetBoolField(TEXT("tangent_space_normal"),Material->bTangentSpaceNormal);Result->SetNumberField(TEXT("blend_mode"),int32(Material->GetBlendMode()));
    Result->SetBoolField(TEXT("two_sided"),Material->IsTwoSided());Result->SetNumberField(TEXT("material_domain"),int32(Material->MaterialDomain));
    Result->SetBoolField(TEXT("use_material_attributes"),Material->bUseMaterialAttributes);Result->SetBoolField(TEXT("package_dirty"),Material->GetOutermost()->IsDirty());
    auto Inputs=MakeShared<FJsonObject>();bool Good=true;
    for(int32 N=0;N<4;++N){FMaterialInputDescription D;if(!Material->GetExpressionInputDescription(Properties[N],D)||D.bHidden)return Refuse(TEXT("required_material_input_unavailable_or_hidden"));Inputs->SetObjectField(PropertyNames[N],Describe(Material,Properties[N],D,Good));}
    if(!Good)return Refuse(TEXT("required_constant_nonfinite_or_default_type"));Result->SetObjectField(TEXT("inputs"),Inputs);
    TArray<TSharedPtr<FJsonValue>> Other;
    for(int32 N=0;N<int32(MP_MAX);++N)
    {
        const auto P=EMaterialProperty(N);if(P==MP_BaseColor||P==MP_Roughness||P==MP_Metallic||P==MP_Normal)continue;
        FMaterialInputDescription D;if(!Material->GetExpressionInputDescription(P,D))continue;
        auto O=MakeShared<FJsonObject>();O->SetNumberField(TEXT("property_enum"),N);O->SetStringField(TEXT("property_name"),FMaterialAttributeDefinitionMap::GetAttributeName(P));
        O->SetBoolField(TEXT("hidden"),D.bHidden);O->SetBoolField(TEXT("use_constant"),D.bUseConstant);O->SetNumberField(TEXT("shader_value_type"),int32(D.Type));
        auto Constant=MakeShared<FJsonObject>();FString ConstantError;
        if(!ShaderConstantRecord(D.ConstantValue,Constant,ConstantError))return Refuse(TEXT("stored_constant_snapshot: ")+ConstantError);
        O->SetStringField(TEXT("stored_constant_encoding"),TEXT("typed_shader_constant_storage_v1"));
        O->SetStringField(TEXT("stored_constant_description"),Json(Constant));
        if(D.Input)
        {O->SetStringField(TEXT("expression_identity"),ObjectIdentity(D.Input->Expression,Material));O->SetNumberField(TEXT("output_index"),D.Input->OutputIndex);O->SetNumberField(TEXT("mask"),D.Input->Mask);O->SetArrayField(TEXT("mask_rgba"),Numbers({double(D.Input->MaskR),double(D.Input->MaskG),double(D.Input->MaskB),double(D.Input->MaskA)},Good));}
        Other.Add(MakeShared<FJsonValueObject>(O));
    }
    Result->SetArrayField(TEXT("other_inputs"),Other);
    FSnapshot Snapshot;Snapshot.Owner=Material;
    Result->SetObjectField(TEXT("material_properties"),Snapshot.Fields(Material->GetClass(),Material,0));
    const UObject* EO=Material->GetEditorOnlyData();Result->SetObjectField(TEXT("editor_only_properties"),Snapshot.Fields(EO->GetClass(),EO,0));
    TMap<FString,UMaterialExpression*> ByName;TArray<FString> Names;
    for(const auto& Ptr:Material->GetExpressions())
    {
        UMaterialExpression* E=Ptr.Get();if(!IsValid(E)||E->GetOuter()!=Material||ByName.Contains(E->GetName())||Names.Num()>=4096)return Refuse(TEXT("expression_owner_alias_or_count"));
        Names.Add(E->GetName());ByName.Add(E->GetName(),E);
    }
    Names.Sort();TArray<TSharedPtr<FJsonValue>> Expressions;
    for(const auto& Name:Names)
    {
        auto* E=ByName[Name];auto O=MakeShared<FJsonObject>();O->SetStringField(TEXT("name"),Name);O->SetStringField(TEXT("class_path"),E->GetClass()->GetPathName());
        O->SetStringField(TEXT("identity"),ObjectIdentity(E,Material));O->SetObjectField(TEXT("properties"),Snapshot.Fields(E->GetClass(),E,0));Expressions.Add(MakeShared<FJsonValueObject>(O));
    }
    if(!Snapshot.Error.IsEmpty()||!Good)return Refuse(Snapshot.Error.IsEmpty()?TEXT("snapshot_nonfinite"):Snapshot.Error);
    Result->SetArrayField(TEXT("expressions"),Expressions);Result->SetNumberField(TEXT("expression_count"),Expressions.Num());
    Result->SetStringField(TEXT("property_snapshot_encoding"),TEXT("nontransient_reflection_v1; scalar ExportText; structural object owner normalization; sorted canonical-JSON set/map entries"));
    Result->SetBoolField(TEXT("source_mutated"),false);const FString Text=Json(Result);if(Text.Len()>4*1024*1024)return Refuse(TEXT("snapshot_json_bound"));return Text;
}

FString ULivingTownWestwoodMaterialLibrary::ClearWestwoodDerivedConstantOverrides(UMaterial* Material)
{
    if(!Allowed(Material)||Material->GetPathName()!=DerivedPath)return Refuse(TEXT("setter_exact_new_material_only"));
    FString Owned=FPlatformMisc::GetEnvironmentVariable(TEXT("LIVING_TOWN_BOOTSTRAP_OUTPUT"));
    if(Owned.IsEmpty()||FPaths::IsRelative(Owned))return Refuse(TEXT("setter_owned_output_required"));
    Owned=FPaths::ConvertRelativePathToFull(Owned);FPaths::NormalizeDirectoryName(Owned);
    FString Project=FPaths::ConvertRelativePathToFull(FPaths::ProjectDir());FPaths::NormalizeDirectoryName(Project);
    if(!FPaths::IsUnderDirectory(Project,Owned)||!NoReparseAncestors(Owned)||!NoReparseAncestors(Project))return Refuse(TEXT("setter_project_outside_owned_output"));
    const FString File=FPaths::ConvertRelativePathToFull(FPackageName::LongPackageNameToFilename(Material->GetOutermost()->GetName(),FPackageName::GetAssetPackageExtension()));
    if(!FPaths::IsUnderDirectory(File,FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()))||IFileManager::Get().FileExists(*File))return Refuse(TEXT("setter_unsaved_new_package_required"));
    if(Material->bUseMaterialAttributes||Material->MaterialDomain!=MD_Surface||Material->bTangentSpaceNormal)return Refuse(TEXT("setter_requires_surface_root_world_normal_frame"));
    UMaterialExpressionCustom* Custom=nullptr;
    for(int32 N=0;N<4;++N)
    {
        FMaterialInputDescription D;if(!Material->GetExpressionInputDescription(Properties[N],D)||D.bHidden||!D.Input)return Refuse(TEXT("setter_missing_root_input"));
        const auto* I=D.Input;auto* C=Cast<UMaterialExpressionCustom>(I->Expression);
        if(!C||C->GetOuter()!=Material||C->Description!=AdapterDescription||I->OutputIndex!=OutputIndices[N]||I->Mask||I->MaskR||I->MaskG||I->MaskB||I->MaskA||(Custom&&C!=Custom))return Refuse(TEXT("setter_exact_common_custom_outputs_required"));
        Custom=C;
    }
    if(!Custom||Custom->OutputType!=CMOT_Float3||Custom->AdditionalOutputs.Num()!=3)return Refuse(TEXT("setter_custom_output_layout"));
    const TCHAR* ExtraNames[3]={TEXT("WorldNormal"),TEXT("Roughness"),TEXT("Metallic")};
    const ECustomMaterialOutputType ExtraTypes[3]={CMOT_Float3,CMOT_Float1,CMOT_Float1};
    for(int32 N=0;N<3;++N)if(Custom->AdditionalOutputs[N].OutputName!=FName(ExtraNames[N])||Custom->AdditionalOutputs[N].OutputType!=ExtraTypes[N])return Refuse(TEXT("setter_additional_output_identity"));
    const auto& Outputs=Custom->GetOutputs();if(Outputs.Num()!=4||Outputs[0].OutputName!=FName(TEXT("return")))return Refuse(TEXT("setter_custom_outputs_not_rebuilt"));
    for(int32 N=0;N<3;++N)if(Outputs[N+1].OutputName!=FName(ExtraNames[N]))return Refuse(TEXT("setter_actual_output_name_mismatch"));
    int32 Occurrences=0;for(const auto& E:Material->GetExpressions())if(E.Get()==Custom)++Occurrences;
    if(Occurrences!=1)return Refuse(TEXT("setter_custom_not_unique_expression_member"));
    // Validate the complete readback before the only mutation. A refusal above
    // leaves every source/derived field intact; there is no Save/Modify/compile.
    const FString Before=ReadWestwoodMaterial(Material);
    TSharedPtr<FJsonObject> Parsed;auto Reader=TJsonReaderFactory<>::Create(Before);
    if(!FJsonSerializer::Deserialize(Reader,Parsed)||!Parsed||Parsed->GetStringField(TEXT("status"))!=TEXT("PASS_READ_ONLY_SNAPSHOT"))return Refuse(TEXT("setter_pre_mutation_snapshot_failed"));
    auto* EO=Material->GetEditorOnlyData();EO->BaseColor.UseConstant=false;EO->Roughness.UseConstant=false;EO->Metallic.UseConstant=false;EO->Normal.UseConstant=false;
    return ReadWestwoodMaterial(Material);
}
