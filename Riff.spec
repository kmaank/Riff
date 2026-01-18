# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_all, collect_submodules
import os

datas = []
binaries = []
hiddenimports = ['pystray', 'PIL', 'pynput', 'groq', 'AVFoundation', 'ApplicationServices', 'objc']
hiddenimports += collect_submodules('ui')

tmp_ret = collect_all('pystray')
datas += tmp_ret[0]; binaries += tmp_ret[1];

# Force include the source file and assets
datas += [('ui/native_onboarding.py', 'ui'), ('assets', 'assets')]

a = Analysis(
    ['main.py'],
    pathex=[os.getcwd()],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='Riff',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch='arm64',
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='Riff',
)
app = BUNDLE(
    coll,
    name='Riff.app',
    icon='assets/AppIcon.icns',
    bundle_identifier='com.riff.app',
    info_plist={
        'NSMicrophoneUsageDescription': 'Riff needs microphone access to listen for your dictation.',
        'NSAppleEventsUsageDescription': 'Riff needs to control other applications to paste text.',
        'NSAccessibilityUsageDescription': 'Riff needs accessibility to listen for global hotkeys.',
        'LSUIElement': True,
    },
)
