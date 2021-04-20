#!/usr/bin/env bash

cd "$(dirname "${BASH_SOURCE[0]}")"
mkdir -p bin

version="0.2.2"
os="$(uname -s)"
arch="$(uname -m)"

download_base="https://github.com/dradtke/vim-dap/releases/download/v${version}"

case "${os}-${arch}" in
	Linux-x86_64)
		wget -O bin/console "${download_base}/console-linux-amd64"
		chmod +x bin/console
		;;

	*)
		# TODO: allow it to always be built from source
		if command -v go >/dev/null; then
			echo "Prebuilt binary not found for ${os}-${arch}, building from source..."
			make console
		else
			echo "Prebuilt binary not found for ${os}-${arch}, and no Go compiler found. Exiting."
			exit 1
		fi
		;;
esac
