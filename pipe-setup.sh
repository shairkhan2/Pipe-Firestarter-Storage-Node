#!/usr/bin/env bash

# Pipe CLI Setup Assistant (Menu-driven)
# Intended for Debian/Ubuntu (or WSL Ubuntu). Requires sudo privileges for apt operations.

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
RED="\033[0;31m"
NC="\033[0m"

print_green() { echo -e "${GREEN}$*${NC}"; }
# Make most system text green (non-error)
print_yellow() { echo -e "${GREEN}$*${NC}"; }
print_cyan() { echo -e "${GREEN}$*${NC}"; }
print_red() { echo -e "${RED}$*${NC}"; }

BASE_DIR="${PIPE_BASE_DIR:-$HOME/Pipe-Firestarter-Storage-Node}"
UPLOADS_DB="$BASE_DIR/uploaded_files.txt"

ensure_base_dir() {
  mkdir -p "$BASE_DIR" 2>/dev/null || true
}

# Returns a durable uploads directory path (stdout)
ensure_uploads_dir() {
  local dir="$HOME/uploads"
  mkdir -p "$dir" 2>/dev/null || true
  echo "$dir"
}

# Expand ~ in user-provided paths
expand_path() {
  local input="$1"
  if [[ "$input" == ~* ]]; then
    echo "$HOME${input:1}"
  else
    echo "$input"
  fi
}

ensure_pipe_installed() {
  if ! command -v pipe >/dev/null 2>&1; then
    print_red "Pipe CLI not found. Please run 'Install Pipe' from the menu first."
    return 1
  fi
}

ensure_gdown() {
  # Already available?
  if command -v gdown >/dev/null 2>&1; then
    return 0
  fi
  # In user bin already?
  if [ -x "$HOME/.local/bin/gdown" ]; then
    if ! echo ":$PATH:" | grep -q ":$HOME/.local/bin:"; then
      export PATH="$HOME/.local/bin:$PATH"
    fi
    return 0
  fi
  print_cyan "Installing gdown (Python) for Google Drive downloads..."
  # Preferred: pipx (isolated venv)
  if ! command -v pipx >/dev/null 2>&1; then
    ensure_apt
    ensure_sudo
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y pipx || true
    # Ensure user bin path
    if ! echo ":$PATH:" | grep -q ":$HOME/.local/bin:"; then
      export PATH="$HOME/.local/bin:$PATH"
    fi
    if ! grep -qs 'HOME/.local/bin' "$HOME/.bashrc" 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
  fi
  if command -v pipx >/dev/null 2>&1; then
    pipx install --force gdown >/dev/null 2>&1 || pipx install gdown || true
  fi
  # Check again for pipx-installed binary
  if command -v gdown >/dev/null 2>&1 || [ -x "$HOME/.local/bin/gdown" ]; then
    if ! echo ":$PATH:" | grep -q ":$HOME/.local/bin:"; then
      export PATH="$HOME/.local/bin:$PATH"
    fi
    return 0
  fi
  # Fallback: private venv under BASE_DIR
  ensure_base_dir
  local venv_dir="$BASE_DIR/.gdown-venv"
  if [ ! -d "$venv_dir" ]; then
    python3 -m venv "$venv_dir" || true
  fi
  if [ -x "$venv_dir/bin/python" ]; then
    "$venv_dir/bin/python" -m pip install --upgrade pip >/dev/null 2>&1 || true
    "$venv_dir/bin/python" -m pip install gdown >/dev/null 2>&1 || true
  fi
  if [ -x "$venv_dir/bin/gdown" ]; then
    export GDOWN_CMD="$venv_dir/bin/gdown"
    return 0
  fi
  print_yellow "gdown is still not available. You can re-run this option after relogin, or install manually."
  return 1
}

run_gdown() {
  # Wrapper to call gdown from PATH, user bin, or private venv
  if command -v gdown >/dev/null 2>&1; then
    gdown "$@"
    return $?
  fi
  if [ -n "$GDOWN_CMD" ] && [ -x "$GDOWN_CMD" ]; then
    "$GDOWN_CMD" "$@"
    return $?
  fi
  if [ -x "$HOME/.local/bin/gdown" ]; then
    "$HOME/.local/bin/gdown" "$@"
    return $?
  fi
  if [ -x "$BASE_DIR/.gdown-venv/bin/gdown" ]; then
    "$BASE_DIR/.gdown-venv/bin/gdown" "$@"
    return $?
  fi
  print_red "gdown command not found."
  return 1
}

record_uploaded_file() {
  local file_name="$1"
  ensure_base_dir
  touch "$UPLOADS_DB" 2>/dev/null || true
  if [ -n "$file_name" ]; then
    if ! grep -Fxq "$file_name" "$UPLOADS_DB" 2>/dev/null; then
      echo "$file_name" >> "$UPLOADS_DB"
    fi
  fi
}

# === Interactive flows ===

swap_sol_flow() {
  ensure_pipe_installed || return 1
  local amount
  while true; do
    amount=$(ask_with_default "Enter amount in SOL to swap for PIPE" "")
    if [ -z "$amount" ]; then
      print_yellow "Amount cannot be empty."
      continue
    fi
    if echo "$amount" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
      break
    else
      print_yellow "Amount must be a positive number (e.g. 0.5)."
    fi
  done
  print_cyan "Running: pipe swap-sol-for-pipe $amount"
  if pipe swap-sol-for-pipe "$amount"; then
    print_green "Swap submitted."
  else
    print_red "Swap failed."
  fi
}

upload_local_flow() {
  ensure_pipe_installed || return 1
  print_yellow "Don't upload confidential files (wallet keys, personal docs)."
  local src_path
  while true; do
    src_path=$(ask_with_default "Enter local file path to upload (supports ~)" "")
    if [ -z "$src_path" ]; then
      print_yellow "File path cannot be empty."
      continue
    fi
    src_path=$(expand_path "$src_path")
    if [ -f "$src_path" ]; then
      break
    else
      print_yellow "File not found: $src_path"
    fi
  done
  local default_name
  default_name=$(basename "$src_path")
  local file_name
  file_name=$(ask_with_default "Enter file name to save as on Pipe" "$default_name")
  print_cyan "Running: pipe upload-file '$src_path' '$file_name'"
  if pipe upload-file "$src_path" "$file_name"; then
    print_green "Upload complete: $file_name"
    record_uploaded_file "$file_name"
  else
    print_red "Upload failed."
  fi
}

upload_gdrive_flow() {
  ensure_pipe_installed || return 1
  ensure_gdown || return 1
  print_yellow "Don't upload confidential files (wallet keys, personal docs)."
  local url
  while true; do
    url=$(ask_with_default "Enter Google Drive URL" "")
    if [ -n "$url" ]; then break; fi
    print_yellow "URL cannot be empty."
  done
  local file_name
  file_name=$(ask_with_default "Enter file name to save as on Pipe (e.g., movie.mp4)" "downloaded_file")
  local dl_dir
  dl_dir=$(ensure_uploads_dir)
  local out_path="$dl_dir/$file_name"
  print_cyan "Downloading with gdown to: $out_path"
  if run_gdown --fuzzy "$url" -O "$out_path"; then
    print_cyan "Uploading to Pipe: $file_name"
    if pipe upload-file "$out_path" "$file_name"; then
      print_green "Uploaded: $file_name"
      record_uploaded_file "$file_name"
    else
      print_red "Upload failed after download."
    fi
  else
    print_red "Download failed."
  fi
}

upload_file_menu() {
  echo
  print_green "=== Upload a File ==="
  print_green "1) Upload from local path"
  print_green "2) Load from Google Drive URL and upload"
  print_green "0) Back"
  while true; do
    read -r -p "Select an option: " up_choice
    case "$up_choice" in
      1) upload_local_flow; break ;;
      2) upload_gdrive_flow; break ;;
      0) break ;;
      *) print_yellow "Invalid choice. Try again." ;;
    esac
  done
}

create_public_link_menu() {
  ensure_pipe_installed || return 1
  echo
  print_green "=== Create Public Link ==="
  local selection=""
  local chosen_name=""
  if [ -s "$UPLOADS_DB" ]; then
    print_cyan "Choose from previously uploaded files or press Enter to type a custom name:"
    local -a files
    mapfile -t files < "$UPLOADS_DB"
    local i=1
    for f in "${files[@]}"; do
      print_green "$i) $f"
      i=$((i+1))
    done
    read -r -p "Type a number (1-${#files[@]}) or press Enter to type name: " selection
    if [ -n "$selection" ] && echo "$selection" | grep -Eq '^[0-9]+$' && [ "$selection" -ge 1 ] && [ "$selection" -le ${#files[@]} ]; then
      chosen_name="${files[$((selection-1))]}"
    fi
  fi
  if [ -z "$chosen_name" ]; then
    chosen_name=$(ask_with_default "Enter file name used when uploading (e.g., text.mkv)" "")
    if [ -z "$chosen_name" ]; then
      print_yellow "File name cannot be empty."
      return 1
    fi
  fi
  print_cyan "Running: pipe create-public-link '$chosen_name'"
  if pipe create-public-link "$chosen_name"; then
    print_green "Public link created for: $chosen_name"
  else
    print_red "Failed to create public link."
  fi
}

check_token_usage() {
  ensure_pipe_installed || return 1
  print_cyan "Fetching token usage (30 days)..."
  if pipe token-usage; then
    :
  else
    print_red "Failed to fetch token usage."
  fi
}

show_referral_stats() {
  ensure_pipe_installed || return 1
  print_cyan "Referral stats:"
  if pipe referral show; then
    :
  else
    print_red "Failed to fetch referral stats."
  fi
}

# Best-effort detection of public IPv4
is_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

detect_public_ip() {
  local ip
  # Public IP services (fast timeouts)
  for url in "https://api.ipify.org" "https://ifconfig.me"; do
    ip=$(curl -s --max-time 2 "$url")
    if is_ipv4 "$ip"; then
      echo "$ip"; return 0
    fi
  done
  # Cloud metadata fallbacks
  ip=$(curl -s --max-time 1 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
  if is_ipv4 "$ip"; then echo "$ip"; return 0; fi
  ip=$(curl -s --max-time 1 -H "Metadata-Flavor: Google" \
    http://metadata/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip 2>/dev/null)
  if is_ipv4 "$ip"; then echo "$ip"; return 0; fi
  ip=$(curl -s --max-time 1 -H "Metadata: true" \
    "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text" 2>/dev/null)
  if is_ipv4 "$ip"; then echo "$ip"; return 0; fi
  # Local fallbacks (may be private)
  ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  if is_ipv4 "$ip"; then echo "$ip"; return 0; fi
  ip=$(ip route get 1 2>/dev/null | awk '/src/ {print $7; exit}')
  if is_ipv4 "$ip"; then echo "$ip"; return 0; fi
  echo "<YOUR_SERVER_IP>"
}

confirm() {
  # Usage: confirm "Prompt text"; returns 0 if yes, 1 otherwise
  local prompt="$1"
  local reply
  read -r -p "$prompt [y/N]: " reply
  case "$reply" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

ask_with_default() {
  # Usage: ask_with_default "Prompt" "default_value" -> echoes result
  local prompt="$1"
  local default_val="$2"
  local input
  if [ -n "$default_val" ]; then
    read -r -p "$prompt [$default_val]: " input
    echo "${input:-$default_val}"
  else
    read -r -p "$prompt: " input
    echo "$input"
  fi
}

ask_password_confirm() {
  # Echoes the chosen password after confirming
  local pass1
  local pass2
  while true; do
    read -r -s -p "Enter password: " pass1; echo
    if [ -z "$pass1" ]; then
      print_yellow "Password cannot be empty."
      continue
    fi
    read -r -s -p "Confirm password: " pass2; echo
    if [ "$pass1" = "$pass2" ]; then
      echo "$pass1"
      return 0
    else
      print_yellow "Passwords do not match. Try again."
    fi
  done
}

ensure_sudo() {
  if sudo -n true 2>/dev/null; then
    return 0
  fi
  print_yellow "Elevating privileges (sudo)..."
  sudo -v || {
    print_red "Failed to obtain sudo privileges. Exiting."
    exit 1
  }
}

ensure_apt() {
  if ! command -v apt-get >/dev/null 2>&1; then
    print_red "apt-get not found. This script supports Debian/Ubuntu (or WSL Ubuntu)."
    print_red "Please run inside Ubuntu or install WSL with Ubuntu."
    exit 1
  fi
}

install_dependencies() {
  ensure_apt
  ensure_sudo
  print_cyan "Updating and upgrading system packages..."
  sudo apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

  print_cyan "Installing required packages..."
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl iptables build-essential git wget lz4 jq make gcc postgresql-client nano \
    automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev tar clang \
    bsdmainutils ncdu unzip libleveldb-dev libclang-dev ninja-build \
    python3 python3-venv python3-pip
}

install_rust() {
  if command -v cargo >/dev/null 2>&1; then
    print_green "Rust and Cargo already installed."
  else
    print_cyan "Installing Rust (rustup)..."
    curl https://sh.rustup.rs -sSf | sh -s -- -y || {
      print_red "Rust installation failed."
      exit 1
    }
  fi

  # Ensure cargo is available in this session and future sessions
  if [ -f "$HOME/.cargo/env" ]; then
    # shellcheck disable=SC1090
    source "$HOME/.cargo/env"
  fi
  if ! grep -qs 'cargo/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$HOME/.bashrc"
  fi
  export PATH="$HOME/.cargo/bin:$PATH"
}

clone_and_build_pipe() {
  # Keep the official repo path as $HOME/pipe to match common docs and avoid conflicts
  local clone_dir="$HOME/pipe"

  if [ -d "$clone_dir/.git" ]; then
    print_green "Pipe repository already exists at $clone_dir"
  else
    print_cyan "Cloning Pipe repository..."
    git clone https://github.com/PipeNetwork/pipe.git "$clone_dir" || {
      print_red "Failed to clone repository."
      exit 1
    }
  fi

  print_cyan "Building and installing the Pipe CLI..."
  pushd "$clone_dir" >/dev/null || exit 1
  cargo install --path . || {
    print_red "Cargo failed to install the Pipe CLI."
    popd >/dev/null 2>&1 || true
    exit 1
  }
  popd >/dev/null || true

  if command -v pipe >/dev/null 2>&1; then
    print_green "Pipe CLI installed successfully."
  else
    print_red "Pipe CLI not found on PATH after installation. Ensure $HOME/.cargo/bin is in PATH."
    exit 1
  fi
}

create_management_site() {
  print_green "=== Create Management Site (port 3001) ==="

  # Ensure dependencies
  install_dependencies

  ensure_base_dir
  local site_dir="$BASE_DIR/management_site"
  if [ ! -d "$site_dir" ]; then
    print_yellow "Management site source not found at $site_dir. Creating it..."
    mkdir -p "$site_dir/templates" || {
      print_red "Failed to create $site_dir"
      return 1
    }

    # Write app.py
    cat > "$site_dir/app.py" << 'PYAPP'
import os
import re
import subprocess
from pathlib import Path

from flask import Flask, render_template, request, redirect, url_for, flash


app = Flask(__name__)
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "pipe-secret")


def get_env_with_cargo_path():
    env = os.environ.copy()
    cargo_bin = str(Path.home() / ".cargo" / "bin")
    env["PATH"] = f"{cargo_bin}:{env.get('PATH', '')}"
    return env


def run_command(cmd, timeout=600):
    try:
        completed = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            env=get_env_with_cargo_path(),
        )
        return completed.returncode, completed.stdout, completed.stderr
    except subprocess.TimeoutExpired as exc:
        return 124, exc.stdout or "", exc.stderr or ""


def ensure_uploads_dir() -> Path:
    uploads = Path.home() / "uploads"
    uploads.mkdir(parents=True, exist_ok=True)
    return uploads


def parse_public_links(output: str):
    direct = None
    preview = None
    for line in output.splitlines():
        if "publicDownload?hash=" in line:
            url = line.strip()
            if "preview=true" in url:
                preview = url
            else:
                direct = url
    return direct, preview


def get_token_usage():
    code, out, err = run_command(["pipe", "token-usage"])  # defaults to 30d
    if code != 0:
        return False, err.strip() or out.strip() or "Failed to fetch token usage."
    return True, out


@app.route("/", methods=["GET"])
def index():
    return render_template("index.html")


@app.post("/deposit")
def deposit():
    amount = (request.form.get("amount") or "").strip()
    if not amount:
        flash("Enter an amount in SOL.", "error")
        return redirect(url_for("index"))
    if not re.fullmatch(r"\d+(?:\.\d+)?", amount):
        flash("Amount must be a number.", "error")
        return redirect(url_for("index"))

    code, out, err = run_command(["pipe", "swap-sol-for-pipe", amount])
    if code == 0:
        flash(f"Swap submitted for {amount} SOL. Output:\n{out}", "success")
    else:
        flash(f"Swap failed. Error:\n{err or out}", "error")
    return redirect(url_for("index"))


@app.post("/upload_local")
def upload_local():
    ensure_uploads_dir()
    file = request.files.get("file")
    desired_name = (request.form.get("desired_name") or "").strip()
    if not file or file.filename == "":
        flash("Please choose a file to upload.", "error")
        return redirect(url_for("index"))
    saved_path = ensure_uploads_dir() / file.filename
    file.save(saved_path)

    file_name = desired_name or file.filename
    code, out, err = run_command(["pipe", "upload-file", str(saved_path), file_name])
    if code == 0:
        flash(f"Uploaded '{file_name}'. CLI output:\n{out}", "success")
    else:
        flash(f"Upload failed. Error:\n{err or out}", "error")
    return redirect(url_for("index"))


@app.post("/upload_gdrive")
def upload_gdrive():
    ensure_uploads_dir()
    url = (request.form.get("gdrive_url") or "").strip()
    desired_name = (request.form.get("desired_name_g") or "").strip()
    if not url:
        flash("Provide a Google Drive URL.", "error")
        return redirect(url_for("index"))

    output_name = desired_name or "downloaded_file"
    output_path = ensure_uploads_dir() / output_name
    code, out, err = run_command(["gdown", "--fuzzy", url, "-O", str(output_path)])
    if code != 0:
        flash(f"Download failed. Error:\n{err or out}", "error")
        return redirect(url_for("index"))

    code2, out2, err2 = run_command(["pipe", "upload-file", str(output_path), output_name])
    if code2 == 0:
        flash(f"Downloaded and uploaded '{output_name}'. CLI output:\n{out2}", "success")
    else:
        flash(f"Upload failed after download. Error:\n{err2 or out2}", "error")
    return redirect(url_for("index"))


@app.post("/public_link")
def public_link():
    file_name = (request.form.get("public_file_name") or "").strip()
    if not file_name:
        flash("Enter the file name you used when uploading.", "error")
        return redirect(url_for("index"))

    code, out, err = run_command(["pipe", "create-public-link", file_name])
    if code != 0:
        flash(f"Failed to create public link. Error:\n{err or out}", "error")
        return redirect(url_for("index"))

    direct, preview = parse_public_links(out)
    if direct or preview:
        combined = "\n".join(filter(None, [
            "Direct link (for downloads/playback):",
            direct,
            "",
            "Social media link (for sharing):",
            preview,
        ]))
        flash(combined, "success")
    else:
        flash(out, "success")
    return redirect(url_for("index"))


@app.get("/usage")
def usage():
    ok, data = get_token_usage()
    if ok:
        flash(data, "success")
    else:
        flash(data, "error")
    return redirect(url_for("index"))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3001, debug=False)
PYAPP

    # Write index.html
    cat > "$site_dir/templates/index.html" << 'HTMLTPL'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Pipe Management</title>
    <style>
      :root { --bg:#0f0f10; --fg:#e5e7eb; --muted:#9ca3af; --card:#151518; --accent:#22d3ee; }
      body { margin:0; font-family: system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, sans-serif; background:var(--bg); color:var(--fg); }
      .wrap { max-width: 920px; margin: 32px auto; padding: 0 16px; }
      .card { background:var(--card); border-radius: 12px; padding: 20px; margin-bottom: 20px; border:1px solid #222; }
      h1 { font-size: 24px; margin: 0 0 12px; }
      h2 { font-size: 18px; margin: 0 0 12px; color: var(--accent); }
      p { color: var(--muted); line-height: 1.6; }
      form { margin: 12px 0; }
      input[type="text"], input[type="number"], input[type="file"] { width: 100%; background:#0c0c0e; border:1px solid #2a2a2e; color:var(--fg); padding:10px 12px; border-radius: 8px; }
      input[type="submit"], button { background: linear-gradient(135deg, #22d3ee, #a78bfa); color:#0b0b0c; font-weight: 700; border:0; padding: 10px 14px; border-radius: 8px; cursor:pointer; }
      .note { font-size: 12px; color: #9ca3af; }
      .grid { display:grid; grid-template-columns: 1fr 1fr; gap:20px; }
      .alert { white-space: pre-wrap; padding: 12px; background: #0b1214; border: 1px solid #1f2937; border-radius: 8px; margin: 8px 0; }
      .success { border-color:#064e3b; background:#071a17; }
      .error { border-color:#7f1d1d; background:#190b0b; }
      .footer { text-align:center; color:#6b7280; font-size:12px; margin-top:24px; }
      @media (max-width: 800px) { .grid { grid-template-columns: 1fr; } }
    </style>
  </head>
  <body>
    <div class="wrap">
      <div class="card">
        <h1>Pipe Command Center</h1>
        <p>Manage your node, swap SOL⇄PIPE, upload huge files, and mint shareable links — all from your VPS.</p>
      </div>

      {% with messages = get_flashed_messages(with_categories=true) %}
        {% if messages %}
          <div class="card">
            <h2>Console</h2>
            {% for category, msg in messages %}
              <div class="alert {{ category }}">{{ msg }}</div>
            {% endfor %}
          </div>
        {% endif %}
      {% endwith %}

      <div class="grid">
        <div class="card">
          <h2>Deposit SOL → PIPE</h2>
          <form method="post" action="/deposit">
            <label>Amount in SOL</label>
            <input type="text" name="amount" placeholder="e.g. 0.5" required />
            <div style="height:10px"></div>
            <input type="submit" value="Deposit" />
          </form>
          <p class="note">Uses <code>pipe swap-sol-for-pipe &lt;AMOUNT_SOL&gt;</code> on your VPS.</p>
        </div>

        <div class="card">
          <h2>Upload a File</h2>
          <p><b>Don’t upload confidential files</b> (wallet keys, personal docs). You can upload big videos too.</p>
          <form method="post" action="/upload_local" enctype="multipart/form-data">
            <label>Select from your computer</label>
            <input type="file" name="file" />
            <div style="height:10px"></div>
            <label>Save as (file name on Pipe)</label>
            <input type="text" name="desired_name" placeholder="my_video.mkv" />
            <div style="height:10px"></div>
            <input type="submit" value="Upload" />
          </form>

          <hr style="border:0; border-top:1px solid #2a2a2e; margin:16px 0;" />

          <form method="post" action="/upload_gdrive">
            <label>Or import from Google Drive URL</label>
            <input type="text" name="gdrive_url" placeholder="https://drive.google.com/..." />
            <div style="height:10px"></div>
            <label>Save as (file name on Pipe)</label>
            <input type="text" name="desired_name_g" placeholder="movie.mp4" />
            <div style="height:10px"></div>
            <input type="submit" value="Import + Upload" />
          </form>

          <p class="note">Local files stored under <code>~/uploads</code> on the VPS.</p>
        </div>
      </div>

      <div class="grid">
        <div class="card">
          <h2>Create Public Link</h2>
          <form method="post" action="/public_link">
            <label>File name you uploaded</label>
            <input type="text" name="public_file_name" placeholder="5cm.mkv" />
            <div style="height:10px"></div>
            <input type="submit" value="Create Link" />
          </form>
          <p class="note">Runs <code>pipe create-public-link &lt;FILE_NAME&gt;</code> to give both direct and preview links.</p>
        </div>

        <div class="card">
          <h2>Rewards + Usage</h2>
          <form method="get" action="/usage">
            <input type="submit" value="Show Token Usage (30d)" />
          </form>
          <p class="note">Displays your latest <code>pipe token-usage</code> report with GB transferred and PIPE spent.</p>
        </div>
      </div>

      <div class="footer">Serving on port 3001 — keep this tab open while managing. </div>
    </div>
  </body>
  </html>
HTMLTPL

    # Write requirements.txt
    cat > "$site_dir/requirements.txt" << 'REQS'
Flask==3.0.3
gdown==5.2.0
REQS
  fi

  # Ensure critical files exist (in case directory existed but files are missing)
  if [ ! -f "$site_dir/requirements.txt" ]; then
    cat > "$site_dir/requirements.txt" << 'REQS'
Flask==3.0.3
gdown==5.2.0
REQS
  fi
  if [ ! -f "$site_dir/app.py" ]; then
    cat > "$site_dir/app.py" << 'PYAPP'
import os
import re
import subprocess
from pathlib import Path

from flask import Flask, render_template, request, redirect, url_for, flash


app = Flask(__name__)
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "pipe-secret")


def get_env_with_cargo_path():
    env = os.environ.copy()
    cargo_bin = str(Path.home() / ".cargo" / "bin")
    env["PATH"] = f"{cargo_bin}:{env.get('PATH', '')}"
    return env


def run_command(cmd, timeout=600):
    try:
        completed = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            env=get_env_with_cargo_path(),
        )
        return completed.returncode, completed.stdout, completed.stderr
    except subprocess.TimeoutExpired as exc:
        return 124, exc.stdout or "", exc.stderr or ""


def ensure_uploads_dir() -> Path:
    uploads = Path.home() / "uploads"
    uploads.mkdir(parents=True, exist_ok=True)
    return uploads


def parse_public_links(output: str):
    direct = None
    preview = None
    for line in output.splitlines():
        if "publicDownload?hash=" in line:
            url = line.strip()
            if "preview=true" in url:
                preview = url
            else:
                direct = url
    return direct, preview


def get_token_usage():
    code, out, err = run_command(["pipe", "token-usage"])  # defaults to 30d
    if code != 0:
        return False, err.strip() or out.strip() or "Failed to fetch token usage."
    return True, out


@app.route("/", methods=["GET"])
def index():
    return render_template("index.html")


@app.post("/deposit")
def deposit():
    amount = (request.form.get("amount") or "").strip()
    if not amount:
        flash("Enter an amount in SOL.", "error")
        return redirect(url_for("index"))
    if not re.fullmatch(r"\d+(?:\.\d+)?", amount):
        flash("Amount must be a number.", "error")
        return redirect(url_for("index"))

    code, out, err = run_command(["pipe", "swap-sol-for-pipe", amount])
    if code == 0:
        flash(f"Swap submitted for {amount} SOL. Output:\n{out}", "success")
    else:
        flash(f"Swap failed. Error:\n{err or out}", "error")
    return redirect(url_for("index"))


@app.post("/upload_local")
def upload_local():
    ensure_uploads_dir()
    file = request.files.get("file")
    desired_name = (request.form.get("desired_name") or "").strip()
    if not file or file.filename == "":
        flash("Please choose a file to upload.", "error")
        return redirect(url_for("index"))
    saved_path = ensure_uploads_dir() / file.filename
    file.save(saved_path)

    file_name = desired_name or file.filename
    code, out, err = run_command(["pipe", "upload-file", str(saved_path), file_name])
    if code == 0:
        flash(f"Uploaded '{file_name}'. CLI output:\n{out}", "success")
    else:
        flash(f"Upload failed. Error:\n{err or out}", "error")
    return redirect(url_for("index"))


@app.post("/upload_gdrive")
def upload_gdrive():
    ensure_uploads_dir()
    url = (request.form.get("gdrive_url") or "").strip()
    desired_name = (request.form.get("desired_name_g") or "").strip()
    if not url:
        flash("Provide a Google Drive URL.", "error")
        return redirect(url_for("index"))

    output_name = desired_name or "downloaded_file"
    output_path = ensure_uploads_dir() / output_name
    code, out, err = run_command(["gdown", "--fuzzy", url, "-O", str(output_path)])
    if code != 0:
        flash(f"Download failed. Error:\n{err or out}", "error")
        return redirect(url_for("index"))

    code2, out2, err2 = run_command(["pipe", "upload-file", str(output_path), output_name])
    if code2 == 0:
        flash(f"Downloaded and uploaded '{output_name}'. CLI output:\n{out2}", "success")
    else:
        flash(f"Upload failed after download. Error:\n{err2 or out2}", "error")
    return redirect(url_for("index"))


@app.post("/public_link")
def public_link():
    file_name = (request.form.get("public_file_name") or "").strip()
    if not file_name:
        flash("Enter the file name you used when uploading.", "error")
        return redirect(url_for("index"))

    code, out, err = run_command(["pipe", "create-public-link", file_name])
    if code != 0:
        flash(f"Failed to create public link. Error:\n{err or out}", "error")
        return redirect(url_for("index"))

    direct, preview = parse_public_links(out)
    if direct or preview:
        combined = "\n".join(filter(None, [
            "Direct link (for downloads/playback):",
            direct,
            "",
            "Social media link (for sharing):",
            preview,
        ]))
        flash(combined, "success")
    else:
        flash(out, "success")
    return redirect(url_for("index"))


@app.get("/usage")
def usage():
    ok, data = get_token_usage()
    if ok:
        flash(data, "success")
    else:
        flash(data, "error")
    return redirect(url_for("index"))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3001, debug=False)
PYAPP
  fi
  if [ ! -f "$site_dir/templates/index.html" ]; then
    mkdir -p "$site_dir/templates" 2>/dev/null || true
    cat > "$site_dir/templates/index.html" << 'HTMLTPL'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Pipe Management</title>
    <style>
      :root { --bg:#0f0f10; --fg:#e5e7eb; --muted:#9ca3af; --card:#151518; --accent:#22d3ee; }
      body { margin:0; font-family: system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, sans-serif; background:var(--bg); color:var(--fg); }
      .wrap { max-width: 920px; margin: 32px auto; padding: 0 16px; }
      .card { background:var(--card); border-radius: 12px; padding: 20px; margin-bottom: 20px; border:1px solid #222; }
      h1 { font-size: 24px; margin: 0 0 12px; }
      h2 { font-size: 18px; margin: 0 0 12px; color: var(--accent); }
      p { color: var(--muted); line-height: 1.6; }
      form { margin: 12px 0; }
      input[type="text"], input[type="number"], input[type="file"] { width: 100%; background:#0c0c0e; border:1px solid #2a2a2e; color:var(--fg); padding:10px 12px; border-radius: 8px; }
      input[type="submit"], button { background: linear-gradient(135deg, #22d3ee, #a78bfa); color:#0b0b0c; font-weight: 700; border:0; padding: 10px 14px; border-radius: 8px; cursor:pointer; }
      .note { font-size: 12px; color: #9ca3af; }
      .grid { display:grid; grid-template-columns: 1fr 1fr; gap:20px; }
      .alert { white-space: pre-wrap; padding: 12px; background: #0b1214; border: 1px solid #1f2937; border-radius: 8px; margin: 8px 0; }
      .success { border-color:#064e3b; background:#071a17; }
      .error { border-color:#7f1d1d; background:#190b0b; }
      .footer { text-align:center; color:#6b7280; font-size:12px; margin-top:24px; }
      @media (max-width: 800px) { .grid { grid-template-columns: 1fr; } }
    </style>
  </head>
  <body>
    <div class="wrap">
      <div class="card">
        <h1>Pipe Command Center</h1>
        <p>Manage your node, swap SOL⇄PIPE, upload huge files, and mint shareable links — all from your VPS.</p>
      </div>

      {% with messages = get_flashed_messages(with_categories=true) %}
        {% if messages %}
          <div class="card">
            <h2>Console</h2>
            {% for category, msg in messages %}
              <div class="alert {{ category }}">{{ msg }}</div>
            {% endfor %}
          </div>
        {% endif %}
      {% endwith %}

      <div class="grid">
        <div class="card">
          <h2>Deposit SOL → PIPE</h2>
          <form method="post" action="/deposit">
            <label>Amount in SOL</label>
            <input type="text" name="amount" placeholder="e.g. 0.5" required />
            <div style="height:10px"></div>
            <input type="submit" value="Deposit" />
          </form>
          <p class="note">Uses <code>pipe swap-sol-for-pipe &lt;AMOUNT_SOL&gt;</code> on your VPS. Need Devnet SOL? Get some from the <a href="https://faucet.solana.com/" target="_blank" rel="noreferrer">Solana Faucet</a>.</p>
        </div>

        <div class="card">
          <h2>Upload a File</h2>
          <p><b>Don’t upload confidential files</b> (wallet keys, personal docs). You can upload big videos too.</p>
          <form method="post" action="/upload_local" enctype="multipart/form-data">
            <label>Select from your computer</label>
            <input type="file" name="file" />
            <div style="height:10px"></div>
            <label>Save as (file name on Pipe)</label>
            <input type="text" name="desired_name" placeholder="my_video.mkv" />
            <div style="height:10px"></div>
            <input type="submit" value="Upload" />
          </form>

          <hr style="border:0; border-top:1px solid #2a2a2e; margin:16px 0;" />

          <form method="post" action="/upload_gdrive">
            <label>Or import from Google Drive URL</label>
            <input type="text" name="gdrive_url" placeholder="https://drive.google.com/..." />
            <div style="height:10px"></div>
            <label>Save as (file name on Pipe)</label>
            <input type="text" name="desired_name_g" placeholder="movie.mp4" />
            <div style="height:10px"></div>
            <input type="submit" value="Import + Upload" />
          </form>

          <p class="note">Local files stored under <code>~/uploads</code> on the VPS.</p>
        </div>
      </div>

      <div class="grid">
        <div class="card">
          <h2>Create Public Link</h2>
          <form method="post" action="/public_link">
            <label>File name you uploaded</label>
            <input type="text" name="public_file_name" placeholder="5cm.mkv" />
            <div style="height:10px"></div>
            <input type="submit" value="Create Link" />
          </form>
          <p class="note">Runs <code>pipe create-public-link &lt;FILE_NAME&gt;</code> to give both direct and preview links.</p>
        </div>

        <div class="card">
          <h2>Rewards + Usage</h2>
          <form method="get" action="/usage">
            <input type="submit" value="Show Token Usage (30d)" />
          </form>
          <p class="note">Displays your latest <code>pipe token-usage</code> report with GB transferred and PIPE spent.</p>
        </div>
      </div>

      <div class="footer">Serving on port 3001 — keep this tab open while managing. </div>
    </div>
  </body>
  </html>
HTMLTPL
  fi

  # Setup venv
  local venv_dir="$site_dir/.venv"
  if [ ! -d "$venv_dir" ]; then
    print_cyan "Creating Python venv..."
    python3 -m venv "$venv_dir" || {
      print_red "Failed to create Python venv"
      return 1
    }
  fi

  # shellcheck disable=SC1091
  source "$venv_dir/bin/activate"
  pip install --upgrade pip >/dev/null 2>&1
  pip install -r "$site_dir/requirements.txt" || {
    print_red "Failed to install Python requirements"
    deactivate 2>/dev/null || true
    return 1
  }

  # Run in tmux so it keeps serving
  local session_name="pipe-mgmt-site"
  if tmux has-session -t "$session_name" 2>/dev/null; then
    print_yellow "An existing tmux session '$session_name' is running. Restarting it..."
    tmux kill-session -t "$session_name" 2>/dev/null || true
  fi

  print_cyan "Starting management site in tmux session '$session_name' on port 3001..."
  # Ensure Basic Auth credentials: ask the user on installation, persist to file
  local auth_file="$site_dir/.auth"
  local mgmt_user
  local mgmt_pass
  # If env vars are provided, use them directly and persist
  if [ -n "${MGMT_USER:-}" ] && [ -n "${MGMT_PASS:-}" ]; then
    mgmt_user="$MGMT_USER"
    mgmt_pass="$MGMT_PASS"
    print_green "Using MGMT_USER/MGMT_PASS from environment."
  elif [ -f "$auth_file" ] && confirm "Use existing saved credentials from $auth_file?"; then
    # shellcheck disable=SC1090
    source "$auth_file"
    mgmt_user="${MGMT_USER_FILE:-shair}"
    mgmt_pass="${MGMT_PASS_FILE:-}"
    if [ -z "$mgmt_pass" ]; then
      print_yellow "Saved password is empty. You'll be asked to set a new one."
    fi
  fi
  if [ -z "$mgmt_user" ] || [ -z "$mgmt_pass" ]; then
    print_green "Set credentials to protect the management site:"
    mgmt_user=$(ask_with_default "Username" "shair")
    while [ -z "$mgmt_user" ]; do
      print_yellow "Username cannot be empty."
      mgmt_user=$(ask_with_default "Username" "shair")
    done
    mgmt_pass=$(ask_password_confirm)
    {
      echo "MGMT_USER_FILE=$mgmt_user"
      echo "MGMT_PASS_FILE=$mgmt_pass"
    } > "$auth_file"
    print_green "Saved credentials to $auth_file."
  fi
  tmux new-session -d -s "$session_name" bash -lc "cd '$site_dir' && source .venv/bin/activate && MGMT_USER='$mgmt_user' MGMT_PASS='$mgmt_pass' FLASK_APP=app.py python app.py"

  # Determine public server IP (best effort)
  local ip
  ip=$(detect_public_ip)

  print_green "Management site is starting. Access: http://$ip:3001"
  print_green "To view logs: tmux attach -t $session_name (Ctrl+b d to detach)"
  deactivate 2>/dev/null || true
}

setup_pipe_user_flow() {
  print_green "=== Pipe User Setup ==="

  if ! command -v pipe >/dev/null 2>&1; then
    print_red "Pipe CLI not found. Please run 'Install Pipe' from the menu first."
    return 1
  fi

  local username
  while true; do
    username=$(ask_with_default "Enter your Pipe username" "")
    if [ -n "$username" ]; then
      break
    fi
    print_yellow "Username cannot be empty."
  done

  print_cyan "Creating user: $username"
  if ! pipe new-user "$username"; then
    print_red "Failed to create user with 'pipe new-user'."
    if ! confirm "Continue anyway?"; then
      return 1
    fi
  fi

  print_green "Copy your Solana Pubkey now (it was printed above if available)."
  print_green "You can also find it in: $HOME/.pipe-cli.json"
  if confirm "Have you copied your Solana Pubkey?"; then
    print_cyan "Now setting a password (follow the interactive prompt)..."
    pipe set-password || print_yellow "'pipe set-password' did not complete successfully. You can re-run it later."
  else
    print_yellow "Skipping password setup for now. You can run 'pipe set-password' later."
  fi

  if [ -f "$HOME/.pipe-cli.json" ]; then
    print_cyan "Showing your ~/.pipe-cli.json (save this securely):"
    echo "-------------------------------------------"
    cat "$HOME/.pipe-cli.json"
    echo "\n-------------------------------------------"
  else
    print_yellow "~/.pipe-cli.json not found yet. It will be created by the CLI once initialized."
  fi

  if confirm "Have you saved your ~/.pipe-cli.json securely?"; then
    :
  else
    print_yellow "Make sure to save it later."
  fi

  local default_ref="SHAIR-O1HG"
  local ref_code
  print_green "Enter the Referral Code (press Enter to use the default)."
  ref_code=$(ask_with_default "Referral Code" "$default_ref")
  print_cyan "Applying referral code: $ref_code"
  if ! pipe referral apply "$ref_code"; then
    print_yellow "Failed to apply referral code. You can run: pipe referral apply $ref_code"
  fi

  if confirm "Generate your own referral code now?"; then
    print_cyan "Generating your referral code..."
    pipe referral generate || print_yellow "Could not generate referral code now. Try later: 'pipe referral generate'"
    print_green "Save your referral code for future use."
  fi

  print_green "# Swap SOL (Devnet) to PIPE"
  print_green "Visit the Solana Faucet to fund your Devnet wallet: https://faucet.solana.com/"
  print_green "Use the wallet you just created, then request and deposit Devnet SOL."
  if confirm "Did you deposit Devnet SOL?"; then
    print_green "Great! You're all set."
  else
    print_yellow "You can deposit later by visiting: https://faucet.solana.com/"
  fi
}

run_install() {
  install_dependencies
  install_rust
  clone_and_build_pipe
}

show_menu() {
  echo
  print_green "=============================="
  print_green "        Pipe Setup Menu        "
  print_green "=============================="
  print_green "Pipe Setup - by shair"
  print_green "1) Install Pipe (deps + Rust + build)"
  print_green "2) Configure Pipe (user setup, referral, faucet)"
  print_green "3) Create Management Site (serve on port 3001)"
  print_green "4) Swap SOL → PIPE"
  print_green "5) Upload File"
  print_green "6) Create Public Link"
  print_green "7) Check Token-Usage"
  print_green "8) Show Referral Stats"
  print_green "0) Exit"
  echo
}

main() {
  while true; do
    show_menu
    read -r -p "Select an option: " choice
    case "$choice" in
      1)
        run_install
        ;;
      2)
        setup_pipe_user_flow
        ;;
      3)
        create_management_site
        ;;
      4)
        swap_sol_flow
        ;;
      5)
        upload_file_menu
        ;;
      6)
        create_public_link_menu
        ;;
      7)
        check_token_usage
        ;;
      8)
        show_referral_stats
        ;;
      0)
        print_green "Bye!"
        exit 0
        ;;
      *)
        print_yellow "Invalid choice. Try again."
        ;;
    esac
  done
}

main "$@"


