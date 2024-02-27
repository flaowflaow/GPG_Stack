#!/bin/bash
# Script d'installation d'un serveur Nginx supervisé par la pile Grafana / Prometheus / Graylog.
# Services : Nginx, Node_Exporter, Nginx_Prometheus_Exporter, Graylog Sidecar
# V1


### Installation de Nginx
# Installation des prérequis
sudo apt install apt-transport-https software-properties-common wget unzip net-tools -y

# Installer Nginx
sudo apt update && apt upgrade -y
sudo apt install -y nginx

# Configurer le site par défaut pour exposer les métriques de Nginx
sudo cat <<"EOF" > /etc/nginx/sites-available/default
server {
  listen 80 default_server;
  listen [::]:80 default_server;

  index index.html index.htm index.nginx-debian.html;

  server_name _;

  root /var/www/html;

  location / {
          try_files $uri $uri/ =404;
  }

  location /metrics {
  stub_status on;
  access_log off;
  allow 127.0.0.1;
  allow 192.168.33.10;
  deny all;

  }

}
EOF


### Installation de Node_Exporter
# Télécharger et installer le node_exporter
sudo mkdir -p /tmp/prometheus && cd /tmp/prometheus \
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


### Installation de Nginx_Prometheus_Exporter
# Installer nginx-prometheus-exporter
mkdir -p /tmp/nginx_prometheus_exporter && cd /tmp/nginx_prometheus_exporter \
  && wget https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v1.1.0/nginx-prometheus-exporter_1.1.0_linux_amd64.tar.gz \
  && tar -xzv -f nginx-prometheus-exporter_1.1.0_linux_amd64.tar.gz \
  && sudo cp ./nginx-prometheus-exporter /usr/local/bin/
sudo cp ./nginx-prometheus-exporter /usr/local/bin/

# Créer l'utilisateur et le groupe node_exporter
sudo useradd --no-create-home --shell /bin/false nginx-prometheus-exporter
sudo groupadd nginx-prometheus-exporter
sudo chown nginx-prometheus-exporter:nginx-prometheus-exporter /usr/local/bin/nginx-prometheus-exporter

# Créer le service systemd pour nginx-prometheus-exporter
sudo cat <<"EOF" > /etc/systemd/system/nginx-prometheus-exporter.service
[Unit]
Description=Nginx Prometheus Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=nginx-prometheus-exporter
Group=nginx-prometheus-exporter
Type=simple
ExecStart=/usr/local/bin/nginx-prometheus-exporter -nginx.scrape-uri=http://127.0.0.1/metrics

[Install]
WantedBy=multi-user.target
EOF

# Configurer le syslog pour envoyer les logs à la machine graylog
sudo bash -c 'cat <<EOF > /etc/rsyslog.d/10-graylog.conf
*.* @192.168.33.10:5514;RSYSLOG_SyslogProtocol23Format
EOF'


# Configurer Nginx pour envoyer les logs d'accès à Graylog
sudo cat <<"EOF" > /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
        worker_connections 768;
        # multi_accept on;
}

http {

        ##
        # Basic Settings
        ##

        sendfile on;
        tcp_nopush on;
        tcp_nodelay on;
        keepalive_timeout 65;
        types_hash_max_size 2048;
        # server_tokens off;

        # server_names_hash_bucket_size 64;
        # server_name_in_redirect off;

        include /etc/nginx/mime.types;
        default_type application/octet-stream;

        ##
        # SSL Settings
        ##

        ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3; # Dropping SSLv3, ref: POODLE
        ssl_prefer_server_ciphers on;

        ##
        # Logging Settings
        ##

        access_log /var/log/nginx/access.log;
        error_log /var/log/nginx/error.log;
		    access_log syslog:server=192.168.33.10:5515,tag=nginx_access;
		    error_log syslog:server=192.168.33.10:5516,tag=nginx_error;

		
        ##
        # Gzip Settings
        ##

        gzip on;

        # gzip_vary on;
        # gzip_proxied any;
        # gzip_comp_level 6;
        # gzip_buffers 16 8k;
        # gzip_http_version 1.1;
        # gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

        ##
        # Virtual Host Configs
        ##

        include /etc/nginx/conf.d/*.conf;
        include /etc/nginx/sites-enabled/*;
}


#mail {
#       # See sample authentication script at:
#       # http://wiki.nginx.org/ImapAuthenticateWithApachePhpScript
# 
#       # auth_http localhost/auth.php;
#       # pop3_capabilities "TOP" "USER";
#       # imap_capabilities "IMAP4rev1" "UIDPLUS";
# 
#       server {
#               listen     localhost:110;
#               protocol   pop3;
#               proxy      on;
#       }
# 
#       server {
#               listen     localhost:143;
#               protocol   imap;
#               proxy      on;
#       }
#}
EOF


### Finalisation de l'installation
# Activation et redémarrage des services
sudo systemctl daemon-reload
sleep 5
sudo systemctl enable nginx
sudo systemctl restart nginx
sleep 5
sudo systemctl start node_exporter
sudo systemctl restart node_exporter
sleep 5
sudo systemctl enable nginx-prometheus-exporter
sudo systemctl restart nginx-prometheus-exporter
sleep 5
sudo systemctl enable rsyslog
sudo systemctl restart rsyslog