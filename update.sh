#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

for version in "${versions[@]}"; do
	fullVersion="$(curl -sSL "http://cache.ruby-lang.org/pub/ruby/$version/" \
		| grep -E '<a href="ruby-'"$version"'.[^"]+\.tar\.bz2' \
		| grep -vE 'preview|rc' \
		| sed -r 's!.*<a href="ruby-([^"]+)\.tar\.bz2.*!\1!' \
		| sort -V | tail -1)"
	(
		set -x
		sed -ri 's/^(ENV RUBY_MAJOR) .*/\1 '"$version"'/' "$version/Dockerfile"
		sed -ri 's/^(ENV RUBY_VERSION) .*/\1 '"$fullVersion"'/' "$version/Dockerfile"
		sed -ri 's/^(FROM ruby):.*/\1:'"$fullVersion"'/' "$version/"*"/Dockerfile"
	)
done
