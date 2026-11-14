#!/usr/bin/env python3
"""Package an existing App and a self-contained Codex skill; never compile."""

import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile


# Build products stay outside Git; both release archives use the same App bytes.
ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / 'skills' / 'aurora-desktop-indicator'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--version', default=(ROOT / 'VERSION').read_text().strip())
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='aurora-release-') as temporary:
        work = Path(temporary)
        app = work / 'AuroraFlow.app'
        subprocess.run(['/usr/bin/ditto', str(args.app.expanduser().resolve()), str(app)], check=True)
        # Keep the MIT notice with the standalone binary as well as the skill ZIP.
        shutil.copy2(ROOT / 'LICENSE', app / 'Contents' / 'Resources' / 'LICENSE')
        library = app / 'Contents' / 'Resources' / 'default.metallib'
        # Strip embedded shader sources using Apple's supported metadata tool.
        strings = subprocess.check_output(['/usr/bin/strings', str(library)])
        if b'/Users/' in strings:
            subprocess.run(['xcrun', 'metal-dsymutil', '--remove-source', '-o', str(work / 'MetalDebug'), str(library)], check=True)
        for binary in (app / 'Contents' / 'MacOS' / 'AuroraFlow', library):
            if b'/Users/' in subprocess.check_output(['/usr/bin/strings', str(binary)]):
                raise RuntimeError('Personal build paths remain in release binary: ' + binary.name)
        subprocess.run(['/usr/bin/codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        skill = work / 'aurora-desktop-indicator'
        shutil.copytree(SKILL, skill, ignore=shutil.ignore_patterns('assets', '__pycache__', '*.pyc'))
        subprocess.run(['/usr/bin/ditto', str(app), str(skill / 'assets' / 'AuroraFlow.app')], check=True)
        shutil.copy2(ROOT / 'LICENSE', skill / 'LICENSE')
        names = [('AuroraFlow.app', 'AuroraFlow-' + args.version + '-macOS-universal.zip'), ('aurora-desktop-indicator', 'aurora-desktop-indicator-' + args.version + '.zip')]
        for folder, name in names:
            target = output / name
            subprocess.run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(work / folder), str(target)], check=True)
            print(target)
        checksums = []
        for _, name in names:
            checksums.append(hashlib.sha256((output / name).read_bytes()).hexdigest() + '  ' + name)
        (output / 'SHA256SUMS.txt').write_text('\n'.join(checksums) + '\n')
        print(output / 'SHA256SUMS.txt')


if __name__ == '__main__':
    main()
