#Requires -Version 7.0
<#
.SYNOPSIS
Sign or verify an artifact with the pinned Windows code-signing identity.
.DESCRIPTION
Secrets are read only from KAZUMI_WINDOWS_PFX, KAZUMI_WINDOWS_PFX_PASSWORD,
and KAZUMI_WINDOWS_CERT_SHA256. Only GitHub-hosted runners receive temporary
CurrentUser trust; local signing never changes the user's trust stores.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('sign', 'verify')]
    [string] $Mode,

    [Parameter(Mandatory = $true)]
    [string] $FilePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Windows Authenticode requires Windows.' }

$certificate = $null
$publicCertificate = $null
$trustChanges = [System.Collections.Generic.List[object]]::new()
try {
    foreach ($name in @('KAZUMI_WINDOWS_PFX', 'KAZUMI_WINDOWS_PFX_PASSWORD', 'KAZUMI_WINDOWS_CERT_SHA256')) {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
            throw "Missing Windows signing configuration: $name"
        }
    }
    $pin = $env:KAZUMI_WINDOWS_CERT_SHA256
    if ($pin -cnotmatch '^[0-9A-Fa-f]{64}$') {
        throw 'KAZUMI_WINDOWS_CERT_SHA256 must be the certificate DER SHA256 fingerprint.'
    }
    if (-not (Test-Path -LiteralPath $env:KAZUMI_WINDOWS_PFX -PathType Leaf)) {
        throw 'The configured Windows signing PFX file does not exist.'
    }
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw 'The artifact to sign or verify does not exist.'
    }
    $artifact = (Resolve-Path -LiteralPath $FilePath).ProviderPath
    try {
        # UserKeySet keeps the imported key out of machine stores. Without
        # PersistKeySet, disposing the certificate removes its temporary key.
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $env:KAZUMI_WINDOWS_PFX, $env:KAZUMI_WINDOWS_PFX_PASSWORD,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::UserKeySet)
    } catch {
        throw 'Unable to open the Windows signing PFX with the configured password.'
    }
    if ($certificate.GetCertHashString([System.Security.Cryptography.HashAlgorithmName]::SHA256) -ne $pin) {
        throw 'The Windows signing certificate does not match the pinned SHA256 fingerprint.'
    }
    $now = Get-Date
    if ($now -lt $certificate.NotBefore -or $now -gt $certificate.NotAfter) {
        throw 'The Windows signing certificate is outside its validity period.'
    }
    $codeSigning = $false
    foreach ($extension in $certificate.Extensions) {
        if ($extension -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]) {
            foreach ($usage in $extension.EnhancedKeyUsages) {
                if ($usage.Value -eq '1.3.6.1.5.5.7.3.3') { $codeSigning = $true }
            }
        }
    }
    if (-not $codeSigning) { throw 'The Windows signing certificate has no code-signing EKU.' }
    if ($Mode -eq 'sign' -and -not $certificate.HasPrivateKey) {
        throw 'The Windows signing certificate has no private key.'
    }

    $hostedRunner = $env:GITHUB_ACTIONS -eq 'true' -and $env:RUNNER_ENVIRONMENT -eq 'github-hosted'
    if ($hostedRunner) {
        # Import only public DER data, never the private key, into trust stores.
        $publicCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certificate.RawData)
        foreach ($name in @('Root', 'TrustedPublisher')) {
            $store = [System.Security.Cryptography.X509Certificates.X509Store]::new($name, 'CurrentUser')
            $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
            $change = [pscustomobject]@{ Store = $store; Added = $false }
            $trustChanges.Add($change)
            $present = @($store.Certificates | Where-Object {
                $_.GetCertHashString([System.Security.Cryptography.HashAlgorithmName]::SHA256) -eq $pin
            })
            if ($present.Count -eq 0) {
                $store.Add($publicCertificate)
                $change.Added = $true
            }
        }
    }

    if ($Mode -eq 'sign') {
        # Include the public signer so the identity travels with the executable.
        Set-AuthenticodeSignature -LiteralPath $artifact -Certificate $certificate `
            -HashAlgorithm SHA256 -IncludeChain Signer | Out-Null
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $artifact
    if ($signature.SignatureType -ne 'Authenticode' -or $null -eq $signature.SignerCertificate) {
        throw 'The artifact has no embedded Authenticode signature.'
    }
    if ($signature.SignerCertificate.GetCertHashString([System.Security.Cryptography.HashAlgorithmName]::SHA256) -ne $pin) {
        throw 'The artifact signer does not match the pinned SHA256 fingerprint.'
    }

    # PowerShell maps CERT_E_UNTRUSTEDROOT to the generic UnknownError status.
    # Ask WinVerifyTrust for the exact result so local self-signed files can be
    # distinguished from corruption, explicit distrust, or any other failure.
    if (-not ('Kazumi.WindowsAuthenticode' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Kazumi {
    public static class WindowsAuthenticode {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct FileInfo {
            public uint Size;
            [MarshalAs(UnmanagedType.LPWStr)] public string Path;
            public IntPtr Handle;
            public IntPtr KnownSubject;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct TrustData {
            public uint Size;
            public IntPtr PolicyCallbackData;
            public IntPtr SIPClientData;
            public uint UIChoice;
            public uint RevocationChecks;
            public uint UnionChoice;
            public IntPtr File;
            public uint StateAction;
            public IntPtr StateData;
            public IntPtr URLReference;
            public uint ProviderFlags;
            public uint UIContext;
            public IntPtr SignatureSettings;
        }
        [DllImport("wintrust.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
        private static extern uint WinVerifyTrust(IntPtr window, [In] ref Guid action, ref TrustData data);

        public static uint Verify(string path) {
            var file = new FileInfo { Size = (uint)Marshal.SizeOf<FileInfo>(), Path = path };
            var pointer = Marshal.AllocHGlobal(Marshal.SizeOf<FileInfo>());
            Marshal.StructureToPtr(file, pointer, false);
            var data = new TrustData {
                Size = (uint)Marshal.SizeOf<TrustData>(),
                UIChoice = 2, UnionChoice = 1, File = pointer,
                StateAction = 1, ProviderFlags = 0x1000
            };
            var action = new Guid("00AAC56B-CD44-11D0-8CC2-00C04FC295EE");
            try {
                return WinVerifyTrust(new IntPtr(-1), ref action, ref data);
            } finally {
                data.StateAction = 2;
                WinVerifyTrust(new IntPtr(-1), ref action, ref data);
                Marshal.DestroyStructure<FileInfo>(pointer);
                Marshal.FreeHGlobal(pointer);
            }
        }
    }
}
'@
    }
    $status = [Kazumi.WindowsAuthenticode]::Verify($artifact)
    if ($status -eq 0) {
        Write-Host "Authenticode signature and file hash verified: $([IO.Path]::GetFileName($artifact))"
    } elseif (-not $hostedRunner -and $status -eq 2148204809) { # CERT_E_UNTRUSTEDROOT (0x800B0109)
        Write-Warning 'The pinned self-signed signature is not publicly trusted. No local trust store was changed.'
    } else {
        throw ('Authenticode verification failed (0x{0:X8}).' -f $status)
    }
} finally {
    $cleanupFailed = $false
    foreach ($change in $trustChanges) {
        try {
            if ($change.Added) { $change.Store.Remove($publicCertificate) }
        } catch {
            $cleanupFailed = $true
            Write-Warning 'Unable to remove temporary runner certificate trust.'
        } finally {
            $change.Store.Close()
        }
    }
    if ($null -ne $publicCertificate) { $publicCertificate.Dispose() }
    if ($null -ne $certificate) { $certificate.Dispose() }
    if ($cleanupFailed) { throw 'Temporary runner certificate trust cleanup failed.' }
}
