set -euo pipefail

INT-NAME=${1}
KUBECONFIG=${2}
BASEDIR=$(dirname "$0")

if [[ -z ${INT-NAME} ]];then
	echo "First Param: Tell me the interface name where the NFS will be exposed"
	exit 1
fi

if [[ -z ${KUBECONFIG} ]];then
	echo "Second Param: Put the Kubeconfig location to create the PVs"
	exit 1
fi

export PRIMARY_IP=$(ip -o -4 addr show ${INT-NAME} |head -1 | awk '{print $4}' | cut -d'/' -f1)
systemctl enable --now firewalld || true
firewall-cmd --permanent --add-service mountd
firewall-cmd --permanent --add-service rpc-bind
firewall-cmd --permanent --add-service nfs
firewall-cmd --reload
systemctl enable --now nfs-server

export KUBECONFIG=${KUBECONFIG}
export MODE="ReadWriteOnce"

for i in `seq 1 20` ; do
    export PV=pv`printf "%03d" ${i}`
    mkdir -p /$PV
    echo "/$PV *(rw,no_root_squash)"  >>  /etc/exports
    chmod 777 /$PV
    [ "$i" -gt "10" ] && export MODE="ReadWriteMany"
    envsubst < ${BASEDIR}/nfs.yaml | oc apply -f -
done
exportfs -r

echo "Checking NFS"
showmount -e localhost

echo "Creating StorageClass"
oc create -f ${BASEDIR}/nfs-sc.yaml
