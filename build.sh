#!/bin/bash

# Ensure we're running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root or with sudo!" 
  exit 1
fi

# Variables
BASE_DIR="/archstep"
WORK_DIR="$BASE_DIR/arch-chroot-iso"

CHROOT_DIR="$WORK_DIR/arch-chroot"
ARCH_DIR="$WORK_DIR/arch"
SQUASHFS_DIR="$ARCH_DIR/x86_64"
SQUASHFS_IMG="$SQUASHFS_DIR/airootfs.sfs"
BOOT_DIR="$ARCH_DIR/boot/x86_64"
EFI_DIR="$WORK_DIR/EFI"
EFI_BOOT_DIR="$EFI_DIR/BOOT"
LOADER_DIR="$WORK_DIR/loader"
LOADER_ENTRIES_DIR="$LOADER_DIR/entries"

ESP_DIR="$BASE_DIR/ESP"
ESP_IMG="$ESP_DIR/esp.img"
ESP_MNT="$WORK_DIR/esp"
ESP_BOOT_DIR="$ESP_MNT/arch/boot/x86_64"
ESP_EFI_BOOT_DIR="$ESP_MNT/EFI/BOOT"
ESP_LOADER_DIR="$ESP_MNT/loader"
ESP_LOADER_ENTRIES_DIR="$ESP_LOADER_DIR/entries"

ISO_OUTPUT_DIR="$BASE_DIR/arch-iso-output"
ISO_NAME="arch-chroot.iso"

# Cleanup previous runs
umount "$ESP_MNT"
rm -rf "$BASE_DIR"

# Set up Arch Linux chroot environment
echo "Setting up Arch Linux chroot environment..."

# Create necessary directories
mkdir -p "$CHROOT_DIR"
mkdir -p "$ARCH_DIR"
mkdir -p "$SQUASHFS_DIR"
mkdir -p "$BOOT_DIR"
mkdir -p "$EFI_DIR"
mkdir -p "$EFI_BOOT_DIR"
mkdir -p "$LOADER_DIR"
mkdir -p "$LOADER_ENTRIES_DIR"

mkdir -p "$ESP_DIR"
mkdir -p "$ESP_MNT"

mkdir -p "$ISO_OUTPUT_DIR"

# Bootstrap Arch Linux base system with LTS kernel
pacstrap -c $CHROOT_DIR base base-devel linux-lts zsh mkinitcpio-archiso sudo git xdg-user-dirs nano less \
  gcc-objc clang libjpeg-turbo libtiff libpng libicns imagemagick libxml2 libxslt gnutls libffi \
  icu cairo libxft avahi flite libxt portaudio make cmake openssl freeglut giflib libao \
  xorg-server xorg-xinit xf86-input-libinput xf86-video-intel xf86-video-amdgpu xf86-video-nouveau \
  xfce4-panel xfce4-session xfwm4 xfce4-settings xfce4-terminal xfce4-clipman-plugin neofetch \
  networkmanager network-manager-applet nm-connection-editor net-tools wireless_tools wpa_supplicant \
  gtk2 glib2 gtk-chtheme meson ninja vala glib2-devel gobject-introspection libdbusmenu-gtk2 appmenu-gtk-module \
  chromium sddm scrot ffmpeg

# Copy overlay files for new settings
cp -R overlays/etc/skel/.* "$CHROOT_DIR/etc/skel/"

# Setup .zshrc for Users
cat > "$CHROOT_DIR/etc/skel/.zshrc" <<EOF
# Removing the following line will break Ctrl-A and Ctrl-E
bindkey -e
autoload -U colors
colors
PS1='%{$(tput setaf 105)%}%n%{$(tput setaf 51)%}@%{$(tput setaf 51)%}%m %{$(tput setaf 231)%}%1~ %{$(tput sgr0)%}$ '
alias ls='ls -G'
alias ll='ls -l'
alias la='ls -la'
export EDITOR=nano

setopt NULL_GLOB
for file in /etc/zsh/profile.d/*.zsh; do
  [ -r "$file" ] && source "$file"
done
unsetopt NULL_GLOB

neofetch --ascii_distro macos --disable packages
EOF

# Create a user account
echo "Creating hexley user account for live system"
systemd-nspawn -D "$CHROOT_DIR" \
    bash -c "useradd -m -d /Users/hexley -s /usr/bin/zsh hexley &&
             passwd -d hexley &&
             usermod -aG wheel hexley"

# Create sudoers file for hexley
cat > "$CHROOT_DIR//etc/sudoers.d/00_hexley" <<EOF
hexley ALL=(ALL) ALL
EOF
chmod 440 "$CHROOT_DIR//etc/sudoers.d/00_hexley"

# Enter chroot environment and install AUR packages
echo "Entering chroot environment with systemd-nspawn to install AUR packages..."
systemd-nspawn -D "$CHROOT_DIR" --user=hexley \
    --setenv=USER=hexley --setenv=HOME=/Users/hexley \
    bash -c "cd /Users/hexley &&
             git clone https://aur.archlinux.org/yay.git &&
             cd yay && makepkg -si --noconfirm
             cd .. &&
             rm -rf yay"

# Enter chroot environment and install AUR packages
echo "Entering chroot environment with systemd-nspawn to install AUR packages..."
systemd-nspawn -D "$CHROOT_DIR" --user=hexley \
    --setenv=USER=hexley --setenv=HOME=/Users/hexley \
    bash -c "cd /Users/hexley &&
             yay -S --noconfirm --removemake --needed package-name gconf
             yay -S --noconfirm --removemake --needed package-name adobe-base-14-fonts"

# Install XFCE4 Global Menu Plugin
echo "Installing vala-panel-appmenu..."
systemd-nspawn -D "$CHROOT_DIR" \
    bash -c "git clone https://github.com/rilian-la-te/vala-panel-appmenu.git &&
             cd vala-panel-appmenu &&
             meson -Dxfce=enabled --prefix=/usr Build
             cd Build && ninja && ninja install"

# Install XNUfont
echo "Installing XNUfont..."
systemd-nspawn -D "$CHROOT_DIR" \
    bash -c "git clone https://github.com/vladkorotnev/xnufont.git &&
             cd xnufont &&
             make font &&
             cp Lat15XNU8x16.psf /usr/share/kbd/consolefonts/
             echo "FONT=Lat15XNU8x16" | tee -a /etc/vconsole.conf"

# Install YellowBox
echo "Installing YellowBox..."
systemd-nspawn -D "$CHROOT_DIR" \
    bash -c "ln -s /usr/bin/make /usr/bin/gmake
             git clone https://github.com/yellowbox-os/yellowbox-src.git --recurse-submodules &&
             cd yellowbox-src && make install"

# Install classic theme for XFCE
echo "Installing classic theme for XFCE.."
systemd-nspawn -D "$CHROOT_DIR" \
    bash -c "git clone https://github.com/B00merang-Project/macOS.git
    mv macOS /usr/share/themes"

# Cleanup git repos
echo "Cleanup git repos..."
systemd-nspawn -D "$CHROOT_DIR" \
    bash -c "rm -rf /xnufont
             rm -rf /yellowbox-src
             rm -rf /macOS
             rm -rf /vala-panel-appmenu"

# Enter chroot environment and configure system
echo "Entering chroot environment with systemd-nspawn..."
systemd-nspawn -D "$CHROOT_DIR" \
    bash -c "ln -sf /usr/share/zoneinfo/UTC /etc/localtime &&
             echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen &&
             locale-gen &&
             echo 'LANG=en_US.UTF-8' > /etc/locale.conf &&
             export LANG=en_US.UTF-8 &&
             echo 'yellowbox' > /etc/hostname"

# Enable services
echo "Enabling services in chroot environment with systemd-nspawn..."
systemd-nspawn -D "$CHROOT_DIR" \
    bash -c "systemctl enable NetworkManager
             systemctl enable sddm"

# Create XDG session for YellowBox
echo "Create XDG session..."
cat > "$CHROOT_DIR/usr/share/xsessions/yellowbox.desktop" <<EOF
[Desktop Entry]
Name=YellowBox
Comment=This session logs you into YellowBox
Exec=/System/Library/Scripts/YellowBox-X11
TryExec=/System/Library/Scripts/YellowBox-X11
Type=Application
EOF

# Configure SDDM autologin for YellowBox
echo "Configure SDDM autologin..."
mkdir "$CHROOT_DIR/etc/sddm.conf.d"
cat > "$CHROOT_DIR/etc/sddm.conf.d/autologin.conf" <<EOF
[Autologin]
User=hexley
Session=yellowbox
EOF

# Recreate linux-lts.preset for archiso.conf
echo "Recreating linux-lts.preset"
cat > "$CHROOT_DIR/etc/mkinitcpio.d/linux-lts.preset" <<EOF
# mkinitcpio preset file for the 'linux-lts' package on archiso

PRESETS=('archiso')

ALL_kver='/boot/vmlinuz-linux-lts'
archiso_config='/etc/mkinitcpio.conf.d/archiso.conf'

archiso_image="/boot/initramfs-linux-lts.img"
EOF

# Create archiso.conf for mkinitcpio
echo "Updating /etc/mkinitcpio.conf..."
cat > "$CHROOT_DIR/etc/mkinitcpio.conf.d/archiso.conf" <<EOF
HOOKS=(base udev microcode modconf kms archiso archiso_loop_mnt block filesystems keyboard)
COMPRESSION="xz"
COMPRESSION_OPTIONS=(-9e)
EOF

# Generate the initramfs for the LTS kernel
echo "Generating initramfs for LTS kernel..."
systemd-nspawn -D "$CHROOT_DIR" mkinitcpio -c /etc/mkinitcpio.conf.d/archiso.conf -p linux-lts

# Create a SquashFS image of the chroot environment
echo "Creating SquashFS image of the chroot environment..."
mksquashfs "$CHROOT_DIR" "$SQUASHFS_IMG" -b 1M -comp xz

# Set up the boot directory structure for BIOS and UEFI
echo "Setting up systemd-boot and kernel..."

# Create systemd-boot entries
cat > "$LOADER_ENTRIES_DIR/arch-live.conf" <<EOF
title   Arch Linux Live
linux   /arch/boot/x86_64/vmlinuz-linux-lts
initrd  /arch/boot/x86_64/initramfs-linux-lts.img
options  archisobasedir=arch archisosearchfilename=/boot/2025-03-01-17-40-22-00.uuid
EOF

cat > "$LOADER_DIR/loader.conf" <<EOF
default arch-live.conf
timeout 5
EOF

# This may not be needed but testing
mkdir "$WORK_DIR/boot"
touch "$WORK_DIR/boot/2025-03-01-17-40-22-00.uuid"

# Copy boot file
cp "$CHROOT_DIR/usr/lib/systemd/boot/efi/systemd-bootx64.efi" "$EFI_BOOT_DIR/BOOTx64.EFI"

# Copy kernel files
cp "$CHROOT_DIR/boot/vmlinuz-linux-lts" "$BOOT_DIR/vmlinuz-linux-lts"
cp "$CHROOT_DIR/boot/initramfs-linux-lts.img" "$BOOT_DIR/initramfs-linux-lts.img"

# Create the FAT32 image for the EFI System Partition (ESP)
echo "Creating FAT32 image for EFI partition..."
dd if=/dev/zero of="$ESP_IMG" bs=1M count=100  # Create a 100MB FAT32 partition image
mkfs.fat -F32 "$ESP_IMG"  # Format the image as FAT32

# Mount the FAT32 image to copy systemd-boot files into it
mount "$ESP_IMG" "$ESP_MNT"
mkdir -p "$ESP_BOOT_DIR"
mkdir -p "$ESP_EFI_BOOT_DIR"
mkdir -p "$ESP_LOADER_DIR"
mkdir -p "$ESP_LOADER_ENTRIES_DIR"

cp -R "$LOADER_DIR"/* "$ESP_LOADER_DIR"
cp -R "$EFI_BOOT_DIR"/* "$ESP_EFI_BOOT_DIR"
cp -R "$BOOT_DIR"/* "$ESP_BOOT_DIR"

# Unmount the ESP image
echo "Unmounting ESP image..."
umount "$ESP_MNT"

# Cleanup before making ISO
rm -rf "$ESP_MNT"
rm -rf "$CHROOT_DIR"

cp "$ESP_IMG" "$WORK_DIR/boot"

# Create the ISO using xorriso
echo "Building ISO..."
xorriso -as mkisofs -o "$ISO_OUTPUT_DIR/$ISO_NAME" \
  -iso-level 3 \
  -full-iso9660-filenames \
  -joliet \
  -joliet-long \
  -rational-rock \
  -volid "YELLOWBOX" \
  -appid "YellowBox Live/Rescue DVD" \
  -publisher "pkgdemon" \
  -preparer "prepared by pkgdemon" \
  -e boot/esp.img \
  -no-emul-boot \
  -append_partition 2 0xef "$ESP_IMG" \
  -partition_cyl_align all \
  -isohybrid-gpt-basdat \
  "$WORK_DIR"

echo "ISO built at: $ISO_OUTPUT_DIR/$ISO_NAME"
