"""Build the offline macOS arm64 localizer from an already verified payload."""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / '.build'
BUILD.mkdir(exist_ok=True)
SDK = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
SWIFT = ['xcrun', 'swiftc', '-swift-version', '5', '-target', 'arm64-apple-macos11.0',
         '-sdk', SDK, '-module-cache-path', str(BUILD / 'ModuleCache'), '-O']

def run(args):
    subprocess.run([str(x) for x in args], check=True)

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def compile_tests():
    test_dir = BUILD / 'tests'
    test_dir.mkdir(exist_ok=True)
    shutil.copy2(ROOT / 'Tests.swift', test_dir / 'main.swift')
    run(SWIFT + [ROOT / 'Core.swift', test_dir / 'main.swift', '-o', BUILD / 'LocalizerTests'])
    run([BUILD / 'LocalizerTests', BUILD / 'test-fixtures'])

def make_icon():
    if (BUILD/'Localizer.icns').exists():
        return
    run(SWIFT + [ROOT/'icon.swift', '-o', BUILD/'DrawIcon'])
    run([BUILD/'DrawIcon', BUILD/'icon-1024.png'])
    iconset = BUILD/'Localizer.iconset'; iconset.mkdir(exist_ok=True)
    for size in [16, 32, 128, 256, 512]:
        for factor in [1, 2]:
            filename = f'icon_{size}x{size}' + ('@2x' if factor == 2 else '') + '.png'
            run(['/usr/bin/sips', '-z', size*factor, size*factor, BUILD/'icon-1024.png', '--out', iconset/filename])
    # ICNS stores the modern representations as PNG chunks. Build the container directly
    # so packaging does not depend on iconutil's image-service availability.
    import struct
    representations = [
        ('icp4','icon_16x16.png'), ('icp5','icon_32x32.png'),
        ('icp6','icon_32x32@2x.png'), ('ic07','icon_128x128.png'),
        ('ic08','icon_256x256.png'), ('ic09','icon_512x512.png'),
        ('ic10','icon_512x512@2x.png'), ('ic11','icon_16x16@2x.png'),
        ('ic12','icon_32x32@2x.png'), ('ic13','icon_128x128@2x.png'),
        ('ic14','icon_256x256@2x.png')]
    chunks = []
    for tag, filename in representations:
        png = (iconset/filename).read_bytes()
        chunks.append(struct.pack('>4sI',tag.encode('ascii'),len(png)+8)+png)
    body = b''.join(chunks)
    (BUILD/'Localizer.icns').write_bytes(struct.pack('>4sI',b'icns',len(body)+8)+body)

def package(payload_app, output_dir):
    config = json.loads((ROOT / 'release-config.json').read_text())
    payload_app = payload_app.resolve()
    if sha(payload_app / 'Contents/MacOS/DeckCraft') != config['chineseExecutableSHA256']:
        raise RuntimeError('Payload does not match the verified release configuration')
    run(['/usr/bin/codesign', '--verify', '--deep', '--strict', payload_app])
    app = output_dir / 'DeckCraft 汉化器.app'
    archive = output_dir / 'DeckCraft 汉化器-1.0.0.zip'
    if app.exists() or archive.exists():
        raise FileExistsError('Output already exists; choose a new --output-dir')
    output_dir.mkdir(parents=True, exist_ok=True)
    binary = BUILD / 'DeckCraftLocalizer'
    run(SWIFT + [ROOT / 'Core.swift', ROOT / 'main.swift', '-o', binary])
    make_icon()
    contents = app / 'Contents'
    resources = contents / 'Resources'
    executable = contents / 'MacOS/DeckCraftLocalizer'
    executable.parent.mkdir(parents=True)
    resources.mkdir()
    shutil.copy2(binary, executable)
    executable.chmod(0o755)
    shutil.copy2(BUILD / 'Localizer.icns', resources / 'Localizer.icns')
    payload_path = f"Packs/{config['version']}/DeckCraft.app"
    payload = resources / payload_path
    shutil.copytree(payload_app, payload)
    files = {str(f.relative_to(payload)): sha(f) for f in sorted(payload.rglob('*')) if f.is_file()}
    pack = {k: config[k] for k in ['version', 'sourceCommit', 'architecture',
                                  'originalExecutableSHA256', 'chineseExecutableSHA256']}
    pack.update(payloadPath=payload_path, files=files)
    (resources / 'catalog.json').write_text(json.dumps(dict(schema=1, packs=[pack]), ensure_ascii=False, indent=2))
    info = dict(CFBundleName='DeckCraft 汉化器', CFBundleDisplayName='DeckCraft 汉化器',
                CFBundleIdentifier='cn.local.deckcraft.localizer', CFBundleExecutable='DeckCraftLocalizer',
                CFBundlePackageType='APPL', CFBundleIconFile='Localizer', CFBundleShortVersionString='1.0.0',
                CFBundleVersion='1', LSMinimumSystemVersion='11.0', NSHighResolutionCapable=True,
                CFBundleDevelopmentRegion='zh_CN', CFBundleLocalizations=['zh-Hans', 'zh_CN'],
                LSApplicationCategoryType='public.app-category.utilities')
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
    (contents / 'PkgInfo').write_bytes(b'APPL????')
    (resources / '使用说明.txt').write_text(
        '双击 DeckCraft 汉化器，检测版本后点击“安装简体中文”。\n'
        '安装前请保存并退出 DeckCraft。原应用会完整备份，演示文稿与设置不修改。\n'
        '当前内置 DeckCraft 0.11.1 的 Apple Silicon 汉化包。未知版本会停止，不会降级。\n'
        '备份：~/Library/Application Support/DeckCraft 汉化器/Backups/\n'
        '恢复前先退出 DeckCraft，再将备份中的 DeckCraft-安装前.app 复制回原位置并改名。\n')
    run(['/usr/bin/codesign', '--force', '--sign', '-', '--options', 'runtime', app])
    run(['/usr/bin/codesign', '--verify', '--deep', '--strict', app])
    run([executable, '--verify-payload'])
    run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive])
    print(json.dumps({'app': str(app), 'archive': str(archive), 'sha256': sha(archive)}, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tests', action='store_true')
    parser.add_argument('--payload-app', type=Path)
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    if args.tests:
        compile_tests()
    elif args.payload_app:
        package(args.payload_app, args.output_dir.resolve())
    else:
        parser.error('--payload-app is required unless --tests is selected')
