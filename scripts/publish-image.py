#!/usr/bin/env python3
"""Publish a unique candidate, verify remote bytes, then promote latest last.

Run only in the serialized main-branch publication job, after local image smoke.
All external commands use argv arrays. No credentials are persisted in receipts.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import sys

DIGEST = re.compile(r'sha256:[0-9a-f]{64}')
SHA = re.compile(r'[0-9a-f]{40}')


def command(*args: str) -> str:
    return subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE).stdout.strip()


class Publisher:
    def __init__(self, env: dict[str, str], run=command):
        self.env, self.run = env, run
        self.repo = env['GITHUB_REPOSITORY']
        self.sha = env['GITHUB_SHA']
        self.base = env['UPSTREAM_DIGEST']
        self.image = env['CUSTOM_IMAGE']
        self.candidate = env['CANDIDATE_TAG']
        if (env['GITHUB_REF'] != 'refs/heads/main'
                or not SHA.fullmatch(self.sha) or not DIGEST.fullmatch(self.base)
                or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', self.repo)
                or self.image != f'ghcr.io/{self.repo.lower()}'
                or not re.fullmatch(r'build-[0-9a-f]{12}-upstream-[0-9a-f]{12}-run-[0-9]+-[0-9]+', self.candidate)
                or not re.fullmatch(r'\d{4}-\d{2}-\d{2}', env['IMAGE_DATE'])):
            raise ValueError('invalid publication identity or non-main branch')
        expected = f"build-{self.sha[:12]}-upstream-{self.base[7:19]}-run-{env['GITHUB_RUN_ID']}-{env['GITHUB_RUN_ATTEMPT']}"
        if self.candidate != expected:
            raise ValueError('candidate tag does not bind this run/source/base')
        self.labels = {
            'org.opencontainers.image.source': f"{env['GITHUB_SERVER_URL']}/{self.repo}",
            'org.opencontainers.image.revision': self.sha,
            'org.opencontainers.image.created': env['IMAGE_CREATED'],
            'org.opencontainers.image.base.name': env['UPSTREAM_IMAGE'],
            'org.opencontainers.image.base.digest': self.base,
        }
        self.receipt = {'status': 'started', 'candidate': f'{self.image}:{self.candidate}',
                        'source': self.sha, 'base': self.base,
                        'pushed_aliases': [], 'verified_aliases': []}

    def remote_digest(self, ref: str) -> str:
        digest = self.run('docker', 'buildx', 'imagetools', 'inspect', ref,
                          '--format', '{{.Manifest.Digest}}')
        if not DIGEST.fullmatch(digest):
            raise ValueError('registry returned an invalid digest')
        return digest

    def current(self) -> bool:
        head = self.run('gh', 'api', f'repos/{self.repo}/git/ref/heads/main', '--jq', '.object.sha')
        if not SHA.fullmatch(head):
            raise ValueError('GitHub returned an invalid main SHA')
        # A valid obsolete candidate is retained, but never promoted.
        return head == self.sha and self.remote_digest(self.env['UPSTREAM_IMAGE']) == self.base

    def publish(self) -> dict:
        candidate = self.receipt['candidate']
        local_id = self.run('docker', 'image', 'inspect', '--format', '{{.Id}}', candidate)
        if not DIGEST.fullmatch(local_id):
            raise ValueError('local image has no valid config identity')
        self.run('docker', 'push', candidate)
        digest = self.remote_digest(candidate)
        ref = f'{self.image}@{digest}'
        self.receipt['digest'] = digest
        self.run('docker', 'pull', ref)
        remote_id = self.run('docker', 'image', 'inspect', '--format', '{{.Id}}', ref)
        if remote_id != local_id:
            raise ValueError('downloaded image differs from the locally smoked candidate')
        labels = json.loads(self.run('docker', 'image', 'inspect', '--format', '{{json .Config.Labels}}', ref))
        if not isinstance(labels, dict) or any(labels.get(k) != v for k, v in self.labels.items()):
            raise ValueError('downloaded image provenance mismatch')
        # Fresh home, normal upstream entrypoint/privilege drop, no egress or secrets.
        self.run('docker', 'run', '--rm', '--network=none', ref,
                 'sh', '-lc', 'hermes-custom-runtime-health')
        self.receipt['remote_health'] = 'passed'
        for tag in (self.env['IMAGE_DATE'], f'upstream-{self.base[7:]}', 'latest'):
            if not self.current():
                self.receipt['status'] = 'superseded'
                return self.receipt
            alias = f'{self.image}:{tag}'
            self.run('docker', 'tag', ref, alias)
            self.run('docker', 'push', alias)
            self.receipt['pushed_aliases'].append(tag)
            if self.remote_digest(alias) != digest:
                raise ValueError(f'remote digest mismatch after promoting {tag}')
            self.receipt['verified_aliases'].append(tag)
        self.receipt['status'] = 'published'
        return self.receipt


def main() -> int:
    publisher = None
    try:
        publisher = Publisher(dict(os.environ))
        publisher.publish()
        return 0
    except (KeyError, ValueError, OSError, subprocess.CalledProcessError) as error:
        if publisher:
            publisher.receipt['status'] = 'failed'
        print(f'Image publication failed: {error}', file=sys.stderr)
        return 1
    finally:
        if publisher:
            payload = json.dumps(publisher.receipt, indent=2)
            print(payload)
            if path := os.environ.get('PUBLICATION_RECEIPT'):
                Path(path).write_text(payload + '\n')
            if path := os.environ.get('GITHUB_STEP_SUMMARY'):
                with open(path, 'a') as stream:
                    stream.write('## Image publication receipt\n```json\n' + payload + '\n```\n')


if __name__ == '__main__':
    raise SystemExit(main())
