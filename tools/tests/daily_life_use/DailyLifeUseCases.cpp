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
    return a.hunger==b.hunger && a.energy==b.energy && a.hygiene==b.hygiene && a.fun==b.fun;
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
        assert(s.needs().fun==7500&&s.requests().back().progressed_ticks==18);
        assert(s.requests().back().end==End::Completed&&s.requests().back().end_tick==118);
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
    { // Durable typed state reconstructs partial gains and then continues once.
        ResidentUse original("ben");const auto g=grant(Kind::Eat);assert(original.begin(g).accepted);
        for(Tick i=1;i<=6;++i)assert(original.advance_one(i,contact())==Outcome::Progress);
        const auto saved=original.export_state();ResidentUse restored("ben");
        assert(restored.restore_state(saved)&&same_journal(saved,restored.export_state()));
        assert(restored.active()->elapsed==6&&restored.requests()[0].progressed_ticks==6);
        assert(restored.needs().fun==7300);
        for(Tick i=7;i<=18;++i){assert(original.advance_one(i,contact())==restored.advance_one(i,contact()));}
        assert(same_journal(original.export_state(),restored.export_state()));
        assert(restored.needs().fun==7500&&restored.requests()[0].end==End::Completed);
        const auto before=restored.export_state();assert(restored.begin(g).already_applied);
        assert(same_journal(before,restored.export_state()));
    }
    { // Recomputed or well-typed cache edits are not a substitute for replay.
        ResidentUse source("ben");assert(source.begin(grant(Kind::Eat)).accepted);
        source.advance_one(1,contact());const auto good=source.export_state();
        ResidentUse guard("ben");assert(guard.advance_idle_to(9));const auto before=guard.export_state();
        for(int i=0;i<8;++i) {
            auto bad=good;
            switch(i){case 0:++bad.needs.fun;break;case 1:++bad.active->elapsed;break;
                case 2:++bad.requests[0].progressed_ticks;break;case 3:bad.requests[0].end=End::Completed;break;
                case 4:bad.history[1].contact->permission_valid=false;break;case 5:bad.history[0].grant->grant_id="other";break;
                case 6:bad.version="1";break;case 7:bad.resident="aria";break;}
            assert(!guard.restore_state(bad)&&same_journal(before,guard.export_state()));
        }
        auto bad=good;bad.history[1].tick=3;assert(!guard.restore_state(bad));
        assert(same_journal(before,guard.export_state()));
        bad=good;bad.history.resize(max_history+1);
        assert(!guard.restore_state(bad)&&same_journal(before,guard.export_state()));
        bad=good;bad.requests.resize(max_requests+1);
        assert(!guard.restore_state(bad)&&same_journal(before,guard.export_state()));
    }
    { // Inactive catch-up is bounded and coalesced, never action progress.
        ResidentUse s("ben");for(Tick i=1;i<=100;++i)assert(s.advance_one(i,{})==Outcome::TickOnly);
        assert(s.export_state().history.size()==1);
        auto g=grant(Kind::Eat);g.tick=100;assert(s.begin(g).accepted);const auto active=s.export_state();
        assert(!s.advance_idle_to(1000)&&same_journal(active,s.export_state()));
        assert(s.interrupt()&&s.requests().back().end==End::Interrupted);
        assert(s.advance_idle_to(max_tick)&&s.needs().hunger==0&&s.needs().energy==0&&s.needs().hygiene==0&&s.needs().fun==7200);
        ResidentUse restored("ben");assert(restored.restore_state(s.export_state()));
        assert(same_journal(restored.export_state(),s.export_state()));
        assert(s.advance_one(max_tick,{})==Outcome::RejectedTick&&!s.advance_idle_to(max_tick));
    }
    { // Load invalidation is distinct from completion/cancel and preserves effects.
        ResidentUse s("ben");const auto g=grant(Kind::Eat);assert(s.begin(g).accepted);
        s.advance_one(1,contact());const auto earned=s.needs();const auto saved=s.export_state();
        ResidentUse restored("ben");assert(restored.restore_state(saved));
        assert(restored.invalidate_use_after_load()&&!restored.active());
        assert(restored.requests().back().end==End::AfterLoad&&same_needs(earned,restored.needs()));
        const auto stopped=restored.export_state();assert(!restored.invalidate_use_after_load());
        assert(restored.begin(g).already_applied&&same_journal(stopped,restored.export_state()));
        ResidentUse again("ben");assert(again.restore_state(stopped));
        assert(same_journal(stopped,again.export_state()));
    }
    std::cout << "PASS 15 daily-life progress/persistence groups (portable CPU only).\n";
}
