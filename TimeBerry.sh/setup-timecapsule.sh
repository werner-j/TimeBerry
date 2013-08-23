#!/bin/bash
#
# TimeBerry v0.5
# Script to setup TimeCapsule on Raspberry Pi and similar systems
#

DISKNAME=TimeCapsule
TCFOLDER=/media/TimeCapsule

clear

tput setaf 7
tput setab 1
echo "                      "
printf " Welcome to TimeBerry "
tput sgr0
echo "   Setup Script for Timecapsule on Raspberry Pi like systems."
tput setaf 7
tput setab 1
echo "                      "
tput sgr0
echo

if [ -f /etc/init.d/netatalk ]; then
	service netatalk stop
fi
if [ -f /etc/init.d/avahi-daemon ]; then
	service avahi-daemon stop
fi

echo ""

tput setaf 3
printf "Looking for HFS+ support in /proc/filesystems... "
tput sgr0
if [[ `cat /proc/filesystems | grep -i hfsplus | wc -l` != 1 ]]; then
	echo "HFS+ not available. Please upgrade your kernel. Exiting..."
	exit 130
else
	echo "HFS+ found in /proc. Good."
fi

echo ""

tput setaf 3
echo "Update package sources, refresh installation and install necessary packages..."
tput sgr0

echo ""
printf "This may take a while. Processing: "
if [ "$1" == "noupgrade" ]; then
	printf "Skipping upgrade. "
else
	printf "Update source lists. "
	apt-get -qq update
	printf "Upgrade system. "
	apt-get --yes -qqq upgrade
fi
printf "Install packages. "
apt-get --yes -qqq install parted hfsplus hfsprogs hfsutils
if [ $? -eq 0 ]; then
	echo "SUCCESS!"
else
	echo "FAIL! Aborting..."
	exit $?
fi

dpkg-reconfigure tzdata

echo ""
printf "Check for timecapsule user and create it if necessary... "
if id -u timecapsule >/dev/null 2>&1; then
        echo "user exists."
else
        echo "user does not exist. Creating."
	groupadd apple
	useradd -g apple -m -s /bin/false timecapsule
	printf "New user 'timecapsule' needs a password. This user will be used to connect to your TimeBerry. "
	passwd timecapsule
fi

echo ""
umount -l $TCFOLDER
echo ""

tput setaf 3
printf "Setup filesystem infrastructure..."
tput sgr0

mkdir -p /media/TimeCapsule
printf " Directories."
chmod -R 777 /media/TimeCapsule
printf " Permissions."
chown -R timecapsule:apple /media/TimeCapsule
echo " Ownership."

echo ""

DISKS=""
echo "Available block devices on this system: "
for disk in `parted -s -l | grep -i "Disk /" | awk '{ print $2; }'`; do
	DISK="$DISK ${disk%?}"
done

for disk in $DISK
do
	printf "%s\t%s\n" "$disk" "`parted -s -m -l | grep -i "$disk" | awk -F':' '{ print $2; }'`"
done

blk=""
FOUND=0
while [[ $FOUND == 0 ]]; do
	echo ""
	tput setaf 7
	tput bold
	printf "Please input the device node of your backup disk: /dev/"
	tput sgr0
	read blk

	blk="/dev/$blk"

	for disk in $DISK; do
		if [ "$disk" == "$blk" ]; then
			FOUND=1
		fi
	done

	echo ""
	if [ "$FOUND" != "1" ]; then
		tput setaf 1
		tput bold
		echo "Device $blk does not exist!"
		tput sgr0
	fi
done

confirm=
while [[ $confirm == "" ]]; do
	echo "Are you sure, you want to use $blk as backup disk?"
	tput bold
	printf "If you type 'yes', this will ERASE ALL DATA on $blk: "
	tput setaf 2
	read confirm
	tput sgr0
	echo ""
done

if [ $confirm == "yes" ]; then
	echo "ERASE";
else
	exit 0;
fi

tput setaf 3
printf "Create new GPT on $blk..."
parted -s $blk mklabel gpt
sync
sleep 2
sync
if [ $? -eq 0 ]; then
	tput setaf 2
	echo " OK."
else
	tput setaf 1
	echo " FAIL!"
	exit 1
fi
tput sgr0

part="$blk""1"
tput setaf 3
printf "Create partition $part on $blk..."
parted -s $blk unit % mkpart primary 0 100
sync
sleep 2
sync
if [ $? -eq 0 ]; then
        tput setaf 2
        echo " OK."
else
        tput setaf 1
        echo " FAIL!"
        exit 1
fi
tput sgr0

parted -s $blk print

tput setaf 3
echo "Formatting $part TimeCapsule on $blk..."
tput sgr0
mkfs.hfsplus -v TimeCapsule $part
echo ""
fsck.hfsplus -fry $part
if [ $? -eq 0 ]; then
	echo "Disk prepared successfully!"
else
	echo "Disk could not be prepared. Exiting..."
	exit $?
fi

echo ""
tput setaf 3
printf "Writing entry to /etc/fstab... "
cp /etc/fstab /etc/fstab~
lines=`cat /etc/fstab | grep -i TimeCapsule | wc -l`
if [ $lines -gt 0 ]; then
	echo "Remove existing entry from /etc/fstab... "
	sed '/TimeCapsule/d' /etc/fstab > /tmp/fstab
	mv /tmp/fstab /etc/fstab
fi
tput sgr0
printf "%s\t%s\t%s\t%s\t%d %d\n" "$part" "$TCFOLDER" "hfsplus" "defaults" 0 2 >> /etc/fstab
cat /etc/fstab
echo ""
sleep 2

mount $TCFOLDER

CURDIR=`pwd -P`
printf "Install Netatalk... "
apt-get --yes -q install build-essential avahi-daemon libavahi-client-dev libdb5.1-dev db-util db5.1-util bzip2 libgcrypt11 libgcrypt11-dev
if [ -f /usr/local/etc/afp.conf ]; then
	tput setaf 3
	echo ""
	printf "Netatalk seems installed! Type 'yes' for reinstall: "
	tput sgr0
	read reinst
fi

if [[ "$reinst" == "" ]]; then
	reinst="no"
fi

if [ ! -f /usr/local/etc/afp.conf ] || [ $reinst = "yes" ]; then
	cd /tmp
	rm -rf netatalk-*
	wget http://downloads.sourceforge.net/project/netatalk/netatalk/3.0.5/netatalk-3.0.5.tar.bz2
	tar -xvf netatalk-3.0.5.tar.bz2
	cd netatalk-3.0.5/
	./configure --with-init-style=debian --with-zeroconf
	make
	sudo make install
	cd $CURDIR
fi

tput setaf 3
printf "Setup Netatalk and restart services... "
tput sgr0
cp afp.conf /usr/local/etc/afp.conf
cp timecapsule_afpd.service /etc/avahi/services/timecapsule_afpd.service
tput setaf 2
echo "DONE"
tput sgr0

update-rc.d netatalk defaults

echo ""

service netatalk restart
service avahi-daemon restart

clear

tput setaf 7
tput setab 1
echo "                      "
printf " Welcome to TimeBerry "
tput sgr0
echo "   Setup Script for Timecapsule on Raspberry Pi like systems."
tput setaf 7
tput setab 1
echo "                      "
tput sgr0

echo ""
tput setaf 2
tput bold
echo "Congratulations!"
echo ""
echo "It seems that you have successfully installed TimeBerry on your device. You may now"
echo "use it on your Mac as a TimeCapsule. Look in Finder's remote shares for TimeBerry."
echo ""
echo "To log-in, use the user 'timecapsule' with the password you provided before."
echo "Have a lot of fun! ;)"
tput sgr0

echo ""
