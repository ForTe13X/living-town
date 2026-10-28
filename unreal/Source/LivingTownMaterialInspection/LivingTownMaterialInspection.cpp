#include "LivingTownMaterialInspection.h"
#include "Materials/MaterialExpressionNamedReroute.h"
#include "Materials/MaterialExpressionFunctionInput.h"
#include "Materials/MaterialInstance.h"
#include "StaticParameterSet.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Modules/ModuleManager.h"

IMPLEMENT_MODULE(FDefaultModuleImpl, LivingTownMaterialInspection)
UObject* ULivingTownMaterialInspection::ReadRerouteDeclaration(UObject* Expression) {
 if (!IsInGameThread()) return nullptr;
 const auto* Usage=Cast<UMaterialExpressionNamedRerouteUsage>(Expression);
 return Usage ? Usage->Declaration.Get() : nullptr;
}
FString ULivingTownMaterialInspection::ReadStaticSwitches(UObject* Material) {
 const auto* Instance=Cast<UMaterialInstance>(Material);
 if (!IsInGameThread() || !Instance) return TEXT("{\"status\":\"REFUSED_TYPE_OR_THREAD\"}");
 const FStaticParameterSet Snapshot=Instance->GetStaticParameters();
 if (Snapshot.StaticSwitchParameters.Num()>1024) return TEXT("{\"status\":\"REFUSED_BOUND\"}");
 TArray<TSharedPtr<FJsonValue>> Rows;
 for (const auto& Switch:Snapshot.StaticSwitchParameters) {
  auto Row=MakeShared<FJsonObject>();
  Row->SetStringField(TEXT("name"),Switch.ParameterInfo.Name.ToString());
  Row->SetNumberField(TEXT("association"),static_cast<int32>(Switch.ParameterInfo.Association));
  Row->SetNumberField(TEXT("index"),Switch.ParameterInfo.Index);
  Row->SetBoolField(TEXT("override"),Switch.bOverride);
  Row->SetBoolField(TEXT("value"),Switch.Value);
  Rows.Add(MakeShared<FJsonValueObject>(Row));
 }
 auto Root=MakeShared<FJsonObject>();
 Root->SetStringField(TEXT("status"),TEXT("PASS_TYPED_READ_ONLY_SNAPSHOT"));
 Root->SetStringField(TEXT("material"),Instance->GetPathName());
 Root->SetArrayField(TEXT("parameters"),Rows);
 FString Result;auto Writer=TJsonWriterFactory<>::Create(&Result);
 FJsonSerializer::Serialize(Root,Writer);return Result;
}

FString ULivingTownMaterialInspection::ReadFunctionInputDefault(UObject* Expression) {
 // No UObject access before the game-thread guard. No effective-preview/compiler evaluation.
 if (!IsInGameThread()) return TEXT("{\"status\":\"REFUSED_THREAD\"}");
 if (!IsValid(Expression)) return TEXT("{\"status\":\"REFUSED_NULL_OR_INVALID\"}");
 const auto* Input=Cast<UMaterialExpressionFunctionInput>(Expression);
 if (!Input) return TEXT("{\"status\":\"REFUSED_TYPE\"}");
 const FVector4f Value=Input->PreviewValue;
 if (!FMath::IsFinite(Value.X) || !FMath::IsFinite(Value.Y) || !FMath::IsFinite(Value.Z) || !FMath::IsFinite(Value.W))
  return TEXT("{\"status\":\"REFUSED_NONFINITE_PREVIEW\"}");
 const FString Name=Input->InputName.ToString();
 if (Name.Len()>256) return TEXT("{\"status\":\"REFUSED_NAME_BOUND\"}");
 const int32 Type=static_cast<int32>(Input->InputType.GetValue());
 if (Type<0 || Type>=static_cast<int32>(FunctionInput_MAX)) return TEXT("{\"status\":\"REFUSED_INPUT_TYPE\"}");
 const UObject* Owner=Input->GetOuter();
 const UMaterialExpression* PreviewExpression=Input->Preview.Expression;
 if (PreviewExpression && !IsValid(PreviewExpression)) return TEXT("{\"status\":\"REFUSED_PREVIEW_EXPRESSION\"}");
 const FString ObjectPath=Input->GetPathName();
 const FString OwnerPath=Owner ? Owner->GetPathName() : FString();
 const FString PreviewPath=PreviewExpression ? PreviewExpression->GetPathName() : FString();
 if (ObjectPath.Len()>4096 || OwnerPath.Len()>4096 || PreviewPath.Len()>4096)
  return TEXT("{\"status\":\"REFUSED_PATH_BOUND\"}");
 auto Root=MakeShared<FJsonObject>();
 Root->SetStringField(TEXT("status"),TEXT("PASS_TYPED_FUNCTION_INPUT_DEFAULT_SNAPSHOT"));
 Root->SetBoolField(TEXT("game_thread"),true);
 Root->SetBoolField(TEXT("read_only"),true);
 Root->SetBoolField(TEXT("effective_preview_stack_or_compiler_evaluated"),false);
 Root->SetStringField(TEXT("object_path"),ObjectPath);
 Root->SetStringField(TEXT("owner_path"),OwnerPath);
 Root->SetStringField(TEXT("owner_path_kind"),TEXT("direct_outer"));
 Root->SetStringField(TEXT("input_name"),Name);
 Root->SetBoolField(TEXT("input_name_is_none"),Input->InputName.IsNone());
 Root->SetStringField(TEXT("input_id"),Input->Id.ToString(EGuidFormats::DigitsWithHyphensLower));
 Root->SetNumberField(TEXT("input_type"),Type);
 Root->SetBoolField(TEXT("use_preview_value_as_default"),Input->bUsePreviewValueAsDefault!=0);
 TArray<TSharedPtr<FJsonValue>> Values;
 Values.Add(MakeShared<FJsonValueNumber>(Value.X));
 Values.Add(MakeShared<FJsonValueNumber>(Value.Y));
 Values.Add(MakeShared<FJsonValueNumber>(Value.Z));
 Values.Add(MakeShared<FJsonValueNumber>(Value.W));
 Root->SetArrayField(TEXT("preview_value"),Values);
 auto Preview=MakeShared<FJsonObject>();
 Preview->SetBoolField(TEXT("connected"),PreviewExpression!=nullptr);
 Preview->SetStringField(TEXT("expression_path"),PreviewPath);
 Preview->SetNumberField(TEXT("output_index"),Input->Preview.OutputIndex);
 Preview->SetNumberField(TEXT("mask"),Input->Preview.Mask);
 Preview->SetNumberField(TEXT("mask_r"),Input->Preview.MaskR);
 Preview->SetNumberField(TEXT("mask_g"),Input->Preview.MaskG);
 Preview->SetNumberField(TEXT("mask_b"),Input->Preview.MaskB);
 Preview->SetNumberField(TEXT("mask_a"),Input->Preview.MaskA);
 Root->SetObjectField(TEXT("preview"),Preview);
 FString Result;auto Writer=TJsonWriterFactory<>::Create(&Result);
 if (!FJsonSerializer::Serialize(Root,Writer) || Result.Len()>32768)
  return TEXT("{\"status\":\"REFUSED_SERIALIZATION_BOUND\"}");
 return Result;
}
