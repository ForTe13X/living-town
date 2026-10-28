#include "LivingTownTilePlan.h"

bool FLivingTownTileDemand::Visit(const FString& Id,TSet<FString>& Path,TSet<FString>& Done,FString& Error) const
{
    if(Done.Contains(Id)) return true;
    const auto* Edges=Dependencies.Find(Id);
    if(!Edges || Path.Contains(Id) || Path.Num()>=64){Error=TEXT("tile_dependency_missing_cycle_or_depth");return false;}
    Path.Add(Id);
    for(const FString& Child:*Edges) if(!Visit(Child,Path,Done,Error)) return false;
    Path.Remove(Id);Done.Add(Id);return true;
}

bool FLivingTownTileDemand::Initialize(const TArray<FLivingTownTileUnitRef>& Units,FString& Error)
{
    TMap<FString,TArray<FString>> Candidate;
    if(Units.IsEmpty() || Units.Num()>2048){Error=TEXT("tile_unit_count");return false;}
    TSet<FString> FoldedIds;
    for(const auto& Unit:Units)
    {
        if(Unit.UnitId.IsEmpty() || FoldedIds.Contains(Unit.UnitId.ToLower())){Error=TEXT("tile_duplicate_unit");return false;}
        FoldedIds.Add(Unit.UnitId.ToLower());
        TSet<FString> Unique;
        for(const FString& Child:Unit.Dependencies)
            if(Child.IsEmpty() || Unique.Contains(Child)){Error=TEXT("tile_duplicate_dependency");return false;}else Unique.Add(Child);
        Candidate.Add(Unit.UnitId,Unit.Dependencies);
    }
    // Validate a candidate without replacing an already usable live graph.
    FLivingTownTileDemand Probe;Probe.Dependencies=Candidate;
    TSet<FString> Done,Path;
    for(const auto& Pair:Candidate) if(!Probe.Visit(Pair.Key,Path,Done,Error)) return false;
    Reset();Dependencies=MoveTemp(Candidate);return true;
}

bool FLivingTownTileDemand::SetSupports(const TMap<FString,TArray<FString>>& ActiveSupports,FString& Error)
{
    TMap<FString,int32> Candidate;
    if(ActiveSupports.Num()>25){Error=TEXT("tile_support_count");return false;}
    for(const auto& Support:ActiveSupports)
    {
        TSet<FString> Path,Closure;
        if(Support.Key.IsEmpty()){Error=TEXT("tile_support_id");return false;}
        for(const FString& Id:Support.Value) if(!Visit(Id,Path,Closure,Error)) return false;
        for(const FString& Id:Closure) ++Candidate.FindOrAdd(Id);
    }
    RefCounts=MoveTemp(Candidate);
    for(auto It=Tokens.CreateIterator();It;++It) if(!RefCounts.Contains(It.Key())) It.RemoveCurrent();
    return true;
}

uint64 FLivingTownTileDemand::BeginRequest(const FString& UnitId)
{
    if(!RefCounts.Contains(UnitId) || Tokens.Contains(UnitId) || NextToken==MAX_uint64) return 0;
    const uint64 Token=NextToken++;Tokens.Add(UnitId,Token);return Token;
}

bool FLivingTownTileDemand::Accepts(const FString& UnitId,uint64 Token) const
{
    const auto* Current=Tokens.Find(UnitId);
    return Token!=0 && Current && *Current==Token && RefCounts.Contains(UnitId);
}

void FLivingTownTileDemand::Cancel(const FString& UnitId){Tokens.Remove(UnitId);}
void FLivingTownTileDemand::Reset()
{
    Dependencies.Empty();RefCounts.Empty();Tokens.Empty();
    // Never reuse a token across Stop/Start, even in the same subsystem object.
    if(NextToken<MAX_uint64) ++NextToken;
}
