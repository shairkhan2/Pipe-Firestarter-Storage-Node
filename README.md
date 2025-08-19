## Pipe One-Click Setup + Web Management (Port 3001)

Make Pipe easy for non-technical users. This guide shows how to install, configure, and then manage everything from a simple website on your VPS at http://YOUR_VPS_IP:3001

### Who is this for?
- Anyone who wants to use Pipe without touching the command line after setup.
- Works best on Ubuntu 20.04/22.04/24.04 (VPS or cloud VM). Also fine on WSL Ubuntu for testing.

### What you get
- Install Pipe and dependencies
- Guided user setup (username, password, referral)
- A management website on your VPS (port 3001) to:
  - Deposit SOL → PIPE
  - Upload a file from your computer
  - Import a file from Google Drive
  - Create a public link for sharing/downloads
  - View token usage and rewards

---

## Quick Setup (one-time)

1) Connect to your Ubuntu VPS (via your cloud provider console or SSH)

2) Run the setup menu (you can run this from any directory)
```bash
cd $HOME/Pipe-Firestarter-Storage-Node
chmod +x ./pipe-setup.sh
./pipe-setup.sh
```

By default, the installer uses this base directory on your VPS:

- `~/Pipe-Firestarter-Storage-Node`

You can override it by exporting `PIPE_BASE_DIR` before running the script:
```bash
export PIPE_BASE_DIR="$HOME/my-custom-pipe-dir"
```

3) In the menu, run in order:
- 1) Install Pipe (deps + Rust + build)
- 2) Configure Pipe (user setup, referral, faucet)
- 3) Create Management Site (serve on port 3001)

4) Open the site in your browser
- URL: http://YOUR_VPS_IP:3001
- If your firewall blocks it, allow the port: `sudo ufw allow 3001/tcp`

Note: If the installer reports that `pipe` isn’t on your PATH, open a new shell and try again. The installer also sets PATH in `~/.bashrc` and sources `~/.cargo/env` when available.

---

## Using the Management Site (no commands)

Open http://YOUR_VPS_IP:3001 and use the cards on the page:

### Deposit SOL → PIPE
- Enter the amount of SOL and click Deposit. This runs `pipe swap-sol-for-pipe <AMOUNT_SOL>` on your VPS.
- Need Devnet SOL? Use the official Solana Devnet Faucet: [Solana Devnet Faucet](https://faucet.solana.com/).

### Upload a File (from your computer)
- Choose a file, optionally set the file name on Pipe, then click Upload.
- Files are stored on your VPS under `~/uploads/` and then uploaded via `pipe upload-file <FILE_PATH> <FILE_NAME>`.

### Import from Google Drive (no local upload)
- Paste your Google Drive link, set a file name, click Import + Upload.
- The site uses Python `gdown` to fetch the file to your VPS first, then runs `pipe upload-file`.

### Create Public Link
- Enter the file name you used during upload and click Create Link.
- You’ll get both a direct link (downloads/playback) and a social/preview link, powered by `pipe create-public-link <FILE_NAME>`.

### Rewards + Usage
- Click “Show Token Usage (30d)” to display your usage report, powered by `pipe token-usage`.

---

## Safety Notes
- Don’t upload confidential files (wallet keys, personal documents) to the site.
- Keep your `~/.pipe-cli.json` safe and backed up.

---

## Admin & Troubleshooting

### Start/Stop/Logs for the site
- The site runs inside a tmux session called `pipe-mgmt-site`.
- View logs / attach: `tmux attach -t pipe-mgmt-site` (Ctrl+b then d to detach)
- Restart: `tmux kill-session -t pipe-mgmt-site` then rerun menu option 3

### Open port 3001
```bash
sudo ufw allow 3001/tcp
```

### Update Pipe
```bash
cd ~/pipe
git pull || true
cargo install --path .
```

---

## FAQ

### The website doesn’t load
- Ensure your VPS firewall allows port 3001, and your cloud provider’s security group isn’t blocking it.

### I can’t find `pipe` after installation
- Open a new shell or run `source ~/.cargo/env`. The installer also adds `$HOME/.cargo/bin` to your PATH via `~/.bashrc`.

### Where are uploaded files stored on the VPS?
- Under `~/uploads/` before being sent to Pipe.

---

Operated by you on your own VPS. Devnet SOL can be requested via the official Solana Foundation faucet: [Solana Devnet Faucet](https://faucet.solana.com/).



