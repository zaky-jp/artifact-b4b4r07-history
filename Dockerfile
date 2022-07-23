# syntax=docker/dockerfile:1
ARG GOLANG_VER='1.18'
FROM golang:${GOLANG_VER} AS go-builder

# artifact-specific configuration
ARG binary
ARG src_dir='upstream'

# prepare build deps
WORKDIR "/go/src/${binary}"
COPY "${src_dir}/go.mod" "${src_dir}/go.sum" ./
RUN \
  --mount=type=cache,target=/go/pkg/mod \
  go mod download && go mod verify
COPY "${src_dir}" .

# build per OS-arch variation
# TODO maybe convert this to makefile
ENV CGO_ENABLED=0
ENV GOOS='linux' GOARCH='arm64'
RUN \
  --mount=type=cache,target=/root/.cache/go-build \
  go build -v -ldflags '-s -w' -o "/go/bin/${binary}.${GOOS}-${GOARCH}"
ENV GOOS='linux' GOARCH='amd64'
RUN \
  --mount=type=cache,target=/root/.cache/go-build \
  go build -v -ldflags '-s -w' -o "/go/bin/${binary}.${GOOS}-${GOARCH}"
ENV GOOS='darwin' GOARCH='arm64'
RUN \
  --mount=type=cache,target=/root/.cache/go-build \
  go build -v -ldflags '-s -w' -o "/go/bin/${binary}.${GOOS}-${GOARCH}"
ENV GOOS='darwin' GOARCH='amd64'
RUN \
  --mount=type=cache,target=/root/.cache/go-build \
  go build -v -ldflags '-s -w' -o "/go/bin/${binary}.${GOOS}-${GOARCH}"

# package artifact
FROM ubuntu:jammy AS packager
ARG binary
WORKDIR "/source"

# linux
ENV GOOS='linux' GOARCH='arm64'
COPY --from=go-builder "/go/bin/${binary}.${GOOS}-${GOARCH}" "./${GOOS}/${GOARCH}/usr/bin/${binary}"
COPY "debian/control.${GOARCH}" "./${GOOS}/${GOARCH}/DEBIAN/control"
ENV GOOS='linux' GOARCH='amd64'
COPY --from=go-builder "/go/bin/${binary}.${GOOS}-${GOARCH}" "./${GOOS}/${GOARCH}/usr/bin/${binary}"
COPY "debian/control.${GOARCH}" "./${GOOS}/${GOARCH}/DEBIAN/control"

# macOS
ENV GOOS='darwin' GOARCH='arm64'
COPY --from=go-builder "/go/bin/${binary}.${GOOS}-${GOARCH}" "./${GOOS}/${GOARCH}/${binary}"
ENV GOOS='darwin' GOARCH='amd64'
COPY --from=go-builder "/go/bin/${binary}.${GOOS}-${GOARCH}" "./${GOOS}/${GOARCH}/${binary}"

# prep build environment
RUN \
  --mount=type=cache,target=/var/lib/apt/lists \
  --mount=type=cache,target=/var/cache/apt/archives \
  apt-get update -y\
  && apt-get install -y --no-install-recommends fakeroot xz-utils

# package files
WORKDIR "/artifact"
# fakeroot to mimic uid=0 gid=0
# linux
RUN fakeroot dpkg-deb --build /source/linux/arm64 ./ \
    && fakeroot dpkg-deb --build /source/linux/amd64 ./
# macOS
RUN tar -Jcf "./darwin-arm64-latest.tar.xz" -C "/source/darwin/arm64" . \
    && tar -Jcf "./darwin-amd64-latest.tar.xz" -C "/source/darwin/amd64" .

# serve
FROM nginx:stable
COPY --from=packager /artifact /artifact
COPY nginx.conf /etc/nginx/nginx.conf
