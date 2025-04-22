#!/bin/bash

echo "Disabling unnecessary services..."

# Avahi - mDNS/Bonjour
sudo systemctl disable --now avahi-daemon

# Bluetooth (and serial config for it)
sudo systemctl disable --now bluetooth hciuart

# Colord - color management, only used with GUI
sudo systemctl disable --now colord

# Triggerhappy - GPIO/button listener
sudo systemctl disable --now triggerhappy

# Wi-Fi supplicant (only if you're Ethernet-only)
sudo systemctl disable --now wpa_supplicant

# Optional: disable ISC DHCP server if dnsmasq is doing DHCP
sudo systemctl disable --now isc-dhcp-server

echo "Done. You can reboot or check status with: systemctl list-units --type=service --state=running"
