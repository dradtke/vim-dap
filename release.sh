#!/usr/bin/env sh

if ! command -v go >/dev/null; then
	echo "go not found, can't create a release"
	exit 1
fi

eval "$(go env)"
echo "Building debug console binary for ${GOOS}/${GOARCH}..."
binary_name="console-${GOOS}-${GOARCH}"

mkdir -p bin
(cd console && go build -o "../bin/${binary_name}")

echo ""
echo "Binaries available in bin/"
