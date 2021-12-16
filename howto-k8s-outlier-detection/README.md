









在本实验中，我们将演示如何在 App Mesh 和 EKS 中使用异常检测(`outlier detection`)。

异常检测是一种被动的健康检查，当给定服务的端点/主机（由virtual node表示）达到故障阈值（被视为 *异常值 - outlier*）时，它会从负载均衡中被临时替换。 可以在Virtual Node的侦听器中配置`异常检测`。



## 实验准备

1. [在 EKS 上安装 App Mesh](https://github.com/aws-samples/app-mesh-workshop-greater-china/tree/main/eks)
2.  运行以下命令以检查正在运行的appmesh controller版本:

```
$ kubectl get deployment -n appmesh-system appmesh-controller -o json | jq -r ".spec.template.spec.containers[].image" | cut -f2 -d ':'|tail -n1
```

3.   安装 Docker， 用于构建示例应用的镜像。

4.   克隆仓库并进入到 `howto-k8s-outlier-detection` 文件夹，所有命令都将从这个位置运行

```
git clone https://github.com/aws-samples/app-mesh-workshop-greater-china.git
cd howto-k8s-outlier-detection
```

5.   设置环境变量：

```
export AWS_ACCOUNT_ID=<your_account_id>
export AWS_DEFAULT_REGION=cn-northwest-1
```







## 创建一个启用`异常检测`的网格

让我们部署一个启用`异常检测`的网格。 这将部署两个Virtual Node（和应用）：`front` 和 `colorapp`，访问方式是 `front`->`colorapp` 。 `colorapp` 是具有四个replica的后端服务。

```bash 
./deploy.sh

kubectl get virtualnodes,pod -n howto-k8s-outlier-detection
NAME                                   ARN                                                                                                                                AGE
virtualnode.appmesh.k8s.aws/colorapp   arn:aws:appmesh:us-west-2:1234567890:mesh/howto-k8s-outlier-detection/virtualNode/colorapp_howto-k8s-outlier-detection   55s
virtualnode.appmesh.k8s.aws/front      arn:aws:appmesh:us-west-2:1234567890:mesh/howto-k8s-outlier-detection/virtualNode/front_howto-k8s-outlier-detection      55s

NAME                           READY   STATUS    RESTARTS   AGE
pod/colorapp-cbfb668dc-6v5sm   2/2     Running   0          55s
pod/colorapp-cbfb668dc-fdt2n   2/2     Running   0          55s
pod/colorapp-cbfb668dc-h2whw   2/2     Running   0          55s
pod/colorapp-cbfb668dc-xzqbd   2/2     Running   0          55s
pod/front-57bfb8f966-8n9rh     2/2     Running   0          55s
```

![image-20210727212401606](https://pingfan.s3-us-west-2.amazonaws.com/pic2/9gu6k.png)



在 `colorapp` 侦听器上配置了`异常检测`：

```
kubectl describe virtualnode colorapp -n howto-k8s-outlier-detection

..
Spec:
  Aws Name:  colorapp_howto-k8s-outlier-detection
  Listeners:
    Outlier Detection:
      Base Ejection Duration:
        Unit:   s
        Value:  10
      Interval:
        Unit:                s
        Value:               10
      Max Ejection Percent:  50
      Max Server Errors:     5
    Port Mapping:
      Port:      8080
      Protocol:  http
...
```

检查 App Mesh 中的`异常检测`配置:

```bash
aws appmesh describe-virtual-node --virtual-node-name colorapp_howto-k8s-outlier-detection --mesh-name howto-k8s-outlier-detection

{
    "virtualNode": {
        "meshName": "howto-k8s-outlier-detection",
        "metadata": {
            "arn": "arn:aws:appmesh:us-west-2:1234567890:mesh/howto-k8s-outlier-detection/virtualNode/colorapp_howto-k8s-outlier-detection",
            "createdAt": 1603467992.872,
            "lastUpdatedAt": 1603468186.926,
            "meshOwner": "1234567890",
            "resourceOwner": "1234567890",
            "uid": "b41a6cd3-40e3-4182-aafe-53b943241221",
            "version": 2
        },
        "spec": {
            "backends": [],
            "listeners": [
                {
                    "outlierDetection": {
                        "baseEjectionDuration": {
                            "unit": "s",
                            "value": 10
                        },
                        "interval": {
                            "unit": "s",
                            "value": 10
                        },
                        "maxEjectionPercent": 50,
                        "maxServerErrors": 5
                    },
                    "portMapping": {
                        "port": 8080,
                        "protocol": "http"
                    }
                }
            ],
            "serviceDiscovery": {
                "awsCloudMap": {
                    "namespaceName": "howto-k8s-outlier-detection.pvt.aws.local",
                    "serviceName": "colorapp"
                }
            }
        },
        "status": {
            "status": "ACTIVE"
        },
        "virtualNodeName": "colorapp_howto-k8s-outlier-detection"
    }
}
```



## 验证`异常检测`

`front` 通过调用 `colorapp` 的 `/get`接口 获取颜色。 `front` 可以通过向 `/fault` 接口发出请求来向 `colorapp` 注入故障。

当 `colorapp` 的一个实例收到这个请求时，它会开始在 `/get` 接口上返回 500 Internal Service Error。

故障可以通过` /recover `接口恢复。



`front` 还记录后端 `colorapp` 主机和每个 `colorapp` 实例的响应状态的统计信息。

统计信息可以通过`/stats` 检索并使用`/reset_stats` 重置。

让我们进入到"流量生成器 Vegeta" 的shell内部，来调用 `front` 服务:

```
VEGETA_POD=$(kubectl get pod -l "app=vegeta-trafficgen" --output=jsonpath={.items..metadata.name})
kubectl exec -it $VEGETA_POD -- /bin/sh
```

让我们通过 `front` 接口验证 `colorapp` 是否返回响应

```
curl -i front.howto-k8s-outlier-detection:8080/color/get

HTTP/1.1 200 OK
date: Fri, 23 Oct 2020 15:58:45 GMT
content-length: 7
content-type: text/plain; charset=utf-8
x-envoy-upstream-service-time: 1
server: envoy

purple
```

![image-20210727213002354](https://pingfan.s3-us-west-2.amazonaws.com/pic2/0g8f2.png)

多访问几次上面的接口，再查看四个`colorapp`后端的统计数据：

```json 
curl front.howto-k8s-outlier-detection:8080/stats | jq .

[
  {
    "HostUID": "8f04b1c8-af29-4345-8a0d-34cb5c981e38",
    "Counter": {
      "StatusOk": 3,
      "StatusError": 0,
      "Total": 3
    }
  },
  {
    "HostUID": "34bb223d-1e6c-4423-898e-372d30a638b2",
    "Counter": {
      "StatusOk": 3,
      "StatusError": 0,
      "Total": 3
    }
  },
  {
    "HostUID": "c87a6e70-c9a2-4343-a453-81808bec9d2d",
    "Counter": {
      "StatusOk": 2,
      "StatusError": 0,
      "Total": 2
    }
  },
  {
    "HostUID": "c3338a28-8590-48e6-9c53-77c4e15100dc",
    "Counter": {
      "StatusOk": 2,
      "StatusError": 0,
      "Total": 2
    }
  }
```

让我们用正常流量进行测试，并查看返回 HTTP 200 响应的实例：

```
echo "GET http://front.howto-k8s-outlier-detection:8080/color/get" | vegeta attack -duration=4s | tee results.bin | vegeta report

Requests      [total, rate, throughput]         200, 50.25, 50.23
Duration      [total, attack, wait]             3.982s, 3.98s, 1.628ms
Latencies     [min, mean, 50, 90, 95, 99, max]  1.59ms, 2.043ms, 1.93ms, 2.29ms, 2.464ms, 5.555ms, 12.771ms
Bytes In      [total, mean]                     1400, 7.00
Bytes Out     [total, mean]                     0, 0.00
Success       [ratio]                           100.00%
Status Codes  [code:count]                      200:200
Error Set:
```

![image-20210727213317132](https://pingfan.s3-us-west-2.amazonaws.com/pic2/zv8dv.png)

在`Status Codes`行，所有响应代码均为`200`。

让我们来看看统计数据。 注意所有后端的流量均匀分布，所有响应都显示`StatusOk`：

```json
curl front.howto-k8s-outlier-detection:8080/stats | jq .

[
  {
    "HostUID": "8f04b1c8-af29-4345-8a0d-34cb5c981e38",
    "Counter": {
      "StatusOk": 53,
      "StatusError": 0,
      "Total": 53
    }
  },
  {
    "HostUID": "34bb223d-1e6c-4423-898e-372d30a638b2",
    "Counter": {
      "StatusOk": 53,
      "StatusError": 0,
      "Total": 53
    }
  },
  {
    "HostUID": "c87a6e70-c9a2-4343-a453-81808bec9d2d",
    "Counter": {
      "StatusOk": 52,
      "StatusError": 0,
      "Total": 52
    }
  },
  {
    "HostUID": "c3338a28-8590-48e6-9c53-77c4e15100dc",
    "Counter": {
      "StatusOk": 52,
      "StatusError": 0,
      "Total": 52
    }
  }
]
```

让我们向其中一个后端注入故障：

```
curl -i front.howto-k8s-outlier-detection:8080/color/fault

host: 05114532-36bc-4b7f-927b-f16124974135 will now respond with 500 on /get.
```

![image-20210727213541616](https://pingfan.s3-us-west-2.amazonaws.com/pic2/bqeus.png)

主机 `05114532-36bc-4b7f-927b-f16124974135` 将返回 HTTP 500 ，我们将看到 App Mesh 如何根据 `colorapp`  Virtual node上的异常检测, 自动检测故障的主机并将其摘除。

让我们生成流量来进行验证：

```
echo "GET http://front.howto-k8s-outlier-detection:8080/color/get" | vegeta attack -duration=4s | tee results.bin | vegeta report

Requests      [total, rate, throughput]         200, 50.25, 48.97
Duration      [total, attack, wait]             3.982s, 3.98s, 2.281ms
Latencies     [min, mean, 50, 90, 95, 99, max]  1.649ms, 2.178ms, 2.062ms, 2.378ms, 2.467ms, 8.118ms, 12.213ms
Bytes In      [total, mean]                     1435, 7.17
Bytes Out     [total, mean]                     0, 0.00
Success       [ratio]                           97.50%
Status Codes  [code:count]                      200:195  500:5
Error Set:
500 Internal Server Error
```

![image-20210727213753364](https://pingfan.s3-us-west-2.amazonaws.com/pic2/d6xy7.png)

请注意，在 `Status Codes`行中有 5 个请求返回了 HTTP 500 响应。 App Mesh 应该检测到这个，并将主机摘除 10 秒。 在接下来的 10 秒内，您应该看到所有请求都返回 HTTP 200 响应，因为故障主机将不再提供流量。

让我们看一下统计数据来确认这一点：

```
curl front.howto-k8s-outlier-detection:8080/stats | jq .

[
  {
    "HostUID": "8f04b1c8-af29-4345-8a0d-34cb5c981e38",
    "Counter": {
      "StatusOk": 118,
      "StatusError": 0,
      "Total": 118
    }
  },
  {
    "HostUID": "34bb223d-1e6c-4423-898e-372d30a638b2",
    "Counter": {
      "StatusOk": 118,
      "StatusError": 0,
      "Total": 118
    }
  },
  {
    "HostUID": "c87a6e70-c9a2-4343-a453-81808bec9d2d",
    "Counter": {
      "StatusOk": 52,
      "StatusError": 5,
      "Total": 57
    }
  },
  {
    "HostUID": "c3338a28-8590-48e6-9c53-77c4e15100dc",
    "Counter": {
      "StatusOk": 117,
      "StatusError": 0,
      "Total": 117
    }
  }
]
```

请注意，主机 `c87a6e70-c9a2-4343-a453-81808bec9d2d` 返回了 5 个错误，并且没有流量发送到该主机。 所有流量都分布在其他三台主机。

如果我们在此主机被摘除期间发送更多流量，我们将看到所有请求都返回 HTTP 200 响应，因为只有健康的主机会提供流量：

```
echo "GET http://front.howto-k8s-outlier-detection:8080/color/get" | vegeta attack -duration=4s | tee results.bin | vegeta report

Requests      [total, rate, throughput]         200, 50.25, 50.23
Duration      [total, attack, wait]             3.982s, 3.98s, 1.945ms
Latencies     [min, mean, 50, 90, 95, 99, max]  1.605ms, 1.995ms, 1.962ms, 2.267ms, 2.318ms, 2.441ms, 5.114ms
Bytes In      [total, mean]                     1400, 7.00
Bytes Out     [total, mean]                     0, 0.00
Success       [ratio]                           100.00%
Status Codes  [code:count]                      200:200
Error Set:
```

上面的请求是在主机 `c87a6e70-c9a2-4343-a453-81808bec9d2d` 被摘除时发出的，我们得到了 100% 的成功响应。

等待摘除的持续时间（10s）过去后，再次产生流量进行测试。 将看到故障主机重新回到集群中，直到再次被摘除：

```
echo "GET http://front.howto-k8s-outlier-detection:8080/color/get" | vegeta attack -duration=4s | tee results.bin | vegeta report

Requests      [total, rate, throughput]         200, 50.25, 48.98
Duration      [total, attack, wait]             3.982s, 3.98s, 1.657ms
Latencies     [min, mean, 50, 90, 95, 99, max]  1.42ms, 1.794ms, 1.766ms, 1.969ms, 2.019ms, 2.78ms, 5.082ms
Bytes In      [total, mean]                     1435, 7.17
Bytes Out     [total, mean]                     0, 0.00
Success       [ratio]                           97.50%
Status Codes  [code:count]                      200:195  500:5
Error Set:
500 Internal Server Error
```



## 清理资源

```
kubectl delete -f _output/manifest.yaml
```

![image-20210727215315260](https://pingfan.s3-us-west-2.amazonaws.com/pic2/g0q2v.png)