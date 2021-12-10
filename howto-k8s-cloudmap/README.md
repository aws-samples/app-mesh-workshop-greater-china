## 总览
本实验会介绍如何使用 App Mesh 和 AWS CloudMap 进行服务发现。AWS Cloud Map是一种云资源发现服务。借助 Cloud Map，可以为应用程序自定义资源名称，并维护这些动态变化的资源的更新情况。服务始终会发现其资源的最新位置，提高应用程序的可用性。

在此示例中，会部署两个CloudMap服务和三个K8s的Deployment，如下所述。

### Color

colorapp有两种Deployment，_blue_ 和 _red_。这两个Deployment的Pod都注册到服务colorapp.howto-k8s-cloudmap.pvt.aws.local。_blue_ Pod已在网格中注册为colorapp-blue虚拟节点（virtual-node），_red_ Pod已注册为colorapp-red虚拟节点（virtual-node）。这些虚拟节点使用AWS CloudMap实现服务发现，因此这些Pod的IP会注册到对应的CloudMap实现服务注册。

另外，定义了colorapp虚拟服务（virtual-service），该服务将流量路由到 _blue_ 和 _red_ 虚拟节点。

### Front

Front app充当网关，可调用colorapp。Front app包含一个Deployment，其中Pod已在服务网格中注册为 _front_ 虚拟节点。该虚拟节点使用colorapp虚拟服务作为后端。这会将注入到前端吊舱中的Envoy配置为使用App Mesh的EDS发现colorapp端点。Envoy注入到 _front_ 的这些配置，使其能够使用App Mesh的EDS(Endpoint Discovery Service)发现colorapp端点。

## 前提条件
1. [Walkthrough: App Mesh with EKS](../eks/)

2. v1beta2 示例 manifest 需要 [aws-app-mesh-controller-for-k8s](https://github.com/aws/aws-app-mesh-controller-for-k8s) 版本 [>=v1.0.0](https://github.com/aws/aws-app-mesh-controller-for-k8s/releases/tag/v1.0.0). 运行下面的命令去检查你运行的controller版本.
```
$ kubectl get deployment -n appmesh-system appmesh-controller -o json | jq -r ".spec.template.spec.containers[].image" | cut -f2 -d ':'|tail -n1
```

如果你 [aws-app-mesh-controller-for-k8s](https://github.com/aws/aws-app-mesh-controller-for-k8s) 版本是 [v0.3.0](https://github.com/aws/aws-app-mesh-controller-for-k8s/blob/legacy-controller/CHANGELOG.md)，你可以使用 v1beta1 示例 manifest

3. 安装Docker，示例需要构建演示应用的Docker image。

## 部署

1. 克隆此仓库，然后进入`walkthrough/howto-k8s-cloudmap`文件夹，所有的命令都是在此文件夹下运行。
2. 你的 **Account ID**:
    ```
    export AWS_ACCOUNT_ID=<your_account_id>
    ```
3. **区域 Region** e.g. cn-northwest-1
    ```
    export AWS_DEFAULT_REGION=cn-northwest-1
    ```
4. **(可选项) 指定 Envoy Image 版本** 如果要使用与[默认版本](https://github.com/aws/eks-charts/tree/master/stable/appmesh-controller#configuration)不同的Envoy 容器镜像，运行 `helm upgrade` 去覆盖 `sidecar.image.repository` 和 `sidecar.image.tag` 字段。

5. **VPC_ID** 环境变量设置为启动 Kubernetes pods 的VPC。VPC 讲用于通过`create-private-dns-namespace` API 在AWS中配置私有DNS namespace . 要查看EKS 集群所在的VPC，可以使用 `aws eks describe-cluster` 。关于为何Cloud Map需要 PrivateDnsNamespace，可以参考[文档](#1-how-can-i-use-cloud-map-namespaces-other-than-privatednsnamespace)。
    ```
    export VPC_ID=<vpc_id>
    ```
6. 部署
    ```.
    ./deploy.sh
    ```

## 验证

1. 使用 AWS Cloud Map DiscoverInstances API 查看被调用的 pods 信息。
   ```
   $ kubectl get pod -n howto-k8s-cloudmap -o wide
    NAME                             READY   STATUS    RESTARTS   AGE     IP               NODE                                           NOMINATED NODE   READINESS GATES
    colorapp-blue-6f99884fd4-2h4jt   2/2     Running   0          4m15s   192.168.10.38    ip-192-168-16-102.us-west-2.compute.internal   <none>           <none>
    colorapp-red-77d6565cc6-8btwz    2/2     Running   0          4m15s   192.168.34.225   ip-192-168-56-146.us-west-2.compute.internal   <none>           <none>
    front-5d96c9bfb6-d2zdx           2/2     Running   0          4m15s   192.168.59.249   ip-192-168-56-146.us-west-2.compute.internal   <none>           <none>

   $ aws servicediscovery discover-instances --namespace howto-k8s-cloudmap.pvt.aws.local --service front
    {
        "Instances": [
            {
                "InstanceId": "192.168.59.249",
                "NamespaceName": "howto-k8s-cloudmap.pvt.aws.local",
                "ServiceName": "front",
                "HealthStatus": "HEALTHY",
                "Attributes": {
                    "AWS_INIT_HEALTH_STATUS": "HEALTHY",
                    "AWS_INSTANCE_IPV4": "192.168.59.249",
                    "app": "front",
                    "k8s.io/namespace": "howto-k8s-cloudmap",
                    "k8s.io/pod": "front-5d96c9bfb6-d2zdx",
                    "pod-template-hash": "5d96c9bfb6",
                    "version": "v1"
                }
            }
        ]
    }

   $ aws servicediscovery discover-instances --namespace howto-k8s-cloudmap.pvt.aws.local --service colorapp --query-parameters "version=blue"
    {
        "Instances": [
            {
                "InstanceId": "192.168.10.38",
                "NamespaceName": "howto-k8s-cloudmap.pvt.aws.local",
                "ServiceName": "colorapp",
                "HealthStatus": "HEALTHY",
                "Attributes": {
                    "AWS_INIT_HEALTH_STATUS": "HEALTHY",
                    "AWS_INSTANCE_IPV4": "192.168.10.38",
                    "app": "colorapp",
                    "k8s.io/namespace": "howto-k8s-cloudmap",
                    "k8s.io/pod": "colorapp-blue-6f99884fd4-2h4jt",
                    "pod-template-hash": "6f99884fd4",
                    "version": "blue"
                }
            }
        ]
    }

   $ aws servicediscovery discover-instances --namespace howto-k8s-cloudmap.pvt.aws.local --service colorapp --query-parameters "version=red"
    {
        "Instances": [
            {
                "InstanceId": "192.168.34.225",
                "NamespaceName": "howto-k8s-cloudmap.pvt.aws.local",
                "ServiceName": "colorapp",
                "HealthStatus": "HEALTHY",
                "Attributes": {
                    "AWS_INIT_HEALTH_STATUS": "HEALTHY",
                    "AWS_INSTANCE_IPV4": "192.168.34.225",
                    "app": "colorapp",
                    "k8s.io/namespace": "howto-k8s-cloudmap",
                    "k8s.io/pod": "colorapp-red-77d6565cc6-8btwz",
                    "pod-template-hash": "77d6565cc6",
                    "version": "red"
                }
            }
        ]
    }
   ```

## FAQ
### 1. 我如何使用除PrivateDnsNamespace之外的Cloud Map命名空间？
AWS Cloud Map 支持三种 namespaces;
1. [PublicDnsNamespace](https://docs.aws.amazon.com/cloud-map/latest/api/API_CreatePublicDnsNamespace.html): Namespace 对互联网可用.
2. [PrivateDnsNamespace](https://docs.aws.amazon.com/cloud-map/latest/api/API_CreatePrivateDnsNamespace.html): Namespace 仅对指定的VPC内可用.
3. [HttpNamespace](https://docs.aws.amazon.com/cloud-map/latest/api/API_CreateHttpNamespace.html): Namespace使用DiscoverInstances，仅支持HTTP 发现. 此namespace不支持DNS解析.

当前，App Mesh仅支持在VPC内运行且无法从Internet直接访问的后端应用程序。因此，这排除了PublicDnsNamespace支持。可以使用PrivateDnsNamespace和HttpNamespace，但是鉴于大多数应用程序在连接到远程服务（通过Envoy）之前仍使用DNS解析，因此HttpNamespace不是最建议的使用方式。将来，我们计划使用 [Envoy's DNS filter](https://github.com/envoyproxy/envoy/issues/6748)无缝支持PrivateDnsNamespace和HttpNamespace。目前，需要创建PrivateDnsNamespace以获得DNS解析和App Mesh的EDS支持。请注意，PrivateDnsNamespace和HttpNamespace服务都支持自定义属性，使其可以与DiscoverInstances API一起使用。

## 故常排查
### 1. 我的Deployment和相应的Pod已成功运行，但是在调用Cloud Map DiscoverInstances API时看不到实例。 是什么原因？
以下是一些实例未在Cloud Map中注册的原因。
1. 检查aws-app-mesh-controller-for-k8s API版本 >=v0.1.2 或 >=v1.0.0。 如果没有，请使用Helm 升级controller，可以参考[文档](https://github.com/aws/eks-charts).
2. 检查aws-app-mesh-controller-for-k8s日志，查看是否有报错. [stern](https://github.com/wercker/stern)是一个在这个场景下非常好用的工具.
   ```
   $ kubectl logs -n appmesh-system appmesh-controller-<pod-id>
   (or)
   $ stern -n appmesh-system appmesh-controller
   ```
3. 如果在调用Cloud Map API时在日志中看到AccessDeniedException，请更新工作节点使用的IAM Role，使其包含AWSCloudMapRegisterInstanceAccess托管的IAM策略。
