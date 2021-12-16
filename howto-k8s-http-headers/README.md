## 总览
本实验会介绍如何使用标头（HTTP Headers）进行路由。

## 前提条件
1. [Walkthrough: App Mesh with EKS](../eks/)

2. v1beta2 示例 manifest 需要 [aws-app-mesh-controller-for-k8s](https://github.com/aws/aws-app-mesh-controller-for-k8s) 版本 [>=v1.0.0](https://github.com/aws/aws-app-mesh-controller-for-k8s/releases/tag/v1.0.0). 运行下面的命令去检查你运行的controller版本.
    ```
    $ kubectl get deployment -n appmesh-system appmesh-controller -o json | jq -r ".spec.template.spec.containers[].image" | cut -f2 -d ':'|tail -n1
    ```

如果你 [aws-app-mesh-controller-for-k8s](https://github.com/aws/aws-app-mesh-controller-for-k8s) 版本是 [v0.3.0](https://github.com/aws/aws-app-mesh-controller-for-k8s/blob/legacy-controller/CHANGELOG.md)，你可以使用 v1beta1 示例 manifest

3. 安装Docker，示例需要构建演示应用的Docker image。

## 部署

1. 克隆此仓库，然后进入`howto-k8s-http-headers`文件夹，所有的命令都是在此文件夹下运行。

2. **你的** account id:

    export AWS_ACCOUNT_ID=<your_account_id>

3. **Region** e.g. cn-northwest-1

    export AWS_DEFAULT_REGION=cn-northwest-1

4. **(可选项) 指定 Envoy Image 版本** 如果要使用与[默认版本](https://github.com/aws/eks-charts/tree/master/stable/appmesh-controller#configuration)不同的Envoy 容器镜像，运行 `helm upgrade` 去覆盖 `sidecar.image.repository` 和 `sidecar.image.tag` 字段。

5. 部署
    ```.
    ./deploy.sh
    ```

## 使用 curl 测试

在集群里添加一个请求者 -
```
kubectl run -it curler --image=curlimages/curl /bin/sh
```

在请求者里运行命令测试.

请求 blue -
```
curl -H "color_header: blue" front.howto-k8s-http-headers.svc.cluster.local:8080/; echo;
```

请求 red  -
```
curl -H "color_header: red" front.howto-k8s-http-headers.svc.cluster.local:8080/; echo;
```

请求 green (color_header 中带有'green'字符串) -
```
curl -H "color_header: requesting.green.color" front.howto-k8s-http-headers.svc.cluster.local:8080/; echo;
```

请求 yellow (color_header 存在无法识别的值) -
```
curl -H "color_header: rainbow" front.howto-k8s-http-headers.svc.cluster.local:8080/; echo;
```

请求 white (不携带color_header) -
```
curl front.howto-k8s-http-headers.svc.cluster.local:8080/; echo;
```
