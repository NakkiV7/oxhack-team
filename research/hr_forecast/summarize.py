"""Render recorded results only; never refit or select a model."""
from pathlib import Path
import csv
import hashlib
import json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

ROOT=Path(__file__).parent
OUT=ROOT/'results'
report=json.loads((OUT/'report.json').read_text())
inventory=json.loads((OUT/'inventory.json').read_text())
with (OUT/'test-predictions.csv').open() as f: trace=list(csv.DictReader(f))

# Reconcile summaries against the actual held-out prediction trace.
coverage=[]
for row in inventory:
    if row['group']!='test': continue
    for horizon in [10,30]:
        c=row.get('coverage',{}).get(str(horizon),{})
        own=[x for x in trace if int(x['subject'])==row['subject'] and int(x['horizon'])==horizon]
        scored=[x for x in own if x['target']!='']
        assert len(own)==c.get('hr_input_eligible',0), 'selected HR-only delivery count drift'
        assert len(scored)==c.get('hr_scored',0), 'score count drift'
        if scored:
            errors=np.array([float(x['frozen'])-float(x['target']) for x in scored])
            recorded=report['test_results'][str(horizon)]['selected_primary_same_origins']['frozen']['per_participant'][str(row['subject'])]
            assert np.isclose(np.abs(errors).mean(),recorded['mae'],rtol=0,atol=1e-12)
        coverage.append({'subject':row['subject'],'horizon':horizon,**c,'delivered_forecasts':len(own),'scored_forecasts':len(scored),'input_coverage':len(own)/c['planned_origins'] if c.get('planned_origins') else None,'scored_coverage':len(scored)/c['planned_origins'] if c.get('planned_origins') else None})
(OUT/'coverage-summary.json').write_text(json.dumps(coverage,indent=2)+'\n')

fig,axes=plt.subplots(1,2,figsize=(10,4.3),layout='constrained')
colors=['#191919','#777777','#b76b13']
for ax,horizon in zip(axes,[10,30]):
    scores=report['test_results'][str(horizon)]['selected_primary_same_origins']
    ids=[108,109]
    x=np.arange(2);width=.24
    for j,(name,label) in enumerate([('persistence','Last value'),('frozen','Frozen ridge'),('adaptive','Adaptive bias')]):
        vals=[scores[name]['per_participant'].get(str(sid),{}).get('mae',np.nan) for sid in ids]
        ax.bar(x+(j-1)*width,vals,width,color=colors[j],label=label)
    for i,sid in enumerate(ids):
        n=scores['frozen']['per_participant'].get(str(sid),{}).get('count',0)
        if n==0: ax.text(i,.3,'No eligible\ntargets',ha='center',fontsize=9)
    ax.set_xticks(x,['108\n'+str(scores['frozen']['per_participant'].get('108',{}).get('count',0))+' forecasts','109\n'+str(scores['frozen']['per_participant'].get('109',{}).get('count',0))+' forecasts'])
    ax.set_title(f'{horizon}s horizon · future 5s mean')
    ax.set_ylabel('MAE (bpm), lower is better')
    ax.set_ylim(0,9)
    ax.spines[['top','right']].set_visible(False)
    ax.set_axisbelow(True);ax.grid(axis='y',alpha=.15)
axes[0].legend(frameon=False,fontsize=8)
fig.suptitle('PAMAP2 held-out participants · exploratory offline benchmark',fontsize=12)
fig.savefig(OUT/'heldout-errors.png',dpi=180)
plt.close(fig)

fig,axes=plt.subplots(2,1,figsize=(10,5.6),layout='constrained')
# Deterministic illustration: participant108, first10minutes; not chosen for low error.
for ax,horizon in zip(axes,[10,30]):
    own=[r for r in trace if int(r['subject'])==108 and int(r['horizon'])==horizon and int(r['origin'])<=600 and r['target']!='']
    target_time=[int(r['target_window_end'])/60 for r in own]
    for name,label,color in [('target','Observed future mean','#151515'),('frozen','Frozen HR ridge','#257c55'),('persistence','Last value','#999999')]:
        ax.plot(target_time,[float(r[name]) for r in own],label=label,color=color,lw=1.3)
    ax.set_title(f'{horizon}s forecast · aligned to target window end',loc='left',fontsize=10)
    ax.set_ylabel('HR (bpm)');ax.spines[['top','right']].set_visible(False)
axes[0].legend(frameon=False,ncol=3,fontsize=8)
axes[-1].set_xlabel('Recording time (minutes)')
fig.suptitle('Participant 108 · forecasts issued during first 10 minutes',fontsize=12)
fig.savefig(OUT/'forecast-example.png',dpi=180)
plt.close(fig)

rows=['# Recorded PAMAP2 benchmark','',f"Run: {report['started_at_utc']} to {report['finished_at_utc']}.",'','Frozen split: train101–105, validation106–107, test108–109. Validation selected HR-only ridge(alpha0.1) at both horizons. These test outcomes have now been examined and must not be used for further tuning.','','| Horizon | Participant | Scored / planned origins | Last-value MAE | Frozen ridge MAE | Adaptive MAE |','|---|---|---:|---:|---:|---:|']
for c in coverage:
    h=str(c['horizon']);sid=str(c['subject']);scores=report['test_results'][h]['selected_primary_same_origins']
    vals=[scores[n]['per_participant'].get(sid,{}).get('mae') for n in ['persistence','frozen','adaptive']]
    formatted=['—' if v is None else f'{v:.3f}' for v in vals]
    rows.append(f"|{h}s|{sid}|{c['scored_forecasts']} / {c['planned_origins']}|"+'|'.join(formatted)+'|')
rows.extend(['','The table includes warm-up and end-of-recording origins in its coverage denominator. Input eligibility and missing future targets are separate in coverage-summary.json. Participant109 has only84.76seconds of data: four scored10s forecasts and zero30s forecasts. Do not present the30s result as two-person validation.','','The fixed bias adapter worsened full-run MAE at both horizons. Keep it as a negative result; it is not a validated improvement. Wrist candidates did not win validation and were not substituted after their test results were visible. All seven prespecified candidates remain in report.json.','','At10s, participant-macro MAE is2.808bpm for frozen ridge versus3.081 for persistence; one of its two participants contributes only four forecasts. At30s, only participant108 contributes:7.066 versus7.650bpm. Correlated windows are not independent participants; no population confidence interval, calibrated band, readiness or failure prediction is claimed.','',f"Resources: {report['resources']['wall_seconds']:.2f}s wall, {report['resources']['cpu_seconds']:.2f}s CPU, {report['resources']['peak_rss_bytes']/1024**2:.1f}MiB peak RSS. Raw protocol rows: {sum(x.get('rows',0) for x in inventory):,}; these are public sensor rows, not independent samples.",'','![Held-out errors](heldout-errors.png)','','![Forecast illustration](forecast-example.png)','','Source attribution: Reiss,A.(2012), PAMAP2 Physical Activity Monitoring, UCI Machine Learning Repository, DOI10.24432/C5NW2H, CC BY4.0 per UCI. Figures, features, models and evaluation are derived changes. No app or Apple Watch validation occurred.'])
text='\n'.join(rows)+'\n'
for a,b in [('train101','train 101'),('validation106','validation 106'),('test108','test 108'),('ridge(alpha0.1)','ridge (alpha 0.1)'),('Participant109','Participant 109'),('only84.76seconds','only 84.76 seconds'),('scored10s','scored 10s'),('zero30s','zero 30s'),('the30s','the 30s'),('At10s','At 10s'),('is2.808bpm','is 2.808 bpm'),('versus3.081','versus 3.081'),('At30s','At 30s'),('participant108','participant 108'),('contributes:7.066','contributes: 7.066'),('versus7.650bpm','versus 7.650 bpm'),('Reiss,A.(2012)','Reiss, A. (2012)'),('DOI10.','DOI 10.'),('BY4.0','BY 4.0')]: text=text.replace(a,b)
(OUT/'README.md').write_text(text)
print('Reconciled',len(coverage),'coverage rows; generated two figures without fitting.')
