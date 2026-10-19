"""Exercise real Authenticode and temporary trust on GitHub-hosted Windows."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SIGNER = Path(__file__).resolve().parents[1] / 'sign_windows.ps1'
HOSTED_WINDOWS = (os.name == 'nt' and os.environ.get('GITHUB_ACTIONS') == 'true'
                  and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted')


class WindowsSignerExistsTests(unittest.TestCase):
    def test_signer_exists(self):
        self.assertTrue(SIGNER.is_file(), 'Windows Authenticode helper is missing')


@unittest.skipUnless(HOSTED_WINDOWS and shutil.which('pwsh'), 'requires GitHub-hosted Windows PowerShell')
class WindowsSignerIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='kazumi-signing-test-')
        cls.root = Path(cls.temp.name)
        cls.env = dict(os.environ, KAZUMI_WINDOWS_PFX=str(cls.root / 'test.pfx'),
                       KAZUMI_WINDOWS_PFX_PASSWORD='temporary integration fixture password')
        command = r"""
$ErrorActionPreference = 'Stop'
$cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=Kazumi signer integration fixture' `
    -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 -KeyExportPolicy Exportable `
    -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddDays(2)
try {
    $password = ConvertTo-SecureString $env:KAZUMI_WINDOWS_PFX_PASSWORD -AsPlainText -Force
    Export-PfxCertificate -Cert $cert -FilePath $env:KAZUMI_WINDOWS_PFX -Password $password | Out-Null
    @{ pin = $cert.GetCertHashString([System.Security.Cryptography.HashAlgorithmName]::SHA256); thumbprint = $cert.Thumbprint } | ConvertTo-Json -Compress
} finally {
    Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($cert.Thumbprint)" -DeleteKey -Force
}
"""
        result = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', command],
                                env=cls.env, capture_output=True, text=True, check=True)
        identity = json.loads(result.stdout)
        cls.env['KAZUMI_WINDOWS_CERT_SHA256'] = identity['pin']
        cls.thumbprint = identity['thumbprint']

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def fixture(self):
        path = self.root / (self.id().rsplit('.', 1)[-1] + '.ps1')
        path.write_text("Write-Output 'original content'\r\n", encoding='utf-8')
        return path

    def helper(self, mode, path, env=None):
        return subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-File', str(SIGNER),
                               '-Mode', mode, '-FilePath', str(path)], env=env or self.env,
                              capture_output=True, text=True)

    def assert_no_trust(self):
        command = ("$ErrorActionPreference = 'Stop'; "
                   f"foreach ($name in @('Root', 'TrustedPublisher')) {{ if (Test-Path -LiteralPath \"Cert:\\CurrentUser\\$name\\{self.thumbprint}\") {{ exit 1 }} }}")
        result = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', command],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_sign_verify_and_remove_temporary_trust(self):
        path = self.fixture()
        self.assert_no_trust()
        for mode in ('sign', 'verify'):
            result = self.helper(mode, path)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assert_no_trust()

    def test_modified_content_is_rejected_and_trust_removed(self):
        path = self.fixture()
        result = self.helper('sign', path)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        path.write_bytes(path.read_bytes().replace(b'original content', b'modified content'))
        for env in (self.env, dict(self.env, GITHUB_ACTIONS='', RUNNER_ENVIRONMENT='')):
            result = self.helper('verify', path, env)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assert_no_trust()

    def test_wrong_certificate_pin_rejected_before_signing(self):
        path = self.fixture()
        before = path.read_bytes()
        result = self.helper('sign', path, dict(self.env, KAZUMI_WINDOWS_CERT_SHA256='00' * 32))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(path.read_bytes(), before)
        self.assert_no_trust()

    def test_local_signing_needs_no_trust_store_change(self):
        path = self.fixture()
        local_env = dict(self.env, GITHUB_ACTIONS='', RUNNER_ENVIRONMENT='')
        result = self.helper('sign', path, local_env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('not publicly trusted', result.stdout + result.stderr)
        self.assert_no_trust()


if __name__ == '__main__':
    unittest.main()
