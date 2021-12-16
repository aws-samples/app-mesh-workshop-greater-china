



## Overview

在本实验中，我们将演示如何在 App Mesh 和 EKS 中使用连接池实现熔断(circuit breaking)功能。

熔断旨在最大限度地减少故障的影响，防止它们级联和复合，并确保端到端的性能。

Envoy 通过熔断开关来控制服务质量。 App Mesh中的Connection Pool等同于[Envoy的熔断配置](https://www.envoyproxy.io/docs/envoy/latest/api-v2/api/v2/cluster/circuit_breaker.proto)。连接池限制了一个 Envoy 可以同时与上游集群中的所有主机建立的连接数。

 App Mesh 中的连接池在侦听器级别得到支持，保护本地应用程序免于被大量连接淹没。因此，连接池作为熔断器配置，直接作用在与本地应用通信的 Envoy 入口集群。



## 实验准备

1. [在 EKS 上安装 App Mesh](https://github.com/aws-samples/app-mesh-workshop-greater-china/tree/main/eks)
2. 运行以下命令以检查正在运行的appmesh控制器版本:

```
$ kubectl get deployment -n appmesh-system appmesh-controller -o json | jq -r ".spec.template.spec.containers[].image" | cut -f2 -d ':'|tail -n1
```

3.   安装 Docker， 用于构建示例应用的镜像。

4.   克隆仓库并进入到 `howto-k8s-connection-pools ` 文件夹，所有命令都将从这个位置运行

```
git clone https://github.com/aws-samples/app-mesh-workshop-greater-china.git
cd howto-k8s-connection-pools
```

5.   设置环境变量：

```
export AWS_ACCOUNT_ID=<your_account_id>
export AWS_DEFAULT_REGION=cn-northwest-1
```

6.   进行应用部署：

```
    ./deploy.sh
```



## 创建一个启用连接池的Mesh

在virtual gateway和virtual node部署示例应用程序和连接池，我们将部署一个虚拟网关（`ingress-gw`）和两个virtual node：`green` 和 `red`，分别对应应用程序。

```bash
                                                                       +---------+
                                                                   +-->+  Green  |
                                                                   |   +---------+
+-----------+       +------------------+      +-----------------+  |
|  ingress  +------>+  virtualservice  +----->+  virtualrouter  +--+
+-----------+       +------------------+      +-----------------+  |
                                                                   |   +---------+
                                                                   +-->+   Red   |
                                                                       +---------+
```

检查部署的资源：

```
$ kubectl get virtualnodes,virtualgateway,virtualrouter,virtualservice,pod -n howto-k8s-connection-pools
NAME                                ARN                                                                                                                   AGE
virtualnode.appmesh.k8s.aws/green   arn:aws:appmesh:us-west-2:145197526627:mesh/howto-k8s-connection-pools/virtualNode/green_howto-k8s-connection-pools   2m4s
virtualnode.appmesh.k8s.aws/red     arn:aws:appmesh:us-west-2:145197526627:mesh/howto-k8s-connection-pools/virtualNode/red_howto-k8s-connection-pools     2m4s

NAME                                        ARN                                                                                                                           AGE
virtualgateway.appmesh.k8s.aws/ingress-gw   arn:aws:appmesh:us-west-2:145197526627:mesh/howto-k8s-connection-pools/virtualGateway/ingress-gw_howto-k8s-connection-pools   2m4s

NAME                                        ARN                                                                                                                           AGE
virtualrouter.appmesh.k8s.aws/color-paths   arn:aws:appmesh:us-west-2:145197526627:mesh/howto-k8s-connection-pools/virtualRouter/color-paths_howto-k8s-connection-pools   2m4s

NAME                                         ARN                                                                                                                                              AGE
virtualservice.appmesh.k8s.aws/color-paths   arn:aws:appmesh:us-west-2:145197526627:mesh/howto-k8s-connection-pools/virtualService/color-paths.howto-k8s-connection-pools.svc.cluster.local   2m4s

NAME                              READY   STATUS    RESTARTS   AGE
pod/green-6f49fcfb8-cxwjn         2/2     Running   0          2m3s
pod/ingress-gw-67686c7bbf-ncttw   1/1     Running   0          2m3s
pod/red-6fb64ddc88-pnj6f          2/2     Running   0          2m3s
```

![image-20210727161208584](https://pingfan.s3-us-west-2.amazonaws.com/pic2/5a6ka.png)



在`green` virtual node和 `ingress-gw` listener上配置了连接池：

```bash
kubectl describe virtualnode green -n howto-k8s-connection-pools

..
Spec:
  Aws Name:  green_howto-k8s-connection-pools
  Listeners:
    Connection Pool:
      Http:
        Max Connections:       10
        Max Pending Requests:  10
...


kubectl describe virtualgateway ingress-gw -n howto-k8s-connection-pools

...
Spec:
  Aws Name:  ingress-gw_howto-k8s-connection-pools
  Listeners:
    Connection Pool:
      Http:
        Max Connections:       5
        Max Pending Requests:  5
...
```

让我们检查 AWS App Mesh 中的连接池配置:

```bash
aws appmesh describe-virtual-node --virtual-node-name green_howto-k8s-connection-pools --mesh-name howto-k8s-connection-pools

{
    "virtualNode": {
        "meshName": "howto-k8s-connection-pools",
        "metadata": {
            "arn": "arn:aws:appmesh:us-west-2:123456789:mesh/howto-k8s-connection-pools/virtualNode/green_howto-k8s-connection-pools",
            "createdAt": 1603667107.741,
            "lastUpdatedAt": 1603668330.257,
            "meshOwner": "123456789",
            "resourceOwner": "123456789",
            "uid": "8d7708cc-609d-44ff-9568-e5bbe2d6f744",
            "version": 4
        },
        "spec": {
            "backends": [],
            "listeners": [
                {
                    "connectionPool": {
                        "http": {
                            "maxConnections": 10,
                            "maxPendingRequests": 10
                        }
                    },
                    "healthCheck": {
                        "healthyThreshold": 2,
                        "intervalMillis": 5000,
                        "path": "/ping",
                        "port": 8080,
                        "protocol": "http",
                        "timeoutMillis": 2000,
                        "unhealthyThreshold": 2
                    },
                    "portMapping": {
                        "port": 8080,
                        "protocol": "http"
                    }
                }
            ],
            "serviceDiscovery": {
                "dns": {
                    "hostname": "color-green.howto-k8s-connection-pools.svc.cluster.local"
                }
            }
        },
        "status": {
            "status": "ACTIVE"
        },
        "virtualNodeName": "green_howto-k8s-connection-pools"
    }
}


aws appmesh describe-virtual-gateway --virtual-gateway-name ingress-gw_howto-k8s-connection-pools --mesh-name howto-k8s-connection-pools

{
    "virtualGateway": {
        "meshName": "howto-k8s-connection-pools",
        "metadata": {
            "arn": "arn:aws:appmesh:us-west-2:123456789:mesh/howto-k8s-connection-pools/virtualGateway/ingress-gw_howto-k8s-connection-pools",
            "createdAt": 1603667107.705,
            "lastUpdatedAt": 1603668330.25,
            "meshOwner": "123456789",
            "resourceOwner": "123456789",
            "uid": "aa8a206e-aaa5-4980-8224-fca8416e0006",
            "version": 3
        },
        "spec": {
            "listeners": [
                {
                    "connectionPool": {
                        "http": {
                            "maxConnections": 5,
                            "maxPendingRequests": 5
                        }
                    },
                    "portMapping": {
                        "port": 8088,
                        "protocol": "http"
                    }
                }
            ]
        },
        "status": {
            "status": "ACTIVE"
        },
        "virtualGatewayName": "ingress-gw_howto-k8s-connection-pools"
    }
}
```



## 测试连接池和熔断

并行运行`fortio load`, 并注意`ingress-gw` Envoy 统计信息中，与熔断器有关的部分：

```
FORTIO=$(kubectl get pod -l "app=fortio" --output=jsonpath={.items..metadata.name})
kubectl exec -it $FORTIO -- fortio load -c 10 -qps 100 -t 100s http://ingress-gw.howto-k8s-connection-pools/paths/red
```

在 fortio 发送请求时检查统计信息：

```bash 
INGRESS_POD=$(kubectl get pod -l "app=ingress-gw" -n howto-k8s-connection-pools --output=jsonpath={.items..metadata.name})
kubectl exec -it $INGRESS_POD -n howto-k8s-connection-pools -- curl localhost:9901/stats | grep -E '(http.ingress.downstream_cx_active|upstream_cx_active|cx_open|upstream_cx_http1_total)'

cluster.cds_egress_howto-k8s-connection-pools_green_howto-k8s-connection-pools_http_8080.circuit_breakers.default.cx_open: 0cluster.cds_egress_howto-k8s-connection-pools_green_howto-k8s-connection-pools_http_8080.circuit_breakers.high.cx_open: 0cluster.cds_egress_howto-k8s-connection-pools_green_howto-k8s-connection-pools_http_8080.upstream_cx_active: 0cluster.cds_egress_howto-k8s-connection-pools_green_howto-k8s-connection-pools_http_8080.upstream_cx_http1_total: 0cluster.cds_egress_howto-k8s-connection-pools_red_howto-k8s-connection-pools_http_8080.circuit_breakers.default.cx_open: 0cluster.cds_egress_howto-k8s-connection-pools_red_howto-k8s-connection-pools_http_8080.circuit_breakers.high.cx_open: 0cluster.cds_egress_howto-k8s-connection-pools_red_howto-k8s-connection-pools_http_8080.upstream_cx_active: 5cluster.cds_egress_howto-k8s-connection-pools_red_howto-k8s-connection-pools_http_8080.upstream_cx_http1_total: 5cluster.cds_ingress_howto-k8s-connection-pools_ingress-gw_howto-k8s-connection-pools_self_redirect_http_15001.circuit_breakers.default.cx_open: 1cluster.cds_ingress_howto-k8s-connection-pools_ingress-gw_howto-k8s-connection-pools_self_redirect_http_15001.circuit_breakers.high.cx_open: 0cluster.cds_ingress_howto-k8s-connection-pools_ingress-gw_howto-k8s-connection-pools_self_redirect_http_15001.upstream_cx_active: 5cluster.cds_ingress_howto-k8s-connection-pools_ingress-gw_howto-k8s-connection-pools_self_redirect_http_15001.upstream_cx_http1_total: 5http.ingress.downstream_cx_active: 10
```

![image-20210727161721075](https://pingfan.s3-us-west-2.amazonaws.com/pic2/qymg2.png)

请注意，`downstream_cx_active` 为 10，它与来自 fortio 的传入连接匹配。 `ingress-gw` 的 `upstream_cx_active` 连接是 5（达到最大连接），而 `cx_open` 是 1，这意味着连接熔断器打开。



现在，让我们将流量发送到虚拟节点`green`并注意类似的行为：

```
FORTIO=$(kubectl get pod -l "app=fortio" --output=jsonpath={.items..metadata.name})
kubectl exec -it $FORTIO -- fortio load -c 20 -qps 500 -t 100s http://color-green.howto-k8s-connection-pools:8080
```

在 fortio 发送请求时检查统计信息：

```bash
GREEN_POD=$(kubectl get pod -l "version=green" -n howto-k8s-connection-pools --output=jsonpath={.items..metadata.name})
kubectl exec -it $GREEN_POD -n howto-k8s-connection-pools -c app -- curl localhost:9901/stats | grep -E '(http.ingress.downstream_cx_active|upstream_cx_active|cx_open|upstream_cx_http1_total)'

cluster.cds_egress_howto-k8s-connection-pools_amazonaws.circuit_breakers.default.cx_open: 0cluster.cds_egress_howto-k8s-connection-pools_amazonaws.circuit_breakers.high.cx_open: 0cluster.cds_egress_howto-k8s-connection-pools_amazonaws.upstream_cx_active: 0cluster.cds_egress_howto-k8s-connection-pools_amazonaws.upstream_cx_http1_total: 0cluster.cds_ingress_howto-k8s-connection-pools_green_howto-k8s-connection-pools_http_8080.circuit_breakers.default.cx_open: 1cluster.cds_ingress_howto-k8s-connection-pools_green_howto-k8s-connection-pools_http_8080.circuit_breakers.high.cx_open: 0cluster.cds_ingress_howto-k8s-connection-pools_green_howto-k8s-connection-pools_http_8080.upstream_cx_active: 10cluster.cds_ingress_howto-k8s-connection-pools_green_howto-k8s-connection-pools_http_8080.upstream_cx_http1_total: 663http.ingress.downstream_cx_active: 20
```



请注意，`downstream_cx_active` 是 20，它与来自 fortio 的传入连接匹配。 `green` 的 `upstream_cx_active` 连接数是 10（达到最大连接数），而 `cx_open` 是 1，这意味着连接熔断器打开。

>    我们将 maxConnection 设置为一个人为的低值，以说明 App Mesh 连接池和熔断功能。 这不是一个符合生产环境的设置，但希望有助于说明熔断器的功能。



## 清理资源

```
kubectl delete -f _output/manifest.yaml
```