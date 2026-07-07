--------------------------
#ifconfig missing
sudo apt install net-tools
sudo apt install python3.14-venv
sudo apt install newgrp
sudo apt update
sudo apt install -y mysql-server
--------------------------
#scaling issue:
gsettings set org.gnome.desktop.interface scaling-factor 2
gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer']"
-------------------------
#static ip
nano /etc/netplan/*.yaml

network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ens33:
      dhcp4: no
      addresses:
        - 192.168.1.99/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [192.168.1.1, 8.8.8.8]
------------------------------
#ssh
apt update
apt install openssh-server
------------------------------
#konstantinos as root
visudo
konstantinos ALL=(ALL) NOPASSWD: ALL
nano /home/konstantinos/.bashrc
sudo -s #add it on top 
--------------------------------
#god mode
# 1. Set root password
sudo passwd root
# 2. Allow root in GDM
sudo nano /etc/gdm3/custom.conf
[Security]
AllowRoot=true
# 3. Allow root in AccountsService
sudo nano /var/lib/AccountsService/users/root
[User]
SystemAccount=false
# 4. Disable PAM restriction
sudo nano /etc/pam.d/gdm-password
sudo nano /etc/pam.d/gdm-autologin
#auth required pam_succeed_if.so user != root quiet_success
--------------------------------
#root sound - chatgpt
apt install pulseaudio-utils
pactl info
xhost +SI:localuser:root
export PULSE_SERVER=unix:/run/user/1000/pulse/native
export XDG_RUNTIME_DIR=/run/user/1000
export PULSE_SERVER=unix:/run/user/1000/pulse/native
--------------------------------
#root sound - claude
#1. Create PipeWire override dirs:
mkdir -p /etc/systemd/user/pipewire.service.d
mkdir -p /etc/systemd/user/pipewire-pulse.service.d
mkdir -p /etc/systemd/user/wireplumber.service.d
#2. Clear the ConditionUser=!root restriction:
echo -e "[Unit]\nConditionUser=" | tee /etc/systemd/user/pipewire.service.d/override.conf
echo -e "[Unit]\nConditionUser=" | tee /etc/systemd/user/pipewire-pulse.service.d/override.conf
echo -e "[Unit]\nConditionUser=" | tee /etc/systemd/user/wireplumber.service.d/override.conf
#3. Reload and restart:
systemctl --user daemon-reload
systemctl --user restart pipewire pipewire-pulse wireplumber