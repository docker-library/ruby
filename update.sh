#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )
shaPage=$(curl -fsSL 'https://www.ruby-lang.org/en/downloads/')

bundler="$(curl -sSL 'https://rubygems.org/api/v1/gems/bundler.json' | sed -r 's/^.*"version":"([^"]+)".*$/\1/')"

for version in "${versions[@]}"; do
	fullVersion="$(curl -sSL --compressed "http://cache.ruby-lang.org/pub/ruby/$version/" \
		| grep -E '<a href="ruby-'"$version"'.[^"]+\.tar\.bz2' \
		| grep -vE 'preview|rc' \
		| sed -r 's!.*<a href="ruby-([^"]+)\.tar\.bz2.*!\1!' \
		| sort -V | tail -1)"
	shaVal="$(echo $shaPage | sed -r "s/.*Ruby ${fullVersion}<\/a><br \/> sha256: ([^<]+).*/\1/")"
	(
		set -x
		sed -ri '
			s/^(ENV RUBY_MAJOR) .*/\1 '"$version"'/;
			s/^(ENV RUBY_VERSION) .*/\1 '"$fullVersion"'/;
			s/^(ENV RUBY_DOWNLOAD_SHA256) .*/\1 '"$shaVal"'/;
			s/^(ENV BUNDLER_VERSION) .*/\1 '"$bundler"'/;
		' "$version/"{,slim/}Dockerfile
		sed -ri 's/^(FROM ruby):.*/\1:'"$fullVersion"'/' "$version/"*"/Dockerfile"
	)
done
