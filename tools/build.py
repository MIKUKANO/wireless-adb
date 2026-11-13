"""Build a deterministic module ZIP with an explicit runtime-only allowlist."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
import hashlib
import os

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    'META-INF/com/google/android/update-binary',
    'META-INF/com/google/android/updater-script',
    'module.prop', 'customize.sh', 'service.sh', 'uninstall.sh',
    'scripts/common.sh', 'scripts/control.sh',
    'webroot/index.html', 'webroot/styles.css', 'webroot/app.js',
    'webroot/bridge.js', 'webroot/model.js',
]


def build():
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    target = dist / 'wireless-adb-v2.0.0-rc1.zip'
    temp = target.with_suffix('.zip.tmp')
    try:
        with ZipFile(temp, 'w', compression=ZIP_DEFLATED, compresslevel=9) as archive:
            for name in FILES:
                data = (ROOT / name).read_bytes()
                if b'\r' in data:
                    raise ValueError(f'Non-LF line endings: {name}')
                data.decode('utf-8')
                info = ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                executable = name.endswith('.sh') or name.endswith('update-binary')
                info.external_attr = (0o100755 if executable else 0o100644) << 16
                info.compress_type = ZIP_DEFLATED
                archive.writestr(info, data)
        with ZipFile(temp) as archive:
            assert archive.testzip() is None
            assert archive.namelist() == FILES
            for name in FILES:
                assert archive.read(name) == (ROOT / name).read_bytes()
        os.replace(temp, target)
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        checksum = target.with_suffix('.zip.sha256')
        checksum_temp = checksum.with_suffix('.tmp')
        checksum_temp.write_text(f'{digest}  {target.name}\n', encoding='ascii')
        os.replace(checksum_temp, checksum)
        print(f'Built {target} ({target.stat().st_size} bytes; {len(FILES)} runtime files)')
        print(f'SHA256 {digest}')
    finally:
        if temp.exists():
            temp.unlink()


if __name__ == '__main__':
    build()
