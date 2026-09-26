"""Publish a verified existing Actions artifact; never replace published releases."""
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def require(condition, message):
    if not condition:
        raise ValueError(message)


def manifest(path):
    data = json.loads(path.read_text(encoding='utf-8'))
    require(re.fullmatch(r'\d+\.\d+\.\d+', data['version']), 'Invalid version')
    require(path.stem == 'v' + data['version'], 'Manifest filename/version mismatch')
    data['tag'] = data.get('tag', 'v' + data['version'])
    require(data['tag'] in ('v' + data['version'], 'native-v' + data['version']), 'Invalid release tag')
    require(re.fullmatch(r'\d+', data['build']), 'Invalid build number')
    require(re.fullmatch(r'[a-f0-9]{40}', data['commit']), 'Invalid source commit')
    require(re.fullmatch(r'[a-f0-9]{64}', data['sha256']), 'Invalid SHA-256')
    require(type(data['run_id']) is int and data['run_id'] > 0, 'Invalid run ID')
    require(data['artifact'] == 'StockLedger-unsigned-IPA', 'Unexpected artifact name')
    require(path.with_suffix('.md').is_file(), 'Release upgrade notes are required')
    return data


def prepare(data, ipa, output, notes, repo):
    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    require(digest == data['sha256'], 'IPA does not match the approved SHA-256')
    subprocess.run([sys.executable, '-X', 'utf8', str(ROOT / 'scripts/verify-ipa.py'), str(ipa)], check=True)
    with zipfile.ZipFile(ipa) as archive:
        info = plistlib.loads(archive.read('Payload/App.app/Info.plist'))
    require(info['CFBundleShortVersionString'] == data['version'], 'IPA version mismatch')
    require(info['CFBundleVersion'] == data['build'], 'IPA build number mismatch')
    output.mkdir(parents=True, exist_ok=True)
    name = f"StockLedger-{data['version']}-unsigned.ipa"
    shutil.copyfile(ipa, output / name)
    (output / (name + '.sha256')).write_text(f'{digest}  {name}\n', encoding='utf-8')
    body = notes.read_text(encoding='utf-8') + (
        f"\n## 构建追溯\n\n- 代码提交：[{data['commit']}](https://github.com/{repo}/commit/{data['commit']})\n"
        f"- 构建记录：https://github.com/{repo}/actions/runs/{data['run_id']}\n"
        f"- IPA SHA-256：`{digest}`\n"
        '\n附件中的 IPA 与上述构建产物完全一致；未重新编译，也未加入签名或用户账本。\n'
    )
    note_file = output / f"UPGRADE-{data['version']}.md"
    note_file.write_text(body, encoding='utf-8')
    return [output / name, output / (name + '.sha256'), note_file]


def gh(*args):
    return subprocess.check_output(['gh', *map(str, args)], text=True, encoding='utf-8')


def publish(path, repo):
    data = manifest(path)
    tag = data['tag']
    refs = json.loads(gh('api', f'repos/{repo}/git/matching-refs/tags/{tag}'))
    if any(ref['ref'] == 'refs/tags/' + tag for ref in refs):
        resolved = json.loads(gh('api', f'repos/{repo}/commits/{tag}'))['sha']
        require(resolved == data['commit'], 'Existing tag points to a different source commit')
    # Listing distinguishes a missing release from an authentication or API error.
    pages = json.loads(gh('api', f'repos/{repo}/releases?per_page=100', '--paginate', '--slurp'))
    existing = next((r for page in pages for r in page if r['tag_name'] == tag), None)
    if existing and not existing['draft']:
        commit = json.loads(gh('api', f'repos/{repo}/commits/{tag}'))['sha']
        require(commit == data['commit'], f'{tag} already points to a different commit')
        assets = {a['name']: a for a in existing['assets']}
        name = f"StockLedger-{data['version']}-unsigned.ipa"
        require(name in assets and name + '.sha256' in assets and f"UPGRADE-{data['version']}.md" in assets, 'Published release is missing required assets; review manually')
        require(assets[name].get('digest') == 'sha256:' + data['sha256'], 'Published IPA digest differs; refusing to overwrite')
        print(f'{tag}: already published and verified; unchanged')
        return
    run = json.loads(gh('api', f"repos/{repo}/actions/runs/{data['run_id']}"))
    require(run['status'] == 'completed' and run['conclusion'] == 'success', 'Source build must succeed')
    require(run['head_sha'] == data['commit'], 'Source run/commit mismatch')
    require(run['path'] == '.github/workflows/build-ios.yml', 'Unexpected source workflow')
    with tempfile.TemporaryDirectory(prefix='stock-ledger-release-') as temp:
        folder = Path(temp)
        gh('run', 'download', data['run_id'], '--repo', repo, '--name', data['artifact'], '--dir', folder / 'download')
        files = prepare(data, folder / 'download/StockLedger-unsigned.ipa', folder / 'publish', path.with_suffix('.md'), repo)
        if not existing:
            gh('release', 'create', tag, '--repo', repo, '--target', data['commit'], '--title', f"持仓账本 {data['version']}", '--notes-file', files[2], '--draft')
        else:
            require(existing['target_commitish'] == data['commit'], 'Draft target mismatch')
            gh('release', 'edit', tag, '--repo', repo, '--notes-file', files[2])
        gh('release', 'upload', tag, *files, '--repo', repo, '--clobber')
        gh('release', 'edit', tag, '--repo', repo, '--draft=false')
        print(f'{tag}: published verified IPA, checksum and upgrade notes')


if __name__ == '__main__':
    repo = os.environ['GH_REPO']
    require(re.fullmatch(r'[\w.-]+/[\w.-]+', repo), 'Invalid repository')
    for path in sorted((ROOT / 'releases').glob('v*.json')):
        publish(path, repo)
