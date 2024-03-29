#!/bin/bash

TMP_FOLDER=$(mktemp -d)
CONFIG_FILE='buntu.conf'
CONFIGFOLDER='/root/.buntu'
COIN_DAEMON='buntud'
COIN_CLI='buntud'
COIN_PATH='/usr/local/bin/'
COIN_REPO='https://github.com/CRYPT0BUNTU/Buntu.git'
COIN_TGZ='https://github.com/CRYPT0BUNTU/Buntu/releases/download/1.2/buntud2004.tar.gz'
COIN_BOOTSTRAP=''
COIN_ZIP=$(echo $COIN_TGZ | awk -F'/' '{print $NF}')
COIN_CHAIN=$(echo $COIN_BOOTSTRAP | awk -F'/' '{print $NF}')
SENTINEL_REPO='N/A'
COIN_NAME='buntu'
COIN_PORT=32821
RPC_PORT=32822
BOOTSTRAPFILE=''

NODEIP=$(curl -s4 icanhazip.com)

BLUE="\033[0;34m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
PURPLE="\033[0;35m"
RED='\033[0;31m'
GREEN="\033[0;32m"
NC='\033[0m'
MAG='\e[1;35m'

purgeOldInstallation() {
    echo -e "${GREEN}Searching and removing old $COIN_NAME files and configurations${NC}"
    #kill wallet daemon
    sudo $COIN_DAEMON stop > /dev/null 2>&1
	sudo killall $COIN_DAEMON > /dev/null 2>&1
    cd $CONFIGFOLDER >/dev/null 2>&1
    rm -rf *.pid *.lock blk*.dat tx* database >/dev/null 2>&1
	#remove binaries and utilities
    cd /usr/local/bin && sudo rm $COIN_DAEMON > /dev/null 2>&1 && cd
    echo -e "${GREEN}* Done${NONE}";
}


function download_node() {
  echo -e "${GREEN}Downloading and Installing VPS $COIN_NAME daemon${NC}"
  cd $TMP_FOLDER >/dev/null 2>&1
  wget -q $COIN_TGZ
  compile_error
  tar xvzf $COIN_ZIP >/dev/null 2>&1
  chmod +x $COIN_DAEMON $COIN_CLI
  cp $COIN_DAEMON $COIN_CLI $COIN_PATH
  cd ~ >/dev/null 2>&1
  rm -rf $TMP_FOLDER >/dev/null 2>&1
  clear
}

function download_bootstrap() {
  echo -e "${GREEN}Downloading and Installing $COIN_NAME bootstrap - this may take a while ${NC}"
  #mkdir -p /root/tmp
  #cd /root/tmp >/dev/null 2>&1
  #rm -rf boot_strap* >/dev/null 2>&1
  cd $CONFIGFOLDER >/dev/null 2>&1
  wget -q $COIN_BOOTSTRAP
  rm -rf blk* txindex*
  #cd /root/tmp >/dev/null 2>&1
  tar -xvzf $BOOTSTRAPFILE >/dev/null 2>&1
  #cp -Rv cache/* $CONFIGFOLDER >/dev/null 2>&1
  cd ~ >/dev/null 2>&1
  #rm -rf $TMP_FOLDER >/dev/null 2>&1
  clear
}

function configure_systemd() {
  cat << EOF > /etc/systemd/system/$COIN_NAME.service
[Unit]
Description=$COIN_NAME service
After=network.target

[Service]
User=root
Group=root

Type=forking
#PIDFile=$CONFIGFOLDER/$COIN_NAME.pid

ExecStart=$COIN_PATH$COIN_DAEMON -daemon -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER
ExecStop=-$COIN_PATH$COIN_CLI -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER stop

Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $COIN_NAME.service
  systemctl enable $COIN_NAME.service >/dev/null 2>&1

  if [[ -z "$(ps axo cmd:100 | egrep $COIN_DAEMON)" ]]; then
    echo -e "${RED}$COIN_NAME is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo -e "${GREEN}systemctl start $COIN_NAME.service"
    echo -e "systemctl status $COIN_NAME.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}


function create_config() {
  mkdir $CONFIGFOLDER >/dev/null 2>&1
  RPCUSER=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n1)
  RPCPASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w22 | head -n1)
  cat << EOF > $CONFIGFOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcport=$RPC_PORT
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
port=$COIN_PORT
EOF
}

function create_key() {
  echo -e "${YELLOW}Enter your ${RED}$COIN_NAME Masternode GEN Key${NC}."
  read -e COINKEY
  if [[ -z "$COINKEY" ]]; then
  $COIN_PATH$COIN_DAEMON -daemon
  sleep 30
  if [ -z "$(ps axo cmd:100 | grep $COIN_DAEMON)" ]; then
   echo -e "${RED}$COIN_NAME server couldn not start. Check /var/log/syslog for errors.{$NC}"
   exit 1
  fi
  COINKEY=$($COIN_PATH$COIN_CLI masternode genkey)
  if [ "$?" -gt "0" ];
    then
    echo -e "${RED}Wallet not fully loaded. Let us wait and try again to generate the GEN Key${NC}"
    sleep 30
    COINKEY=$($COIN_PATH$COIN_CLI masternode genkey)
  fi
  $COIN_PATH$COIN_CLI stop
fi
clear
}

function update_config() {
  sed -i 's/daemon=1/daemon=0/' $CONFIGFOLDER/$CONFIG_FILE
  cat << EOF >> $CONFIGFOLDER/$CONFIG_FILE
logintimestamps=1
maxconnections=256
#bind=$NODEIP
masternode=1
externalip=$NODEIP:$COIN_PORT
masternodeprivkey=$COINKEY

#Addnodes

EOF
}


function enable_firewall() {
  echo -e "Installing and setting up firewall to allow ingress on port ${GREEN}$COIN_PORT${NC}"
  ufw allow $COIN_PORT/tcp comment "$COIN_NAME MN port" >/dev/null
  ufw allow ssh comment "SSH" >/dev/null 2>&1
  ufw limit ssh/tcp >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  echo "y" | ufw enable >/dev/null 2>&1
}


function get_ip() {
  declare -a NODE_IPS
  for ips in $(netstat -i | awk '!/Kernel|Iface|lo/ {print $1," "}')
  do
    NODE_IPS+=($(curl --interface $ips --connect-timeout 2 -s4 icanhazip.com))
  done

  if [ ${#NODE_IPS[@]} -gt 1 ]
    then
      echo -e "${GREEN}More than one IP. Please type 0 to use the first IP, 1 for the second and so on...${NC}"
      INDEX=0
      for ip in "${NODE_IPS[@]}"
      do
        echo ${INDEX} $ip
        let INDEX=${INDEX}+1
      done
      read -e choose_ip
      NODEIP=${NODE_IPS[$choose_ip]}
  else
    NODEIP=${NODE_IPS[0]}
  fi
}


function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile $COIN_NAME. Please investigate.${NC}"
  exit 1
fi
}


function checks() {
if [[ $(lsb_release -d) != *20.04* ]]; then
  echo -e "${RED}You are not running Ubuntu 20.04. Installation is cancelled.${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi

if [ -n "$(pidof $COIN_DAEMON)" ] || [ -e "$COIN_DAEMON" ] ; then
  echo -e "${RED}$COIN_NAME is already installed.${NC}"
  exit 1
fi
}

function prepare_system() {
echo -e "Installing Dependencies to setup the ${CYAN}$COIN_NAME${NC} ${YELLOW}masternode${NC}"
apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade >/dev/null 2>&1
apt install -y software-properties-common >/dev/null 2>&1
echo -e "${PURPLE}Adding bitcoin PPA repository"
apt-add-repository -y ppa:bitcoin/bitcoin >/dev/null 2>&1
echo -e "Installing required packages, it may take some time to finish.${NC}"
apt-get update >/dev/null 2>&1
apt-get install libzmq3-dev -y >/dev/null 2>&1
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" make build-essential \
git screen net-tools libtool autotools-dev automake pkg-config libevent-dev bsdmainutils libgmp3-dev \
software-properties-common libdb5.3++ unzip libzmq5 libminiupnpc-dev libzmq3-dev ufw \
pkg-config libevent-dev  libdb5.3++ unzip libzmq5 >/dev/null 2>&1
if [ "$?" -gt "0" ];
  then
    echo -e "${RED}Not all required packages were installed properly. Try to install them manually by running the following commands:${NC}\n"
    echo "apt-get update"
    echo "apt -y install software-properties-common"
    echo "apt-add-repository -y ppa:bitcoin/bitcoin"
    echo "apt-get update"
    echo "apt install -y make build-essential \
git screen net-tools libtool autotools-dev automake pkg-config libevent-dev bsdmainutils libgmp3-dev \
software-properties-common libdb5.3++ unzip libzmq5 libminiupnpc-dev libzmq3-dev ufw \
pkg-config libevent-dev  libdb5.3++ unzip libzmq5"
 exit 1
fi
clear
}

function install_openssl() {
echo -e "Installing ${YELLOW}openssl-1.0.2n${NC}"
cd ~
DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade >/dev/null 2>&1
sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
echo "deb http://security.ubuntu.com/ubuntu bionic-security main" | sudo tee -a /etc/apt/sources.list
sudo apt-get update && apt-cache policy libssl1.0-dev
sudo apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" libssl1.0-dev
wget -q http://www.openssl.org/source/openssl-1.0.2n.tar.gz
tar -xvzf openssl-1.0.2n.tar.gz
cd openssl-1.0.2n
./config --prefix=/usr/
make
sudo make install
cd ~
echo -e "Finalizing installation of ${YELLOW}openssl-1.0.2n${NC}"
sleep 60
clear
}

function install_berkeley() {
echo -e "Installing ${PURPLE}berkeley 4.8 db${NC}"
cd ~
DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade >/dev/null 2>&1
wget -q http://download.oracle.com/berkeley-db/db-4.8.30.tar.gz
tar -xvzf db-4.8.30.tar.gz
cd db-4.8.30
sed -i 's/__atomic_compare_exchange/__atomic_compare_exchange_db/g' dbinc/atomic.h
cd build_unix/
../dist/configure --prefix=/usr/local --enable-cxx
make
sudo make install
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/local/lib"
cd ~
echo -e "Finalizing installation of ${PURPLE}berkeley 4.8 db${NC}"
sleep 60
clear
}

function install_boost() {
echo -e "Installing ${GREEN}boost 1.57${NC} This may take awhile. Please be patient....."
cd ~
DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade >/dev/null 2>&1
wget -q http://sourceforge.net/projects/boost/files/boost/1.57.0/boost_1_57_0.tar.gz
tar -xvzf boost_1_57_0.tar.gz
cd boost_1_57_0
./bootstrap.sh
./b2
sudo ./b2 install
sudo ldconfig
cd ~
echo -e "Finalizing Installation of ${GREEN}boost 1.57${NC}"
sleep 60
clear
}

function buildbuntu() {
echo -e "Building ${CYAN}Buntu${NC} from source..."
cd ~ >/dev/null 2>&1
sudo git clone $COIN_REPO > /dev/null 2>&1
sudo touch Buntu
cd Buntu/src
sudo make -f makefile.unix
echo -e "Completing compiliation of ${CYAN}Buntu${NC}"
sleep 120
sudo cp $COIN_DAEMON $COIN_CLI $COIN_PATH
cd ~
clear
}

function important_information() {
 echo
 echo -e "${BLUE}================================================================================================================================${NC}"
 echo -e "${Yellow}Welcome to $COIN_NAME"
 echo -e "${BLUE}================================================================================================================================${NC}"
 echo -e "${GREEN}$COIN_NAME Masternode is up and running listening on port:${NC}${PURPLE}$COIN_PORT${NC}."
 echo -e "${GREEN}Configuration file is:${NC}${RED}$CONFIGFOLDER/$CONFIG_FILE${NC}"
 echo -e "${GREEN}daemon is located at:${NC}${RED}$COIN_PATH${NC}"
 echo -e "${GREEN}Start:${NC}${RED}systemctl start $COIN_NAME.service${NC}"
 echo -e "${GREEN}Stop:${NC}${RED}systemctl stop $COIN_NAME.service${NC}"
 echo -e "${GREEN}VPS_IP:${NC}${GREEN}$NODEIP:$COIN_PORT${NC}"
 echo -e "${GREEN}MASTERNODE GENKEY is:${NC}${PURPLE}$COINKEY${NC}"
 echo -e "${BLUE}================================================================================================================================"
 echo -e "${CYAN}Join Discord or Telegram to Stay Updated"
 echo -e "${BLUE}================================================================================================================================${NC}"
 #echo -e "${CYAN}Ensure Node is fully SYNCED with BLOCKCHAIN.${NC}"
 echo -e "${BLUE}================================================================================================================================${NC}"
 echo -e "${GREEN}Daemon info:${NC}"
 echo -e "${GREEN} cd /usr/local/bin/${NC}"
 echo -e "${GREEN} ./buntud getinfo${NC}"

 }

function setup_node() {
  get_ip
  create_config
  create_key
  update_config
  enable_firewall
  #download_bootstrap
  important_information
  configure_systemd
}


##### Main #####
clear

purgeOldInstallation
checks
prepare_system
install_openssl
install_berkeley
install_boost
#buildbuntu
download_node
setup_node
