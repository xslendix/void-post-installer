#!/bin/sh

# Install script inspired by Luke Smith's LARBS install script.

#repo="https://git.xslendi.xyz/xSlendiX/void-post-installer"
repo="https://github.com/xslendix/void-post-installer"
#gitraw="$repo/raw/branch/master"
gitraw="https://raw.githubusercontent.com/xslendix/void-port-installer/master"
prfile="programs.csv"
#dotfiles_repo="https://git.xslendi.xyz/xSlendiX/dotfiles.git"
dotfiles_repo="https://github.com/xslendix/dotfiles.git"

pkginstall() { xbps-install -Sy "$1" | tee -a install_log.txt ;}
pipinstall() { pip3 install "$1" | tee -a install_log.txt ;}
gitinstall() { \
	pname="$(basename "$1".git)"
	srcdir="$repodir/$pname"
	echo " :: Installing $pname in $repodir (git/make)"
	sudo -u "$username" git clone --depth 1 "$1" "$srcdir"
	cd "$srcdir" || error "Could not change directory to $srcdir during installation of $pname!"
	sudo -u "$username" make
	make install
	cd /tmp || error "FATAL: Could not change directory to /tmp! Base installation may be broken!"
	}
gitinstall2() { \
	pname="$(basename "$1".git)"
	srcdir="$repodir/$pname"
	echo " :: Installing $pname in $repodir (git/make)"
	sudo -u "$username" git clone --depth 1 "$1" "$srcdir"
	cd "$srcdir" || error "Could not change directory to $srcdir during installation of $pname!"
	sudo -u "$username" ./autogen.sh
	sudo -u "$username" ./configure
	sudo -u "$username" make
	make install
	cd /tmp || error "FATAL: Could not change directory to /tmp! Base installation may be broken!"
	}
error() { printf " :: An error occured during install!\\n\\t%s\\n" "$1"; exit 1; }

firstmsg() { \
	echo "Welcome to xSlendiX's ricing script!"
	echo ""
	echo "This will install all my config files to your system. The script was"
	echo "designed to work on fresh Void Linux installations. Other distributions"
	echo -e "are currently not supported. NOT TESTED ON MUSL!"
	echo ""
	DISTRO=$(cat /etc/*-release | grep ^NAME | awk -F\" '{print $2}')
	echo " :: Detected Linux distribution: $DISTRO"
	[ "$DISTRO" = "void" ] && echo "Ready to install." || echo "Distribution $DISTRO not supported."

	while true; do
		printf "Are you sure you want to continue? [y/n]"
		read yn
		case $yn in
			[Yy]* ) break;;
			[Nn]* ) echo " :: Instalation canceled."; exit;;
			* ) echo "Please enter a valid answer"
		esac
	done
	}

askuser() { \
	while true; do
		printf "Please provide the user account's username: "
		read username
		if getent passwd "$username" > /dev/null 2>&1; then
			echo " :: User $username found!"
			break
		else
			echo " :: User $username doesn't exist!"
		fi
	done
	repodir="/home/$username/.local/src"
	sudo -u $username mkdir -p /home/$username/.local/src
	}

installdeps() { \
	echo " :: Installing required dependencies..."
	xbps-install -Syu xtools git python3 python3-pip base-devel
	}

installloop() { \
	([ -f "$prfile" ] && cp "$prfile" /tmp/prfile.csv) || curl -Ls $gitraw/$prfile | sed '/^;/d' > /tmp/prfile.csv
	total=$(wc -l /tmp/prfile.csv)
	echo " :: Total packages to be installed: $total"
	while IFS=, read -r type package comment; do
		n=$((n+1))
		echo " :: Installing package nr. $n: $package"
		echo "$comment" | grep -q "^\".*\"$" && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		case "$type" in
			"P") pipinstall "$package" ;;
			"G") gitinstall "$package" ;;
			"C") gitinstall2 "$package" ;;
			*) pkginstall "$package" ;;
		esac
	done < /tmp/prfile.csv
	}

setupservices() { \
	echo " :: Setting up startup services"
	ln -sf /etc/sv/acpid /var/service
	ln -sf /etc/sv/dbus /var/service
	ln -sf /etc/sv/cronie /var/service
	ln -sf /etc/sv/NetworkManager /var/service
	ln -sf /etc/sv/udevd /var/service
	rm -rf /var/service/dhcpcd
	rm -rf /var/service/wpa_supplicant
	}

finalize() { \
	echo " :: Finished installation!"
	echo "All done! Enjoy your new system and thanks for using my rice!"
	echo "Please note, however that stuff like system time and video"
	echo "drivers have not yet been set up. You need to do this yourself."
	}

if [ $(id -u) -ne 0 ] ; then echo " :: Please run the installer as root." ; exit 1 ; fi
#case "$(curl -s --max-time 2 -I http://google.com | sed 's/^[^ ]*  *\([0-9]\).*/\1/; 1q')" in
	#[23]) echo " :: HTTP connectivity is up" ;;
	#5) echo " :: The web proxy won't let us through"; exit ;;
	#*) echo " :: The network is down or very slow"; exit ;;
#esac

firstmsg
askuser
installdeps
echo " :: Configuring makepkg.conf"
echo "MAKEFLAGS=\"-j$(nproc)\"" > /etc/makepkg.conf
installloop

echo " :: Installing dotfiles"
cd /tmp
sudo -u "$username" git clone --depth 1 $dotfiles_repo
cd /tmp/$(basename "$dotfiles_repo".git)
sudo -u "$username" mv -vf .* "/home/$username/."
sudo -u "$username" mv -vf * "/home/$username/."

echo " :: Blacklisting annoying PC Speaker"
rmmod pcspkr
echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf

echo " :: Changing default shell for $username to zsh."
chsh -s /bin/zsh "$username"
sudo -u "$username" mkdir -p "/home/$username/.cache/zsh"

echo " :: Enabling tap to click if touchpad is available"
[ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
        Identifier "libinput touchpad catchall"
        MatchIsTouchpad "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
	# Enable left mouse button by tapping
	Option "Tapping" "on"
EndSection' > /etc/X11/xorg.conf.d/40-libinput.conf

echo " :: Restarting PulseAudio"
killall pulseaudio; sudo -u "$username" pulseaudio --start

echo " :: Enabling commands to be ran as root without entering password"
echo "%wheel ALL=(ALL) NOPASSWD: /bin/shutdown,/bin/reboot,/bin/init,/bin/mount,/bin/umount,/bin/sv restart NetworkManager,/bin/xi,/bin/xbps-install" >> /etc/sudoers

finalize

