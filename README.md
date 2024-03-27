# kubernetes-the-fox-way

Designed to test the compatibility of solutions with different versions and configurations 
of Kubernetes, as well as for educational and research purposes.
Deploy various kinds of PRIVATE self-managed Kubernetes cluster with NFS PV-volumes*
in GCP

All cluster nodes (including the control plane) will be deployed in private mode. 
Access to all cluster components and cluster management is carried out REMOTELY 
through a regular SSH connection to the bastion node and/or LOCALLY through an 
automatically created SSH tunnel loclahost->bastion->Control Plane. To make the 
first method easier, a fake FQDN "bastion.gcp" will be automatically added (and
 configured) to the local /etc/hosts file. It is highly recommended to add the path 
 to your ssh public key to the variable.tf file for easy SSH access.** The second method 
 will be configured completely automatically and will use the key pairs generated 
 during deployment. In BOTH modes, you can use any Kubernetes tools designed for 
 kubeconfig-managed access (kubectl, k9s, etc.). Accordingly configured kubeconfigs 
 will be automatically created and imported for BOTH access cases.

supported Kubernetes kinds:
- k8raw:  raw k8s(i.e. daemons-based Control Plane) - 3 masters ***
- k8adm:  kubeadm k8s - 1 master
- k3s:    runcher k3s - 3 masters


All of the following steps assume you already have:
- Local Linux machine (bare metal, WSL, Virtual Box, etc.) with Terraform and Git installed.
- active GCP user account
- GCP project with billing activated (e.g. trial version)
- At least  Editor role rights in this project for chosen access way,
 which can be one of :
a) Configured Application Default Credentials (ADC) for your user account 
(read https://cloud.google.com/docs/authentication/provide-credentials-adc)
OR
b) Access key(i.e. kind of special json file) for any Service Account (in this project),
generated via GCP console and downloaded locally  

By default, project files are configured for ADC access mode. To use the Service Account
access instead ADC you need to uncomment (and edit) the corresponding lines in the files:
- variables.tf
- maint.tf

#QUICK START:

- Enabled APIs for Compute Engine ad Filestore services (use GCP console) if not yet.

- clone repository:

 git clone https://github.com/shakhor-shual/kubernetes-the-fox-way.git

- go to the project's working folder

cd kubernetes-the-fox-way/kuberntes-deploy-gcp

- MANDATORY: modify (in variables.tf)  ALL strings looks like: default="CHANGE-IT-TO-YOURS!" 
 to yours real settings(you ca use "nano" or any another editor)
- ADDITIONAL: modify any another defaults accordingly your requirements:

nano variables.tf    
- Deploy all needful infrastructure and bootstrap Kubernetes cluster:

terraform init && terraform apply

 - Access info for deployed cluster management will be printed
 in the finish of bootstrap process.
 ATTENTION: bootstrapping of cluster required at least 7-10 minutes ****

---------------------------------------------------------------------------------------
*NFS storage can be deployed on bastion or as a separate cloud service; the deployment 
type is selected automatically depending on the specified storage size in GB (value >=1024 
automatically creates a separate NFS storage on the cloud service). Using a dedicated NFS s
torage significantly lengthens the initial deployment process!

**Recommended to use k9s tool (pred-installed on bastion) for quick cluster 
manipulation via regular-SSH 
 
***k8raw - implies the use of Control Plane, compiled directly from Linux 
daemons, i.e. without wrapper-containers. Such solutions are described in detail 
in the kubernetes-the-hard-way guide and used in clouds for CP of managed clusters

****By default, all cluster kinds are deployed with two ingress controllers.
(Traefik on bastion and Nginx on nodes-ingress-0/1. Nginx uses an external TCP load 
balancer). The control planes for k8raw and K3s also use dedicated internal TCP load 
balancers. The initial cluster setup is done using manifests from the ./meta/manifests 
folder. ALL manifests placed in this folder will be automatically applied after the 
cluster boots up ONLY IF their file names begin with a number. Other manifest names 
are ignored. The order in which manifests are automatically applied follows the 
alphabetical sorting order of file names. To get a cluster with some basic custom 
initial settings, you can change the contents of this folder. 
For more complex configurations, Helm is recommended!
  
