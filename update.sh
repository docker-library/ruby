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

travisEnv=
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
		' "$version"{/,/*/}Dockerfile
		sed -ri 's/^(FROM ruby):.*/\1:'"$version"'/' "$version/"*"/Dockerfile"
	)
	for variant in alpine slim; do
		[ -d "$version/$variant" ] || continue
		travisEnv='\n  - VERSION='"$version VARIANT=$variant$travisEnv"
	done
	travisEnv='\n  - VERSION='"$version VARIANT=$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml
