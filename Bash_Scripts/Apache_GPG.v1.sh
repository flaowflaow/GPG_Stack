#!/bin/bash
# Script d'installation d'un serveur Apache supervisé par la pile Grafana / Prometheus / Graylog.
# Services : Apache, Node_Exporter, Prometheus_Apache_Exporter, Graylog Sidecar
# V1

# Installation des prérequis
sudo apt install apt-transport-https software-properties-common wget unzip net-tools -y


### Installation d'Apache2
# Installer Apache2
sudo apt update
sudo apt install -y apache2
sudo systemctl daemon-reload
sudo systemctl start apache2
sudo systemctl enable apache2

# Création de la page Apache server-status
sudo cat <<"EOF" > /etc/apache2/conf-available/server-status.conf
ExtendedStatus on
<Location /server-status>
    SetHandler server-status
    Order deny,allow
    Deny from all
    Allow from 127.0.0.1
</Location>
EOF

# Activation de la configuration Apache
cd /etc/apache2/conf-enabled
sudo ln -s ../conf-available/server-status.conf server-status.conf && cd
sudo systemctl restart apache2


### Installation de Prometheus_Apache_Exporter 
# Téléchargement et installation de la librairie Apache Exporter
mkdir -p /tmp/apache_node_exporter && cd /tmp/apache_node_exporter \
  && curl -s https://api.github.com/repos/Lusitaniae/apache_exporter/releases/latest \
  | grep browser_download_url \
  | cut -d '"' -f 4 \
  | grep linux-amd64.tar.gz \
  | wget -vO - -i - \
  | tar -xzv --strip-components=1
sudo cp ./apache_exporter /usr/local/bin/

# Création de l'user Apache_exporter & attribution des droits
sudo useradd -M -r -s /bin/false apache_exporter
sudo groupadd apache_exporter
sudo chown apache_exporter:apache_exporter /usr/local/bin/apache_exporter

# Créer le service systemd pour Prometheus-Apache-exporter
sudo cat <<"EOF" > /etc/systemd/system/prometheus-apache-exporter.service
[Unit]
Description=Prometheus Apache Exporter
Wants=network-online.target
After=network-online.target
      
[Service]
User=apache_exporter
Group=apache_exporter
Type=simple
ExecStart=/usr/local/bin/apache_exporter
      
[Install]
WantedBy=multi-user.target
EOF

### Installation du Node_Exporter
# Télécharger et installer le node_exporter
mkdir -p /tmp/prometheus && cd /tmp/prometheus \
  && curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest \
  | grep browser_download_url \
  | cut -d '"' -f 4 \
  | grep linux-amd64.tar.gz \
  | wget -vO - -i - \
  | tar -xzv --strip-components=1
sudo cp ./node_exporter /usr/local/bin/

# Créer l'utilisateur et le groupe node_exporter
sudo useradd --no-create-home --shell /bin/false node_exporter
sudo groupadd node_exporter
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

# Créer le service systemd pour node_exporter
sudo cat <<"EOF" > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF


### Installation de Graylog Sidecar
# Téléchargement & installation de Graylog Sidecar
wget https://packages.graylog2.org/repo/packages/graylog-sidecar-repository_1-5_all.deb
sudo dpkg -i graylog-sidecar-repository_1-5_all.deb
sudo apt-get update && sudo apt-get install graylog-sidecar
# Configuration de Sidecar
sudo bash -c 'cat <<EOF > /etc/graylog/sidecar/sidecar.yml
server_url: http://192.168.200.10:9000/api/
update_interval: 10
tls_skip_verify: false
send_status: true
list_log_files:
  - /var/log
  - /etc/apache2/logs
collector_id: file:/etc/graylog/collector-sidecar/collector-id
log_path: /var/log/graylog/collector-sidecar
log_rotation_time: 86400
log_max_age: 604800
tags:
  - linux
  - apache
sidecar:                                                                
  node_id: file:/etc/graylog/collector-sidecar/generated/filebeat.yml       
  collector_id: file:/etc/graylog/collector-sidecar/collector-id
  cache_path: /var/cache/graylog/collector-sidecar
  log_path: /var/log/graylog/collector-sidecar
  log_rotation_time: 86400                                                
  log_max_age: 604800
  tags:
    - linux
    - apache
  backends:
    - name: filebeat
      enabled: true
      binary_path: /usr/bin/filebeat
      configuration_path: /etc/graylog/collector-sidecar/generated/filebeat
EOF'
# Téléchargement et installation des librairies et modules Apache pour Gelf
wget https://github.com/graylog-labs/apache-mod_log_gelf/releases/download/0.2.0/libapache2-mod-gelf_0.2.0-1_amd64.debian.deb  
sudo dpkg -i libapache2-mod-gelf_0.2.0-1_amd64.debian.deb
wget http://security.ubuntu.com/ubuntu/pool/main/j/json-c/libjson-c2_0.11-4ubuntu2.6_amd64.deb                                                   
sudo dpkg -i libjson-c2_0.11-4ubuntu2.6_amd64.deb 
sudo apt install libjson-c2 -y
# Activation du module log_gelf d'Apache
sudo a2enmod log_gelf
# Configuration du module log_gelf
sudo bash -c 'cat <<EOF > /etc/apache2/mods-enabled/log_gelf.load
LoadModule log_gelf_module /usr/lib/apache2/modules/mod_log_gelf.so
EOF'
sudo cat <<"EOF" > /etc/apache2/mods-enabled/log_gelf.conf
GelfEnabled On
GelfUrl "udp://192.168.200.10:5510"
GelfSource "apache_server"
GelfFacility "apache-gelf"
GelfTag "gelf-tag"
GelfCookie "tracking"
GelfFields "ABDhmsvRti
EOF


### Activation et redémarrage des services
sudo systemctl daemon-reload
# Activation et démarrage du service Apache
sudo systemctl enable apache2
sudo systemctl restart apache2
# Activation et démarrage du service prometheus-apache-exporter
sudo systemctl enable prometheus-apache-exporter.service
sudo systemctl start prometheus-apache-exporter.service
# Activation et démarrage du service Node_Exporter
sudo systemctl enable node_exporter
sudo systemctl restart node_exporter
