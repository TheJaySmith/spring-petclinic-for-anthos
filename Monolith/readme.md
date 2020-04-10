# Spring PetClinic Monolith on [Google Compute Engine (GCE)](https://cloud.google.com/compute)

Example Petclinic deployment on Google Cloud Platform into Google Kubernetes Engine with Istio.
This is based on [Spring PetClinic](https://github.com/spring-petclinic/spring-petclinic)

Petclinic is a [Spring Boot](https://spring.io/guides/gs/spring-boot) application built using [Maven](https://spring.io/guides/gs/maven/). You can build a jar file and run it from the command line:

## Google Cloud Platform Project

Create a new Project if you haven't done so already.

```bash
export PROJECT_ID=<your project>
gcloud project create $PROJECT_ID
```

If you already have a project, let's just set the variable.

```bash
export PROJECT_ID=<your project>
```

Set the default Project ID:

```bash
gcloud config set core/project $PROJECT_ID
```

## Creating a Firewall Port

Create a firewall rule to allow your machine access to 8080

```bash
gcloud compute firewall-rules create http-8080 \
--network default \
--priority 1000 \
--target-tags http-8080 \
--source-ranges 0.0.0.0/0 \
--rules tcp:8080 \
--action allow
```

## Create our GCE Instance

```bash
gcloud compute instances create spring-monolith \
--image-family ubuntu-1804-lts \
--image-project gce-uefi-images \
--machine-type n1-standard-2 \
--zone us-central1-a \
--network default \
--subnet default \
--tags http-server,https-server,http-8080
```

## Stage our Server

Let's ssh into the server

```bash
gcloud compute ssh --project [PROJECT_ID] --zone us-central1-a spring-monolith
```

Install NGINX and Maven on the server

```bash
sudo apt-get update --fix-missing \
&& sudo apt-get -y upgrade \
&& sudo apt-get -y dist-upgrade \
&& sudo apt-get install -y openjdk-11-jdk maven nginx-full
```

If you want to use port 80 instead of 8080, we will use NGINX as a proxy. 

```bash
sudo rm /etc/nginx/sites-enabled/default
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

sudo service nginx restart
```

Now let's install the application

```bash
git clone https://github.com/TheJaySmith/spring-petclinic-for-anthos
cd Monolith
./mvnw package
java -jar target/*.jar
```

We will allow this to run in it’s own terminal. Open another terminal and let's get our IP address

```bash
gcloud compute instances describe spring-monolith --format='get(networkInterfaces[0].networkIP)'
```

Copy the External IP address and enter it into your browser. If you used the firewall port, then you will append :8080 to the IP address. If you are using NGINX, just the IP is fine.
