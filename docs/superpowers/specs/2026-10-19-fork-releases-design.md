# Fork releases and updates

The fork `AmazingZ-sys/Kazumi` will build Android APK, unsigned iOS IPA, macOS DMG, and unsigned Windows ZIP from its own source. Branch pushes produce downloadable Actions artifacts; numeric version tags publish a stable GitHub Release in this fork after tests and all platform builds pass. Windows signing and MSIX publication are excluded until this fork has its own authorized SignPath service.

The first fork release targets `2.3.11+20311`, based on upstream 2.3.9. The initial `2.3.10` tag encountered CI setup failures and was retained without a published release. The application reads only this fork's latest stable GitHub Release, chooses assets that actually exist, defaults to GitHub downloads, and never falls back to the upstream update mirror. Missing releases mean there is no update; network failures remain visible. SHA256 verification stays mandatory. iOS opens the fork release page for re-signing/sideloading.

Android uses a new persistent fork signing key, authorized by the user. Private signing files stay outside Git and are supplied through repository Actions secrets. Builds keep their platform filename identifiers so the updater can select the correct APK/DMG/ZIP. The public release notes clearly state Windows ZIP and iOS/macOS signature limitations.

Validation covers fork release requests, 404, asset selection and source handling, existing Flutter tests/analyzer, packaging tests, workflow structure, and actual cloud builds. The release is complete only after four downloadable assets are published and the GitHub release response matches the updater's expectations.
