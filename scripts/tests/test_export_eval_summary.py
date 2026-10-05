import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('exporter', Path(__file__).parents[1] / 'export_eval_summary.py')
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


class EvidenceExportTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.fixtures = self.root / 'cases.jsonl'
        self.fixtures.write_text(json.dumps({'id': 'a', 'category': 'source'}) + '\n')
        self.results = [{'id': 'a', 'seconds': 3.0, 'text': 'PRIVATE ANSWER', 'error': None}]
        self.scores = {'cases': [{'id': 'a', 'category': 'source', 'seconds': 3.0,
                                 'outcome': 'pass', 'objective_pass': True}],
                       'summary': {'cases': 1, 'objective_passed': 1, 'scorer': 'v2'}}
        self.summary = {'runID': 'example', 'startedAt': '2026-10-02T00:00:00Z',
                        'finishedAt': '2026-10-02T00:01:00Z', 'caseCount': 1, 'failedCount': 0,
                        'evalFileSHA256': exporter.digest(self.fixtures), 'thinkingEnabled': False,
                        'usesCPU': True, 'device': {'isSimulator': True, 'systemVersion': '27.0'},
                        'model': {'sha256': 'example-hash', 'byteCount': 100, 'path': '/PRIVATE/PATH'},
                        'launchArguments': ['PRIVATE ARGUMENT']}

    def export(self):
        (self.root / 'litert-eval-results.jsonl').write_text(
            '\n'.join(json.dumps(row) for row in self.results))
        (self.root / 'objective-scores-v2.json').write_text(json.dumps(self.scores))
        (self.root / 'litert-eval-result.json').write_text(json.dumps(self.summary))
        return exporter.summarize(self.root, self.fixtures, 'revision', 'test host')

    def test_export_excludes_personal_content_and_paths(self):
        report = self.export()
        self.assertEqual(report['objective_passed'], 1)
        self.assertEqual(report['median_answer_seconds'], 3.0)
        self.assertNotIn('PRIVATE', json.dumps(report))

    def test_duplicate_results_rejected(self):
        self.results.append(self.results[0])
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            self.export()

    def test_missing_case_rejected(self):
        self.scores['cases'][0]['id'] = 'other'
        with self.assertRaisesRegex(ValueError, 'same case ids'):
            self.export()

    def test_unfinished_run_rejected(self):
        self.summary.pop('finishedAt')
        with self.assertRaisesRegex(ValueError, 'completion'):
            self.export()

    def test_changed_fixtures_rejected(self):
        self.fixtures.write_text(self.fixtures.read_text() + '\n')
        with self.assertRaisesRegex(ValueError, 'fixture hash'):
            self.export()

    def test_nonfinite_duration_rejected(self):
        self.results[0]['seconds'] = float('nan')
        with self.assertRaisesRegex(ValueError, 'finite'):
            self.export()

    def test_inconsistent_pass_total_rejected(self):
        self.scores['summary']['objective_passed'] = 0
        with self.assertRaisesRegex(ValueError, 'aggregate score'):
            self.export()

    def test_runtime_failure_cannot_be_pass(self):
        self.results[0]['error'] = 'failure'
        self.summary['failedCount'] = 1
        with self.assertRaisesRegex(ValueError, 'reject'):
            self.export()

    def test_score_timing_must_match_raw_result(self):
        self.scores['cases'][0]['seconds'] = 10.0
        with self.assertRaisesRegex(ValueError, 'duration differs'):
            self.export()


if __name__ == '__main__':
    unittest.main()
