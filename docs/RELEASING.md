# Release policy

Current stage: v1.0.0-beta.1 (preview; runtime compatibility is not verified).

- The only user-facing file is the root VeyraConnect_Kur.bat.
- The BAT embeds source src/VeyraConnect.ps1 after marker :__VEYRA_PS_PAYLOAD__.
- CI checks the embedded payload, official ByeDPI hashes, and Windows PowerShell 5.1 parsing.
- The first successful main push publishes an immutable prerelease with the BAT download asset.
- For a newer release, bump its version and tag. Never silently replace a published installer.
- Before a stable release test Win10 x86/x64, Win11 x64, Discord chat, voice and screen sharing, CoD start/exit, reinstall and uninstall.
- Do not modify anti-cheat software or disable OS security protections for tests.
