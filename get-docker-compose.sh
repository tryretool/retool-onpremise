if command -v docker-compose &> /dev/null ; then
    echo "docker-compose is already installed..."
    echo "skipping docker-compose installation..."
    exit 0
fi

sudo -E curl -L https://github.com/docker/compose/releases/download/1.29.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
