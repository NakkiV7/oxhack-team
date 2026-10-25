"""Behavioral data-contract checks; these do not assert fitted model accuracy."""
import importlib
import json
from pathlib import Path
import unittest
import numpy as np

PROTOCOL = json.loads((Path(__file__).parents[1] / 'protocol.json').read_text())

class ForecastContractTests(unittest.TestCase):
    def setUp(self):
        self.api = importlib.import_module('research.hr_forecast.forecast')
        self.times = np.arange(0.01, 121.0, 0.01)
        self.hr = 80 + self.times / 10
        self.acc = np.column_stack([np.ones(len(self.times)), np.zeros(len(self.times)), np.ones(len(self.times))*9.8])

    def test_future_samples_cannot_change_origin_features(self):
        first = self.api.extract_features(self.times, self.hr, self.acc, 60, with_wrist=True)
        changed_hr = self.hr.copy(); changed_hr[self.times > 60] = 999
        changed_acc = self.acc.copy(); changed_acc[self.times > 60] = 999
        second = self.api.extract_features(self.times, changed_hr, changed_acc, 60, with_wrist=True)
        self.assertTrue(first['eligible'])
        np.testing.assert_array_equal(first['features'], second['features'])

    def test_target_is_only_five_observed_seconds_ending_at_horizon(self):
        values = np.where(self.times <= 60, 1000, np.where(self.times <= 65, 500, np.where(self.times <= 70, 90, 300)))
        self.assertAlmostEqual(self.api.future_target(self.times, values, 60, 10), 90)
        self.assertAlmostEqual(self.api.future_target(self.times, values, 60, 30), 300)

    def test_missing_target_bin_is_not_filled_or_interpolated(self):
        values = self.hr.copy(); values[(self.times > 67) & (self.times <= 68)] = np.nan
        self.assertIsNone(self.api.future_target(self.times, values, 60, 10))
        self.assertTrue(self.api.extract_features(self.times, values, self.acc, 60)['eligible'])

    def test_stale_or_gappy_history_abstains_even_when_target_exists(self):
        for start, end in [(57, 60), (20, 25)]:
            values = self.hr.copy(); values[(self.times > start) & (self.times <= end)] = np.nan
            result = self.api.extract_features(self.times, values, self.acc, 60)
            self.assertFalse(result['eligible'])
            self.assertIsNotNone(self.api.future_target(self.times, values, 60, 10))

    def test_negative_nonfinite_hr_and_missing_wrist_are_not_measurements(self):
        values = self.hr.copy(); values[self.times <= 60] = -1
        self.assertFalse(self.api.extract_features(self.times, values, self.acc, 60)['eligible'])
        broken = self.acc.copy(); broken[(self.times > 50) & (self.times <= 60)] = np.nan
        self.assertTrue(self.api.extract_features(self.times, self.hr, broken, 60)['eligible'])
        self.assertFalse(self.api.extract_features(self.times, self.hr, broken, 60, with_wrist=True)['eligible'])

    def test_participants_have_one_locked_group_unknown_and_overlap_rejected(self):
        for group in ['train', 'validation', 'test']:
            for subject in PROTOCOL['dataset'][group]:
                self.assertEqual(self.api.split_for_subject(subject, PROTOCOL), group)
        with self.assertRaises(ValueError): self.api.split_for_subject(110, PROTOCOL)
        altered = json.loads(json.dumps(PROTOCOL)); altered['dataset']['test'].append(101)
        with self.assertRaises(ValueError): self.api.split_for_subject(101, altered)

    def test_scaling_uses_training_only_and_handles_constant_feature(self):
        training = np.array([[1., 5.], [3., 5.]])
        scaler = self.api.fit_scaler(training)
        transformed = scaler.transform(np.array([[101., 5.]]))
        self.assertGreater(transformed[0, 0], 90)
        self.assertEqual(transformed[0, 1], 0)
        np.testing.assert_allclose(scaler.transform(training).mean(axis=0), 0)

    def test_nonmonotonic_duplicate_or_negative_timestamps_rejected(self):
        for times in [[0., 2., 1.], [0., 1., 1.], [-1., 0., 1.]]:
            with self.assertRaises(ValueError): self.api.validate_timestamps(np.array(times))

    def test_adaptation_predicts_before_matured_update_and_never_reuses_outcome(self):
        adapter = self.api.BiasAdapter(horizon=10)
        self.assertEqual(adapter.step(0, 100., {}), 100.)
        self.assertEqual(adapter.step(10, 100., {0: 200.}), 100.)
        self.assertEqual(adapter.step(15, 100., {}), 105.)
        with self.assertRaises(ValueError): adapter.step(20, 100., {0: 200.})

    def test_future_outcome_cannot_update_adaptation_and_bias_is_bounded(self):
        adapter = self.api.BiasAdapter(horizon=10)
        adapter.step(0, 100., {})
        with self.assertRaises(ValueError): adapter.step(5, 100., {0: 500.})
        adapter = self.api.BiasAdapter(horizon=10)
        adapter.step(0, 100., {})
        adapter.step(10, 100., {0: 1000.})
        self.assertEqual(adapter.step(20, 100., {}), 110.)

if __name__ == '__main__': unittest.main()
