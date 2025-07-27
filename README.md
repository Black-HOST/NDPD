# NDPD - Neighbor Discovery Protocol Daemon

## 🚨 THE PROBLEM

The majority of web hosting providers provide at least /64 IPv6 subnet nowadays to their clients. That is 2⁶⁴ IP addresses, around 18 quintillion, or to put into perspective it is about 4.3 billion times more addresses than the entire IPv4 address space 🤯.

In IPv6, ARP (Address Resolution Protocol) was replaced by a more efficient mechanism called NDP (Neighbor Discovery Protocol). Instead of broadcasting ARP requests, NDP uses multicast ICMPv6 messages to discover neighbors and routers. This approach is more efficient than ARP’s broadcasts, avoiding unnecessary traffic in large subnets and supporting features like Duplicate Address Detection (DAD).

While NDP is a robust and well-designed system, it has some drawbacks from a user perspective. Since NDP relies on ICMPv6 Neighbor Solicitation/Advertisement to establish address reachability, a newly added global IPv6 address might not be immediately usable, particularly for incoming traffic, until the OS announces the new address to the network or receives relevant traffic. Basicaly the gateway needs to learn which physical machine (identified by its MAC address) is using that new IP address before it can forward any incoming traffic to it.

This can often be resolved by sending an outbound ping from the new IPv6 address (e.g. ping -6 -I 2a01:e940:0:242:: black.host), which prompts the OS to initiate NDP resolution and announce the new address. However, in environments like shared hosting (e.g. cPanel), IPv6 addresses may be automatically assigned. With such big address space (up to 2⁶⁴ usable IPs in a /64), manually monitoring and pinging each new address can be quite a demanding task.

---

## 🚀 THE SOLUTION

**NDPD** is a lightweight daemon that monitors network interfaces for newly assigned global IPv6 addresses. When a new address is detected, NDPD uses `ndisc6` to send an NDP probe to the default gateway, instantly announcing the address to the network. This eliminates manual intervention, reduces downtime, and ensures seamless IPv6 connectivity in large subnets.

---

## 📦 INSTALLATION

To install NDPD, run this simple oneliner :

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Black-HOST/NDPD/master/install.sh)
```

Or using `wget`:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/Black-HOST/NDPD/master/install.sh)
```

This will:
- Detect your distro and install core dependency `ndisc6` (on RHEL 7 systems via EPEL)
- Install the NDPD script to `/usr/local/bin/ndpd`
- Install and enable the systemd unit `ndpd.service`

To verify NDPD is running check: `systemctl status ndpd.service`

---

## 📋 REQUIREMENTS

- A Linux system with:
  - `bash`
  - `ip` (from `iproute2`)
  - `ndisc6` (installed automatically if missing)
  - `systemd`
- Root privileges

---

## ✅ TESTED ON

- Ubuntu 20.04, 22.04, 24.04
- Debian 10, 11, 12
- RHEL 7, 8, 9 based systems (including CentOS, AlmaLinux, Rocky Linux)
- Other `systemd`-based Linux distributions

---

## 🔄 HOW IT WORKS

NDPD runs `ip -6 monitor address` to watch for changes on all interfaces on the host.

When a new **global** IPv6 address is assigned:
1. The script extracts the interface and address
2. Finds the default gateway for that interface
3. Runs:
   ```bash
   ndisc6 <gateway> <interface> -s <ipv6_address>
   ```
4. This announces the address to the upstream router immediately

### Troubleshooting
- Check NDPD logs: `journalctl -u ndpd.service`
- Verify the default gateway is reachable: `ip -6 route`
- Ensure `ndisc6` is installed: `ndisc6 --version`

---

## 🧹 UNINSTALLATION

If NDPD is already installed, the installer will prompt you:

```
[!] NDPD is already installed at /usr/local/bin/ndpd.
Do you want to uninstall it? (y/N)
```

Uninstallation will:
- Stop and disable the service
- Remove the script and service files
- Reload systemd

---

## 🤝 CONTRIBUTING

Feel free to open issues or pull requests!
