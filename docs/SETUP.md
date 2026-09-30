# Setup help

## Build tools

Run `swift --version`.
Use a Swift 6 toolchain on macOS 14 or later.
The package uses Swift 5 language mode.
Run `python3 --version` to check Python.

The build creates `outputs/Computah.app`.
This is a local developer build.
It is not a signed installer for general distribution.

## App permissions

If Computah cannot read or act on an app, open System Settings.
Go to **Privacy & Security → Accessibility**.
Add `outputs/Computah.app` and enable it.

Microphone permission is needed only for voice input.
Start listening to request permission.
If you denied access, enable Computah under **Privacy & Security → Microphone**.

After a permission change, restart Computah if it still cannot connect.
Some apps do not provide enough controls through Accessibility.
Permission alone cannot fix missing controls.

## API keys

Keep keys in `.env` at the project root.
Use the names in `.env.example`.
An empty or rejected key prevents that provider from working.
Check the key with the provider.
Never include the key in an issue, screenshot, or log.

Typed commands in Debug Mode need TypeSafe.
Voice input needs the key matching `SPEECH_PROVIDER`: Volcengine or Deepgram.

## Start or restart

Quit the app from the notch menu before you run `zsh scripts/run.sh` again.
The launcher refuses to open a second copy.
Changes to startup options require a restart.

Keep the app in `outputs/` for direct Finder launch.
The launcher passes the project folder with `--root`.
If you move the app, pass that option yourself:

```sh
/path/to/Computah.app/Contents/MacOS/Computah --root /path/to/project
```

You can also set `COMPUTAH_PROJECT_ROOT`.
This variable tells the app where to find `.env` and where to save optional debug history.

## Signing

The build uses `COMPUTAH_CODESIGN_IDENTITY` when you set it.
Otherwise, it prefers the local `Computah Local Code Signing` identity, then the first valid
Apple signing identity.

Create the local identity once:

```sh
zsh scripts/setup-local-codesign.sh
```

This creates a self-signed code-signing certificate and private key in your login keychain.
They stay on this Mac and are not added to the repository.
After the next build, remove the old Computah entry from Accessibility, add
`outputs/Computah.app` again, and enable it. Later builds signed with the same identity retain
that permission.

If no stable identity is available, the build warns and uses an ad-hoc signature.
An ad-hoc signature changes identity on every rebuild, so macOS will not retain Accessibility
permission.

## Slow or incomplete commands

Open Debug Mode from the notch menu.
To type a command, use the input field in Debug Mode.
Select **Run** or press **Return**.
The panel hides while the command executes.
Reopen Debug Mode and select a recent command.

- **Overview** shows the result, timing, and each action with its observed outcome.
- **Jev decisions** shows selection details and time spent asking the model.
- **App controls** shows what Computah read before and after each action.

An unknown result means Computah could not confirm completion.
It does not prove that nothing happened.
Check the app before you repeat the command.
