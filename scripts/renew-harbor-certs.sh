#!/usr/bin/env bash
set -ex

TKG_LAB_SCRIPTS="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source $TKG_LAB_SCRIPTS/../scripts/set-env.sh

# if [ ! $# -eq 2 ]; then
#   echo "Must supply Mgmt and Shared Services cluster name as args"
#   exit 1
# fi

MGMT_CLUSTER_NAME=${1:=gg-sch-ess-mgmt}
SHAREDSVC_CLUSTER_NAME=${2:=gg-sch-ess-svcs}
VALUES_FILE="$TKG_LAB_SCRIPTS/generated/$SHAREDSVC_CLUSTER_NAME/harbor/harbor-data-values-test.yaml"

# Identifying Shared Services Cluster at TKG level
# kubectl config use-context $MGMT_CLUSTER_NAME-admin@$MGMT_CLUSTER_NAME
# kubectl label cluster.cluster.x-k8s.io/$SHAREDSVC_CLUSTER_NAME cluster-role.tkg.tanzu.vmware.com/tanzu-services="" --overwrite=true
# tanzu login --server $MGMT_CLUSTER_NAME
# tanzu cluster list --include-management-cluster

# We'll install Harbor in Shared Services Cluster
# kubectl config use-context $SHAREDSVC_CLUSTER_NAME-admin@$SHAREDSVC_CLUSTER_NAME

export HARBOR_CN=$(yq e .harbor.harbor-cn $PARAMS_YAML)

# Since TKG 1.3 the Notary FQDN is forced to be "notary."+harbor-cn
export NOTARY_CN="notary."$HARBOR_CN

# Create a staging folder if it doesn't exist
[[ -d generated/$SHAREDSVC_CLUSTER_NAME/harbor ]] || mkdir -p generated/$SHAREDSVC_CLUSTER_NAME/harbor

# TODO: Create certificate 02-certs.yaml if one doesn't exist
# cp tkg-extensions-mods-examples/registry/harbor/02-certs.yaml generated/$SHAREDSVC_CLUSTER_NAME/harbor/02-certs.yaml
# yq e -i ".spec.commonName = env(HARBOR_CN)" generated/$SHAREDSVC_CLUSTER_NAME/harbor/02-certs.yaml
# yq e -i ".spec.dnsNames[0] = env(HARBOR_CN)" generated/$SHAREDSVC_CLUSTER_NAME/harbor/02-certs.yaml
# yq e -i ".spec.dnsNames[1] = env(NOTARY_CN)" generated/$SHAREDSVC_CLUSTER_NAME/harbor/02-certs.yaml
# kubectl apply -f generated/$SHAREDSVC_CLUSTER_NAME/harbor/02-certs.yaml
# # Wait for cert to be ready
# while kubectl get certificates -n tanzu-system-registry harbor-cert | grep True ; [ $? -ne 0 ]; do
# 	echo Harbor certificate is not yet ready
# 	sleep 5
# done

# Read Harbor certificate details and store in files
export HARBOR_CERT_CRT=$(kubectl get secret harbor-cert-tls -n tanzu-system-registry -o=jsonpath={.data."tls\.crt"} | base64 --decode)
export HARBOR_CERT_KEY=$(kubectl get secret harbor-cert-tls -n tanzu-system-registry -o=jsonpath={.data."tls\.key"} | base64 --decode)
export HARBOR_CERT_CA=$(cat keys/letsencrypt-ca.pem)


# Get Harbor Package version
# Retrieve the most recent version number.  There may be more than one version available and we are assuming that the most recent is listed last,
# thus supplying '-' as the index of the array
# echo "Retreiving Harbor versions..."
# export HARBOR_VERSION=$(tanzu package available list -oyaml | yq eval '.[] | select(.display-name == "harbor") | .latest-version' -)

# We won't wait for the package while there is an issue we solve with an overlay
WAIT_FOR_PACKAGE=false

# Prepare Harbor custom configuration
# image_url=$(kubectl -n tanzu-package-repo-global get packages harbor.tanzu.vmware.com."$HARBOR_VERSION" -o jsonpath='{.spec.template.spec.fetch[0].imgpkgBundle.image}')
# imgpkg pull -b $image_url -o /tmp/harbor-package
cp /tmp/harbor-package/config/values.yaml generated/$SHAREDSVC_CLUSTER_NAME/harbor/harbor-data-values.yaml

# Hardcode the version if we didn't find one
export HARBOR_VERSION=${HARBOR_VERSION:=2.5.3+vmware.1-tkg.1}

# To be used in the future. Initial tests show that this approach doesn't work in this script: 
# Our let's encrypt cert secret does not include the CA, and even if we manually create the k8s 
# Once https://github.com/vmware-tanzu/community-edition/issues/2942 is done 
# and the CA cert is properly passed to the core and other Harbor components it may work.
# export HARBOR_CERT_NAME="harbor-tls"
# yq e -i '.tlsCertificateSecretName = strenv(HARBOR_CERT_NAME)' ${VALUES_FILE}

yq e -i '.tlsCertificate."tls.crt" = strenv(HARBOR_CERT_CRT)' ${VALUES_FILE}
yq e -i '.tlsCertificate."tls.key" = strenv(HARBOR_CERT_KEY)' ${VALUES_FILE}

# secret with the ca.crt it does not work if it's not called harbor-tls
yq e -i '.tlsCertificate."ca.crt" = strenv(HARBOR_CERT_CA)' ${VALUES_FILE}

# Remove all comments
yq -i eval '... comments=""' ${VALUES_FILE}

# Create Harbor using modifified Extension
tanzu package installed update harbor \
    --package-name harbor.tanzu.vmware.com \
    --version $HARBOR_VERSION \
    --namespace tanzu-kapp \
    --values-file ${VALUES_FILE} \
    --wait=$WAIT_FOR_PACKAGE \
	--install


	## 1. Get values of Cert from `harbor-cert-tls` lines 46-48
	## 2. Update harbor values file with new cert from CA lines 75-79
	## 3. tanzu package install line 85-91