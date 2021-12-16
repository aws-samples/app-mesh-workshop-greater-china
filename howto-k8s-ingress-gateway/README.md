







在本实验中，我们将在我们现有的Color app中配置一个 Ingress Gateway，使用 VirtualGateway 而不是 VirtualNode 来处理入口流量。

Virtual Gateway 允许网格外部的资源与网格内部的资源进行通信。 virtual gateway以Envoy代理形式运行在 Amazon ECS、EKS 或 Amazon EC2 。 与和应用一起运行envoy proxy的virtual node不同，virtual gateway是单独部署的代理。



## 实验准备

1.   [aws-app-mesh-controller-for-k8s](https://github.com/aws/aws-app-mesh-controller-for-k8s) 版本大于等于[v1.1.0](https://github.com/aws/aws-app-mesh-controller-for-k8s/releases/tag/v1.1.0) 。 运行以下命令以检查您正在运行的控制器版本。

```bash 
kubectl get deployment -n appmesh-system appmesh-controller -o json | jq -r ".spec.template.spec.containers[].image" | cut -f2 -d ':'|tail -n1

v1.4.0
```

2.   安装 Docker， 用于构建示例应用的镜像。

3.   克隆仓库并进入到 `howto-k8s-ingress-gateway` 文件夹，所有命令都将从这个位置运行

     ```
     git clone https://github.com/aws-samples/app-mesh-workshop-greater-china.git
     cd howto-k8s-ingress-gateway
     ```

4.   设置环境变量：

     ```
     export AWS_ACCOUNT_ID=<your_account_id>
     export AWS_DEFAULT_REGION=cn-northwest-1

     # 参考 https://docs.aws.amazon.com/app-mesh/latest/userguide/envoy.html
     export ENVOY_IMAGE=840364872350.dkr.ecr.us-west-2.amazonaws.com/aws-appmesh-envoy:v1.18.3.0-prod
     ```

5.   进行应用部署

```
    ./deploy.sh
```

## 使用 Ingress gateway

在这个例子中有两个 GatewayRoutes 设置：

1)   `gateway-route-headers` 。将流量路由到 VirtualService `color-headers`
2)   `gateway-route-paths`。 将流量路由到 VirtualService `color-paths`

VirtualService `color-headers` 使用 VirtualRouter 来匹配 HTTP 标头，来选择后端 VirtualNode。

VirtualService `color-paths` 使用 HTTP 路径前缀，来选择后端 VirtualNode

让我们看看部署在 Kubernetes 和 AWS App Mesh 中的 VirtualGateway：

```bash 
kubectl get virtualgateway -n howto-k8s-ingress-gateway
NAME         ARN                                                                                                                                 AGE
ingress-gw   arn:aws:appmesh:us-west-2:112233333455:mesh/howto-k8s-ingress-gateway/virtualGateway/ingress-gw_howto-k8s-ingress-gateway   113s

aws appmesh list-virtual-gateways --mesh-name howto-k8s-ingress-gateway

# {
#    "virtualGateways": [
#        {
#            "arn": "arn:aws:appmesh:us-west-2:1234567890:mesh/howto-k8s-ingress-gateway/virtualGateway/ingress-gw_howto-k8s-ingress-gateway",
#            "createdAt": 1592601321.986,
#            "lastUpdatedAt": 1592601321.986,
#            "meshName": "howto-k8s-ingress-gateway",
#            "meshOwner": "1234567890",
#            "resourceOwner": "1234567890",
#            "version": 1,
#            "virtualGatewayName": "ingress-gw_howto-k8s-ingress-gateway"
#        }
#    ]
# }

aws appmesh list-gateway-routes --virtual-gateway-name ingress-gw_howto-k8s-ingress-gateway --mesh-name howto-k8s-ingress-gateway

# {
#    "gatewayRoutes": [
#        {
#            "arn": "arn:aws:appmesh:us-west-2:1234567890:mesh/howto-k8s-ingress-gateway/virtualGateway/ingress-gw_howto-k8s-ingress-gateway/gatewayRoute/gateway-route-paths_howto-k8s-ingress-gateway",
#            "createdAt": 1592601647.409,
#            "gatewayRouteName": "gateway-route-paths_howto-k8s-ingress-gateway",
#            "lastUpdatedAt": 1592601647.409,
#            "meshName": "howto-k8s-ingress-gateway",
#            "meshOwner": "1234567890",
#            "resourceOwner": "1234567890",
#            "version": 1,
#            "virtualGatewayName": "ingress-gw_howto-k8s-ingress-gateway"
#        },
#        {
#            "arn": "arn:aws:appmesh:us-west-2:1234567890:mesh/howto-k8s-ingress-gateway/virtualGateway/ingress-gw_howto-k8s-ingress-gateway/gatewayRoute/gateway-route-headers_howto-k8s-ingress-gateway",
#            "createdAt": 1592601647.395,
#            "gatewayRouteName": "gateway-route-headers_howto-k8s-ingress-gateway",
#            "lastUpdatedAt": 1592601647.395,
#            "meshName": "howto-k8s-ingress-gateway",
#            "meshOwner": "1234567890",
#            "resourceOwner": "1234567890",
#            "version": 1,
#            "virtualGatewayName": "ingress-gw_howto-k8s-ingress-gateway"
#        }
#    ]
# }
```

流量入口点将是一个链接到 VirtualGateway `ingress-gw` 的 Envoy：

```bash 
kubectl get pod -n howto-k8s-ingress-gateway
NAME                        READY   STATUS    RESTARTS   AGE
blue-574fc6f766-jtc76       2/2     Running   0          13s
green-5fdb4488cb-mtrsl      2/2     Running   0          13s
ingress-gw-c9c9b895-rqv9r   1/1     Running   0          13s
red-54b44b859b-jqmxx        2/2     Running   0          13s
white-85685c459b-rgj4f      2/2     Running   0          13s
yellow-67b88f8cf4-mtnhq     2/2     Running   0          13s
```

`ingress-gw-c9c9b895-rqv9r` 指向 VirtualGateway，可以通过 LoadBalancer 类型的 k8s service访问：

```bash 
kubectl get svc -n howto-k8s-ingress-gateway
NAME            TYPE           CLUSTER-IP       EXTERNAL-IP                                                              PORT(S)          AGE
color-blue      ClusterIP      10.100.10.91     <none>                                                                   8080/TCP         3m21s
color-green     ClusterIP      10.100.81.185    <none>                                                                   8080/TCP         3m22s
color-headers   ClusterIP      10.100.90.162    <none>                                                                   8080/TCP         3m21s
color-paths     ClusterIP      10.100.49.62     <none>                                                                   8080/TCP         3m21s
color-red       ClusterIP      10.100.247.202   <none>                                                                   8080/TCP         3m21s
color-white     ClusterIP      10.100.5.232     <none>                                                                   8080/TCP         3m21s
color-yellow    ClusterIP      10.100.151.20    <none>                                                                   8080/TCP         3m21s
ingress-gw      LoadBalancer   10.100.177.113   a0b14c18c13114255ab46432fcb9e1f8-135255798.us-west-2.elb.amazonaws.com   80:30151/TCP   3m21s
```

让我们验证与 Mesh 的连接：

```
GW_ENDPOINT=$(kubectl get svc ingress-gw -n howto-k8s-ingress-gateway --output jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

通过 VirtualService color-path连接到VirtualNode red:

```
curl ${GW_ENDPOINT}/paths/red ; echo;
```

![image-20210727140013228](https://pingfan.s3-us-west-2.amazonaws.com/pic2/6pak5.png)

通过 VirtualService color-path连接到VirtualNode blue:

```
curl ${GW_ENDPOINT}/paths/blue ; echo;
```

通过 VirtualService color-path连接到VirtualNode yellow:

```
curl ${GW_ENDPOINT}/paths/yellow ; echo;
```

通过 VirtualService color-headers连接到VirtualNode blue:

```
curl -H "color_header: blue" ${GW_ENDPOINT}/headers ; echo;
```

![image-20210727140121750](https://pingfan.s3-us-west-2.amazonaws.com/pic2/l5r8o.png)

通过 VirtualService color-headers连接到VirtualNode red:

```
curl -H "color_header: red" ${GW_ENDPOINT}/headers ; echo;
```



## 资源清理

```
kubectl delete -f _output/manifest.yaml
```

![image-20210727141406716](https://pingfan.s3-us-west-2.amazonaws.com/pic2/o611w.png)