#!/bin/sh

if [ $# -lt 2 ]
then
	echo "Usage: ./get-kubeconfig.sh <kubeconfig path> <output filename> <Optional: kubecontext> <Optional: cluster's server URL>"
	exit 1
fi

if [ $# -eq 3 ]
then
	echo "Invalid input params. Server URL is a mandatory input param if K8s context is provided."
	exit 1
fi

KUBECONFIG_FILE_PATH=$1
OUTPUT_FILE=$2
CONTEXT=$3
SERVER_URL=$4

export KUBECONFIG=$KUBECONFIG_FILE_PATH

# If context is provided, set it
if [ -n "$CONTEXT" ]
then
  kubectl config use-context $CONTEXT
  if [ $? -ne 0 ]
  then
    echo "Error occurred in setting context"
    exit 1
  fi

fi

# This clean up function is called to clean up all resources that were created as part of this script.
clean_up()
{
  kubectl delete sa cnsmanager-sa > /dev/null 2>&1
  kubectl delete ClusterRole cnsmanager-sa-role > /dev/null 2>&1
  kubectl delete ClusterRoleBinding cnsmanager-sa-rb > /dev/null 2>&1
  kubectl config delete-user cnsmanager-sa > /dev/null 2>&1
  rm -f cnsmanagerrbac.yaml > /dev/null 2>&1
  rm -f cnsmanagerkubeconfig > /dev/null 2>&1
  rm -f secret_output > /dev/null 2>&1
  rm cnsmanagerkubeconfig.bak > /dev/null 2>&1
}

# Clean up env before proceeding
clean_up

echo "Starting creation of kubeconfig..."

# Create service account for kubeconfig
kubectl create sa cnsmanager-sa
if [ $? -ne 0 ]
then
	echo "Failed to create service account. Cleaning up resources before exiting."
	clean_up
	exit 1
fi

token_secretname=$(kubectl get secret 2> /dev/null | grep "cnsmanager-sa-token" | awk '{print $1}')

# Contents of token secret if required to be created explicitly
cat <<EOF > cnsmanager-token-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: cnsmgr-sa-token
  annotations:
    kubernetes.io/service-account.name: cnsmanager-sa
type: kubernetes.io/service-account-token
EOF

# If token secret is not autogenerated, create it
if [ -z "$token_secretname" ]
then
  token_secretname="cnsmgr-sa-token"
  # Create token secret for cnsmanager-sa
  kubectl apply -f cnsmanager-token-secret.yaml
  if [ $? -ne 0 ]
    then
	  echo "Failed to create token secret for service account. Cleaning up resources before exiting."
	  clean_up
	  exit 1
  fi
fi

sleep 3

# Get the token secret created for CNS manager SA
kubectl get secret $token_secretname -oyaml > secret_output
if [ $? -ne 0 ]
then
  echo "Failed to find token secret for cnsmanager service account. Cleaning up resources before exiting."
  clean_up
  exit 1
fi

token=$(cat secret_output | grep "token:" | awk -F ' ' '{print $2}' | base64 -d)

# Set config for cns manager SA
kubectl config set-credentials cnsmanager-sa --token=$token
if [ $? -ne 0 ]
then
  echo "Failed to set credentials in config. Cleaning up resources before exiting"
  clean_up
  exit 1
fi

# Extract values needed to contruct canmanager kubeconfig
clusterAuthData=$(cat secret_output | grep "ca.crt:" | awk -F ' ' '{print $2}')

# If server URL was provided in input, we don't need to extract it from kubeconfig file
if [ -z $SERVER_URL ]
then

  num_of_clusters=$(cat $KUBECONFIG_FILE_PATH | grep -c "server:")

  if [ $num_of_clusters -ne 1 ]
  then
    echo "Invalid configuration provided. If multiple clusters are concerned, provide the context and server URL also in input parameters."
    clean_up
    exit 1
  fi

  serverUrl=$(cat $KUBECONFIG_FILE_PATH | grep "server:" | awk -F ' ' '{print $2}')
else
  serverUrl=$SERVER_URL
fi

cat <<EOF > cnsmanagerkubeconfig
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: clusterAuthDataPlaceholder
    server: serverUrlPlaceholder
  name: cnsmgr-cluster
contexts:
- context:
    cluster: cnsmgr-cluster
    user: cnsmanager-sa
  name: cnsmanager-sa
current-context: cnsmanager-sa
users:
- name: cnsmanager-sa
  user:
    token: tokenPlaceholder
EOF

sed -i'.bak' -e "s~clusterAuthDataPlaceholder~$clusterAuthData~g" cnsmanagerkubeconfig
sed -i'.bak' -r "s~serverUrlPlaceholder~$serverUrl~g" cnsmanagerkubeconfig
sed -i'.bak' -e "s/tokenPlaceholder/$token/g" cnsmanagerkubeconfig

cat <<EOF > cnsmanagerrbac.yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cnsmanager-sa-role
rules:
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["clusterroles"]
  verbs: ["get", "list", "update", "escalate", "patch", "delete"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["persistentvolumes"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
- apiGroups: ["cns.vmware.com"]
  resources: ["cnsvspherevolumemigrations"]
  verbs: ["get", "list"]
- apiGroups: ["cns.vmware.com"]
  resources: ["csinodetopologies"]
  verbs: ["list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cnsmanager-sa-rb
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cnsmanager-sa-role
subjects:
- kind: ServiceAccount
  name: cnsmanager-sa
  namespace: default
EOF

# Apply RBAC rules
kubectl create -f cnsmanagerrbac.yaml
if [ $? -ne 0 ]
then
  echo "Failed to create RBAC rules. Cleaning up resources before exiting"
  clean_up
  exit 1
fi

echo "\n"
cat cnsmanagerkubeconfig > $OUTPUT_FILE
echo "Generated kubeconfig stored in output file $OUTPUT_FILE"
echo '\n'

rm cnsmanagerrbac.yaml
rm cnsmanagerkubeconfig
rm secret_output
rm cnsmanager-token-secret.yaml
rm cnsmanagerkubeconfig.bak
