## Pipe Storage Node – One‑Click Setup + Web Management (port 3001)

Manage Pipe from a secure, responsive site on your VPS. No day‑to‑day CLI needed.

### Who is this for?
- Anyone who wants a streamlined Pipe setup and a GUI for uploads, links, and usage
- Best on Ubuntu 20.04/22.04/24.04 (VPS/cloud). Works on WSL Ubuntu for testing

### What you get
- Menu‑driven installer (deps, Rust, Pipe CLI build)
- Guided user setup (username, password, referral)
- Management site on port 3001 with Basic Auth
- Desktop + mobile friendly UI with dark/light modes and upload progress
- Features:
  - Swap SOL → PIPE (with faucet shortcut)
  - Upload: local file picker or Google Drive import
  - Create public links (direct + preview) with history
  - Download remote files directly to your PC
  - Show Token Usage (30d) and Referral Stats
  - Quick “pipe …” command runner (restricted)

---

## Quick start (one‑time)

1) Connect to your wsl/Ubuntu VPS (via your cloud provider console or SSH)

2) clone repo
```
git clone https://github.com/shairkhan2/Pipe-Firestarter-Storage-Node.git
```

3) Run the setup menu (from this repo directory)
```bash
cd $HOME/Pipe-Firestarter-Storage-Node
chmod +x ./pipe-setup.sh
./pipe-setup.sh
```

By default, the installer uses this base directory on your VPS: `~/Pipe-Firestarter-Storage-Node`

You can override it by exporting `PIPE_BASE_DIR` before running:
```bash
export PIPE_BASE_DIR="$HOME/my-custom-pipe-dir"
```

3) In the menu, run in order:
- 1) Install Pipe (deps + Rust + build)
- 2) Configure Pipe (user setup, referral, faucet)
- 3) Create Management Site (serve on port 3001)

4) Open the site in your browser
- VPS: `http://YOUR_SERVER_IP:3001`
  - Also open port 3001 in your cloud provider's firewall/security group (AWS SG, GCP VPC firewall, DigitalOcean Cloud Firewalls, etc.)
  - If using UFW on the server: `sudo ufw allow 3001/tcp`
- WSL on your own PC: `http://localhost:3001`

Note: If the installer reports that `pipe` isn’t on your PATH, open a new shell and try again. The installer also sets PATH in `~/.bashrc` and sources `~/.cargo/env` when available.

---

## Using the Management Site

Open http://YOUR_VPS_IP:3001 and use the cards on the page:

### Swap SOL → PIPE
- Enter the amount and click Swap.
- Need Devnet SOL? Use the official Solana Faucet: [Solana Faucet](https://faucet.solana.com/).

### Upload
- Local: pick a file and optionally set a custom name. Progress bar shows the transfer to your VPS.
- Google Drive: paste a URL (and optional save‑as). Server downloads via gdown, then uploads to Pipe.
- VPS staging path: `~/uploads`

### Import from Google Drive (no local upload)
- Paste your Google Drive link, set a file name, click Import + Upload.
- The site uses Python `gdown` to fetch the file to your VPS first, then runs `pipe upload-file`.

### Public links
- Create direct and preview links for any uploaded file. History is saved for quick reuse.

### Usage & referrals
- Show Token Usage (30d) and Referral Stats

---

## Safety notes
- Don’t upload confidential files (wallet keys, personal documents) to the site.
- Keep your `~/.pipe-cli.json` safe and backed up.

---

## Admin & troubleshooting

### Start/stop/logs for the site
- The site runs inside a tmux session called `pipe-mgmt-site`.
- View logs / attach: `tmux attach -t pipe-mgmt-site` (Ctrl+b then d to detach)
- Restart: `tmux kill-session -t pipe-mgmt-site` then rerun menu option 3

### Open port 3001
```bash
sudo ufw allow 3001/tcp
```

### Update Pipe CLI
```bash
cd ~/pipe
git pull || true
cargo install --path .
```

---

## FAQ

### The website doesn’t load
- VPS: ensure your cloud provider firewall/security group allows TCP/3001 and the server’s firewall (e.g., UFW) is open.
- WSL: browse to `http://localhost:3001` from Windows; no cloud firewall needed.

### I can’t find `pipe` after installation
- Open a new shell or run `source ~/.cargo/env`. The installer also adds `$HOME/.cargo/bin` to your PATH via `~/.bashrc`.

### Where are uploaded files stored on the VPS?
- Under `~/uploads/` before being sent to Pipe.

---

Operated by you on your own VPS. Devnet SOL can be requested via the official Solana Foundation faucet: [Solana Devnet Faucet](https://faucet.solana.com/).





