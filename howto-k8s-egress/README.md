

本实验演示了如何访问Mesh之外的外部服务。

本实验将创建两个 Kubernetes 命名空间：`howto-k8s-egress` 和 `mesh-external`。 

*   Mesh 将只应用在命名空间 `howto-k8s-egress` 和其中的资源， `mesh-external` 不是 Mesh 的一部分。
*    `mesh-external` 将有两个服务 `red` 和 `blue`，我们将展示从 Mesh 访问这两个外部服务的情况：
    *   通过使用 Mesh `ALLOW_ALL` egress filter
    *   通过使用Mesh `DROP_ALL` egress filter和virtual node暴露的blue service

## 实验准备

1. [在 EKS 上安装 App Mesh](https://github.com/aws/aws-app-mesh-examples/blob/main/walkthroughs/eks)
2. [aws-app-mesh-controller-for-k8s](https://github.com/aws/aws-app-mesh-controller-for-k8s) 版本大于等于[v1.0.0](https://github.com/aws/aws-app-mesh-controller-for-k8s/releases/tag/v1.0.0) 。 运行以下命令以检查正在运行的控制器版本:

```
$ kubectl get deployment -n appmesh-system appmesh-controller -o json | jq -r ".spec.template.spec.containers[].image" | cut -f2 -d ':'|tail -n1
```

3.   安装 Docker， 用于构建示例应用的镜像。

4.   克隆仓库并进入到 `walkthroughs/howto-k8s-egress` 文件夹，所有命令都将从这个位置运行

```
git clone https://github.com/aws/aws-app-mesh-examples
cd aws-app-mesh-examples/walkthroughs/howto-k8s-egress
```

5.   设置环境变量：

```
export AWS_ACCOUNT_ID=<your_account_id>
export AWS_DEFAULT_REGION=us-west-2
```

6.   进行应用部署：

```
    ./deploy.sh
```



## 验证过程

1.验证创建了两个命名空间：`howto-k8s-egress`（Mesh的一部分）和`mesh-external`（Mesh的外部）

```bash 
kubectl get ns

appmesh-system     Active   10d
default            Active   10d
howto-k8s-egress   Active   6s
kube-node-lease    Active   10d
kube-public        Active   10d
kube-system        Active   10d
mesh-external      Active   6s
```

2.   让我们检查外部服务：

```bash
kubectl get pod,svc -n mesh-external

NAME                        READY   STATUS    RESTARTS   AGE
pod/blue-5cf49bddcf-mnlrx   1/1     Running   0          2m17s
pod/red-7c595d6f8f-jj2vh    1/1     Running   0          2m17s

NAME           TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
service/blue   ClusterIP   10.100.254.102   <none>        8080/TCP   2m17s
service/red    ClusterIP   10.100.237.219   <none>        8080/TCP   2m17s
```

3.   从Mesh内部检查与`blue`和`red`的连接。进入到front pod内部shell：

```bash
FRONT_POD=$(kubectl get pod -l "app=front" -n howto-k8s-egress --output=jsonpath={.items..metadata.name})
kubectl exec -it $FRONT_POD -n howto-k8s-egress -- /bin/bash
```

4.   检查与外部服务的连接：`blue`

```
$ curl blue.mesh-external.svc.cluster.local:8080/; echo;
external: blue
```

![image-20210727150524193](https://pingfan.s3-us-west-2.amazonaws.com/pic2/t43az.png)

尽管在网格级别有`DROP_ALL` egress, 还是得到了`external: blue`响应，因为我们已经在网格内部设置了一个virtual node来引用这个外部服务：

![image-20210727153356612](https://pingfan.s3-us-west-2.amazonaws.com/pic2/cinui.png)

5.   检查与外部服务的连接：`red`

```
curl -lvv red.mesh-external.svc.cluster.local:8080/; echo;
```

![image-20210727150840546](https://pingfan.s3-us-west-2.amazonaws.com/pic2/6dbau.png)

访问外部服务`red`时，您应该收到 404 响应，因为 Mesh 具有`DROP_ALL` egress，并且我们没有任何引用此外部服务的virtual node.

6.   修改Mesh为`ALLOW_ALL`出口

将 `v1beta2/manifest.yaml.template` 中的 `mesh->egressFilter` 更改为 `ALLOW_ALL` , 并再次部署应用程序

![image-20210727152506491](https://pingfan.s3-us-west-2.amazonaws.com/pic2/8kd18.png)

```
SKIP_IMAGES=1 ./deploy.sh
```

![image-20210727152547562](https://pingfan.s3-us-west-2.amazonaws.com/pic2/ulpju.png)

检查与外部服务`blue`和`red`的连接：

```
kubectl exec -it $FRONT_POD -n howto-k8s-egress -- /bin/bash
curl blue.mesh-external.svc.cluster.local:8080/; echo;
external: blue

curl red.mesh-external.svc.cluster.local:8080/; echo;
external: red
```

![image-20210727153149608](https://pingfan.s3-us-west-2.amazonaws.com/pic2/ex2bg.png)

可以看到访问外部服务都成功响应，因为 Mesh 允许使用 `ALLOW_ALL` egressFilter 连接所有外部服务。

## 清理资源

```
kubectl delete -f _output/manifest.yaml
```