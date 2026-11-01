// Portable CPU property contract cases; native V3 gameplay integration remains pending.
#include "../../../unreal/Source/LivingTownNative/ThirdParty/CafeWorldV3.hpp"
#include "../../../unreal/Source/LivingTownNative/ThirdParty/LeaseKernel.hpp"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>

namespace p=living_town::cafe_world_v3;
namespace {
int checks=0;
std::vector<std::string> cases;
void check(bool yes,const std::string& why) {++checks;if(!yes)throw std::runtime_error(why);}
p::Context at(const std::string& actor,p::Int tick) {return {actor,actor,"cafe","1f","cafe1f_counter",tick,true};}
p::Intent command(const std::string& id,p::Action action) {return {id,"cafe_ground_commercial_v1",action};}
p::Receipt act(p::Kernel& k,const std::string& actor,p::Int tick,const std::string& id,p::Action action) {
    return k.execute(command(id,action),at(actor,tick));
}
void passed(const std::string& name) {cases.push_back(name);std::cout<<"CASE "<<name<<" PASS\n";}
void balances(const p::Kernel& k,p::Int aria,p::Int ben) {
    check(k.coin("aria")==aria&&k.coin("ben")==ben,"exact wallets");check(k.verify_ledger(),"ledger reconciles");
    const auto sum=static_cast<std::uint64_t>(aria)+static_cast<std::uint64_t>(ben);
    const auto total=static_cast<std::uint64_t>(k.accounts()[0].opening)+static_cast<std::uint64_t>(k.accounts()[1].opening);
    check(sum==total,"opening money conserved without signed sum overflow");
}
p::Kernel sold() {
    p::Kernel k;
    check(act(k,"aria",10,"sale/aria/1",p::Action::offer_sale).ok,"owner offers sale");
    check(act(k,"ben",11,"buy/ben/1",p::Action::buy).ok,"buyer purchases");return k;
}
p::Kernel leased_after_sale() {
    auto k=sold();check(act(k,"ben",12,"lease_offer/ben/1",p::Action::offer_lease).ok,"new owner consents");
    check(act(k,"aria",13,"lease/aria/1",p::Action::lease).ok,"former owner becomes tenant");return k;
}
void bad_journal(const p::Journal& j,const p::Kernel& guard,const std::string& why) {
    auto live=guard;const auto before=live.save_bytes();check(!live.restore(j),why);check(live.save_bytes()==before,"failed load keeps exact authority");
}
std::string read_file(const std::filesystem::path& path) {
    std::ifstream in(path,std::ios::binary);if(!in)throw std::runtime_error("open saved journal");
    std::ostringstream out;out<<in.rdbuf();return out.str();
}
void write_file(const std::filesystem::path& path,const std::string& bytes) {
    if(std::filesystem::exists(path))throw std::runtime_error("refuse existing fixture output");
    std::ofstream out(path,std::ios::binary);out.write(bytes.data(),static_cast<std::streamsize>(bytes.size()));
    out.close();if(!out)throw std::runtime_error("write fixture output");
}
}

int main(int argc,char** argv) {
    try {
        if(argc!=2)throw std::invalid_argument("Usage: CafePropertyV2Cases.exe OWNED_F_OUTPUT_DIRECTORY");
        const std::filesystem::path output=std::filesystem::absolute(argv[1]);
        // The coordinator creates/selects the fresh build directory. This consumer never deletes/moves files.
        if(!std::filesystem::is_directory(output))throw std::invalid_argument("existing owned output directory required");
        if(std::filesystem::exists(output/"CASE_RESULTS.json"))throw std::invalid_argument("refuse rerun over results");
        {
            p::Kernel k;check(k.title().owner=="aria"&&k.title().revision==0,"authored title");
            check(k.offer().present&&k.offer().kind=="lease"&&k.offer().revision==0,"authored lease only");
            balances(k,12,12);check(!k.can_operate("aria","cafe","2f",0),"title excludes upstairs");
            check(!act(k,"ben",1,"buy_unlisted/1",p::Action::buy).ok,"no silently authored sale consent");
            check(k.events().back().note=="no_owner_offer","sale needs owner listing");passed("P00_source_bound_opening");
        }
        {
            const auto k=sold();balances(k,24,0);check(k.events().size()==3,"one offer plus payment/deed");
            const auto& offer=k.events()[0];const auto& pay=k.events()[1];const auto& deed=k.events()[2];
            check(offer.id==1&&offer.type=="property_offer_opened"&&offer.offer_kind=="sale"&&offer.offer_revision==1&&offer.title_revision==0,"source offer event");
            check(pay.id==2&&pay.type=="pay"&&pay.actor=="ben"&&pay.target=="aria"&&pay.amt==12&&pay.tick==11&&pay.accepted,"actual conserved payment");
            check(pay.note=="property_sale:cafe_ground_commercial_v1*12"&&pay.txid=="property/buy/ben/1","exact payment linkage");
            check(deed.id==3&&deed.type=="property_deed_transferred"&&deed.owner_before=="aria"&&deed.owner_after=="ben"&&deed.pay_event_id==2&&deed.title_revision==0&&deed.offer_revision==1,"source deed fields");
            check(k.title().owner=="ben"&&k.title().revision==1&&!k.offer().present,"new title removes old consent");
            check(k.operator_at(11)=="ben"&&!k.can_operate("ben","cafe","2f",11),"operator changes only commercial unit");passed("P01_owner_consent_paid_sale");
        }
        {
            const auto k=leased_after_sale();balances(k,20,4);check(k.events().size()==6,"new listing and second payment pair");
            check(k.events()[3].offer_revision==1&&k.events()[3].title_revision==1,"new listing starts after erased old offer");
            check(k.title().owner=="ben"&&k.operator_at(13)=="aria","title and tenant distinct");
            check(k.lease().event_id==6&&k.lease().pay_event_id==5&&k.lease().start==13&&k.lease().end==733,"exact prepaid lease");
            check(!k.can_operate("aria","cafe","2f",13),"tenant excludes upstairs");passed("P02_new_owner_explicit_lease");
        }
        {
            auto k=sold();const auto before=k.save_bytes();const auto r=act(k,"ben",12,"buy/ben/1",p::Action::buy);
            check(r.ok&&r.already_applied&&r.event_id==3&&k.save_bytes()==before,"retry does not repay/revise/append");
            const auto wrong=act(k,"aria",12,"buy/ben/1",p::Action::offer_sale);
            check(!wrong.ok&&wrong.reason=="request_id_conflict"&&k.save_bytes()==before,"ID cannot change actor/action");
            check(act(k,"ben",9,"buy/ben/1",p::Action::buy).reason=="invalid_command_tick","tick validation precedes retry");passed("P03_idempotence_and_conflict");
        }
        {
            auto k=sold();check(act(k,"aria",12,"old_consent/1",p::Action::lease).reason=="no_owner_offer","new owner consent required");
            balances(k,24,0);check(k.title().owner=="ben","failed old consent preserves title");passed("P04_no_inherited_offer");
        }
        {
            p::Kernel k;check(act(k,"ben",1,"not_owner/1",p::Action::offer_sale).reason=="not_owner","only owner lists");
            check(act(k,"aria",2,"self/1",p::Action::buy).reason=="self_transaction","no self payment");
            auto c=at("aria",3);c.authenticated_actor="ben";const auto before=k.save_bytes();
            check(k.execute(command("spoof/1",p::Action::offer_sale),c).reason=="unauthenticated_actor"&&k.save_bytes()==before,"auth mismatch has no event");
            c=at("ben",4);c.floor_id="2f";check(k.execute(command("upstairs/1",p::Action::lease),c).reason=="not_at_commercial_counter","private plane refuses");
            c=at("ben",5);c.within_reach=false;check(k.execute(command("remote/1",p::Action::lease),c).reason=="not_at_commercial_counter","remote refuses");
            c=at("ben",6);c.interaction_id="other_counter";check(k.execute(command("wrong_fixture/1",p::Action::lease),c).reason=="not_at_commercial_counter","wrong fixture refuses");
            balances(k,12,12);check(k.title().owner=="aria","refusals preserve title");passed("P05_authority_and_geometry");
        }
        {
            p::Kernel k;check(act(k,"ben",10,"initial_lease/1",p::Action::lease).ok,"initial source consent works");
            check(act(k,"aria",11,"sale_during/1",p::Action::offer_sale).reason=="lease_must_end_first","sale cannot displace tenant");
            check(k.lease().active&&k.lease().tenant=="ben","lease survives refused listing");balances(k,16,8);passed("P06_active_lease_blocks_sale");
        }
        {
            p::Kernel k(p::Terms{},{{"aria",12,12},{"ben",11,11}});
            check(act(k,"aria",10,"sale/poor",p::Action::offer_sale).ok,"independent low-wallet fixture offers");
            const auto r=act(k,"ben",11,"buy/poor",p::Action::buy);
            check(!r.ok&&r.reason=="settlement_rejected"&&k.events().size()==2,"no pay event on insufficient funds");
            const auto& e=k.events().back();check(e.type=="property_refused"&&!e.accepted&&!e.amount&&!e.offer_revision&&e.owner_after.empty()&&e.txid.empty(),"refusal strips financial claims");
            check(k.title().owner=="aria"&&k.title().revision==0,"no title without payment");balances(k,12,11);passed("P07_settlement_failure");
        }
        {
            p::Kernel k;check(act(k,"aria",10,"sale/aria/1",p::Action::offer_sale).ok,"offer for injected transaction");
            const auto before=k.save_bytes();const auto r=k.execute(command("buy/ben/1",p::Action::buy),at("ben",11),p::FaultPoint::after_payment_before_property);
            check(!r.ok&&r.reason=="technical_failure:injected_postpay","actual cloned post-pay fault occurs");
            check(k.save_bytes()==before,"no payment, title, dedup or clock publication after technical failure");
            check(act(k,"ben",11,"buy/ben/1",p::Action::buy).ok,"same request reusable after rollback");
            check(k.save_bytes()==sold().save_bytes(),"retry equals clean branch byte for byte");passed("P08_postpay_rollback");
        }
        {
            p::Kernel k;check(act(k,"aria",10,"sale/1",p::Action::offer_sale).ok,"receipt fixture offer");
            const auto plan=k.prepare(command("buy/1",p::Action::buy),at("ben",11));check(plan.payment.has_value(),"exact payment prepared");
            const auto& x=*plan.payment;p::Event actual;actual.id=2;actual.tick=x.tick;actual.type="pay";actual.accepted=true;
            actual.actor=x.actor;actual.target=x.target;actual.amt=x.amt;actual.note=x.note;actual.txid=x.txid;
            check(p::Kernel::settled_event(plan,actual).has_value(),"matching actual receipt can link");
            for(int n=0;n<10;++n){auto bad=actual;switch(n){case 0:bad.type="gift";break;case 1:bad.accepted=false;break;case 2:bad.id=-1;break;
                case 3:bad.actor="aria";break;case 4:bad.target="ben";break;case 5:bad.amt=11;break;case 6:bad.tick=12;break;
                case 7:bad.note="other";break;case 8:bad.txid="property/other";break;case 9:bad.id=p::max_tick+1;break;}
                check(!p::Kernel::settled_event(plan,bad),"single-field receipt mutation refuses");}
            // Source only validates an actual ID's bounds; exact provenance is enforced by full replay/ledger, not a guessed next ID.
            actual.id=7;check(p::Kernel::settled_event(plan,actual).has_value(),"do not invent an extra source ID matcher");
            check(k.events().size()==1,"read-only settlement helper publishes nothing");passed("P09_exact_receipt_validation");
        }
        const auto final=leased_after_sale();
        {
            auto fresh=p::Kernel{};check(fresh.restore_bytes(final.save_bytes()),"strict full bytes restore");
            check(fresh.save_bytes()==final.save_bytes()&&fresh.digest()==final.digest(),"full replay and derived cache exact");
            check(act(fresh,"ben",14,"buy/ben/1",p::Action::buy).already_applied,"replay reconstructs request dedup");
            for(int n=0;n<17;++n){auto j=final.journal();switch(n){case 0:j.events.pop_back();break;case 1:j.events.insert(j.events.begin()+2,j.events[1]);break;
                case 2:j.events[2].pay_event_id=99;break;case 3:std::swap(j.events[1],j.events[2]);break;case 4:j.accounts[0].coin+=1;break;
                case 5:j.title.owner="aria";break;case 6:j.terms.config_sha256=std::string(64,'0');break;case 7:j.document_schema="cafe.prepaid_lease.v1";break;
                case 8:j.document_capability="whole_world";break;case 9:j.events[1].amt=11;break;case 10:j.events[0].context->authenticated_actor="ben";break;
                case 11:j.events[3].title_revision=0;break;case 12:j.lease.end+=1;break;case 13:j.digest^=1;break;case 14:j.last_tick-=1;break;
                case 15:j.opening[0].opening+=1;j.opening[0].coin+=1;break;case 16:j.events[1].txid="property/forged";break;}
                bad_journal(j,final,"corrupt journal rejects before publish");}
            auto live=final;const auto before=live.save_bytes();check(!live.restore_bytes(before+"x")&&live.save_bytes()==before,"trailing bytes refused");
            check(!live.restore_bytes(before.substr(0,before.size()-1))&&live.save_bytes()==before,"truncated bytes refused");
            check(!live.restore_bytes(std::string(p::max_journal_bytes+1,'x')),"bounded input refuses oversized document");
            check(!live.restore_bytes("01:x"),"noncanonical or wrong schema refuses");passed("P10_replay_save_and_corruption");
        }
        {
            auto k=final;check(act(k,"aria",20,"surrender/1",p::Action::end_lease).ok,"tenant surrenders");
            check(!k.lease().active&&k.operator_at(20)=="ben","operator returns to current title owner");balances(k,20,4);
            k=final;check(act(k,"town",732,"expire/early",p::Action::expire).reason=="lease_not_due","trusted expiry before due refuses");
            check(k.operator_at(732)=="aria"&&!k.expiry_request(732),"term still running with no due request");
            const auto due=k.expiry_request(733);check(due&&due->request_id=="expire/cafe_ground_commercial_v1/6","source-derived due request ID");
            auto trusted_clock=at("town",733);trusted_clock.space_id.clear();trusted_clock.floor_id.clear();trusted_clock.interaction_id.clear();trusted_clock.within_reach=false;
            check(k.execute(*due,trusted_clock).ok,"trusted natural due tick expires without fabricated location");
            check(!k.lease().active&&k.operator_at(733)=="ben","expired operator is current owner");balances(k,20,4);
            check(!k.can_operate("ben","cafe","2f",733),"expiry does not grant upstairs");passed("P11_end_and_due_expiry");
        }
        {
            p::Kernel k;auto c=at("ben",-1);check(k.execute(command("negative/1",p::Action::lease),c).reason=="invalid_command_tick","negative clock refused");
            c=at("ben",p::max_tick+1);check(k.execute(command("beyond/1",p::Action::lease),c).reason=="invalid_command_tick","beyond exact source clock refused");
            c=at("ben",p::max_tick-719);check(k.execute(command("overflow/1",p::Action::lease),c).reason=="lease_tick_overflow","end-tick overflow refused");
            check(!k.events().back().amount&&!k.events().back().offer_revision&&!k.events().back().end_tick,"range refusal has source baseline fields only");
            const auto before=k.save_bytes();check(k.execute({"bad request","cafe_ground_commercial_v1",p::Action::lease},at("ben",p::max_tick)).reason=="malformed_request","invalid token refused");
            check(k.execute(command("invalid_enum/1",static_cast<p::Action>(99)),at("ben",p::max_tick)).reason=="malformed_request","invalid action enum refused");
            check(k.save_bytes()==before,"malformed input does not append");
            p::Kernel rich(p::Terms{},{{"aria",std::numeric_limits<p::Int>::max(),std::numeric_limits<p::Int>::max()},{"ben",12,12}});
            check(act(rich,"aria",1,"rich_offer/1",p::Action::offer_sale).ok,"independent overflow fixture offers");
            check(act(rich,"ben",2,"rich_buy/1",p::Action::buy).reason=="settlement_rejected","recipient overflow refuses");
            balances(rich,std::numeric_limits<p::Int>::max(),12);
            bool threw=false;try{auto terms=p::Terms{};terms.sale_price=1;p::Kernel invalid(terms);(void)invalid;}catch(const std::invalid_argument&){threw=true;}
            check(threw,"terms cannot drift from source");passed("P12_bounds_and_source_binding");
        }
        {
            p::Kernel k;for(std::size_t n=0;n<p::max_events;++n)check(act(k,"aria",0,"capacity/"+std::to_string(n),p::Action::offer_lease).ok,"bounded listing sequence");
            const auto before=k.save_bytes();const auto r=act(k,"ben",0,"capacity_buy/1",p::Action::lease);
            check(!r.ok&&r.reason.find("technical_failure:")==0&&k.save_bytes()==before,"full journal cannot publish half financial transaction");
            check(act(k,"aria",0,"capacity/0",p::Action::offer_lease).already_applied,"dedup still works at capacity");passed("P13_capacity_is_atomic");
        }
        {
            const auto file=output/"cafe_property_v2.journal";write_file(file,final.save_bytes());
            p::Kernel reopened;check(reopened.restore_bytes(read_file(file)),"actual file readback restores");
            check(reopened.save_bytes()==final.save_bytes(),"file bytes and replay exact");passed("P14_actual_file_save_readback");
        }
        {
            // Direct cross-source check against byte-exact frozen v1, for its shared unchanged scope.
            namespace v1=living_town::lease_pilot;
            v1::Kernel old({"cafe_ground_commercial_v1","aria","cafe","1f","cafe1f_counter",4,720},{{"aria",12,12},{"ben",12,12}});
            p::Kernel current;
            struct Step {const char* actor;const char* id;p::Int tick;p::Action action;v1::Action old_action;bool near;};
            const Step steps[]={
                {"ben","shared/remote",1,p::Action::lease,v1::Action::lease,false},
                {"ben","shared/lease1",10,p::Action::lease,v1::Action::lease,true},
                {"ben","shared/lease1",11,p::Action::lease,v1::Action::lease,true},
                {"aria","shared/nottenant",12,p::Action::end_lease,v1::Action::end_lease,true},
                {"ben","shared/end",13,p::Action::end_lease,v1::Action::end_lease,true},
                {"ben","shared/lease2",14,p::Action::lease,v1::Action::lease,true},
                {"town","shared/expire",734,p::Action::expire,v1::Action::expire,false}};
            for(const auto& s:steps){
                auto c=at(s.actor,s.tick);c.within_reach=s.near;
                const auto a=current.execute(command(s.id,s.action),c);
                const auto b=old.execute({s.id,"cafe_ground_commercial_v1",s.old_action},{s.actor,"cafe","1f","cafe1f_counter",s.tick,s.near});
                check(a.ok==b.ok&&a.already_applied==b.already_applied&&a.reason==b.reason&&a.event_id==b.event_id,"v1/v2 shared command receipt exact");
                check(current.accounts().size()==old.accounts().size(),"v1/v2 account count");
                for(std::size_t n=0;n<old.accounts().size();++n)check(current.accounts()[n].id==old.accounts()[n].id&&current.accounts()[n].coin==old.accounts()[n].coin,"v1/v2 conserved wallet exact");
                check(current.events().size()==old.events().size(),"v1/v2 event count");
                for(std::size_t n=0;n<old.events().size();++n){const auto& x=current.events()[n];const auto& y=old.events()[n];
                    check(x.id==y.id&&x.tick==y.tick&&x.type==y.type&&x.actor==y.actor&&x.target==y.target&&x.subject==y.subject&&x.note==y.note&&x.txid==y.txid&&x.accepted==y.accepted&&
                        x.amt==y.amt&&x.amount==y.amount&&x.end_tick==y.end_tick&&x.pay_event_id==y.pay_event_id&&x.lease_event_id==y.lease_event_id&&x.title_revision==y.title_revision&&x.offer_revision==y.offer_revision&&
                        x.request_id==y.request_id&&x.action==y.action&&x.owner_before==y.owner_before,"v1/v2 shared event semantic fields exact");
                    check(x.context.has_value()==y.context.has_value(),"v1/v2 shared context presence");
                    if(x.context&&y.context)check(x.context->actor==y.context->actor&&x.context->tick==y.context->tick&&x.context->space_id==y.context->space_id&&x.context->floor_id==y.context->floor_id&&
                        x.context->interaction_id==y.context->interaction_id&&x.context->within_reach==y.context->within_reach,"v1/v2 trusted spatial context exact");
                }
                check(current.operator_at(s.tick)==old.operator_at(s.tick)&&current.lease().active==old.lease().active,"v1/v2 rights exact");
            }
            passed("P15_direct_frozen_v1_shared_scope_parity");
        }
        std::ostringstream receipt;receipt<<"{\n  \"schema\": \"living_town.cafe_property_cpu_cases.v1\",\n  \"status\": \"PASS_PORTABLE_CPU_ONLY\",\n  \"checks\": "<<checks<<",\n  \"case_count\": "<<cases.size()<<",\n  \"property_config_sha256\": \""<<p::source_config_sha256<<"\",\n  \"native_player_journey_qualified\": false,\n  \"engine_runs\": 0,\n  \"cases\": [";
        for(std::size_t n=0;n<cases.size();++n){if(n)receipt<<",";receipt<<"\n    \""<<cases[n]<<"\"";}receipt<<"\n  ]\n}\n";
        write_file(output/"CASE_RESULTS.json",receipt.str());std::cout<<"PASS "<<cases.size()<<" cases, "<<checks<<" checks. Native integration remains pending.\n";return 0;
    } catch(const std::exception& e){std::cerr<<"FAIL "<<e.what()<<" after "<<checks<<" checks\n";return 1;}
}
