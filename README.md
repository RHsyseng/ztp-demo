# ztp-demo
Demo to showcase the capabilities of ZTP.

We will execute this demo in virtual, and we ecourage to use kcli to prepare the VMs accordingly.

## Demo pre reqs

We need to have some things previously in order to go through the demo

- Hub Deployment
- Some PVs available
- Some Nodes to deploy the Edge Cluster
- DNS entries properly configured for Ingress and Api on Hub and Spoke cluster

In case of Virtual configuration

- SushyTools to manage the VMs using a BMC Emulator

## Demo 

- Create a temporary folder to hold the objects

```
cd /var/tmp
mkdir ztp && cd ztp
```

### RHACM

- Deploy RHACM Using the manifests located into hub/manifests/RHACM/

```
cd /var/tmp/ztp
git clone //github.com/RHsyseng/ztp-demo.git
oc apply -f ztp-demo/hub/manifests/RHACM/RHACM-Sub.yaml
```

Wait for some time until the RHACM Operator finishes the deployment, then:

```
oc apply -f ztp-demo/hub/manifests/RHACM/RHACM-Operand.yaml
```

Wait for some time until the RHACM MultiClusterHub finishes, then deploy the AgentServiceConfig for Infrastructure Operator:

```
oc apply -f ztp-demo/hub/manifests/RHACM/RHACM-AgentServiceConfig.yaml
```

### GitOps Operator

- Deploy the GitOps Operator using [this](https://github.com/openshift-kni/cnf-features-deploy/tree/master/ztp/gitops-subscriptions/argocd)

```
cd /var/tmp/ztp
git clone https://github.com/openshift-kni/cnf-features-deploy.git
cd cnf-features-deploy/tree/master/ztp/gitops-subscriptions/argocd
oc apply -f deployment/openshift-gitops-operator.yaml
```

### PolicyGen

- Extract the files from cnf-features-deploy:

```
cd /var/tmp/ztp
mkdir -p ./out
podman run --rm quay.io/openshift-kni/ztp-site-generator:latest extract /home/ztp --tar | tar x -C ./out
```

- Patch the GitOps Operator

```
oc patch argocd openshift-gitops -n openshift-gitops  --type=merge --patch-file out/argocd/deployment/argocd-openshift-gitops-patch.json
```

- Access Argo UI and add the repo: https://github.com/RHsyseng/ztp-demo.git
- update yamls from `out/argocd/deployment`, more concretelly, `policies-app.yaml`:

- clusters-app.yaml
```
  source:
    path: ztp/site-config
    repoURL: https://github.com/RHsyseng/ztp-demo
    targetRevision: main
```

- policies-app.yaml

```
  source:
    path: ztp/site-policies
    repoURL: https://github.com/RHsyseng/ztp-demo
    targetRevision: main
```

### Demo Bootstrapping

Now we need to create some necessary and private objects like PullSecrets, BMC Secrets (with Username and Passwords) and Namespaces, we don't recommend to store them into a git repo, this is why we generate them on the fly.

To do that:

```
cd /var/tmp/ztp/ztp-demo/ztp
```

Edit the `config/env` file accordingly.

NOTE: We've assummed that all the BMCs has the same user/pass for the demo purposes, if that's not the case, you will need to modify them accordingly. So after the execute of the `bootstrap.sh` script you will need to modify those secrets with `echo -n 'BLAHBLAH' | base64` and replace the string into the cluster assets folder which will be in `/var/tmp/ztp/ztp-demo/out` once you executed the script.

Then execute the `bootstrap.sh` script with the KUBECONFIG loaded as an env var:

```
cd /var/tmp/ztp/ztp-demo/ztp
./bootstrap.sh
```

This will be the output:
```
$ ./bootstrap.sh
>> Rendering assets for spoke0-cluster in ./../out/spoke0-cluster
namespace/spoke0-cluster created
secret/alk-lab-pull-secret created
secret/master0-spoke0-cluster-bmh-secret created
secret/master1-spoke0-cluster-bmh-secret created
secret/master2-spoke0-cluster-bmh-secret created
namespace/spoke0-cluster unchanged
secret/rh-lab-pull-secret created
>> Done!

>> Rendering assets for alk-lab in ./../out/alk-lab
namespace/alk-lab unchanged
namespace/alk-lab unchanged
secret/alk-lab-pull-secret configured
secret/master0-alk-lab-bmh-secret unchanged
secret/master1-alk-lab-bmh-secret unchanged
secret/master2-alk-lab-bmh-secret unchanged
>> Done!
```

Then apply all the folder using Kustomize, which will trigger the whole automation:

```
cd /var/tmp/ztp
oc apply -k out/argocd/deployment/
```

This will deploy an ArgoApplication which will take care of the GitOps part.

## Following the progress

- To follow the Cluster manifests rendering go to the ArgoCD UI, in our case: [ArgoCD](https://openshift-gitops-server-openshift-gitops.apps.test-ci.alklabs.com/applications?proj=&sync=&health=&namespace=&cluster=&labels=) 
- To follow the Cluster deployment got to the RHACM UI, in our case: [RHACM Clusters](https://multicloud-console.apps.test-ci.alklabs.com/multicloud/clusters)
- If the Cluster deployment are not progressing, check the `aci` and `infraenv` objects in the spoke0-cluster ` oc get aci -n spoke0-cluster spoke0-cluster -o yaml` or `oc get infranev -n spoke0-cluster spoke0-cluster -o yaml`
- To check the RHACM Polcies being deployed by ArgoCD, check the Applications tab into the RHACM UI, in our case: [RHACM Applications](https://multicloud-console.apps.test-ci.alklabs.com/multicloud/applications/)
- To follow the policies propagation check the Governance tab into the RHACM UI, in our case: [RHACM Governance](https://multicloud-console.apps.test-ci.alklabs.com/multicloud/policies/all)


You also has the `img` folder which contains some useful screenshots about how should looks like the environment after the deployment

Hope you liked the demo.

Enjoy
