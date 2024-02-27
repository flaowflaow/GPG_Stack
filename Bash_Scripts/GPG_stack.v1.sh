#!/bin/bash
# Script d'installation d'un serveur de supervision Grafana.
# Services : Grafana, Prometheus & Graylog

# Installation des prérequis
sudo apt install apt-transport-https software-properties-common wget curl unzip net-tools -y


### Installation de Grafana
# Ajout des clés et dépôts de Grafana
mkdir -p /etc/apt/keyrings/ && \
wget -vO - https://packages.grafana.com/gpg.key | sudo apt-key add - && \
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
      
# Installer grafana
sudo apt-get update && sudo apt-get install -y grafana

# Modification du fichier grafana.ini
sudo cat <<"EOF" >> /etc/grafana/grafana.ini
[paths]
data = /var/lib/grafana
temp_data_lifetime = 24h
logs = /var/log/grafana
plugins = /var/lib/grafana/plugins
provisioning = /etc/grafana/provisioning
  
[server]
protocol = http
;min_tls_version = ""
http_addr = 192.168.200.10
http_port = 3000
domain = 192.168.200.10
enforce_domain = false
EOF
      
# Configurer le datasource prometheus
sudo cat <<"EOF" > /etc/grafana/provisioning/datasources/prometheus.yaml
apiVersion: 1

datasources:
 - name: Prometheus
   type: prometheus
   access: proxy
   url: http://127.0.0.1:9090
   isDefault: true
   version: 1
   editable: true
EOF

# Configurer le datasource loki
sudo cat <<"EOF" > /etc/grafana/provisioning/datasources/loki.yaml
apiVersion: 1

datasources:
 - name: Loki
   type: loki
   access: proxy
   url: http://127.0.0.1:3100
   jsonData:
     timeout: 60
     maxLines: 1000
EOF


### Installation de Prometheus
# Télécharger et extraire le binaire prometheus
mkdir -p /tmp/prometheus && cd /tmp/prometheus \
  && curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest \
  | grep browser_download_url \
  | cut -d '"' -f 4 \
  | grep linux-amd64.tar.gz \
  | wget -vO - -i - \
  | tar -xzv --strip-components=1

# Créer le répertoire et copier les fichiers
sleep 20
sudo mkdir /etc/prometheus
sudo cp prometheus /usr/bin/
sudo cp promtool /usr/bin/
sudo cp -r consoles /etc/prometheus
sudo cp -r console_libraries /etc/prometheus
sudo mkdir -p /var/lib/prometheus/

# Créer l'user prometheus et attibution des droits
sudo useradd --no-create-home --shell /bin/false prometheus
sudo chown -R prometheus:prometheus /etc/prometheus
sudo chown prometheus:prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /usr/bin/prometheus
sudo chown prometheus:prometheus /usr/bin/promtool
sudo chown prometheus:prometheus /var/lib/prometheus/

# Configuration de prometheus.yaml et prometheus.service
sudo cat <<"EOF" > /etc/prometheus/prometheus.yaml
global:
  scrape_interval: 15s
    
scrape_configs:
  - job_name: "prometheus"
    scrape_interval: 5s
    static_configs:
      - targets: ["localhost:9090"]
  - job_name: "apache2_exporter"
    scrape_interval: 5s
    metrics_path: /metrics
    static_configs:
      - targets: ["192.168.200.11:9117"]
  - job_name: "apache2_node_exporter"
    scrape_interval: 5s
    static_configs:
      - targets: ["192.168.200.11:9100"]
  - job_name: "nginx_exporter"
    scrape_interval: 5s
    metrics_path: /metrics
    static_configs:
      - targets: ["192.168.200.12:9113"]
  - job_name: "nginx_node_exporter"
    scrape_interval: 5s
    static_configs:
      - targets: ["192.168.200.12:9100"]
EOF

sudo cat <<"EOF" > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/bin/prometheus \
  --config.file /etc/prometheus/prometheus.yaml \
  --storage.tsdb.path /var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF

### GRAYLOG
# Installer les dépendances
sudo apt-get update
sudo apt-get install -y apt-transport-https openjdk-8-jre-headless uuid-runtime pwgen wget curl
# Ajouter le dépôt mongodb
wget -qO - https://www.mongodb.org/static/pgp/server-4.4.asc | sudo apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.4 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.4.list
# Ajouter le dépôt elasticsearch
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb https://artifacts.elastic.co/packages/oss-7.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-7.x.list
# Ajouter le dépôt graylog
wget https://packages.graylog2.org/repo/packages/graylog-4.2-repository_latest.deb
sudo dpkg -i graylog-4.2-repository_latest.deb
# Installer mongodb, elasticsearch et graylog
sudo apt-get update
sudo apt-get install -y mongodb-org elasticsearch-oss graylog-server
# Configurer elasticsearch
sudo sed -i 's/#cluster.name: my-application/cluster.name: graylog/g' /etc/elasticsearch/elasticsearch.yml
# Configurer graylog
sudo sed -i 's/password_secret =.*/password_secret = $(pwgen -s 96 1)/g' /etc/graylog/server/server.conf
# Générer le mot de passe admin
sudo sed -i "s/root_password_sha2 =.*/root_password_sha2 = $(echo -n admin | sha256sum | cut -d" " -f1)/g" /etc/graylog/server/server.conf
# Configurer l'adresse IP
sudo sed -i "s/# Default: 127.0.0.1:9000/Default: 127.0.0.1:9000/g" /etc/graylog/server/server.conf
sudo sed -i "s/#http_bind_address = 127.0.0.1:9000/http_bind_address = 192.168.200.10:9000/g" /etc/graylog/server/server.conf
# Configurer le collecteur UDP
sudo sed -i "s/#inputbuffer_processors = 2/inputbuffer_processors = 2/g" /etc/graylog/server/server.conf
sudo sed -i "s/#processbuffer_processors = 5/processbuffer_processors = 5/g" /etc/graylog/server/server.conf
sudo sed -i "s/#outputbuffer_processors = 3/outputbuffer_processors = 3/g" /etc/graylog/server/server.conf
sudo sed -i "s/#udp_recvbuffer_sizes = 1048576/udp_recvbuffer_sizes = 1048576/g" /etc/graylog/server/server.conf


# Activation et redémarrage des services
sudo systemctl daemon-reload
sleep 5
sudo systemctl enable grafana-server
sudo systemctl restart grafana-server
sleep 5
sudo systemctl enable prometheus
sudo systemctl restart prometheus
sleep 5
sudo systemctl enable graylog
sudo systemctl restart graylog
sudo systemctl enable mongod.service
sudo systemctl restart mongod.service
sudo systemctl enable elasticsearch.service
sudo systemctl restart elasticsearch.service
sleep 10
sudo systemctl enable graylog-server.service
sudo systemctl start graylog-server.service
