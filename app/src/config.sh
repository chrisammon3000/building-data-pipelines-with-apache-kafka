#! /bin/bash -xe

# Install Dependencies
yum update -y
yum install -y docker git
service docker start
usermod -a -G docker ec2-user
chkconfig docker on
curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
docker-compose version

# Application specific configuration
# https://opensearch.org/docs/latest/install-and-configure/install-opensearch/docker/#important-host-settings
swapoff -a
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
sysctl -p
echo "Checking vm.max_map_count: $(cat /proc/sys/vm/max_map_count)"

# Deploy services
mkdir -p /opt/app /opt/data/opensearch-data1 /opt/data/opensearch-data2
chown -R ec2-user:ec2-user /opt/app /opt/data
git clone https://github.com/chrisammon3000/building-data-pipelines-with-apache-kafka.git /opt/app
cd /opt/app && docker-compose up -d
