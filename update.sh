#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )
shaPage=$(curl -fsSL 'https://www.ruby-lang.org/en/downloads/')

latest_gem_version() {
	curl -sSL "https://rubygems.org/api/v1/gems/$1.json" | sed -r 's/^.*"version":"([^"]+)".*$/\1/'
}

rubygems="$(latest_gem_version rubygems-update)"
bundler="$(latest_gem_version bundler)"

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
			s/^(ENV RUBYGEMS_VERSION) .*/\1 '"$rubygems"'/;
		' "$version/"{,slim/}Dockerfile
		sed -ri 's/^(FROM ruby):.*/\1:'"$version"'/' "$version/"*"/Dockerfile"
	)
done
