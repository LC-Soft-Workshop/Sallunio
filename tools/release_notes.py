from pathlib import Path
import re
import sys

version = sys.argv[1].removeprefix('v')
content = Path('CHANGELOG.md').read_text(encoding='utf-8')
match = re.search(r'^## ' + re.escape(version) + r'\s*\n(.*?)(?=^## |\Z)', content, re.M | re.S)
if not match:
    raise SystemExit('Version absente du changelog français')
Path('release-notes.md').write_text(match[1].strip() + '\n', encoding='utf-8')
