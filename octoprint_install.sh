#!/bin/bash

set -e

HOMEDIR="/home/octo"
DISTRIBUTOR="$(/usr/bin/lsb_release -is)"
RELEASE="$(lsb_release -cs)"
UNSTABLE_INSTALL=false
UNSTABLE_PYTHON=false

export HOMEDIR \
       DISTRIBUTOR \
       RELEASE \
       UNSTABLE_INSTALL \
       UNSTABLE_PYTHON_COMPILE \
       UNSTABLE_PYTHON_PACKAGE

function echo_yellow {
  TEXT="${*}"
  echo -e "\e[33m${TEXT}\e[0m"
}

function echo_green {
  TEXT="${*}"
  echo -e "\e[32m${TEXT}\e[0m"
}

function echo_red {
  TEXT="${*}"
  echo -e "\e[31m${TEXT}\e[0m"
}

function question_unstable {
  echo_yellow "# Detected unstable distributior version: ${DISTRIBUTOR} ${RELEASE}"
  echo_yellow '# Installation on your distribution may be unstable or completely broken'
  echo_yellow '# We are STRONGLY recommend upgrade your OS to supported version'
  while true; do
    read -p "# Do you REALLY want to continue installation? (Y or N)" ANSWER_CONTINUE
    case $ANSWER_CONTINUE in
      [Yy]*)
             UNSTABLE_INSTALL=true
             export UNSTABLE_INSTALL
             break
             while true; do
               echo_yellow '# 1 - Try use python3 package from your distribution'
               echo_yellow '# 2 - Compile Python 3.8.5'
               read -p "# Please answer:" ANSWER_PYTHON
               case $ANSWER_PYTHON in
                 1)
                   UNSTABLE_PYTHON=package
                   export UNSTABLE_PYTHON_PACKAGE
                 ;;
                 2)
                   UNSTABLE_PYTHON=compile
                   export UNSTABLE_PYTHON_COMPILE
                 ;;
               esac
             done
      ;;
      [Nn]*)
            exit;;
      *)
        echo "Please answer yes or no."
      ;;
    esac
  done
}

if [ "$EUID" -ne 0 ]; then
  echo_red "# Please run as root"
  exit 1
fi

case $DISTRIBUTOR in
  Debian|Ubuntu)
    case "${RELEASE}" in
      bionic|cosmic|disco|eoam|focal|groovy|stretch|buster)
        echo_green "# Detected stable distributior version: ${DISTRIBUTOR} ${RELEASE}"
      ;;
      *)
        question_unstable
      ;;
    esac
    ;;
  LinuxMint)
    case "${RELEASE}" in
      Tara|Tessa|Tina|Tricia|Ulyana)
        echo_green "# Detected stable distributior version: ${DISTRIBUTOR} ${RELEASE}"
      ;;
      *)
        question_unstable
      ;;
    esac
    ;;
  *)
    echo_red "# Unsupported distributor: ${DISTRIBUTOR}"
    exit 2
    ;;
esac

function setup_venv {
  set -e
  mkdir ${HOMEDIR}/OctoPrint
  cd ${HOMEDIR}/OctoPrint
  case "${UNSTABLE_PYTHON}" in
    compile)
      export PATH="${HOME}/.local/bin/:${PATH}"
      pip3.8 install virtualenv
      virtualenv -p /usr/local/bin/python3.8 --quiet venv
      source venv/bin/activate
      pip3.8 install pip --upgrade
      pip3.8 install octoprint
    ;;
    package)
      virtualenv -p /usr/bin/python3 --quiet venv
      source venv/bin/activate
      pip install pip --upgrade
      pip install octoprint
    ;;
  esac
}

export -f setup_venv

if [ -d "${HOMEDIR}" ]; then
    read -p "User octo already exist, delete user and continue? (Y/n)" -n 1 -r
    echo    # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo_yellow "# Delete user octo and $HOMEDIR folder"
      userdel -r octo
    else
      echo_red "# User octo already exist. Installation stoped"
      exit
    fi
fi

echo_yellow "# Create octo user"
useradd -m -s /bin/bash -G tty,dialout,video octo

echo_yellow "# Please password for octo user"
passwd octo

echo_yellow "# Install package dependencies"
# apt-get update
# Python dependencies
case $DISTRIBUTOR in
  Ubuntu|Debian)
    apt-get -y install \
      build-essential \
      curl \
      git \
      libyaml-dev \
      python3-dev \
      python3-pip \
      python3-setuptools \
      python3-virtualenv \
      zlib1g-dev \
      virtualenv
    ;;
  LinuxMint)
    case "${RELEASE}" in
      18.*)
        echo_yellow '# WARNING!!! 18.* based on outdated Ubuntu 16.04. We strogly recommend upgrade OS!'
        echo_yellow '# Install dependencies for compile python 3.8'
        apt-get -y install \
          build-essential \
          checkinstall \
          curl \
          git \
          libbz2-dev \
          libc6-dev \
          libffi-dev \
          libgdbm-dev \
          libncursesw5-dev \
          libreadline-gplv2-dev \
          libsqlite3-dev \
          libssl-dev \
          libyaml-dev \
          sudo \
          tk-dev \
          zlib1g-dev
        echo_yellow '# Download and compile python 3.8'
        rm -rf /tmp/Python-3.8.5*
        wget https://www.python.org/ftp/python/3.8.5/Python-3.8.5.tar.xz \
          -O /tmp/Python-3.8.5.tar.xz
        cd /tmp
        tar -xf /tmp/Python-3.8.5.tar.xz
        cd /tmp/Python-3.8.5/
        ./configure
        make
        echo_yellow '# Install python 3.8'
        make install
      ;;
      *)
        apt-get -y install \
          build-essential \
          curl \
          git \
          libyaml-dev \
          python3-dev \
          python3-pip \
          python3-setuptools \
          python3-virtualenv \
          zlib1g-dev \
          virtualenv
      ;;
    esac
    ;;
esac
# ffmpeg && mjpg-streamer build dependencies
case $DISTRIBUTOR in
  Debian)
    apt-get -y install \
      cmake \
      ffmpeg \
      git \
      imagemagick \
      libjpeg62-turbo-dev \
      libv4l-dev \
      sudo
    ;;
  Ubuntu|LinuxMint)
    apt-get -y install \
      cmake \
      ffmpeg \
      git \
      imagemagick \
      libjpeg8-dev \
      libv4l-dev \
      sudo
    ;;
esac

echo_yellow "# Configure OctoPrint VirtualEnv"
su octo -c "setup_venv"

echo_yellow "# Configure OctoPrint autostart"
curl -fsvL \
  -o /etc/systemd/system/octoprint.service \
  https://raw.githubusercontent.com/Nebari-xx/octoprint_installer/master/octoprint.service
curl -fsvL \
  -o /etc/default/octoprint \
  https://raw.githubusercontent.com/Nebari-xx/octoprint_installer/master/octoprint.default

echo_yellow "# Build mjpg-streamer"
git clone https://github.com/jacksonliam/mjpg-streamer.git /home/octo/mjpg-streamer
cd /home/octo/mjpg-streamer/mjpg-streamer-experimental
export LD_LIBRARY_PATH=.
make
cp -v /home/octo/mjpg-streamer/mjpg-streamer-experimental/_build/mjpg_streamer /usr/local/bin/mjpg_streamer

echo_yellow "# Configure scripts"
echo "octo ALL=NOPASSWD: /sbin/shutdown,/bin/systemctl restart octoprint.service" >> /etc/sudoers
curl -fsvL \
  -o /etc/systemd/system/webcam.service \
  https://raw.githubusercontent.com/Nebari-xx/octoprint_installer/master/webcam.service
curl -fsvL \
  -o /usr/local/bin/webcamDaemon\
  https://raw.githubusercontent.com/Nebari-xx/octoprint_installer/master/webcamDaemon
chmod +x /usr/local/bin/webcamDaemon

systemctl daemon-reload

for SERVICE in octoprint webcam; do
  set +e
  systemctl enable "${SERVICE}.service"
  systemctl start "${SERVICE}.service"
  sleep 10
  systemctl is-active --quiet "${SERVICE}.service"
  if systemctl is-active --quiet "${SERVICE}.service"; then
    echo_green "# Service ${SERVICE} OK."
  else
    echo_red "# Service ${SERVICE} not running! Check it:"
    echo_red "# Run for logs: journalctl --no-pager -b -u ${SERVICE}.service"
  fi
done

echo_green "# All done! Try to open web interface with this link:"
for IP in $(hostname --all-ip-addresses | grep -v '127.0.0.1'); do
  echo_green "# Listen http://${IP}:5000"
  echo_green "# Webcam stream http://${IP}:8080/?action=stream"
done
