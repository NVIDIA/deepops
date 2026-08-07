# Mirror Docker Images

Setting up an offline mirror for Docker container images

- [Mirror Docker Images](#mirror-docker-images)
  - [Identifying images to mirror](#identifying-images-to-mirror)
  - [Downloading images with Skopeo](#downloading-images-with-skopeo)
  - [Downloading container images with Docker](#downloading-container-images-with-docker)
  - [Transferring images to offline network](#transferring-images-to-offline-network)
  - [Set up a container registry on the offline network](#set-up-a-container-registry-on-the-offline-network)
  - [Configuring your hosts to use the offline container
    registry](#configuring-your-hosts-to-use-the-offline-container-registry)
  - [Loading images into the container registry](#loading-images-into-the-container-registry)

## Identifying images to mirror

To identify which container images you need, we recommend configuring a server
for your workload in an environment with Internet access.
Then determine the list of images by:

- If using Docker: run `docker images` on each host
- If using Singularity: check your history of `singularity` commands to identify
  which containers you used
- If using Pyxis/Enroot with Slurm: check your `slurmd` logs for a list of images
  downloaded by Pyxis

## Downloading images with Skopeo

For a repeatable mirror, use [Skopeo](https://github.com/podman-container-tools/skopeo).
It copies images without a Docker daemon and can preserve the complete image
index, including every platform in a multi-architecture image. Select exact
image tags in the
[NGC Catalog](https://catalog.ngc.nvidia.com/) or with the
[NGC CLI](https://docs.nvidia.com/ngc/latest/ngc-catalog-user-guide.html#introduction-to-the-ngc-catalog-and-ngc-clis);
do not mirror a mutable `latest` tag.

Install Skopeo by following its
[installation guide](https://github.com/podman-container-tools/skopeo/blob/main/install.md).
In local testing with Skopeo 1.22.2, a direct copy of a Docker-media-type
multi-architecture index to either `oci-archive:` or `oci:` could not preserve
the source digest, even with `--preserve-digests`: conversion to an OCI index
would change the manifest-list digest. This limitation is scoped to Skopeo
1.22.2 and that source-media-type/OCI-transport combination; do not assume that
it applies to other versions or image formats. The workflow below instead uses
the `dir:` transport, which stores the original manifest bytes without that
conversion, verifies the copied digest, and archives the directory with `tar`.

The following example authenticates to NGC without putting the API key in a
command argument, resolves the requested tag to an immutable digest, preserves
the complete image index in an exact manifest directory, and creates a
checksummed archive for transfer:

```bash
(
set -euo pipefail
umask 077

SOURCE_REPOSITORY="nvcr.io/nvidia/cuda"
SOURCE_TAG="12.4.1-base-ubuntu22.04"
IMAGE_NAME="nvidia-cuda-${SOURCE_TAG}"
TRANSFER_ROOT="/tmp/images"
WORK_DIR="$(mktemp -d)"
IMAGE_DIR="${WORK_DIR}/${IMAGE_NAME}"
ARCHIVE="${TRANSFER_ROOT}/${IMAGE_NAME}.tar"
NGC_AUTH_FILE="${WORK_DIR}/auth.json"

mkdir -p "${TRANSFER_ROOT}"

cleanup_mirror_workdir() {
    find "${WORK_DIR}" -mindepth 1 -delete
    rmdir "${WORK_DIR}"
}
trap cleanup_mirror_workdir EXIT

skopeo login \
    --authfile "${NGC_AUTH_FILE}" \
    --username '$oauthtoken' \
    nvcr.io

SOURCE_DIGEST="$(
    skopeo inspect \
        --authfile "${NGC_AUTH_FILE}" \
        --format '{{.Digest}}' \
        "docker://${SOURCE_REPOSITORY}:${SOURCE_TAG}"
)"
printf '%s\n' "${SOURCE_DIGEST}" \
    > "${WORK_DIR}/${IMAGE_NAME}.source-digest"
printf '%s\n' "${SOURCE_DIGEST}" \
    > "/trusted/${IMAGE_NAME}.source-digest"

skopeo copy \
    --authfile "${NGC_AUTH_FILE}" \
    --all \
    --preserve-digests \
    "docker://${SOURCE_REPOSITORY}@${SOURCE_DIGEST}" \
    "dir:${IMAGE_DIR}"

test "${SOURCE_DIGEST}" = "$(
    skopeo inspect --format '{{.Digest}}' "dir:${IMAGE_DIR}"
)"

tar -C "${WORK_DIR}" -cf "${ARCHIVE}" \
    "${IMAGE_NAME}" \
    "${IMAGE_NAME}.source-digest"
(
    cd "${TRANSFER_ROOT}"
    sha256sum "${IMAGE_NAME}.tar" > "${IMAGE_NAME}.tar.sha256"
    cp "${IMAGE_NAME}.tar.sha256" "/trusted/${IMAGE_NAME}.tar.sha256"
)
)
```

The exact manifest directory plus ordinary tar archive is intentional. A
successful archive checksum proves only that the transferred archive is intact;
it does not prove that the image kept its registry identity. Do not accept the
mirror until the import procedure below copies it to the offline registry and
confirms that the destination digest exactly equals the recorded source digest.
Repeat this process for every exact image tag. For larger, explicit image lists,
see
[`skopeo sync`](https://github.com/podman-container-tools/skopeo/blob/main/docs/skopeo-sync.1.md);
use an auth file and do not store credentials in its YAML source file.

## Downloading container images with Docker

Docker `pull` and `save` remain a useful single-platform fallback. Unlike the
Skopeo example above, this path saves only the platform pulled into the local
Docker image store.

On a machine with Internet access, install Docker manually or with DeepOps:

```bash
ansible-playbook playbooks/container/docker.yml
```

For an NGC image, log in without putting the API key in the command line, pull
the image, and save it to a local file:

```bash
(
set -euo pipefail
umask 077

DOCKER_AUTH_DIR="$(mktemp -d)"
cleanup_docker_auth() {
    find "${DOCKER_AUTH_DIR}" -mindepth 1 -delete
    rmdir "${DOCKER_AUTH_DIR}"
}
trap cleanup_docker_auth EXIT
export DOCKER_CONFIG="${DOCKER_AUTH_DIR}"

mkdir -p /tmp/images
docker login nvcr.io --username '$oauthtoken'

docker pull nvcr.io/nvidia/cuda:12.4.1-base-ubuntu22.04
docker save \
    -o /tmp/images/nvidia-cuda-12.4.1-base-ubuntu22.04.tar \
    nvcr.io/nvidia/cuda:12.4.1-base-ubuntu22.04
docker logout nvcr.io
(
    cd /tmp/images
    sha256sum nvidia-cuda-12.4.1-base-ubuntu22.04.tar \
        > nvidia-cuda-12.4.1-base-ubuntu22.04.tar.sha256
)
)
```

Additionally, download and save the
[`registry` image](https://hub.docker.com/_/registry) so that you can deploy a
local registry on the offline network. Docker saves only the platform pulled
for the connected staging host, so the staging host and offline registry host
must use the same CPU architecture for this fallback. For a different target
architecture, use an architecture-matched staging host or mirror the registry
image with the multi-architecture Skopeo `dir:` workflow above. Resolve and
record the registry image digest independently before transfer:

```bash
REGISTRY_SOURCE="docker.io/library/registry:3.1.1"
REGISTRY_DIGEST="$(skopeo inspect --format '{{.Digest}}' "docker://${REGISTRY_SOURCE}")"
printf '%s\n' "${REGISTRY_DIGEST}" > /trusted/registry-3.1.1.source-digest

docker pull "registry@${REGISTRY_DIGEST}"
docker save -o /tmp/images/registry-3.1.1.tar "registry@${REGISTRY_DIGEST}"
(
    set -euo pipefail
    cd /tmp/images
    sha256sum registry-3.1.1.tar > registry-3.1.1.tar.sha256
    cp registry-3.1.1.tar.sha256 /trusted/registry-3.1.1.tar.sha256
)
```

Retain `/trusted/registry-3.1.1.tar.sha256` and the recorded source digest in a
separate trusted system or signed manifest. The checksum copy carried on the
same removable media detects accidental corruption but does not prove
authenticity if that media is replaced.

## Transferring images to offline network

After downloading the container images, transfer the downloaded files to your
offline network.

There are many ways to do this, depending on your local setup!
Use the mechanism that gives you the best performance and ease-of-use in your
environment.

One common method is to bundle the downloaded files into an ISO file. Container
archives often exceed 4 GiB, so use
[`genisoimage` ISO level 3](https://manpages.ubuntu.com/manpages/noble/man1/genisoimage.1.html)
and Rock Ridge. List the archives and checksums explicitly so temporary
unpacked image directories or unrelated files are not included:

```bash
(
set -euo pipefail
umask 077

# Install the ISO tool separately, then run the remaining commands unprivileged.
sudo apt install genisoimage
TRANSFER_ROOT="/tmp/images"
CUDA_NAME="nvidia-cuda-12.4.1-base-ubuntu22.04"
REGISTRY_NAME="registry-3.1.1"
ISO_STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/deepops-image-iso.XXXXXX")"
chmod 0700 "${ISO_STAGING_DIR}"
genisoimage \
    -iso-level 3 \
    -R \
    -graft-points \
    -o "${ISO_STAGING_DIR}/images.iso" \
    "${CUDA_NAME}.tar=${TRANSFER_ROOT}/${CUDA_NAME}.tar" \
    "${CUDA_NAME}.tar.sha256=${TRANSFER_ROOT}/${CUDA_NAME}.tar.sha256" \
    "${REGISTRY_NAME}.tar=${TRANSFER_ROOT}/${REGISTRY_NAME}.tar" \
    "${REGISTRY_NAME}.tar.sha256=${TRANSFER_ROOT}/${REGISTRY_NAME}.tar.sha256"
printf 'ISO written to %s\n' "${ISO_STAGING_DIR}/images.iso"
)
```

Add each additional image archive and checksum to this explicit list. Before
transfer, verify that the output filesystem and media can hold both the total
ISO and its largest individual archive. FAT32 media cannot store files larger
than 4 GiB. Keep ISO creation unprivileged and keep the ISO in the private
mode-0700 staging directory until it is transferred.

## Set up a container registry on the offline network

Once the container images have been transferred to the offline network, push
them to a container registry for use on your offline cluster. Your offline
environment may already have a registry, and there are many free and commercial
solutions for running one.

If you don't already have a container registry, the official
[Docker Registry](https://hub.docker.com/_/registry) image can provide an
isolated test registry.

First, in the offline network, pick a host to use as your container registry.
We assume this host already has Docker installed and can run containers which
expose ports to the offline network. We also assume that the `registry` image
was included when you transferred container images from the Internet-connected
machine.

Load the registry image into the Docker image cache of your container registry
host:

```bash
(
set -euo pipefail
cd /tmp/images
sha256sum --check /trusted/registry-3.1.1.tar.sha256
EXPECTED_REGISTRY_DIGEST="$(cat /trusted/registry-3.1.1.source-digest)"
docker load -i registry-3.1.1.tar
LOADED_REGISTRY_ID="$(docker image inspect --format '{{.Id}}' "registry@${EXPECTED_REGISTRY_DIGEST}")"
test -n "${LOADED_REGISTRY_ID}"
)
```

`/trusted/registry-3.1.1.source-digest` represents the separately retained or
signed digest record from the connected side; do not source it from the same
untrusted transfer media as the archive.

Then create a Docker volume to store your container images:

```bash
docker volume create registry-images
```

The following command is for isolated testing on the registry host only. It
binds the unauthenticated HTTP endpoint to loopback so other hosts cannot reach
it:

```bash
docker run -d \
    -p 127.0.0.1:5000:5000 \
    --restart=always \
    --name registry \
    -v registry-images:/var/lib/registry \
    registry:3.1.1
```

Before binding the registry to a network-reachable address, follow the
[official deployment guide](https://distribution.github.io/distribution/about/deploying/)
to configure both TLS and access control. Do not expose the test configuration
on a shared or untrusted network.

Before loading application images, complete the registry handoff and require all
of these checks:

- bind the registry to its intended network address;
- configure TLS and access control, and install the registry CA on clients;
- verify `curl --fail --cacert <ca-file> https://registry-host:5000/v2/`
  succeeds from every provisioning/cluster network that must pull images;
- verify an authenticated test push and pull from a non-registry host.

Do not configure cluster hosts for `registry-host:5000` until this checklist
passes.

## Configuring your hosts to use the offline container registry

By default, Docker requires connections to a container registry to use TLS. If
you can set up a trusted TLS certificate in your offline environment, follow
the [Distribution TLS instructions](https://distribution.github.io/distribution/about/deploying/#get-a-certificate).

If you do not have a TLS certificate, or you want to test first without one,
you can configure Docker to treat your registry as insecure. Follow the
[Docker Engine insecure-registry documentation](https://docs.docker.com/reference/cli/dockerd/#insecure-registries),
or, if you installed Docker with DeepOps, configure the list in your DeepOps
configuration:

```bash
docker_insecure_registries:
- "registry-host:5000"
```

## Loading images into the container registry

Once your registry is running and you've configured your hosts to access it,
verify the transferred archive and copy it into the registry. Skopeo verifies
TLS by default. The following production-oriented example prompts for the
registry credentials and keeps them in the same temporary directory as the
extracted image so an exit or interruption removes both:

```bash
(
set -euo pipefail
umask 077

SOURCE_TAG="12.4.1-base-ubuntu22.04"
IMAGE_NAME="nvidia-cuda-${SOURCE_TAG}"
TRANSFER_ROOT="/tmp/images"
IMPORT_ROOT="$(mktemp -d)"
IMAGE_DIR="${IMPORT_ROOT}/${IMAGE_NAME}"
DESTINATION_REGISTRY="registry-host:5000"
DESTINATION_IMAGE="${DESTINATION_REGISTRY}/nvidia/cuda:${SOURCE_TAG}"
DESTINATION_AUTH_FILE="${IMPORT_ROOT}/auth.json"

cleanup_import_root() {
    find "${IMPORT_ROOT}" -mindepth 1 -delete
    rmdir "${IMPORT_ROOT}"
}
trap cleanup_import_root EXIT

cd "${TRANSFER_ROOT}"
sha256sum --check "/trusted/${IMAGE_NAME}.tar.sha256"
test ! -e "${IMAGE_DIR}"
tar --no-same-owner --no-same-permissions \
    -C "${IMPORT_ROOT}" \
    -xf "${IMAGE_NAME}.tar"
test -f "${IMAGE_DIR}/manifest.json"

skopeo login \
    --authfile "${DESTINATION_AUTH_FILE}" \
    "${DESTINATION_REGISTRY}"

SOURCE_DIGEST="$(cat /trusted/${IMAGE_NAME}.source-digest)"
test "${SOURCE_DIGEST}" = "$(
    skopeo inspect \
        --format '{{.Digest}}' \
        "dir:${IMAGE_DIR}"
)"
skopeo copy \
    --all \
    --preserve-digests \
    --dest-authfile "${DESTINATION_AUTH_FILE}" \
    "dir:${IMAGE_DIR}" \
    "docker://${DESTINATION_IMAGE}"

DESTINATION_DIGEST="$(
    skopeo inspect \
        --authfile "${DESTINATION_AUTH_FILE}" \
        --format '{{.Digest}}' \
        "docker://${DESTINATION_IMAGE}"
)"
test "${SOURCE_DIGEST}" = "${DESTINATION_DIGEST}"
)
```

The final equality test is the required round-trip acceptance gate. Treat a
mismatch as a failed mirror even if the archive checksum passed and the copy
command reported success.

For the production path, `/trusted/${IMAGE_NAME}.tar.sha256` and
`/trusted/${IMAGE_NAME}.source-digest` are the separately retained or signed
records from the connected side. Do not source either trust anchor from the
same removable media as the archive.

For the loopback-only, unauthenticated test registry above, omit `skopeo login`
and both auth-file options, use `localhost:5000` as the destination, add
`--dest-tls-verify=false` to `skopeo copy`, and add `--tls-verify=false` to
`skopeo inspect`. Do not disable TLS verification for a production registry.

Images saved with the Docker fallback can still be loaded, tagged, and pushed
with Docker:

```bash
(
set -euo pipefail
cd /tmp/images
sha256sum --check nvidia-cuda-12.4.1-base-ubuntu22.04.tar.sha256
docker load -i /tmp/images/nvidia-cuda-12.4.1-base-ubuntu22.04.tar
docker tag nvcr.io/nvidia/cuda:12.4.1-base-ubuntu22.04 registry-host:5000/nvidia/cuda:12.4.1-base-ubuntu22.04
docker push registry-host:5000/nvidia/cuda:12.4.1-base-ubuntu22.04
)
```
