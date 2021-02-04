if ! command_present wget && command_present yum; then
  sudo yum install wget
fi
wget -qO- https://get.docker.com/ | sh
