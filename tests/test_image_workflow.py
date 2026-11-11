"""Offline command-boundary regressions; not a substitute for Docker/GHCR CI."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import types
import unittest
from unittest.mock import patch
from collections.abc import Callable

ROOT = Path(__file__).resolve().parents[1]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / filename)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


publish = load('publish_image', 'publish-image.py')
health = load('runtime_health', 'runtime-health.py')


def environment():
    return dict(GITHUB_REPOSITORY='Develata/hermes-agent-custom-image',
                GITHUB_SHA='a' * 40, UPSTREAM_DIGEST='sha256:' + 'b' * 64,
                CUSTOM_IMAGE='ghcr.io/develata/hermes-agent-custom-image',
                CANDIDATE_TAG='build-' + 'a' * 12 + '-upstream-' + 'b' * 12 + '-run-42-1',
                GITHUB_RUN_ID='42', GITHUB_RUN_ATTEMPT='1', GITHUB_REF='refs/heads/main',
                IMAGE_DATE='2026-11-11', IMAGE_CREATED='2026-11-11T03:00:00Z',
                GITHUB_SERVER_URL='https://github.com', UPSTREAM_IMAGE='nousresearch/hermes-agent:latest')


class Registry:
    """Explicit fake external boundary: every unrecognized command fails."""
    def __init__(self):
        self.calls = []
        self.env = environment()
        self.digest = 'sha256:' + 'c' * 64
        self.image_id = 'sha256:' + 'd' * 64
        self.head = self.env['GITHUB_SHA']
        self.base = self.env['UPSTREAM_DIGEST']
        self.remote_id = self.image_id
        self.labels = publish.Publisher(self.env).labels.copy()
        self.fail: Callable[[tuple[str, ...]], bool] | None = None
        self.alias_digest = self.digest
        self.advance_after_alias = False

    def __call__(self, *args):
        self.calls.append(args)
        if self.fail and self.fail(args):
            raise subprocess.CalledProcessError(1, args)
        if args[:3] == ('docker', 'image', 'inspect'):
            return (self.image_id if '@' not in args[-1] else self.remote_id) if args[4] == '{{.Id}}' else json.dumps(self.labels)
        if args[:2] == ('docker', 'push'):
            if self.advance_after_alias and args[-1].endswith(':2026-11-11'):
                self.head = 'e' * 40
            return ''
        if args[:4] == ('docker', 'buildx', 'imagetools', 'inspect'):
            if args[4] == self.env['UPSTREAM_IMAGE']:
                return self.base
            return self.digest if ':build-' in args[4] else self.alias_digest
        if args[:2] in [('docker', 'pull'), ('docker', 'tag'), ('docker', 'run')]:
            return ''
        if args[:2] == ('gh', 'api'):
            return self.head
        raise AssertionError(f'unexpected external command: {args}')

    def aliases(self):
        return [c[-1].split(':')[-1] for c in self.calls if c[:2] == ('docker', 'push') and ':build-' not in c[-1]]


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.registry = Registry()
        self.publisher = publish.Publisher(environment(), self.registry)

    def test_success_candidate_first_latest_last_and_read_back(self):
        receipt = self.publisher.publish()
        self.assertEqual(receipt['status'], 'published')
        self.assertEqual(self.registry.aliases(), ['2026-11-11', 'upstream-' + 'b' * 64, 'latest'])
        calls = self.registry.calls
        candidate_push = next(i for i,c in enumerate(calls) if c[:2] == ('docker','push'))
        health_run = next(i for i,c in enumerate(calls) if c[:2] == ('docker','run'))
        first_tag = next(i for i,c in enumerate(calls) if c[:2] == ('docker','tag'))
        self.assertLess(candidate_push, health_run)
        self.assertLess(health_run, first_tag)
        self.assertIn('--network=none', calls[health_run])
        self.assertEqual(len(receipt['verified_aliases']), 3)
        self.assertTrue(calls[-1][4].endswith(':latest'))

    def test_failed_candidate_push_never_promotes(self):
        self.registry.fail = lambda a: a[:2] == ('docker','push')
        with self.assertRaises(subprocess.CalledProcessError): self.publisher.publish()
        self.assertEqual(self.registry.aliases(), [])

    def test_failed_remote_pull_never_promotes(self):
        self.registry.fail = lambda a: a[:2] == ('docker','pull')
        with self.assertRaises(subprocess.CalledProcessError): self.publisher.publish()
        self.assertEqual(self.registry.aliases(), [])

    def test_remote_health_failure_never_promotes(self):
        self.registry.fail = lambda a: a[:2] == ('docker','run')
        with self.assertRaises(subprocess.CalledProcessError): self.publisher.publish()
        self.assertEqual(self.registry.aliases(), [])

    def test_remote_bytes_mismatch_never_promotes(self):
        self.registry.remote_id = 'sha256:' + 'e' * 64
        with self.assertRaisesRegex(ValueError,'differs'): self.publisher.publish()
        self.assertEqual(self.registry.aliases(), [])

    def test_every_provenance_field_is_required(self):
        for key in self.publisher.labels:
            with self.subTest(key=key):
                registry = Registry(); del registry.labels[key]
                with self.assertRaisesRegex(ValueError,'provenance'): publish.Publisher(environment(),registry).publish()
                self.assertEqual(registry.aliases(), [])

    def test_stale_main_cannot_promote(self):
        self.registry.head = 'e' * 40
        self.assertEqual(self.publisher.publish()['status'], 'superseded')
        self.assertEqual(self.registry.aliases(), [])

    def test_stale_base_cannot_promote(self):
        self.registry.base = 'sha256:' + 'e' * 64
        self.assertEqual(self.publisher.publish()['status'], 'superseded')
        self.assertEqual(self.registry.aliases(), [])

    def test_head_advances_mid_promotion_latest_untouched(self):
        self.registry.advance_after_alias = True
        self.assertEqual(self.publisher.publish()['status'], 'superseded')
        self.assertEqual(self.registry.aliases(), ['2026-11-11'])

    def test_failed_alias_push_keeps_latest_untouched(self):
        self.registry.fail = lambda a: a[:2] == ('docker','push') and ':upstream-' in a[-1]
        with self.assertRaises(subprocess.CalledProcessError): self.publisher.publish()
        self.assertNotIn('latest', self.registry.aliases())

    def test_alias_read_back_mismatch_aborts_before_latest(self):
        self.registry.alias_digest = 'sha256:' + 'e' * 64
        with self.assertRaisesRegex(ValueError,'remote digest mismatch'): self.publisher.publish()
        self.assertNotIn('latest', self.registry.aliases())

    def test_invalid_registry_digest_aborts(self):
        self.registry.digest = 'not-a-digest'
        with self.assertRaisesRegex(ValueError,'invalid digest'): self.publisher.publish()
        self.assertEqual(self.registry.aliases(), [])

    def test_cli_records_failure_and_verified_partial_state(self):
        import tempfile, os
        registry = self.registry
        registry.fail = lambda a: a[:2] == ('docker','run')
        original = publish.Publisher
        with tempfile.TemporaryDirectory() as temp:
            receipt=Path(temp)/'receipt.json'; summary=Path(temp)/'summary.md'
            env={**environment(),'PUBLICATION_RECEIPT':str(receipt),'GITHUB_STEP_SUMMARY':str(summary)}
            with patch.dict(os.environ,env,clear=True), patch.object(publish,'Publisher',side_effect=lambda e: original(e,registry)):
                self.assertEqual(publish.main(),1)
            data=json.loads(receipt.read_text())
            self.assertEqual(data['status'],'failed')
            self.assertEqual(data['verified_aliases'],[])
            self.assertNotIn('remote_health',data)
            self.assertIn('Image publication receipt',summary.read_text())

    def test_main_lookup_failure_does_not_promote(self):
        self.registry.fail = lambda a: a[:2] == ('gh','api')
        with self.assertRaises(subprocess.CalledProcessError): self.publisher.publish()
        self.assertEqual(self.registry.aliases(), [])

    def test_bad_identity_fails_before_external_commands(self):
        for key,value in [('GITHUB_REF','refs/heads/other'), ('GITHUB_SHA','bad'),
                          ('UPSTREAM_DIGEST','bad'), ('CUSTOM_IMAGE','ghcr.io/foreign/image'),
                          ('CANDIDATE_TAG','build-not-this-run'), ('GITHUB_RUN_ATTEMPT','2')]:
            with self.subTest(key=key):
                env=environment(); env[key]=value
                with self.assertRaises(ValueError): publish.Publisher(env,self.registry)
        self.assertEqual(self.registry.calls, [])


class HealthTests(unittest.TestCase):
    def native(self, problem=None):
        module=types.ModuleType('hermes_cli.venv_sync')
        setattr(module, 'check_runtime', lambda root: problem)
        return patch.dict(sys.modules, {'hermes_cli':types.ModuleType('hermes_cli'), 'hermes_cli.venv_sync':module})

    def test_doctor_failure_is_not_swallowed(self):
        with patch.object(health.subprocess,'run',return_value=types.SimpleNamespace(returncode=1)):
            self.assertEqual(health.main(),1)

    def test_passive_drift_is_not_swallowed(self):
        with patch.object(health.subprocess,'run',return_value=types.SimpleNamespace(returncode=0)), self.native('pnpm missing'):
            self.assertEqual(health.main(),1)

    def test_both_native_checks_must_pass(self):
        with patch.object(health.subprocess,'run',return_value=types.SimpleNamespace(returncode=0)) as run, self.native():
            self.assertEqual(health.main(),0)
            self.assertEqual(run.call_args.args[0][-3:], ['-m','pm.cli','doctor'])

    def test_shell_smoke_propagates_native_health_failure(self):
        import tempfile, os
        with tempfile.TemporaryDirectory() as temp:
            binary=Path(temp)/'hermes-custom-runtime-health'; binary.write_text('#!/bin/sh\nexit 17\n'); binary.chmod(0o755)
            cp=subprocess.run(['sh',str(ROOT/'scripts/smoke-image.sh')],env={**os.environ,'PATH':temp+':'+os.environ['PATH']},capture_output=True)
            self.assertEqual(cp.returncode,17)


class WorkflowTests(unittest.TestCase):
    def test_publication_is_serialized_main_only_and_unique_per_attempt(self):
        source=(ROOT/'.github/workflows/docker-build.yml').read_text()
        self.assertIn('group: docker-publish-main',source)
        self.assertIn('cancel-in-progress: false',source)
        self.assertIn("if: github.ref == 'refs/heads/main'",source)
        self.assertIn('-run-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}',source)
        self.assertNotIn('docker manifest inspect',source)
        self.assertIn('latest already matches source and upstream digest',source)
        self.assertIn('python3 scripts/publish-image.py',source)

    def test_pr_still_builds_and_smokes_without_write_permission(self):
        source=(ROOT/'.github/workflows/docker-pr.yml').read_text()
        self.assertIn('pull_request:',source)
        self.assertIn('hermes-custom-image-smoke',source)
        self.assertNotIn('packages: write',source)
        self.assertNotIn('publish-image.py',source)

    def test_runtime_pnpm_uses_native_locked_pm_not_npm_global(self):
        source=(ROOT/'Dockerfile').read_text()
        self.assertIn('ensure("pnpm", explicit=True)',source)
        self.assertIn('installed_package("pnpm").binary',source)
        self.assertIn('paths.facts_path().chmod(0o644)',source)
        self.assertIn('scripts/runtime-health.py /usr/local/bin/hermes-custom-runtime-health',source)
        self.assertNotIn('npm install -g pnpm',source)


class ScheduleTests(unittest.TestCase):
    def run_decision(self, case, event='schedule'):
        import os, tempfile, textwrap
        source=(ROOT/'.github/workflows/docker-build.yml').read_text()
        section=source.split('      - name: Check upstream digest\n',1)[1]
        body=section.split('        run: |\n',1)[1].split('\n      - name:',1)[0]
        body=textwrap.dedent(body).strip()
        with tempfile.TemporaryDirectory() as temp:
            binary=Path(temp)/'docker'
            binary.write_text('''#!/usr/bin/env python3
import json,os,sys
case=os.environ['TEST_CASE']
if sys.argv[4]=='nousresearch/hermes-agent:latest':
 print('invalid' if case=='invalid' else 'sha256:'+'b'*64)
else:
 print(json.dumps({'org.opencontainers.image.revision':('e'*40 if case=='source_changed' else 'a'*40),
 'org.opencontainers.image.base.digest':('sha256:'+'e'*64 if case=='base_changed' else 'sha256:'+'b'*64)}))
''')
            binary.chmod(0o755)
            output=Path(temp)/'output'
            env={**os.environ, **environment(), 'PATH':temp+':'+os.environ['PATH'],
                 'TEST_CASE':case, 'GITHUB_EVENT_NAME':event,'GITHUB_OUTPUT':str(output),
                 'IMAGE_OWNER':'develata','IMAGE_NAME':'hermes-agent-custom-image','CUSTOM_REVISION':'a'*12}
            cp=subprocess.run(['bash','-e','-o','pipefail','-c',body],env=env,text=True,capture_output=True)
            return cp,dict(line.split('=',1) for line in output.read_text().splitlines()) if output.exists() else {}

    def test_matching_latest_skips(self):
        cp,out=self.run_decision('matching')
        self.assertEqual(cp.returncode,0,cp.stderr)
        self.assertEqual(out['should_build'],'false')
        self.assertTrue(out['immutable_tag'].endswith('-run-42-1'))

    def test_source_change_rebuilds_even_with_same_base(self):
        cp,out=self.run_decision('source_changed')
        self.assertEqual(cp.returncode,0,cp.stderr)
        self.assertEqual(out['should_build'],'true')

    def test_base_change_rebuilds(self):
        cp,out=self.run_decision('base_changed')
        self.assertEqual(cp.returncode,0,cp.stderr)
        self.assertEqual(out['should_build'],'true')

    def test_manual_build_does_not_skip_matching_latest(self):
        cp,out=self.run_decision('matching','workflow_dispatch')
        self.assertEqual(cp.returncode,0,cp.stderr)
        self.assertEqual(out['should_build'],'true')

    def test_invalid_upstream_digest_fails_closed(self):
        cp,out=self.run_decision('invalid')
        self.assertNotEqual(cp.returncode,0)
        self.assertNotIn('should_build',out)


if __name__ == '__main__':
    unittest.main()
