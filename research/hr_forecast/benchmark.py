"""Run the locked public-data benchmark. All fitting is on train participants."""
from __future__ import annotations
import argparse
from collections import Counter
import csv
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import resource
import signal
import time
import zipfile
import numpy as np
import sklearn
from sklearn.linear_model import Ridge
from .forecast import BiasAdapter, CausalSeries, fit_scaler, split_for_subject

ROOT = Path(__file__).parent


def utc(): return datetime.now(timezone.utc).isoformat()
def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        while block := stream.read(1024*1024): digest.update(block)
    return digest.hexdigest()


def verify_archive(path, expected_sha256):
    if sha(path) != expected_sha256:
        raise ValueError('archive differs from locked source provenance')
def save(path, value): Path(path).write_text(json.dumps(value, indent=2, allow_nan=False)+'\n')


class Candidate:
    def __init__(self, name, feature_key=None, alpha=None, scaler=None, regressor=None):
        self.name, self.feature_key, self.alpha = name, feature_key, alpha
        self.scaler, self.regressor = scaler, regressor

    def eligible(self, row):
        return row['features'] is not None and (self.feature_key is None or row[self.feature_key] is not None)

    def predict(self, rows):
        latest = np.array([r['latest_hr'] for r in rows])
        if self.feature_key is None: return latest
        features = np.array([r[self.feature_key] for r in rows])
        return latest+self.regressor.predict(self.scaler.transform(features))

    def export(self):
        result = {'name':self.name,'feature_key':self.feature_key,'alpha':self.alpha}
        if self.feature_key:
            result.update({'mean':self.scaler.mean_.tolist(),'scale':self.scaler.scale_.tolist(),'coefficients':self.regressor.coef_.tolist(),'intercept':float(self.regressor.intercept_)})
        return result


def fit_candidates(records):
    models = {'persistence':Candidate('persistence')}
    for key, prefix in [('features','hr'),('wrist_features','wrist')]:
        rows = [r for r in records if r['group']=='train' and r[key] is not None and r['target'] is not None]
        if not rows: continue
        x = np.array([r[key] for r in rows])
        y = np.array([r['target']-r['latest_hr'] for r in rows])
        scaler = fit_scaler(x)
        counts = Counter(r['subject'] for r in rows)
        weights = np.array([len(rows)/(len(counts)*counts[r['subject']]) for r in rows])
        for alpha in [.1,1.,10.]:
            regressor = Ridge(alpha=alpha).fit(scaler.transform(x), y, sample_weight=weights)
            name = f'{prefix}-ridge-{alpha:g}'
            models[name] = Candidate(name,key,alpha,scaler,regressor)
    return models


def error_metrics(rows, predictions):
    if not rows: return {'count':0,'mae':None,'rmse':None,'bias':None}
    error = np.asarray(predictions)-np.array([r['target'] for r in rows])
    return {'count':len(rows),'mae':float(np.abs(error).mean()),'rmse':float(np.sqrt(np.mean(error**2))),'bias':float(error.mean())}


def participant_scores(rows, predictions):
    predictions = np.asarray(predictions)
    result = {}
    for sid in sorted({r['subject'] for r in rows}):
        indices = [i for i,r in enumerate(rows) if r['subject']==sid]
        result[str(sid)] = error_metrics([rows[i] for i in indices],predictions[indices])
    macro = float(np.mean([r['mae'] for r in result.values()])) if result else None
    return {'participant_macro_mae':macro,'per_participant':result,'pooled_dependent_windows':error_metrics(rows,predictions)}


def choose_candidate(models, validation):
    if any(r['group']!='validation' for r in validation):
        raise ValueError('selection accepts validation participants only')
    common = [r for r in validation if r['target'] is not None and r['wrist_features'] is not None]
    fallback = not bool(common)
    if fallback: common = [r for r in validation if r['target'] is not None and r['features'] is not None]
    if not common: raise ValueError('no eligible validation forecasts; test must stay unevaluated')
    scores = {}
    for name, model in models.items():
        if all(model.eligible(r) for r in common):
            scores[name] = participant_scores(common,model.predict(common))
    best = min(s['participant_macro_mae'] for s in scores.values())
    def simplicity(name):
        m=models[name]
        return (0 if name=='persistence' else (1 if m.feature_key=='features' else 2), -(m.alpha or 0))
    tied = [name for name,s in scores.items() if s['participant_macro_mae'] <= best+1e-9]
    return {'selected':min(tied,key=simplicity),'participants':sorted({r['subject'] for r in common}),'common_count':len(common),'wrist_empty_fallback':fallback,'scores':scores}


def load_records(archive, protocol):
    records={h:[] for h in protocol['task']['horizons_seconds']}
    inventory=[]
    with zipfile.ZipFile(archive) as z:
        for subject in [sid for group in ['train','validation','test'] for sid in protocol['dataset'][group]]:
            group=split_for_subject(subject,protocol)
            name=f'PAMAP2_Dataset/Protocol/subject{subject}.dat'
            if name not in z.namelist():
                inventory.append({'subject':subject,'group':group,'status':'missing','coverage':{}})
                continue
            with z.open(name) as stream:
                data=np.loadtxt(stream,usecols=(0,2,4,5,6),dtype=np.float64)
            resource_peak=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
            if resource_peak>protocol['budget']['memory_bytes']: raise MemoryError('RSS budget exceeded')
            try: series=CausalSeries(data[:,0],data[:,1],data[:,2:5])
            except ValueError as error:
                inventory.append({'subject':subject,'group':group,'status':'invalid_session','reason':str(error),'coverage':{}})
                continue
            origins=np.arange(math.ceil(series.times[0]/5)*5, math.floor(series.times[-1]/5)*5+1,5,dtype=int)
            coverage={str(h):Counter() for h in records}
            rejection=Counter()
            for origin in origins:
                hr=series.features(origin)
                wrist=series.features(origin,with_wrist=True) if hr['eligible'] else hr
                if not hr['eligible']: rejection['hr:'+hr['reason']]+=1
                elif not wrist['eligible']: rejection['wrist:'+wrist['reason']]+=1
                for horizon in records:
                    target=series.target(origin,horizon)
                    c=coverage[str(horizon)]
                    c['planned_origins']+=1
                    c['hr_input_eligible']+=int(hr['eligible'])
                    c['wrist_input_eligible']+=int(wrist['eligible'])
                    c['target_observed']+=int(target is not None)
                    c['hr_scored']+=int(hr['eligible'] and target is not None)
                    c['wrist_scored']+=int(wrist['eligible'] and target is not None)
                    records[horizon].append({'subject':subject,'group':group,'origin':int(origin),'target':target,'latest_hr':hr.get('latest_hr'),'features':hr.get('features'),'wrist_features':wrist.get('features') if wrist['eligible'] else None})
            inventory.append({'subject':subject,'group':group,'status':'loaded','rows':len(data),'first_timestamp':float(series.times[0]),'last_timestamp':float(series.times[-1]),'valid_hr_observations':int(series.valid_hr.sum()),'raw_hr_missing_fraction':float(1-series.valid_hr.mean()),'coverage':{h:dict(c) for h,c in coverage.items()},'input_abstention_reasons':dict(rejection)})
            print(f'Prepared subject{subject}: {len(data)} rows,{len(origins)} origins; group={group}',flush=True)
    return records,inventory


def evaluate_test(models, selected, rows, horizon):
    test=[r for r in rows if r['group']=='test']
    candidate_scores={}
    for name,model in models.items():
        eligible=[r for r in test if model.eligible(r) and r['target'] is not None]
        candidate_scores[name]=participant_scores(eligible,model.predict(eligible) if eligible else [])
    primary=models[selected]
    delivered=[r for r in test if primary.eligible(r)]
    trace=[]
    for subject in sorted({r['subject'] for r in delivered}):
        own=sorted([r for r in delivered if r['subject']==subject],key=lambda r:r['origin'])
        frozen=primary.predict(own)
        adapter=BiasAdapter(horizon)
        # Outcomes are looked up only at/after their future target window end.
        waiting={}
        for row,base in zip(own,frozen):
            origin=row['origin']
            matured={old:oldrow['target'] for old,oldrow in waiting.items() if old+horizon<=origin and oldrow['target'] is not None}
            before=adapter.update_count
            adaptive=adapter.step(origin,float(base),matured)
            for old in list(waiting):
                if old+horizon<=origin: waiting.pop(old)
            waiting[origin]=row
            trace.append({'subject':subject,'origin':origin,'horizon':horizon,'target_window_start':origin+horizon-5,'target_window_end':origin+horizon,'target':row['target'],'frozen':float(base),'adaptive':adaptive,'persistence':row['latest_hr'],'prior_matured_updates':before,'updates_after_prediction':adapter.update_count-before,'cold_start':before<10})
    scored=[r for r in trace if r['target'] is not None]
    summary={name:participant_scores(scored,[r[name] for r in scored]) for name in ['frozen','adaptive','persistence']}
    summary['cold_start']={name:participant_scores([r for r in scored if r['cold_start']],[r[name] for r in scored if r['cold_start']]) for name in ['frozen','adaptive','persistence']}
    summary['paired_participant_mae_delta']={sid:values['mae']-summary['persistence']['per_participant'][sid]['mae'] for sid,values in summary['frozen']['per_participant'].items()}
    return {'selected':selected,'prespecified_candidate_scores_own_eligibility':candidate_scores,'selected_primary_same_origins':summary},trace


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--archive',default='.local/research/PAMAP2/PAMAP2_Dataset.zip')
    parser.add_argument('--output',default='research/hr_forecast/results')
    args=parser.parse_args()
    protocol=json.loads((ROOT/'protocol.json').read_text())
    expected=(ROOT/'protocol.sha256').read_text().split()[0]
    if sha(ROOT/'protocol.json')!=expected: raise RuntimeError('locked protocol hash mismatch')
    out=Path(args.output)
    out.mkdir(parents=True,exist_ok=False)
    started=utc(); wall=time.monotonic(); cpu=time.process_time()
    signal.signal(signal.SIGALRM,lambda *_: (_ for _ in ()).throw(TimeoutError('600-second compute limit')))
    signal.alarm(600)
    provenance=json.loads((ROOT/'provenance.json').read_text())
    verify_archive(args.archive,provenance['data_zip_sha256'])
    records,inventory=load_records(args.archive,protocol)
    save(out/'inventory.json',inventory)
    models={h:fit_candidates(rows) for h,rows in records.items()}
    selections={h:choose_candidate(models[h],[r for r in rows if r['group']=='validation']) for h,rows in records.items()}
    save(out/'selection.json',{'selected_at_utc':utc(),'protocol_sha256':expected,'horizons':selections,'test_scored':False})
    selection_hash=sha(out/'selection.json')
    save(out/'models.json',{h:{n:m.export() for n,m in candidates.items()} for h,candidates in models.items()})
    results={}; traces=[]
    for horizon,rows in records.items():
        result,trace=evaluate_test(models[horizon],selections[horizon]['selected'],rows,horizon)
        results[horizon]=result; traces.extend(trace)
    with (out/'test-predictions.csv').open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(traces[0]) if traces else ['subject','origin','horizon'])
        writer.writeheader(); writer.writerows(traces)
    elapsed=time.monotonic()-wall
    report={'started_at_utc':started,'finished_at_utc':utc(),'protocol_sha256':expected,'selection_sha256_before_test_scoring':selection_hash,'provenance_sha256':sha(ROOT/'provenance.json'),'code_sha256':{p.name:sha(p) for p in [ROOT/'forecast.py',ROOT/'benchmark.py']},'environment':{'python':platform.python_version(),'numpy':np.__version__,'sklearn':sklearn.__version__,'platform':platform.platform(),'thread_limits':{k:os.getenv(k) for k in ['OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','VECLIB_MAXIMUM_THREADS']}},'resources':{'wall_seconds':elapsed,'cpu_seconds':time.process_time()-cpu,'peak_rss_bytes':resource.getrusage(resource.RUSAGE_SELF).ru_maxrss},'test_results':results,'test_participants_expected':protocol['dataset']['test'],'zero_coverage_participants':[r['subject'] for r in inventory if r['group']=='test' and (r['status']!='loaded' or not any(v.get('hr_scored',0) for v in r['coverage'].values()))],'claims':'Offline public-data HR forecast only; two held-out participants, no Watch transfer, recovery, RIR, clinical or runtime app validation.'}
    save(out/'report.json',report)
    size=sum(p.stat().st_size for p in out.iterdir())
    if elapsed>600 or size>100000000 or report['resources']['peak_rss_bytes']>4294967296: raise RuntimeError('resource budget exceeded')
    signal.alarm(0)
    print(json.dumps({'resources':report['resources'],'output_bytes':size,'selected':{h:s['selected'] for h,s in selections.items()},'test_primary':{h:r['selected_primary_same_origins'] for h,r in results.items()}},indent=2),flush=True)

if __name__=='__main__': main()
