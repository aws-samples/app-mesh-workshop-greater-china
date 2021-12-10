# App Mesh with EKS—基础部署

这部分将涵盖在EKS中使用AppMesh的基础设置。

## 先决条件

为确保后续内容顺利进行，请核对以下内容已经正确部署：

- 请确保安装了最新的 [AWS CLI](https://aws.amazon.com/cli/)，即 `1.18.82` 或更高版本。
- 请确保安装了最新的 [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)，即 `1.13` 或更高版本。
- 请确保已经安装了 [jq](https://stedolan.github.io/jq/download/)。
- 请确保`helm` 已经[安装](https://helm.sh/docs/intro/install/)。
- 安装 [eksctl](https://eksctl.io/). 请参阅 [附录](#附录) 以获取eksctl安装说明。请确保您安装了0.21.0或更高版本。

请配置实验所在区域，例如`us-west-2`或`cn-northwest-1`:

```
export AWS_DEFAULT_REGION=$REGION_ID
```

## 集群配置

使用以下命令，通过`eksctl`创建一个EKS集群：

```
eksctl create cluster \
--name appmeshtest \
--nodes-min 2 \
--nodes-max 3 \
--nodes 2 \
--auto-kubeconfig \
--full-ecr-access \
--appmesh-access
# ...
# [✔]  EKS cluster "appmeshtest" in "us-west-2" region is ready
```

完成后，根据`eksctl`的输出更新`KUBECONFIG`环境变量：

```
export KUBECONFIG=~/.kube/eksctl/clusters/appmeshtest
```

## 安装App Mesh Kubernetes组件

为了在Pod创建时自动注入App Mesh组件和代理，我们需要在集群上创建一些自定义资源。为此，我们将使用 *helm*。

*代码仓库*

将克隆代码仓库到适当的目录，然后cd目录中，我们将从该路径运行所有命令。
```
git clone https://github.com/aws/aws-app-mesh-examples.git
cd aws-app-mesh-examples/walkthroughs/eks/
```

*安装App Mesh组件*

运行以下命令集以安装App Mesh控制器（controller）

```
# 添加eks charts repo 到本地 helm
helm repo add eks https://aws.github.io/eks-charts
# 安装 appmesh controller CRDS
kubectl apply -k "https://github.com/aws/eks-charts/stable/appmesh-controller/crds?ref=master"
# 创建 namespace appmesh-system
kubectl create ns appmesh-system

```

为集群创建 OpenID Connect (OIDC) 身份提供程序

```
eksctl utils associate-iam-oidc-provider \
    --region=$AWS_DEFAULT_REGION \
    --cluster appmeshtest \
    --approve
```

创建对应的 IAM Role

```

eksctl create iamserviceaccount \
    --cluster appmeshtest \
    --namespace appmesh-system \
    --name appmesh-controller \
    --attach-policy-arn  arn:aws:iam::aws:policy/AWSCloudMapFullAccess,arn:aws:iam::aws:policy/AWSAppMeshFullAccess \
    --override-existing-serviceaccounts \
    --approve
```

安装 appmesh controller

```
helm upgrade -i appmesh-controller eks/appmesh-controller \
    --namespace appmesh-system \
    --set region=$AWS_DEFAULT_REGION \
    --set serviceAccount.create=false \
    --set serviceAccount.name=appmesh-controller
```

如果在亚马逊云科技中国区域部署，可能会遇到拉取镜像失败的问题。
使用下面的命令更换亚马逊云科技中国区容器镜像
#TODO
```
helm upgrade -i appmesh-controller eks/appmesh-controller \
    --namespace appmesh-system \
    --set region=$AWS_DEFAULT_REGION \
    --set serviceAccount.create=false \
    --set serviceAccount.name=appmesh-controller \
    --set image.repository=961992271922.dkr.ecr.cn-northwest-1.amazonaws.com.cn/amazon/appmesh-controller \
    --set init.image.repository=048912060910.dkr.ecr.cn-northwest-1.amazonaws.com.cn/aws/appmesh/aws-appmesh-proxy-route-manager \
    --set init.iamge.tag=v3-prod \
    --set sidecar.image.repository=048912060910.dkr.ecr.cn-northwest-1.amazonaws.com.cn/aws/appmesh/aws-appmesh-envoy \
    --set sidecar.image.tag=v1.19.1.0-prod
```

验证

```
kubectl get deployment appmesh-controller \
    -n appmesh-system -owide
```

详情可以参考：[https://docs.aws.amazon.com/zh_cn/app-mesh/latest/userguide/getting-started-kubernetes.html#install-controller](https://docs.aws.amazon.com/zh_cn/app-mesh/latest/userguide/getting-started-kubernetes.html#install-controller)


目前，一切就绪，您已经配置了EKS集群并设置了App Mesh组件，这些组件能够自动向Pod注入Envoy并负责App Mesh资源（如Mesh，虚拟节点，虚拟服务和虚拟路由器）的生命周期管理。

此时，您可能还需要检查App Mesh Controller使用的自定义资源：


```
kubectl api-resources --api-group=appmesh.k8s.aws
# NAME              SHORTNAMES   APIGROUP          NAMESPACED   KIND
# meshes                         appmesh.k8s.aws   false        Mesh
# virtualnodes                   appmesh.k8s.aws   true         VirtualNode
# virtualrouters                 appmesh.k8s.aws   true         VirtualRouter
# virtualservices                appmesh.k8s.aws   true         VirtualService
```

## 示例应用(可选)

如果完成了上面的内容，可以使用示例应用验证集群。[howto-k8s-http2](../howto-k8s-http2/) 来演示将App Mesh与EKS结合使用的方法。


确保使用以下命令创建了所有资源：
```
kubectl -n appmesh-system get deploy,po,svc

NAME                                 READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/appmesh-controller   1/1     1            1           19h

NAME                                      READY   STATUS    RESTARTS   AGE
pod/appmesh-controller-5954995557-tsnf9   1/1     Running   0          19h

NAME                                         TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)              AGE
service/appmesh-controller-webhook-service   ClusterIP   10.100.18.188    <none>        443/TCP              19h
```

```
kubectl get pod -n howto-k8s-http2 -o wide

NAME                      READY   STATUS    RESTARTS   AGE     IP               NODE                                          NOMINATED NODE   READINESS GATES
blue-64885d7dd6-bjlx5     2/2     Running   0          3m48s   192.168.83.144   ip-192-168-70-3.us-west-2.compute.internal    <none>           1/1
client-6ddfdd884d-l9nvv   2/2     Running   0          3m49s   192.168.87.223   ip-192-168-70-3.us-west-2.compute.internal    <none>           1/1
green-5674cfb556-65qch    2/2     Running   0          3m48s   192.168.1.139    ip-192-168-4-114.us-west-2.compute.internal   <none>           1/1
red-5bf7f49fbd-86f54      2/2     Running   0          3m49s   192.168.82.36    ip-192-168-70-3.us-west-2.compute.internal    <none>           1/1
```

现在，使用aws CLI验证服务网格的创建情况：

```
aws appmesh list-meshes

# {
#    "meshes": [
#        {
#            "arn": "arn:aws:appmesh:us-west-2:1234567890:mesh/howto-k8s-http2",
#            "createdAt": 1592578534.868,
#            "lastUpdatedAt": 1592578534.868,
#            "meshName": "howto-k8s-http2",
#            "meshOwner": "1234567890",
#            "resourceOwner": "1234567890",
#            "version": 1
#        }
#    ]
# }

aws appmesh list-virtual-services --mesh-name howto-k8s-http2

# {
#    "virtualServices": [
#        {
#            "arn": "arn:aws:appmesh:us-west-2:1234567890:mesh/howto-k8s-http2/virtualService/color.howto-k8s-http2.svc.cluster.local",
#            "createdAt": 1592578534.971,
#            "lastUpdatedAt": 1592578535.237,
#            "meshName": "howto-k8s-http2",
#            "meshOwner": "1234567890",
#            "resourceOwner": "1234567890",
#            "version": 2,
#            "virtualServiceName": "color.howto-k8s-http2.svc.cluster.local"
#        }
#    ]
# }

aws appmesh list-virtual-nodes --mesh-name howto-k8s-http2

# {
#    "virtualNodes": [
#        {
#            "arn": "arn:aws:appmesh:us-west-2:1234567890:mesh/howto-k8s-http2/virtualNode/green_howto-k8s-http2",
#            "createdAt": 1592578534.934,
#            "lastUpdatedAt": 1592578534.934,
#            "meshName": "howto-k8s-http2",
#            "meshOwner": "1234567890",
#            "resourceOwner": "1234567890",
#            "version": 1,
#            "virtualNodeName": "green_howto-k8s-http2"
#        },
#        {
#            "arn": "arn:aws:appmesh:us-west-2:1234567890:mesh/howto-k8s-http2/virtualNode/client_howto-k8s-http2",
#            "createdAt": 1592578534.965,
#            "lastUpdatedAt": 1592578534.965,
#            "meshName": "howto-k8s-http2",
#            "meshOwner": "1234567890",
#            "resourceOwner": "1234567890",
#            "version": 1,
#            "virtualNodeName": "client_howto-k8s-http2"
#        },
#        {
#            "arn": "arn:aws:appmesh:us-west-2:1234567890:mesh/howto-k8s-http2/virtualNode/blue_howto-k8s-http2",
#            "createdAt": 1592578534.929,
#            "lastUpdatedAt": 1592578534.929,
#            "meshName": "howto-k8s-http2",
#            "meshOwner": "1234567890",
#            "resourceOwner": "1234567890",
#            "version": 1,
#            "virtualNodeName": "blue_howto-k8s-http2"
#        },
#        {
#            "arn": "arn:aws:appmesh:us-west-2:1234567890:mesh/howto-k8s-http2/virtualNode/red_howto-k8s-http2",
#            "createdAt": 1592578534.91,
#            "lastUpdatedAt": 1592578534.91,
#            "meshName": "howto-k8s-http2",
#            "meshOwner": "1234567890",
#            "resourceOwner": "1234567890",
#            "version": 1,
#            "virtualNodeName": "red_howto-k8s-http2"
#        }
#    ]
# }

aws appmesh list-virtual-routers --mesh-name howto-k8s-http2

# {
#     "virtualRouters": [
#        {
#            "arn": "arn:aws:appmesh:us-west-2:1234567890:mesh/howto-k8s-http2/virtualRouter/color_howto-k8s-http2",
#            "createdAt": 1592578535.039,
#            "lastUpdatedAt": 1592578535.039,
#            "meshName": "howto-k8s-http2",
#            "meshOwner": "1234567890",
#            "resourceOwner": "1234567890",
#            "version": 1,
#            "virtualRouterName": "color_howto-k8s-http2"
#        }
#    ]
# }

```

您可以按以下方式访问应用程序集群中的`color`服务：

```
kubectl -n howto-k8s-http2 port-forward deployment/client 7000:8080 &

# Color virtual service uses the color virtual router with even distribution to 3 virtual nodes (red, blue, and green) over HTTP/2. Prove this by running the following command a few times:

curl localhost:7000/color ; echo;
red

curl localhost:7000/color ; echo;
green

curl localhost:7000/color ; echo;
blue
```

这样就完成了有关基础部署的工作。 现在，您可以继续进行第2天的操作任务，例如在EKS上将[CloudWatch](o11y-cloudwatch.md)与App Mesh一起使用.

## 清除

删除演示命名空间(namesapce)和Mesh自定义资源时，AWS App Mesh Controller会清理网格及其相关资源（虚拟节点，服务，虚拟路由器等），如下所示：

```
kubectl delete ns howto-k8s-http2 && kubectl delete mesh howto-k8s-http2
```

```
helm delete appmesh-controller -n appmesh-system
```


最后，使用以下方法释放EKS集群所有计算，网络和存储资源：

```
eksctl delete cluster --name appmeshtest
```


## 附录

### eksctl 安装说明

```
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp

sudo mv -v /tmp/eksctl /usr/local/bin
```

```
eksctl version
0.51.0
```
