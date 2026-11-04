// Domain/replay tests only. Native timing, physical reach and pixels are separate.
#include "../../../unreal/Source/LivingTownNative/ThirdParty/CafeWorldV3Envelope.hpp"
#include <fstream>
#include <iostream>
#include <iterator>
namespace w=living_town::cafe_world_v3;
namespace {
int checks=0,groups=0;
void check(bool value,const char* why){++checks;if(!value)throw std::runtime_error(why);}
void passed(const char* name){++groups;std::cout<<"CASE "<<name<<" PASS\n";}
w::Context at(const std::string& actor,w::Int tick){return {actor,actor,"cafe","1f","cafe1f_counter",tick,true};}
w::Receipt act(w::Kernel& k,const char* actor,w::Int tick,const std::string& id,w::Action action){return k.execute({id,k.terms().property_id,action},at(actor,tick));}
void money(const w::Kernel& k,w::Int aria,w::Int ben){check(k.coin("aria")==aria&&k.coin("ben")==ben,"exact wallets");check(k.verify_ledger()&&k.verify_care(),"single ledger/care reconcile");check(aria+ben==24,"money conserved");}
w::Kernel recurring(){w::Kernel k;check(k.activate_care({0,true}).ok,"enable paired policy");check(act(k,"aria",1,"rolling/offer",w::Action::offer_recurring_lease).ok,"owner explicit offer");w::Intent i{"rolling/agree",k.terms().property_id,w::Action::lease,"recurring_lease",k.offer().revision,k.title().revision};check(k.execute(i,at("ben",10)).ok,"observed recurring agreement");return k;}
w::CareBindings bindings(){w::CareBindings b;b.world.core_sha256=std::string(64,'a');b.world.fixture_sha256=std::string(64,'b');b.world.physical_sha256=std::string(64,'c');b.world.clip_sha256=std::string(64,'d');b.world.roster_sha256=std::string(64,'e');b.care_core_sha256="3968a82beab862fdd56054d1fe6cfe08aca3c7be41003a1fdc82abae56841d06";return b;}
w::CareBindings legacy_bindings(){auto b=bindings();b.world.core_sha256="4856df21feca1d51d357454cee2047e4de19e4ffa7c16aa57d459f6f0793e903";return b;}
std::string file(const char* path){std::ifstream f(path,std::ios::binary);if(!f)throw std::runtime_error("frozen old public-API fixture required");return std::string(std::istreambuf_iterator<char>(f),{});}
std::uint64_t bits(double fraction){std::uint64_t b=0;std::memcpy(&b,&fraction,sizeof(b));return b;}
}
int main(int argc,char** argv){try{
 check(argc==2,"one actual old-API fixture path required");const auto legacy=file(argv[1]);
 {
  w::Kernel k;check(act(k,"ben",10,"fixed/start",w::Action::lease).ok,"old default fixed lease");check(!k.recurring_lease(),"fixed is not silently recurring");money(k,16,8);check(k.reconcile_property_until(730).ok&&!k.lease().active&&k.operator_at(730)=="aria","fixed expiry unchanged");money(k,16,8);passed("R01_fixed_contract_preserved");
 }
 {
  w::Kernel k;check(!act(k,"ben",1,"forged/offer",w::Action::offer_recurring_lease).ok,"tenant cannot offer owner property");
  check(act(k,"aria",2,"owner/offer",w::Action::offer_recurring_lease).ok,"owner offers recurring terms");const auto before=k.save_bytes();
  check(!act(k,"ben",3,"not/agreed",w::Action::lease).ok&&k.save_bytes()==before,"old K intent cannot silently agree to recurring terms");
  w::Intent wrong{"stale/agree",k.terms().property_id,w::Action::lease,"recurring_lease",k.offer().revision+1,k.title().revision};check(!k.execute(wrong,at("ben",3)).ok&&k.save_bytes()==before,"stale observed offer refuses without money/event");
  wrong.expected_offer_revision=k.offer().revision;check(k.execute(wrong,at("ben",3)).ok,"explicit current agreement accepted");const auto paid=k.save_bytes();check(k.execute(wrong,at("ben",4)).already_applied&&k.save_bytes()==paid,"acceptance retry does not repay");wrong.agreed_lease_kind.clear();check(k.execute(wrong,at("ben",5)).reason=="malformed_agreement"&&k.save_bytes()==paid,"ill-formed cleared kind keeps no effects");wrong.expected_offer_revision=-1;wrong.expected_title_revision=-1;check(k.execute(wrong,at("ben",5)).reason=="request_id_conflict"&&k.save_bytes()==paid,"canonical fixed intent conflicts with recorded recurring agreement");money(k,16,8);passed("R02_explicit_consent_and_retry");
 }
 {
  auto k=recurring();const auto grant=k.lease().event_id;check(k.lease().end==730&&k.recurring_lease(),"first paid period");money(k,16,8);
  check(k.reconcile_property_until(729).already_applied,"early frame is not billable");const auto due=k.due_request(730);check(bool(due),"authority derives due request");
  check(k.reconcile_property_until(730).reason=="rent_paid"&&k.lease().end==1450&&k.lease().event_id==grant&&k.operator_at(730)=="ben","real payment continues same agreement");money(k,20,4);const auto once=k.save_bytes();
  check(k.reconcile_property_until(730).already_applied&&k.save_bytes()==once,"same tick does not repay");auto trusted=at("town",730);trusted.space_id.clear();trusted.floor_id.clear();trusted.interaction_id.clear();trusted.within_reach=false;check(k.execute(*due,trusted).already_applied&&k.save_bytes()==once,"old due receipt retry is idempotent");
  check(!k.can_operate("ben","cafe","2f",730),"rent never grants private upstairs");check(k.reconcile_property_until(1450).reason=="rent_paid","second periodic payment");money(k,24,0);check(k.reconcile_property_until(2170).reason=="rent_unpaid"&&!k.lease().active&&k.operator_at(2170)=="aria","unfunded next term ends without fake payment");money(k,24,0);passed("R03_paid_periods_and_nonpayment");
 }
 {
  auto k=recurring();check(act(k,"ben",20,"tenant/surrender",w::Action::end_lease).ok,"tenant ends future obligations");const auto ended=k.save_bytes();check(k.reconcile_property_until(5000).already_applied&&k.save_bytes()==ended,"ended agreement cannot accrue new rent");money(k,16,8);passed("R04_surrender_stops_dues");
 }
 {
  auto stepped=recurring(),batched=stepped;for(w::Int t=11;t<=3000;++t)check(stepped.reconcile_property_until(t).ok,"stepped clock valid");check(batched.reconcile_property_until(3000).ok&&stepped.save_bytes()==batched.save_bytes(),"batched catchup has identical scheduled events/rights/money");passed("R05_temporal_batch_equivalence");
 }
 {
  auto k=recurring(),clean=k;const auto before=k.save_bytes();check(!k.reconcile_property_until(1450,w::FaultPoint::after_payment_before_property,1).ok&&k.save_bytes()==before,"post-payment failure rolls back every crossed period");check(k.reconcile_property_until(1450).ok&&clean.reconcile_property_until(1450).ok&&k.save_bytes()==clean.save_bytes(),"retry equals clean branch");passed("R06_transaction_rollback");
 }
 {
  auto k=recurring();const auto before=k.save_bytes();auto due=*k.due_request(730);check(!k.execute(due,at("ben",730)).ok&&k.save_bytes()==before,"client cannot impersonate trusted collection");auto spoof=at("town",730);spoof.authenticated_actor="ben";check(!k.execute(due,spoof).ok&&k.save_bytes()==before,"spoofed authority cannot bill");due.request_id+="/changed";auto town=at("town",730);check(!k.execute(due,town).ok&&k.save_bytes()==before,"wrong derived due ID refused");passed("R07_no_client_financial_authority");
 }
 {
  auto k=recurring();check(k.reconcile_property_until(730).ok,"make actual rent history");auto j=k.journal();const auto good=k.save_bytes();
  for(auto& e:j.events){
   if(e.type=="property_rent_paid"){e.pay_event_id=1;break;}
  }
  check(!k.restore(j)&&k.save_bytes()==good,"forged payment reference cannot replay");j=k.journal();++j.lease.end;check(!k.restore(j)&&k.save_bytes()==good,"cached due tampering refused");j=k.journal();j.events.push_back(j.events.back());check(!k.restore(j)&&k.save_bytes()==good,"duplicate rent event refused");passed("R08_strict_financial_replay");
 }
 {
  auto k=recurring();w::care::ResidentUse use("ben");check(use.advance_idle_to(729),"legitimate near-due public care advancement");const auto saved=w::save_care_envelope(k,use,bindings(),{729,bits(.25)});check(bool(saved),"paired near-due save");w::Kernel loaded;w::care::ResidentUse resumed("ben");w::ClockMetadata clock;
  check(w::load_care_envelope(loaded,resumed,*saved,bindings(),clock)&&clock.tick==729&&clock.fraction_bits==bits(.25),"paired load retains exact due/fraction");check(loaded.reconcile_property_until(730).ok&&resumed.advance_idle_to(730),"one next authority second settles actual due");money(loaded,20,4);
  const auto after=w::save_care_envelope(loaded,resumed,bindings(),{730,0});check(bool(after),"save after payment");check(w::load_care_envelope(loaded,resumed,*after,bindings(),clock),"restore paid state");const auto once=loaded.save_bytes();check(loaded.reconcile_property_until(731).already_applied&&loaded.save_bytes()==once,"paid restore cannot double charge");passed("R09_paired_due_and_after_payment_load");
 }
 {
  w::Kernel k;w::care::ResidentUse use("ben");w::ClockMetadata clock{0,0};const auto empty=k.save_bytes();check(!w::load_care_envelope(k,use,legacy,legacy_bindings(),clock)&&k.save_bytes()==empty,"ordinary current load never falls back to old version");
  check(w::import_legacy_care_envelope(k,use,legacy,legacy_bindings(),clock),"actual frozen old public-API paired fixture imports");check(!k.recurring_lease()&&k.lease().active&&k.lease().start==10&&k.lease().end==730&&clock.tick==20&&clock.fraction_bits==bits(.25),"old fixed agreement/time untouched");money(k,16,8);
  const auto imported=k.save_bytes();auto bad=w::decode_care_envelope_document(legacy);check(bool(bad),"old fixture canonical");auto old_world=w::decode(bad->world_payload);check(bool(old_world),"old world canonical");for(auto& e:old_world->events)if(e.type=="property_lease_granted")e.offer_kind="recurring_lease";bad->world_payload=w::encode(*old_world);bad->world_digest=w::detail::hash_bytes(14695981039346656037ULL,bad->world_payload);
  check(!w::import_legacy_care_envelope(k,use,w::encode_care_envelope_document(*bad),legacy_bindings(),clock)&&k.save_bytes()==imported,"legacy tag cannot smuggle recurring consent even with recomputed checksums");auto foreign=legacy_bindings();foreign.world.physical_sha256=std::string(64,'f');check(!w::import_legacy_care_envelope(k,use,legacy,foreign,clock)&&k.save_bytes()==imported,"old source context remains strict");
  check(k.reconcile_property_until(730).ok&&!k.lease().active,"imported fixed term expires instead of billing");money(k,16,8);check(file(argv[1])==legacy,"old fixture not overwritten");passed("R10_explicit_legacy_fixed_contract_import");
 }
 {
  auto k=recurring();while(k.events().size()<w::max_events-2)check(!act(k,"ben",20,"capacity/"+std::to_string(k.events().size()),w::Action::offer_sale).ok,"refusal occupies actual journal");const auto before=k.save_bytes();check(!k.reconcile_property_until(730).ok&&k.save_bytes()==before,"capacity cannot publish partial rent or advance end");check(act(k,"ben",20,"capacity/end",w::Action::end_lease).ok&&!k.lease().active,"reserved terminal event remains available");passed("R11_capacity_keeps_atomicity_and_exit");
 }
 {
  w::Kernel k;check(act(k,"aria",1,"denied/offer",w::Action::offer_recurring_lease).ok,"owner consent before declined request");w::Intent i{"denied/reach",k.terms().property_id,w::Action::lease,"recurring_lease",k.offer().revision,k.title().revision};auto remote=at("ben",2);remote.within_reach=false;check(!k.execute(i,remote).ok,"real out-of-reach request is declined");const auto journal=k.save_bytes();w::Kernel loaded;check(loaded.restore_bytes(journal),"declined explicit agreement replays its observed terms");check(loaded.execute(i,at("ben",3)).already_applied&&loaded.save_bytes()==journal,"declined retry after load retains original outcome");passed("R12_declined_agreement_replay");
 }
 {
  const std::vector<w::Account> opening={{"aria",21,21},{"ben",3,3}};w::Kernel k(w::Terms{},opening);check(act(k,"aria",1,"poor/offer",w::Action::offer_recurring_lease).ok,"offer does not invent tenant capital");w::Intent i{"poor/agreement",k.terms().property_id,w::Action::lease,"recurring_lease",k.offer().revision,k.title().revision};check(!k.execute(i,at("ben",2)).ok&&!k.lease().active,"first unfunded payment refuses agreement");money(k,21,3);w::Kernel loaded(w::Terms{},opening);check(loaded.restore_bytes(k.save_bytes())&&loaded.execute(i,at("ben",3)).already_applied,"first-settlement refusal preserves explicit intent through replay");passed("R13_first_payment_refusal_replay");
 }
 {
  w::Kernel k;check(k.activate_care({0,true}).ok,"enable paired policy for ownership round trip");check(act(k,"aria",1,"aba/first-recurring",w::Action::offer_recurring_lease).ok,"first recurring offer");
  const w::Intent stale{"aba/stale-consent",k.terms().property_id,w::Action::lease,"recurring_lease",k.offer().revision,k.title().revision};
  check(act(k,"aria",2,"aba/sale-to-ben",w::Action::offer_sale).ok&&act(k,"ben",3,"aba/buy-by-ben",w::Action::buy).ok,"first actual deed transfers title and money");money(k,24,0);check(k.title().revision==1,"first deed advances title generation");
  check(act(k,"ben",4,"aba/sale-to-aria",w::Action::offer_sale).ok&&act(k,"aria",5,"aba/buy-by-aria",w::Action::buy).ok,"second actual deed returns title and money");money(k,12,12);check(k.title().revision==2,"return deed cannot reset title generation");
  check(act(k,"aria",6,"aba/new-recurring",w::Action::offer_recurring_lease).ok,"new recurring offer after round trip");check(k.offer().revision==stale.expected_offer_revision&&k.offer().title_revision!=stale.expected_title_revision,"released local offer counter restarts but title generation differs");
  const auto before=k.save_bytes();check(k.execute(stale,at("ben",7)).reason=="recurring_agreement_required"&&k.save_bytes()==before,"old consent cannot charge against a same-number offer after sale ABA");money(k,12,12);
  const w::Intent current{"aba/current-consent",k.terms().property_id,w::Action::lease,"recurring_lease",k.offer().revision,k.title().revision};check(k.execute(current,at("ben",7)).ok&&k.recurring_lease(),"newly observed full generation accepts agreement");money(k,16,8);
  w::care::ResidentUse use("ben");check(use.advance_idle_to(8),"public care clock before paired save");const auto saved=w::save_care_envelope(k,use,bindings(),{8,bits(.25)});check(bool(saved),"save after round-trip consent");w::Kernel restored;w::care::ResidentUse restored_use("ben");w::ClockMetadata clock;check(w::load_care_envelope(restored,restored_use,*saved,bindings(),clock)&&restored.title().revision==2&&restored.save_bytes()==k.save_bytes(),"paired replay preserves both deeds and accepted generation");
  const auto paid=restored.save_bytes();check(restored.execute(stale,at("ben",9)).reason=="recurring_agreement_required"&&restored.save_bytes()==paid,"stale generation remains rejected after load");check(restored.execute(current,at("ben",9)).already_applied&&restored.save_bytes()==paid,"accepted full-generation retry after load cannot repay");
  auto changed=current;changed.expected_title_revision=0;check(restored.execute(changed,at("ben",9)).reason=="request_id_conflict"&&restored.save_bytes()==paid,"retry identity includes title generation");auto forged=restored.journal();for(auto& e:forged.events)if(e.type=="property_lease_granted")e.title_revision=0;check(!restored.restore(forged)&&restored.save_bytes()==paid,"recomputed title cache cannot disguise a forged consent generation");passed("R14_ownership_ABA_and_paired_replay");
 }
 std::cout<<"PASS_PORTABLE_RECURRING_LEASE checks="<<checks<<" groups="<<groups<<" native_or_pixels=false\n";return 0;
}catch(const std::exception& e){std::cerr<<"FAIL "<<e.what()<<"\n";return 1;}}
