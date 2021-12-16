## 总览
本实验会展示了如何使用 App Mesh 配置 Kubernetes 应用程序的重试策略（retry-policy）。

### Color
如果在请求中设置了statuscode-header，Color app的返回中可以带有可配置的错误状态码。这样我们就能够在应用重试策略（retry-policy）时验证重试行为。

### Front
Front app 充当远程调用 colorapp 的网关. Front app 有一个单独的 deployment，其中的 Pods 已经作为虚拟节点（virtual-node）：**front** 注册到了服务网格。 这个虚拟节点（virtual-node） 使用虚拟服务（virtual-service）：**colorapp** 作为后端.

## 前提条件
1. [Walkthrough: App Mesh with EKS](../eks/)

2. v1beta2 示例 manifest 需要 [aws-app-mesh-controller-for-k8s](https://github.com/aws/aws-app-mesh-controller-for-k8s) 版本 [>=v1.0.0](https://github.com/aws/aws-app-mesh-controller-for-k8s/releases/tag/v1.0.0). 运行下面的命令去检查你运行的controller版本.
```
$ kubectl get deployment -n appmesh-system appmesh-controller -o json | jq -r ".spec.template.spec.containers[].image" | cut -f2 -d ':'|tail -n1
```

你可以使用 v1beta1 示例 manifest，如果你 [aws-app-mesh-controller-for-k8s](https://github.com/aws/aws-app-mesh-controller-for-k8s) 版本是 [v0.3.0](https://github.com/aws/aws-app-mesh-controller-for-k8s/blob/legacy-controller/CHANGELOG.md)

3. 安装Docker，示例需要构建演示应用的Docker image。

## 部署

1. 克隆此仓库，然后进入`howto-k8s-retry-policy`文件夹，所有的命令都是在此文件夹下运行。
2. **你的** account id:
    ```
    export AWS_ACCOUNT_ID=<your_account_id>
    ```
3. **Region** e.g. cn-northwest-1
    ```
    export AWS_DEFAULT_REGION=cn-northwest-1
    ```
4. **(可选项) 指定 Envoy Image 版本** 如果要使用与[默认版本](https://github.com/aws/eks-charts/tree/master/stable/appmesh-controller#configuration)不同的Envoy 容器镜像，运行 `helm upgrade` 去覆盖 `sidecar.image.repository` 和 `sidecar.image.tag` 字段。
5. 部署
    ```.
    ./deploy.sh
    ```

## 验证
1. 端口转发（Port-forward） front pod
   ```
   kubectl get pod -n howto-k8s-retry-policy
   NAME                     READY   STATUS    RESTARTS   AGE
   blue-55d5bf6bb9-4n7hc    3/3     Running   0          11s
   front-5dbdcbc896-l8bnz   3/3     Running   0          11s
   ...

   kubectl -n howto-k8s-retry-policy port-forward deployment/front 8080:8080
   ```

2. 打开一个新的终端创口。 使用 curl 命令发送大量请求到 front app 服务. 您应该看到几乎相等数量的200（OK）和503（Server Error）响应。
    ```
    while true; do curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 ; sleep 0.5; echo ; done
    ```

3. 返回原始终端创口, 在 ./v1beta2/manifest.yaml.template（如果 aws-app-mesh-controller-for-k8s 版本是 v0.3.0，则修改./v1beta1/manifest.yaml.template）中取消 retryPolicy 的注释，然后运行 `./deploy.sh`
    请注意缩进，retryPolicy 应与 action 对齐
   ```
      # UNCOMMENT below to enable retries
        retryPolicy:
          maxRetries: 4
          perRetryTimeoutMillis: 2000
          httpRetryEvents:
            - server-error
   ```

4. 依赖于新添加的重试策略（retry-policy）你应该会看到更多的 200(OK) 响应.

可以前往[envoy 重试](https://www.envoyproxy.io/docs/envoy/v1.8.0/api-v1/route_config/route#config-http-conn-man-route-table-route-retry)获取更多的细节关于 Envoy 是如何进行重试的.

## 默认重试策略
如果未在虚拟路由上设置重试策略，App Mesh为客户提供默认的重试策略。但是，当前这并不适用于所有场景。如果您当前无法使用默认重试策略，则您将无法运行此后续部分，而可以跳过此部分。 要了解有关默认重试策略的更多信息，可以在这里阅读：[envoy 默认重试策略](https://docs.aws.amazon.com/app-mesh/latest/userguide/envoy.html#default-retry-policy)

1. 再次更改配置文件重新注释掉重试策略（retry-policy），使默认重试策略（default retry policy）生效。可以通过注释或删除相关配置，使路由配置文件中不再包含重试相关配置项。然后再次运行`./deploy.sh`使其生效:
   ```
      # COMMENT back out or remove below to disable explicit retries
        retryPolicy:
          maxRetries: 4
          perRetryTimeoutMillis: 2000
          httpRetryEvents:
            - server-error
   ```
2. 在一个单独的终端窗口中，再次发送请求到 front 服务，我们可以再次观察到有些请求返回了503。
    ```
    while true; do curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 ; sleep 0.5; echo ; done
    ```

3. 为了更好地了解默认的重试策略，让我们降低应用程序的错误概率。 目前，在50％的错误概率下，对于某些请求，我们很可能会用尽所有重试，导致503s退回。 让我们通过将文件顶部的错误概率变量从50％更改为10%，将colorapp文件夹中的serve.py更改为50％到10％。

    ```
    # Change this value to 10
    FAULT_RATE = 50
    ```

4. 我们可以通过运行以下命令来重新部署应用程序，立刻应用此新的错误概率变量。
    ```
    REDEPLOY=true ./deploy.sh
    ```


5. 现在，让我们再次将请求发送到 front 服务，应该可以观察到我们几乎200个请求中有10％失败了。
    ```
    while true; do curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 ; sleep 0.5; echo ; done
    ```

App Mesh默认重试策略（retry-policy）可以在某些情况下帮助防止请求失败。 但是，在某些情况下，您可能需要根据应用程序和场景额外设置重试策略（retry-policy）。 要详细了解我们对重试策略（retry-policy）提出的建议，可以在此处阅读更多内容：[AWS 重试策略最佳实践](https://docs.aws.amazon.com/app-mesh/latest/userguide/best-practices.html#route-retries)