FROM golang:1 AS builder

# Use the default go proxy
ARG GO_PROXY=https://goproxy.io

WORKDIR /go/src/github.com/aws/github.com/aws-samples/app-mesh-workshop-greater-china/howto-http2/color_client

# Set the proxies for the go compiler.
ENV GOPROXY=$GO_PROXY

# go.mod and go.sum go into their own layers.
# This ensures `go mod download` happens only when go.mod and go.sum change.
COPY go.mod .
COPY go.sum .
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix nocgo -o /color_client .

FROM amazonlinux:2
RUN yum install -y ca-certificates
COPY --from=builder /color_client /color_client

ENTRYPOINT ["/color_client"]
