if command -v docker &> /dev/null ; then
    echo "docker is already installed..."
    echo "skipping docker installation..."
    exit 0
fi

# adapted from https://askubuntu.com/questions/459402/how-to-know-if-the-running-platform-is-ubuntu-or-centos-with-help-of-a-bash-scri
command_present() {
  type "$1" >/dev/null 2>&1
}

if ! command_present wget && command_present yum; then
  sudo yum install wget
fi
wget -qO- https://get.docker.com/ | sh
