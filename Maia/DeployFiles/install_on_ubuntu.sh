#!/bin/bash

# Update package lists
sudo apt update

# Install kwin-x11

# Ubuntu 24.04
sudo apt install --no-install-recommends --no-install-suggests kwin-x11  #kwin
# kwin aurorae engine libraries
sudo apt install --no-install-recommends --no-install-suggests kwin-common
# kwin aurorae qml-s data files
sudo apt install --no-install-recommends --no-install-suggests kwin-data
sudo apt install --no-install-recommends --no-install-suggests kwin-addons

# Ubuntu 24.10
# additional dependiences for kwin
sudo apt install libkf5globalaccel-bin breeze libkf5kcmutils5


# INSTALL MAIA

# Remove existing Maia directory if it exists
sudo rm -v -r "/opt/Maia/Maia_0.1.0"

# Create /opt/Maia dir
sudo mkdir -p "/opt/Maia"

# Copy "Maia_version to /opt/Maia/Maia_version
sudo cp -v -r "$(dirname "$0")/Maia_0.1.0" "/opt/Maia/Maia_0.1.0"

# Set executable permissions for specific scripts
sudo chmod +x "/opt/Maia/Maia_0.1.0/bin/run.sh"
sudo chmod +x "/opt/Maia/Maia_0.1.0/bin/run_logger.sh"
sudo chmod +x "/opt/Maia/Maia_0.1.0/bin/run_maia_in_xephyr.sh"

# Set read, write, and execute permissions for all users on the Maia directory and its contents
# sudo chmod -R 777 "/opt/Maia"

# Copy maia_version-desktop.desktop file to /usr/share/xsessions
sudo cp -v "$(dirname "$0")/Maia_0.1.0/bin/maia_0.1.0-desktop.desktop" "/usr/share/xsessions/"






## Check for available updates (equivalent to apt update)
#sudo dnf check-update
## Install KWin packages without weak dependencies
#sudo dnf install --setopt=install_weak_deps=False kwin-x11
#sudo dnf install --setopt=install_weak_deps=False kwin-common
## sudo dnf install --setopt=install_weak_deps=False kwin-data - unavailable
## sudo dnf install --setopt=install_weak_deps=False kwin-addons - unavailable


