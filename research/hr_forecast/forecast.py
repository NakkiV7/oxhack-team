"""Causal PAMAP2 HR forecast data contract. No device/clinical inference."""
from __future__ import annotations
import numpy as np
from sklearn.preprocessing import StandardScaler


def validate_timestamps(times):
    times = np.asarray(times)
    if times.ndim != 1 or not len(times) or not np.all(np.isfinite(times)) or np.any(times < 0) or np.any(np.diff(times) <= 0):
        raise ValueError('timestamps must be finite, nonnegative and strictly increasing')


def split_for_subject(subject, protocol):
    groups = {name: protocol['dataset'][name] for name in ['train', 'validation', 'test']}
    all_ids = [sid for ids in groups.values() for sid in ids]
    if len(all_ids) != len(set(all_ids)):
        raise ValueError('participants overlap between locked groups')
    found = [name for name, ids in groups.items() if subject in ids]
    if len(found) != 1:
        raise ValueError('unknown participant')
    return found[0]


def fit_scaler(training):
    return StandardScaler().fit(training)


class CausalSeries:
    def __init__(self, times, hr, acc):
        self.times = np.asarray(times, dtype=float)
        validate_timestamps(self.times)
        self.hr = np.asarray(hr, dtype=float)
        self.acc = np.asarray(acc, dtype=float)
        if self.hr.shape != self.times.shape or self.acc.shape != (len(self.times), 3):
            raise ValueError('sensor shapes do not match timestamps')
        self.valid_hr = np.isfinite(self.hr) & (self.hr > 0)
        self.hr_times = self.times[self.valid_hr]
        self.hr_values = self.hr[self.valid_hr]
        # A bin ending at s contains actual measurements in (s-1,s].
        ends = np.ceil(self.hr_times).astype(int)
        size = int(np.ceil(self.times[-1])) + 1
        sums = np.bincount(ends, weights=self.hr_values, minlength=size)
        counts = np.bincount(ends, minlength=size)
        self.bins = np.full(size, np.nan)
        np.divide(sums, counts, out=self.bins, where=counts > 0)

    def features(self, origin, with_wrist=False):
        if origin < 60 or int(origin) != origin:
            return {'eligible': False, 'reason': 'insufficient_history'}
        origin = int(origin)
        hist = self.bins[origin-59:origin+1]
        finite = np.isfinite(hist)
        if len(hist) != 60 or finite.sum() < 54:
            return {'eligible': False, 'reason': 'history_coverage'}
        stop = np.searchsorted(self.hr_times, origin, side='right')
        start = np.searchsorted(self.hr_times, origin-60, side='right')
        past_times = self.hr_times[start:stop]
        if not len(past_times) or origin-past_times[-1] > 2:
            return {'eligible': False, 'reason': 'stale_hr'}
        if np.diff(np.r_[origin-60, past_times, origin]).max() > 4:
            return {'eligible': False, 'reason': 'history_gap'}
        latest = float(self.hr_values[stop-1])
        features = [latest, origin-past_times[-1], float(finite.mean())]
        for window in [10, 30, 60]:
            values = hist[-window:]
            features.extend([float(np.nanmean(values)), float(np.nanstd(values))])
        recent = hist[-30:]
        observed = np.isfinite(recent)
        if observed.sum() < 2 or not np.isfinite(features).all():
            return {'eligible': False, 'reason': 'feature_missing'}
        x = np.arange(30)[observed].astype(float)
        y = recent[observed]
        slope = np.dot(x-x.mean(), y-y.mean()) / np.dot(x-x.mean(), x-x.mean())
        features.extend([float(np.nanmin(hist)), float(np.nanmax(hist)), float(slope), latest-float(np.nanmean(hist))])
        if with_wrist:
            left = np.searchsorted(self.times, origin-10, side='right')
            right = np.searchsorted(self.times, origin, side='right')
            values = self.acc[left:right]
            valid = np.isfinite(values).all(axis=1)
            if valid.sum() < 900:
                return {'eligible': False, 'reason': 'wrist_coverage'}
            norms = np.linalg.norm(values[valid], axis=1)
            # Differences use adjacent observed samples only; never bridge missing samples.
            adjacent = valid[1:] & valid[:-1]
            full_norms = np.linalg.norm(values, axis=1)
            differences = np.diff(full_norms)[adjacent]
            if not len(differences):
                return {'eligible': False, 'reason': 'wrist_gap'}
            features.extend([float(norms.mean()), float(norms.std()), float(np.percentile(norms, 95)), float(np.sqrt(np.mean(differences**2)))])
        return {'eligible': True, 'reason': None, 'features': np.array(features), 'latest_hr': latest}

    def target(self, origin, horizon):
        if horizon not in [10, 30] or int(origin) != origin:
            raise ValueError('unsupported target alignment')
        end = int(origin+horizon)
        values = self.bins[end-4:end+1]
        if len(values) != 5 or not np.isfinite(values).all():
            return None
        return float(values.mean())


def extract_features(times, hr, acc, origin, with_wrist=False):
    return CausalSeries(times, hr, acc).features(origin, with_wrist)


def future_target(times, hr, origin, horizon):
    return CausalSeries(times, hr, np.zeros((len(times), 3))).target(origin, horizon)


class BiasAdapter:
    """Issue current forecast before applying previously issued, now mature labels."""
    def __init__(self, horizon):
        self.horizon = horizon
        self.bias = 0.
        self.pending = {}
        self.used = set()
        self.last_origin = -np.inf
        self.update_count = 0

    def step(self, origin, base_prediction, matured_outcomes):
        if not np.isfinite(base_prediction) or origin <= self.last_origin:
            raise ValueError('prediction origins must advance with finite predictions')
        for previous, target in matured_outcomes.items():
            if previous not in self.pending or previous in self.used or previous+self.horizon > origin or not np.isfinite(target):
                raise ValueError('outcome is unknown, repeated, invalid or not yet mature')
        prediction = float(base_prediction+self.bias)
        self.pending[origin] = float(base_prediction)
        self.last_origin = origin
        for previous, target in sorted(matured_outcomes.items()):
            self.bias = float(np.clip(.95*self.bias+.05*(target-self.pending[previous]), -10, 10))
            self.used.add(previous)
            self.update_count += 1
        return prediction
