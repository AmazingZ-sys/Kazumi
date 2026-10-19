# Windows self-signed signing identity

`windows-self-signed.cer` is the public DER certificate; `windows-self-signed.pem` is the same public certificate in PEM format. `windows-self-signed.sha256` pins the SHA-256 of the DER bytes, not the executable or the PEM text.

Subject: `CN=AmazingZ-sys Kazumi, O=AmazingZ-sys`. This is a self-signed Authenticode identity, not a publicly trusted CA certificate. It does not remove Windows security warnings.

Certificate DER SHA-256:

```text
A6C853EDFC35B042E02E5BA64978D8187FFEAD155287455AA6344811143610A6
```

Verify the public certificate with `openssl x509 -in certificates/windows-self-signed.pem -noout -subject -dates -fingerprint -sha256`. On Windows, inspect a downloaded executable using `Get-AuthenticodeSignature`, then compare its signer certificate's SHA-256 to this value. A trust-chain warning is expected on a machine that does not trust this self-signed identity.

The corresponding password-protected PFX, encrypted private key and password are backed up outside Git. Never commit or publish them. Subsequent builds must reuse this identity unless a deliberate key rotation is performed. The workflow requires the three repository secrets documented in `docs/packaging.md` and signs this fork's own executable and installer; third-party DLLs retain their original signatures.
