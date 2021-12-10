## 总览
本实验展示如何使用 EKS 和 App Mesh 管理HTTP/2路由。

## 前提条件
1. [Walkthrough: App Mesh with EKS](../eks/)

2. v1beta2 示例 manifest 需要 [aws-app-mesh-controller-for-k8s](https://github.com/aws/aws-app-mesh-controller-for-k8s) 版本 [>=v1.0.0](https://github.com/aws/aws-app-mesh-controller-for-k8s/releases/tag/v1.0.0). 运行下面的命令去检查你运行的controller版本.
```
$ kubectl get deployment -n appmesh-system appmesh-controller -o json | jq -r ".spec.template.spec.containers[].image" | cut -f2 -d ':'|tail -n1
```

你可以使用 v1beta1 示例 manifest，如果你 [aws-app-mesh-controller-for-k8s](https://github.com/aws/aws-app-mesh-controller-for-k8s) 版本是 [v0.3.0](https://github.com/aws/aws-app-mesh-controller-for-k8s/blob/legacy-controller/CHANGELOG.md)

3. 安装Docker，示例需要构建演示应用的Docker image。


## 部署

1. 克隆此仓库，然后进入`walkthrough/howto-k8s-http2`文件夹，所有的命令都是在此文件夹下运行。
2. **你的** account id:
    ```
    export AWS_ACCOUNT_ID=<your_account_id>
    ```
3. **Region** e.g. us-west-2
    ```
    export AWS_DEFAULT_REGION=us-west-2
    ```
4. **(可选项) 指定 Envoy Image 版本** 如果要使用与[默认版本](https://github.com/aws/eks-charts/tree/master/stable/appmesh-controller#configuration)不同的Envoy 容器镜像，运行 `helm upgrade` 去覆盖 `sidecar.image.repository` 和 `sidecar.image.tag` 字段。
    ```
    helm upgrade -i appmesh-controller eks/appmesh-controller --namespace appmesh-system --set sidecar.image.repository=840364872350.dkr.ecr.us-west-2.amazonaws.com/aws-appmesh-envoy --set sidecar.image.tag=<VERSION>
    ```
5. 部署
    ```.
    ./deploy.sh
    ```

6. 请注意，示例应用程序使用go模块。如果在部署期间无法访问[Go Proxy](https://goproxy.io/zh/)，则可以通过设置`GO_PROXY = direct`覆盖GOPROXY。
   ```
   GO_PROXY=direct
   ./deploy.sh
   ```

7. 设置[端口转发（port forwarding）](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/)以将请求从本地路由到 *client* 容器。 本地端口由您决定，但本实验将假定本地端口为7000。
    ```
    kubectl -n howto-k8s-http2 port-forward deployment/client 7000:8080
    ```
## HTTP/2 路由
1. 为了查看应用程序日志，您必须通过运行以下命令找到您的 *client* Pod：
    ```
    kubectl get pod -n howto-k8s-http2
    ```

2. 使用*client* Pod的名称，运行以下命令以查看*client*应用程序日志：
    ```
    kubectl logs -f -n howto-k8s-http2 <pod_name> app
    ```

3. 请求会通过HTTP/2均匀分布到3种*color*服务（red, blue, and green）。可以通过多次运行以下命令来证明这一点：
    ```
    curl localhost:7000/color
    ```

4. 您可以在此处的[here](./manifest.yaml.template)中编辑这些配置。进行任何更改后，运行./deploy.sh。例如，您可以删除一个权重目标并再次触发上面的curl命令，可以看到不再显示这个颜色的返回。
