if command -v docker &> /dev/null ; then
  echo "docker is already installed..."
  echo "skipping docker installation..."
  exit 0
  # The docker compose plugin (Docker Compose V2) is now installed by default with Docker.
  # If Docker is already installed but the docker compose plugin is not installed, 
  # the docker compose plugin will need to be manually installed -> 
  # https://docs.docker.com/compose/install/linux/
  # To check if it's installed, run `docker compose version`
fi

# adapted from https://askubuntu.com/questions/459402/how-to-know-if-the-running-platform-is-ubuntu-or-centos-with-help-of-a-bash-scri
command_present() {
  type "$1" >/dev/null 2>&1
}

if ! command_present wget && command_present yum; then
  sudo yum install wget
fi
wget -qO- https://get.docker.com/ | sh
