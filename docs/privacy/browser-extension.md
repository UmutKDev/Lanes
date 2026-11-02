# Lanes browser extensions: privacy

Applies to Lanes for Safari, Chrome and Edge. Last updated 2 November 2026.

**Short version:** the extension runs only on claude.ai, keeps everything on
your device and sends nothing to us or anyone else.

## What the extension reads

- From claude.ai's account endpoint: your Claude user ID, name, e-mail,
  organization name and plan. This is how it recognizes which of your
  accounts is signed in. It never reads your chats, projects or files.
- claude.ai cookies: to save the session of each account you add and put it
  back when you switch. Cookies of other sites are never read.
- The text you are typing in claude.ai's message box, only when you switch
  with "Carry draft" on, to move it to the other account.

## Where it is kept

- Account list and settings: the browser's extension storage on your device.
- Saved sessions: the macOS Keychain when the Lanes app is installed, otherwise
  the browser's extension storage on your device.
- The Lanes app shares its own account names, colors, e-mails and Claude
  user IDs with the extension so they match. That stays on your Mac too.

## What is sent

Nothing. The extension has no server, no analytics and no tracking. The only
network requests it makes are to claude.ai, as your browser would.

## Removing data

Forgetting an account in the extension deletes its saved session. Removing the
extension deletes its storage. To end a session on Claude's side, sign out on
claude.ai.

## Contact

https://github.com/UmutKDev/Lanes/issues
