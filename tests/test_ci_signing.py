#!/usr/bin/env python3
"""Exercise temporary signing credential lifecycle without Apple credentials."""
import base64
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SigningLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        scripts = self.root / 'scripts'
        scripts.mkdir()
        shutil.copy(ROOT / 'scripts/ci-build-release.sh', scripts)
        self.script = scripts / 'ci-build-release.sh'
        self.log = self.root / 'calls'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = os.environ.copy()
        self.env.update(PATH=f'{self.bin}:{self.env["PATH"]}', RUNNER_TEMP=str(self.root),
                        CALL_LOG=str(self.log), APPLE_CERTIFICATE_P12_BASE64=base64.b64encode(b'fake-p12').decode(),
                        APPLE_CERTIFICATE_PASSWORD='fake-export-secret', APPLE_TEAM_ID='ABCDE12345',
                        APPLE_SIGNING_IDENTITY='Developer ID Application: Example (ABCDE12345)',
                        APPLE_ID='example@example.invalid', APPLE_APP_SPECIFIC_PASSWORD='fake-notary-secret')
        self.write(self.bin / 'security', '''#!/usr/bin/env python3
import os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['CALL_LOG'], 'a') as f: f.write('security ' + repr(args) + '\\n')
if args == ['list-keychains', '-d', 'user']:
    print('    "/original/login with spaces.keychain-db"')
    print('    "/original/System.keychain"')
if args[0] == os.environ.get('FAIL_SECURITY'):
    raise SystemExit(9)
''')
        self.write(self.bin / 'xcrun', '''#!/usr/bin/env python3
import os, sys
with open(os.environ['CALL_LOG'], 'a') as f: f.write('xcrun ' + repr(sys.argv[1:]) + '\\n')
raise SystemExit(int(os.environ.get('FAIL_NOTARY', '0')))
''')
        self.write(scripts / 'build-release.sh', '''#!/usr/bin/env python3
import os, sys
from pathlib import Path
assert sys.argv[1:] == ['--notarize']
for name in ['APPLE_CERTIFICATE_P12_BASE64', 'APPLE_CERTIFICATE_PASSWORD', 'APPLE_APP_SPECIFIC_PASSWORD', 'APPLE_ID']:
    assert name not in os.environ, name
assert os.environ['APPLE_NOTARY_PROFILE'] == 'tokchan-release'
assert Path(os.environ['APPLE_KEYCHAIN_PATH']).parent.exists()
assert os.umask(0o022) == 0o022, 'credential umask leaked into distributed build'
with open(os.environ['CALL_LOG'], 'a') as f: f.write('build\\n')
raise SystemExit(int(os.environ.get('FAIL_BUILD', '0')))
''')

    def write(self, path, body):
        path.write_text(body)
        path.chmod(0o755)

    def run_script(self):
        result = subprocess.run(['bash', '-c', 'umask 022; exec bash "$1"', 'test', str(self.script)],
                                env=self.env, text=True, capture_output=True)
        self.assertNotIn('fake-export-secret', result.stdout + result.stderr)
        self.assertNotIn('fake-notary-secret', result.stdout + result.stderr)
        self.assertEqual(list(self.root.glob('tokchan-signing.*')), [])
        return result, self.log.read_text() if self.log.exists() else ''

    def assert_restored(self, calls):
        self.assertIn("['list-keychains', '-d', 'user', '-s', '/original/login with spaces.keychain-db', '/original/System.keychain']", calls)
        self.assertIn("['delete-keychain',", calls)

    def test_success_restores_keychains_and_removes_secrets_from_build(self):
        result, calls = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('build\n', calls)
        self.assert_restored(calls)

    def test_build_failure_preserves_failure_and_cleans_up(self):
        self.env['FAIL_BUILD'] = '23'
        result, calls = self.run_script()
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assert_restored(calls)

    def test_notary_auth_failure_does_not_build(self):
        self.env['FAIL_NOTARY'] = '17'
        result, calls = self.run_script()
        self.assertEqual(result.returncode, 17)
        self.assertNotIn('build\n', calls)
        self.assert_restored(calls)

    def test_import_failure_deletes_keychain_without_build(self):
        self.env['FAIL_SECURITY'] = 'import'
        result, calls = self.run_script()
        self.assertEqual(result.returncode, 9)
        self.assertNotIn('build\n', calls)
        self.assertIn("['delete-keychain',", calls)

    def test_missing_secret_fails_before_keychain_access(self):
        del self.env['APPLE_APP_SPECIFIC_PASSWORD']
        result, calls = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('APPLE_APP_SPECIFIC_PASSWORD', result.stderr)
        self.assertEqual(calls, '')

    def test_invalid_base64_never_imports(self):
        self.env['APPLE_CERTIFICATE_P12_BASE64'] = '%%%'
        result, calls = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("['import',", calls)

    def test_wrong_certificate_type_fails_before_keychain_access(self):
        self.env['APPLE_SIGNING_IDENTITY'] = 'Apple Development: Example (ABCDE12345)'
        result, calls = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, '')

    def test_cleanup_failure_fails_job(self):
        self.env['FAIL_SECURITY'] = 'delete-keychain'
        result, calls = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('build\n', calls)


if __name__ == '__main__':
    unittest.main()
