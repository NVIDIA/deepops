#!/bin/bash
set -ex

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
IMAGE_LIST_FILE="${SCRIPT_DIR}/docker_image_list.txt"
IMAGES_DEST_DIR="${IMAGES_DEST_DIR:-/tmp/deepops/docker-images}"

if [ ! -d "${IMAGES_DEST_DIR}" ]; then
	mkdir -p "${IMAGES_DEST_DIR}"
fi

echo "Pulling Docker images from remote repo"
while IFS= read -r img
do
	docker pull "${img}"
done < "${IMAGE_LIST_FILE}"

echo "Saving Docker images to files"
while IFS= read -r img
do
	fixed_img_name="$(echo "${img}".tar | sed 's/[\/:]/-/g')"
	docker save -o "${IMAGES_DEST_DIR}/${fixed_img_name}" "${img}"
done < "${IMAGE_LIST_FILE}"
