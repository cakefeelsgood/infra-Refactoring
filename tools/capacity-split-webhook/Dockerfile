# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM golang:1.27 AS build
ARG TARGETARCH
WORKDIR /src
COPY go.mod ./
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w" -o /out/webhook .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/webhook /webhook
USER 65532:65532
EXPOSE 9443
ENTRYPOINT ["/webhook"]
