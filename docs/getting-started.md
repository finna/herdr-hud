# Getting started with Herdr HUD

Start here if you want to check on coding agents while playing a game, even if
those agents run on another computer. You can use the downloadable HUD without
building any code.

- [Why Herdr?](#why-herdr)
- [Choose your setup](#choose-your-setup)
- [Install Herdr and start an agent](#install-herdr-and-start-an-agent)
- [Install and connect the HUD](#install-and-connect-the-hud)
- [Set up SSH between computers](#set-up-ssh-between-computers)
- [Add more computers](#add-more-computers)
- [Use it while gaming](#use-it-while-gaming)
- [Troubleshooting](#troubleshooting)

## Why Herdr?

Your coding agent does the work. [Herdr](https://herdr.dev/) gives those agent
terminals a persistent home and brings their status together. **Herdr HUD** adds
the floating H button: open it to read output, send a follow-up, and see which
agent needs attention while your game is open.

For example, you can give an agent a task on your Mac, play on your Windows PC,
and read its progress from H. Add a Linux workstation to that Mac's Herdr setup
and its agents can appear in the same HUD roster.

The HUD is free and open source. It connects to your own Herdr installation and
has no separate HUD account or model subscription. Your chosen agent still needs
its own installation and authentication; any provider usage is governed by that
agent's plan. Installing the HUD alone does not install or start a coding agent.

## Choose your setup

| Where you play | Where your agents run | What to set up |
| --- | --- | --- |
| Mac | That Mac | Herdr and your agent on the Mac, then the Mac HUD. |
| Windows | That PC | Native Windows Herdr and your agent, then the Windows HUD in local mode. |
| Windows | A Mac or Linux computer | Herdr and agents on that computer; SSH access from the PC; Windows HUD pointed at that computer. |
| Mac, or Windows using a Mac/Linux source | Several Mac/Linux computers | Save the additional computers in Herdr on the Mac or source host. |

A **source host** means the computer whose Herdr setup supplies the Windows HUD's
roster. Windows remote mode selects one source at a time; it does not merge the
PC's local agents with that source. The Mac HUD uses the Mac's local `default`
session and its saved remote profiles.

For multiple computers, use a Mac/Linux source. Herdr does not currently support
native Windows servers as SSH targets, and its saved-machine feature is not
supported on Windows clients. Local Windows use and the Windows HUD's SSH-source
mode are separate paths. See [Herdr's Windows support](https://herdr.dev/docs/windows-beta/).

Omarchy uses the separate [Omarchy HUD plugin and its installation guide](https://github.com/finna/omarchy-herdr-hud).
The connection settings below describe this repository's Mac and Windows apps.

## Install Herdr and start an agent

Do this **on each computer that will run agents**. A Windows PC used only to
view a remote source needs the HUD and SSH client, but does not need local Herdr.

### 1. Install Herdr

On **macOS or Linux**, open Terminal and run:

```sh
curl -fsSL https://herdr.dev/install.sh | sh
```

On **Windows**, open PowerShell and run:

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://herdr.dev/install.ps1 | iex"
```

These are Herdr's official stable installers. For package-manager options or an
alternative if Windows blocks the installer, use the [Herdr installation guide](https://herdr.dev/docs/install/).
Open a new terminal after installing, then check:

```sh
herdr --version
```

The HUD requires Herdr 0.9 or newer. Already have Herdr working? Keep that setup
and proceed to your agent; you do not need another installation.

### 2. Start your agent inside Herdr

Install and sign in to your preferred coding agent first, following its own
instructions. Herdr's [agent documentation](https://herdr.dev/docs/agents/) lists
supported agents and integrations.

Open a terminal in the project folder you want the agent to work on, then run:

```sh
herdr
```

This opens the default Herdr session. **Inside its pane**, start your installed
agent, for example:

```sh
claude
```

Or run `codex`, `pi`, or `opencode` if that is what you use. Run one agent command,
then finish any login or project-trust prompts there. It should appear in Herdr's
agent sidebar. An agent started in an unrelated terminal is not automatically
moved into Herdr.

To run another agent, right-click in Herdr to create a tab or split a pane, then
start it there. The default keyboard shortcut for a new tab is **Ctrl+B**, release
both keys, then **C**. See the [Herdr quick start](https://herdr.dev/docs/quick-start/).

### 3. Leave the agents available

Use **Ctrl+B**, release, then **Q** to detach. Running `herdr` again reconnects to
the session. Detaching leaves the background server and agents running; stopping
the server stops its panes. Keep the host powered on, awake, and connected to the
network while you want to use it remotely. See [Herdr persistence](https://herdr.dev/docs/persistence-remote/).

## Install and connect the HUD

### Mac

1. [Download the Mac DMG](https://github.com/finna/herdr-hud/releases/download/v0.1.0-alpha.1/Herdr-HUD-macOS-arm64.dmg). This build requires an Apple Silicon Mac and macOS 13 or newer.
2. Open it and drag **Herdr HUD.app** onto the **Applications** folder shown inside.
3. Eject the disk image, then open **Herdr HUD** from Applications. The current download is signed and notarized by Apple; you may see the normal internet-download confirmation.
4. Click the floating **H**. Agents in this Mac's default Herdr session should appear. Enabled saved remote machines are discovered automatically.

There is no URL, API key, or SSH-source form to fill out on Mac. If your agents
only run elsewhere, keep a local default Herdr session on the Mac and follow
[Add more computers](#add-more-computers).

### Windows

1. [Download the Windows ZIP](https://github.com/finna/herdr-hud/releases/download/v0.1.0-alpha.1/Herdr-HUD-Windows-x64.zip). This build targets Windows 11 x64.
2. Right-click the ZIP and choose **Extract All**. Open the extracted folder and double-click **Install.cmd**. The package is unsigned; Windows may show a publisher warning. Verify you downloaded it from this repository before proceeding.
3. Open **Herdr HUD** from Start. If WebView2 is missing, install Microsoft's [Evergreen WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) and reopen the HUD. The package includes its .NET runtime.
4. Right-click the **H in the system tray**, near the clock, and select **Herdr connection**. Check the tray's hidden-icons arrow if H is not visible there.
5. For agents **on this PC**, leave **SSH target (leave blank for this PC)** empty and enter `default` in **Session**.
6. For agents **on a Mac/Linux source**, first complete [SSH setup](#set-up-ssh-between-computers). Enter that source's SSH target, for example `sam@workbox`, and `default` in **Session**. Replace the example with your own remote username and hostname. An existing SSH alias also works.
7. Click **Connect**, then select an agent in H.

In remote mode, the source's own agents and its enabled saved machines supply the
roster. Each saved profile contributes its configured session. Discovery is one
level deep: it does not recursively search every computer's machine list.

## Set up SSH between computers

Skip this section for local-only use. **SSH** lets the HUD read and send to your
Herdr machine over an authenticated connection. Complete setup in a visible
terminal first: the HUD cannot answer password or host-key questions.

In these examples, `sam` is the **account on the remote computer**, and `workbox`
is that computer's reachable hostname. Substitute your own values everywhere.

### 1. Make the remote computer reachable

You can use a local-network address or Tailscale. For Tailscale, install it on
both computers and sign them into your network, following the [Tailscale quickstart](https://tailscale.com/docs/how-to/quickstart).
Use the target's Tailscale device name or IP address in place of `workbox`.
Tailscale supplies connectivity; it does not add machines to Herdr or automatically
configure the ordinary SSH login used in this guide. Router port forwarding is
not needed for this Tailscale path.

### 2. Enable SSH on the remote Mac/Linux computer

On a **Mac**, open **System Settings → General → Sharing → Remote Login**. Turn
it on and allow the account that owns your Herdr session. Apple's [Remote Login guide](https://support.apple.com/guide/mac-help/allow-a-remote-computer-to-access-your-mac-mchlp1066/mac)
shows where to find the login command.

On **Linux**, enable your distribution's OpenSSH server. For Ubuntu, follow the
[OpenSSH server guide](https://ubuntu.com/server/docs/how-to/security/openssh-server/).
Also check on each remote host:

```sh
python3 --version
```

Remote HUD prompt delivery requires Python 3. Local Mac/Windows prompt delivery
does not. If it is missing, install Python 3 using that host's normal installer or
package manager before testing remote prompts.

### 3. Establish the first login

On the computer **initiating the connection**, open Terminal or PowerShell:

```sh
ssh sam@workbox
```

Check the first-connection host fingerprint against the remote computer before
accepting it, then authenticate. You should reach that computer's shell. Run
`whoami` to confirm the remote account, then `exit` to return to your own computer.

On Windows, the HUD uses **Windows OpenSSH**, not WSL or Git Bash's SSH. Test from
PowerShell. If `ssh` is unavailable, install **OpenSSH Client** from Windows
Optional Features; the gaming PC does not need OpenSSH Server for this path.

### 4. Set up a key so the HUD can connect without questions

Use an existing working SSH key if you have one. Otherwise, on the computer
initiating the connection, run:

```sh
ssh-keygen -t ed25519
```

Follow the prompts. Do not overwrite an existing key. Keep the private key on
this computer. Only the public file, ending in `.pub`, goes to the remote host.

If you used the default filename, display the public key:

**Mac/Linux Terminal:**

```sh
cat ~/.ssh/id_ed25519.pub
```

**Windows PowerShell:**

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
```

Copy the complete single line. Log into the **remote Mac/Linux account**, then:

```sh
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys
```

Append the copied public key on its own line, keeping any existing keys. In nano,
press **Ctrl+O**, **Enter**, then **Ctrl+X** to save and exit. Then run:

```sh
chmod 600 ~/.ssh/authorized_keys
exit
```

For a passphrase-protected key, load it into your SSH agent with
`ssh-add` using the key's path. On Windows, follow Microsoft's [SSH key and
ssh-agent setup](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement).
The agent must be available to the desktop HUD, including after a reboot; an
SSH agent available only inside a terminal may not be visible to a GUI app.

Back on the initiating computer, test the same noninteractive settings used by
the HUD:

```sh
ssh -T -o BatchMode=yes -o StrictHostKeyChecking=yes sam@workbox whoami
```

It should print the remote username and exit **without asking anything**. If it
fails, fix the SSH login before configuring the HUD. Do not disable host-key
checking to work around an error.

For a Windows-to-Mac connection, do this on Windows. To reach an additional
computer from the Mac/source, repeat setup on that Mac/source with its own key. No private-key
copying or SSH agent forwarding is required.

## Add more computers

Do these steps **on your Mac running the HUD**, or **on the Mac/Linux source your
Windows HUD connects to**. In Windows remote mode, the source makes the onward
SSH connections, so its keys and SSH aliases must work independently of the PC.

1. Install Herdr and start agents on the additional Mac/Linux computer using the earlier steps.
2. Complete SSH setup from the Mac/source to that computer.
3. On the Mac/source, open a normal terminal outside Herdr and run:

```sh
herdr machine add sam@workbox --label "Work computer"
herdr machine list
```

Replace `sam@workbox` and the label. Herdr may ask to install or update remote
components; read those prompts before accepting, particularly if agents are
already running. The new profile should be listed as enabled. Herdr's
[connecting-machines guide](https://herdr.dev/docs/connecting-machines/) explains
setup and profile management.

Return to the HUD and let the roster refresh. Repeat for each additional host.
Adding a machine saves a connection; it does not create a coding agent on it.

**Already use named sessions?** The examples use `default`. To select a different
session on an additional machine, use:

```sh
herdr machine add sam@workbox --label "Work agents" --remote-session agents
```

Use the actual session name in place of `agents`. The Windows connection dialog
also lets you select the source session. Mac local discovery uses `default`.
See the [Herdr CLI reference](https://herdr.dev/docs/cli-reference/) for session
and machine commands.

**Example with three computers:** Windows gaming PC → Mac source → Linux workbox.
Set up Windows-to-Mac SSH, then Mac-to-Linux SSH. Run `herdr machine add` on the
Mac for the Linux host. Put the Mac target in the Windows HUD's connection form.
H can then display agents from both the Mac and Linux host.

## Use it while gaming

| Action | Mac | Windows |
| --- | --- | --- |
| Open/close agent panel | Click H or Command+Option+H | Click H or Ctrl+Alt+H |
| Hide/restore the entire HUD | Command+Option+Shift+H | Ctrl+Alt+Shift+H |
| Close panel, keep H | Escape | Escape |
| Send to a ready agent | Enter | Enter |
| Add a new line | Shift+Enter or Ctrl+Enter | Shift+Enter or Ctrl+Enter |

Drag H to a comfortable position. Alerts appear beside H when an agent finishes
or needs input; click an alert to open that agent. Visibility and optional login
startup controls live in the Mac menu-bar H or Windows tray H.

Start with an agent you recognize and check its machine and output before sending
a follow-up. Busy, blocked, unknown, or offline agents cannot receive a HUD prompt.
Open Herdr itself to answer native permission requests or interactive questions.
Chat formats recent supported Codex output; Terminal view remains available for
other agents and raw output.

Try your game's borderless window mode if H is hidden in exclusive fullscreen.
Windows has been used over WoW Classic; exclusive fullscreen and other games
remain unverified. Read the [platform notes](../README.md#run-on-windows) before
assuming every game behaves the same way.

## Troubleshooting

| What you see | What to check |
| --- | --- |
| H opens, but no agents appear | Start the agent **inside Herdr**. On its host, in a separate terminal, run `herdr --session default agent list`. Use the configured session name if different. Check the same OS account is running Herdr and being used by the HUD/SSH. |
| Only some machines appear | Run `herdr machine list` on the Mac/source. Check profiles are enabled and point at the right sessions. Add missing machines there; discovery is one level deep. |
| Connection refused or timed out | Check the host is awake, Remote Login/OpenSSH server is enabled, and its address is reachable. If using Tailscale, both devices need to be connected and network policy must allow SSH. |
| Permission denied or a password prompt | Repeat the batch SSH test above from the correct initiating computer. Check remote username, public-key installation, and the SSH agent available to the HUD. |
| Host key verification failed | Connect interactively and verify the host identity. If a known host's key changed, confirm why before updating its saved key. |
| Herdr reports Attention | Open Herdr on the source and follow its connection/setup message. Resolve it in a visible terminal; the HUD cannot answer setup questions. |
| Remote output works, but sending fails | Check `python3 --version` on that remote host. Also check the agent is ready and has no pending approval in Herdr. |
| Delivery is uncertain | Inspect the actual agent in Herdr before trying again. The HUD keeps the draft and does not retry automatically; the first prompt may already have arrived. |
| Mac says it cannot check for malware | Download the current DMG again and replace the earlier copy. Current Mac assets are signed and notarized. Do not globally disable Gatekeeper. |
| Windows HUD will not open / WebView2 error | Extract the whole archive before installing, keep its files together, and install Microsoft's Evergreen WebView2 Runtime using the link above. |
| Windows cannot find Herdr | Open a new PowerShell window and check `herdr --version`, then quit and reopen the HUD after preserving drafts. Local mode requires native Windows Herdr. |
| H disappears or a shortcut conflicts | Use the menu-bar/tray H visibility controls or alternative shortcuts. Try borderless game mode and check other monitors. |

For installation details, updates, and uninstall locations, return to the
[README](../README.md#download-and-install). For help, [open an issue](https://github.com/finna/herdr-hud/issues)
with your OS, local/remote setup, and error text. Review logs and screenshots for
private agent output, addresses, and credentials before sharing them.
