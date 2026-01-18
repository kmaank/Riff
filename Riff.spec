# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_all

datas = []
binaries = []
hiddenimports = ['pystray', 'PIL', 'pynput', 'groq', 'AVFoundation', 'ApplicationServices', 'objc']
tmp_ret = collect_all('pystray')
datas += tmp_ret[0]; binaries += tmp_ret[1];
a = Analysis(
    ['main.py'],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=['pystray', 'PIL.Image', 'PIL.ImageDraw', 'pystray._util'],
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
    icon=None,
    bundle_identifier='com.riff.app',
    info_plist={
        'NSMicrophoneUsageDescription': 'Riff needs microphone access to listen for your dictation.',
        'NSAppleEventsUsageDescription': 'Riff needs to control other applications to paste text.',
        'NSAccessibilityUsageDescription': 'Riff needs accessibility to listen for global hotkeys.',
        'LSUIElement': True,
    },
)
