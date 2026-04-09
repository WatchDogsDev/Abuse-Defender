<h1 align="center">Abuse Defender</h1>

<div align="center">
    <a href="https://t.me/savechannelkiya6955"> 
        <img src="https://img.shields.io/badge/TelegramChannel-%230577B8?logo=telegram" alt="Telegram channel"/> 
    </a>
    <a href="https://github.com/Kiya6955/Abuse-Defender"> 
        <img src="https://img.shields.io/github/stars/Kiya6955/Abuse-Defender?style=flat" alt="GitHub stars"/> 
    </a>
    <a href="https://github.com/Kiya6955/Abuse-Defender/releases/latest"> 
        <img src="https://img.shields.io/github/release/Kiya6955/Abuse-Defender.svg" alt="Latest release"/> 
    </a>
</div>

## Overview

**Abuse Defender** is a bash script that blocks abusive IP ranges and malicious domains using `iptables`, helping prevent your server from being flagged or blocked by your hosting provider.

## Requirements

- Debian/Ubuntu-based Linux distribution
- Root privileges
- `iptables` and `iptables-persistent` (auto-installed if missing)

## Usage

### Interactive mode

Run the script and use the menu to choose what to do:

```bash
bash <(curl -s https://raw.githubusercontent.com/WatchDogsDev/Abuse-Defender/refs/heads/main/abuse-defender.sh)
```

### Non-interactive mode

Automatically applies the default setup (block abuse IP ranges + configure DNS) without any prompts:

```bash
bash <(curl -s https://raw.githubusercontent.com/WatchDogsDev/Abuse-Defender/refs/heads/main/abuse-defender.sh) --auto
```

Accepted flags: `--non-interactive`, `-y`, `--auto`, `--defaults`

## Menu Options

| Option | Description |
|--------|-------------|
| **1** Block Abuse IP-Ranges | Blocks all IP ranges listed in `abuse-ips.ipv4` via `iptables`. Also blocks known malicious domains by redirecting them to `127.0.0.1` in `/etc/hosts`. |
| **2** Whitelist an IP / IP-Range | Adds an IP or CIDR range to the whitelist chain so it is never blocked. |
| **3** Block an IP / IP-Range manually | Adds a custom IP or CIDR range to the block chain. |
| **4** View Rules | Displays all current rules across the three `abuse-defender` chains. |
| **5** Clear all rules | Removes all `abuse-defender` iptables rules and restores original DNS settings. |
| **6** Setup DNS | Configures the system to use Cloudflare for Families (`1.1.1.2`) and Quad9 (`9.9.9.9`) as DNS servers. Supports both `systemd-resolved` and `/etc/resolv.conf`. |

## How It Works

### iptables chains

The script creates three dedicated chains and hooks them into both `INPUT` and `OUTPUT`:

- `abuse-defender` — blocked abuse IP ranges (from `abuse-ips.ipv4`)
- `abuse-defender-custom` — manually blocked IPs/ranges
- `abuse-defender-whitelist` — whitelisted IPs/ranges (evaluated first, always accepted)

Rules are persisted to `/etc/iptables/rules.v4` via `iptables-persistent`.

### Automatic whitelist

The following are whitelisted automatically when blocking abuse ranges:

- Localhost (`127.0.0.0/8`)
- RFC 1918 private ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`)
- Link-local (`169.254.0.0/16`)
- The server's own public IP(s)
- DNS servers (`1.1.1.2`, `9.9.9.9`)

### DNS protection

Option 6 sets up malware-blocking DNS resolvers:

- **Primary:** `1.1.1.2` — Cloudflare for Families (blocks malware & adult content)
- **Secondary:** `9.9.9.9` — Quad9 (blocks malicious domains)

Original DNS configuration is backed up and restored when rules are cleared (option 5).

## Contributing

If you'd like to contribute by adding IP ranges to the list, please send them via [Telegram](https://t.me/Kiya6955Contactbot).
