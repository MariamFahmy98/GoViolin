# Table of contents
* [Building a multi-stage docker image of the application](#building-a-multi\-stage-docker-image-of-the-application)
* [Creating Kubernetes manifests for GoViolin application](#creating-kubernetes-manifests-for-goviolin-application)
* [Deploying Nginx Ingress Controller on Kubernetes using Helm Chart](#deploying-nginx-ingress-controller-on-kubernetes-using-helm-chart)
* [Deploying Kubernetes to AWS using kOps](#deploying-kubernetes-to-aws-using-kops)
* [CI/CD pipeline stages](#cicd-pipeline-stages)

# Building a multi-stage docker image of the application
A docker image is created for GoViolin application using multi-stage builds:
- The first stage:
  - It uses ```golang:1.17.3``` as its base image.
  - It copies both ```go.mod``` and ```go.sum``` into the container's file system.
  - It runs ```go get -d -v ./...``` to update/pull the golang app dependencies.
  - It copies all project files into the container's file system.
  - It runs ```CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o GoViolin .``` to compile the application for Linux to run on Alpine.
- The second stage:
  - It uses ```alpine:latest``` as its base image.
  - It copies the compiled binary from the builder stage (the first stage).
  - It copies the required static files from the source code as it isn't included in the compiled binary.
  - It runs the container's main process which is ```./GoViolin``` on port 3000.

To build docker image: ```docker build -t mariamfahmy98/go-violin-app:latest .```                                                       
To run a container from the application's image: ```docker run --name goviolin-app -d -p 3000:3000 mariamfahmy98/go-violin-app```

# Creating Kubernetes manifests for GoViolin application
To deploy GoViolin application into kubernetes cluster, the following K8s resources are created:
- Deployment:
  - A Deployment named ```go-violin-deployment``` is created. It is responsible for creating a ReplicaSet to bring up one replica pod which runs a container from the application's image. The Pod have a container that is listening on TCP port 3000.
  - It defines a liveness HTTP request, as a result kubelet will send an HTTP GET request to the server that is running in the container and listening on port 3000, If the handler for the server's ```/duets``` path returns a success code, kubelet will consider the containter to be running and healthy, otherwise kubelet will kill the container and it will apply the restart policy.
  - It defines a readiness probe where the Pod will not be marked as "Ready" before it will be possible to connect to port 3000 of the container. The first check/probe will start after 10 seconds from the moment the container started to run and will continue to run the check/probe every 5 seconds until it will manage to connect to the defined port.
  
- Service:
  - A ClusterIP service is used to enable internal communication and prevent any external access, it is called ``` go-violin-service```.
  - Clients in the cluster call the Service by using the cluster IP address and the TCP port 3000 specified by ```port``` field and then the request is forwarded to the pod on the TCP port specified in the ```targetPort``` field which is the same port that the container is listening on.
  
- Ingress:
  - It exposes HTTP routes from outside the cluster to the service within the cluster.
  - It routes requests from the host ```go-violin.mariamfahmy.rocks``` to ```/``` to the ClusterIP service ``` go-violin-service```.

# Deploying Nginx Ingress Controller on Kubernetes using Helm Chart
- Without Ingress controller, Ingress resource does nothing as the ingress controller does the actual routing by reading the routing rules from ingress resource stored in etcd. It fulfils the ingress with a LoadBalancer.
- To deploy Nginx Ingress controller on K8s using helm chart:
```
helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update
helm install nginx-ingress-controller nginx-stable/nginx-ingress
```
- Helm applies the ingress controller manifests by communicating with the kube api server.
- The kube api server recieves the request from the ingress controller and stores it in etcd.
- The Kubernetes controller will change the actual state of the cluster to the desired state.

Therefore, A Load Balancer will be created which will route the HTTP requests from the URL: ```go-violin.mariamfahmy.rocks``` to our ClusterIP service, this is done by reading the ingress resource rules stored in the etcd.

<b> Note: In AWS, a new route record is added in order to map the ```go-violin.mariamfahmy.rocks``` with the IP address of Ingress Controller Load Balancer.</b>

# Deploying Kubernetes to AWS using kOps
  Kops creates a highly-available cluster, and deploy it into AWS. Behind the scenes Kops creates the VPC and subnet for the cluster, Auto Scaling Groups for the master and the worker node, Launch Configurations for those nodes, EBS volumes for the EC2 instances, and security groups for the network as well as a Load Balancer to be able to communicate with the kube api server by using kubectl.
  - Kops Installation:
  ```
  curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4
  curl -Lo kops https://github.com/kubernetes/kops/releases/download/v1.23.2/kops-linux-amd64
  chmod +x kops
  sudo mv kops /usr/local/bin/kops
  ```
  - Configure S3 buckets to store the Kubernetes cluster configuration:
  ```
  aws s3api create-bucket --bucket mariam-kops-state
  aws s3api put-bucket-versioning --bucket mariam-kops-state --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption --bucket mariam-kops-state --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  export KOPS_STATE_STORE=s3://mariam-kops-state
  ```
  - Creating Kops cluster (inside kops-cluster directory):
  ```
  kops create cluster --name=cluster.mariamfahmy.rocks --cloud=aws --zones=us-east-1a --image=099720109477/ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-20220509 --node-count=1 --networking=calico --dry-run -oyaml > kops-config.yaml
  kops update cluster --name cluster.mariamfahmy.rocks --yes
  kops export kubeconfig cluster.mariamfahmy.rocks --admin
  ```
  To check the kops cluster is running: ```kubectl get nodes```
  - Applying k8s manifests (inside k8s directory):
  ```
  kubectl apply -f .
  ```
  
# CI/CD pipeline stages
  - <b> Building stage:</b>           
  It builds a docker image for the GoViolin application by running ```docker build -t $DOCKER_USERNAME/go-violin-app:latest .```
  - <b> Login stage:</b>                                          
  It logs into dockerhub by running ```docker login --username $DOCKER_USERNAME --password $DOCKER_PASSWORD```
  - <b> Pushing stage:</b>                                  
  It pushes to docker repository by running ```docker push $DOCKER_USERNAME/go-violin-app:latest```
  - <b> Deploying stage:</b>                                                   
  It deploys the GoViolin application to kops cluster by running ```kubectl apply --kubeconfig=${params.kubeConfig} -f kubernetes/deployment.yaml -f kubernetes/service.yaml```

<b> In case of sucess/failure builds, an email is sent to the developer to be notified. </b>
