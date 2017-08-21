!/bin/bash

exec >  >(tee -a silkinstall.log)
exec 2> >(tee -a silkinstall.log >&2)

silk_ver=$(echo "silk-3.15.0")
libf_ver=$(echo "libfixbuf-1.7.1")

#Set interface variable
echo "$(tput setaf 3)Which interface do you wish to monitor?"
cd /sys/class/net && select interface in *; do
        if [ "$interface" = "" ]; then
                echo  "$(tput setaf 1)You didn't pick an interface. Pick a number from the list.$(tput setaf 3)"
        else
                break
        fi
done
echo "You will be monitoring the $interface interface.$(tput sgr0)"

# Configure to start rwflowpack on boot
#
sudo sed -i '/\/usr\/local\/sbin\/rwflowpack/ d' /etc/rc.local
sudo sed -i '$ s,exit 0,/usr/local/sbin/rwflowpack --compression-method=best --sensor-configuration=/data/sensors.conf --site-config-file=/data/silk.conf --output-mode=local-storage --root-directory=/data/ --pidfile=/var/log/rwflowpack.pid --log-level=debug --log-directory=/var/log --log-basename=rwflowpack\nexit 0,' /etc/rc.local

# Prepare for Install... on User's directory
#
cd ~
sudo apt-get update -yy
sudo dpkg --configure -a

# Install Prerequisites
#
echo -e "$(tput setaf 6)Installing Prerequisites. This might require your password and take a few minutes.$(tput sgr0)"

for a in glib2.0 libglib2.0-dev libpcap-dev g++ python-dev make gcc; do
     echo -e "$(tput setaf 6)Installing $a .... Please wait .... $(tput sgr0)"
     sudo apt-get -qq -y install $a
     echo $a has been installed
     echo
done

# --- start of function ---
function install_apps {
echo
echo
echo -e "$(tput setaf 6)Building $1 $(tput sgr0)"
  cd ~
  if [ ! -f $1 ]; then wget http://tools.netsa.cert.org/releases/$1.tar.gz; fi
  tar zxf $1.tar.gz
  rm ./$1.tar.gz
  cd ./$1/
  export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
  ./configure $2
  make
  sudo make install
}
# --- end of function ---

apps=$(echo "$libf_ver")
apps_config=$(echo "")
install_apps $apps $apps_config

apps=$(echo "$silk_ver")
apps_config=$(echo "--with-libfixbuf=/usr/local/lib/pkgconfig/ --with-python")
install_apps $apps $apps_config

# Configure SiLk
sudo mkdir /data
cat > silk.conf << "EOF"
        /usr/local/lib
        /usr/local/lib/silk
EOF
sudo mv silk.conf /etc/ld.so.conf.d/

sudo ldconfig
cat ./site/twoway/silk.conf | \
        sed 's/sensor 0 .*$/sensor 0 NRyde-vcs101/' | \
        sed 's/sensor 1 .*$/sensor 1 Homebush-vcs102/' | \
        sed 's/sensor 2 .*$/sensor 2 NextDC-vcs103/' | \
        sed 's/sensor 3 .*$/sensor 3 Equinix-vcs104/' | \
        sed 's/sensors S0 S1.*$/sensors Brocade-vcs101 homebush nthryde nthryde2/' \
        >> silk.conf
sudo mv -f silk.conf /data/

# configure sensors.conf
#
cat > sensors.conf << "EOF"
probe NRyde-vcs101 sflow
        listen-on-port 6343
        protocol udp
        accept-from-host 192.168.100.11
end probe

probe Homebush-vcs102 sflow
        listen-on-port 6343
        protocol udp
        accept-from-host 192.168.100.21
end probe

probe NextDC-vcs103 sflow
        listen-on-port 6343
        protocol udp
        accept-from-host 192.168.100.31
end probe

probe Equinix-vcs104 sflow
        listen-on-port 6343
        protocol udp
        accept-from-host 192.168.100.41
end probe

group ICO-Subnets
        ipblocks 119.161.32.0/21
        ipblocks 119.161.40.0/21
        ipblocks 202.191.48.0/21
        ipblocks 203.22.107.0/24
end group

sensor NRyde-vcs101
        sflow-probes NRyde-vcs101
        internal-ipblocks @ICO-Subnets
        external-ipblocks remainder
end sensor

sensor Homebush-vcs102
        ipfix-probes Homebush-vcs102
        internal-ipblocks @ICO-Subnets
        external-ipblocks remainder
end sensor

sensor NextDC-vcs103
        ipfix-probes NextDC-vcs103
        internal-ipblocks @ICO-Subnets
        external-ipblocks remainder
end sensor

sensor Equinix-vcs104
        ipfix-probes Equinix-vcs104
        internal-ipblocks @ICO-Subnets
        external-ipblocks remainder
end sensor

EOF

sudo mv sensors.conf /data/

# Configure rwflowpack.conf
#
cat /usr/local/share/silk/etc/rwflowpack.conf | \
        sed 's/ENABLED=/ENABLED=yes/;' | \
        sed 's/SENSOR_CONFIG=/SENSOR_CONFIG=\/data\/sensors.conf/;' | \
        sed 's/SITE_CONFIG=/SITE_CONFIG=\/data\/silk.conf/' | \
        sed 's/LOG_TYPE=syslog/LOG_TYPE=legacy/' | \
        sed 's/LOG_DIR=.*/LOG_DIR=\/var\/log/' | \
        sed 's/CREATE_DIRECTORIES=.*/CREATE_DIRECTORIES=yes/' \
        >> rwflowpack.conf
sudo mv rwflowpack.conf /usr/local/etc/

# Download country code database - These can be updated as needed via the commands below
#
wget http://geolite.maxmind.com/download/geoip/database/GeoLiteCountry/GeoIP.dat.gz
gzip -d -c GeoIP.dat.gz | rwgeoip2ccmap --encoded-input > country_codes.pmap
sudo mv country_codes.pmap /usr/local/share/silk/

# Start up services
#
sudo /usr/local/sbin/rwflowpack --compression-method=best \
     --sensor-configuration=/data/sensors.conf \
     --site-config-file=/data/silk.conf \
     --output-mode=local-storage --root-directory=/data/ \
     --pidfile=/var/log/rwflowpack.pid --log-level=info \
     --log-directory=/var/log --log-basename=rwflowpack

echo
ps -ef | grep rwflowpack
echo

# sudo apt-get -y purge glib2.0 libglib2.0-dev libpcap-dev g++ python-dev make gcc
exit 0
