#!/bin/sh
#
# Simple script to upgrade Libreswan on CentOS and RHEL
#
# Copyright (C) 2015 Lin Song
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

SWAN_VER=3.16

if [ ! -f /etc/redhat-release ]; then
  echo "Looks like you aren't running this script on a CentOS/RHEL system."
  exit 1
fi

if grep -qs -v -e "release 6" -e "release 7" /etc/redhat-release; then
  echo "Sorry, this script only supports versions 6 and 7 of CentOS/RHEL."
  exit 1
fi

if [ "$(uname -m)" != "x86_64" ]; then
  echo "Sorry, this script only supports 64-bit CentOS/RHEL."
  exit 1
fi

if [ "$(id -u)" != 0 ]; then
  echo "Sorry, you need to run this script as root."
  exit 1
fi

ipsec --version 2>/dev/null | grep -qs "Libreswan"
if [ "$?" != "0" ]; then
  echo "This upgrade script requires that you already have Libreswan installed."
  echo "Aborting."
  exit 1
fi

ipsec --version 2>/dev/null | grep -qs "Libreswan ${SWAN_VER}"
if [ "$?" = "0" ]; then
  echo "You already have Libreswan ${SWAN_VER} installed! "
  echo
  read -r -p "Do you wish to continue anyway? [y/N] " response
  case $response in
    [yY][eE][sS]|[yY])
      echo
      ;;
    *)
      echo "Aborting."
      exit 1
      ;;
  esac
fi

echo "Welcome! This upgrade script will build and install Libreswan ${SWAN_VER} on your server."
echo "This is intended for use on VPN servers with an older version of Libreswan installed."
echo "Your existing VPN configuration files will NOT be modified."

echo
read -r -p "Do you wish to continue? [y/N] " response
case $response in
  [yY][eE][sS]|[yY])
    echo
    echo "Please be patient. Setup is continuing..."
    echo
    ;;
  *)
    echo "Aborting."
    exit 1
    ;;
esac

# Create and change to working dir
mkdir -p /opt/src
cd /opt/src || { echo "Failed to change working directory to /opt/src. Aborting."; exit 1; }

# Install wget and nano
yum -y install wget nano

# Add the EPEL repository
if grep -qs "release 6" /etc/redhat-release; then
  EPEL_RPM="epel-release-6-8.noarch.rpm"
  EPEL_URL="http://download.fedoraproject.org/pub/epel/6/x86_64/$EPEL_RPM"
elif grep -qs "release 7" /etc/redhat-release; then
  EPEL_RPM="epel-release-7-5.noarch.rpm"
  EPEL_URL="http://download.fedoraproject.org/pub/epel/7/x86_64/e/$EPEL_RPM"
else
  echo "Sorry, this script only supports versions 6 and 7 of CentOS/RHEL."
  exit 1
fi
wget -t 3 -T 30 -nv -O $EPEL_RPM $EPEL_URL
[ ! -f $EPEL_RPM ] && { echo "Could not retrieve EPEL repository RPM file. Aborting."; exit 1; }
rpm -ivh --force $EPEL_RPM && /bin/rm -f $EPEL_RPM

# Install necessary packages
yum -y install nss-devel nspr-devel pkgconfig pam-devel \
    libcap-ng-devel libselinux-devel \
    curl-devel gmp-devel flex bison gcc make \
    fipscheck-devel unbound-devel gmp gmp-devel xmlto
yum -y install ppp xl2tpd

# Installed Libevent 2. Use backported version for CentOS 6.
if grep -qs "release 6" /etc/redhat-release; then
  LE2_URL="https://people.redhat.com/pwouters/libreswan-rhel6"
  RPM1="libevent2-2.0.21-1.el6.x86_64.rpm"
  RPM2="libevent2-devel-2.0.21-1.el6.x86_64.rpm"
  wget -t 3 -T 30 -nv -O $RPM1 $LE2_URL/$RPM1
  wget -t 3 -T 30 -nv -O $RPM2 $LE2_URL/$RPM2
  [ ! -f $RPM1 ] || [ ! -f $RPM2 ] && { echo "Could not retrieve Libevent2 RPM file(s). Aborting."; exit 1; }
  rpm -ivh --force $RPM1 $RPM2 && /bin/rm -f $RPM1 $RPM2
elif grep -qs "release 7" /etc/redhat-release; then
  yum -y install libevent-devel
fi

# Compile and install Libreswan (https://libreswan.org/)
SWAN_URL=https://download.libreswan.org/libreswan-${SWAN_VER}.tar.gz
/bin/rm -rf "/opt/src/libreswan-${SWAN_VER}"
wget -t 3 -T 30 -qO- $SWAN_URL | tar xvz
[ ! -d libreswan-${SWAN_VER} ] && { echo "Could not retrieve Libreswan source files. Aborting."; exit 1; }
cd libreswan-${SWAN_VER}
make programs && make install

ipsec --version 2>/dev/null | grep -qs "Libreswan ${SWAN_VER}"
if [ "$?" != "0" ]; then
  echo
  echo "Sorry, something went wrong."
  echo "Libreswan ${SWAN_VER} was NOT installed successfully."
  echo "Exiting script."
  exit 1
fi

# Restore SELinux contexts
restorecon /etc/ipsec.d/*db 2>/dev/null
restorecon /usr/local/sbin -Rv 2>/dev/null
restorecon /usr/local/libexec/ipsec -Rv 2>/dev/null

service ipsec restart
service xl2tpd restart

echo
echo "Congratulations! Libreswan ${SWAN_VER} was installed successfully!"

exit 0
