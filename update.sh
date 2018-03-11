#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

releasesPage="$(curl -fsSL 'https://www.ruby-lang.org/en/downloads/releases/')"
newsPage="$(curl -fsSL 'https://www.ruby-lang.org/en/news/')" # occasionally, releases don't show up on the Releases page (see https://github.com/ruby/www.ruby-lang.org/blob/master/_data/releases.yml)
# TODO consider parsing https://github.com/ruby/www.ruby-lang.org/blob/master/_data/downloads.yml as well

latest_gem_version() {
	curl -fsSL "https://rubygems.org/api/v1/gems/$1.json" | sed -r 's/^.*"version":"([^"]+)".*$/\1/'
}

rubygems="$(latest_gem_version rubygems-update)"
bundler="$(latest_gem_version bundler)"

travisEnv=
for version in "${versions[@]}"; do
	rcGrepV='-v'
	rcVersion="${version%-rc}"
	if [ "$rcVersion" != "$version" ]; then
		rcGrepV=
	fi

	IFS=$'\n'; allVersions=(
		$(curl -fsSL --compressed "https://cache.ruby-lang.org/pub/ruby/$rcVersion/" \
			| grep -E '<a href="ruby-'"$rcVersion"'.[^"]+\.tar\.xz' \
			| grep $rcGrepV -E 'preview|rc' \
			| sed -r 's!.*<a href="ruby-([^"]+)\.tar\.xz.*!\1!' \
			| sort -rV)
	); unset IFS

	fullVersion=
	shaVal=
	for tryVersion in "${allVersions[@]}"; do
		if \
			{
				versionReleasePage="$(echo "$releasesPage" | grep "<td>Ruby $tryVersion</td>" -A 2 | awk -F '"' '$1 == "<td><a href=" { print $2; exit }')" \
					&& [ "$versionReleasePage" ] \
					&& shaVal="$(curl -fsSL "https://www.ruby-lang.org/$versionReleasePage" |tac|tac| grep "ruby-$tryVersion.tar.xz" -A 5 | awk '/^SHA256:/ { print $2; exit }')" \
					&& [ "$shaVal" ]
			} \
			|| {
				versionReleasePage="$(echo "$newsPage" | grep -oE '<a href="[^"]+">Ruby '"$tryVersion"' Released</a>' | cut -d'"' -f2)" \
					&& [ "$versionReleasePage" ] \
					&& shaVal="$(curl -fsSL "https://www.ruby-lang.org/$versionReleasePage" |tac|tac| grep "ruby-$tryVersion.tar.xz" -A 5 | awk '/^SHA256:/ { print $2; exit }')" \
					&& [ "$shaVal" ]
			} \
		; then
			fullVersion="$tryVersion"
			break
		fi
	done

	if [ -z "$fullVersion" ]; then
		echo >&2 "warning: cannot determine sha for $version (tried all of ${allVersions[*]}); skipping"
		continue
	fi

	echo "$version: $fullVersion; rubygems $rubygems, bundler $bundler; $shaVal"

	for v in \
		alpine{3.4,3.6,3.7} \
		{jessie,stretch}{/slim,/onbuild,} \
	; do
		dir="$version/$v"
		variant="$(basename "$v")"

		[ -d "$dir" ] || continue

		case "$variant" in
			slim|onbuild|windowsservercore) template="$variant"; tag="$(basename "$(dirname "$dir")")" ;;
			alpine*) template='alpine'; tag="${variant#alpine}" ;;
			*) template='debian'; tag="$variant" ;;
		esac
		template="Dockerfile-${template}.template"

		sed -r \
			-e 's!%%VERSION%%!'"$version"'!g' \
			-e 's!%%FULL_VERSION%%!'"$fullVersion"'!g' \
			-e 's!%%SHA256%%!'"$shaVal"'!g' \
			-e 's!%%RUBYGEMS%%!'"$rubygems"'!g' \
			-e 's!%%BUNDLER%%!'"$bundler"'!g' \
			-e "$(
				if [ "$version" = 2.3 ] && [[ "$v" = stretch* ]]; then
					echo 's/libssl-dev/libssl1.0-dev/g'
				else
					echo '/libssl1.0-dev/d'
				fi
			)" \
			-e 's/^(FROM (debian|buildpack-deps|alpine)):.*/\1:'"$tag"'/' \
			"$template" > "$dir/Dockerfile"

		if [ "$variant" = 'alpine3.4' ]; then
			sed -ri -e 's/libressl/openssl/g' "$dir/Dockerfile"
		fi

		case "$v" in
			*/onbuild) ;;
			*)
				travisEnv='\n  - VERSION='"$version VARIANT=$v$travisEnv"
				;;
		esac
	done
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml
