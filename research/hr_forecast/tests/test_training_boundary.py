import importlib
import unittest
import numpy as np

class TrainingBoundaryTests(unittest.TestCase):
    def records(self):
        rows=[]
        for subject, group in [(101,'train'),(102,'train'),(106,'validation'),(108,'test')]:
            for i in range(8):
                x=np.arange(13,dtype=float)+i
                rows.append({'subject':subject,'group':group,'origin':i*5,'latest_hr':80.+i,'target':82.+i,'features':x,'wrist_features':np.r_[x,[1.,2.,3.,4.]]})
        return rows

    def test_held_out_labels_and_features_cannot_affect_fitted_models(self):
        api=importlib.import_module('research.hr_forecast.benchmark')
        first=self.records(); changed=self.records()
        for row in changed:
            if row['group']!='train':
                row['features'][:]=100000
                row['wrist_features'][:]=100000
                row['target']=-100000
        models1=api.fit_candidates(first); models2=api.fit_candidates(changed)
        probe=first[-1]
        self.assertEqual(set(models1),set(models2))
        for name in models1:
            np.testing.assert_array_equal(models1[name].predict([probe]),models2[name].predict([probe]))

    def test_model_selection_refuses_test_rows(self):
        api=importlib.import_module('research.hr_forecast.benchmark')
        rows=self.records(); models=api.fit_candidates(rows)
        with self.assertRaises(ValueError): api.choose_candidate(models,[r for r in rows if r['group']=='test'])
        selected=api.choose_candidate(models,[r for r in rows if r['group']=='validation'])
        self.assertIn(selected['selected'],models)
        self.assertEqual(selected['participants'],[106])


class SourceIntegrityTests(unittest.TestCase):
    def test_changed_archive_cannot_be_used_with_original_provenance(self):
        import tempfile,hashlib
        from pathlib import Path
        api=importlib.import_module('research.hr_forecast.benchmark')
        with tempfile.TemporaryDirectory() as folder:
            archive=Path(folder)/'data.zip';archive.write_bytes(b'original public input')
            expected=hashlib.sha256(archive.read_bytes()).hexdigest()
            api.verify_archive(archive,expected)
            archive.write_bytes(b'different input')
            with self.assertRaises(ValueError): api.verify_archive(archive,expected)

if __name__=='__main__': unittest.main()
