




此示例展示了如何使用 Kubernetes deployment在 App Mesh 中**管理 gRPC 路由**。

## 实验准备

1. [在 EKS 上安装 App Mesh](https://github.com/aws/aws-app-mesh-examples/blob/main/walkthroughs/eks)
2. v1beta2 示例需要[aws-app-mesh-controller-for-k8s](https://github.com/aws/aws-app-mesh-controller-for-k8s) 版本大于等于[v1.0.0](https://github.com/aws/aws-app-mesh-controller-for-k8s/releases/tag/v1.0.0) 。 运行以下命令以检查正在运行的控制器版本:

```
$ kubectl get deployment -n appmesh-system appmesh-controller -o json | jq -r ".spec.template.spec.containers[].image" | cut -f2 -d ':'|tail -n1
```

3.   安装 Docker， 用于构建示例应用的镜像。

4.   克隆仓库并进入到 `walkthroughs/howto-k8s-grpc` 文件夹，所有命令都将从这个位置运行

     ```
     git clone https://github.com/aws/aws-app-mesh-examples
     cd walkthroughs/howto-k8s-grpc
     ```

5.   设置环境变量：

     ```
     export AWS_ACCOUNT_ID=<your_account_id>
     export AWS_DEFAULT_REGION=us-west-2
     ```

6.   **VPC_ID** 环境变量设置为启动 Kubernetes pod 的 VPC。 VPC 将用于使用 `create-private-dns-namespace` API 创建私有 DNS 命名空间。 要查找 EKS 集群的 VPC，您可以使用 `aws eks describe-cluster`。

     ```
     aws eks describe-cluster --name eks-kpf | grep vpc  # 获取vpcId
     export VPC_ID=...
     ```

     ![image-20210727043819187](https://pingfan.s3-us-west-2.amazonaws.com/pic2/yei84.png)

7.   进行应用部署：

     ```
     ./deploy.sh
     ```

     >   请注意，示例应用使用 go 模块。 如果您在部署期间无法访问 [https://proxy.golang.org](https://proxy.golang.org/)，可以通过设置 `GO_PROXY=direct` 来覆盖 GOPROXY

     ```
     GO_PROXY=direct ./deploy.sh
     ```

8.  设置[端口转发](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/) ，将本地计算机的请求路由到**client ** pod。 本地端口由您决定，在本实验中，我们假设本地端口为 **7000**。

    ```
    kubectl port-forward pod/client-xxxxxxxx-xxxx -n howto-k8s-grpc 7000:8080
    ```

    ![image-20210727051816717](https://pingfan.s3-us-west-2.amazonaws.com/pic2/yscnf.png)

    访问本机7000端口，发现

    ![image-20210727051854131](https://pingfan.s3-us-west-2.amazonaws.com/pic2/ertwt.png)



## gRPC 路由

1.  使用以下命令来查看client应用程序日志：

    ```
     kubectl logs -f client-xxxxx-xxxx -n howto-k8s-grpc app 
    ```

    ![image-20210727052250922](https://pingfan.s3-us-west-2.amazonaws.com/pic2/v6oh1.png)

2.  curl  `/getColor` API

    ```
    curl localhost:7000/getColor
    ```

    你应该看到返回 `no_color`。

    ![image-20210727052614604](https://pingfan.s3-us-west-2.amazonaws.com/pic2/0scwg.png)

3.   `Color client`返回的颜色可以使用 `/setColor` API 进行配置。

     ```
     curl -i -X POST -d "blue" localhost:7000/setColor
     ```

我们通过 `-i` 标志来查看响应中的任何错误信息。 你应该看到类似的返回：

```
HTTP/1.1 404 Not Found
Date: Fri, 27 Sep 2019 01:27:42 GMT
Content-Type: text/plain; charset=utf-8
Content-Length: 40
Connection: keep-alive
x-content-type-options: nosniff
x-envoy-upstream-service-time: 1
server: envoy
rpc error: code = Unimplemented desc =
```

这是因为我们当前的Mesh仅配置为路由 gRPC 方法`GetColor`:

```yaml
cat _output/manifest.yaml 

..........
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualRouter
metadata:
  name: color
  namespace: howto-k8s-grpc
spec:
  listeners:
    - portMapping:
        port: 8080
        protocol: grpc
  routes:
    - name: route
      grpcRoute:
        match:
          serviceName: color.ColorService
          methodName: GetColor
        action:
          weightedTargets:
            - virtualNodeRef:
                name: server
              weight: 1
---
```



删除 gRPC 路由中的 `methodName` 匹配条件以匹配 `color.ColorService` 的所有方法。



为此，请删除 `v1beta2/manifest.yaml.template`中的 methodName 部分， 并重新运行部署脚本

![image-20210727053344631](https://pingfan.s3-us-west-2.amazonaws.com/pic2/ld63v.png)



```
./deploy.sh
```







现在尝试再次更新颜色

```
curl -i -X POST -d "blue" localhost:7000/setColor
```

你会看到返回了 `HTTP/1.1 200 OK` 响应,  还会在响应中看到`no_color`, 但这是成功更新color后, 返回先前颜色。

验证颜色确实成功更新：

```
curl localhost:7000/getColor
```

![image-20210727053647484](https://pingfan.s3-us-west-2.amazonaws.com/pic2/6yoww.png)