# Windows self-signing implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development to execute the authorized work in this session. Do not commit private material or print secrets.

**Goal:** Generate and back up a self-signed code-signing identity, configure GitHub Actions Secrets, push working packaging changes, and deliver signed EXE and ZIP artifacts.

**Architecture:** A Windows signing script consumes a PFX path, password, and pinned certificate fingerprint from environment variables. The Python packager signs once before producing both formats and signs the installer after Inno Setup. Release workflow artifact selection and checksum validation cover both Windows packages.

**Tech stack:** Python unittest, OpenSSL, PowerShell Authenticode, Inno Setup, GitHub Actions and GitHub CLI/API.

- [x] Add failing packaging tests for `--windows-format both`, signing before archiving, installer signing, and signing failure preventing export. Implement those behaviors in `scripts/package.py` and `scripts/sign_windows.ps1` and run `python3 -m unittest discover -s scripts/tests -v`.
- [x] Add release-metadata tests for the second Windows output and artifact selection. Update `scripts/release_metadata.py`, `.github/workflows/release.yaml`, and metadata tests; retain existing updater-compatible ZIP names.
- [x] Generate RSA code-signing key, certificate, encrypted PFX, and password under a private directory outside the checkout; publish only `.cer` and SHA256 fingerprint. Upload PFX base64, password and expected thumbprint with GitHub repository secrets.
- [x] Update README and packaging instructions to distinguish self-signed Windows artifacts from publicly trusted signing and document local backup/reuse.
- [x] Review code for correctness and secret handling, run unit tests and workflow validation, commit explicit paths and push to the authorized repository branch.
- [x] Run and monitor GitHub Actions, repair any signing or packaging failures, download both Windows artifacts, verify checksums and signatures, and provide local files plus the workflow link.
