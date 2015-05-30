#!/bin/bash

#
# Contains public sector information licensed under the Open Government Licence v3.0.
# https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/
#
# This script provides a basic way of configuring a single Ubuntu machine in accordance
# with the attached End User Device guidance. This script contains sugegstions only and
# should be customised for individual user needs. In particular it will likely not scale
# to large deployments; in those scenarios a purpose-built tool should handle the roll-
# out and deployment of these devices. SCM tools, preseed scripts and automated technology
# such as PXE boot scripts should be used instead.
#

if [[ $UID -ne 0 ]]; then
	echo "This script needs to be run as root (with sudo)"
	exit 1
fi

YES=Y
NO=N

function promptPassphrase {
  PASS=""
  PASSCONF=""
  while [ -z "$PASS" ]; do
    read -s -p "Passphrase: " PASS
    echo ""
  done
  while [ -z "$PASSCONF" ]; do
    read -s -p "Confirm passphrase: " PASSCONF
    echo ""
  done
  echo ""
}

function getPassphrase {
  promptPassphrase
  while [ "$PASS" != "$PASSCONF" ]; do
    echo "Passphrases did not match, try again..."
    promptPassphrase
  done
}

function confirm {
   QUESTION=$1
   CONFIRM=
   DEFAULT=$2
   OPTION="y/n"
   if [[ "${DEFAULT^^}" == "$YES" ]]; then
     OPTION="Y/n"
   elif [[ "${DEFAULT^^}" == "$NO" ]]; then
     OPTION="y/N"
   fi
   while [[ (-z "$CONFIRM") && (${CONFIRM^^} != "$YES" && ${CONFIRM^^} != "$NO") ]]; do
     read -p "$QUESTION ["$OPTION"]: " CONFIRM
     if [[ (-z "$CONFIRM") ]]; then
       CONFIRM=$DEFAULT
     fi
   done
   CONFIRM=${CONFIRM^^}
   echo ""
}

confirm "(Re)partion disk?" $YES
if [[ "$CONFIRM" == "$YES" ]]; then

  # Prompt for disk device to install to
  echo -e "\nSearching for disks...\n"
  lshw -short -class disk
  while [ -z "$DISK" ]; do read -p "Enter the disk to install to (eg. /dev/sda): " DISK; done
  confirm "(Re)partition disk $DISK?" $YES
  if [[ "$CONFIRM" == "$NO" ]]; then
    echo "Installer exiting..."
    exit 0
  fi

  # Prompt for whether an SCM will be used or not
  #echo -e "\nYou can use an SCM for configuration after install, or this script can perform configuration during the install.\n"
  #while [ "$DOCONFIG" != "y" -a "$DOCONFIG" != "n" ]; do read -p "Should the script perform configuration? [y/n]: " DOCONFIG; done
  
  echo -e "\n\nOk, preparing to partition...\n"

  # Ensure disk is not mounted
  for D in "$DISK"* ; do umount $D ; done

  # Partition disk
  sgdisk $DISK -Z
  sgdisk $DISK -g
  sgdisk $DISK -n 1:0:+512M -t 1:ef00 # create EFI partition
  sgdisk $DISK -n 2:0:+1024M -t 2:8300 # create boot partition
  sgdisk $DISK -N 3 -t 3:8e00         # create partition filling rest of disk
  echo ""

  CIPHER=aes-xts-plain64
  confirm "Encrypt entire disk partition 3 on ${DISK} using ${CIPHER}?" $YES
  ENCRYPT=$CONFIRM
  if [[ $ENCRYPT == "$YES" ]]; then
    # Set up LUKS
    echo "Please enter a disk encryption passphrase..."
    getPassphrase
    echo -n "$PASS" | cryptsetup luksFormat --cipher aes-xts-plain64 "$DISK"3 -
    echo -n "$PASS" | cryptsetup open --type luks "$DISK"3 lvm
  fi

  VG=vgsystem
  # Create volumes
  pvcreate /dev/mapper/lvm
  vgcreate -v $VG /dev/mapper/lvm

  LVTABFILE=lvtab
  LINE=0
  while read LVLVNAME LVSIZE LVVG MOUNT; do
    if [[ ${LVLVNAME:0:1} == "#" ]]; then
      continue
    fi;
    LINE=$(($LINE+1))
    OPSWITCH=
    echo ""
    if [[ "$LVSIZE" == *"%"* ]]; then
      echo "Setting up LV $LVLVNAME extent to $LVSIZE"
      OPSWITCH=l
    else
      echo "Setting up LV $LVLVNAME to size $LVSIZE"
      OPSWITCH=L
    fi
    echo "Preparing Logical Volume No. $LINE: LVVG=$LVVG LVLVNAME=$LVLVNAME LVSIZE=$LVSIZE"
    lvcreate -"$OPSWITCH" $LVSIZE $LVVG -n $LVLVNAME
  done <$LVTABFILE
fi

# Start Ubiquity
echo "\n"
echo "GUI INSTALLER INSTRUCTIONS"
echo -e "-------------------------\n"
echo "When prompted for \"Installation Type\" select \"Something Else\"."
echo "Then assign each device-mapper volume, click Change and use as EXT4 (except for swapvol which can be used as \"swap area\")."
echo "Assign each volume its respective mount point (eg. homevol to /home, root to / etc.)."
echo -n "Also use "
echo -n "$DISK"
echo "1 as EFI partition."
echo -n "$DISK"
echo "2 as EXT4 and a mount point of /boot."
echo ""
echo "The user you create will be the ADMINISTRATOR of the system."
echo ""
echo "!!! IMPORTANT: When the installer is finished select \"Continue Testing\" so this script can finish up. !!!"
echo ""

confirm "Continue and launch GUI installer now?" $YES
if [ "$CONFIRM" == "$NO" ]; then
  echo "Installer exiting..."
  exit
fi
ubiquity gtk_ui

LVTABFILE=lvtab
LINE=0
echo "Mounting OS's disks using $LVTABFILE file..."
while read LVLVNAME LVSIZE LVVG MOUNT; do
  if [[ ${LVLVNAME:0:1} == "#" ]]; then
    continue
  fi;
  if [[ ${MOUNT:0:1} != "/" ]]; then
    echo "Skipping $MOUNT"
    continue
  fi
  LINE=$(($LINE+1))
  echo "Mounting $LINE: LVLVNAME=$LVLVNAME MOUNT=$MOUNT"
  echo mount /dev/$VG/$LVLVNAME /mnt$MOUNT
done <$LVTABFILE
exit

# Mount everything
#mount /dev/vgsystem/rootvol /mnt
#mount /dev/vgsystem/homevol /mnt/home
echo "Mounting /proc..."
chroot /mnt mount /proc
echo "Mounting /dev..."
mount --bind /dev /mnt/dev
chroot /mnt mount /boot

#if [ "$DOCONFIG" = "y" ]; then
  echo -e "\n\nApplying recommended system settings...\n"

  while [ -z "$ADMINUSER" ]; do read -p "Enter the name of the user you created in the GUI: " ADMINUSER; done

  # Update /etc/fstab
  #echo "none     /tmp     tmpfs     rw,noexec,nosuid,nodev     0     0" >> /mnt/etc/fstab
  #sed -ie '/\s\/home\s/ s/defaults/defaults,noexec,nosuid,nodev/' /mnt/etc/fstab
  #echo "none     /run/shm     tmpfs     rw,noexec,nosuid,nodev     0     0" >> /mnt/etc/fstab

  # Enable automatic updates
  echo "Enable automatic updates"
  echo "APT::Periodic::Update-Package-Lists \"1\";
APT::Periodic::Unattended-Upgrade \"1\";
APT::Periodic::AutocleanInterval \"7\";
" >> /mnt/etc/apt/apt.conf.d/20auto-upgrades
  chmod 644 /mnt/etc/apt/apt.conf.d/20auto-upgrades

  # Prevent standard user executing su
  echo "Prevent standard user executing su"
  chroot /mnt dpkg-statoverride --update --add root adm 4750 /bin/su

  # Disable apport (error reporting)
  echo "Disabling error reporting"
  sed -ie '/^enabled=1$/ s/1/0/' /mnt/etc/default/apport

  # Protect user home directories
  echo "Protecting user home directories"
  sed -ie '/^DIR_MODE=/ s/=[0-9]*\+/=0750/' /mnt/etc/adduser.conf
  sed -ie '/^UMASK\s\+/ s/022/027/' /mnt/etc/login.defs
  chmod 750 /mnt/home/"$ADMINUSER"

  # Disable shell access for new users (not affecting the existing admin user)
  echo "Disagling shell for new users"
  sed -ie '/^SHELL=/ s/=.*\+/=\/usr\/sbin\/nologin/' /mnt/etc/default/useradd
  sed -ie '/^DSHELL=/ s/=.*\+/=\/usr\/sbin\/nologin/' /mnt/etc/adduser.conf

  # Disable guest login
  "Disabling guest login"
  mkdir /mnt/etc/lightdm/lightdm.conf.d
  echo "[SeatDefaults]
allow-guest=false
" > /mnt/etc/lightdm/lightdm.conf.d/50-no-guest.conf

  # A hook to disable online scopes in dash on login
  echo "Disabling Online action in dash on login"
  echo '#!/bin/bash' > /mnt/usr/local/bin/unity-privacy-hook.sh
  echo "gsettings set com.canonical.Unity.Lenses remote-content-search 'none'
gsettings set com.canonical.Unity.Lenses disabled-scopes \"['more_suggestions-amazon.scope', 'more_suggestions-u1ms.scope', 'more_suggestions-populartracks.scope', 'music-musicstore.scope', 'more_suggestions-ebay.scope', 'more_suggestions-ubuntushop.scope', 'more_suggestions-skimlinks.scope']\"
for USER in \`ls -1 /home\`; do
  chown \"\$USER\":\"\$USER\" /home/\"\$USER\"/.*
done
exit 0
" >> /mnt/usr/local/bin/unity-privacy-hook.sh
  chmod 755 /mnt/usr/local/bin/unity-privacy-hook.sh
  echo "[SeatDefaults]
session-setup-script=/usr/local/bin/unity-privacy-hook.sh" > /mnt/etc/lightdm/lightdm.conf.d/20privacy-hook.conf

  # Create standard user
  echo ""
  while [ -z "$ENDUSER" ]; do read -p "Username for primary device user: " ENDUSER; done
  chroot /mnt adduser "$ENDUSER"

  # Fix some permissions in /var that are writable and executable by the standard user
  chmod o-w /mnt/var/crash
  chmod o-w /mnt/var/metrics
  chmod o-w /mnt/var/tmp

  # Fix the lightdm-data subdirectory on the /var partition to avoid it being writable and executable by the standard user
  mkdir /mnt/home/lightdm-data
  chmod 755 /mnt/home/lightdm-data
  mkdir /mnt/home/lightdm-data/"$ENDUSER"
  chroot /mnt chown "$ENDUSER":lightdm /home/lightdm-data/"$ENDUSER"
  chmod 770 /mnt/home/lightdm-data/"$ENDUSER"
  chroot /mnt ln -s /home/lightdm-data/"$ENDUSER" /var/lib/lightdm-data/"$ENDUSER"

  # Set grub password
  echo "Please enter a grub sysadmin passphrase..."
  getPassphrase
  echo "set superusers=\"sysadmin\"" >> /mnt/etc/grub.d/40_custom
  echo -e "$PASS\n$PASS" | grub-mkpasswd-pbkdf2 | tail -n1 | awk -F" " '{print "password_pbkdf2 sysadmin " $7}' >> /mnt/etc/grub.d/40_custom
  sed -ie '/echo "menuentry / s/echo "menuentry /echo "menuentry --unrestricted /' /mnt/etc/grub.d/10_linux
  sed -ie '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/"$/ module.sig_enforce=yes"/' /mnt/etc/default/grub
  echo "GRUB_SAVEDEFAULT=false" >> /mnt/etc/default/grub
  chroot /mnt update-grub
#fi

# Create /etc/crypttab
blkid | grep "$DISK"3 | awk -F"\"" '{print "lvm UUID=" $2, "none luks,discard"}' > /mnt/etc/crypttab
chmod 664 /mnt/etc/crypttab

# Update initramfs
chroot /mnt update-initramfs -u -k all

echo -e "\nINSTALLATION COMPLETE\n"
if [ "$DOCONFIG" = "y" ]; then
  echo "Remember to run the post installation script after rebooting to finalise configuration."
fi
read -p "Reboot now? [y/n]: " CONFIRM
if [ "$CONFIRM" = "y" ]; then
  reboot
fi
