# SPDX-License-Identifier: GPL-3.0-or-later
import base64
import hashlib
import json
import os
import pathlib
import subprocess
import urllib.request

repo = os.environ['GITHUB_REPOSITORY']
token = os.environ['GITHUB_TOKEN']
base = os.environ['GITHUB_SHA']
out_path = pathlib.Path(os.environ['GITHUB_OUTPUT'])
patch_path = pathlib.Path(os.environ['PRE_MS_PATCH'])
api = f'https://api.github.com/repos/{repo}'


def request(method, path, payload=None):
    data = None if payload is None else json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(api + path, data=data, method=method)
    req.add_header('Authorization', f'Bearer {token}')
    req.add_header('Accept', 'application/vnd.github+json')
    req.add_header('X-GitHub-Api-Version', '2022-11-28')
    with urllib.request.urlopen(req) as response:
        return json.load(response)


# Remove every temporary pre-MS mechanism from the candidate itself.
for rel in (
    'tools/apply-pre-ms-hardening.py',
    'tools/pre-ms-update-docs.py',
    'tools/create-pre-ms-detached.py',
    '.github/workflows/pre-ms-hardening.yml',
    '.github/workflows/run-pre-ms-hardening.yml',
    '.github/workflows/run-pre-ms-push.yml',
    '.github/workflows/run-pre-ms-push-v2.yml',
    '.github/workflows/pre-ms-issue-v3.yml',
):
    if pathlib.Path(rel).exists():
        subprocess.run(['git', 'rm', '-f', rel], check=True)

patch_path.parent.mkdir(parents=True, exist_ok=True)
with patch_path.open('wb') as handle:
    subprocess.run(['git', 'diff', '--binary', 'HEAD'], stdout=handle, check=True)
patch_hash = hashlib.sha256(patch_path.read_bytes()).hexdigest()

base_commit = request('GET', f'/git/commits/{base}')
entries = []
raw = subprocess.check_output(['git', 'diff', '--name-status', '-z', 'HEAD'])
fields = raw.decode('utf-8').split('\0')
i = 0
while i < len(fields) and fields[i]:
    status = fields[i]
    i += 1
    path = fields[i]
    i += 1
    if status.startswith(('R', 'C')):
        path = fields[i]
        i += 1
    if status.startswith('D'):
        entries.append({'path': path, 'mode': '100644', 'type': 'blob', 'sha': None})
        continue
    content = pathlib.Path(path).read_bytes()
    blob = request('POST', '/git/blobs', {
        'content': base64.b64encode(content).decode('ascii'),
        'encoding': 'base64',
    })
    ls = subprocess.check_output(['git', 'ls-files', '-s', '--', path]).decode('utf-8').split()
    mode = ls[0] if ls else '100644'
    entries.append({'path': path, 'mode': mode, 'type': 'blob', 'sha': blob['sha']})

tree = request('POST', '/git/trees', {
    'base_tree': base_commit['tree']['sha'],
    'tree': entries,
})
commit = request('POST', '/git/commits', {
    'message': 'Pre-MS hardening: lifecycle and filename correctness',
    'tree': tree['sha'],
    'parents': [base],
})
with out_path.open('a', encoding='utf-8') as handle:
    handle.write(f"source_sha={commit['sha']}\n")
    handle.write(f"base_sha={base}\n")
    handle.write(f"patch_sha256={patch_hash}\n")
print(f"Detached candidate: {commit['sha']}")
print(f"Patch SHA-256: {patch_hash}")
