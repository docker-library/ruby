#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

curl -s "https://www.ruby-lang.org/en/downloads/" | tr -d "\r\n\t" > shafile.html

for version in "${versions[@]}"; do
	shaVal="$(sed -r "s/^.*Ruby ${fullVersion}.*sha256: ([^<]+).*/\1/" shafile.html)"
	fullVersion="$(curl -sSL --compressed "http://cache.ruby-lang.org/pub/ruby/$version/" \
		| grep -E '<a href="ruby-'"$version"'.[^"]+\.tar\.bz2' \
		| grep -vE 'preview|rc' \
		| sed -r 's!.*<a href="ruby-([^"]+)\.tar\.bz2.*!\1!' \
		| sort -V | tail -1)"
	(
		set -x
		sed -ri 's/^(ENV RUBY_MAJOR) .*/\1 '"$version"'/' "$version/"{,wheezy/,slim/}Dockerfile
		sed -ri 's/^(ENV RUBY_VERSION) .*/\1 '"$fullVersion"'/' "$version/"{,wheezy/,slim/}Dockerfile
		sed -ri 's/^(ENV RUBY_DOWNLOAD_SHA256) .*/\1 '"$shaVal"'/' "$version/"{,wheezy/,slim/}Dockerfile
		sed -ri 's/^(FROM ruby):.*/\1:'"$fullVersion"'/' "$version/"*"/Dockerfile"
	)
done
