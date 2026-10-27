#include "LivingTownMaterialInspection.h"
#include "Materials/MaterialExpressionNamedReroute.h"
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
