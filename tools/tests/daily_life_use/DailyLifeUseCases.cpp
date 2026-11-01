// Portable care progression cases; trusted contexts are synthetic CPU inputs.
#ifdef NDEBUG
#error DailyLifeUseCases requires active assertions.
#endif
#include "../../../unreal/Source/LivingTownNative/ThirdParty/DailyLifeUseV1.hpp"
#include <cassert>
#include <iostream>
using namespace living_town::daily_life_use_v1;
static ApprovedUse grant(Kind kind,const char* request="use/1",const char* id="grant/1") {
    return {request,"ben","site/qualified",id,kind,0,1};
}
static Contact contact() {
    return {"ben","site/qualified","grant/1",true,true,true,true,true};
}
static bool same_needs(const Needs& a,const Needs& b) {
    return a.hunger==b.hunger && a.energy==b.energy && a.hygiene==b.hygiene;
}
int main() {
    { // Authored exact decay, independent of rendering frequency.
        ResidentUse s("ben");assert(s.advance_one(1,{})==Outcome::TickOnly);
        assert(s.needs().hunger==7172&&s.needs().energy==7182&&s.needs().hygiene==7189);
        assert(s.advance_one(3,{})==Outcome::RejectedTick&&s.tick()==1);
    }
    { // Exact 50-point meal benefit across 18 ticks, before saturation.
        ResidentUse s("ben");for(Tick i=1;i<=100;++i)s.advance_one(i,{});
        auto g=grant(Kind::Eat);g.tick=100;assert(s.begin(g).accepted);
        for(Tick i=101;i<118;++i)assert(s.advance_one(i,contact())==Outcome::Progress);
        assert(s.advance_one(118,contact())==Outcome::Completed);
        assert(s.needs().hunger==7200-118*28+5000&&!s.active());
    }
    { // Replay is not another action/meal; conflicting reuse is rejected.
        ResidentUse s("ben");auto g=grant(Kind::Eat);assert(s.begin(g).accepted);
        assert(s.begin(g).already_applied&&s.requests().size()==1);
        auto bad=g;bad.kind=Kind::Sleep;
        assert(s.begin(bad).reason=="request_id_conflict");
        assert(s.cancel());auto replay=g;assert(s.begin(replay).already_applied&&!s.active());
        auto reuse=g;reuse.request_id="use/2";assert(s.begin(reuse).reason=="grant_already_consumed");
    }
    { // Contact loss earns no action gain on the interrupted tick.
        ResidentUse s("ben");assert(s.begin(grant(Kind::Sleep)).accepted);
        auto c=contact();c.permission_valid=false;
        assert(s.advance_one(1,c)==Outcome::Interrupted&&s.needs().energy==7182);
        assert(!s.active()&&!s.cancel());
    }
    { // Copied in-memory continuation is exact; it is not a tested disk load.
        ResidentUse a("ben");assert(a.begin(grant(Kind::WashFace)).accepted);
        for(Tick i=1;i<=3;++i)a.advance_one(i,contact());
        ResidentUse b=a;for(Tick i=4;i<=6;++i){a.advance_one(i,contact());b.advance_one(i,contact());}
        assert(a.needs().hygiene==7200-6*11+1800);
        assert(a.needs().hygiene==b.needs().hygiene&&!a.active()&&!b.active());
    }
    { // Post-load progress invalidation keeps earned needs. World owns release.
        ResidentUse s("ben");assert(s.begin(grant(Kind::Sleep)).accepted);
        s.advance_one(1,contact());auto before=s.needs();
        assert(s.invalidate_use_after_load()&&!s.active());
        assert(s.needs().energy==before.energy);assert(s.advance_one(2,{})==Outcome::TickOnly);
    }
    { // Malformed internal grants fail shape checks; this is not a UI trust test.
        ResidentUse s("ben");auto bad=grant(Kind::Eat);bad.resident_id="aria";
        assert(!s.begin(bad).accepted&&s.requests().empty());bad=grant(Kind::Eat);bad.grant_event_id=0;
        assert(!s.begin(bad).accepted&&s.requests().empty());
    }
    { // Original immutable grant replays late during use without changing progress.
        ResidentUse s("ben");const auto g=grant(Kind::Eat);assert(s.begin(g).accepted);
        assert(s.advance_one(1,contact())==Outcome::Progress);
        const auto before=s.needs();const auto elapsed=s.active()->elapsed;
        const auto replay=s.begin(g);
        assert(replay.accepted&&replay.already_applied&&replay.reason=="started");
        assert(s.tick()==1&&same_needs(s.needs(),before)&&s.requests().size()==1);
        assert(s.active()&&s.active()->elapsed==elapsed&&s.active()->grant.tick==0);
        auto changed=g;changed.tick=1;
        assert(s.begin(changed).reason=="request_id_conflict");
        changed.tick=-1;assert(s.begin(changed).reason=="request_id_conflict");
        assert(s.tick()==1&&same_needs(s.needs(),before)&&s.active()->elapsed==elapsed);
    }
    { // Completed use replay does not start again or grant another benefit.
        ResidentUse s("ben");const auto g=grant(Kind::WashFace);assert(s.begin(g).accepted);
        for(Tick i=1;i<6;++i)assert(s.advance_one(i,contact())==Outcome::Progress);
        assert(s.advance_one(6,contact())==Outcome::Completed);
        const auto before=s.needs();const auto replay=s.begin(g);
        assert(replay.accepted&&replay.already_applied&&!s.active());
        assert(s.tick()==6&&same_needs(s.needs(),before)&&s.requests().size()==1);
        assert(s.advance_one(7,contact())==Outcome::TickOnly);
        assert(s.needs().hygiene==before.hygiene-11);
    }
    { // Interrupted use replay keeps partial gains and cannot revive spatial use.
        ResidentUse s("ben");const auto g=grant(Kind::Sleep);assert(s.begin(g).accepted);
        assert(s.advance_one(1,contact())==Outcome::Progress);
        auto lost=contact();lost.reachable=false;
        assert(s.advance_one(2,lost)==Outcome::Interrupted);
        const auto before=s.needs();const auto replay=s.begin(g);
        assert(replay.accepted&&replay.already_applied&&!s.active());
        assert(s.tick()==2&&same_needs(s.needs(),before)&&s.requests().size()==1);
        assert(s.advance_one(3,contact())==Outcome::TickOnly);
        assert(s.needs().energy==before.energy-18);
    }
    { // Request/grant history precedes current-tick policy for NEW grants.
        ResidentUse s("ben");const auto g=grant(Kind::Eat);assert(s.begin(g).accepted);
        assert(s.advance_one(1,contact())==Outcome::Progress);assert(s.cancel());
        auto reused=g;reused.request_id="use/2";
        assert(s.begin(reused).reason=="grant_already_consumed");
        auto fresh=grant(Kind::WashFace,"use/3","grant/3");fresh.grant_event_id=3;
        assert(s.begin(fresh).reason=="invalid_authority_grant");
        assert(!s.active()&&s.requests().size()==1);
        fresh.tick=1;assert(s.begin(fresh).accepted&&s.requests().size()==2);
        assert(s.active()&&s.active()->elapsed==0&&s.active()->grant.tick==1);
    }
    std::cout << "PASS 11 daily-life progress groups (portable CPU only).\n";
}
