#!/usr/bin/env python3
"""Run local workflow assertions in a booted, isolated iPhone simulator.
Usage: python3 checks/run-workflow-checks.py SIMULATOR_UDID
Requires a successful simulator build at /tmp/muses-derived (or --derived-data).
"""
import argparse
import pathlib
import plistlib
import subprocess
import tempfile
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('simulator')
parser.add_argument('--derived-data', default='/tmp/muses-derived')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
products = pathlib.Path(args.derived_data) / 'Build/Products/Debug-iphonesimulator'
bundle_id = 'com.ordoeden.muses.checks.' + uuid.uuid4().hex
with tempfile.TemporaryDirectory(prefix='muses-workflow-') as temporary:
    app = pathlib.Path(temporary) / 'MusesWorkflowChecks.app'
    app.mkdir()
    with (app / 'Info.plist').open('wb') as file:
        plistlib.dump({'CFBundleIdentifier': bundle_id, 'CFBundleName': 'MusesWorkflowChecks',
                      'CFBundleExecutable': 'MusesWorkflowChecks', 'CFBundlePackageType': 'APPL',
                      'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0',
                      'LSRequiresIPhoneOS': True, 'UILaunchScreen': {}}, file)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
    # The legacy JSON workflow does not use Realm yet; its checks link only Alamofire.
    excluded = {'MusesApp.swift', 'RealmModels.swift', 'RealmDatabase.swift'}
    sources = sorted(str(path) for path in (root / 'Muses').rglob('*.swift') if path.name not in excluded)
    subprocess.run(['xcrun', '--sdk', 'iphonesimulator', 'swiftc', '-swift-version', '6', '-parse-as-library',
                    '-target', 'arm64-apple-ios17.0-simulator', '-sdk', sdk,
                    '-module-cache-path', temporary + '/cache', '-I', str(products), *sources,
                    str(root / 'checks/WorkflowChecks.swift'), str(products / 'Alamofire.o'),
                    '-o', str(app / 'MusesWorkflowChecks')], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    subprocess.run(['xcrun', 'simctl', 'install', args.simulator, str(app)], check=True)
    try:
        result = subprocess.run(['xcrun', 'simctl', 'launch', '--console', args.simulator, bundle_id],
                                capture_output=True, text=True, timeout=60)
        print(result.stdout)
        assert 'WORKFLOW CHECKS PASSED' in result.stdout, result.stderr + result.stdout
    finally:
        subprocess.run(['xcrun', 'simctl', 'uninstall', args.simulator, bundle_id], check=True)
