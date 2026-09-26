"""Run with Python to check release tag compatibility without contacting GitHub."""
import importlib.util
import json
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('publisher', root / 'scripts/publish-release.py')
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)
data = json.loads((root / 'releases/v1.1.0.json').read_text(encoding='utf-8'))
with tempfile.TemporaryDirectory() as folder:
    path = Path(folder) / 'v1.1.0.json'
    path.with_suffix('.md').write_text('Upgrade notes', encoding='utf-8')
    for tag in (None, 'v1.1.0', 'native-v1.1.0'):
        candidate = dict(data)
        candidate.pop('tag', None)
        if tag is not None:
            candidate['tag'] = tag
        path.write_text(json.dumps(candidate), encoding='utf-8')
        assert publisher.manifest(path)['tag'] == (tag or 'v1.1.0')
    for tag in ('native-v1.1.1', 'other-tag', ''):
        candidate['tag'] = tag
        path.write_text(json.dumps(candidate), encoding='utf-8')
        try:
            publisher.manifest(path)
        except ValueError:
            pass
        else:
            raise AssertionError(f'Accepted invalid tag: {tag}')
print('PASS: legacy/native release tags and invalid-tag rejection')
