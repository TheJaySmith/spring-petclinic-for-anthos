#!/bin/bash env

sudo apt-get update --fix-missing
sudo apt-get -y upgrade
sudo apt-get -y dist-upgrade

sudo apt-get install -y openjdk-11-jdk maven nginx-full


# create firewall rule
gcloud compute firewall-rules create http-8080 \
--network default \
--priority 1000 \
--target-tags http-8080 \
--source-ranges 0.0.0.0/0 \
--rules tcp:8080 \
--action allow

#spring Firewall
gcloud compute firewall-rules create spring-http --allow tcp:80,tcp:443

# create machine
gcloud compute instances create spring-monolith \
--image-family ubuntu-1804-lts \
--image-project gce-uefi-images \
--machine-type n1-standard-2 \
--zone us-central1-a \
--network default \
--subnet default \
--tags http-server,https-server,http-8080

#tag machine
gcloud compute instances add-tags spring-monolith \
--zone us-central1-a \
--tags http-8080


sudo bash -c 'cat <<EOF >> spring
server {
  listen          80;
  server_name     localhost;
  location / {
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Server $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:8080/;
  }
} 
EOF'