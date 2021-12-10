## 总览
本示例说明如何配置App Mesh虚拟路由（virtual-route）和虚拟节点（VirtualNode）侦听器超时。 此功能使我们可以根据应用程序的需要指定自定义超时值，如果未指定，则将对所有请求应用15秒的默认超时。

在本示例演练中，我们使用基于AWS Cloud Map的服务发现机制。

### Color
colorapp包含两个deployments, _blue_ 和 _red_. 这两个Deployment的Pod都注册到服务colorapp.howto-k8s-timeout-policy.pvt.aws.local。 _blue_ Pod已在网格中注册为colorapp-blue虚拟节点（virtual-node），_red_ Pod已注册为colorapp-red虚拟节点（virtual-node）。 这些虚拟节点使用AWS CloudMap实现服务发现，因此这些Pod的IP会注册到对应的CloudMap实现服务注册。我们为所有虚拟节点和虚拟路由器指定的超时值为60秒。

另外，定义了colorapp虚拟服务，该服务将流量路由到 _blue_ 和 _red_ 虚拟节点。

### Front
Front app充当网关，可调用colorapp。Front app包含一个Deployment，其中Pod已在服务网格中注册为 _front_ 虚拟节点。该虚拟节点使用colorapp虚拟服务作为后端。这会将注入到前端吊舱中的Envoy配置为使用App Mesh的EDS发现colorapp端点。Envoy注入到 _front_ 的这些配置，使其能够使用App Mesh的EDS(Endpoint Discovery Service)发现colorapp端点。

Colorapp配置了45秒的延迟响应，以模拟耗时超过Envoy默认的15秒超时等待时间。 由于 _front_ 虚拟节点（virtual-node）中配置的超时值为60秒（后端虚拟路由器中的路由超时为60秒），因此我们可以看到在这种情况下使者将不会超时。

## 前提条件
1. [Walkthrough: App Mesh with EKS](../eks/)

2. v1beta2 示例 manifest 需要 [aws-app-mesh-controller-for-k8s](https://github.com/aws/aws-app-mesh-controller-for-k8s) 版本 [>=v1.0.0](https://github.com/aws/aws-app-mesh-controller-for-k8s/releases/tag/v1.0.0). 运行下面的命令去检查你运行的controller版本.

```
$ kubectl get deployment -n appmesh-system appmesh-controller -o json | jq -r ".spec.template.spec.containers[].image" | cut -f2 -d ':'|tail -n1
```
3. 安装Docker，示例需要构建演示应用的Docker image。

## 部署

1. 克隆此仓库，然后进入`walkthrough/howto-k8s-timeout-policy`文件夹，所有的命令都是在此文件夹下运行。
2. **你的** account id:
    ```
    export AWS_ACCOUNT_ID=<your_account_id>
    ```
3. **Region** e.g. us-west-2
    ```
    export AWS_DEFAULT_REGION=us-west-2
    ```
4. **(可选项) 指定 Envoy Image 版本** 如果要使用与[默认版本](https://github.com/aws/eks-charts/tree/master/stable/appmesh-controller#configuration)不同的Envoy 容器镜像，运行 `helm upgrade` 去覆盖 `sidecar.image.repository` 和 `sidecar.image.tag` 字段。
5. **VPC_ID** 环境变量设置为启动 Kubernetes pods 的VPC。`create-private-dns-namespace` API会使用VPC_ID在AWS中配置私有DNS namespace . 要查看EKS 集群所在的VPC，可以使用 `aws eks describe-cluster` 。关于为何Cloud Map需要 PrivateDnsNamespace，可以参考[文档](#1-how-can-i-use-cloud-map-namespaces-other-than-privatednsnamespace)。
    ```
    export VPC_ID=...
    ```
6. 部署
    ```.
    ./deploy.sh
    ```

## 验证

1. 使用 AWS Cloud Map DiscoverInstances API 查看被调用的 pods 信息。
   ```
   $ kubectl get pod -n howto-k8s-timeout-policy -o wide
    NAME                             READY   STATUS    RESTARTS   AGE     IP               NODE                                           NOMINATED NODE   READINESS GATES
    colorapp-blue-6f99884fd4-2h4jt   2/2     Running   0          4m15s   192.168.10.38    ip-192-168-16-102.us-west-2.compute.internal   <none>           <none>
    colorapp-red-77d6565cc6-8btwz    2/2     Running   0          4m15s   192.168.34.225   ip-192-168-56-146.us-west-2.compute.internal   <none>           <none>
    front-5d96c9bfb6-d2zdx           2/2     Running   0          4m15s   192.168.59.249   ip-192-168-56-146.us-west-2.compute.internal   <none>           <none>

   $ aws servicediscovery discover-instances --namespace howto-k8s-timeout-policy.pvt.aws.local --service front
    {
        "Instances": [
            {
                "InstanceId": "192.168.59.249",
                "NamespaceName": "howto-k8s-timeout-policy.pvt.aws.local",
                "ServiceName": "front",
                "HealthStatus": "HEALTHY",
                "Attributes": {
                    "AWS_INIT_HEALTH_STATUS": "HEALTHY",
                    "AWS_INSTANCE_IPV4": "192.168.59.249",
                    "app": "front",
                    "k8s.io/namespace": "howto-k8s-timeout-policy",
                    "k8s.io/pod": "front-5d96c9bfb6-d2zdx",
                    "pod-template-hash": "5d96c9bfb6",
                    "version": "v1"
                }
            }
        ]
    }

   $ aws servicediscovery discover-instances --namespace howto-k8s-timeout-policy.pvt.aws.local --service colorapp --query-parameters "version=blue"
    {
        "Instances": [
            {
                "InstanceId": "192.168.10.38",
                "NamespaceName": "howto-k8s-timeout-policy.pvt.aws.local",
                "ServiceName": "colorapp",
                "HealthStatus": "HEALTHY",
                "Attributes": {
                    "AWS_INIT_HEALTH_STATUS": "HEALTHY",
                    "AWS_INSTANCE_IPV4": "192.168.10.38",
                    "app": "colorapp",
                    "k8s.io/namespace": "howto-k8s-timeout-policy",
                    "k8s.io/pod": "colorapp-blue-6f99884fd4-2h4jt",
                    "pod-template-hash": "6f99884fd4",
                    "version": "blue"
                }
            }
        ]
    }

   $ aws servicediscovery discover-instances --namespace howto-k8s-timeout-policy.pvt.aws.local --service colorapp --query-parameters "version=red"
    {
        "Instances": [
            {
                "InstanceId": "192.168.34.225",
                "NamespaceName": "howto-k8s-timeout-policy.pvt.aws.local",
                "ServiceName": "colorapp",
                "HealthStatus": "HEALTHY",
                "Attributes": {
                    "AWS_INIT_HEALTH_STATUS": "HEALTHY",
                    "AWS_INSTANCE_IPV4": "192.168.34.225",
                    "app": "colorapp",
                    "k8s.io/namespace": "howto-k8s-timeout-policy",
                    "k8s.io/pod": "colorapp-red-77d6565cc6-8btwz",
                    "pod-template-hash": "77d6565cc6",
                    "version": "red"
                }
            }
        ]
    }
   ```

2. 现在，您可以访问front app的/color路径，并且应该看到延迟的响应时间超过了默认的特使超时时间15秒。VirtualNode的超时阈值已经设置成60秒，您可以看到在模拟的45秒延迟的情况下。是可以正常访问的。
    ```
    kubectl -n howto-k8s-timeout-policy port-forward deployment/front 8080:8080
    ```
    再打开一个窗口访问front app的/color
    ```
    curl localhost:8080/color
    ```
3. 接下来调整模拟的超时时间至75秒
    ```
    kubectl set env deployment/colorapp-blue TIMEOUT_VALUE=75
    kubectl set env deployment/colorapp-red TIMEOUT_VALUE=75
    ```
4. 再次访问front app
    ```
    kubectl -n howto-k8s-timeout-policy port-forward deployment/front 8080:8080
    ```
    再打开一个窗口访问front app的/color，稍作等待可以看到已经超时：“upstream request timeout”
    ```
    curl localhost:8080/color
    ```
## 故障排除
1. 检查aws-app-mesh-controller-for-k8s API版本 >=v1.0.0。 如果没有，请使用Helm 升级controller，可以参考[文档](https://github.com/aws/eks-charts).

2. 检查aws-app-mesh-controller-for-k8s日志，查看是否有报错. [stern](https://github.com/wercker/stern)是一个在这个场景下非常好用的工具.
   ```
   $ kubectl logs -n appmesh-system appmesh-controller-manager-<pod-id>
   (or)
   $ stern -n appmesh-system appmesh-controller-manager
   ```
3. 如果在调用Cloud Map API时在日志中看到AccessDeniedException，请更新工作节点使用的IAM Role，使其包含AWSCloudMapRegisterInstanceAccess托管的IAM策略。
