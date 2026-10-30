# Clipboard Shelf

A clipboard history for macOS that works like Windows' Win+V. Press **⌥V** in any app and a
small panel opens next to the text cursor with everything you copied recently. Type to search,
pick one with the arrow keys and press Return, and it's pasted into the app you're in. Press
**⌥S** for your snippets: named texts you save once and paste any time.

## Features

- **Opens at the text cursor.** ⌥V puts the panel below the caret, or above it when there's no
  room. When an app doesn't report its caret (some Electron apps), the panel opens at the mouse.
  Clicking the menu bar icon opens it under the icon instead.
- **Search as you type.** The search field is focused when the panel opens. Every word you type
  must appear in the clip or the name of the app it came from, and matching clips stay listed
  with the newest first.
- **Tabs:** All, Pinned, Text, Images, Links and Snippets. Tab and ⇧Tab switch between them.
- **Snippets.** ⌥S opens the panel on the Snippets tab. Add a snippet with ⌘N (or the + button),
  give it a name and a text, and it stays until you delete it — Clear History never touches it.
  Search, arrows, Return and ⌘1–⌘9 paste a snippet exactly like a clip.
- **Triggers type themselves.** Give a snippet a trigger like `-email`; type that trigger in any
  app and the snippet's text is pasted at the cursor — the typed trigger is deleted as it
  expands. Word-like triggers (starting with a letter) only expand at a word boundary, never in
  password fields, and the clipboard is restored right after. Settings can turn this off.
- **Pinned clips** stay at the top of All and are never removed, by the history limit or by Clear.
- **Keeps text, formatting, links, images and files.** Formatting (RTF, HTML) comes back when you
  paste. ⇧Return pastes the text only, without formatting.
- **The same copy twice moves to the top** instead of being added again.
- **Passwords stay out.** Nothing copied in 1Password, Bitwarden, Passwords, Keychain Access,
  KeePassXC, LastPass or Dashlane is kept, nor anything an app marks as concealed or temporary
  ([nspasteboard.org](http://nspasteboard.org) markers).
- **Secrets are hidden in the list.** `API_KEY=…`, `password: …`, tokens recognisable by their
  shape (OpenAI, Stripe, GitHub, Slack, AWS, Google, JWTs), and a lone word mixing upper case,
  lower case and digits (likely a password) show as `••••••••`. They still paste in full.
  Settings can turn this off.
- **Code looks like code.** Clips copied from a terminal or a code editor use a monospaced font.
- Pause Recording in the menu bar icon's menu stops keeping copies until you turn it back on.
- Light and dark mode follow the system.

## Keys

| Key | Does |
| --- | --- |
| ⌥V | Open or close the clipboard panel (change it in Settings) |
| ⌥S | Open or close the snippets panel (change it in Settings) |
| ↑ ↓, Page Up/Down | Move the selection |
| Return or a click | Paste |
| ⇧Return | Paste as plain text |
| ⌘1 – ⌘9 | Paste the first nine |
| ⌘P | Pin or unpin |
| ⌘N | New snippet (on the Snippets tab) |
| ⌘⌫ | Delete the clip or snippet |
| Tab, ⇧Tab | Next or previous tab |
| Esc | Clear the search, close, or leave the snippet editor |
| ⌘, | Settings |

Hovering a clip shows pin and delete buttons; hovering a snippet shows edit and delete.
Right-clicking the menu bar icon gives Open Clipboard, Open Snippets, Pause Recording, Clear
History and Settings.

## Accessibility access

Pasting into another app means pressing ⌘V for you, and opening at the text cursor means asking
the app where its cursor is. Both need **System Settings › Privacy & Security › Accessibility**.
The app asks on its first launch. Without it, choosing a clip copies it and you press ⌘V
yourself, and the panel opens at the mouse. Trigger expansion needs the same access; it stays
off until it's allowed.

`build.sh` signs with the `Local Self-Signed` certificate when this Mac has it, so the permission
survives rebuilds. With an ad hoc signature, macOS forgets it after every build: remove the app
from the Accessibility list and add it again.

## Install

Needs macOS 14 and Xcode or the Command Line Tools.

```sh
scripts/install.sh            # builds, installs /Applications/ClipboardShelf.app, launch at login, starts it
scripts/install.sh --dest ~/Applications
```

`./build.sh` alone builds `build/ClipboardShelf.app`.

## Where the history is kept

`~/Library/Application Support/ClipboardShelf`: `history.json` lists the clips, `blobs/` holds
each clip's clipboard data (`<id>.plist`) and an image's thumbnail (`<id>.png`), and
`snippets.json` lists your snippets with their triggers. It stays on this Mac.
Settings › History sets how many unpinned clips to keep (200 by default).

Only these formats are read from the clipboard: plain text, RTF, RTFD, HTML, web archive, URL,
file URL, PNG, TIFF, JPEG and HEIC. Reading every format an app offers can make apps such as
Excel render each one. Images are kept as PNG, and a TIFF is added again when pasting. A single
format over 30 MB is skipped.

## Command line

```sh
CS=/Applications/ClipboardShelf.app/Contents/MacOS/ClipboardShelf
$CS --dump                         # the history as JSON (what the panel lists)
$CS --snapshot panel.png dark zens # draw the panel offscreen, dark, searching "zens"
$CS --register-login-item          # launch at login on (--unregister-login-item: off)
```
