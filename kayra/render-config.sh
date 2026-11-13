#!/bin/sh
# Renders the dev configuration: generates one RSA key per local signing
# key and writes it, indented as a YAML block scalar, in place of its
# placeholder.
#
#   render-config.sh <template> <output>
set -eu

template=$1
output=$2
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cp "$template" "$work/config"
for name in SELF LOCAL; do
	openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$work/$name.pem" 2>/dev/null
	awk -v placeholder="__${name}_KEY__" -v keyfile="$work/$name.pem" '
		$0 == placeholder { while ((getline line < keyfile) > 0) print "          " line; next }
		{ print }
	' "$work/config" > "$work/next"
	mv "$work/next" "$work/config"
done
if grep -qx '__[A-Z]*_KEY__' "$work/config"; then
	echo "render-config: a key placeholder is left in $template" >&2
	exit 1
fi
install -D -m 0640 "$work/config" "$output"
