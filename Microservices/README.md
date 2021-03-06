# Spring PetClinic on Anthos using Microservices

Example Petclinic deployment on Google Cloud Platform into Google Kubernetes Engine with Istio.
This is based on [Spring PetClinic Microservices](https://github.com/spring-petclinic/spring-petclinic-microservices)

This example has:

- Observability and Monitoring
  - Stackdriver Trace
  - Stackdriver Monitorning
  - Stackdriver Logging
  - Stackdriver Debugging
  - Stackdriver Profiling
- Spring Boot Petclinic Example with Google Cloud Native configuration
  - Spring Cloud GCP
  - Removed Eureka, Hystrix, Ribbon, Config Server, Gateway, and many other components, because they are provided by Kubernetes and Istio.
  - Eureka -> Kubernetes Service
  - Config Server -> Kubernetes Config Map
  - Gateway -> Kubernetes Ingress
  - Hystrix -> Istio
  - Ribbon -> Istio
- Build
  - Spotify's dockerfile-maven-plugin
- DevOps
  - Travis CI

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

Create a variable for your [Google Container Registry](https://cloud.google.com/container-registry) repository

```bash
export REPO='gcr.io/'${PROJECT_ID}
```

Finally, let's ensure that we are logged in.

```bash
gcloud auth application-default login
```

## Kubernetes Engine Cluster

Use `gcloud` to provision a multi-zone Kubernetes Engine cluster.

```bash
gcloud services enable compute.googleapis.com container.googleapis.com
gcloud beta container clusters create petclinic-micro \
    --cluster-version=1.15.11-gke.3 \
    --addons HorizontalPodAutoscaling,HttpLoadBalancing,Istio \
    --istio-config=auth=MTLS_PERMISSIVE \
    --zone=us-central1-a \
    --num-nodes=3 \
    --machine-type=n1-standard-4 \
    --enable-autorepair \
    --scopes=cloud-platform \
    --enable-stackdriver-kubernetes
```

Since we installed [Istio](https://istio.io) with our cluster, we will want to enable side car injection.

```bash
kubectl label namespace default istio-injection=enabled
```

We will also want to set the proper cluster permissions

```bash
kubectl create clusterrolebinding cluster-admin-binding \
--clusterrole=cluster-admin \
--user="$(gcloud config get-value core/account)"
```

## Stackdriver Prometheus Scraper

Install Prometheus scraper to propagate Prometheus metrics to Stackdriver Monitoring.

```bash
kubectl apply -f https://storage.googleapis.com/stackdriver-prometheus-documentation/rbac-setup.yml --as=admin --as-group=system:masters
curl -s https://storage.googleapis.com/stackdriver-prometheus-documentation/prometheus-service.yml | \
  sed -e "s/\(\s*_kubernetes_cluster_name:*\).*/\1 'petclinic-cluster'/g" | \
  sed -e "s/\(\s*_kubernetes_location:*\).*/\1 'us-central1'/g" | \
  sed -e "s/\(\s*_stackdriver_project_id:*\).*/\1 '${PROJECT_ID}'/g" | \
  kubectl apply -f -
```

## Spanner

```bash
gcloud spanner instances create petclinic --config=regional-us-central1 --nodes=1 --description="PetClinic Spanner Instance"
gcloud spanner databases create petclinic --instance=petclinic
gcloud spanner databases ddl update petclinic --instance=petclinic --ddl="$(<db/spanner.ddl)"
```

## Debugging and Profiling

```bash
gcloud services enable cloudprofiler.googleapis.com clouddebugger.googleapis.com
```

## Generate Service Account

Create a new Service Account for the microservices:

```bash
gcloud iam service-accounts create petclinic --display-name "PetClinic Service Account"
```

Grant IAM Roles to the Service Account:

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
     --member serviceAccount:petclinic@$PROJECT_ID.iam.gserviceaccount.com \
     --role roles/cloudprofiler.agent
gcloud projects add-iam-policy-binding $PROJECT_ID \
     --member serviceAccount:petclinic@$PROJECT_ID.iam.gserviceaccount.com \
     --role roles/clouddebugger.agent
gcloud projects add-iam-policy-binding $PROJECT_ID \
     --member serviceAccount:petclinic@$PROJECT_ID.iam.gserviceaccount.com \
     --role roles/cloudtrace.agent
gcloud projects add-iam-policy-binding $PROJECT_ID \
     --member serviceAccount:petclinic@$PROJECT_ID.iam.gserviceaccount.com \
     --role roles/spanner.databaseUser
```

Create a new JSON Service Account Key. Keep it secure!

```bash
gcloud iam service-accounts keys create ~/petclinic-service-account.json \
    --iam-account petclinic@$PROJECT_ID.iam.gserviceaccount.com
```

## Build

### Update pom.xml with our GCR repo

We need to edit pom.xml to use our docker registry. In between <docker.image.prefix> and </docker.image.prefix> and plug in your own registry like gcr.io/$PROJECT_ID.

```bash
sed -i 's/REPO/gcr.io\/${PROJECT_ID}/g' pom.xml
```

### Compile and Install to Maven

```bash
./mvnw install
```

### Build Docker Images

Build all images:

```bash
./mvnw package install -PbuildDocker
```

Build just one image:

```bash
./mvnw package install -PbuildDocker -pl spring-petclinic-customers-service
```

## Run

### Docker Compose

Update `docker-compose.yml` file so that `secrets.petclinic-credentials.file`
points to the JSON file.

To run the docker images on your machine, we will execute `docker-compose`:

```bash
echo "PROJECT_ID=$PROJECT_ID" > .env
docker-compose up
```

### Kubernetes

Store Service Account as a Kubenetes Secret:

```bash
kubectl create secret generic petclinic-credentials --from-file=$HOME/petclinic-service-account.json
```

Update yaml files to use your GCR repo:

```bash
for i in $(ls); do sed -i 's/REPO/gcr.io\/${PROJECT_ID}/g' $i; done
```

Deploy Application:

```bash
kubectl apply -f kubernetes/
```

### Try It Out

Find the Ingress IP address (it may take a few second)

```bash
kubectl get svc istio-ingressgateway -n istio-system
NAME                   TYPE           CLUSTER-IP EXTERNAL-IP                                                                                                                              istio-ingressgateway   LoadBalancer   X.X.X.X   <Your IP>
```

Open the browser to see if the app is working!

## Travis CI/CD

Install the Travis CLI:

```bash
brew install travis
```

Or, follow the [Travis CLI Installation instruction](https://github.com/travis-ci/travis.rb#installation)

Login to Travis

```bash
travis login
```

Or, optionally login with `travis login --github-token=...` to avoid typing password, etc.

Configure Docker credentials:

```bash
travis env set DOCKER_USERNAME your_username
travis env set DOCKER_PASSWORD your_password
```

Create a CI/CD Service Account, assign roles, and create a JSON file:

```bash
$ gcloud iam service-accounts create travis-ci --display-name "Travis CI/CD"
$ gcloud projects add-iam-policy-binding $PROJECT_ID \
     --member serviceAccount:travis-ci@$PROJECT_ID.iam.gserviceaccount.com \
     --role roles/container.developer
$ gcloud iam service-accounts keys create ~/travis-ci-petclinic.json \
    --iam-account travis-ci@$PROJECT_ID.iam.gserviceaccount.com
```

Encrypt and Store the Travis CI/CD Service Account:

```bash
travis encrypt-file ~/travis-ci-petclinic.json
```

Travis asks you to add a line to `before_install` section. Make sure it's updated.

Set the Google Cloud Platform Project ID for reference in the build:

```bash
travis env set PROJECT_ID $PROJECT_ID
```

Commit `.travis.yml`
