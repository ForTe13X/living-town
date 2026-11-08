// Synthetic portable observations only. This cannot qualify a native bed/clip.
#ifdef NDEBUG
#error Sleep cases require active assertions
#endif
#include "../../../unreal/Source/LivingTownNative/ThirdParty/CafeWorldV3Envelope.hpp"
#include <fstream>
#include <iostream>
#include <iterator>
namespace w=living_town::cafe_world_v3;
namespace c=w::care;
namespace {
int checks=0,groups=0;
void check(bool value,const char* why){++checks;if(!value)throw std::runtime_error(why);}
void pass(const char* label){++groups;std::cout<<"CASE "<<label<<" PASS\n";}
w::TrustedResidentialChange authored(w::Int tick=0){return {tick,true,w::residential_registry_sha256};}
w::Kernel world(){w::Kernel k;check(k.activate_care({0,true}).ok,"care activation");check(k.activate_residential(authored()).ok,"explicit new residential assignment");return k;}
w::SleepCommand intent(const w::Kernel& k,const std::string& id="sleep/1"){return {id,w::sleep_site,k.revision()};}
w::SleepContext at(w::Int tick){return {"ben","ben",tick,true,true,true,true};}
c::Contact contact(const c::ResidentUse& use){const auto& g=use.active()->grant;return {g.resident_id,g.site_id,g.grant_id,true,true,true,true,true};}
c::SleepEntryObservation entry(const c::ResidentUse& use){const auto& g=use.active()->grant;return {g.resident_id,g.site_id,g.grant_id,true,true,true,true,true,true};}
w::CareBindings sources(){w::SourceBindings b;b.core_sha256=std::string(64,'a');b.fixture_sha256=std::string(64,'b');b.physical_sha256=std::string(64,'c');b.clip_sha256=std::string(64,'d');b.roster_sha256=std::string(64,'e');return {b,std::string(64,'6'),w::residential_registry_sha256,std::string(64,'7')};}
std::string snapshot(const c::ResidentUse& use){return w::encode_care_document(use.export_state());}
void money(const w::Kernel& k,w::Int aria=12,w::Int ben=12,w::Int stock=2){check(k.coin("aria")==aria&&k.coin("ben")==ben&&k.rations()==stock&&k.verify_ledger()&&k.verify_care(),"one unchanged wallet/stock book reconciles");}
void begin(w::Kernel& k,c::ResidentUse& use){check(w::begin_sleep_use(k,use,intent(k),at(use.tick())).ok,"paired sleep starts");}
std::string read(const char* path){std::ifstream f(path,std::ios::binary);check(bool(f),"existing fixture readable");return {std::istreambuf_iterator<char>(f),{}};}
}
int main(int argc,char** argv){try{
 check(argc==2,"Usage: SleepCases ACTIVE_MEAL_V5_FIXTURE");
 {
  w::Kernel k;const auto untouched=k.save_bytes();check(!k.residential_right().active,"default has no residential right");
  check(!k.activate_residential({0,false,w::residential_registry_sha256}).ok&&k.save_bytes()==untouched,"explicit activation required");
  check(!k.activate_residential({0,true,std::string(64,'0')}).ok&&k.save_bytes()==untouched,"exact new source required");
  check(!k.has_residential_right("ben",w::sleep_site,0),"old address does not authorize bed");
  check(k.activate_residential(authored()).ok&&k.residential_right().active,"new authored event grants right");
  const auto once=k.save_bytes();check(k.activate_residential(authored()).already_applied&&k.save_bytes()==once,"activation idempotent");
  check(k.coin("aria")==12&&k.coin("ben")==12&&k.rations()==0,"assignment invents no coins/stock");
  check(!k.has_residential_right("aria",w::sleep_site,0)&&!k.has_residential_right("ben",w::meal_site,0),"resident and bed identity exact");pass("S00_explicit_source_assignment");
 }
 {
  auto k=world();c::ResidentUse use("ben");check(use.advance_idle_to(200),"low-energy history without setter");begin(k,use);const auto cmd=intent(k);(void)cmd;
  const auto before=use.needs();const auto paid=k.save_bytes();
  for(w::Int i=201;i<=206;++i){auto r=w::wait_for_sleep_entry(k,use,i,entry(use));check(r.ok&&r.outcome==c::Outcome::WaitingBeforeFirstProgress,"bounded sleep entry");check(use.active()->elapsed==0&&use.needs().energy==before.energy-(i-200)*18&&use.needs().fun==before.fun&&k.save_bytes()==paid,"entry decays and grants no benefit/transaction");}
  auto r=w::wait_for_sleep_entry(k,use,207,entry(use));check(!r.ok&&use.tick()==206,"entry finite six-tick deadline");
  for(w::Int i=207;i<=246;++i){r=w::advance_sleep_use(k,use,i,contact(use));check(r.ok&&r.outcome==(i==246?c::Outcome::Completed:c::Outcome::Progress),"one natural logical rest tick");}
  check(use.needs().energy==7200-246*18+6200&&use.needs().hunger==7200-246*28&&use.needs().fun==7200,"exact energy gain with normal decay/no fun gain");
  check(!use.active()&&!k.care_grants().back().active&&use.requests().back().progressed_ticks==40,"forty ticks release reservation");money(k);pass("S01_entry_and_forty_tick_sleep");
 }
 {
  for(int i=0;i<8;++i){auto k=world();c::ResidentUse use("ben");auto cmd=intent(k);auto where=at(0);
   switch(i){case 0:where.authenticated_actor="aria";break;case 1:where.fresh=false;break;case 2:where.correct_floor=false;break;case 3:where.reachable=false;break;case 4:where.qualified_clip=false;break;case 5:cmd.site_id="unknown_bed";break;case 6:cmd.expected_revision=0;break;case 7:check(k.revoke_residential(authored()).ok,"revoke before begin");cmd=intent(k);break;}
   const auto needs=snapshot(use);check(!w::begin_sleep_use(k,use,cmd,where).ok&&snapshot(use)==needs&&k.care_grants().empty(),"invalid sleep cannot start/gain");money(k);
  }pass("S02_auth_source_spatial_clip_and_revision_refusals");
 }
 {
  auto k=world();c::ResidentUse use("ben");const auto original=intent(k);check(w::begin_sleep_use(k,use,original,at(0)).ok,"initial intent");
  check(w::advance_sleep_use(k,use,1,contact(use)).ok,"one progress");const auto wb=k.save_bytes(),cb=snapshot(use);
  const auto replay=w::begin_sleep_use(k,use,original,at(1));check(replay.ok&&replay.already_applied&&k.save_bytes()==wb&&snapshot(use)==cb,"retry does not restart physical/logical use");
  auto conflict=original;conflict.site_id=w::meal_site;check(w::begin_sleep_use(k,use,conflict,at(1)).reason=="request_id_conflict","same ID conflicting bed refused");
  w::MealCommand meal{original.request_id,w::meal_site,w::MealKind::PurchaseMeal,k.revision()};check(!k.execute_meal(meal,{"ben","ben",1,true,true,true,true,true}).ok,"one request domain across care kinds");
  check(!w::advance_meal_use(k,use,2,contact(use)).ok,"meal tick cannot progress sleep");
  check(w::cancel_care_use(k,use).ok&&!use.active(),"generic cancel dispatch");
  check(w::begin_sleep_use(k,use,original,at(1)).already_applied&&!use.active(),"cancelled retry does not reserve again");money(k);pass("S03_idempotence_and_kind_separation");
 }
 {
  auto k=world();c::ResidentUse use("ben");const auto wb=k.save_bytes(),cb=snapshot(use);
  check(!w::begin_sleep_use(k,use,intent(k),at(0),w::CareCommitFault::AfterCareBegin).ok&&k.save_bytes()==wb&&snapshot(use)==cb,"begin rollback");begin(k,use);
  const auto active=k.save_bytes(),pending=snapshot(use);
  check(!w::wait_for_sleep_entry(k,use,1,entry(use),w::CareCommitFault::AfterCareWait).ok&&k.save_bytes()==active&&snapshot(use)==pending,"entry rollback");
  check(!w::advance_sleep_use(k,use,1,contact(use),w::CareCommitFault::AfterCareAdvance).ok&&k.save_bytes()==active&&snapshot(use)==pending,"rest rollback");
  check(w::advance_sleep_use(k,use,1,contact(use)).ok,"rest succeeds");const auto needs=use.needs();
  check(w::revoke_residential_use(k,use,authored(1)).ok&&!use.active()&&!k.care_grants().back().active&&!k.residential_right().active,"revocation releases exact sleep atomically");
  check(c::same_need_values(use.needs(),needs)&&use.requests().back().end==c::End::Interrupted,"revocation preserves earned needs");
  check(!k.activate_residential(authored(1)).ok,"revoked initial assignment cannot silently reactivate");money(k);pass("S04_atomicity_and_revocation_cleanup");
  w::Kernel replay;check(replay.restore_bytes(k.save_bytes())&&!replay.residential_right().active,"revocation history replays exactly");
  const auto revoked=k.save_bytes(),stopped=snapshot(use);check(w::revoke_residential_use(k,use,authored(1)).already_applied&&k.save_bytes()==revoked&&snapshot(use)==stopped,"revocation retry is exact");
 }
 {
  auto k=world();auto cmd=intent(k,"other/sleep");auto other=at(0);other.actor=other.authenticated_actor="aria";check(!k.execute_sleep(cmd,other).ok&&k.care_grants().empty(),"another authenticated resident cannot reserve exclusive Ben bed");
  c::ResidentUse use("ben");begin(k,use);check(w::advance_sleep_use(k,use,1,contact(use)).ok,"one rest tick");const auto before=snapshot(use);check(!w::wait_for_sleep_entry(k,use,2,entry(use)).ok&&snapshot(use)==before,"entry cannot follow positive rest progress");
  auto missing=sources();missing.residential_sha256=std::string(64,'0');check(!w::save_care_envelope(k,use,missing,{1,0}),"wrong registry hash refused");
  auto candidate=world();c::ResidentUse pending("ben");begin(candidate,pending);check(w::wait_for_sleep_entry(candidate,pending,1,entry(pending)).ok,"typed entry history");auto forged=pending.export_state();forged.version="3";check(!w::decode_care_document(w::encode_care_document(forged),true),"legacy parser rejects new sleep entry operation");
  money(k);pass("S11_exclusive_resident_and_entry_phase");
 }
 {
  for(int i=0;i<6;++i){auto k=world();c::ResidentUse use("ben");begin(k,use);auto bad=entry(use);switch(i){case 0:bad.freshly_observed=false;break;case 1:bad.floor_supported=false;break;case 2:bad.station_valid=false;break;case 3:bad.entry_advancing=false;break;case 4:bad.permission_valid=false;break;case 5:bad.reservation_valid=false;break;}
   const auto cb=snapshot(use);check(!w::wait_for_sleep_entry(k,use,1,bad).ok&&snapshot(use)==cb,"bad entry cannot fabricate progress or decay");
   auto lost=contact(use);lost.freshly_observed=false;check(w::advance_sleep_use(k,use,1,lost).outcome==c::Outcome::Interrupted&&use.needs().energy==7182&&!use.active(),"lost native rest contact interrupts with decay only");
  }pass("S05_distinct_entry_and_live_contact");
 }
 {
  auto k=world();c::ResidentUse use("ben");begin(k,use);check(w::wait_for_sleep_entry(k,use,1,entry(use)).ok,"saved entry");check(w::advance_sleep_use(k,use,2,contact(use)).ok,"saved rest");
  const auto encoded=w::save_care_envelope(k,use,sources(),{2,0});check(bool(encoded),"new paired save");const auto needs=use.needs();w::Kernel target;c::ResidentUse restored("ben");w::ClockMetadata clock;
  check(w::load_care_envelope(target,restored,*encoded,sources(),clock),"v6 restored");check(clock.tick==2&&c::same_need_values(restored.needs(),needs)&&target.residential_right().active,"right, clock and earned needs preserved");
  check(!restored.active()&&!target.care_grants().back().active&&restored.requests().back().end==c::End::AfterLoad,"historical observations never resume use");
  auto bad=sources();bad.sleep_recipe_sha256=std::string(64,'8');const auto before=target.save_bytes();check(!w::load_care_envelope(target,restored,*encoded,bad,clock)&&target.save_bytes()==before,"wrong sleep source atomically refused");
  auto missing=sources();missing.sleep_recipe_sha256.clear();check(!w::save_care_envelope(k,use,missing,{2,0}),"sleep history requires declared recipe source");money(target);pass("S06_persistence_quarantine_and_source_binding");
 }
 {
  const auto legacy=read(argv[1]);auto e=w::decode_care_envelope_document(legacy);check(e&&e->version=="5","actual baseline v5 fixture");const auto oldworld=w::decode(e->world_payload);const auto oldcare=w::decode_care_document(e->care_payload,true);check(bool(oldworld)&&bool(oldcare),"explicit old data read");
  w::Kernel k;c::ResidentUse use("ben");w::ClockMetadata clock;const auto original=k.save_bytes(),original_use=snapshot(use);
  check(!w::load_care_envelope(k,use,legacy,sources(),clock)&&k.save_bytes()==original&&snapshot(use)==original_use,"ordinary v6 load never falls back");
  check(w::import_v5_care_envelope(k,use,legacy,sources(),clock),"explicit exact v5 migration");
  check(clock.tick==103&&c::same_need_values(use.needs(),oldcare->needs)&&use.requests().back().progressed_ticks==3,"all needs, clock and partial progress preserved");
  check(!use.active()&&use.requests().back().end==c::End::AfterLoad&&!k.residential_right().active&&k.residential_right().activation_event_id==-1,"migration grants no new home or physical continuation");
  for(std::size_t i=0;i<oldworld->events.size();++i)check(w::detail::same_event(k.events()[i],oldworld->events[i]),"old financial/meal events preserved byte-exact");money(k,14,10,1);
  check(k.activate_residential(authored(clock.tick)).ok,"new assignment only subsequent explicit source event");
  auto smuggled=*e;auto forged=*oldworld;w::Event event;event.id=static_cast<w::Int>(forged.events.size())+1;event.tick=103;event.type="residential_owner_occupancy_activated";event.actor="ben";event.target=w::residential_assignment;event.subject=w::sleep_site;event.note=w::residential_registry_sha256;event.accepted=true;forged.events.push_back(event);forged.digest=w::detail::hash_bytes(forged.digest,w::detail::event_bytes(event));forged.last_tick=103;smuggled.world_payload=w::encode(forged);smuggled.world_digest=w::detail::hash_bytes(14695981039346656037ULL,smuggled.world_payload);
  const auto before=k.save_bytes();check(!w::import_v5_care_envelope(k,use,w::encode_care_envelope_document(smuggled),sources(),clock)&&k.save_bytes()==before,"rehashed v5 cannot smuggle residential semantics");pass("S07_explicit_migration_preserves_old_ledger");
 }
 {
  auto k=world();c::ResidentUse use("ben");begin(k,use);
  for(int i=0;i<7;++i){auto forged=k.journal();switch(i){case 0:forged.grants.back().energy_gain=63;break;case 1:forged.grants.back().duration_ticks=18;break;case 2:forged.grants.back().kind=w::CareKind::Meal;break;case 3:forged.residential.active=false;break;case 4:forged.residential.activation_event_id=999;break;case 5:forged.events[1].note=std::string(64,'0');break;case 6:forged.events.back().sleep_context->qualified_clip=false;break;}auto target=k;const auto before=target.save_bytes();check(!target.restore(forged)&&target.save_bytes()==before,"forged typed world replay refused atomically");}
  auto j=use.export_state();j.history.push_back({c::Op::SleepEntry,1,{},{},{},entry(use)});++j.needs.energy;check(!w::decode_care_document(w::encode_care_document(j)),"forged sleep entry cache refused");
  auto old=use.export_state();old.version="3";check(!w::decode_care_document(w::encode_care_document(old)),"v3 care never normal-loaded");pass("S08_strict_replay_and_no_version_alias");
 }
 {
  auto k=world();c::ResidentUse use("ben");begin(k,use);const auto before=use.needs();
  w::MealCommand meal{"meal/while-sleeping",w::meal_site,w::MealKind::PurchaseMeal,k.revision()};check(!w::begin_meal_use(k,use,meal,{"ben","ben",0,true,true,true,true,true}).ok,"meal cannot overlap sleep");money(k);
  check(w::cancel_care_use(k,use).ok&&c::same_need_values(use.needs(),before),"early cancel adds no benefit");
  meal.expected_revision=k.revision();meal.request_id="meal/after-sleep";check(w::begin_meal_use(k,use,meal,{"ben","ben",0,true,true,true,true,true}).ok,"released resident may eat");
  check(!w::begin_sleep_use(k,use,intent(k,"sleep/while-eating"),at(0)).ok,"sleep cannot overlap meal");money(k,14,10,1);pass("S09_shared_resident_reservation");
 }
 {
  auto k=world();c::ResidentUse use("ben");begin(k,use);
  for(std::size_t i=k.events().size();i<w::max_events-2;++i){w::Context counter{"aria","aria","cafe","1f","cafe1f_counter",0,true};check(k.execute({"capacity/"+std::to_string(i),"cafe_ground_commercial_v1",w::Action::offer_lease},counter).ok,"capacity fill preserves cleanup slots");}
  const auto before=k.save_bytes();w::Context counter{"aria","aria","cafe","1f","cafe1f_counter",0,true};check(!k.execute({"capacity/overflow","cafe_ground_commercial_v1",w::Action::offer_lease},counter).ok&&k.save_bytes()==before,"reserved sleep+revocation slots cannot be consumed");
  check(w::revoke_residential_use(k,use,authored()).ok&&k.events().size()==w::max_events&&!use.active()&&!k.residential_right().active&&w::care_matches_world(k,use),"both cleanup events fit at boundary");money(k);pass("S10_capacity_keeps_release_and_revocation");
 }
 std::cout<<"PASS_PORTABLE_SLEEP groups="<<groups<<" checks="<<checks<<" native_or_physical_contact=false\n";return 0;
}catch(const std::exception& e){std::cerr<<"FAIL "<<e.what()<<" after "<<checks<<" checks\n";return 1;}}
