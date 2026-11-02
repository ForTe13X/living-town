// Portable CPU meal/grant/replay cases; native contact, clips and UI remain pending.
#include "../../../unreal/Source/LivingTownNative/ThirdParty/CafeWorldV3Envelope.hpp"
#include "../../../unreal/Source/LivingTownNative/ThirdParty/CafeBackendV3.hpp"
#include <iostream>

namespace w=living_town::cafe_world_v3;
namespace v2=living_town::cafe_property_v2;
namespace {
int checks=0, groups=0;
void check(bool yes,const char* why) {++checks;if(!yes)throw std::runtime_error(why);}
void passed(const char* name) {++groups;std::cout<<"CASE "<<name<<" PASS\n";}
w::MealContext observed(const char* who="ben",w::Int tick=1) {
    // Synthetic trusted-context INPUT, not a measurement of native geometry.
    return {who,who,tick,true,true,true,true,true};
}
w::MealCommand meal(const w::Kernel& k,const char* id="meal/1",w::MealKind kind=w::MealKind::PurchaseMeal) {
    return {id,w::meal_site,kind,k.revision()};
}
w::Context counter(const char* who,w::Int tick) {return {who,who,"cafe","1f","cafe1f_counter",tick,true};}
w::Receipt property(w::Kernel& k,const char* who,w::Int tick,const char* id,w::Action action) {
    return k.execute({id,"cafe_ground_commercial_v1",action},counter(who,tick));
}
w::Kernel enabled() {w::Kernel k;check(k.activate_care({0,true}).ok,"explicit activation");return k;}
void release(w::Kernel& k,w::Int tick=2) {
    const auto g=k.care_grants().back();check(k.release_grant({g.resident,g.event_id,tick,w::ReleaseReason::Cancelled}).ok,"cancel owned grant");
}
w::SourceBindings bindings() {
    // Deliberately synthetic CPU fixture fingerprints. No native asset qualifies.
    w::SourceBindings b;b.core_sha256=std::string(64,'a');b.fixture_sha256=std::string(64,'b');
    b.physical_sha256=std::string(64,'c');b.clip_sha256=std::string(64,'d');b.roster_sha256=std::string(64,'e');return b;
}
std::uint64_t bits(double fraction) {std::uint64_t out=0;std::memcpy(&out,&fraction,sizeof(out));return out;}
void same_money(const w::Kernel& k,w::Int aria,w::Int ben) {
    check(k.coin("aria")==aria&&k.coin("ben")==ben,"wallets exact");check(k.verify_ledger(),"one coin book reconciles");check(k.verify_care(),"stock/grants reconcile");
}
void refused_load(const w::Journal& altered,const w::Kernel& guard) {
    auto live=guard;const auto before=live.save_bytes();check(!live.restore(altered),"altered journal refused");check(live.save_bytes()==before,"failed restore leaves exact authority");
}
w::CareBindings care_bindings() {return {bindings(),std::string(64,'6')};}
w::care::Contact care_contact(const w::care::ResidentUse& use) {
    // Synthetic observation only. No native pose, prop or contact is asserted.
    const auto& g=use.active()->grant;return {g.resident_id,g.site_id,g.grant_id,true,true,true,true,true};
}
}
int main() {
    try {
        {
            w::Kernel k;const auto before=k.save_bytes();check(!k.care_enabled()&&k.rations()==0,"default care explicitly disabled");
            check(!k.activate_care({0,false}).ok&&k.save_bytes()==before,"no implicit opening stock");
            check(k.activate_care({0,true}).ok&&k.rations()==2,"declared two-ration pilot activation");
            const auto active=k.save_bytes();check(k.activate_care({1,true}).already_applied&&k.save_bytes()==active,"activation not repeated");
            same_money(k,12,12);passed("M00_explicit_opening");
        }
        {
            auto k=enabled();const auto cmd=meal(k);const auto r=k.execute_meal(cmd,observed());check(r.ok&&r.reason=="Paid"&&r.event_id==4,"paid receipt comes from actual terminal event");
            same_money(k,14,10);check(k.rations()==1&&k.events().size()==4&&k.care_grants().size()==1,"one stock and grant");
            const auto& pay=k.events()[1];const auto& stock=k.events()[2];const auto& use=k.events()[3];const auto& g=k.care_grants()[0];
            check(pay.type=="pay"&&pay.id==2&&pay.amt==2&&pay.actor=="ben"&&pay.target=="aria"&&pay.txid=="meal/meal/1","unchanged private transfer emitted exact pay");
            check(stock.type=="meal_stock_consumed"&&stock.amount==1&&stock.id==3,"actual stock event");
            check(use.type=="care_meal_granted"&&use.pay_event_id==2&&use.stock_event_id==3,"actual links only");
            check(g.event_id==4&&g.resident=="ben"&&g.provider=="aria"&&g.active&&g.duration_ticks==18&&g.hunger_gain==50&&g.fun_gain==3,"owned typed authored grant, no need mutation");
            check(!k.interrupt_loaded_grants(1),"load-specific API does not invent a load for a fresh live grant");
            const auto before=k.save_bytes();const auto retry=k.execute_meal(cmd,observed("ben",8));check(retry.ok&&retry.already_applied&&k.save_bytes()==before,"late intent replay is no second pay/stock/grant");
            auto changed=cmd;changed.expected_revision=k.revision();check(k.execute_meal(changed,observed("ben",8)).reason=="request_id_conflict"&&k.save_bytes()==before,"immutable revision conflict");
            release(k,9);const auto released=k.save_bytes();auto historical=observed("ben",0);historical.permission=false;
            check(k.execute_meal(cmd,historical).already_applied&&k.save_bytes()==released,"historical receipt is not fresh physical access");
            check(k.release_grant({"ben",4,10,w::ReleaseReason::Cancelled}).already_applied&&k.save_bytes()==released,"release once, no refund");same_money(k,14,10);passed("M01_cost_stock_links_late_idempotence");
        }
        {
            auto k=enabled();check(k.execute_meal(meal(k),observed("aria")).reason=="OwnStock","own operator uses stock without self pay");
            check(k.events().size()==3&&!k.events().back().pay_event_id&&k.care_grants().back().funding=="OwnStock","no phantom paid claim");same_money(k,12,12);passed("M02_operator_own_stock");
        }
        {
            auto k=enabled();
            for(int i=0;i<3;++i) {
                const auto id="public/"+std::to_string(i);const auto r=k.execute_meal(meal(k,id.c_str(),w::MealKind::PublicMeal),observed("ben",1+i*2));
                check(r.ok&&r.reason==(i<2?"PublicStock":"PublicRelief"),"public provision explicitly funded");
                check(!k.events().back().pay_event_id,"public is never paid");release(k,2+i*2);
            }
            check(k.rations()==0&&k.care_grants().size()==3,"relief does not create/consume phantom stock");
            const auto shortage=std::count_if(k.events().begin(),k.events().end(),[](const auto& e){return e.type=="public_meal_shortage";});check(shortage==1,"one actual public shortage");
            check(k.execute_meal(meal(k,"paid/empty"),observed("ben",7)).reason=="meal_stock_unavailable"&&k.rations()==0,"empty stock never becomes a phantom purchase");
            same_money(k,12,12);passed("M03_nonpunitive_public_shortage");
        }
        {
            for(int i=0;i<5;++i) {
                auto k=enabled();auto c=observed();switch(i){case 0:c.fresh=false;break;case 1:c.correct_floor=false;break;case 2:c.reachable=false;break;case 3:c.permission=false;break;case 4:c.qualified_clip=false;break;}
                const auto cmd=meal(k);check(!k.execute_meal(cmd,c).ok,"trusted observation refusal");
                check(k.rations()==2&&k.care_grants().empty()&&k.events().size()==2&&k.events().back().type=="meal_refused","refusal commits no supply/payment/grant");
                const auto before=k.save_bytes();check(k.execute_meal(cmd,observed()).already_applied&&k.save_bytes()==before,"refusal receipt also idempotent");same_money(k,12,12);
            }
            auto k=enabled();auto c=observed();c.authenticated_actor="aria";const auto before=k.save_bytes();check(k.execute_meal(meal(k),c).reason=="unauthenticated_actor"&&k.save_bytes()==before,"identity spoof no append");
            auto bad=meal(k);bad.site_id="other_site";check(k.execute_meal(bad,observed()).reason=="unknown_meal_site","unbound fixture refused");
            passed("M04_permission_contact_clip_are_preconditions");
        }
        {
            auto k=enabled();check(k.execute_meal(meal(k),observed()).ok,"one active owned grant");
            check(k.execute_meal(meal(k,"busy/1"),observed("ben",2)).reason=="resident_busy","resident cannot acquire another use");
            check(k.execute_meal(meal(k,"occupied/1",w::MealKind::PublicMeal),observed("aria",3)).reason=="meal_site_occupied","second resident cannot share one reserved site");
            check(k.rations()==1&&k.care_grants().size()==1&&k.care_grants()[0].active,"refusal cannot consume or replace grant ownership");
            same_money(k,14,10);passed("M04b_owned_resident_and_site_reservation");
        }
        {
            auto k=enabled();auto stale=meal(k);stale.expected_revision=0;check(k.execute_meal(stale,observed()).reason=="stale_world_revision","stale UI intent refused");
            const auto snapshot=k.save_bytes();check(k.execute_meal(stale,observed("ben",4)).already_applied&&k.save_bytes()==snapshot,"cached stale refusal");
            w::Kernel later;check(later.activate_care({10,true}).ok,"later trusted clock");const auto before=later.save_bytes();
            check(later.execute_meal(meal(later),observed("ben",9)).reason=="invalid_command_tick"&&later.save_bytes()==before,"stale authority context no append");
            check(later.execute_meal(meal(later),observed("ben",w::max_tick+1)).reason=="invalid_command_tick","bounded clock");
            passed("M05_stale_command_and_context");
        }
        {
            w::Kernel k(w::Terms{},{{"aria",12,12},{"ben",1,1}});check(k.activate_care({0,true}).ok,"low wallet world");
            check(k.execute_meal(meal(k),observed()).reason=="meal_settlement_rejected"&&k.rations()==2&&k.care_grants().empty(),"unaffordable purchase not fake success");
            check(k.execute_meal(meal(k,"relief/1",w::MealKind::PublicMeal),observed("ben",2)).ok,"explicit public option still available");same_money(k,12,1);
            w::Kernel rich(w::Terms{},{{"aria",std::numeric_limits<w::Int>::max(),std::numeric_limits<w::Int>::max()},{"ben",12,12}});check(rich.activate_care({0,true}).ok,"overflow fixture opening");
            check(rich.execute_meal(meal(rich),observed()).reason=="meal_settlement_rejected"&&rich.rations()==2,"recipient overflow refused");same_money(rich,std::numeric_limits<w::Int>::max(),12);passed("M06_insufficient_or_overflow_not_paid");
        }
        {
            auto k=enabled();check(property(k,"ben",1,"lease/1",w::Action::lease).ok,"source paid lease");
            check(k.execute_meal(meal(k),observed("aria",2)).ok&&k.care_grants().back().provider=="ben","payee is current operator, not fixed owner");same_money(k,14,10);release(k,3);
            const auto before=k.save_bytes();check(k.execute_meal(meal(k,"due/meal"),observed("ben",721)).reason=="property_expiry_required"&&k.save_bytes()==before,"natural expiry must precede meal");
            const auto due=k.expiry_request(721);check(due.has_value(),"due request source generated");auto c=counter("town",721);c.within_reach=false;c.space_id.clear();c.floor_id.clear();c.interaction_id.clear();check(k.execute(*due,c).ok,"trusted natural expiry");
            check(k.execute_meal(meal(k,"after/expiry"),observed("ben",722)).ok&&k.care_grants().back().provider=="aria","payee changes after expiry");same_money(k,16,8);passed("M07_shared_property_operator_and_expiry");
        }
        {
            for(auto fault:{w::MealFault::AfterPayment,w::MealFault::AfterStock,w::MealFault::AfterGrant}) {
                auto k=enabled();const auto cmd=meal(k);const auto before=k.save_bytes();const auto r=k.execute_meal(cmd,observed(),fault);
                check(!r.ok&&r.reason.find("technical_failure:")==0&&k.save_bytes()==before,"fault discards entire candidate");
                check(k.care_grants().empty()&&k.rations()==2,"no stock/grant half publication");same_money(k,12,12);
                check(k.execute_meal(cmd,observed()).ok,"same intent reusable after technical rollback");auto clean=enabled();check(clean.execute_meal(cmd,observed()).ok&&clean.save_bytes()==k.save_bytes(),"retry exact clean branch");
            }
            passed("M08_postpay_stock_grant_faults_atomic");
        }
        {
            auto k=enabled();const auto cmd=meal(k);check(k.execute_meal(cmd,observed()).ok,"save grant");
            const auto raw=w::save_envelope(k,bindings(),{7,bits(0.25)},"aria");check(raw.has_value(),"single canonical envelope");
            w::Kernel live;w::ClockMetadata clock{0,0};check(w::load_envelope(live,*raw,bindings(),clock),"complete replay before one publication");
            check(clock.tick==7&&clock.fraction_bits==bits(0.25)&&live.save_bytes()==k.save_bytes(),"clock/fraction/full payload exact");
            check(live.loaded_grants_require_interruption(),"saved contact never fresh permission");const auto before=live.save_bytes();
            check(live.execute_meal(cmd,observed("ben",7)).already_applied&&live.save_bytes()==before,"replay after load cannot repay");
            check(live.execute_meal(meal(live,"new/while_loaded"),observed("ben",7)).reason=="loaded_grants_require_interruption"&&live.save_bytes()==before,"no new grant until interrupted");
            check(live.interrupt_loaded_grants(7)&&!live.care_grants().back().active,"one load interruption releases history reservation");
            const auto stopped=live.save_bytes();check(live.interrupt_loaded_grants(7)&&live.save_bytes()==stopped,"interruption idempotent");
            check(live.execute_meal(meal(live,"new/after_load"),observed("ben",8)).ok,"fresh qualified-context input may start another meal");same_money(live,16,8);passed("M09_unified_envelope_and_load_quarantine");
        }
        {
            auto k=enabled();check(k.execute_meal(meal(k),observed()).ok,"tamper source");
            for(int i=0;i<8;++i) {auto j=k.journal();switch(i){case 0:++j.stock_current;break;case 1:--j.events[1].amt.value();break;case 2:j.grants[0].pay_event_id=99;break;case 3:j.events[3].stock_event_id=2;break;case 4:j.grants[0].hunger_gain=99;break;case 5:j.events[3].note="PublicRelief";break;case 6:j.events.insert(j.events.begin()+2,j.events[1]);break;case 7:j.events[3].meal_command->expected_revision=0;break;}refused_load(j,k);}
            const auto good=w::save_envelope(k,bindings(),{4,0});check(good.has_value(),"tamper envelope source");
            for(int i=0;i<6;++i) {auto e=*w::decode_envelope_document(*good);switch(i){case 0:e.version="2";break;case 1:e.bindings.fixture_sha256=std::string(64,'f');break;case 2:e.clock.tick=0;break;case 3:e.clock.fraction_bits=0x7ff8000000000000ULL;break;case 4:{auto j=k.journal();++j.stock_current;e.payload=w::encode(j);e.payload_digest=w::detail::hash_bytes(14695981039346656037ULL,e.payload);break;}case 5:e.saved_persona="town";break;}
                auto live=k;const auto before=live.save_bytes();w::ClockMetadata c{9,bits(0.5)};check(!w::load_envelope(live,w::encode_envelope_document(e),bindings(),c)&&live.save_bytes()==before&&c.tick==9&&c.fraction_bits==bits(0.5),"even recomputed checksums cannot bypass typed replay/binding/clock rules");
            }
            auto live=k;w::ClockMetadata c;check(!w::load_envelope(live,*good+"x",bindings(),c),"trailing envelope bytes refused");check(!live.restore_bytes(std::string(w::max_journal_bytes+1,'x')),"oversize bounded");passed("M10_corruption_before_publication");
        }
        {
            v2::Kernel original;const auto at=[](const char* who,v2::Int tick){return v2::Context{who,who,"cafe","1f","cafe1f_counter",tick,true};};
            check(original.execute({"sale/1","cafe_ground_commercial_v1",v2::Action::offer_sale},at("aria",10)).ok,"legacy offer");check(original.execute({"buy/1","cafe_ground_commercial_v1",v2::Action::buy},at("ben",11)).ok,"legacy paid deed");
            const auto legacy=original.save_bytes();w::Kernel k;check(k.import_v2_payload(legacy,20,bits(0.25)),"explicit strict V2 import");
            check(!k.care_enabled()&&k.rations()==0&&k.care_grants().empty()&&k.journal().v2_origin==legacy,"import no invented care/stock/history");same_money(k,24,0);
            check(property(k,"ben",19,"too_early/1",w::Action::offer_lease).reason=="invalid_command_tick","import world-clock floor retained");
            check(k.execute_meal(meal(k),observed("ben",20)).reason=="care_disabled","import does not silently activate");
            check(k.activate_care({21,true}).ok&&k.execute_meal(meal(k,"public/import",w::MealKind::PublicMeal),observed("ben",22)).ok,"explicit versioned activation and public care");same_money(k,24,0);
            w::Kernel reopened;check(reopened.restore_bytes(k.save_bytes())&&reopened.save_bytes()==k.save_bytes(),"lineage plus new branch strict replay");
            check(!original.restore_bytes(k.save_bytes()),"old V2 never accepts V3");w::Kernel wrong;check(!wrong.restore_bytes(legacy),"V2 requires explicit import, not auto schema acceptance");
            const auto before=wrong.save_bytes();check(!wrong.import_v2_payload(legacy,10,0)&&wrong.save_bytes()==before,"invalid import clock atomic");check(!wrong.import_v2_payload(legacy,20,0x7ff8000000000000ULL),"invalid import fraction");
            passed("M11_v2_import_disabled_care_and_backward_reader");
        }
        {
            auto k=enabled();const auto cmd=meal(k);check(k.execute_meal(cmd,observed()).ok,"shared ID fixture grant");
            const auto before=k.save_bytes();check(property(k,"aria",2,"meal/1",w::Action::offer_sale).reason=="request_id_conflict"&&k.save_bytes()==before,"property cannot reuse meal ID");release(k,2);
            check(property(k,"aria",3,"property/once",w::Action::offer_sale).ok,"property ID created");const auto after=k.save_bytes();check(k.execute_meal(meal(k,"property/once"),observed("ben",3)).reason=="request_id_conflict"&&k.save_bytes()==after,"meal cannot reuse property ID");passed("M12_single_request_identity_domain");
        }
        {
            auto k=enabled();check(k.execute_meal(meal(k),observed("ben",0)).ok,"reserved grant");
            for(std::size_t i=k.events().size();i<w::max_events-1;++i) {const auto id="fill/"+std::to_string(i);check(property(k,"aria",0,id.c_str(),w::Action::offer_lease).ok,"fill keeps release slot");}
            const auto before=k.save_bytes();check(!property(k,"aria",0,"beyond/reserve",w::Action::offer_lease).ok&&k.save_bytes()==before,"property cannot spend grant release reservation");
            release(k,0);check(k.events().size()==w::max_events,"reserved release still commits at capacity");same_money(k,14,10);passed("M13_capacity_preserves_release");
        }
        {
            auto k=enabled();check(property(k,"ben",0,"lease/full",w::Action::lease).ok,"lease and grant reservation fixture");
            check(k.execute_meal(meal(k),observed("aria",0)).ok,"active care before full journal");
            for(std::size_t i=k.events().size();i<w::max_events-2;++i) {const auto id="refusal_fill/"+std::to_string(i);check(property(k,"aria",0,id.c_str(),w::Action::offer_sale).reason=="lease_must_end_first","bounded business refusals preserve lease/grant slots");}
            const auto due=k.expiry_request(720);check(due.has_value(),"capacity due expiry");auto c=counter("town",720);c.within_reach=false;c.space_id.clear();c.floor_id.clear();c.interaction_id.clear();
            check(k.execute(*due,c).ok&&k.events().size()==w::max_events-1,"expiry consumes its own reserved slot");
            release(k,720);check(k.events().size()==w::max_events,"release consumes final reserved slot");same_money(k,14,10);passed("M13b_capacity_preserves_expiry_and_release");
        }
        {
            w::Kernel legacy_scope;
            for(std::size_t i=0;i<w::max_events-2;++i) {const auto id="legacy_fill/"+std::to_string(i);check(property(legacy_scope,"aria",0,id.c_str(),w::Action::offer_lease).ok,"unchanged disabled-care old scope can fill");}
            check(property(legacy_scope,"ben",0,"legacy_full_lease",w::Action::lease).ok,"old core property contract remains allowed");
            check(legacy_scope.events().size()==w::max_events&&legacy_scope.lease().active,"unreserved old core boundary");
            check(!w::save_envelope(legacy_scope,bindings(),{0,0}),"envelope refuses unreplayable future-expiry capacity, matching native V2 guard");passed("M13c_envelope_pending_capacity_guard");
        }
        {
            namespace b=living_town::cafe_backend_v3;
            for(int mask=0;mask<8;++mask) {b::Flags f{(mask&1)!=0,(mask&2)!=0,(mask&4)!=0,false};const auto result=b::select(f);const int count=((mask&1)?1:0)+((mask&2)?1:0)+((mask&4)?1:0);
                check((result==b::Backend::Invalid)==(count>1),"all flag conflicts select no authority");
                const int books=(result==b::Backend::LegacyV1?1:0)+(result==b::Backend::PropertyV2?1:0)+(result==b::Backend::WorldV3?1:0);check(books==(count>1?0:1),"exactly one chosen authority");}
            check(b::select({})==b::Backend::LegacyV1&&b::select({true,false,false,false})==b::Backend::PropertyV2,"old default/explicit V2 preserved");
            check(b::select({false,true,false,true})==b::Backend::Invalid,"worker preview cannot activate V3");
            check(b::can_activate(b::Backend::WorldV3,b::ExactMode::WorldV3,true,false)&&!b::can_activate(b::Backend::WorldV3,b::ExactMode::PropertyV2,true,false)&&!b::can_activate(b::Backend::WorldV3,b::ExactMode::WorldV3,false,false),"exact standalone mode preflight");passed("M14_all_entrypoint_selector_contract");
        }
        {
            auto k=enabled();check(k.execute_meal(meal(k),observed("ben",1)).ok,"late-release fixture has one owned grant");
            check(k.care_grants().back().event_id==4,"actual initial grant event4");
            const w::TrustedRelease original{"ben",4,2,w::ReleaseReason::Cancelled};
            const auto first=k.release_grant(original);
            check(first.ok&&!first.already_applied&&first.event_id==5&&k.care_grants().back().release_event_id==5,"first release records actual event5");
            check(property(k,"aria",9,"late-release/property",w::Action::offer_lease).ok&&k.last_tick()==9&&k.events().back().id==6,"later property event advances authority time");
            const auto before=k.save_bytes();const auto count=k.events().size();const auto retry=k.release_grant(original);
            check(retry.ok&&retry.already_applied&&retry.reason=="grant_already_released"&&retry.event_id==first.event_id,"original old-tick release returns cached exact event");
            check(k.save_bytes()==before&&k.events().size()==count&&!k.care_grants().back().active&&k.rations()==1,"late release changes no journal, reservation or stock");
            same_money(k,14,10);
            for(int i=0;i<3;++i) {
                auto bad=original;switch(i){case 0:bad.tick=-1;break;case 1:bad.tick=w::max_tick+1;break;case 2:bad.reason=static_cast<w::ReleaseReason>(99);break;}
                const auto refused=k.release_grant(bad);
                check(!refused.ok&&!refused.already_applied&&refused.reason=="invalid_release"&&refused.event_id==-1,"invalid shape still refuses before released-grant cache");
                check(k.save_bytes()==before,"invalid release shape changes nothing");
            }
            auto wrong_owner=original;wrong_owner.resident="aria";
            check(k.release_grant(wrong_owner).reason=="unknown_care_grant"&&k.save_bytes()==before,"cached release requires owned resident/grant identity");
            check(k.execute_meal(meal(k,"late-release/new-meal"),observed("ben",10)).ok&&k.care_grants().back().event_id==9,"new active grant has actual event9");
            check(property(k,"aria",11,"late-release/later-property",w::Action::offer_sale).ok&&k.events().back().id==10,"new grant remains active across later property event");
            const auto active=k.save_bytes();const auto stale=k.release_grant({"ben",9,10,w::ReleaseReason::Cancelled});
            check(!stale.ok&&!stale.already_applied&&stale.reason=="invalid_release"&&stale.event_id==-1,"NEW active release cannot use a stale authority tick");
            check(k.save_bytes()==active&&k.care_grants().back().active&&k.rations()==0,"stale NEW release preserves complete active state");
            same_money(k,16,8);
            const auto current=k.release_grant({"ben",9,11,w::ReleaseReason::Cancelled});
            check(current.ok&&!current.already_applied&&current.event_id==11&&!k.care_grants().back().active,"fresh active release commits actual event11");
            same_money(k,16,8);passed("M15_late_release_replay_and_new_release_clock");
        }
        {
            auto k=enabled();check(k.execute_meal(meal(k),observed("ben",0)).ok,"completion source grant");
            const auto before=k.save_bytes();
            check(k.release_grant({"ben",4,17,w::ReleaseReason::Completed,18}).reason=="meal_completion_not_elapsed"&&k.save_bytes()==before,"time alone not elapsed");
            check(k.release_grant({"ben",4,18,w::ReleaseReason::Completed,17}).reason=="meal_completion_not_elapsed"&&k.save_bytes()==before,"full authored progress required");
            check(k.release_grant({"ben",4,18,w::ReleaseReason::Cancelled,18}).reason=="invalid_release"&&k.save_bytes()==before,"cancel cannot carry completion evidence");
            const w::TrustedRelease complete{"ben",4,18,w::ReleaseReason::Completed,18};const auto receipt=k.release_grant(complete);
            check(receipt.ok&&!receipt.already_applied&&!k.care_grants().back().active&&k.events().back().note=="completed"&&k.events().back().amount==18,"truthful distinct completion event");
            check(property(k,"aria",25,"after-completion/property",w::Action::offer_sale).ok,"later authority event");const auto done=k.save_bytes();
            check(k.release_grant(complete).already_applied&&k.save_bytes()==done,"original completion receipt replays after later time");
            check(k.release_grant({"ben",4,25,w::ReleaseReason::Cancelled}).reason=="release_reason_conflict"&&k.save_bytes()==done,"completion cannot masquerade as cancellation");
            w::Kernel restored;check(restored.restore_bytes(done)&&restored.save_bytes()==done,"completed event and elapsed evidence replay");
            auto bad=k.journal();bad.events[4].amount=17;refused_load(bad,k);
            bad=k.journal();bad.events[4].note="cancelled";refused_load(bad,k);
            same_money(k,14,10);passed("M16_completed_release_distinct_and_replayable");
        }
        {
            auto k=enabled();w::care::ResidentUse use("ben");const auto command=meal(k);const auto begin=w::begin_meal_use(k,use,command,observed("ben",0));
            check(begin.ok&&use.active()&&w::care_matches_world(k,use),"world grant and care begin commit together");
            for(w::Int tick=1;tick<=18;++tick){const auto r=w::advance_meal_use(k,use,tick,care_contact(use));check(r.ok&&r.outcome==(tick==18?w::care::Outcome::Completed:w::care::Outcome::Progress),"one actual supplied tick per progression");}
            check(!use.active()&&use.needs().fun==7500&&k.events().back().note=="completed"&&k.events().back().amount==18,"authored fun exactly3 and completion releases site");
            const auto world_before=k.save_bytes();const auto care_before=w::encode_care_document(use.export_state());
            check(w::begin_meal_use(k,use,command,observed("ben",18)).already_applied&&!use.active(),"late accepted request is no restart");
            check(k.save_bytes()==world_before&&w::encode_care_document(use.export_state())==care_before,"late receipt changes neither side");
            check(k.rations()==1&&use.requests().size()==1&&w::care_matches_world(k,use),"one ration and one care history");same_money(k,14,10);
            const auto bytes=w::save_care_envelope(k,use,care_bindings(),{18,0});check(bytes.has_value(),"completed paired state saves");
            w::Kernel target;w::care::ResidentUse loaded("ben");w::ClockMetadata clock;
            check(w::load_care_envelope(target,loaded,*bytes,care_bindings(),clock)&&target.save_bytes()==k.save_bytes()&&w::encode_care_document(loaded.export_state())==care_before,"completed load is not relabelled AfterLoad");
            passed("M17_paired_completion_effects_exactly_once");
        }
        {
            auto k=enabled();w::care::ResidentUse use("ben");const auto command=meal(k);check(w::begin_meal_use(k,use,command,observed("ben",0)).ok,"partial source meal");
            for(w::Int tick=1;tick<=6;++tick)check(w::advance_meal_use(k,use,tick,care_contact(use)).ok,"partial ticks");
            const auto earned=use.needs();check(earned.fun==7300&&use.active()->elapsed==6,"partial authored effect");
            const auto saved=w::save_care_envelope(k,use,care_bindings(),{6,bits(.25)});check(saved.has_value(),"one paired durable document");
            w::Kernel restored;w::care::ResidentUse reopened("ben");w::ClockMetadata clock;
            check(w::load_care_envelope(restored,reopened,*saved,care_bindings(),clock),"both documents validated before publication");
            check(clock.tick==6&&clock.fraction_bits==bits(.25)&&w::care::same_need_values(earned,reopened.needs()),"clock/fraction/all four earned needs restore");
            check(!reopened.active()&&!restored.care_grants().back().active&&restored.events().back().note=="after_load"&&reopened.requests().back().end==w::care::End::AfterLoad,"old use/reservation invalidated together");
            const auto before=restored.save_bytes();const auto care_before=w::encode_care_document(reopened.export_state());
            check(w::begin_meal_use(restored,reopened,command,observed("ben",6)).already_applied&&!reopened.active()&&restored.save_bytes()==before&&w::encode_care_document(reopened.export_state())==care_before,"load replay earns no extra effect/payment");
            const auto stopped=w::save_care_envelope(restored,reopened,care_bindings(),clock);check(stopped.has_value(),"interrupted load state is itself durable");
            w::Kernel again;w::care::ResidentUse again_use("ben");w::ClockMetadata again_clock;
            check(w::load_care_envelope(again,again_use,*stopped,care_bindings(),again_clock)&&again.save_bytes()==before&&w::encode_care_document(again_use.export_state())==care_before,"already-invalidated load appends nothing");
            same_money(restored,14,10);check(restored.rations()==1,"load no refund/replenishment");passed("M18_partial_progress_durable_load_quarantine");
        }
        {
            auto k=enabled();w::care::ResidentUse use("ben");const auto command=meal(k);check(w::begin_meal_use(k,use,command,observed("ben",0)).ok,"cancel source");
            for(w::Int tick=1;tick<=3;++tick)check(w::advance_meal_use(k,use,tick,care_contact(use)).ok,"cancel source ticks");
            const auto earned=use.needs();check(w::cancel_meal_use(k,use).ok&&!use.active()&&w::care::same_need_values(earned,use.needs()),"cancel retains only earned needs");
            check(k.events().back().note=="cancelled"&&use.requests().back().end==w::care::End::Cancelled&&!k.events().back().amount,"cancel never claims completed duration");
            const auto cancelled=k.save_bytes();check(w::cancel_meal_use(k,use).already_applied&&k.save_bytes()==cancelled,"cancel idempotent");
            check(k.release_grant({"ben",4,18,w::ReleaseReason::Completed,18}).reason=="release_reason_conflict"&&k.save_bytes()==cancelled,"elapsed clock cannot turn a cancelled grant into completion");
            const auto stopped=w::save_care_envelope(k,use,care_bindings(),{3,0});check(stopped.has_value(),"cancelled partial effects save");
            w::Kernel cancelled_world;w::care::ResidentUse cancelled_use("ben");w::ClockMetadata cancelled_clock;
            check(w::load_care_envelope(cancelled_world,cancelled_use,*stopped,care_bindings(),cancelled_clock)&&cancelled_world.save_bytes()==cancelled&&w::care::same_journal(cancelled_use.export_state(),use.export_state()),"cancelled load keeps partial effects and terminal cause without another release");
            check(w::begin_meal_use(cancelled_world,cancelled_use,command,observed("ben",3)).already_applied&&!cancelled_use.active()&&w::care::same_need_values(earned,cancelled_use.needs()),"original cancelled request replay after load earns nothing");
            check(w::advance_meal_use(k,use,4,{}).ok&&use.needs().fun==earned.fun,"inactive next tick no meal gain");
            check(w::begin_meal_use(k,use,meal(k,"interrupt/2"),observed("ben",4)).ok,"new actual meal");const auto at=care_contact(use);auto lost=at;lost.permission_valid=false;
            const auto interrupted=w::advance_meal_use(k,use,5,lost);check(interrupted.ok&&interrupted.outcome==w::care::Outcome::Interrupted&&!use.active()&&k.events().back().note=="interrupted","lost contact is interruption, not completion");
            const auto before=k.save_bytes();const auto care_before=w::encode_care_document(use.export_state());check(!w::advance_meal_use(k,use,7,at).ok&&k.save_bytes()==before&&w::encode_care_document(use.export_state())==care_before,"long frame cannot fabricate ticks/gains");
            check(!w::cancel_meal_use(k,use,w::ReleaseReason::Completed).ok,"cancel API cannot claim completion");same_money(k,16,8);passed("M19_cancel_interruption_and_tick_refusals");
        }
        {
            auto k=enabled();w::care::ResidentUse use("ben");
            for(auto fault:{w::MealFault::AfterPayment,w::MealFault::AfterStock,w::MealFault::AfterGrant}) {
                const auto world_before=k.save_bytes();const auto care_before=w::encode_care_document(use.export_state());const auto command=meal(k);
                check(!w::begin_meal_use(k,use,command,observed("ben",0),fault).ok,"injected world candidate failure");
                check(k.save_bytes()==world_before&&w::encode_care_document(use.export_state())==care_before,"both world and care remain exact after failure");
            }
            const auto opening_world=k.save_bytes();const auto opening_care=w::encode_care_document(use.export_state());
            check(!w::begin_meal_use(k,use,meal(k),observed("ben",0),w::MealFault::None,w::CareCommitFault::AfterCareBegin).ok,"failure after both candidate sides mutated");
            check(k.save_bytes()==opening_world&&w::encode_care_document(use.export_state())==opening_care,"care begin fault discards payment/stock/grant/progress together");
            check(w::begin_meal_use(k,use,meal(k),observed("ben",0)).ok,"same command remains usable after rollback");
            const auto world_before=k.save_bytes();const auto care_before=w::encode_care_document(use.export_state());
            check(!w::advance_meal_use(k,use,2,care_contact(use)).ok&&k.save_bytes()==world_before&&w::encode_care_document(use.export_state())==care_before,"nonconsecutive tick atomic across both states");
            check(!w::advance_meal_use(k,use,1,care_contact(use),w::CareCommitFault::AfterCareAdvance).ok&&k.save_bytes()==world_before&&w::encode_care_document(use.export_state())==care_before,"earned-gain candidate failure leaves no tick/gain publication");
            for(w::Int tick=1;tick<=17;++tick)check(w::advance_meal_use(k,use,tick,care_contact(use)).ok,"completion fault setup");
            const auto before_completion=k.save_bytes();const auto care_before_completion=w::encode_care_document(use.export_state());
            check(!w::advance_meal_use(k,use,18,care_contact(use),w::CareCommitFault::AfterCareAdvance).ok&&k.save_bytes()==before_completion&&w::encode_care_document(use.export_state())==care_before_completion,"completion benefit and release are not half-published");
            check(w::advance_meal_use(k,use,18,care_contact(use)).outcome==w::care::Outcome::Completed,"fresh fixture retry commits completion once");
            passed("M20_paired_rollback");
        }
        {
            auto k=enabled();w::care::ResidentUse use("ben");check(w::begin_meal_use(k,use,meal(k),observed("ben",0)).ok,"corruption source");
            for(w::Int tick=1;tick<=6;++tick)check(w::advance_meal_use(k,use,tick,care_contact(use)).ok,"corruption source progress");
            const auto good=w::save_care_envelope(k,use,care_bindings(),{6,0});check(good.has_value(),"canonical V4 source");
            for(int i=0;i<7;++i) {
                auto e=*w::decode_care_envelope_document(*good);
                if(i<4){auto j=*w::decode_care_document(e.care_payload);switch(i){case 0:++j.needs.fun;break;case 1:++j.active->elapsed;break;case 2:j.history[1].contact->reservation_valid=false;break;case 3:j.active.reset();j.requests[0].end=w::care::End::Cancelled;j.requests[0].end_tick=6;j.history.push_back({w::care::Op::Cancel,6,{}, {}});break;}e.care_payload=w::encode_care_document(j);e.care_digest=w::detail::hash_bytes(14695981039346656037ULL,e.care_payload);}
                if(i==4)e.bindings.care_core_sha256=std::string(64,'f');
                if(i==5)++e.clock.tick;
                if(i==6)e.version="3";
                auto target=k;auto target_use=use;w::ClockMetadata clock{6,bits(.5)};const auto before=target.save_bytes();const auto care_before=w::encode_care_document(target_use.export_state());
                check(!w::load_care_envelope(target,target_use,w::encode_care_envelope_document(e),care_bindings(),clock),"recomputed checksum cannot bypass replay/pair/bindings/version");
                check(target.save_bytes()==before&&w::encode_care_document(target_use.export_state())==care_before&&clock.tick==6&&clock.fraction_bits==bits(.5),"refused load publishes no partial world/care/clock");
            }
            const auto legacy=w::save_envelope(k,bindings(),{6,0});check(legacy.has_value(),"old V3 API remains available");auto target=k;auto target_use=use;w::ClockMetadata clock;
            check(!w::load_care_envelope(target,target_use,*legacy,care_bindings(),clock),"V3 lacks care, requires explicit migration");
            check(!w::load_envelope(target,*good,bindings(),clock),"old envelope reader rejects paired V4");
            check(!w::decode_care_document(w::encode_care_document(use.export_state())+"x"),"care trailing bytes refused");
            passed("M21_paired_corruption_and_explicit_versions");
        }
        std::cout<<"PASS "<<groups<<" groups, "<<checks<<" checks. Portable CPU only; native integration absent.\n";return 0;
    }catch(const std::exception& e){std::cerr<<"FAIL "<<e.what()<<" after "<<checks<<" checks\n";return 1;}
}
