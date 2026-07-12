#!/usr/bin/env python
# Bake-off distill + held-out eval: tiny GBDT ranker vs logic-floor, both scored against the teacher.
# Usage: python train_eval.py decisions_full.jsonl labels_baseline.jsonl
import json, sys, hashlib, collections
import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.inspection import permutation_importance

DATA, LAB = sys.argv[1], sys.argv[2]
labels={}
for line in open(LAB,encoding="utf-8"):
    r=json.loads(line)
    if r["teacher_label"]>=0: labels[r["key"]]=r
print("labeled (parseable): %d"%len(labels))

# join: stream dataset, keep only labeled rows
rows={}
for line in open(DATA,encoding="utf-8"):
    d=json.loads(line)
    k="%d:%d:%s"%(d["seed"],d["tick"],d["agent"])
    if k in labels: rows[k]=d
print("joined decisions: %d"%len(rows))

NEEDK=["energy","fun","hunger","hygiene","social"]
ACTS=sorted({c["action"] for d in rows.values() for c in d["cands"]})
AID={a:i for i,a in enumerate(ACTS)}
PERS=sorted({d["persona"] for d in rows.values()})
PID={p:i for i,p in enumerate(PERS)}
TODS=sorted({d["tod"] for d in rows.values()})
TID={t:i for i,t in enumerate(TODS)}
DRAMA={"confront","rally_oust","apologize","endorse","leak","confide"}

def feats(d):
    needs=d["needs"]; cap=d["cap_order"]; cands=[d["cands"][j] for j in cap]
    scores=[float(c.get("score",0)) for c in cands]; mx=max(scores) if scores else 1.0
    order=sorted(range(len(cands)),key=lambda i:-scores[i])
    rank={i:r for r,i in enumerate(order)}
    X=[]
    for i,c in enumerate(cands):
        nd = 100.0-float(needs.get(c.get("need",""),100.0)) if c.get("need") else 0.0
        X.append([
            float(c.get("score",0)), scores[i]/mx if mx else 0.0, rank[i],
            1.0 if c.get("kind")=="social" else 0.0,
            1.0 if c.get("action") in DRAMA else 0.0,
            nd, float(c.get("aff",0) or 0), float(c.get("fam",0) or 0), float(c.get("trust",0) or 0),
            AID.get(c.get("action"),-1),
            needs.get("energy",0),needs.get("fun",0),needs.get("hunger",0),needs.get("hygiene",0),needs.get("social",0),
            float(d["min_need"]), PID[d["persona"]], TID.get(d["tod"],-1), len(cands),
        ])
    return np.array(X,dtype=np.float32)
FNAMES=["score","score_norm","score_rank","is_social","is_drama","need_deficit","aff","fam","trust","action_id",
        "n_energy","n_fun","n_hunger","n_hygiene","n_social","min_need","persona","tod","n_cap"]

# build per-candidate matrix, grouped by decision; 80/20 split by hashed key
def split(k): return (int(hashlib.md5(k.encode()).hexdigest(),16)%5==0)  # ~20% test
Xtr,ytr=[],[]; test=[]
for k,d in rows.items():
    X=feats(d); t=labels[k]["teacher_label"]; lg=labels[k]["logic_label"]
    if t>=len(X): continue
    y=np.zeros(len(X)); y[t]=1
    if split(k):
        test.append((k,d,X,t,lg))
    else:
        Xtr.append(X); ytr.append(y)
Xtr=np.vstack(Xtr); ytr=np.concatenate(ytr)
print("train candidate-rows: %d (%.1f%% positive) | test decisions: %d"%(len(Xtr),100*ytr.mean(),len(test)))

clf=HistGradientBoostingClassifier(max_iter=300,learning_rate=0.06,max_depth=6,l2_regularization=1.0,
                                   categorical_features=[9,16,17],random_state=0)
clf.fit(Xtr,ytr)

# eval
rk_hit=lg_hit=rand=0; n=len(test)
conf=collections.Counter()   # (logic_act, teacher_act, ranker_act) agreement tallies
tvl=lambda a,b:"="if a==b else"≠"
rk_vs_lg_when_diff=0; diff_cases=0
teacher_act_c=collections.Counter(); logic_act_c=collections.Counter(); ranker_act_c=collections.Counter()
for k,d,X,t,lg in test:
    p=clf.predict_proba(X)[:,1]; rk=int(np.argmax(p))
    rk_hit+=(rk==t); lg_hit+=(lg==t); rand+=1.0/len(X)
    cap=d["cap_order"]
    ta=d["cands"][cap[t]]["action"]; la=d["cands"][cap[lg]]["action"] if lg<len(cap) else "?"; ra=d["cands"][cap[rk]]["action"]
    teacher_act_c[ta]+=1; logic_act_c[la]+=1; ranker_act_c[ra]+=1
    if lg!=t:
        diff_cases+=1; rk_vs_lg_when_diff+=(rk==t)
print("\n=== HELD-OUT (n=%d) — top-1 match to TEACHER ==="%n)
print("  tiny GBDT ranker : %5.1f%%"%(100*rk_hit/n))
print("  logic floor      : %5.1f%%"%(100*lg_hit/n))
print("  random baseline  : %5.1f%%"%(100*rand/n))
print("  ranker recovers teacher on %d/%d cases where logic≠teacher (%.1f%%)"%(rk_vs_lg_when_diff,diff_cases,100*rk_vs_lg_when_diff/max(1,diff_cases)))
print("\n=== what each picks (test action distribution, top8) ===")
print("  teacher:", teacher_act_c.most_common(8))
print("  logic  :", logic_act_c.most_common(8))
print("  ranker :", ranker_act_c.most_common(8))

# feature importance (permutation on a decision-flattened test set)
Xte=np.vstack([X for _,_,X,_,_ in test]); yte=np.concatenate([ (lambda X,t: (lambda z: (z.__setitem__(t,1),z)[1])(np.zeros(len(X))))(X,t) for _,_,X,t,_ in test])
imp=permutation_importance(clf,Xte,yte,n_repeats=5,random_state=0,scoring="average_precision")
order=np.argsort(-imp.importances_mean)[:8]
print("\n=== top feature importances (permutation, avg-precision drop) ===")
for i in order: print("  %-14s %.4f"%(FNAMES[i],imp.importances_mean[i]))
