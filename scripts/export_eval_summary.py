#!/usr/bin/env python3
"""Export aggregate evidence from a completed LiteRTEvalBatchProbe run, without answer text.

This validates and summarizes existing scores; it does not run or score a language model.
"""
import argparse
import hashlib
import json
import math
from collections import Counter
from pathlib import Path
from statistics import median


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def indexed(rows, label):
    result = {}
    for row in rows:
        identifier = row.get('id')
        if not isinstance(identifier, str) or not identifier or identifier in result:
            raise ValueError(f'{label}: missing or duplicate case id')
        result[identifier] = row
    if not result:
        raise ValueError(f'{label}: empty case set')
    return result


def summarize(run_dir, cases_file, app_revision, host):
    summary_file = run_dir / 'litert-eval-result.json'
    results_file = run_dir / 'litert-eval-results.jsonl'
    scores_file = run_dir / 'objective-scores-v2.json'
    summary = json.loads(summary_file.read_text())
    score_document = json.loads(scores_file.read_text())
    expected = indexed(read_jsonl(cases_file), 'fixtures')
    results = indexed(read_jsonl(results_file), 'results')
    scores = indexed(score_document['cases'], 'scores')
    if set(expected) != set(results) or set(expected) != set(scores):
        raise ValueError('fixtures, results and scores must contain exactly the same case ids')
    if (summary.get('error') or not summary.get('finishedAt')
            or summary.get('caseCount') != len(expected)):
        raise ValueError('run has no valid completion marker or case count')
    if summary.get('evalFileSHA256') != digest(cases_file):
        raise ValueError('fixture hash differs from the completed run')
    errors = sum(bool(row.get('error')) for row in results.values())
    if summary.get('failedCount') != errors:
        raise ValueError('runtime error count differs from completion marker')
    categories = {}
    durations = []
    outcomes = Counter()
    passed = 0
    for identifier, row in results.items():
        seconds = row.get('seconds')
        if (isinstance(seconds, bool) or not isinstance(seconds, (float, int))
                or not math.isfinite(seconds) or seconds < 0):
            raise ValueError('answer duration must be finite and nonnegative')
        score = scores[identifier]
        outcome = score.get('outcome')
        if outcome not in {'pass', 'abstained', 'incomplete_or_wrong', 'reject'}:
            raise ValueError('unrecognized score outcome')
        if score.get('objective_pass') is not (outcome == 'pass'):
            raise ValueError('score pass flag differs from outcome')
        if row.get('error') and outcome != 'reject':
            raise ValueError('runtime failure must be scored as reject')
        score_seconds = score.get('seconds')
        if not isinstance(score_seconds, (float, int)) or abs(score_seconds - seconds) > 0.011:
            raise ValueError('score duration differs from raw result')
        category = expected[identifier]['category']
        if score.get('category') != category:
            raise ValueError('score category differs from fixture')
        counts = categories.setdefault(category, {'cases': 0, 'objective_passed': 0})
        counts['cases'] += 1
        counts['objective_passed'] += outcome == 'pass'
        passed += outcome == 'pass'
        outcomes[outcome] += 1
        durations.append(seconds)
    recorded = score_document['summary']
    if recorded.get('cases') != len(expected) or recorded.get('objective_passed') != passed:
        raise ValueError('aggregate score disagrees with per-case scores')
    model = summary['model']
    device = summary['device']
    # Deliberate allowlist: never export prompts, answers, paths, device ids or native logs.
    return {
        'schema_version': 1,
        'run_id': summary['runID'],
        'started_at': summary['startedAt'],
        'finished_at': summary['finishedAt'],
        'app_revision': app_revision,
        'host': host,
        'environment': 'simulator CPU' if device['isSimulator'] and summary['usesCPU']
            else ('simulator' if device['isSimulator'] else 'physical device'),
        'os_version': device['systemVersion'],
        'thinking_enabled': summary['thinkingEnabled'],
        'model_bytes': model['byteCount'],
        'model_sha256': model['sha256'],
        'fixture_sha256': digest(cases_file),
        'cases': len(expected),
        'runtime_errors': errors,
        'objective_passed': passed,
        'outcomes': dict(sorted(outcomes.items())),
        'categories': dict(sorted(categories.items())),
        'median_answer_seconds': round(median(durations), 3),
        'scorer': recorded['scorer'],
        'input_sha256': {
            'completion': digest(summary_file),
            'results': digest(results_file),
            'scores': digest(scores_file),
        },
        'limitations': [
            'Previously used development sets; not an independent acceptance benchmark.',
            'Objective pattern checks are not a complete assessment of correctness or usefulness.',
            'Answer duration measures the eval adapter, not queue-to-visible UI latency.',
            'Simulator results do not establish phone latency, memory, thermal or battery behavior.',
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-dir', type=Path, required=True)
    parser.add_argument('--cases', type=Path, required=True)
    parser.add_argument('--app-revision', required=True)
    parser.add_argument('--host', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--scorer-artifact', type=Path, action='append', default=[],
                        help='Optional scorer or additions file to fingerprint (repeatable).')
    args = parser.parse_args()
    try:
        report = summarize(args.run_dir, args.cases, args.app_revision, args.host)
        if args.scorer_artifact:
            names = [path.name for path in args.scorer_artifact]
            if len(names) != len(set(names)):
                raise ValueError('scorer artifact basenames must be unique')
            report['scorer_sha256'] = {path.name: digest(path) for path in args.scorer_artifact}
    except (ValueError, KeyError, OSError, TypeError) as error:
        parser.exit(1, f'Cannot export evidence: {error}\n')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + '\n')
    print(f"Exported {report['run_id']}: {report['objective_passed']}/{report['cases']}")


if __name__ == '__main__':
    main()
