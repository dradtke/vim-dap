#!/usr/bin/env sh

mkdir -p bin

version="0.0.1"
os="$(uname -s)"
arch="$(uname -m)"

download_base="https://github.com/dradtke/vim-dap/releases/download/v${version}"

case "${os}-${arch}" in
	Linux-x86_64)
		wget -O bin/console "${download_base}/console-linux-amd64"
		chmod +x bin/console
		;;

	*)
		echo "OS-arch pair not supported: ${os}-${arch}"
		exit 1
		;;
esac
