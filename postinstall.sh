#!/bin/bash

#
# Contains public sector information licensed under the Open Government Licence v3.0.
# https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/
#


if [[ $UID -ne 0 ]]; then
  echo "This script needs to be run as root (with sudo)"
  exit 1
fi

echo "If you are not using the default internet repositories you should configure this before running this script."
echo "You should also have an active network connection to the repositories."
read -p "Continue? [y/n]: " CONFIRM
if [ "$CONFIRM" != "y" ]; then
  exit
fi

# Refresh the package list
apt-get update

# Install extra packages
apt-get install -y apparmor-profiles apparmor-utils
apt-get install -y iptables-persistent

# Configure a basic IPv4 firewall
echo "*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p tcp -m tcp --dport 22 -m conntrack --ctstate NEW -j ACCEPT
-A OUTPUT -o lo -j ACCEPT
COMMIT" > /etc/iptables/rules.v4

# Configure a basic IPv6 firewall
echo "*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 134 -j ACCEPT
-A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 135 -j ACCEPT
-A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 136 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 22 -m conntrack --ctstate NEW -j ACCEPT
-A OUTPUT -o lo -j ACCEPT
COMMIT" > /etc/iptables/rules.v6

# Load the above rule sets
service iptables-persistent start

# Set some AppArmor profiles to enforce mode
aa-enforce /etc/apparmor.d/usr.bin.firefox
aa-enforce /etc/apparmor.d/usr.sbin.avahi-daemon
aa-enforce /etc/apparmor.d/usr.sbin.dnsmasq
aa-enforce /etc/apparmor.d/bin.ping
aa-enforce /etc/apparmor.d/usr.sbin.rsyslogd


# Turn off privacy-leaking aspects of Unity
echo "user-db:user" > /etc/dconf/profile/user
echo "system-db:local" >> /etc/dconf/profile/user

mkdir -p /etc/dconf/db/local.d

echo "[com/canonical/unity/lenses]" > /etc/dconf/db/local.d/unity
echo "remote-content-search=false" >> /etc/dconf/db/local.d/unity

mkdir -p /etc/dconf/db/local.d/locks

echo "/com/canonical/unity/lenses/remote-content-search" > /etc/dconf/db/local.d/locks/unity

dconf update


# Upgrade the system
apt-get dist-upgrade -y

echo -e "\nPOST INSTALLATION COMPLETE"
