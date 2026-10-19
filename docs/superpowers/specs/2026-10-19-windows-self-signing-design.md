# Windows self-signing and dual packages

The maintainer authorized generating a persistent local self-signed Windows code-signing certificate, configuring this fork's GitHub Actions secrets, pushing the changes, and running the packaging workflow to obtain an executable installer and portable ZIP. Public CA trust is outside the requirement and the budget is zero.

The certificate's private key and password are generated outside the repository with restrictive permissions. Only a public certificate and its fingerprint may be committed. GitHub repository secrets hold the password and base64-encoded PFX; normal repository variables must never hold either secret. The expected certificate fingerprint is pinned when signing and checking artifacts. Reuse the same key for subsequent releases.

The Windows packager builds Flutter once, signs the fork's own kazumi.exe before archiving, creates both the ZIP and Inno Setup installer when requested, and signs the completed installer. Existing single-format and unsigned local packaging remain supported. Explicit signing configuration errors fail the build rather than silently exporting unsigned packages. Third-party DLLs retain their original signatures.

The existing release workflow configures the certificate only for the Windows job and removes temporary signing material on every exit. Windows artifacts include both formats. Release metadata and SHA256SUMS require both Windows files when publishing new releases. Existing updater selection keeps using the portable ZIP. A manual Windows-only run may be used to verify the requested output without waiting on unrelated platform builds.

Verification includes packaging regression tests, real Authenticode verification on Windows with the expected public certificate, checks that the ZIP's kazumi.exe is signed, and downloading the successful Actions artifacts locally. Any temporary runner trust is removed after verification; no change to the end user's Windows trust is required.
